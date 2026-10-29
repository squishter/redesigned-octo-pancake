class_name SlotPacker
extends RefCounted
## Packs gem slots into the regions of a RegionMap as orderly patterns, the
## way gem-art pictures are laid out: rows of stones that follow a region's
## outline, a big center stone ringed by smaller ones, honeycombs, chains of
## stones that shrink toward a petal's tip.
##
## Every slot is treated as a capsule for collisions: a segment of half-length
## h along its rotation, grown by radius r. A round stone has h = 0; a marquise
## or baguette has h > 0. A "free" field holds, for every pixel, how far it is
## from the region's edge and from every slot placed so far, so each stone a
## pattern asks for shrinks to whatever room is left there (and is skipped if
## that gets too small).
##
## Patterns are chosen per symmetry group, so symmetric copies match.
##
## The peak search uses per-block maxima (BLOCK x BLOCK px) that are refreshed
## only where slots changed the field.

const BLOCK := 16

## Length / width of the elongated shapes. The rest are as wide as they are long.
const ASPECT := {"oval": 1.35, "teardrop": 1.5, "marquise": 2.0, "baguette": 2.4}

## Full patterns, picked per symmetry group from the region's size and shape:
## echo: rows of stones following the outline inward, like ripples
## halo: one or two outline rows around a big center stone
## rosette: a center stone ringed by outward teardrops, with outline rows
## honeycomb: an even lattice of stones lined up with the region's axis
## spine: a chain along the middle, each stone as big as fits (petals, thin bands)
## solitaire: one stone shaped to the region, small ones in the corners
## stripes: straight parallel rows across the region, in alternating tones
## sunburst: a center stone with spokes of stones growing outward
## pave: the old free-form packing of mixed sizes, kept for some variety
## Sparse fills, only used when asked for (see DesignPlan):
## scatter: an airy lattice of small stones
## accent: a single stone at the region's heart
## outline: only a row of small stones along the edge
## bare: no stones
const PATTERNS := ["echo", "halo", "rosette", "honeycomb", "spine", "solitaire", "stripes", "sunburst", "pave"]
const STYLES := PATTERNS + ["scatter", "accent", "outline", "bare"]
## Stone shapes for outline rows; elongated ones lie along the row.
const ROW_SHAPES := ["round", "round", "round", "hexagon", "square", "marquise", "oval"]
## How a pattern uses the region's accent color (slot "tone" 1):
## solid: none; rows: every other row; edge: the outermost row; heart: the
## center stone(s).
const TONINGS := ["solid", "rows", "edge", "heart"]
## Smallest stone scale at the picture's center when sizes shrink inward.
const RADIAL_MIN := 0.55

var map: RegionMap
var rng := RandomNumberGenerator.new()
var free := PackedFloat32Array()
var slots: Array[Dictionary] = []
## Base stone radius in px; every pattern's sizes are multiples of it.
var unit := 8.0
var gap := 2.0
var seed_value := 1
## Stones shrink toward the picture's center (to RADIAL_MIN at the center).
var radial_size := false
## Multi-pass designs: a few large stones first, then a few medium ones,
## then the group's pattern around them.
var tiers := false
var _pic_center := Vector2.ZERO
var _pic_reach := 1.0

var _bw := 0
var _bh := 0
var _block_max := PackedFloat32Array()
var _block_arg := PackedInt32Array()
var _block_dirty := PackedByteArray()
var _region := -1
var _region_blocks := Rect2i()
var _cur_max := 0.0
var _tone := 0
## Which step of the pattern is placing stones (a row, a ring, the center
## stone...). Counted from 0 in every region, so symmetric copies agree.
var _part := 0


## Packs every region. options:
##   seed (int), unit (base stone radius in px, default 1% of the picture),
##   gap (px between stones, default 0.3%),
##   groups (PackedInt32Array: symmetry group per region; copies share a pattern),
##   radial_size (bool): rows, lattices and spines shrink toward the picture's center,
##   tiers (bool): some groups first get a few large, then a few medium stones,
##   styles (Dictionary region id -> style, to force a style or sparse fill).
## Returns slots: {id, region, shape, x, y, rotation, size, width, tone, part},
## in px of the map; size is the length along the rotation, width across it;
## tone 1 marks stones in the region's accent color, tone 2 in its feature
## color (the big tier stones); part numbers the pattern's steps (each row,
## ring or tier), the same in symmetric copies.
## Also writes the chosen pattern into each region's dictionary ("style").
static func pack(region_map: RegionMap, options: Dictionary = {}) -> Array[Dictionary]:
	var p := SlotPacker.new()
	p._setup(region_map, options)
	var forced: Dictionary = options.get("styles", {})
	var groups: PackedInt32Array = options.get("groups", PackedInt32Array())
	var order := region_map.regions.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["area"] > b["area"])
	# Each group's pattern is designed on its biggest member (first in order).
	var designs := {}
	for region in order:
		var id: int = region["id"]
		var g: int = groups[id] if id < groups.size() else -1 - id
		if not designs.has(g):
			designs[g] = p._design(region, forced.get(id, ""), g)
		p._pack_region(region, designs[g])
	return p.slots


func _setup(region_map: RegionMap, options: Dictionary) -> void:
	var side := float(mini(region_map.width, region_map.height))
	map = region_map
	seed_value = options.get("seed", 1)
	rng.seed = seed_value
	unit = options.get("unit", side * 0.010)
	gap = options.get("gap", side * 0.003)
	radial_size = options.get("radial_size", false)
	tiers = options.get("tiers", false)
	_pic_center = Vector2(region_map.width, region_map.height) / 2.0
	_pic_reach = side / 2.0
	free = region_map.dist.duplicate()
	_bw = ceili(region_map.width / float(BLOCK))
	_bh = ceili(region_map.height / float(BLOCK))
	_block_max.resize(_bw * _bh)
	_block_arg.resize(_bw * _bh)
	_block_dirty.resize(_bw * _bh)


## Picks a pattern and its parameters for a group from its biggest region.
func _design(region: Dictionary, forced_style: String, group: int) -> Dictionary:
	var g_rng := RandomNumberGenerator.new()
	g_rng.seed = hash([seed_value, group, "pattern"])
	var u := unit
	var max_d: float = region["max_dist"]
	var compact: float = region["area"] / (PI * max_d * max_d)
	var style := forced_style
	if not style in STYLES:
		if max_d < u * 1.1:
			style = "spine"
		elif compact > 4.0 and max_d < u * 3.0:
			style = "spine" if g_rng.randf() < 0.45 else "echo"
		elif max_d < u * 2.4:
			style = _pick({"solitaire": 0.55, "echo": 0.3, "spine": 0.15}, g_rng)
		elif max_d < u * 4.0:
			style = _pick({"halo": 0.3, "echo": 0.3, "solitaire": 0.1, "rosette": 0.1, "stripes": 0.1,
					"pave": 0.1}, g_rng)
		else:
			var weights := {"echo": 0.3, "halo": 0.1, "honeycomb": 0.2, "stripes": 0.15, "pave": 0.1}
			if compact < 2.6:
				weights["rosette"] = 0.12
				weights["sunburst"] = 0.15
			style = _pick(weights, g_rng)
	var row_r: float = u * [0.7, 0.85, 1.0, 1.15][g_rng.randi_range(0, 3)]
	# Shallow regions take smaller rows so at least two fit across.
	row_r = minf(row_r, maxf(u * 0.5, (max_d - gap * 2.0) / 2.0))
	var shape: String = ROW_SHAPES[g_rng.randi_range(0, ROW_SHAPES.size() - 1)]
	if style == "honeycomb":
		shape = "hexagon" if g_rng.randf() < 0.4 else "round"
	return {
		"style": style,
		"row_r": row_r,
		"row_shape": shape,
		# Every other row smaller, like alternating bead sizes.
		"alternate": style == "echo" and g_rng.randf() < 0.3,
		"toning": TONINGS[g_rng.randi_range(0, TONINGS.size() - 1)],
		"halo_rows": 1 if g_rng.randf() < 0.6 else 2,
		"edge_row": g_rng.randf() < 0.5,
		"lattice_turn": g_rng.randf() * PI / 3.0 if g_rng.randf() < 0.3 else 0.0,
		# Size change per row inward (echo, stripes outward from the middle):
		# below 1 the stones shrink toward the middle, above 1 they grow.
		"grade": [1.0, 1.0, 0.85, 1.15][g_rng.randi_range(0, 3)],
		# Honeycomb stones shrink toward the edge, like a halftone.
		"gradient": g_rng.randf() < 0.35,
		"scatter_space": u * g_rng.randf_range(1.2, 2.0),
		# Tiers: big stones (radius) and how many medium ones go in first.
		"large": u * g_rng.randf_range(2.2, 3.2) if tiers and max_d > u * 2.6 and g_rng.randf() < 0.4 else 0.0,
		"mediums": g_rng.randi_range(1, 3) if tiers and max_d > u * 1.8 and g_rng.randf() < 0.45 else 0,
		"medium_r": u * g_rng.randf_range(1.2, 1.6),
		"tier_shape": ["round", "round", "hexagon", "square", "oval", "marquise"][g_rng.randi_range(0, 5)],
	}


static func _pick(weights: Dictionary, r: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var x := r.randf() * total
	for k in weights:
		x -= weights[k]
		if x <= 0.0:
			return k
	return weights.keys()[0]


func _pack_region(region: Dictionary, design: Dictionary) -> void:
	_region = region["id"]
	var bbox: Rect2i = region["bbox"]
	_region_blocks = Rect2i(bbox.position.x / BLOCK, bbox.position.y / BLOCK, 0, 0)
	_region_blocks.end = Vector2i((bbox.end.x - 1) / BLOCK + 1, (bbox.end.y - 1) / BLOCK + 1)
	for by in range(_region_blocks.position.y, _region_blocks.end.y):
		for bx in range(_region_blocks.position.x, _region_blocks.end.x):
			_block_dirty[by * _bw + bx] = 1
	_cur_max = region["max_dist"]
	_tone = 0
	_part = 0
	var style: String = design["style"]
	region["style"] = style
	var u := unit
	var r_row: float = design["row_r"]
	var toning: String = design["toning"]

	if tiers and style != "bare":
		_tier_stones(region, design)

	match style:
		"bare":
			return
		"outline":
			_rows(region, [u * 0.45], ["round"], [0])
		"accent":
			_center_stone(region, u * 2.2)
		"scatter":
			_lattice(region, u * 0.6, design["scatter_space"], "round", design["lattice_turn"], false)
		"echo":
			var radii := _graded_rows(region, r_row, design["grade"], design["alternate"])
			var n := radii.size()
			var shapes := []
			var tones := []
			for k in n:
				var small: bool = design["alternate"] and k % 2 == 1
				shapes.append("round" if small else design["row_shape"])
				tones.append(_row_tone(toning, k))
			_rows(region, radii, shapes, tones)
			_tone = 1 if toning == "heart" else 0
			_fill_rest([r_row, r_row * 0.75, r_row * 0.55])
		"halo":
			var rows: int = design["halo_rows"]
			var radii := []
			var shapes := []
			var tones := []
			for k in rows:
				radii.append(r_row * (1.0 if k == 0 else 0.8))
				shapes.append(design["row_shape"] if k == 0 else "round")
				tones.append(_row_tone(toning, k))
			_rows(region, radii, shapes, tones)
			_tone = 0 if toning == "edge" else 1
			_center_stone(region, INF)
			_tone = 0
			_fill_rest([r_row * 0.8, r_row * 0.6])
		"rosette":
			_tone = 1 if toning in ["heart", "rows"] else 0
			var rc := _rosette(region, r_row)
			_tone = 0
			# Outline rows stop short of the rosette.
			var depth: float = region["max_dist"] - rc
			var n := clampi(floori(depth / (2.0 * r_row + gap)), 0, 3)
			var radii := []
			var shapes := []
			var tones := []
			for k in n:
				radii.append(r_row)
				shapes.append(design["row_shape"])
				tones.append(_row_tone("edge" if toning == "edge" else "solid", k))
			_rows(region, radii, shapes, tones)
			_fill_rest([r_row, r_row * 0.7, r_row * 0.5])
		"honeycomb":
			if design["edge_row"]:
				_rows(region, [r_row * 0.6], ["round"], [1 if toning != "solid" else 0])
			_tone = 0
			_lattice(region, r_row, gap, design["row_shape"], design["lattice_turn"], design["gradient"])
			_fill_rest([r_row * 0.7, r_row * 0.5])
		"stripes":
			_stripes(region, r_row, design["row_shape"], design["lattice_turn"] * 1.5, toning != "solid", design["grade"])
			_fill_rest([r_row * 0.7, r_row * 0.5])
		"sunburst":
			_tone = 0 if toning == "edge" else 1
			_sunburst(region, r_row, toning)
			_tone = 0
			_fill_rest([r_row * 0.7, r_row * 0.5])
		"pave":
			_fill_rest([u * 1.2, u * 0.85, u * 0.6, u * 0.45])
		"spine":
			_tone = 1 if toning == "heart" else 0
			_spine(region, u * 2.0, u * 0.4)
		"solitaire":
			_tone = 1 if toning == "heart" else 0
			_center_stone(region, INF)
			_tone = 0
			_fill_rest([u * 0.8, u * 0.6])


## The first passes of a tiered design: one large stone at the region's
## deepest point (shaped to it), then a few medium stones at the next
## deepest free points, before the pattern fills around them. Symmetric
## copies have the same shape, so they get the same stones.
func _tier_stones(region: Dictionary, design: Dictionary) -> void:
	var large: float = design["large"]
	var shape: String = design["tier_shape"]
	if large > 0.0:
		_part += 1
		_tone = 2
		var peak := _argmax()
		if peak >= 0:
			var c := _center(peak)
			var r := minf(large * _scale_at(c), free[peak] - gap)
			if r >= unit * 1.4:
				var placed := false
				if shape in ASPECT:
					placed = _try_capsule(shape, c, region["axis"], r / ASPECT[shape] * 1.2)
				if not placed:
					_place("round" if shape in ASPECT else shape, c, region["axis"], r, 0.0)
	var mediums: int = design["mediums"]
	if mediums > 0:
		_part += 1
		_tone = 2 if large <= 0.0 else 1
		var mr: float = design["medium_r"]
		for _i in mediums:
			var peak := _argmax()
			if peak < 0:
				break
			var c := _center(peak)
			var r := minf(mr * _scale_at(c), free[peak] - gap)
			if r < mr * 0.7:
				break
			_place("hexagon" if shape == "hexagon" else "round", c, region["axis"], r, 0.0)
	_tone = 0


func _row_tone(toning: String, k: int) -> int:
	match toning:
		"rows":
			return k % 2
		"edge":
			return 1 if k == 0 else 0
	return 0


## Radii of the outline rows that fit from the edge to the middle: each row
## `grade` times the one outside it (kept between 0.45 and 1.6 units), every
## other row smaller when `alternate`. The last row may sit a little past the
## middle; its stones shrink to fit.
func _graded_rows(region: Dictionary, r: float, grade: float, alternate: bool) -> Array:
	var depth: float = region["max_dist"]
	var d := gap
	var out := []
	var base := r
	while out.size() < 24:
		var rk := base * (0.62 if alternate and out.size() % 2 == 1 else 1.0)
		if d + rk > depth + rk * 0.35:
			break
		out.append(rk)
		d += 2.0 * rk + gap
		base = clampf(base * grade, unit * 0.45, unit * 1.6)
	return out


## Rows of stones that follow the region's outline: row k runs along the
## iso-line of the edge distance at its stones' centers, stones evenly spaced
## around it. Where the region pinches, stones shrink or drop out.
func _rows(region: Dictionary, radii: Array, shapes: Array, tones: Array) -> void:
	if radii.is_empty():
		return
	var levels := PackedFloat32Array()
	var d := gap
	for rk: float in radii:
		levels.append(d + rk)
		d += 2.0 * rk + gap
	var lines := Contours.iso_lines(map.dist, map.labels, map.width, map.height, _region, region["bbox"], levels)
	for k in radii.size():
		_tone = tones[k]
		_part += 1
		for path in lines[k]:
			_along(path["points"], path["closed"], radii[k], shapes[k])
	_tone = 0


## Stones of radius r evenly spaced along a path; elongated shapes lie along it.
func _along(pts: PackedVector2Array, closed: bool, r: float, shape: String) -> void:
	var length := Contours.length(pts, closed)
	var aspect: float = ASPECT.get(shape, 1.0)
	var pitch := 2.0 * r * aspect + gap
	if length < r:
		return
	var n: int
	var step: float
	var start := 0.0
	if closed:
		n = maxi(1, floori(length / pitch))
		step = length / n
	else:
		n = floori(length / pitch) + 1
		step = length / (n - 1) if n > 1 else 0.0
		if n == 1:
			start = length / 2.0
	var floor_r := maxf(r * 0.55, unit * 0.3)
	for i in n:
		var at: Array = Contours.sample(pts, closed, start + step * i)
		var p: Vector2 = at[0]
		var f := _free_at(p)
		var rf := minf(r * _scale_at(p), f - gap)
		if rf < floor_r * _scale_at(p):
			continue
		var rot: float = (at[1] as Vector2).angle()
		if aspect > 1.0:
			if not _try_capsule(shape, p, rot, rf):
				_place("round", p, 0.0, rf, 0.0)
		else:
			# Flat sides face along the row.
			var turn := PI / 4.0 if shape == "square" else (PI / 6.0 if shape == "hexagon" else 0.0)
			_place(shape, p, rot + turn, rf, 0.0)


## The biggest stone that fits at the region's deepest free point, shaped to
## the region (marquise or oval when it is long), at most `cap` in radius.
func _center_stone(region: Dictionary, cap: float) -> void:
	_part += 1
	var peak := _argmax()
	if peak < 0:
		return
	var c := _center(peak)
	var r := minf(free[peak] - gap, cap)
	if r < unit * 0.3:
		return
	var el: float = region["elongation"]
	if el > 1.5 and _try_capsule("marquise" if el > 2.2 else "oval", c, region["axis"], r * 0.95):
		return
	_place("round", c, 0.0, r, 0.0)


## A center stone ringed by outward teardrops. Returns the ring's outer radius.
func _rosette(region: Dictionary, r_row: float) -> float:
	var peak := _argmax()
	if peak < 0:
		return 0.0
	var c := _center(peak)
	var rc := minf(free[peak] - gap, unit * 2.2) * 0.75
	if rc < unit * 0.4:
		return 0.0
	_part += 1
	_place("round", c, 0.0, rc, 0.0)
	_part += 1
	var rt := maxf(unit * 0.5, minf(rc * 0.6, r_row))
	var ring := rc + gap + rt * 1.5
	var k := maxi(5, int(TAU * ring / (2.0 * rt + gap * 2.0)))
	var offset: float = region["axis"]
	for j in k:
		var a := offset + TAU * j / k
		var p := c + Vector2.from_angle(a) * ring
		if _free_at(p) >= rt + gap:
			_try_capsule("teardrop", p, a, rt)
	return ring + rt * 1.5 + gap


## An even lattice of stones (optionally graded smaller toward the rim):
## hexagonal, lined up with the region's axis and
## centered on its centroid, so symmetric copies get the same lattice.
func _lattice(region: Dictionary, r: float, spacing: float, shape: String, turn: float, gradient: bool) -> void:
	_part += 1
	var pitch := 2.0 * r + spacing
	var c: Vector2 = region["centroid"]
	var a: float = region["axis"] + turn
	var e1 := Vector2.from_angle(a) * pitch
	var e2 := Vector2.from_angle(a + PI / 3.0) * pitch
	var bbox: Rect2i = region["bbox"]
	var reach := ceili(Vector2(bbox.size).length() / pitch) + 1
	var pts := []
	for j in range(-reach, reach + 1):
		for i in range(-reach, reach + 1):
			var p := c + e1 * i + e2 * j
			if bbox.has_point(Vector2i(p)) and map.label_at(int(p.x), int(p.y)) == _region:
				pts.append(p)
	pts.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.distance_squared_to(c) < q.distance_squared_to(c))
	var far := 1.0
	for p: Vector2 in pts:
		far = maxf(far, p.distance_to(c))
	for p: Vector2 in pts:
		# With a gradient, stones shrink from full size at the center to 45% at the rim.
		var want := r * (lerpf(1.0, 0.45, p.distance_to(c) / far) if gradient else 1.0) * _scale_at(p)
		var rf := minf(want, _free_at(p) - gap - (spacing - gap) * 0.5)
		if rf >= want * 0.7 and rf >= unit * 0.3:
			_place(shape, p, a + (PI / 6.0 if shape == "hexagon" else 0.0), rf, 0.0)


## Straight parallel rows across the region (along its axis, turned by
## `turn`), each clipped to the region and evenly spaced inside, with the
## middle row through the centroid; rows away from the middle are `grade`
## times the size of the row before. Rows alternate tones when `banded`.
func _stripes(region: Dictionary, r0: float, shape: String, turn: float, banded: bool, grade: float) -> void:
	var c: Vector2 = region["centroid"]
	var dir := Vector2.from_angle(region["axis"] + turn)
	var nrm := dir.orthogonal()
	var bbox: Rect2i = region["bbox"]
	var reach := Vector2(bbox.size).length() / 2.0 + 2.0
	# Row offsets from the middle row outward on both sides, each row `grade`
	# times the size of the one nearer the middle.
	var offsets := [0.0]
	var sizes := [r0]
	var off := 0.0
	var r := r0
	while off < reach and offsets.size() < 200:
		var nr := clampf(r * grade, unit * 0.45, unit * 1.6)
		off += r + gap + nr
		r = nr
		offsets.append_array([off, -off])
		sizes.append_array([r, r])
	for k in offsets.size():
		r = sizes[k]
		_tone = (((k + 1) / 2) % 2) if banded else 0
		_part += 1
		var base: Vector2 = c + nrm * float(offsets[k])
		# Inside stretches of this row, where a full stone could sit.
		var run_start := NAN
		var t := -reach
		while t <= reach + 1.0:
			var p := base + dir * t
			var inside := t <= reach and _free_at(p) >= r * 0.6 + gap
			if inside and is_nan(run_start):
				run_start = t
			elif not inside and not is_nan(run_start):
				var pts := PackedVector2Array([base + dir * run_start, base + dir * (t - 1.0)])
				_along(pts, false, r, shape)
				run_start = NAN
			t += 1.0
	_tone = 0


## A center stone, then rings of stones on shared spokes, each ring's stones
## as big as the spacing between spokes allows, so they grow outward.
func _sunburst(region: Dictionary, r_row: float, toning: String) -> void:
	var peak := _argmax()
	if peak < 0:
		return
	var c := _center(peak)
	var rc := minf(free[peak] - gap, r_row * 1.6)
	if rc < unit * 0.4:
		return
	_part += 1
	_place("round", c, 0.0, rc, 0.0)
	var spokes := clampi(int(TAU * (rc + gap + r_row * 0.6) / (r_row * 1.2 + gap)), 6, 24)
	if spokes % 2 == 1:
		spokes += 1
	var a0: float = region["axis"]
	var rad := rc + gap
	var ring := 0
	var reach: float = Vector2(region["bbox"].size).length()
	while rad < reach and ring < 30:
		# Stones touch their neighbors on the ring: r = R sin(pi / n), so R = r / sin.
		var rr := minf(r_row * 1.3, (rad + r_row) * sin(PI / spokes) - gap / 2.0)
		rr = maxf(rr, unit * 0.35)
		var at := rad + rr
		_tone = (ring % 2) if toning == "rows" else _tone
		_part += 1
		for j in spokes:
			var a := a0 + TAU * j / spokes + (PI / spokes if ring % 2 == 1 and toning == "rows" else 0.0)
			var p := c + Vector2.from_angle(a) * at
			var rf := minf(rr, _free_at(p) - gap)
			if rf >= rr * 0.6:
				_place("round", p, 0.0, rf, 0.0)
		rad = at + rr + gap
		ring += 1
	_tone = 0


## A chain of stones along the region's medial axis (its centerline), each
## as big as the region is wide there (up to r_max), so the chain swells where
## the region does and tapers toward its tips. Side branches shorter than the
## region is wide are ignored; the longest stretch goes first.
func _spine(region: Dictionary, r_max: float, r_min: float) -> void:
	_part += 1
	var bbox: Rect2i = region["bbox"].grow(1)
	var bw := bbox.size.x
	var bh := bbox.size.y
	var local := PackedByteArray()
	local.resize(bw * bh)
	for y in range(1, bh - 1):
		for x in range(1, bw - 1):
			if map.label_at(bbox.position.x + x, bbox.position.y + y) == _region:
				local[y * bw + x] = 255
	var axis := Contours.centerlines(local, bw, bh, region["max_dist"] * 1.5)
	var paths: Array = axis["paths"]
	paths.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		return Contours.length(p["points"], p["closed"]) > Contours.length(q["points"], q["closed"]))
	var shift := Vector2(bbox.position)
	for path in paths:
		var pts: PackedVector2Array = path["points"]
		for i in pts.size():
			pts[i] += shift
		var closed: bool = path["closed"]
		var length := Contours.length(pts, closed)
		var s := 0.0
		while s <= length:
			var p: Vector2 = Contours.sample(pts, closed, s)[0]
			var r := minf(r_max * _scale_at(p), _free_at(p) - gap)
			if r >= r_min:
				_place("round", p, 0.0, r, 0.0)
				# The next stone sits just past this one, sized for where it lands.
				var ahead: Vector2 = Contours.sample(pts, closed, s + 2.0 * r + gap)[0]
				var nr := clampf(_dist_at(ahead) - gap, r_min, minf(r_max, r * 1.4))
				s += r + gap + nr
			else:
				s += 1.0
	# Wide spots the axis missed (a fat end, a corner) get one stone each.
	_fill_rest([r_max * 0.5, unit * 0.6])


func _dist_at(p: Vector2) -> float:
	var x := int(p.x)
	var y := int(p.y)
	if map.label_at(x, y) != _region:
		return 0.0
	return map.dist[y * map.width + x]


## Fills what the pattern left open, biggest stones first, from the given
## sizes only, so leftovers match the pattern instead of turning to dust.
func _fill_rest(sizes: Array) -> void:
	_part += 1
	var r_min: float = sizes[-1]
	while true:
		var peak := _argmax()
		if peak < 0:
			return
		_cur_max = free[peak]
		var avail := free[peak] - gap
		if avail < r_min:
			return
		var r := r_min
		for s: float in sizes:
			if s <= avail:
				r = s
				break
		_place("round", _center(peak), 0.0, r, 0.0)


## Size scale for a stone at p: 1, or smaller toward the picture's center.
func _scale_at(p: Vector2) -> float:
	if not radial_size:
		return 1.0
	return lerpf(RADIAL_MIN, 1.0, clampf(p.distance_to(_pic_center) / _pic_reach, 0.0, 1.0))


func _center(i: int) -> Vector2:
	return Vector2(i % map.width + 0.5, i / map.width + 0.5)


func _free_at(p: Vector2) -> float:
	var x := int(p.x)
	var y := int(p.y)
	if map.label_at(x, y) != _region:
		return -1.0
	return free[y * map.width + x]


## True if a capsule of half-length h and radius r at c fits, sampling the
## free field along its axis.
func _fits(c: Vector2, dir: Vector2, h: float, r: float) -> bool:
	var n := maxi(1, ceili(h / maxf(1.0, r * 0.5)))
	for i in range(-n, n + 1):
		if _free_at(c + dir * (h * i / n)) < r + gap:
			return false
	return true


## Places an elongated shape as long as it fits (up to its full aspect).
func _try_capsule(shape: String, c: Vector2, rotation: float, r: float) -> bool:
	var dir := Vector2.from_angle(rotation)
	var h: float = r * (ASPECT.get(shape, 1.0) - 1.0)
	for _attempt in 4:
		if _fits(c, dir, h, r):
			_place(shape, c, rotation, r, h)
			return true
		h *= 0.6
	return false


func _place(shape: String, c: Vector2, rotation: float, r: float, h: float) -> void:
	slots.append({
		"id": slots.size(),
		"region": _region,
		"shape": shape,
		"x": c.x,
		"y": c.y,
		"rotation": wrapf(rotation, -PI, PI),
		"size": 2.0 * (r + h),
		"width": 2.0 * r,
		"tone": _tone,
		"part": _part,
	})
	_stamp(c, Vector2.from_angle(rotation), h, r)


## Lowers the free field around a new capsule. Pixels further away than the
## current peak value can't change, which bounds the box.
func _stamp(c: Vector2, dir: Vector2, h: float, r: float) -> void:
	var w := map.width
	var reach := r + h + _cur_max + gap + 2.0
	var x0 := maxi(0, int(c.x - reach))
	var x1 := mini(w - 1, int(c.x + reach))
	var y0 := maxi(0, int(c.y - reach))
	var y1 := mini(map.height - 1, int(c.y + reach))
	for y in range(y0, y1 + 1):
		var py := y + 0.5 - c.y
		for x in range(x0, x1 + 1):
			var i := y * w + x
			if map.labels[i] != _region:
				continue
			var px := x + 0.5 - c.x
			var t := clampf(px * dir.x + py * dir.y, -h, h)
			var ex := px - t * dir.x
			var ey := py - t * dir.y
			var dd := sqrt(ex * ex + ey * ey) - r
			if dd < free[i]:
				free[i] = dd
	for by in range(y0 / BLOCK, y1 / BLOCK + 1):
		for bx in range(x0 / BLOCK, x1 / BLOCK + 1):
			_block_dirty[by * _bw + bx] = 1


## Pixel index of the current region's largest free value, or -1.
func _argmax() -> int:
	var w := map.width
	var best := -1
	var best_v := -INF
	for by in range(_region_blocks.position.y, _region_blocks.end.y):
		for bx in range(_region_blocks.position.x, _region_blocks.end.x):
			var b := by * _bw + bx
			if _block_dirty[b]:
				_block_dirty[b] = 0
				var m := -INF
				var arg := -1
				for y in range(by * BLOCK, mini(map.height, (by + 1) * BLOCK)):
					for x in range(bx * BLOCK, mini(w, (bx + 1) * BLOCK)):
						var i := y * w + x
						if map.labels[i] == _region and free[i] > m:
							m = free[i]
							arg = i
				_block_max[b] = m
				_block_arg[b] = arg
			if _block_max[b] > best_v:
				best_v = _block_max[b]
				best = _block_arg[b]
	return best

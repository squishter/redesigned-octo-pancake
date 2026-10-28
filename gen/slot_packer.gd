class_name SlotPacker
extends RefCounted
## Packs gem slots into the regions of a RegionMap.
##
## Every slot is treated as a capsule for collisions: a segment of half-length
## h along its rotation, grown by radius r. A round stone has h = 0; a marquise
## or baguette has h > 0. A "free" field holds, for every pixel, how far it is
## from the region's edge and from every slot placed so far. Each step places
## the biggest stone that fits at the pixel where that field peaks, so stones
## go in largest first and shrink until the region is about 80% covered.
##
## The peak search uses per-block maxima (BLOCK x BLOCK px) that are refreshed
## only where slots changed the field.

const BLOCK := 16

## Length / width of the elongated shapes. The rest are as wide as they are long.
const ASPECT := {"oval": 1.35, "teardrop": 1.5, "marquise": 2.0, "baguette": 2.4}

## Fill styles, picked per region from its size and shape:
## cabochon: one big stone, leftovers get small pave stones
## pave: many small rounds of a few sizes
## petals: a center stone ringed by outward teardrops, then pave
## flow: marquises and baguettes along the region's spine
## mosaic: mixed squares, hexagons and triangles
## Sparse fills, only used when asked for (see DesignPlan):
## scatter: a few small stones with breathing room between them
## accent: a single stone at the region's heart
## outline: only a rhinestone border
## bare: no stones
const STYLES := ["cabochon", "pave", "petals", "flow", "mosaic", "scatter", "accent", "outline", "bare"]
## Share of a scatter region its stones cover.
const SCATTER_COVERAGE := 0.3

var map: RegionMap
var rng := RandomNumberGenerator.new()
var free := PackedFloat32Array()
var slots: Array[Dictionary] = []
## Base stone radius in px; every style's sizes are multiples of it.
var unit := 8.0
var gap := 2.0
var coverage := 0.8
var outline_chance := 0.5

var _bw := 0
var _bh := 0
var _block_max := PackedFloat32Array()
var _block_arg := PackedInt32Array()
var _block_dirty := PackedByteArray()
var _region := -1
var _region_blocks := Rect2i()
var _cur_max := 0.0
var _covered := 0.0


## Packs every region. options:
##   seed (int), unit (base stone radius in px, default 1% of the picture),
##   gap (px between stones, default 0.3%), coverage (0..1, default 0.8),
##   outline (chance a big region gets a rhinestone border, default 0.5),
##   styles (Dictionary region id -> style, to force a style).
## Returns slots: {id, region, shape, x, y, rotation, size, width}, in px of
## the map; size is the length along the rotation, width across it.
## Also writes the chosen style into each region's dictionary.
static func pack(region_map: RegionMap, options: Dictionary = {}) -> Array[Dictionary]:
	var p := SlotPacker.new()
	p._setup(region_map, options)
	var forced: Dictionary = options.get("styles", {})
	var order := region_map.regions.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["area"] > b["area"])
	for region in order:
		p._pack_region(region, forced.get(region["id"], ""))
	return p.slots


func _setup(region_map: RegionMap, options: Dictionary) -> void:
	var side := float(mini(region_map.width, region_map.height))
	map = region_map
	rng.seed = options.get("seed", 1)
	unit = options.get("unit", side * 0.010)
	gap = options.get("gap", side * 0.003)
	coverage = options.get("coverage", 0.8)
	outline_chance = options.get("outline", 0.5)
	free = region_map.dist.duplicate()
	_bw = ceili(region_map.width / float(BLOCK))
	_bh = ceili(region_map.height / float(BLOCK))
	_block_max.resize(_bw * _bh)
	_block_arg.resize(_bw * _bh)
	_block_dirty.resize(_bw * _bh)


func _pack_region(region: Dictionary, forced_style: String) -> void:
	_region = region["id"]
	var bbox: Rect2i = region["bbox"]
	_region_blocks = Rect2i(bbox.position.x / BLOCK, bbox.position.y / BLOCK, 0, 0)
	_region_blocks.end = Vector2i((bbox.end.x - 1) / BLOCK + 1, (bbox.end.y - 1) / BLOCK + 1)
	for by in range(_region_blocks.position.y, _region_blocks.end.y):
		for bx in range(_region_blocks.position.x, _region_blocks.end.x):
			_block_dirty[by * _bw + bx] = 1
	var max_d: float = region["max_dist"]
	_cur_max = max_d
	_covered = 0.0
	var style: String = forced_style if forced_style in STYLES else _choose_style(region)
	region["style"] = style
	var u := unit

	match style:
		"bare":
			return
		"outline":
			_outline(region, u * 0.45)
			return
		"accent":
			var peak := _argmax()
			var c := _center(peak)
			var r := minf(free[peak] - gap, u * 2.2)
			var placed := false
			if region["elongation"] > 1.5:
				placed = _try_capsule("marquise" if region["elongation"] > 2.2 else "oval", c, region["axis"], r * 0.92)
			if not placed:
				_place("round", c, 0.0, r, 0.0)
			return

	if style in ["pave", "mosaic", "petals"] and max_d > u * 3.0 and rng.randf() < outline_chance:
		_outline(region, u * 0.45)

	if style == "cabochon":
		var peak := _argmax()
		var c := _center(peak)
		var r := free[peak] - gap
		var placed := false
		if region["elongation"] > 1.5:
			var shape: String = "marquise" if region["elongation"] > 2.2 else "oval"
			placed = _try_capsule(shape, c, region["axis"], r * 0.92)
		if not placed:
			_place("round", c, 0.0, r, 0.0)
		style = "pave"
	elif style == "petals":
		var peak := _argmax()
		var c := _center(peak)
		var rc := minf(free[peak] - gap, u * 2.2) * 0.75
		_place("round", c, 0.0, rc, 0.0)
		var rt := maxf(u * 0.5, rc * 0.5)
		var ring := rc + gap + rt * 1.5
		var k := maxi(5, int(TAU * ring / (2.0 * rt + gap * 2.0)))
		var offset := rng.randf() * PI
		for j in k:
			var a := offset + TAU * j / k
			var p := c + Vector2.from_angle(a) * ring
			if _free_at(p) >= rt + gap:
				_try_capsule("teardrop", p, a, rt)
		style = "pave"

	var sizes: Array
	match style:
		"mosaic":
			sizes = [u * 1.3, u * 1.0, u * 0.75]
		"flow":
			sizes = [u * 1.4, u * 1.0, u * 0.7, u * 0.5]
			# Thin regions take whatever width they have, down to a floor.
			if max_d - gap < u * 0.5 and max_d - gap >= u * 0.3:
				sizes.append(max_d - gap)
		"scatter":
			sizes = [u * 0.8, u * 0.6, u * 0.45]
		_:
			sizes = [u * 1.2, u * 0.85, u * 0.6, u * 0.45]
	var r_min: float = sizes[-1]
	var area: float = region["area"]
	var target := coverage
	# Scatter keeps each stone this far from its neighbors and the edge.
	var spacing := 0.0
	if style == "scatter":
		target = SCATTER_COVERAGE
		spacing = u * rng.randf_range(1.0, 1.8)
	while _covered < target * area:
		var peak := _argmax()
		if peak < 0:
			break
		_cur_max = free[peak]
		var avail := free[peak] - gap - spacing
		if avail < r_min:
			break
		var r := r_min
		for s in sizes:
			if s <= avail:
				r = s
				break
		var c := _center(peak)
		match style:
			"mosaic":
				var shape: String = ["square", "hexagon", "triangle"][rng.randi_range(0, 2)]
				_place(shape, c, rng.randi_range(0, 5) * PI / 6.0, r, 0.0)
			"flow":
				var ang := map.gradient_angle(peak % map.width, peak / map.width)
				var rot: float = 0.0 if is_nan(ang) else ang + PI / 2.0
				var shape: String = "baguette" if rng.randf() < 0.33 else "marquise"
				r = minf(avail, sizes[0])
				if not _try_capsule(shape, c, rot, r):
					_place("round", c, 0.0, r, 0.0)
			_:
				_place("round", c, 0.0, r, 0.0)


func _choose_style(region: Dictionary) -> String:
	var max_d: float = region["max_dist"]
	var compact: float = region["area"] / (PI * max_d * max_d)
	var u := unit
	if compact > 4.5 or max_d < u * 0.9:
		return "flow"
	if max_d < u * 4.0:
		return "cabochon"
	if compact < 2.6 and max_d > u * 3.5 and rng.randf() < 0.5:
		return "petals"
	if max_d > u * 5.0 and rng.randf() < 0.7:
		return "pave"
	return "mosaic" if rng.randf() < 0.5 else "pave"


## Small round stones in a band just inside the region's edge, like a
## rhinestone outline.
func _outline(region: Dictionary, r: float) -> void:
	var bbox: Rect2i = region["bbox"]
	var w := map.width
	var lo := r + gap
	for y in range(bbox.position.y, bbox.end.y):
		for x in range(bbox.position.x, bbox.end.x):
			var i := y * w + x
			if map.labels[i] != _region:
				continue
			var d := map.dist[i]
			if d >= lo and d < lo + 1.0 and free[i] >= lo:
				_place("round", Vector2(x + 0.5, y + 0.5), 0.0, r, 0.0)


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
	})
	_covered += PI * r * r + 4.0 * r * h
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

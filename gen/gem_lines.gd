class_name GemLines
extends RefCounted
## Turns a picture's lines into rows of gems: stones slotted along each line's
## centerline instead of a metal setting. A stone sits on every junction, and
## the stones between are spaced evenly so each line starts and ends neatly.
##
## Styles (the shape of the stones, and how their size changes along a line):
##   beads: round stones of one size
##   pearls: big and small rounds alternating
##   marquise: marquises lying along the line, rounds on the junctions
##   baguette: baguettes along the line, rounds on the junctions
##   emerald: clipped-corner step cuts along the line, rounds on the junctions
##   lozenge: diamond-shaped lozenges along the line, rounds on the junctions
##   taper: swells in the middle of each stretch of line and narrows at its
##     ends, like an ink stroke
##   pulse: grows and shrinks in waves, evenly from the line's middle
##   ramp: grows from one end of a line to the other: outward on some
##     symmetry classes of lines, inward on others (lines that run around
##     the center swell or pinch in the middle instead)
##   radial: stones shrink toward the picture's center
##   hub: stones shrink toward the nearest hub where several lines meet (the
##     middle of a flower, a star's center), so each motif draws inward
## In the styles of one size, some classes of longer lines grow, shrink or
## swell along their length too (GRADED_CHANCE), so runs of stones change
## size as they go. Sizes always run relative to the picture's center, so
## symmetric copies match. Every style also narrows toward a line's loose
## end. The caller builds the channel around the stones it gets back, so a
## line is exactly as wide as its stones at every point.
## A share of the classes of lines can be dense: their stones sit closer
## together (DENSE_GAP of the gap), so a line carries more of them.

const STYLES := ["beads", "beads", "pearls", "marquise", "baguette", "emerald", "lozenge", "taper", "pulse", "ramp",
		"radial", "hub"]
## Step sequences an occasional long line repeats, one gem type per step.
## Open lines count from both ends toward the middle, so the sequence reads
## the same either way and mirrored copies match; closed loops only take
## the simple alternation, and only with an even number of stones.
## All use at most 3 types and, apart from the wave, repeat within 4 stones.
const SEQUENCES := [
	[0, 1], [0, 1],  # 1-2
	[0, 1, 1],  # 1-2-2
	[0, 0, 1],  # 1-1-2
	[0, 0, 1, 1],  # 1-1-2-2
	[0, 1, 1, 1],  # 1-2-2-2
	[0, 1, 2],  # 1-2-3
	[0, 1, 2, 1],  # 1-2-3-2
	[0, 1, 0, 2],  # 1-2-1-3
	[0, 1, 1, 2, 2, 1, 1, 0],  # 1-2-2-3-3-2-2-1, a wave
]
## Share of line classes with long enough lines that get a sequence.
const SEQUENCE_CHANCE := 0.2
## Stones a line needs before it can carry a sequence.
const SEQUENCE_MIN_STONES := 10
## Junction stones' parts start here, after the lines' own.
const NODE_PARTS := 100000
## Smallest stone, as a share of the full line stone.
const MIN_SCALE := 0.35
## Largest stone of a line that grows or swells, as a share of the line stone.
const GROWN_SCALE := 1.45
## Share of line classes (with room for 4+ stones) that grow, shrink or swell
## in the styles of one size.
const GRADED_CHANCE := 0.6
## Size profiles along a line (see _radius).
const GRADED := ["grow", "shrink", "swell"]
## Lines carry on through a junction (as one stroke) when they meet within
## this many radians of a straight line.
const STROKE_TURN := 0.52
## A line's stones are at most this share of the room beside it (the width
## of the narrower area there, from the line's center), and at least
## MIN_FIT of the full line stone.
const FIT_SHARE := 0.45
const MIN_FIT := 0.35
## Lines that meet at a hub: at least this many.
const HUB_DEGREE := 4
## Bold lines: a few classes of lines through the middle of the picture take
## medium or large stones (times the line stone), to break up the run of
## small ones there. They lie within this share of the picture's reach.
const BOLD_SIZES := [1.7, 2.3]
const BOLD_REACH := 0.55
## How far out bold lines may go when the middle has too few with room.
const BOLD_REACH_MORE := 0.75
## The space between a dense line's stones, as a share of the gap.
const DENSE_GAP := 0.4


## graph: Contours.centerlines() of the line mask. map: a RegionMap of the
## lines (its BACKGROUND tells the silhouette apart).
## Returns slots ({id, region, shape, x, y, rotation, size, width, tone, part}) with
## region 0 for inner lines and 1 for the silhouette; the caller renumbers.
## `part` is the line's symmetry class (lines that are copies of each other
## under `symmetry` share one), and junction stones get classes of their own,
## so a line's stones always stay one gem type, except on the occasional
## long line that repeats a sequence (see SEQUENCES): there `seq` (and
## `tone`) gives each stone's step, 0, 1 or 2, for the caller to color;
## `seq` is -1 on other lines.
## Up to `bold` classes of lines through the middle get medium or large
## stones (see BOLD_SIZES) where their areas have room, in the line's
## accent color (tone 1) unless they repeat a sequence.
## `line_mask` (the line art, nonzero on lines; default: the map's lines)
## gives the symmetry the stones are made to follow (see LineMirror).
## Classes listed in `drop` get no stones (their lines stay as plain
## separators); class numbers don't change when some are dropped.
## `dense` (0..1) is the share of classes whose stones sit closer together
## (see DENSE_GAP), picked by the seed among all the classes, so dropping
## some doesn't change which.
static func place(graph: Dictionary, map: RegionMap, r: float, gap: float, style: String,
		symmetry: String = "none", seed_value: int = 1, bold: int = 0,
		line_mask: PackedByteArray = PackedByteArray(), drop: Array = [], dense: float = 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hash := {}
	var cell := r * 4.0
	var nodes: Array = graph["nodes"]
	var center := Vector2(map.width, map.height) / 2.0
	var tol := minf(map.width, map.height) * 0.015
	# Symmetry classes over every line first, so they keep their numbers when
	# some are dropped.
	var all_paths: Array = graph["paths"]
	var path_keys := []
	for path in all_paths:
		var pts: PackedVector2Array = path["points"]
		# A loop's traversal starts anywhere, so key it by its center instead.
		var at := pts[pts.size() / 2]
		if path["closed"]:
			at = Vector2.ZERO
			for q in pts:
				at += q
			at /= pts.size()
		path_keys.append(_sym_key(at, center, symmetry, Contours.length(pts, path["closed"])))
	var all_class := _classes(path_keys, tol)
	var tight := _dense_classes(all_class, dense, seed_value)
	var paths := []
	var path_class := PackedInt32Array()
	for k in all_paths.size():
		if not all_class[k] in drop:
			paths.append(all_paths[k])
			path_class.append(all_class[k])
	# Which paths run along the silhouette (background on one side).
	var outer := PackedByteArray()
	var node_outer := PackedInt32Array()
	node_outer.resize(nodes.size())
	var node_paths := PackedInt32Array()
	node_paths.resize(nodes.size())
	var far := 1.0
	for path in paths:
		var o := _is_outer(path["points"], map, r + gap * 2.0 + 2.0)
		outer.append(1 if o else 0)
		for e: int in path["ends"]:
			if e >= 0:
				node_paths[e] += 1
				node_outer[e] += 1 if o else 0
		for p in path["points"]:
			far = maxf(far, p.distance_to(center))
	var hubs := []
	for n in nodes.size():
		if node_paths[n] >= HUB_DEGREE:
			hubs.append(nodes[n])
	if style == "hub" and hubs.is_empty():
		style = "radial"
	var field := {"style": style, "r": r, "center": center, "far": far, "hubs": hubs,
			"hub_reach": minf(map.width, map.height) * 0.22}

	var node_keys := []
	for n in nodes.size():
		node_keys.append(_sym_key(nodes[n], center, symmetry, 0.0))
	var node_class := _classes(node_keys, tol)
	var bold_r := _bold_classes(paths, path_class, map, r, gap, center, far, bold, seed_value)
	# Each line's stones fit the room beside it, so lines drawn close
	# together (small curly details) still get a run of small stones instead
	# of crowding each other out; a junction takes its smallest line's size.
	var path_r := PackedFloat32Array()
	var node_r := PackedFloat32Array()
	node_r.resize(nodes.size())
	node_r.fill(INF)
	for k in paths.size():
		var pr: float = bold_r.get(path_class[k], r)
		if not bold_r.has(path_class[k]):
			pr = r * clampf(FIT_SHARE * _line_room(paths[k], map) / r, MIN_FIT, 1.0)
		path_r.append(pr)
		for e: int in paths[k]["ends"]:
			if e >= 0:
				node_r[e] = minf(node_r[e], minf(pr, r))
	for c: int in bold_r:
		cell = maxf(cell, (bold_r[c] + r) * 1.2 + gap)

	# The symmetry of the lines in a band around the center (see
	# Symmetry.ring_symmetry), for loops around the center and for snapping
	# copies' transforms; each band is worked out once.
	var drawn := _draw_paths(paths, map.width, map.height) if symmetry != "none" else PackedByteArray()
	var bands := {}
	var band_sym := func(span: Vector2) -> Dictionary:
		var key := Vector2i(floori(span.x / (r * 2.0)), ceili(span.y / (r * 2.0)))
		if not bands.has(key):
			var around := PackedVector2Array()
			for path in paths:
				for q: Vector2 in path["points"]:
					var d := q.distance_to(center)
					if d >= span.x - r * 6.0 and d <= span.y + r * 6.0:
						around.append(q)
			var w := map.width
			var h := map.height
			bands[key] = Symmetry.ring_symmetry(around, center, func(q: Vector2) -> bool:
				return q.x >= 0.0 and q.y >= 0.0 and q.x < w and q.y < h and drawn[int(q.y) * w + int(q.x)] == 1)
		return bands[key]
	var rings := {}
	if symmetry != "none":
		for k in paths.size():
			if paths[k]["closed"] and Geometry2D.is_point_in_polygon(center, paths[k]["points"]):
				rings[k] = band_sym.call(_span(paths[k]["points"], center))
	var r_node := r * (1.15 if style == "beads" else 1.0)
	# Lines go one symmetry class at a time: a line is laid out once, and every
	# symmetric copy of it copies its stones by the rotation or reflection that
	# carries it there, so copies match stone for stone. A class can hold more
	# than one shape of line; each is laid out once. Pulses and ramps run in
	# set directions, so each of their lines is laid out anew. Junctions sit
	# where thinning happened to put them, a few px apart on each copy; a
	# copy's junctions move to where its master's land.
	var by_class := {}
	for k in paths.size():
		if not by_class.has(path_class[k]):
			by_class[path_class[k]] = []
		by_class[path_class[k]].append(k)
	var copies := symmetry != "none"
	var copy_of := {}
	var at := nodes.duplicate()
	var settled := PackedByteArray()
	settled.resize(nodes.size())
	for c: int in by_class:
		var masters := []
		for k: int in by_class[c]:
			if copies:
				for m: int in masters:
					var sym: Dictionary = band_sym.call(_span(paths[k]["points"], center)) if symmetry == "radial" else {}
					var xf := Symmetry.line_transform(paths[m], paths[k], center, map, sym)
					if not xf.is_empty():
						copy_of[k] = [m, xf]
						_follow_ends(paths[m], paths[k], xf, at, settled, nodes, r * 3.0)
						break
			if not copy_of.has(k):
				masters.append(k)
			for e: int in paths[k]["ends"]:
				if e >= 0:
					settled[e] = 1
	if symmetry == "radial":
		_snap_nodes(at, node_class, center, band_sym, minf(map.width, map.height))
	# Lines run on through junctions where they carry straight on (strokes),
	# and a stroke changes size along its whole length.
	var strokes := _strokes(paths, node_paths, center, r)
	var pitch := r * 2.0 * _aspect(style) + gap
	for st: Dictionary in strokes["list"]:
		var key := 1 << 30
		for k: int in st["paths"]:
			key = mini(key, path_class[k])
			st["bold"] = st.get("bold", false) or bold_r.has(path_class[k])
		st["profile"] = _profile(style, key, seed_value, st, pitch)
	for n in nodes.size():
		if node_paths[n] == 0:
			continue
		var silhouette := node_outer[n] * 2 >= node_paths[n]
		var rn := minf(r, node_r[n]) * (r_node / r) * _place_scale(field, at[n])
		# A junction inside a stroke takes the stroke's size there.
		if strokes["node_t"].has(n):
			var nt: Array = strokes["node_t"][n]
			rn = minf(r, node_r[n]) * (r_node / r) * _scale(strokes["list"][nt[0]]["profile"], nt[1])
		_add(out, hash, cell, at[n], 0.0, rn, 0.0, "round", 1 if silhouette else 0, gap, NODE_PARTS + node_class[n])
	var ctx := {
		"field": field, "r": r, "r_node": r_node, "gap": gap, "cell": cell, "style": style, "outer": outer,
		"path_class": path_class, "bold_r": bold_r, "seed": seed_value, "rings": rings, "strokes": strokes,
		"path_r": path_r, "node_r": node_r, "tight": tight,
	}
	var laid := {}
	for c: int in by_class:
		for k: int in by_class[c]:
			if copy_of.has(k):
				_copy_line(out, hash, cell, laid[copy_of[k][0]], copy_of[k][1], gap * tight.get(c, 1.0))
			else:
				var before := out.size()
				_lay_line(out, hash, paths[k], k, ctx)
				laid[k] = out.slice(before)
	# Details drawn smaller than a run of stones (a little tulip, a petal,
	# lines cut short by junctions) still get stones wherever one fits along
	# them, so the drawing stays legible.
	for c: int in by_class:
		for k: int in by_class[c]:
			_fill_line(out, hash, cell, gap * tight.get(c, 1.0), paths[k], path_r[k], outer[k], path_class[k])
	if line_mask.is_empty():
		line_mask = map.line_mask()
	return LineMirror.apply(out, line_mask, map.width, map.height, symmetry, r, gap, cell, tight)


## The dense classes of lines: `share` of the classes in `all_class`, picked
## in a seeded order, as {class: their gap's share of the gap}.
static func _dense_classes(all_class: PackedInt32Array, share: float, seed_value: int) -> Dictionary:
	var tight := {}
	if share <= 0.0:
		return tight
	var seen := {}
	for c in all_class:
		seen[c] = true
	var classes: Array = seen.keys()
	classes.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "dense lines"])
	for i in range(classes.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = classes[i]
		classes[i] = classes[j]
		classes[j] = t
	for i in mini(classes.size(), roundi(classes.size() * share)):
		tight[classes[i]] = DENSE_GAP
	return tight


## Moves the junctions at the ends of `copy` (a copy of `master` by xf) to
## where the master's junctions land, unless a line placed earlier already
## settled them, or the nearest lands more than `reach` px away.
static func _follow_ends(master: Dictionary, copy: Dictionary, xf: Dictionary, at: Array, settled: PackedByteArray,
		nodes: Array, reach: float) -> void:
	var t: Transform2D = xf["xf"]
	for e: int in copy["ends"]:
		if e < 0 or settled[e]:
			continue
		var best := reach
		for em: int in master["ends"]:
			if em >= 0:
				var q: Vector2 = t * (at[em] as Vector2)
				var d := q.distance_to(nodes[e])
				if d < best:
					best = d
					at[e] = q


## Puts each class of junctions exactly where the symmetry of the lines
## around them says (see Symmetry.ring_symmetry): one radius, and angles
## that repeat with the folds (mirrored across the axes). A class can hold
## more than one set (tips and bases of teeth at the same radius); each set
## is the junctions that sit at the same angle within their fold, to a few
## px. Sets that don't line up that well are left as they are.
static func _snap_nodes(at: Array, node_class: PackedInt32Array, center: Vector2, band_sym: Callable,
		side: float) -> void:
	var members := {}
	for n in at.size():
		if not members.has(node_class[n]):
			members[node_class[n]] = []
		members[node_class[n]].append(n)
	for c: int in members:
		var ns: Array = members[c]
		var rho := 0.0
		for n: int in ns:
			rho += (at[n] as Vector2).distance_to(center)
		rho /= ns.size()
		if rho < side * 0.02:
			continue
		var sym: Dictionary = band_sym.call(Vector2(rho, rho))
		if sym["folds"] >= Symmetry.MAX_FOLDS:
			continue
		var mirrored := not is_nan(sym["axis"])
		var axis: float = sym["axis"] if mirrored else 0.0
		var step: float = TAU / sym["folds"]
		var tol := 3.0 / rho
		# Each junction's angle within its fold, folded onto one side of the
		# axis when mirrored (or taken as just before the next fold when it's
		# near the end of one).
		var found := []  # [offset within the fold, junction, angle within the fold]
		for n: int in ns:
			var a := fposmod((at[n] as Vector2 - center).angle() - axis, step)
			var t := a
			if mirrored and a > step / 2.0:
				t = step - a
			elif not mirrored and a > step / 2.0:
				t = a - step
			found.append([t, n, a])
		found.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		var i := 0
		while i < found.size():
			var j := i + 1
			while j < found.size() and found[j][0] - found[j - 1][0] <= tol:
				j += 1
			_snap_set(at, found.slice(i, j), center, step, mirrored, tol)
			i = j


## Snaps one set of junctions (see _snap_nodes) to their mean radius and
## mean angle within the fold, if they agree to within a few px.
static func _snap_set(at: Array, group: Array, center: Vector2, step: float, mirrored: bool, tol: float) -> void:
	if group.size() < 2:
		return
	var mean := 0.0
	var rho := 0.0
	for f: Array in group:
		mean += f[0]
		rho += (at[f[1]] as Vector2).distance_to(center)
	mean /= group.size()
	rho /= group.size()
	for f: Array in group:
		if absf(f[0] - mean) > tol or absf((at[f[1]] as Vector2).distance_to(center) - rho) > 3.0:
			return
	for f: Array in group:
		var n: int = f[1]
		var a: float = f[2]
		var base := (at[n] as Vector2 - center).angle() - a
		var angle := base + mean
		if mirrored and a > step / 2.0:
			angle = base + step - mean
		elif not mirrored and a > step / 2.0:
			angle = base + step + mean
		at[n] = center + Vector2.from_angle(angle) * rho


## Lays out the stones along path k (see place; ctx holds its settings).
static func _lay_line(out: Array[Dictionary], hash: Dictionary, path: Dictionary, k: int, ctx: Dictionary) -> void:
	var field: Dictionary = ctx["field"]
	var style: String = ctx["style"]
	var r: float = ctx["r"]
	var r_node: float = ctx["r_node"]
	var path_class: PackedInt32Array = ctx["path_class"]
	var gap: float = ctx["gap"] * ctx["tight"].get(path_class[k], 1.0)
	var cell: float = ctx["cell"]
	var bold_r: Dictionary = ctx["bold_r"]
	var pts: PackedVector2Array = path["points"]
	var closed: bool = path["closed"]
	var ends: Array = path["ends"].duplicate()
	var length := Contours.length(pts, closed)
	var aspect := 1.0
	var shape := "round"
	match style:
		"marquise":
			shape = "marquise"
			aspect = 1.8
		"baguette", "emerald":
			shape = style
			aspect = 1.6
		"lozenge":
			shape = "lozenge"
			aspect = 1.8
	var prof := {
		"pts": pts,
		"closed": closed,
		"length": length,
		"r": ctx["path_r"][k],
		"bold": bold_r.has(path_class[k]),
		"loose": [not closed and ends[0] < 0, not closed and ends[1] < 0],
		"ring": ctx["rings"].has(k),
	}
	var place: Array = ctx["strokes"]["of"][k]
	prof["profile"] = ctx["strokes"]["list"][place[0]]["profile"]
	prof["t0"] = place[1]
	prof["t1"] = place[2]
	var s0 := 0.0
	var s1 := length
	if not closed:
		if ends[0] >= 0:
			s0 = _end_r(ctx, ends[0], r_node) * _place_scale(field, pts[0]) + gap + _radius(field, prof, 0.0, 0) * aspect
		if ends[1] >= 0:
			s1 = length - (_end_r(ctx, ends[1], r_node) * _place_scale(field, pts[pts.size() - 1]) + gap
					+ _radius(field, prof, length, 0) * aspect)
	var span := s1 - s0
	if span < -r:
		return
	# Walk the line once with each stone's radius taken from the profile, then
	# stretch the spacing so the stones fill the span evenly.
	var at_list := PackedFloat32Array([0.0])
	var used := 0.0
	var limit := length if closed else maxf(0.0, span)
	var first := _radius(field, prof, s0, 0)
	while at_list.size() < 5000:
		var i := at_list.size() - 1
		var cur := _radius(field, prof, s0 + used, i)
		var nxt := _radius(field, prof, s0 + used + 2.0 * cur * aspect + gap, i + 1)
		var step := cur * aspect + gap + nxt * aspect
		var room := limit - ((nxt * aspect + gap + first * aspect) if closed else 0.0)
		if used + step > room + 0.001:
			break
		used += step
		at_list.append(used)
	if closed and style == "pearls" and at_list.size() % 2 == 1 and at_list.size() > 1:
		at_list.resize(at_list.size() - 1)
		used = at_list[at_list.size() - 1]
	var stretch := 1.0
	var start := s0
	if closed:
		var last := _radius(field, prof, used, at_list.size() - 1)
		stretch = length / maxf(1.0, used + last * aspect + gap + first * aspect)
		start = 0.0
	elif at_list.size() == 1:
		start = (s0 + s1) / 2.0
	elif used > 0.0:
		stretch = maxf(0.0, span) / used
	if prof["ring"]:
		# A ring around the center: a multiple of its folds, from its axis.
		var lay := Symmetry.ring_layout(at_list.size(), ctx["rings"][k], pts, field["center"])
		at_list.resize(lay[0])
		for i in at_list.size():
			at_list[i] = length * i / at_list.size()
		start = lay[1]
		stretch = 1.0
	var tone: int = ctx["outer"][k]
	var n_stones := at_list.size()
	var seq: Array = []
	var seq_rng := RandomNumberGenerator.new()
	seq_rng.seed = hash([ctx["seed"], path_class[k], "sequence"])
	if n_stones >= SEQUENCE_MIN_STONES and seq_rng.randf() < SEQUENCE_CHANCE:
		seq = SEQUENCES[seq_rng.randi_range(0, SEQUENCES.size() - 1)]
		if closed and (seq.size() != 2 or n_stones % 2 == 1):
			seq = []
	for i in at_list.size():
		var at := start + at_list[i] * stretch
		if closed:
			at = fposmod(at, length)
		var sample: Array = Contours.sample(pts, closed, at)
		var rot: float = (sample[1] as Vector2).angle()
		var rr := _radius(field, prof, at, i)
		var h := rr * (aspect - 1.0)
		var step := 0
		if not seq.is_empty():
			step = seq[(i if closed else mini(i, n_stones - 1 - i)) % seq.size()]
		_add(out, hash, cell, sample[0], rot, rr, h, shape, tone, gap, path_class[k], step if not seq.is_empty() else -1,
				prof["bold"])


## Nearest and farthest a line comes to the center, as (near, far).
static func _span(pts: PackedVector2Array, center: Vector2) -> Vector2:
	var near := INF
	var reach := 0.0
	for q in pts:
		near = minf(near, q.distance_to(center))
		reach = maxf(reach, q.distance_to(center))
	return Vector2(near, reach)


## The centerlines drawn 3 px wide, for checking where symmetries carry them.
static func _draw_paths(paths: Array, w: int, h: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	for path in paths:
		for q: Vector2 in path["points"]:
			for y in range(maxi(0, int(q.y) - 1), mini(h, int(q.y) + 2)):
				for x in range(maxi(0, int(q.x) - 1), mini(w, int(q.x) + 2)):
					out[y * w + x] = 1
	return out


## Adds the stones laid along one line onto its symmetric copy (xf, see
## Symmetry.line_transform), each one crowd-checked as usual.
static func _copy_line(out: Array[Dictionary], hash: Dictionary, cell: float, laid: Array[Dictionary],
		xf: Dictionary, gap: float) -> void:
	var t: Transform2D = xf["xf"]
	for s: Dictionary in laid:
		var rot := Symmetry.rotation(xf, s["rotation"])
		var r: float = s["width"] / 2.0
		var step: int = s["seq"]
		_add(out, hash, cell, t * Vector2(s["x"], s["y"]), rot, r, s["size"] / 2.0 - r, s["shape"], s["region"], gap,
				s["part"], step, step < 0 and s["tone"] == 1)


## Round stones wherever they still fit along a line (as big as its stones,
## shrunk to the room left, down to MIN_FIT of that).
static func _fill_line(out: Array[Dictionary], hash: Dictionary, cell: float, gap: float, path: Dictionary, pr: float,
		region: int, part: int) -> void:
	var pts: PackedVector2Array = path["points"]
	var closed: bool = path["closed"]
	var length := Contours.length(pts, closed)
	var least := maxf(1.5, pr * MIN_FIT)
	var s := 0.0
	while s <= length:
		var p: Vector2 = Contours.sample(pts, closed, s)[0]
		var room := LineMirror.room_at(hash, cell, gap, p, 0.0, 0.0)
		if room >= least:
			var rr := minf(pr, room)
			_add(out, hash, cell, p, 0.0, rr, 0.0, "round", region, gap, part)
			s += rr + gap
		else:
			s += 1.0


## The junction stone's radius at a line's end (before position scaling).
static func _end_r(ctx: Dictionary, node: int, r_node: float) -> float:
	var r: float = ctx["r"]
	return minf(r, ctx["node_r"][node]) * (r_node / r)


## The room beside a line: the narrower area's width (see _side_room) at a
## few points along it, a low one of them.
static func _line_room(path: Dictionary, map: RegionMap) -> float:
	var pts: PackedVector2Array = path["points"]
	var closed: bool = path["closed"]
	var length := Contours.length(pts, closed)
	var rooms := PackedFloat32Array()
	for f in [0.2, 0.4, 0.6, 0.8]:
		rooms.append(_side_room(pts, closed, length * f, map))
	rooms.sort()
	return rooms[1]


## A line stone's radius at arc length s along a path (the i-th stone).
static func _radius(field: Dictionary, prof: Dictionary, s: float, i: int) -> float:
	var r: float = prof["r"]
	var length: float = prof["length"]
	# Where along its stroke, from the stroke's inner end (nearer the center).
	var t := lerpf(prof.get("t0", 0.0), prof.get("t1", 1.0), clampf(s / maxf(1.0, length), 0.0, 1.0))
	var out := r
	match prof.get("profile", "flat"):
		"pearls":
			out = r if i % 2 == 0 else r * 0.6
		"swell", "pinch", "grow", "shrink":
			out = r * _scale(prof["profile"], t)
		"pulse":
			# About two pulses per ten stones, from the middle out either way.
			out = r * lerpf(0.55, 1.0, 0.5 + 0.5 * cos(TAU * (s - length / 2.0) / (r * 11.0)))
		"position":
			# Bold lines keep their size: they are there to be big.
			if not prof["bold"]:
				var p: Vector2 = Contours.sample(prof["pts"], prof["closed"], s)[0]
				out = r * _place_scale(field, p)
	var fade := r * 6.0
	var loose: Array = prof["loose"]
	if loose[0] and s < fade:
		out *= lerpf(0.5, 1.0, s / fade)
	if loose[1] and length - s < fade:
		out *= lerpf(0.5, 1.0, maxf(0.0, length - s) / fade)
	# Never dust: at least 1.5 px.
	return maxf(out, maxf(r * MIN_SCALE, 1.5))


## How a stroke's stones change size along it (see _radius): its style's
## profile, or for the styles of one size, a grow, shrink or swell on some
## longer strokes (GRADED_CHANCE), picked by `key` (the lowest class of its
## lines, so symmetric copies pick alike). Grows and shrinks run outward
## from the center; on a stroke that keeps about the same distance from the
## center (an arc around it) they swell or pinch in the middle instead, and
## loops keep one size.
static func _profile(style: String, key: int, seed_value: int, stroke: Dictionary, pitch: float) -> String:
	var length: float = stroke["length"]
	var around: bool = absf(stroke["outer"] - stroke["inner"]) < length * 0.25
	var profile := "flat"
	match style:
		"pearls":
			profile = "pearls"
		"taper":
			profile = "swell"
		"pulse":
			profile = "pulse"
		"radial", "hub":
			profile = "position"
		_:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([seed_value, key, "profile"])
			var roll := rng.randf()
			var pick: String = GRADED[rng.randi_range(0, GRADED.size() - 1)]
			if style == "ramp":
				profile = "grow" if roll < 0.5 else "shrink"
			elif roll < GRADED_CHANCE and length >= pitch * 4.0:
				profile = pick
	if stroke["cycle"] or stroke["bold"]:
		return "pearls" if profile == "pearls" else "flat"
	if around and profile in ["grow", "shrink"]:
		return "swell" if profile == "grow" else "pinch"
	return profile


## Size scale of a graded profile at t (0 at a stroke's inner end, 1 at its
## outer one).
static func _scale(profile: String, t: float) -> float:
	match profile:
		"swell":
			return lerpf(MIN_SCALE, GROWN_SCALE, sin(PI * t))
		"pinch":
			return lerpf(GROWN_SCALE, MIN_SCALE, sin(PI * t))
		"grow":
			return lerpf(MIN_SCALE, GROWN_SCALE, t)
		"shrink":
			return lerpf(GROWN_SCALE, MIN_SCALE, t)
	return 1.0


## Length / width of a style's line stones.
static func _aspect(style: String) -> float:
	match style:
		"marquise", "lozenge":
			return 1.8
		"baguette", "emerald":
			return 1.6
	return 1.0


## Strokes: lines joined through the junctions where they carry straight on
## (the two ends there that meet within STROKE_TURN of a straight line, the
## straightest pair first), as a pen would draw them. Returns
## {"list": [{paths, length, inner, outer, cycle}], "of": {path: [stroke,
## t at its first point, t at its last]}, "node_t": {junction: [stroke, t]}}
## where t runs 0..1 from the stroke's end nearer the center (inner and
## outer: the two ends' distances from it).
static func _strokes(paths: Array, node_paths: PackedInt32Array, center: Vector2, r: float) -> Dictionary:
	# Each end's way out of its junction.
	var at_node := {}
	for k in paths.size():
		var pts: PackedVector2Array = paths[k]["points"]
		if paths[k]["closed"]:
			continue
		var length := Contours.length(pts, false)
		var d := minf(r * 3.0, length / 2.0)
		for e in 2:
			var n: int = paths[k]["ends"][e]
			if n < 0:
				continue
			var tip: Vector2 = pts[0] if e == 0 else pts[pts.size() - 1]
			var into: Vector2 = Contours.sample(pts, false, d if e == 0 else length - d)[0]
			if not at_node.has(n):
				at_node[n] = []
			at_node[n].append([k * 2 + e, (into - tip).angle()])
	var partner := {}
	for n: int in at_node:
		var ends_here: Array = at_node[n]
		var pairs := []
		for i in ends_here.size():
			for j in i:
				var bend := absf(angle_difference(ends_here[i][1], ends_here[j][1] + PI))
				if bend < STROKE_TURN:
					pairs.append([bend, ends_here[i][0], ends_here[j][0]])
		pairs.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		for pr: Array in pairs:
			if not partner.has(pr[1]) and not partner.has(pr[2]):
				partner[pr[1]] = pr[2]
				partner[pr[2]] = pr[1]
	var out := {"list": [], "of": {}, "node_t": {}}
	var done := {}
	for k0 in paths.size():
		if done.has(k0):
			continue
		# Back to the stroke's first line (or round a loop to this one).
		var start := [k0, 0]
		var cycle: bool = paths[k0]["closed"]
		while not cycle and partner.has(start[0] * 2 + start[1]):
			var q: int = partner[start[0] * 2 + start[1]]
			if q / 2 == k0:
				cycle = true
				break
			start = [q / 2, 1 - q % 2]
		# Then along it: each line in order, entered at end `from`.
		var run := []
		var cur := start
		while true:
			run.append(cur)
			done[cur[0]] = true
			if paths[cur[0]]["closed"]:
				break
			var exit_key: int = cur[0] * 2 + (1 - cur[1])
			if not partner.has(exit_key):
				break
			var q: int = partner[exit_key]
			if done.has(q / 2):
				break
			cur = [q / 2, q % 2]
		var total := 0.0
		var lengths := []
		for e: Array in run:
			lengths.append(Contours.length(paths[e[0]]["points"], paths[e[0]]["closed"]))
			total += lengths[-1]
		total = maxf(total, 1.0)
		var first: Array = run[0]
		var last: Array = run[-1]
		var p0: PackedVector2Array = paths[first[0]]["points"]
		var p1: PackedVector2Array = paths[last[0]]["points"]
		var a_end: Vector2 = p0[0] if first[1] == 0 else p0[p0.size() - 1]
		var b_end: Vector2 = p1[p1.size() - 1] if last[1] == 0 else p1[0]
		var flip := a_end.distance_to(center) > b_end.distance_to(center)
		var id: int = out["list"].size()
		var ks := []
		var o := 0.0
		for i in run.size():
			var e: Array = run[i]
			var t_a := o / total
			var t_b: float = (o + lengths[i]) / total
			if flip:
				t_a = 1.0 - t_a
				t_b = 1.0 - t_b
			# t at the line's own first and last points.
			out["of"][e[0]] = [id, t_a, t_b] if e[1] == 0 else [id, t_b, t_a]
			ks.append(e[0])
			o += lengths[i]
			if i < run.size() - 1 and not paths[e[0]]["closed"]:
				var n: int = paths[e[0]]["ends"][1 - e[1]]
				if n >= 0 and node_paths[n] == 2:
					out["node_t"][n] = [id, t_b]
		out["list"].append({"paths": ks, "length": total, "inner": minf(a_end.distance_to(center),
				b_end.distance_to(center)), "outer": maxf(a_end.distance_to(center), b_end.distance_to(center)),
				"cycle": cycle})
	return out


## Picks the bold lines: classes of lines through the middle (BOLD_REACH),
## long enough for a handful of stones, whose areas have room for bigger
## stones. A bold stone may take up to half of the narrower neighboring
## area's width (two thirds, a little further out, when that finds too
## few). Up to `count` classes, spread from the center outward and kept
## apart from each other. Returns {class: stone radius}.
static func _bold_classes(paths: Array, path_class: PackedInt32Array, map: RegionMap, r: float, gap: float,
		center: Vector2, far: float, count: int, seed_value: int) -> Dictionary:
	var out := {}
	if count <= 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "bold lines"])
	var info := {}
	for k in paths.size():
		var pts: PackedVector2Array = paths[k]["points"]
		var closed: bool = paths[k]["closed"]
		var c: int = path_class[k]
		if not info.has(c):
			info[c] = {"length": 0.0, "dist": 0.0, "n": 0, "rooms": PackedFloat32Array()}
		var e: Dictionary = info[c]
		var length := Contours.length(pts, closed)
		e["length"] += length
		e["n"] += 1
		var mid := 0.0
		for q in pts:
			mid += q.distance_to(center)
		e["dist"] += mid / pts.size()
		for f in [0.2, 0.4, 0.6, 0.8]:
			e["rooms"].append(_side_room(pts, closed, length * f, map))
	var targets := {}
	for c: int in info:
		targets[c] = r * BOLD_SIZES[rng.randi_range(0, BOLD_SIZES.size() - 1)]
	var chosen := []
	# First lines through the middle whose areas keep at least half their
	# width; if that finds too few, lines a little further out whose areas
	# keep a third.
	for tries in [[BOLD_REACH, 0.5], [BOLD_REACH_MORE, 0.35]]:
		var reach: float = far * tries[0]
		var keep: float = tries[1]
		var picks := []
		for c: int in info:
			var e: Dictionary = info[c]
			var dist: float = e["dist"] / e["n"]
			if out.has(c) or dist > reach or e["length"] / e["n"] < r * 10.0:
				continue
			var rooms: PackedFloat32Array = e["rooms"]
			rooms.sort()
			# A stone of radius R leaves the area beside W - R - 1.2 gap of the
			# W - r - 1.2 gap it had (W measured from the line's center).
			var room := rooms[rooms.size() / 4]
			var big := minf(targets[c], (1.0 - keep) * room + keep * r - (1.0 - keep) * 1.2 * gap)
			if big >= r * 1.3:
				picks.append({"class": c, "r": big, "dist": dist, "length": e["length"]})
		# Spread them through the middle: each aims at its own distance from the
		# center and takes the nearest class there, longer ones on ties.
		picks.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["length"] > y["length"])
		for i in count:
			if chosen.size() >= count:
				break
			var aim := far * BOLD_REACH * (i + 0.5) / count
			var best: Dictionary = {}
			for p: Dictionary in picks:
				var near := out.has(p["class"])
				for q: Dictionary in chosen:
					if absf(p["dist"] - q["dist"]) < (p["r"] + q["r"]) * 2.0:
						near = true
				if not near and (best.is_empty() or absf(p["dist"] - aim) < absf(best["dist"] - aim) - r):
					best = p
			if not best.is_empty():
				chosen.append(best)
				out[best["class"]] = best["r"]
		if chosen.size() >= count:
			break
	return out


## How wide the narrower of the two areas beside a line is at arc length s,
## measured from the line's center across to the area's far edge. Sides
## outside the picture's silhouette don't count.
static func _side_room(pts: PackedVector2Array, closed: bool, s: float, map: RegionMap) -> float:
	var at: Array = Contours.sample(pts, closed, s)
	var p: Vector2 = at[0]
	var nrm: Vector2 = (at[1] as Vector2).orthogonal()
	var room := INF
	for side in [-1.0, 1.0]:
		var id := RegionMap.LINE
		for t in range(1, 400):
			var q: Vector2 = p + nrm * side * t
			var l := map.label_at(int(q.x), int(q.y))
			if id == RegionMap.LINE:
				if l == RegionMap.BACKGROUND:
					break
				id = l
			elif l != id:
				room = minf(room, float(t))
				break
	return room


## Size scale at a point for the styles that depend on position: radial
## shrinks toward the picture's center, hub toward the nearest hub.
static func _place_scale(field: Dictionary, p: Vector2) -> float:
	match field["style"]:
		"radial":
			return lerpf(MIN_SCALE, 1.0, clampf(p.distance_to(field["center"]) / field["far"], 0.0, 1.0))
		"hub":
			var best := INF
			for h: Vector2 in field["hubs"]:
				best = minf(best, p.distance_to(h))
			return lerpf(MIN_SCALE, 1.0, clampf(best / field["hub_reach"], 0.0, 1.0))
	return 1.0


## Where a point sits up to the picture's symmetry, plus a size: radial uses
## the distance from the center, mirror the height and distance from the
## axis, none the position itself.
static func _sym_key(p: Vector2, center: Vector2, symmetry: String, size: float) -> Array:
	match symmetry:
		"radial":
			return [p.distance_to(center), 0.0, size]
		"mirror":
			return [p.y, absf(p.x - center.x), size]
	return [p.y, p.x, size]


## Clusters keys that match within `tol` px (and 15% in size) into classes,
## numbered in order of the first key; walks the keys sorted by their first
## value so near-equal copies land together.
static func _classes(keys: Array, tol: float) -> PackedInt32Array:
	var order := range(keys.size())
	order.sort_custom(func(a: int, b: int) -> bool: return keys[a][0] < keys[b][0])
	var out := PackedInt32Array()
	out.resize(keys.size())
	var reps := []  # [key, class]
	var next := 0
	for i: int in order:
		var k: Array = keys[i]
		var found := -1
		for j in range(reps.size() - 1, -1, -1):
			var rk: Array = reps[j][0]
			if k[0] - rk[0] > tol:
				break
			var size_ok: bool = absf(k[2] - rk[2]) <= maxf(tol, 0.15 * maxf(k[2], rk[2]))
			if absf(k[1] - rk[1]) <= tol and size_ok:
				found = reps[j][1]
				break
		if found < 0:
			found = next
			next += 1
		reps.append([k, found])
		out[i] = found
	return out


## True if the background lies within `reach` px on either side of the
## path's middle stretch.
static func _is_outer(pts: PackedVector2Array, map: RegionMap, reach: float) -> bool:
	var n := pts.size()
	var hits := 0
	var tries := 0
	for f in [0.25, 0.5, 0.75]:
		var i := clampi(int(n * f), 0, n - 1)
		var j := clampi(i + 1, 0, n - 1)
		var dir := (pts[j] - pts[maxi(0, i - 1)]).normalized()
		if dir == Vector2.ZERO:
			continue
		tries += 1
		var nrm := dir.orthogonal()
		for side in [-1.0, 1.0]:
			var q: Vector2 = pts[i] + nrm * reach * side
			if map.label_at(int(q.x), int(q.y)) == RegionMap.BACKGROUND:
				hits += 1
				break
	return tries > 0 and hits * 2 >= tries


## Adds a stone unless it would crowd another line stone; crowded stones
## shrink to fit (down to 55%) or are left out.
static func _add(out: Array[Dictionary], hash: Dictionary, cell: float, c: Vector2, rot: float, r: float,
		h: float, shape: String, region: int, gap: float, part: int, step: int = -1, accent := false) -> void:
	var dir := Vector2.from_angle(rot)
	var cx := floori(c.x / cell)
	var cy := floori(c.y / cell)
	var room := INF
	for yy in range(cy - 1, cy + 2):
		for xx in range(cx - 1, cx + 2):
			for s: Dictionary in hash.get(Vector2i(xx, yy), []):
				var sr: float = s["width"] / 2.0
				var sh: float = s["size"] / 2.0 - sr
				var sc := Vector2(s["x"], s["y"])
				var sd := Vector2.from_angle(s["rotation"]) * sh
				var pts := Geometry2D.get_closest_points_between_segments(c - dir * h, c + dir * h, sc - sd, sc + sd)
				room = minf(room, pts[0].distance_to(pts[1]) - sr - gap)
	if room < r:
		if room < r * 0.55 or room < 1.5:
			return
		h = h * room / r
		r = room
	var slot := {
		"id": out.size(),
		"region": region,
		"shape": shape if h > 0.0 or shape == "round" else "round",
		"x": c.x,
		"y": c.y,
		"rotation": wrapf(rot, -PI, PI),
		"size": 2.0 * (r + h),
		"width": 2.0 * r,
		"tone": step if step >= 0 else (1 if accent else 0),
		"seq": step,
		"part": part,
	}
	out.append(slot)
	var key := Vector2i(cx, cy)
	if not hash.has(key):
		hash[key] = []
	hash[key].append(slot)

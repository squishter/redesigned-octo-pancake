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
##   pulse: grows and shrinks in waves as the line runs left to right
##   ramp: small to large along one line, large to small along the next,
##     alternating around the picture
##   radial: stones shrink toward the picture's center
##   hub: stones shrink toward the nearest hub where several lines meet (the
##     middle of a flower, a star's center), so each motif draws inward
## Every style also narrows toward a line's loose end. The caller builds the
## channel around the stones it gets back, so a line is exactly as wide as
## its stones at every point.

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
## Lines that meet at a hub: at least this many.
const HUB_DEGREE := 4
## Bold lines: a few classes of lines through the middle of the picture take
## medium or large stones (times the line stone), to break up the run of
## small ones there. They lie within this share of the picture's reach.
const BOLD_SIZES := [1.7, 2.3]
const BOLD_REACH := 0.55


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
static func place(graph: Dictionary, map: RegionMap, r: float, gap: float, style: String,
		symmetry: String = "none", seed_value: int = 1, bold: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hash := {}
	var cell := r * 4.0
	var nodes: Array = graph["nodes"]
	var paths: Array = graph["paths"]
	var center := Vector2(map.width, map.height) / 2.0
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
	# Ramps alternate direction in order around the picture's center, so they
	# repeat evenly around a symmetric picture.
	var ramp_up := {}
	if style == "ramp":
		var order := range(paths.size())
		var mids := []
		for path in paths:
			var pts: PackedVector2Array = path["points"]
			mids.append((pts[pts.size() / 2] - center).angle())
		order.sort_custom(func(a: int, b: int) -> bool: return mids[a] < mids[b])
		for i in order.size():
			ramp_up[order[i]] = i % 2 == 0
	var field := {"style": style, "r": r, "center": center, "far": far, "hubs": hubs,
			"hub_reach": minf(map.width, map.height) * 0.22}

	var tol := minf(map.width, map.height) * 0.015
	var path_keys := []
	for path in paths:
		var pts: PackedVector2Array = path["points"]
		# A loop's traversal starts anywhere, so key it by its center instead.
		var at := pts[pts.size() / 2]
		if path["closed"]:
			at = Vector2.ZERO
			for q in pts:
				at += q
			at /= pts.size()
		path_keys.append(_sym_key(at, center, symmetry, Contours.length(pts, path["closed"])))
	var path_class := _classes(path_keys, tol)
	var node_keys := []
	for n in nodes.size():
		node_keys.append(_sym_key(nodes[n], center, symmetry, 0.0))
	var node_class := _classes(node_keys, tol)
	var bold_r := _bold_classes(paths, path_class, map, r, gap, center, far, bold, seed_value)
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
	var copies := symmetry != "none" and not style in ["pulse", "ramp"]
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
	for n in nodes.size():
		if node_paths[n] == 0:
			continue
		var silhouette := node_outer[n] * 2 >= node_paths[n]
		var rn := r_node * _place_scale(field, at[n])
		_add(out, hash, cell, at[n], 0.0, rn, 0.0, "round", 1 if silhouette else 0, gap, NODE_PARTS + node_class[n])
	var ctx := {
		"field": field, "r": r, "r_node": r_node, "gap": gap, "cell": cell, "style": style, "outer": outer,
		"path_class": path_class, "bold_r": bold_r, "ramp_up": ramp_up, "seed": seed_value, "rings": rings,
	}
	var laid := {}
	for c: int in by_class:
		for k: int in by_class[c]:
			if copy_of.has(k):
				_copy_line(out, hash, cell, laid[copy_of[k][0]], copy_of[k][1], gap)
			else:
				var before := out.size()
				_lay_line(out, hash, paths[k], k, ctx)
				laid[k] = out.slice(before)
	return out


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


## Lays out the stones along path k (see place; ctx holds its settings).
static func _lay_line(out: Array[Dictionary], hash: Dictionary, path: Dictionary, k: int, ctx: Dictionary) -> void:
	var field: Dictionary = ctx["field"]
	var style: String = ctx["style"]
	var r: float = ctx["r"]
	var r_node: float = ctx["r_node"]
	var gap: float = ctx["gap"]
	var cell: float = ctx["cell"]
	var path_class: PackedInt32Array = ctx["path_class"]
	var bold_r: Dictionary = ctx["bold_r"]
	var pts: PackedVector2Array = path["points"]
	var closed: bool = path["closed"]
	var ends: Array = path["ends"].duplicate()
	# Pulses run left to right (top to bottom for vertical lines).
	if style == "pulse" and not closed:
		var d := pts[pts.size() - 1] - pts[0]
		if d.x < 0.0 or (is_zero_approx(d.x) and d.y < 0.0):
			pts.reverse()
			ends.reverse()
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
		"r": bold_r.get(path_class[k], r),
		"bold": bold_r.has(path_class[k]),
		"loose": [not closed and ends[0] < 0, not closed and ends[1] < 0],
		"up": ctx["ramp_up"].get(k, true),
		"ring": ctx["rings"].has(k),
	}
	var s0 := 0.0
	var s1 := length
	if not closed:
		if ends[0] >= 0:
			s0 = r_node * _place_scale(field, pts[0]) + gap + _radius(field, prof, 0.0, 0) * aspect
		if ends[1] >= 0:
			s1 = length - (r_node * _place_scale(field, pts[pts.size() - 1]) + gap
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


## A line stone's radius at arc length s along a path (the i-th stone).
static func _radius(field: Dictionary, prof: Dictionary, s: float, i: int) -> float:
	var r: float = prof["r"]
	var length: float = prof["length"]
	var t := clampf(s / maxf(1.0, length), 0.0, 1.0)
	var out := r
	# Rings around the center keep one size all the way round, so they stay
	# symmetric; position-based styles are symmetric anyway.
	match "" if prof.get("ring", false) and field["style"] in ["taper", "pulse", "ramp"] else field["style"]:
		"pearls":
			out = r if i % 2 == 0 else r * 0.6
		"taper":
			out = r * lerpf(MIN_SCALE, 1.0, sin(PI * t))
		"pulse":
			# About two pulses per ten stones.
			out = r * lerpf(0.55, 1.0, 0.5 + 0.5 * cos(TAU * s / (r * 11.0)))
		"ramp":
			out = r * lerpf(MIN_SCALE, 1.0, t if prof["up"] else 1.0 - t)
		"radial", "hub":
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


## Picks the bold lines: classes of lines through the middle (BOLD_REACH),
## long enough for a handful of stones, whose areas have room for bigger
## stones. A bold stone may take up to half of the narrower neighboring
## area's width. Up to `count` classes, spread from the center outward and
## kept apart from each other. Returns {class: stone radius}.
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
	var picks := []
	for c: int in info:
		var e: Dictionary = info[c]
		var target: float = r * BOLD_SIZES[rng.randi_range(0, BOLD_SIZES.size() - 1)]
		var dist: float = e["dist"] / e["n"]
		if dist > far * BOLD_REACH or e["length"] / e["n"] < r * 10.0:
			continue
		var rooms: PackedFloat32Array = e["rooms"]
		rooms.sort()
		# The areas beside keep at least half the width they had.
		var room := rooms[rooms.size() / 4]
		var big := minf(target, 0.5 * (room + r) - 0.6 * gap)
		if big >= r * 1.35:
			picks.append({"class": c, "r": big, "dist": dist, "length": e["length"]})
	# Spread them through the middle: each aims at its own distance from the
	# center and takes the nearest class there, longer ones on ties.
	picks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["length"] > b["length"])
	var chosen := []
	for i in count:
		var aim := far * BOLD_REACH * (i + 0.5) / count
		var best: Dictionary = {}
		for p: Dictionary in picks:
			var near := false
			for q: Dictionary in chosen:
				if absf(p["dist"] - q["dist"]) < (p["r"] + q["r"]) * 2.5:
					near = true
			if not near and (best.is_empty() or absf(p["dist"] - aim) < absf(best["dist"] - aim) - r):
				best = p
		if not best.is_empty():
			chosen.append(best)
			out[best["class"]] = best["r"]
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

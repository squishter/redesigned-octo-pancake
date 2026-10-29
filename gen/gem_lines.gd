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

const STYLES := ["beads", "beads", "pearls", "marquise", "baguette", "taper", "pulse", "ramp", "radial", "hub"]
## Junction stones' parts start here, after the lines' own.
const NODE_PARTS := 100000
## Smallest stone, as a share of the full line stone.
const MIN_SCALE := 0.45
## Lines that meet at a hub: at least this many.
const HUB_DEGREE := 4


## graph: Contours.centerlines() of the line mask. map: a RegionMap of the
## lines (its BACKGROUND tells the silhouette apart).
## Returns slots ({id, region, shape, x, y, rotation, size, width, tone, part}) with
## region 0 for inner lines and 1 for the silhouette; the caller renumbers.
## `part` is the line's symmetry class (lines that are copies of each other
## under `symmetry` share one), and junction stones get classes of their own,
## so a line's stones always stay one gem type.
static func place(graph: Dictionary, map: RegionMap, r: float, gap: float, style: String,
		symmetry: String = "none") -> Array[Dictionary]:
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

	var r_node := r * (1.15 if style == "beads" else 1.0)
	for n in nodes.size():
		var silhouette := node_paths[n] > 0 and node_outer[n] * 2 >= node_paths[n]
		var rn := r_node * _place_scale(field, nodes[n])
		_add(out, hash, cell, nodes[n], 0.0, rn, 0.0, "round", 1 if silhouette else 0, gap, NODE_PARTS + node_class[n])
	for k in paths.size():
		var path: Dictionary = paths[k]
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
			"baguette":
				shape = "baguette"
				aspect = 1.6
		var prof := {
			"pts": pts,
			"closed": closed,
			"length": length,
			"loose": [not closed and ends[0] < 0, not closed and ends[1] < 0],
			"up": ramp_up.get(k, true),
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
			continue
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
		var tone := outer[k]
		for i in at_list.size():
			var at := start + at_list[i] * stretch
			var sample: Array = Contours.sample(pts, closed, at)
			var rot: float = (sample[1] as Vector2).angle()
			var rr := _radius(field, prof, at, i)
			var h := rr * (aspect - 1.0)
			_add(out, hash, cell, sample[0], rot, rr, h, shape, tone, gap, path_class[k])
	return out


## A line stone's radius at arc length s along a path (the i-th stone).
static func _radius(field: Dictionary, prof: Dictionary, s: float, i: int) -> float:
	var r: float = field["r"]
	var length: float = prof["length"]
	var t := clampf(s / maxf(1.0, length), 0.0, 1.0)
	var out := r
	match field["style"]:
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
			var p: Vector2 = Contours.sample(prof["pts"], prof["closed"], s)[0]
			out = r * _place_scale(field, p)
	var fade := r * 6.0
	var loose: Array = prof["loose"]
	if loose[0] and s < fade:
		out *= lerpf(0.5, 1.0, s / fade)
	if loose[1] and length - s < fade:
		out *= lerpf(0.5, 1.0, maxf(0.0, length - s) / fade)
	return maxf(out, r * MIN_SCALE)


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
		h: float, shape: String, region: int, gap: float, part: int) -> void:
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
		if room < r * 0.55 or room < 1.0:
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
		"tone": 0,
		"part": part,
	}
	out.append(slot)
	var key := Vector2i(cx, cy)
	if not hash.has(key):
		hash[key] = []
	hash[key].append(slot)

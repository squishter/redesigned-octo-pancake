class_name Contours
extends RefCounted
## Vector paths from raster fields: iso-lines of a region's distance field
## (marching squares) and centerlines of a line mask (thinning plus a walk of
## the skeleton graph). Gem patterns place stones evenly along these paths.

## 8-neighbor offsets.
const _NX := [1, 1, 0, -1, -1, -1, 0, 1]
const _NY := [0, 1, 1, 1, 0, -1, -1, -1]


## Iso-lines of `field` at each of `levels`, restricted to pixels labeled
## `region` in `labels` (everything else counts as -1, so lines stay inside).
## Field values are sampled at pixel centers. Returns, per level, an Array of
## {"points": PackedVector2Array, "closed": bool}, lightly smoothed.
static func iso_lines(field: PackedFloat32Array, labels: PackedInt32Array, w: int, h: int, region: int,
		bbox: Rect2i, levels: PackedFloat32Array) -> Array:
	var out := []
	var segs := []  # per level: Dictionary edge key -> [other edge keys]
	var pos := []  # per level: Dictionary edge key -> Vector2
	for _l in levels:
		out.append([])
		segs.append({})
		pos.append({})
	if levels.is_empty():
		return out
	var lo := levels[0]
	var hi := levels[levels.size() - 1]
	var x0 := maxi(0, bbox.position.x - 1)
	var y0 := maxi(0, bbox.position.y - 1)
	var x1 := mini(w - 1, bbox.end.x)
	var y1 := mini(h - 1, bbox.end.y)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i := y * w + x
			# Corners: a (x, y), b (x+1, y), c (x+1, y+1), d (x, y+1).
			var va := field[i] if labels[i] == region else -1.0
			var vb := field[i + 1] if labels[i + 1] == region else -1.0
			var vc := field[i + w + 1] if labels[i + w + 1] == region else -1.0
			var vd := field[i + w] if labels[i + w] == region else -1.0
			var mx := maxf(maxf(va, vb), maxf(vc, vd))
			if mx < lo:
				continue
			var mn := minf(minf(va, vb), minf(vc, vd))
			if mn >= hi:
				continue
			for li in levels.size():
				var t := levels[li]
				if t <= mn or t > mx:
					continue
				var code := (1 if va >= t else 0) | (2 if vb >= t else 0) | (4 if vc >= t else 0) | (8 if vd >= t else 0)
				if code == 0 or code == 15:
					continue
				# Edge keys: top (a-b) = 4i, right (b-c) = 4(i+1)+1, bottom (d-c) = 4(i+w),
				# left (a-d) = 4i+1. Shared edges get the same key from both cells.
				var top := 4 * i
				var left := 4 * i + 1
				var bottom := 4 * (i + w)
				var right := 4 * (i + 1) + 1
				var p: Dictionary = pos[li]
				if not p.has(top) and (code & 1) != (code >> 1 & 1):
					p[top] = Vector2(x + 0.5 + _lerp_t(va, vb, t), y + 0.5)
				if not p.has(right) and (code >> 1 & 1) != (code >> 2 & 1):
					p[right] = Vector2(x + 1.5, y + 0.5 + _lerp_t(vb, vc, t))
				if not p.has(bottom) and (code >> 3 & 1) != (code >> 2 & 1):
					p[bottom] = Vector2(x + 0.5 + _lerp_t(vd, vc, t), y + 1.5)
				if not p.has(left) and (code & 1) != (code >> 3 & 1):
					p[left] = Vector2(x + 0.5, y + 0.5 + _lerp_t(va, vd, t))
				var s: Dictionary = segs[li]
				match code:
					1, 14:
						_link(s, top, left)
					2, 13:
						_link(s, top, right)
					3, 12:
						_link(s, left, right)
					4, 11:
						_link(s, right, bottom)
					6, 9:
						_link(s, top, bottom)
					7, 8:
						_link(s, left, bottom)
					5:  # saddle: keep the high corners apart
						_link(s, top, right)
						_link(s, bottom, left)
					10:
						_link(s, top, left)
						_link(s, right, bottom)
	for li in levels.size():
		out[li] = _chains(segs[li], pos[li])
	return out


static func _lerp_t(a: float, b: float, t: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0) if b != a else 0.5


static func _link(s: Dictionary, a: int, b: int) -> void:
	if not s.has(a):
		s[a] = []
	if not s.has(b):
		s[b] = []
	s[a].append(b)
	s[b].append(a)


## Walks linked edge keys into polylines; open chains start at their ends.
static func _chains(s: Dictionary, p: Dictionary) -> Array:
	var out := []
	var seen := {}
	var starts := []
	for k in s:
		if s[k].size() == 1:
			starts.append(k)
	starts.append_array(s.keys())
	for start in starts:
		if seen.has(start):
			continue
		var pts := PackedVector2Array()
		var prev := -1
		var cur: int = start
		var closed := false
		while true:
			seen[cur] = true
			pts.append(p[cur])
			var nxt := -1
			for n in s[cur]:
				if n != prev and not seen.has(n):
					nxt = n
					break
			if nxt < 0:
				closed = pts.size() > 2 and start in s[cur] and prev != start
				break
			prev = cur
			cur = nxt
		if pts.size() >= 2:
			out.append({"points": smooth(pts, closed, 2), "closed": closed})
	return out


## Moving-average smoothing over +-radius points (ends of open paths stay put).
static func smooth(pts: PackedVector2Array, closed: bool, radius: int) -> PackedVector2Array:
	var n := pts.size()
	if n < 3 or radius <= 0:
		return pts
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var sum := Vector2.ZERO
		var k := 0
		for j in range(i - radius, i + radius + 1):
			var jj := j
			if closed:
				jj = posmod(j, n)
			elif j < 0 or j >= n:
				continue
			sum += pts[jj]
			k += 1
		out[i] = sum / k
	if not closed:
		out[0] = pts[0]
		out[n - 1] = pts[n - 1]
	return out


static func length(pts: PackedVector2Array, closed: bool) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	if closed and pts.size() > 1:
		total += pts[pts.size() - 1].distance_to(pts[0])
	return total


## Point and direction (unit tangent) at arc length s along a path.
static func sample(pts: PackedVector2Array, closed: bool, s: float) -> Array:
	var n := pts.size()
	var segs := n if closed else n - 1
	var acc := 0.0
	for i in segs:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var l := a.distance_to(b)
		if acc + l >= s or i == segs - 1:
			var t := clampf((s - acc) / l, 0.0, 1.0) if l > 0.0 else 0.0
			return [a.lerp(b, t), (b - a).normalized() if l > 0.0 else Vector2.RIGHT]
		acc += l
	return [pts[0], Vector2.RIGHT]


## Centerlines of a line mask: thins it to a 1 px skeleton, prunes short
## spurs, and splits it at junctions. Returns
## {"nodes": [Vector2 per junction], "paths": [{points, closed, ends: [node or -1, node or -1]}]}.
static func centerlines(mask: PackedByteArray, w: int, h: int, spur: float) -> Dictionary:
	var skel := _thin(mask, w, h)
	_drop_corners(skel, w, h)
	var graph := _graph(skel, w, h)
	# Prune spurs: short paths with a loose end, attached to a junction.
	for _round in 2:
		var kept := []
		var pruned := false
		for path in graph["paths"]:
			var ends: Array = path["ends"]
			var dangling: bool = (ends[0] < 0) != (ends[1] < 0)
			if dangling and length(path["points"], false) < spur:
				pruned = true
				for q in path["pixels"]:
					skel[q] = 0
			else:
				kept.append(path)
		if not pruned:
			break
		_drop_corners(skel, w, h)
		graph = _graph(skel, w, h)
	for path in graph["paths"]:
		path["points"] = smooth(path["points"], path["closed"], 3)
		path.erase("pixels")
	return graph


## Zhang-Suen thinning. Returns a mask with 1 on skeleton pixels.
static func _thin(mask: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var img := PackedByteArray()
	img.resize(w * h)
	var live := PackedInt32Array()
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			if mask[i]:
				img[i] = 1
				live.append(i)
	var changed := true
	while changed:
		changed = false
		for step in 2:
			var kill := PackedInt32Array()
			for i in live:
				if not img[i]:
					continue
				# p2..p9 clockwise from north.
				var p2 := img[i - w]
				var p3 := img[i - w + 1]
				var p4 := img[i + 1]
				var p5 := img[i + w + 1]
				var p6 := img[i + w]
				var p7 := img[i + w - 1]
				var p8 := img[i - 1]
				var p9 := img[i - w - 1]
				var b := p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
				if b < 2 or b > 6:
					continue
				var a := int(p2 == 0 and p3 == 1) + int(p3 == 0 and p4 == 1) + int(p4 == 0 and p5 == 1) \
						+ int(p5 == 0 and p6 == 1) + int(p6 == 0 and p7 == 1) + int(p7 == 0 and p8 == 1) \
						+ int(p8 == 0 and p9 == 1) + int(p9 == 0 and p2 == 1)
				if a != 1:
					continue
				if step == 0:
					if p2 * p4 * p6 != 0 or p4 * p6 * p8 != 0:
						continue
				else:
					if p2 * p4 * p8 != 0 or p2 * p6 * p8 != 0:
						continue
				kill.append(i)
			for i in kill:
				img[i] = 0
			if not kill.is_empty():
				changed = true
		var next := PackedInt32Array()
		for i in live:
			if img[i]:
				next.append(i)
		live = next
	return img


## Removes staircase corners: a pixel with two orthogonal 4-neighbors that
## touch each other adds nothing to connectivity and fakes a junction.
static func _drop_corners(img: PackedByteArray, w: int, h: int) -> void:
	# Ring order N, NE, E, SE, S, SW, W, NW.
	var offs := PackedInt32Array([-w, -w + 1, 1, w + 1, w, w - 1, -1, -w - 1])
	for i in _pixels(img, w, h):
		var ring := PackedByteArray()
		ring.resize(8)
		var count := 0
		for k in 8:
			ring[k] = img[i + offs[k]]
			count += ring[k]
		if count < 2:
			continue
		if not ((ring[0] and ring[2]) or (ring[2] and ring[4]) or (ring[4] and ring[6]) or (ring[6] and ring[0])):
			continue
		# Neighbors must form one 8-connected group, or removing it would cut a path.
		var groups := 0
		var seen := PackedByteArray()
		seen.resize(8)
		for k in 8:
			if not ring[k] or seen[k]:
				continue
			groups += 1
			var stack := [k]
			seen[k] = 1
			while not stack.is_empty():
				var q: int = stack.pop_back()
				var adj := [(q + 1) % 8, (q + 7) % 8]
				if q % 2 == 0:
					adj.append_array([(q + 2) % 8, (q + 6) % 8])
				for m: int in adj:
					if ring[m] and not seen[m]:
						seen[m] = 1
						stack.append(m)
		if groups == 1:
			img[i] = 0


## Indices of the set pixels of a skeleton (away from the image edge).
static func _pixels(img: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lo := w
	var hi := w * (h - 1)
	var i := img.find(1, lo)
	while i >= 0 and i < hi:
		var x := i % w
		if x > 0 and x < w - 1:
			out.append(i)
		i = img.find(1, i + 1)
	return out


static func _neighbors(img: PackedByteArray, w: int, i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in 8:
		var j: int = i + _NY[k] * w + _NX[k]
		if img[j]:
			out.append(j)
	return out


static func _graph(img: PackedByteArray, w: int, h: int) -> Dictionary:
	var degree := {}
	for i in _pixels(img, w, h):
		degree[i] = _neighbors(img, w, i).size()
	# Junction pixels (3+ neighbors) clump into nodes.
	var node_of := {}
	var nodes := []
	for i: int in degree:
		if degree[i] < 3 or node_of.has(i):
			continue
		var id := nodes.size()
		var stack := [i]
		node_of[i] = id
		var sum := Vector2.ZERO
		var k := 0
		while not stack.is_empty():
			var q: int = stack.pop_back()
			sum += Vector2(q % w + 0.5, q / w + 0.5)
			k += 1
			for j in _neighbors(img, w, q):
				if degree[j] >= 3 and not node_of.has(j):
					node_of[j] = id
					stack.append(j)
		nodes.append(sum / k)
	var paths := []
	var used := {}
	# Paths leaving each junction, then paths from loose ends, then loops.
	var starts := []
	for i: int in node_of:
		for j in _neighbors(img, w, i):
			if not node_of.has(j):
				starts.append([i, j])
	for i: int in degree:
		if degree[i] <= 1 and not node_of.has(i):
			starts.append([-1, i])
	for st in starts:
		var from: int = st[0]
		var first: int = st[1]
		if used.has(first):
			continue
		var pixels := PackedInt32Array()
		var pts := PackedVector2Array()
		if from >= 0:
			pts.append(nodes[node_of[from]])
		var prev := from
		var cur := first
		var end_node := -1
		while true:
			if node_of.has(cur):
				end_node = node_of[cur]
				pts.append(nodes[end_node])
				break
			used[cur] = true
			pixels.append(cur)
			pts.append(Vector2(cur % w + 0.5, cur / w + 0.5))
			var nxt := -1
			# Prefer stepping onto a junction, then onto unvisited pixels.
			for j in _neighbors(img, w, cur):
				if j != prev and node_of.has(j) and not (from >= 0 and node_of[j] == node_of[from] and pixels.size() < 2):
					nxt = j
					break
			if nxt < 0:
				for j in _neighbors(img, w, cur):
					if j != prev and not used.has(j) and not node_of.has(j):
						nxt = j
						break
			if nxt < 0:
				break
			prev = cur
			cur = nxt
		if pts.size() >= 2:
			paths.append({
				"points": pts,
				"closed": false,
				"ends": [node_of[from] if from >= 0 else -1, end_node],
				"pixels": pixels,
			})
	for i: int in degree:
		if used.has(i) or node_of.has(i):
			continue
		var pixels := PackedInt32Array()
		var pts := PackedVector2Array()
		var prev := -1
		var cur := i
		while cur >= 0:
			used[cur] = true
			pixels.append(cur)
			pts.append(Vector2(cur % w + 0.5, cur / w + 0.5))
			var nxt := -1
			for j in _neighbors(img, w, cur):
				if j != prev and not used.has(j):
					nxt = j
					break
			prev = cur
			cur = nxt
		if pts.size() >= 3:
			paths.append({"points": pts, "closed": true, "ends": [-1, -1], "pixels": pixels})
	return {"nodes": nodes, "paths": paths}

class_name PlantSurfaceProjection
extends RefCounted
## Plant adapter for the posed-animal CPU projector. No nodes or GPU needed.
## Each leaf/petal has an organ ID, distinct from its semantic paint family.

const FAMILY_NAMES := ["outline", "stems", "leaves", "petals", "centers", "buds", "midribs", "occlusion"]
const VIEWS := {
	"front": Vector2(0, 15),
	"three_quarter": Vector2(45, 20),
	"side": Vector2(90, 15),
	"back": Vector2(180, 20),
	"high": Vector2(30, 65),
}


static func frame_camera(data: Dictionary, view: String) -> Dictionary:
	if not VIEWS.has(view) or data.vertices.is_empty():
		return {}
	var angles: Vector2 = VIEWS[view] * PI / 180.0
	var direction := Vector3(sin(angles.x) * cos(angles.y), sin(angles.y), cos(angles.x) * cos(angles.y))
	var basis := Basis.looking_at(-direction)
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for point: Vector3 in data.vertices:
		var projected := basis.inverse() * point
		low = low.min(projected)
		high = high.max(projected)
	var center := basis * ((low + high) * .5)
	return {
		"transform": Transform3D(basis, center + direction * 8),
		"size": maxf(high.x - low.x, high.y - low.y) * 1.16,
		"near": .01, "far": 100., "preset": view,
	}


## `min_region` (a share of the projection's area, 0 for off) folds away
## what is too small to hold gems: see _simplify. `veins` adds open lines
## inside leaves and petals (see _veins), so their anatomy reads.
static func project(data: Dictionary, view: String, size := 320, camera_override: Dictionary = {},
		min_region := 0.0, veins := false) -> Dictionary:
	var camera := frame_camera(data, view) if camera_override.is_empty() else camera_override
	if camera.is_empty() or size < 64 or size > 1024:
		return {}
	var raster := AnimalSurfaceProjection._raster(data, camera, size)
	var labels := PackedInt32Array()
	labels.resize(size * size)
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	image.fill(data.palette[0])
	for at in labels.size():
		var triangle: int = raster.triangle[at]
		if triangle < 0:
			continue
		# All three corners have the same semantic label and organ ID.
		var vertex: int = data.triangles[triangle]
		var family: int = data.labels[vertex]
		var part: int = data.parts[vertex]
		labels[at] = part * 8 + family
		raster.parts[at] = part
		image.set_pixel(at % size, at / size, data.palette[family])
	var unfolded: PackedInt32Array = raster.parts.duplicate()
	if min_region > 0.0:
		_simplify(labels, raster.parts, size, maxi(1, int(size * size * min_region)))
		for at in labels.size():
			if labels[at] > 0:
				image.set_pixel(at % size, at / size, data.palette[posmod(labels[at], 8)])
	# Animal depth thresholds are too coarse for overlapping thin petals.
	# Organ IDs give exact visible boundaries even within one paint family.
	var design := AnimalSurfaceProjection._vectors(labels, raster.depth, raster.parts, size)
	for i in design.families.size():
		design.families[i] = posmod(design.families[i], 8)
	var marked := labels
	if veins:
		var drawn := _veins(data, camera, size, labels, unfolded)
		design.polylines.append_array(drawn.polylines)
		design.closed.append_array(drawn.closed)
		design.families.append_array(drawn.families)
		# Area marks stay well off the veins, which are drawn wider than a
		# projection pixel, or they would land on a line.
		marked = labels.duplicate()
		var near: Array = drawn.pixels
		for _ring in VEIN_CLEAR:
			var grown := []
			for at: int in near:
				marked[at] = 0
				grown.append_array(AnimalSurfaceProjection._neighbors(at, size))
			near = grown.filter(func(at: int) -> bool: return marked[at] != 0)
		for at: int in near:
			marked[at] = 0
	design.marks = AnimalSurfaceProjection._marks(marked, size)
	if veins:
		design.marks = _one_mark_each(design.marks, labels, size)
	# Each mark also says which organ it is on (a flower head with its
	# center, a leaf), so a picture can color every head on its own.
	for mark: Dictionary in design.marks:
		mark.organ = (mark.family / 8) / PlantGrowth.STRIDE
		mark.family = posmod(mark.family, 8)
	design.family_names = PackedStringArray(FAMILY_NAMES)
	design.projection_size = size
	design.metadata = data.get("metadata", {}).duplicate(true)
	design.metadata.camera = view
	return {"design": design, "image": image, "labels": labels}


## Folds every visible patch smaller than `least` px into a neighbor, so a
## head of many small florets (a hydrangea, a lavender spike), a rose's
## inner petals or a leaf's midrib become a few areas big enough to fill
## with gems instead of a knot of lines. A patch joins the biggest patch
## beside it on its own organ (its flower head or leaf) if there is one,
## else the biggest beside it at all; smallest first, until none is left
## that has a neighbor. `labels` (part * 8 + family) and `parts` are
## changed in place: a folded patch takes its neighbor's, so no line is
## drawn between them.
static func _simplify(labels: PackedInt32Array, parts: PackedInt32Array, size: int, least: int) -> void:
	for _pass in 8:
		# Connected patches of one label.
		var patch := PackedInt32Array()
		patch.resize(labels.size())
		patch.fill(-1)
		var areas := PackedInt32Array()
		var stack := PackedInt32Array()
		for start in labels.size():
			if labels[start] <= 0 or patch[start] >= 0:
				continue
			var id := areas.size()
			var count := 0
			patch[start] = id
			stack.append(start)
			while not stack.is_empty():
				var at := stack[stack.size() - 1]
				stack.resize(stack.size() - 1)
				count += 1
				for other in AnimalSurfaceProjection._neighbors(at, size):
					if patch[other] < 0 and labels[other] == labels[start]:
						patch[other] = id
						stack.append(other)
			areas.append(count)
		# Each small patch's neighbors, with the px of border they share.
		var beside := {}
		var sample := PackedInt32Array()
		sample.resize(areas.size())
		for at in labels.size():
			var id := patch[at]
			if id < 0:
				continue
			sample[id] = at
			if areas[id] >= least:
				continue
			for other in AnimalSurfaceProjection._neighbors(at, size):
				var oid := patch[other]
				if oid >= 0 and oid != id:
					if not beside.has(id):
						beside[id] = {}
					beside[id][oid] = beside[id].get(oid, 0) + 1
		if beside.is_empty():
			return
		var order := beside.keys()
		order.sort_custom(func(a: int, b: int) -> bool: return areas[a] < areas[b] or (areas[a] == areas[b] and a < b))
		# Smallest first; a patch that has taken another in this pass waits
		# for the next, when its new size is known.
		var into := {}
		var taken := {}
		for id: int in order:
			if taken.has(id):
				continue
			var organ := parts[sample[id]] / PlantGrowth.STRIDE
			var best := -1
			var best_score := -1.0
			for oid: int in beside[id]:
				if into.has(oid):
					continue
				var own := parts[sample[oid]] / PlantGrowth.STRIDE == organ
				var score := float(areas[oid]) * (1000.0 if own else 1.0)
				if score > best_score:
					best_score = score
					best = oid
			if best >= 0:
				into[id] = best
				taken[best] = true
		if into.is_empty():
			return
		for at in labels.size():
			var id := patch[at]
			if id >= 0 and into.has(id):
				var to: int = sample[into[id]]
				labels[at] = labels[to]
				parts[at] = parts[to]


## Open lines that show a plant's anatomy inside its areas, which otherwise
## are bare outlines: each leaf's midrib with pairs of side veins, and a
## line down the middle of each petal. They are traced on the 3D surface
## and kept only where that leaf or petal is the one in view, at least
## VEIN_MARGIN of the projection inside its (folded) area, so they never
## meet an outline: areas are not split, and keep their color. Pieces
## shorter than VEIN_MIN are dropped, and a petal's line that would touch
## another vein is left out (crossing lines could close off a patch).
## Returns {polylines, closed, families, pixels (projection px under them)}.
const VEIN_MARGIN := 0.009
const VEIN_MIN := 0.03
const VEIN_LEVELS := [0.28, 0.46, 0.64]
## Projection px kept clear around veins when placing area marks.
const VEIN_CLEAR := 3


static func _veins(data: Dictionary, camera: Dictionary, size: int, labels: PackedInt32Array,
		unfolded: PackedInt32Array) -> Dictionary:
	var out := {"polylines": [] as Array[PackedVector2Array], "closed": PackedByteArray(),
		"families": PackedInt32Array(), "pixels": []}
	var roots := {}
	for site: Dictionary in data.get("attachments", []):
		roots[int(site.part) / PlantGrowth.STRIDE] = site.root
	# Vertices of each leaf blade, leaf midrib and petal, by part.
	var pieces := {}
	for i in data.labels.size():
		var label: int = data.labels[i]
		if label in [2, 3, 6]:
			var part: int = data.parts[i]
			if not pieces.has(part):
				pieces[part] = {"label": label, "points": []}
			(pieces[part].points as Array).append(data.vertices[i])
	var inside := _inner_distance(labels, size)
	var taken := PackedByteArray()
	taken.resize(size * size)
	var inverse: Transform3D = camera.transform.affine_inverse()
	var to_screen := func(p: Vector3) -> Vector2:
		var q := inverse * p
		return Vector2((q.x / camera.size + 0.5) * size, (-q.y / camera.size + 0.5) * size)
	var parts := pieces.keys()
	parts.sort()
	for part: int in parts:
		var piece: Dictionary = pieces[part]
		if piece.label == 6 or not roots.has(part / PlantGrowth.STRIDE):
			continue
		var leaf: bool = piece.label == 2
		var points := PackedVector3Array(piece.points)
		var root: Vector3 = roots[part / PlantGrowth.STRIDE]
		var base := points[0]
		for p in points:
			if p.distance_squared_to(root) < base.distance_squared_to(root):
				base = p
		var tip := base
		for p in points:
			if p.distance_squared_to(base) > tip.distance_squared_to(base):
				tip = p
		var axis := tip - base
		if axis.length() < 0.0001:
			continue
		var rib: PackedVector3Array = points
		var allowed := [part]
		if leaf and pieces.has(part + 1) and pieces[part + 1].label == 6:
			rib = PackedVector3Array(pieces[part + 1].points)
			allowed.append(part + 1)
		var spine := _spine(rib, base, axis, 0.04 if leaf else 0.12, 0.95 if leaf else 0.88)
		var lines: Array[PackedVector3Array] = [spine]
		if leaf:
			var side := _across(points, axis)
			for t: float in VEIN_LEVELS:
				var from := _spine(rib, base, axis, t, t, 1)[0]
				var reach := _slice(points, base, axis, t + 0.14)
				for sign: float in [-1.0, 1.0]:
					var edge := from
					for p in reach:
						if (p - from).dot(side) * sign > (edge - from).dot(side) * sign:
							edge = p
					if edge != from:
						lines.append(PackedVector3Array([from, from.lerp(edge, 0.82)]))
		var own := PackedByteArray()
		own.resize(size * size)
		for line in lines:
			var screen := PackedVector2Array()
			for p in line:
				screen.append(to_screen.call(p))
			for run in _visible_runs(screen, size, allowed, unfolded, inside):
				var pixels: Array = run.pixels
				if not leaf and pixels.any(func(at: int) -> bool: return taken[at] and not own[at]):
					continue
				for at: int in pixels:
					own[at] = 1
				var normalized := PackedVector2Array()
				for q: Vector2 in run.points:
					normalized.append(q * (2.0 / size) - Vector2.ONE)
				out.polylines.append(AnimalSurfaceProjection._smooth(normalized, false))
				out.closed.append(0)
				out.families.append(6 if leaf else 3)
		for at in own.size():
			if own[at]:
				out.pixels.append(at)
				# A little room around each line, for the next piece's test.
				for other in AnimalSurfaceProjection._neighbors(at, size):
					taken[other] = 1
				taken[at] = 1
	return out


## Keeps the first mark in each connected area of `labels`: the room kept
## clear around veins can cut an area in two for _marks, but it is one area.
static func _one_mark_each(marks: Array, labels: PackedInt32Array, size: int) -> Array:
	var area := PackedInt32Array()
	area.resize(labels.size())
	area.fill(-1)
	var kept := []
	var count := 0
	for mark: Dictionary in marks:
		var q: Vector2 = (mark.at + Vector2.ONE) * (size / 2.0)
		var start := clampi(floori(q.y), 0, size - 1) * size + clampi(floori(q.x), 0, size - 1)
		if labels[start] <= 0:
			kept.append(mark)
			continue
		if area[start] >= 0:
			continue
		area[start] = count
		var stack := PackedInt32Array([start])
		while not stack.is_empty():
			var at := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			for other in AnimalSurfaceProjection._neighbors(at, size):
				if area[other] < 0 and labels[other] == labels[start]:
					area[other] = count
					stack.append(other)
		count += 1
		kept.append(mark)
	return kept


## Points down the middle of `points` from `low` to `high` (shares of the
## base -> tip axis), the middle of each slice across it.
static func _spine(points: PackedVector3Array, base: Vector3, axis: Vector3, low: float, high: float,
		steps := 10) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in steps:
		var t := lerpf(low, high, float(i) / maxi(1, steps - 1))
		var slice := _slice(points, base, axis, t)
		if slice.is_empty():
			continue
		var mid := Vector3.ZERO
		for p in slice:
			mid += p
		out.append(mid / slice.size())
	if out.is_empty():
		out.append(base + axis * low)
	return out


## The points of `points` near share `t` of the base -> tip axis.
static func _slice(points: PackedVector3Array, base: Vector3, axis: Vector3, t: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var length_sq := axis.length_squared()
	for width: float in [0.05, 0.1, 0.2]:
		for p in points:
			if absf((p - base).dot(axis) / length_sq - t) <= width:
				out.append(p)
		if not out.is_empty():
			return out
	return out


## The direction a blade spreads widest across its axis.
static func _across(points: PackedVector3Array, axis: Vector3) -> Vector3:
	var along := axis.normalized()
	var mean := Vector3.ZERO
	for p in points:
		mean += p
	mean /= points.size()
	var guess := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
	for _i in 6:
		var next := Vector3.ZERO
		for p in points:
			var d := p - mean
			d -= along * d.dot(along)
			next += d * d.dot(guess)
		if next.length() < 0.000001:
			break
		guess = next.normalized()
	return guess


## Distance in px from each pixel to the nearest pixel of another label.
static func _inner_distance(labels: PackedInt32Array, size: int) -> PackedFloat32Array:
	var distance := PackedFloat32Array()
	distance.resize(labels.size())
	distance.fill(float(size))
	for at in labels.size():
		if labels[at] <= 0:
			distance[at] = 0
			continue
		for other in AnimalSurfaceProjection._neighbors(at, size):
			if labels[other] != labels[at]:
				distance[at] = 0.5
		var x := at % size
		if x == 0 or x == size - 1 or at < size or at >= labels.size() - size:
			distance[at] = 0.5
	for at in labels.size():
		if at % size > 0:
			distance[at] = minf(distance[at], distance[at - 1] + 1)
		if at >= size:
			distance[at] = minf(distance[at], distance[at - size] + 1)
		if at % size > 0 and at >= size:
			distance[at] = minf(distance[at], distance[at - size - 1] + 1.414)
		if at % size < size - 1 and at >= size:
			distance[at] = minf(distance[at], distance[at - size + 1] + 1.414)
	for at in range(labels.size() - 1, -1, -1):
		if at % size < size - 1:
			distance[at] = minf(distance[at], distance[at + 1] + 1)
		if at < labels.size() - size:
			distance[at] = minf(distance[at], distance[at + size] + 1)
		if at % size < size - 1 and at < labels.size() - size:
			distance[at] = minf(distance[at], distance[at + size + 1] + 1.414)
		if at % size > 0 and at < labels.size() - size:
			distance[at] = minf(distance[at], distance[at + size - 1] + 1.414)
	return distance


## The stretches of a screen polyline that lie on one of `allowed` parts
## (so are in view) and well inside its area: [{points, pixels}].
static func _visible_runs(screen: PackedVector2Array, size: int, allowed: Array, unfolded: PackedInt32Array,
		inside: PackedFloat32Array) -> Array:
	var margin := size * VEIN_MARGIN
	var runs := []
	var points := PackedVector2Array()
	var pixels := []
	var length := 0.0
	var samples := PackedVector2Array()
	for i in screen.size() - 1:
		var steps := maxi(1, ceili(screen[i].distance_to(screen[i + 1]) / 1.5))
		for j in steps:
			samples.append(screen[i].lerp(screen[i + 1], float(j) / steps))
	if not screen.is_empty():
		samples.append(screen[-1])
	samples.append(Vector2(-1, -1)) # Ends the last run.
	for q in samples:
		var x := floori(q.x)
		var y := floori(q.y)
		var ok := x >= 0 and y >= 0 and x < size and y < size
		if ok:
			var at := y * size + x
			ok = unfolded[at] in allowed and inside[at] >= margin
		if ok:
			if not points.is_empty():
				length += points[-1].distance_to(q)
			# Every few px is enough for a line; smoothing does the rest.
			if points.is_empty() or points[-1].distance_to(q) >= 3.0:
				points.append(q)
			pixels.append(y * size + x)
			continue
		if points.size() >= 2 and length >= size * VEIN_MIN:
			runs.append({"points": points, "pixels": pixels})
		points = PackedVector2Array()
		pixels = []
		length = 0.0
	return runs

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
## what is too small to hold gems: see _simplify.
static func project(data: Dictionary, view: String, size := 320, camera_override: Dictionary = {},
		min_region := 0.0) -> Dictionary:
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
	design.marks = AnimalSurfaceProjection._marks(labels, size)
	for mark: Dictionary in design.marks:
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

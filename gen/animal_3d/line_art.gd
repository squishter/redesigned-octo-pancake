class_name AnimalSurfaceProjection
extends RefCounted
## Orthographic visibility, continuous skin markings and a shared boundary
## graph. Pure data: safe on the generator's worker thread, with no viewport.


static func project(
	data: Dictionary, camera: Dictionary, coat: AnimalSurfaceCoat, size := 320
) -> Dictionary:
	if coat == null or camera.is_empty() or size < 64 or size > 1024:
		return {}
	var raster := _raster(data, camera, size)
	var labels := PackedInt32Array()
	labels.resize(size * size)
	var colors := PackedColorArray()
	colors.resize(size * size)
	colors.fill(coat.palette[0])
	var light := Vector3(-0.3, 0.8, 0.5).normalized()
	for at in labels.size():
		var triangle: int = raster.triangle[at]
		if triangle < 0:
			continue
		var weights: Vector3 = raster.weights[at]
		var a: int = data.triangles[triangle]
		var b: int = data.triangles[triangle + 1]
		var c: int = data.triangles[triangle + 2]
		var original: Color = (
			data.colors[a] * weights.x + data.colors[b] * weights.y + data.colors[c] * weights.z
		)
		var region: int = data.regions[
			a if weights.x >= maxf(weights.y, weights.z) else b if weights.y > weights.z else c
		]
		var protection: float = (
			data.protected[a] * weights.x
			+ data.protected[b] * weights.y
			+ data.protected[c] * weights.z
		)
		var label := coat.label_at(
			_mix(data.rest, a, b, c, weights),
			_mix(data.coat_coordinates, a, b, c, weights),
			_mix(data.face_coordinates, a, b, c, weights),
			region,
			original,
			protection
		)
		labels[at] = label
		var normal := _mix(data.normals, a, b, c, weights).normalized()
		var color: Color = (
			original.linear_to_srgb()
			if coat.style == "source" or protection > 0.5
			else coat.palette[label]
		)
		colors[at] = color * (0.58 + 0.42 * maxf(0, normal.dot(light)))
		colors[at].a = 1.0
		raster.parts[at] = region
	_clean(labels, size)
	var design := _vectors(labels, raster.depth, raster.parts, size)
	design.marks = _marks(labels, size)
	design.family_names = (
		PackedStringArray(AnimalSurfaceCoat.LABELS) + PackedStringArray(["anatomy"])
	)
	design.family_names[0] = "outline"
	design.coat = coat.metadata()
	design.projection_size = size
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for at in colors.size():
		image.set_pixel(at % size, at / size, colors[at])
	return {"design": design, "image": image, "labels": labels, "depth": raster.depth}


static func _mix(values: PackedVector3Array, a: int, b: int, c: int, w: Vector3) -> Vector3:
	return values[a] * w.x + values[b] * w.y + values[c] * w.z


static func line_image(design: Dictionary, size := 640) -> Image:
	var mask := LineRaster.rasterize(
		design.polylines, design.closed, Vector2i(size, size), 1.8, 0.0
	)
	for index in mask.size():
		mask[index] = 255 - mask[index]
	return Image.create_from_data(size, size, false, Image.FORMAT_L8, mask)


static func _raster(data: Dictionary, camera: Dictionary, size: int) -> Dictionary:
	var screen := PackedVector3Array()
	var inverse: Transform3D = camera.transform.affine_inverse()
	for vertex: Vector3 in data.vertices:
		var p := inverse * vertex
		screen.append(
			Vector3((p.x / camera.size + 0.5) * size, (-p.y / camera.size + 0.5) * size, -p.z)
		)
	var depth := PackedFloat32Array()
	depth.resize(size * size)
	depth.fill(INF)
	var triangles := PackedInt32Array()
	triangles.resize(size * size)
	triangles.fill(-1)
	var weights := PackedVector3Array()
	weights.resize(size * size)
	var parts := PackedInt32Array()
	parts.resize(size * size)
	for index in range(0, data.triangles.size(), 3):
		if data.colors[data.triangles[index]].a < 0.4:
			continue
		var a := screen[data.triangles[index]]
		var b := screen[data.triangles[index + 1]]
		var c := screen[data.triangles[index + 2]]
		var low := Vector2i(
			maxi(0, floori(minf(a.x, minf(b.x, c.x)))), maxi(0, floori(minf(a.y, minf(b.y, c.y))))
		)
		var high := Vector2i(
			mini(size - 1, ceili(maxf(a.x, maxf(b.x, c.x)))),
			mini(size - 1, ceili(maxf(a.y, maxf(b.y, c.y))))
		)
		var denominator := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(denominator) < 0.000001:
			continue
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var wa := (
					((b.y - c.y) * (x + 0.5 - c.x) + (c.x - b.x) * (y + 0.5 - c.y)) / denominator
				)
				var wb := (
					((c.y - a.y) * (x + 0.5 - c.x) + (a.x - c.x) * (y + 0.5 - c.y)) / denominator
				)
				var wc := 1 - wa - wb
				if minf(wa, minf(wb, wc)) < -0.000001:
					continue
				var z := wa * a.z + wb * b.z + wc * c.z
				var at := y * size + x
				if z < camera.near or z > camera.far or z >= depth[at]:
					continue
				depth[at] = z
				triangles[at] = index
				weights[at] = Vector3(wa, wb, wc)
	return {"depth": depth, "triangle": triangles, "weights": weights, "parts": parts}


static func _clean(labels: PackedInt32Array, size: int) -> void:
	var seen := PackedByteArray()
	seen.resize(labels.size())
	for start in labels.size():
		if seen[start] or labels[start] == 0:
			continue
		var label := labels[start]
		var queue := PackedInt32Array([start])
		seen[start] = 1
		var next := 0
		while next < queue.size():
			var at := queue[next]
			next += 1
			for other in _neighbors(at, size):
				if not seen[other] and labels[other] == label:
					seen[other] = 1
					queue.append(other)
		var minimum := maxi(3, roundi(size * size / 7000.0)) if label < 4 else 2
		if label != 1 and queue.size() < minimum:
			for at in queue:
				labels[at] = 1


static func _neighbors(at: int, size: int) -> PackedInt32Array:
	var values := PackedInt32Array()
	if at % size > 0:
		values.append(at - 1)
	if at % size < size - 1:
		values.append(at + 1)
	if at >= size:
		values.append(at - size)
	if at < size * (size - 1):
		values.append(at + size)
	return values


static func _marks(labels: PackedInt32Array, size: int) -> Array:
	var distance := PackedFloat32Array()
	distance.resize(labels.size())
	distance.fill(float(size))
	for at in labels.size():
		if labels[at] == 0:
			distance[at] = 0
			continue
		for other in _neighbors(at, size):
			if labels[other] != labels[at]:
				distance[at] = 0.5
		if at % size > 0:
			distance[at] = minf(distance[at], distance[at - 1] + 1)
		if at >= size:
			distance[at] = minf(distance[at], distance[at - size] + 1)
	for at in range(labels.size() - 1, -1, -1):
		if at % size < size - 1:
			distance[at] = minf(distance[at], distance[at + 1] + 1)
		if at < labels.size() - size:
			distance[at] = minf(distance[at], distance[at + size] + 1)
	var seen := PackedByteArray()
	seen.resize(labels.size())
	var marks := []
	for start in labels.size():
		if seen[start] or labels[start] == 0:
			continue
		var queue := PackedInt32Array([start])
		seen[start] = 1
		var next := 0
		var best := start
		while next < queue.size():
			var at := queue[next]
			next += 1
			if distance[at] > distance[best]:
				best = at
			for other in _neighbors(at, size):
				if not seen[other] and labels[other] == labels[start]:
					seen[other] = 1
					queue.append(other)
		if distance[best] >= 1.5:
			marks.append(
				{
					"at":
					(
						(Vector2(best % size, best / size) + Vector2.ONE * 0.5) * (2.0 / size)
						- Vector2.ONE
					),
					"family": labels[best]
				}
			)
	return marks


static func _vectors(
	labels: PackedInt32Array, depth: PackedFloat32Array, parts: PackedInt32Array, size: int
) -> Dictionary:
	var edges := {}
	var edge_families := {}
	for y in range(size - 1):
		for x in range(size - 1):
			var at := y * size + x
			for offset in [1, size]:
				var other: int = at + offset
				var different := labels[at] != labels[other]
				var both := labels[at] > 0 and labels[other] > 0
				var occluded: bool = (
					both and parts[at] != parts[other] and absf(depth[at] - depth[other]) > 0.035
				)
				if not different and not occluded:
					continue
				var family := 0 if not both else maxi(labels[at], labels[other]) if different else 7
				var a: int = y * (size + 1) + x + 1 if offset == 1 else (y + 1) * (size + 1) + x
				var b: int = a + (size + 1 if offset == 1 else 1)
				if not edges.has(a):
					edges[a] = []
				if not edges.has(b):
					edges[b] = []
				edges[a].append(b)
				edges[b].append(a)
				edge_families[Vector2i(a, b)] = family
	var seen := {}
	var polylines: Array[PackedVector2Array] = []
	var closed := PackedByteArray()
	var families := PackedInt32Array()
	var starts: Array = edges.keys().filter(func(at): return edges[at].size() != 2)
	starts.append_array(edges.keys())
	for start: int in starts:
		for neighbor: int in edges[start]:
			var key := Vector2i(mini(start, neighbor), maxi(start, neighbor))
			if seen.has(key):
				continue
			var family: int = edge_families[key]
			var path := PackedInt32Array([start])
			var current := start
			var next := neighbor
			while true:
				seen[Vector2i(mini(current, next), maxi(current, next))] = true
				path.append(next)
				if next == start or edges[next].size() != 2:
					break
				var candidate: int = edges[next][0] if edges[next][0] != current else edges[next][1]
				key = Vector2i(mini(next, candidate), maxi(next, candidate))
				if seen.has(key) or edge_families[key] != family:
					break
				current = next
				next = candidate
			var loop := path[-1] == path[0]
			if loop:
				path.resize(path.size() - 1)
			var points := PackedVector2Array()
			for vertex in path:
				points.append(
					Vector2(vertex % (size + 1), vertex / (size + 1)) * (2.0 / size) - Vector2.ONE
				)
			polylines.append(_smooth(points, loop))
			closed.append(1 if loop else 0)
			families.append(family)
	return {"polylines": polylines, "closed": closed, "families": families}


static func _smooth(points: PackedVector2Array, loop: bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not loop:
		result.append(points[0])
	for index in points.size() if loop else points.size() - 1:
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		result.append(a.lerp(b, 0.25))
		result.append(a.lerp(b, 0.75))
	if not loop:
		result.append(points[-1])
	return result

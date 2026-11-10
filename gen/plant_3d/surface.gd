class_name PlantMeshSurface
extends RefCounted
## A plain-array mesh builder; it never touches nodes or the rendering server.

var vertices := PackedVector3Array()
var triangles := PackedInt32Array()
var labels := PackedInt32Array()
var parts := PackedInt32Array()
var attachments: Array = []


static func frame(axis: Vector3, normal := Vector3.BACK) -> Basis:
	var y := axis.normalized()
	var z := normal - y * y.dot(normal)
	if z.length() < .01:
		z = y.cross(Vector3.RIGHT)
	z = z.normalized()
	return Basis(y.cross(z).normalized(), y, z)


func tube(path: PackedVector3Array, radius: float, part: int) -> void:
	var base := vertices.size()
	const SIDES := 8
	for i in path.size():
		var tangent := path[mini(path.size() - 1, i + 1)] - path[maxi(0, i - 1)]
		var basis := frame(tangent)
		var r := radius * (1. - .42 * i / (path.size() - 1))
		for j in SIDES:
			var angle := TAU * j / SIDES
			_vertex(path[i] + basis * Vector3(r * cos(angle), 0., r * sin(angle)), 1, part)
		if i > 0:
			for j in SIDES:
				var a := base + (i - 1) * SIDES + j
				var b := base + (i - 1) * SIDES + (j + 1) % SIDES
				triangles.append_array(PackedInt32Array([a, b, b + SIDES, a, b + SIDES, a + SIDES]))
	var bottom := vertices.size()
	_vertex(path[0], 1, part)
	_vertex(path[-1], 1, part)
	for j in SIDES:
		var end := base + (path.size() - 1) * SIDES
		triangles.append_array(PackedInt32Array([
			bottom, base + (j + 1) % SIDES, base + j,
			bottom + 1, end + j, end + (j + 1) % SIDES]))


func component(data: Dictionary, transform: Transform3D, scale: float, part: int,
		bloom := 1., changes: Dictionary = {}) -> void:
	var base := vertices.size()
	var opened: PackedVector3Array = data.open
	var closed: PackedVector3Array = data.closed
	var maturity := bloom * bloom * (3. - 2. * bloom)
	var width: float = changes.get("width", 1.)
	var length: float = changes.get("length", 1.)
	var depth: float = changes.get("depth", 1.)
	var curl: float = changes.get("curl", 0.)
	var twist: float = changes.get("twist", 0.)
	for i in opened.size():
		var point := closed[i].lerp(opened[i], maturity)
		point *= Vector3(width, length, depth)
		point.z += curl * point.y * point.y
		if twist != 0.:
			point = point.rotated(Vector3.UP, twist * point.y)
		_vertex(transform * (point * scale), data.labels[i], part + data.parts[i])
	for index in data.triangles:
		triangles.append(base + index)


func _vertex(point: Vector3, label: int, part: int) -> void:
	vertices.append(point)
	labels.append(label)
	parts.append(part)


func snapshot() -> Dictionary:
	var palette := PackedColorArray()
	for color: String in PlantComponentData.CATALOG.data.palette:
		palette.append(Color(color))
	var colors := PackedColorArray()
	colors.resize(labels.size())
	for i in labels.size():
		colors[i] = palette[labels[i]]
	return {"vertices": vertices, "triangles": triangles, "labels": labels, "parts": parts,
		"colors": colors, "palette": palette, "attachments": attachments}

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


static func load_surface(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	var points := PackedVector3Array()
	for point: Array in parsed.vertices:
		points.append(Vector3(point[0], point[1], point[2]))
	var triangles := PackedInt32Array()
	for triangle: Array in parsed.triangles:
		triangles.append_array(PackedInt32Array(triangle))
	var palette := PackedColorArray()
	for color: String in parsed.palette:
		palette.append(Color(color))
	var labels := PackedInt32Array(parsed.labels)
	var colors := PackedColorArray()
	for label in labels:
		colors.append(palette[label])
	parsed.metadata.seed = int(parsed.metadata.seed)
	parsed.metadata.version = int(parsed.metadata.version)
	if parsed.metadata.has("growth"):
		parsed.metadata.growth.seed = int(parsed.metadata.growth.seed)
		parsed.metadata.growth.version = int(parsed.metadata.growth.version)
	return {
		"vertices": points, "triangles": triangles, "colors": colors,
		"labels": labels, "parts": PackedInt32Array(parsed.parts),
		"palette": palette, "metadata": parsed.metadata,
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


static func project(data: Dictionary, view: String, size := 320, camera_override: Dictionary = {}) -> Dictionary:
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
	design.metadata = data.metadata.duplicate(true)
	design.metadata.camera = view
	return {"design": design, "image": image, "labels": labels}


static func puzzle_lines(result: Dictionary, size := 512) -> Dictionary:
	var design: Dictionary = result.design
	var pixels := Vector2i(size, size)
	var marks := []
	for mark: Dictionary in design.marks:
		marks.append({"at": LineRaster.to_px(mark.at, pixels), "family": mark.family})
	return {
		"width": size, "height": size,
		"mask": LineRaster.rasterize(design.polylines, design.closed, pixels, size / 200.0),
		"motifs": {
			"lines": LineRaster.rasterize_labels(design.polylines, design.closed, design.families,
				pixels, size / 200.0 + 2.),
			"areas": marks,
		},
		"mandala": {
			"seed": int(design.metadata.seed), "variant": "plant_mesh", "symmetry": "none",
			"frame": {}, "plant_mesh": design.metadata,
		},
	}

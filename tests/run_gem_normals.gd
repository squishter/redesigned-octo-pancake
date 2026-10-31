extends SceneTree
## Checks both production shaders against normals of the transformed faces.
## Requires a real renderer (software Vulkan works), e.g.:
## xvfb-run -a godot --rendering-method mobile -s res://tests/run_gem_normals.gd

const PX := 512
const NORMAL_COLOR := """
vec3 gem_color(vec3 facing, vec2 p, vec4 stone, vec4 color, vec2 shine, bool fire) {
	return normalize(facing) * 0.5 + 0.5;
}
"""
var _failures := 0
var _viewport: SubViewport
var _camera: Camera3D
var _instance: MultiMeshInstance3D
var _materials := []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Use a real rendering driver; headless cannot validate GPU normals.")
		quit(1)
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(PX, PX)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 28.0
	_viewport.add_child(_camera)
	_camera.position = Vector3(0.0, 30.0, 0.0)
	_camera.look_at(Vector3.ZERO, Vector3(0.0, 0.0, -1.0))
	_instance = MultiMeshInstance3D.new()
	_viewport.add_child(_instance)
	for path: String in ["res://render/gem.gdshader", "res://render/gem_impostor.gdshader"]:
		# Keep the production vertex, atlas decoding and normal transforms.
		# Replace only the final lighting function with a normal diagnostic.
		var shader := Shader.new()
		shader.code = FileAccess.get_file_as_string(path).replace(
				'#include "res://render/gem_body.gdshaderinc"', NORMAL_COLOR)
		var material := ShaderMaterial.new()
		material.shader = shader
		_materials.append(material)
	_materials[1].set_shader_parameter("samples", 1)
	var checks := 0
	for shape: String in GemCuts.BY_SHAPE:
		for cut: String in ["step", "brilliant"]:
			if cut not in GemCuts.for_shape(shape):
				continue
			for ratio: float in [0.4, 1.0, 1.4]:
				checks += await _check_stone(shape, cut, ratio, 1.0, Vector3.ONE)
	# Placement animations scale uniformly; a parent can also scale the board.
	checks += await _check_stone("kite", "step", 0.625, 0.6, Vector3(1.2, 0.9, 1.1))
	checks += await _check_stone("emerald", "step", 0.625, 1.15, Vector3.ONE)
	print("GPU gem normals: %d face samples, %d failures" % [checks, _failures])
	quit(1 if _failures else 0)


func _check_stone(shape: String, cut: String, ratio: float, animation: float, parent_scale: Vector3) -> int:
	var mesh := GemMesh.get_mesh(shape, cut, ratio)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var flat_mesh := GemMesh.get_outline_mesh(shape, 0.25, ratio)
	var flat_outline := PackedVector2Array()
	for point: Array in GemMesh.girdle_points(shape, roundi(GemMesh.GIRDLE.get(shape, GemMesh.GIRDLE_DEFAULT)
			* GemMesh.LOW_SHARE), 1, ratio):
		flat_outline.append(point[1])
	flat_outline.append(flat_outline[0])
	var basis := Basis(Vector3.UP, 0.37) * Basis.from_scale(Vector3(10.0, 10.0 * minf(ratio, 1.0), 10.0 * ratio) * animation)
	_instance.scale = parent_scale
	var transform := _instance.transform * Transform3D(basis, Vector3.ZERO)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(basis, Vector3.ZERO))
	mm.set_instance_color(0, Color.WHITE)
	mm.set_instance_custom_data(0, Color(0.0, 1.55, 0.0, GemCuts.SHADER_STYLE[cut]))
	_instance.multimesh = mm
	var facets := GemMesh.get_facets(shape, cut, ratio)
	_materials[1].set_shader_parameter("facets", ImageTexture.create_from_image(facets))
	var tile_px := float(facets.get_width())
	_instance.set_instance_shader_parameter("facet_tile", Vector4(1.0, 1.0, GemMesh.FACET_PX, GemMesh.FACET_PX) / tile_px)
	var total := 0
	for flat in [false, true]:
		mm.mesh = flat_mesh if flat else mesh
		_instance.material_override = _materials[int(flat)]
		await process_frame
		await RenderingServer.frame_post_draw
		var image := _viewport.get_texture().get_image()
		var worst := 0.0
		var count := 0
		for i in range(0, vertices.size(), 3):
			var a := transform * vertices[i]
			var b := transform * vertices[i + 1]
			var c := transform * vertices[i + 2]
			var pixel := Vector2i(_camera.unproject_position((a + b + c) / 3.0).floor())
			if pixel.x < 0 or pixel.y < 0 or pixel.x >= PX or pixel.y >= PX:
				continue
			var screen := Vector2(pixel) + Vector2.ONE * 0.5
			var hit: Variant = Geometry3D.ray_intersects_triangle(_camera.project_ray_origin(screen),
					_camera.project_ray_normal(screen), a, b, c)
			if hit == null:
				continue
			var local: Vector3 = transform.affine_inverse() * hit
			var p := Vector2(local.x, local.z)
			var edge := INF
			for j in 3:
				var v := vertices[i + j]
				var w := vertices[i + (j + 1) % 3]
				edge = minf(edge, p.distance_to(Geometry2D.get_closest_point_to_segment(p,
						Vector2(v.x, v.z), Vector2(w.x, w.z))))
			# Stay clear of interpolated atlas edges and pixel coverage boundaries.
			if not flat and edge < 0.022:
				continue
			if flat:
				var local_normal := (vertices[i + 2] - vertices[i]).cross(vertices[i + 1] - vertices[i]).normalized()
				if not _stable_atlas_sample(p, local_normal, facets):
					continue
				if not Geometry2D.is_point_in_polygon(p, flat_outline):
					continue
				var outline_distance := INF
				for j in range(flat_outline.size() - 1):
					outline_distance = minf(outline_distance, p.distance_to(Geometry2D.get_closest_point_to_segment(
							p, flat_outline[j], flat_outline[j + 1])))
				if outline_distance < 0.035:
					continue
			var expected := (c - a).cross(b - a).normalized()
			var color := image.get_pixelv(pixel).srgb_to_linear()
			var actual := (Vector3(color.r, color.g, color.b) * 2.0 - Vector3.ONE).normalized()
			worst = maxf(worst, rad_to_deg(actual.angle_to(expected)))
			count += 1
		var limit := 3.0 if flat else 1.5  # 8-bit atlas and framebuffer quantization.
		var label := "%s %s ratio %.3f %s" % [shape, cut, ratio, "impostor" if flat else "mesh"]
		print("  %s: %d faces, maximum error %.3f degrees" % [label, count, worst])
		if count < 4 or worst > limit:
			_failures += 1
			printerr("FAIL: ", label, " normals differ from the transformed geometry")
		total += count
	return total


static func _stable_atlas_sample(p: Vector2, expected: Vector3, facets: Image) -> bool:
	# Adjacent triangles in a step-cut face are coplanar. Filter only actual
	# facet boundaries, where bilinear atlas sampling intentionally mixes normals.
	var texel := Vector2i(((p * 0.5 + Vector2.ONE * 0.5) * GemMesh.FACET_PX + Vector2.ONE * 0.5).floor())
	for y in 2:
		for x in 2:
			var color := facets.get_pixelv(texel + Vector2i(x, y))
			var normal := Vector3(color.r * 2.0 - 1.0, 0.0, color.g * 2.0 - 1.0)
			normal.y = sqrt(maxf(1.0 - normal.x * normal.x - normal.z * normal.z, 0.0))
			if color.b < 0.5 or normal.dot(expected) < cos(deg_to_rad(2.0)):
				return false
	return true

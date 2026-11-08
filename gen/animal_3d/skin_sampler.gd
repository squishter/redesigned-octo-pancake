class_name AnimalSkinSampler
extends RefCounted
## Reference CPU skinning for pose validation, bounds and later projection.
## Surface UVs remain the imported mesh's immutable per-vertex attributes.

var _space: Node3D
var _surfaces: Array[Dictionary] = []
var _images := {}
var _active_bones := {}


func _init(space: Node3D, model: Node3D) -> void:
	_space = space
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh == null:
			continue
		var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			_register_weights(skeleton, instance.skin, arrays)
			var material := instance.get_active_material(surface) as StandardMaterial3D
			_surfaces.append(
				{
					"instance": instance,
					"skeleton": skeleton,
					"skin": instance.skin,
					"arrays": arrays,
					"material": material,
					"shapes": instance.mesh.surface_get_blend_shape_arrays(surface)
				}
			)
		var parent: Node = instance.get_parent()
		while parent != null and parent != space:
			if parent is BoneAttachment3D and parent.get_parent() is Skeleton3D:
				var arm := parent.get_parent() as Skeleton3D
				var bone := arm.find_bone(parent.bone_name)
				if bone >= 0:
					if not _active_bones.has(arm.get_instance_id()):
						_active_bones[arm.get_instance_id()] = {}
					_active_bones[arm.get_instance_id()][bone] = true
			parent = parent.get_parent()


func affects_geometry(skeleton: Skeleton3D, ancestor: int) -> bool:
	for bone: int in _active_bones.get(skeleton.get_instance_id(), {}):
		var index := bone
		while index >= 0:
			if index == ancestor:
				return true
			index = skeleton.get_bone_parent(index)
	return false


func _register_weights(skeleton: Skeleton3D, skin: Skin, arrays: Array) -> void:
	if skeleton == null or skin == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
		return
	var key := skeleton.get_instance_id()
	if not _active_bones.has(key):
		_active_bones[key] = {}
	var binds := {}
	for i in arrays[Mesh.ARRAY_WEIGHTS].size():
		if arrays[Mesh.ARRAY_WEIGHTS][i] > 0:
			binds[arrays[Mesh.ARRAY_BONES][i]] = true
	for bind: int in binds:
		var bone := skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(bind))
		if bone >= 0:
			_active_bones[key][bone] = true


func sample(attributes := true) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var atlas := PackedVector2Array()
	var flow := PackedVector2Array()
	var colors := PackedColorArray()
	var triangles := PackedInt32Array()
	var palettes := {}
	var inverse := _space.global_transform.affine_inverse()
	for surface in _surfaces:
		var instance: MeshInstance3D = surface.instance
		var skeleton: Skeleton3D = surface.skeleton
		var skin: Skin = surface.skin
		var arrays: Array = surface.arrays
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var shape_weights := []
		for shape in instance.mesh.get_blend_shape_count():
			shape_weights.append(instance.get_blend_shape_value(shape))
		var transform := inverse * instance.global_transform
		var normal_transform := transform.basis.inverse().transposed()
		var palette: Array = []
		var normal_palette: Array = []
		var weighted: bool = (
			skin != null and skeleton != null and arrays[Mesh.ARRAY_WEIGHTS] != null
		)
		if weighted:
			var key := str(skeleton.get_instance_id()) + ":" + str(skin.get_instance_id())
			if not palettes.has(key):
				for bind in skin.get_bind_count():
					var bone := skin.get_bind_bone(bind)
					if bone < 0:
						bone = skeleton.find_bone(skin.get_bind_name(bind))
					assert(bone >= 0, "Skin references a missing bone")
					var matrix := (
						inverse
						* skeleton.global_transform
						* skeleton.get_bone_global_pose(bone)
						* skin.get_bind_pose(bind)
					)
					palette.append(matrix)
					normal_palette.append(matrix.basis.inverse().transposed())
				palettes[key] = [palette, normal_palette]
			else:
				palette = palettes[key][0]
				normal_palette = palettes[key][1]
		var offset := vertices.size()
		var influences: int = (
			arrays[Mesh.ARRAY_WEIGHTS].size() / positions.size() if weighted else 0
		)
		for i in positions.size():
			var point := Vector3.ZERO
			var normal := Vector3.ZERO
			var source_point := positions[i]
			var source_normal: Vector3 = (
				arrays[Mesh.ARRAY_NORMAL][i] if arrays[Mesh.ARRAY_NORMAL] != null else Vector3.UP
			)
			for shape in surface.shapes.size():
				var weight: float = shape_weights[shape]
				if is_zero_approx(weight):
					continue
				var target: Array = surface.shapes[shape]
				var relative: bool = (
					instance.mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
				)
				source_point += (
					(target[Mesh.ARRAY_VERTEX][i] - (Vector3.ZERO if relative else positions[i]))
					* weight
				)
				if attributes and target[Mesh.ARRAY_NORMAL] != null:
					source_normal += (
						(
							target[Mesh.ARRAY_NORMAL][i]
							- (Vector3.ZERO if relative else arrays[Mesh.ARRAY_NORMAL][i])
						)
						* weight
					)
			if weighted:
				for j in influences:
					var weight: float = arrays[Mesh.ARRAY_WEIGHTS][i * influences + j]
					if weight <= 0:
						continue
					var bind: int = arrays[Mesh.ARRAY_BONES][i * influences + j]
					point += (palette[bind] * source_point) * weight
					if attributes:
						normal += (normal_palette[bind] * source_normal) * weight
			else:
				point = transform * source_point
				normal = normal_transform * source_normal
			vertices.append(point)
			if not attributes:
				continue
			normals.append(normal.normalized())
			var uv: Vector2 = (
				arrays[Mesh.ARRAY_TEX_UV][i] if arrays[Mesh.ARRAY_TEX_UV] != null else Vector2.ZERO
			)
			atlas.append(uv)
			flow.append(
				(
					arrays[Mesh.ARRAY_TEX_UV2][i]
					if arrays[Mesh.ARRAY_TEX_UV2] != null
					else Vector2.ZERO
				)
			)
			var color := _color(surface.material, uv)
			if arrays[Mesh.ARRAY_COLOR] != null:
				color *= arrays[Mesh.ARRAY_COLOR][i]
			colors.append(color)
		if attributes:
			if arrays[Mesh.ARRAY_INDEX] != null:
				for i: int in arrays[Mesh.ARRAY_INDEX]:
					triangles.append(offset + i)
			else:
				for i in positions.size():
					triangles.append(offset + i)
	return {
		"vertices": vertices,
		"normals": normals,
		"atlas": atlas,
		"flow": flow,
		"colors": colors,
		"triangles": triangles
	}


func _color(material: StandardMaterial3D, uv: Vector2) -> Color:
	if material == null:
		return Color(0.5, 0.5, 0.5)
	var color := material.albedo_color
	if material.albedo_texture == null:
		return color
	var key := material.albedo_texture.get_instance_id()
	if not _images.has(key):
		var image := material.albedo_texture.get_image()
		if image != null and image.is_compressed():
			image.decompress()
		_images[key] = image
	var image: Image = _images[key]
	if image != null and not image.is_empty():
		var x := mini(image.get_width() - 1, int(fposmod(uv.x, 1.0) * image.get_width()))
		var y := mini(image.get_height() - 1, int(fposmod(uv.y, 1.0) * image.get_height()))
		color *= image.get_pixel(x, y).srgb_to_linear()
	return color

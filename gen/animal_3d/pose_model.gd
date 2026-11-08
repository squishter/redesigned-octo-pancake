class_name AnimalPoseModel
extends Node3D
## A frozen authored pose with bounded, seeded changes on the sourced skeleton.
## Add via AnimalPoseLibrary.spawn(), then call pose(); no animation keeps running.

const CONTROL_NAMES := [
	"heading",
	"look_yaw",
	"look_pitch",
	"head_tilt",
	"neck_yaw",
	"neck_pitch",
	"back_bend",
	"body_pitch",
	"body_roll",
	"stance_width",
	"stance_stagger",
	"tail_sweep",
	"tail_lift",
	"ear_left",
	"ear_right",
	"trunk_sweep",
	"trunk_curl"
]
const LEG_LIMIT := 20.0

var model_id := ""
var source_info := {}
var last_pose := {}
var skeleton: Skeleton3D
var _model: Node3D
var _placement: Node3D
var _placement_base := Transform3D.IDENTITY
var _player: AnimationPlayer
var _sampler: AnimalSkinSampler
var _profile := {}
var _presets := {}
var _nodes: Array[Dictionary] = []
var _legs: Array[Dictionary] = []
var _height := 1.0
var _forward := Vector3.FORWARD
var _right := Vector3.RIGHT
var _head_active := true


func configure(id: String, info: Dictionary, model: Node3D, target_height: float) -> bool:
	model_id = id
	source_info = info.duplicate(true)
	_height = target_height
	_model = model
	_placement = Node3D.new()
	add_child(_placement)
	_placement.add_child(model)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return false
	skeleton = skeletons[0]
	for arm: Skeleton3D in skeletons:
		arm.reset_bone_poses()
		if arm.get_bone_count() > skeleton.get_bone_count():
			skeleton = arm
	for player: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
		player.stop()
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if _player == null:
			_player = player
	_profile = AnimalRigProfiles.get_profile(info.rig)
	if (
		_profile.is_empty()
		or skeleton.find_bone(_profile.head) < 0
		or skeleton.find_bone(_profile.body) < 0
	):
		return false
	_flush()
	_sampler = AnimalSkinSampler.new(self, model)
	var bounds := _bounds(_sampler.sample(false).vertices)
	if bounds.size.y <= 0:
		return false
	var scale_value := target_height / bounds.size.y
	_placement.scale = Vector3.ONE * scale_value
	_placement.position = (
		-Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * scale_value
	)
	_capture_nodes(model)
	_placement_base = _placement.transform
	_resolve_profile()
	_build_presets()
	return true


func available_poses() -> PackedStringArray:
	return PackedStringArray(_presets.keys())


func forward_direction() -> Vector3:
	return _forward


func supported_controls() -> PackedStringArray:
	var names := PackedStringArray(["heading", "phase"])
	if _head_active:
		names.append_array(["look_yaw", "look_pitch", "head_tilt"])
	for group in ["neck", "tail", "ears", "trunk"]:
		if _profile[group].is_empty():
			continue
		match group:
			"neck":
				names.append_array(["neck_yaw", "neck_pitch"])
			"tail":
				names.append_array(["tail_sweep", "tail_lift"])
			"ears":
				names.append_array(["ear_left", "ear_right"])
			"trunk":
				names.append_array(["trunk_sweep", "trunk_curl"])
	if _legs.size() == 4:
		names.append_array(
			["body_pitch", "body_roll", "back_bend", "stance_width", "stance_stagger"]
		)
	elif source_info.locomotion == "free":
		names.append("back_bend")
	return names


func pose(
	preset := "idle", seed_value := 0, amount := 0.65, controls: Dictionary = {}
) -> Dictionary:
	if not _presets.has(preset) or not is_finite(amount):
		return {}
	for key in controls:
		if not key is String:
			return {}
		if (
			(key != "phase" and key not in CONTROL_NAMES)
			or not (controls[key] is float or controls[key] is int)
		):
			return {}
		if not is_finite(float(controls[key])):
			return {}
	amount = clampf(amount, 0, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var values := {}
	for key: String in CONTROL_NAMES:
		values[key] = clampf(float(controls.get(key, rng.randf_range(-1, 1))), -1, 1) * amount
	var phase := clampf(
		float(controls.get("phase", lerpf(0.25, rng.randf_range(0.08, 0.92), amount))), 0, 1
	)
	_reset_source()
	var base: Dictionary = _presets[preset]
	var sample_time: float = lerpf(base.start, base.end, phase)
	if not base.clip.is_empty():
		_player.play(base.clip)
		_player.seek(sample_time, true)
		_player.pause()
	_flush()
	var reference := _capture_state()
	var anchors := _capture_legs()
	var body_factor := 0.0
	var accepted := {}
	if amount > 0:
		for factor in [1.0, 0.5, 0.25, 0.125, 0.0]:
			_restore_bones(reference)
			_apply_offsets(values, factor, preset)
			var result := _fit_legs(anchors, values, factor, reference, preset)
			if result.ok:
				body_factor = factor
				accepted = result
				break
		if accepted.is_empty():
			_restore_bones(reference)
			return {}
	else:
		accepted = {"ok": true, "max_error": 0.0, "max_leg_angle": 0.0, "feet": []}
	var before_turn := _placement.transform
	_placement.rotate_y(deg_to_rad(values.heading * 6.0))
	var turn := _placement.transform * before_turn.affine_inverse()
	for foot: Dictionary in accepted.feet:
		foot.target = turn * foot.target
		foot.position = turn * foot.position
	_flush()
	var posed_bounds := _bounds(_sampler.sample(false).vertices)
	var ground_shift := -posed_bounds.position.y
	if source_info.locomotion != "free":
		_placement.position.y += ground_shift
	else:
		ground_shift = 0.0
	_flush()
	for foot: Dictionary in accepted.feet:
		foot.target.y += ground_shift
		foot.position.y += ground_shift
	last_pose = {
		"version": 1,
		"model": model_id,
		"source_sha256": source_info.sha256,
		"preset": preset,
		"clip": base.clip,
		"time": sample_time,
		"phase": phase,
		"seed": seed_value,
		"amount": amount,
		"controls": values,
		"overrides": controls.duplicate(true),
		"body_factor": body_factor,
		"max_contact_error": accepted.max_error,
		"max_leg_delta_degrees": accepted.max_leg_angle,
		"ground_shift": ground_shift,
		"feet": accepted.feet
	}
	return last_pose.duplicate(true)


func snapshot(attributes := true) -> Dictionary:
	_flush()
	return _sampler.sample(attributes)


func bone_poses() -> Array[Transform3D]:
	return _capture_bones()


func _capture_nodes(node: Node) -> void:
	if node is Node3D:
		var row := {"node": node, "transform": node.transform, "shapes": []}
		if node is MeshInstance3D and node.mesh != null:
			for shape in node.mesh.get_blend_shape_count():
				row.shapes.append(node.get_blend_shape_value(shape))
		_nodes.append(row)
	for child in node.get_children():
		_capture_nodes(child)


func _reset_source() -> void:
	if _player != null:
		_player.stop()
	for row in _nodes:
		row.node.transform = row.transform
		for shape in row.shapes.size():
			row.node.set_blend_shape_value(shape, row.shapes[shape])
	_placement.transform = _placement_base
	for arm: Skeleton3D in _model.find_children("*", "Skeleton3D", true, false):
		arm.reset_bone_poses()


func _resolve_profile() -> void:
	for key in ["spine", "neck", "tail", "ears", "trunk"]:
		var bones := []
		for name_value: String in _profile[key]:
			var index := skeleton.find_bone(name_value)
			if index >= 0 and _sampler.affects_geometry(skeleton, index):
				bones.append(index)
		_profile[key] = bones
	_profile.body = skeleton.find_bone(_profile.body)
	_profile.head = skeleton.find_bone(_profile.head)
	_head_active = _sampler.affects_geometry(skeleton, _profile.head)
	_forward = _bone(_profile.head).origin - _bone(_profile.body).origin
	_forward.y = 0
	_forward = _forward.normalized() if _forward.length() > 0.0001 else Vector3.BACK
	_right = _forward.cross(Vector3.UP).normalized()
	for entry: Dictionary in _profile.legs:
		var upper := skeleton.find_bone(entry.upper)
		var lower := skeleton.find_bone(entry.lower)
		var foot := skeleton.find_bone(entry.foot)
		if mini(upper, mini(lower, foot)) < 0 or skeleton.get_bone_parent(lower) != upper:
			continue
		_legs.append(
			{
				"upper": upper,
				"lower": lower,
				"foot": foot,
				"front": entry.front,
				"direct": skeleton.get_bone_parent(foot) == lower
			}
		)
	# Some exporters call the shoulder-bearing upper spine a neck. Keep those
	# bones under the stance-fitting/backoff path, away from free head gestures.
	var neck := []
	for bone: int in _profile.neck:
		var carries_leg := false
		for leg in _legs:
			var parent: int = leg.upper
			while parent >= 0:
				carries_leg = carries_leg or parent == bone
				parent = skeleton.get_bone_parent(parent)
		if carries_leg:
			_profile.spine.append(bone)
		else:
			neck.append(bone)
	_profile.neck = neck


func _build_presets() -> void:
	_presets = {"rest": {"clip": "", "start": 0.0, "end": 0.0}}
	if _player == null:
		return
	var clips := _player.get_animation_list()
	clips.sort()
	for clip in clips:
		var leaf := clip.get_slice("|", clip.get_slice_count("|") - 1).to_lower()
		var preset := ""
		if leaf in ["idle", "idlenorm"]:
			preset = "idle"
		elif leaf in ["walk", "walking", "walkcycle"]:
			preset = "walk"
		elif leaf in ["eating", "eat", "graze", "idle_headlow", "idle_2_headlow"]:
			preset = "graze"
		elif leaf == "idlesit":
			preset = "sit"
		if not preset.is_empty() and not _presets.has(preset):
			_presets[preset] = {
				"clip": clip, "start": 0.0, "end": _player.get_animation(clip).length
			}
	if source_info.rig == "gobkit":
		for clip in clips:
			if clip != "RESET" and _player.get_animation(clip).length >= 119.0 / 24:
				_presets.idle = {"clip": clip, "start": 0.0, "end": 29.0 / 24}
				_presets.walk = {"clip": clip, "start": 90.0 / 24, "end": 119.0 / 24}
				break
	elif source_info.rig == "toon_cat":
		for clip in clips:
			if clip != "RESET":
				_presets.source = {
					"clip": clip, "start": 0.0, "end": _player.get_animation(clip).length
				}
				break


func _apply_offsets(v: Dictionary, factor: float, preset: String) -> void:
	var grazing := preset == "graze"
	if _head_active:
		_rotate(
			_profile.head, Vector3.UP, v.look_yaw * _profile.look_limit * (0.5 if grazing else 1.0)
		)
		_rotate(_profile.head, _right, v.look_pitch * (2.0 if grazing else 8.0))
		_rotate(_profile.head, _forward, v.head_tilt * 5.0)
	_chain(_profile.neck, Vector3.UP, v.neck_yaw * 5.0)
	_chain(_profile.neck, _right, v.neck_pitch * (1.0 if grazing else 4.0))
	_chain(_profile.tail, Vector3.UP, v.tail_sweep * 28.0)
	_chain(_profile.tail, _right, v.tail_lift * 16.0)
	_chain(_profile.trunk, Vector3.UP, v.trunk_sweep * 12.0)
	_chain(_profile.trunk, _right, v.trunk_curl * 18.0)
	for i in _profile.ears.size():
		_rotate(_profile.ears[i], _forward, v["ear_left" if i == 0 else "ear_right"] * 8.0)
	if _legs.size() == 4 and preset != "sit":
		_rotate(_profile.body, _right, v.body_pitch * 1.7 * factor)
		_rotate(_profile.body, _forward, v.body_roll * 1.2 * factor)
		_chain(_profile.spine, _right, v.back_bend * 2.0 * factor)
	elif source_info.locomotion == "free":
		_chain(_profile.spine, _right, v.back_bend * 3.0)


func _capture_legs() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var minimum := INF
	for leg in _legs:
		var a := _bone(leg.upper)
		var b := _bone(leg.lower)
		var c := _bone(leg.foot)
		minimum = minf(minimum, c.origin.y)
		rows.append(
			{
				"leg": leg,
				"a": a.origin,
				"b": b.origin,
				"c": c.origin,
				"foot_rotation": c.basis.orthonormalized().get_rotation_quaternion(),
				"tip_offset": b.affine_inverse() * c.origin
			}
		)
	for row in rows:
		row.contact = row.c.y <= minimum + _height * 0.06
	return rows


func _fit_legs(
	anchors: Array[Dictionary],
	v: Dictionary,
	factor: float,
	reference: Array[Dictionary],
	preset: String
) -> Dictionary:
	var result := {"ok": true, "max_error": 0.0, "max_leg_angle": 0.0, "feet": []}
	for row in anchors:
		var leg: Dictionary = row.leg
		var target: Vector3 = row.c
		if preset != "sit":
			var side := signf((row.c - _bone(_profile.body).origin).dot(_right))
			target += _right * side * v.stance_width * _height * 0.018 * factor
			target += (
				_forward
				* (1.0 if leg.front else -1.0)
				* v.stance_stagger
				* _height
				* 0.012
				* factor
			)
		if factor > 0 and preset != "sit":
			_solve_leg(row, target)
		var tip: Vector3 = (
			_bone(leg.foot).origin if leg.direct else _bone(leg.lower) * row.tip_offset
		)
		var error := tip.distance_to(target)
		result.max_error = maxf(result.max_error, error)
		for bone: int in [leg.upper, leg.lower]:
			var angle := rad_to_deg(
				reference[bone].rotation.angle_to(skeleton.get_bone_pose_rotation(bone))
			)
			result.max_leg_angle = maxf(result.max_leg_angle, angle)
		result.feet.append(
			{
				"bone": skeleton.get_bone_name(leg.foot),
				"contact": row.contact,
				"target": target,
				"position": tip
			}
		)
	result.ok = result.max_error < _height * 0.002 and result.max_leg_angle <= LEG_LIMIT + 0.01
	return result


func _solve_leg(row: Dictionary, target: Vector3) -> void:
	var leg: Dictionary = row.leg
	if not leg.direct:
		_set_position(leg.foot, target)
	var a := _bone(leg.upper).origin
	var b := _bone(leg.lower).origin
	var tip: Vector3 = _bone(leg.foot).origin if leg.direct else _bone(leg.lower) * row.tip_offset
	var first := a.distance_to(b)
	var second := b.distance_to(tip)
	if minf(first, second) < _height * 0.0001:
		return
	var distance := clampf(
		a.distance_to(target), absf(first - second) + 0.000001, first + second - 0.000001
	)
	var direction := (target - a).normalized()
	var pole: Vector3 = row.b - row.a
	pole -= direction * pole.dot(direction)
	if pole.length() < _height * 0.0001:
		pole = -_forward - direction * (-_forward).dot(direction)
	if pole.length() < 0.000001:
		pole = direction.cross(_right)
	var along := (first * first + distance * distance - second * second) / (2 * distance)
	var knee := (
		a + direction * along + pole.normalized() * sqrt(maxf(0, first * first - along * along))
	)
	_align(leg.upper, b - a, knee - a)
	b = _bone(leg.lower).origin
	tip = _bone(leg.foot).origin if leg.direct else _bone(leg.lower) * row.tip_offset
	_align(leg.lower, tip - b, target - b)
	if leg.direct:
		var rotation := _bone(leg.foot).basis.orthonormalized().get_rotation_quaternion()
		_apply_rotation(leg.foot, row.foot_rotation * rotation.inverse())


func _set_position(bone: int, position: Vector3) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_transform := (
		_bone(parent)
		if parent >= 0
		else global_transform.affine_inverse() * skeleton.global_transform
	)
	skeleton.set_bone_pose_position(bone, parent_transform.affine_inverse() * position)


func _align(bone: int, from: Vector3, to: Vector3) -> void:
	if minf(from.length(), to.length()) > 0.000001:
		_apply_rotation(bone, Quaternion(from.normalized(), to.normalized()))


func _chain(bones: Array, axis: Vector3, degrees: float) -> void:
	for bone: int in bones:
		_rotate(bone, axis, degrees / maxf(1, bones.size()))


func _rotate(bone: int, axis: Vector3, degrees: float) -> void:
	_apply_rotation(bone, Quaternion(axis, deg_to_rad(degrees)))


func _apply_rotation(bone: int, rotation: Quaternion) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var basis := (
		_bone(parent).basis
		if parent >= 0
		else (global_transform.affine_inverse() * skeleton.global_transform).basis
	)
	var frame := basis.orthonormalized().get_rotation_quaternion()
	var delta := frame.inverse() * rotation * frame
	skeleton.set_bone_pose_rotation(
		bone, (delta * skeleton.get_bone_pose_rotation(bone)).normalized()
	)


func _bone(index: int) -> Transform3D:
	return (
		global_transform.affine_inverse()
		* skeleton.global_transform
		* skeleton.get_bone_global_pose(index)
	)


func _capture_bones() -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_pose(bone))
	return poses


func _capture_state() -> Array[Dictionary]:
	var state: Array[Dictionary] = []
	for bone in skeleton.get_bone_count():
		state.append(
			{
				"position": skeleton.get_bone_pose_position(bone),
				"rotation": skeleton.get_bone_pose_rotation(bone),
				"scale": skeleton.get_bone_pose_scale(bone)
			}
		)
	return state


func _restore_bones(poses: Array[Dictionary]) -> void:
	for bone in poses.size():
		skeleton.set_bone_pose_position(bone, poses[bone].position)
		skeleton.set_bone_pose_rotation(bone, poses[bone].rotation)
		skeleton.set_bone_pose_scale(bone, poses[bone].scale)


func _flush() -> void:
	for arm: Skeleton3D in _model.find_children("*", "Skeleton3D", true, false):
		arm.force_update_all_bone_transforms()
	for attachment: BoneAttachment3D in _model.find_children("*", "BoneAttachment3D", true, false):
		attachment.on_skeleton_update()


static func _bounds(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var box := AABB(points[0], Vector3.ZERO)
	for point in points:
		box = box.expand(point)
	return box

extends SceneTree
## Runtime posing, not Blender posing: validate the actual bundled GLBs.
## godot --headless -s res://tests/run_animal_poses.gd -- --out=/tmp/animal-poses

var failures := 0
var out := "/tmp/animal-poses"
var reports := []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("_run")


func _run() -> void:
	_check(AnimalPoseLibrary.model_ids().size() == 37, "complete roster")
	_check(AnimalPoseLibrary.spawn(null, "ultimate_fox") == null, "missing parent rejected")
	_check(AnimalPoseLibrary.spawn(root, "missing") == null, "unknown model rejected")
	_check(AnimalPoseLibrary.spawn(root, "ultimate_fox", NAN) == null, "nonfinite height rejected")
	var preview_ids := [
		"ultimate_fox",
		"ultimate_horse",
		"farm_pug",
		"vol2_cat",
		"daydaze_labrador",
		"daydaze_elephant",
		"daydaze_lion",
		"gobkit_corgi",
		"tuxedo_cat_tuxedo_cat",
		"toon_cat_toon_cat_free"
	]
	for id: String in AnimalPoseLibrary.model_ids():
		var animal := AnimalPoseLibrary.spawn(root, id)
		_check(animal != null, id + " spawn")
		if animal == null:
			continue
		var imported := animal.snapshot()
		# Imported vertices are in bind space, not necessarily mesh-node space.
		# Export this neutral skin for an independent glTF matrix/bind check.
		var neutral := {"vertices": [], "scene": animal.source_info.scene}
		for point: Vector3 in imported.vertices:
			neutral.vertices.append([point.x, point.y, point.z])
		var bind_dir := out.path_join("bind_checks")
		DirAccess.make_dir_recursive_absolute(bind_dir)
		FileAccess.open(bind_dir.path_join(id + ".json"), FileAccess.WRITE).store_string(
			JSON.stringify(neutral)
		)
		animal.pose("rest", 0, 0)
		var rest := animal.snapshot()
		var pose_count := 0
		var max_error := 0.0
		var max_delta := 0.0
		var changed_presets := 0
		var preview := {"source": id, "action": "runtime static variations", "snapshots": []}
		for preset: String in animal.available_poses():
			var zero := animal.pose(preset, 3, 0)
			_check(not zero.is_empty(), id + " " + preset + " baseline")
			var reference := animal.bone_poses()
			var base := animal.snapshot()
			var base_hash := _signature(animal, base)
			animal.pose(preset, 888, 0)
			_check(
				base_hash == _signature(animal, animal.snapshot()),
				id + " zero amount is seed independent"
			)
			var first := animal.pose(preset, 12, 1, {"phase": 0.25})
			var first_data := animal.snapshot()
			var first_hash := _signature(animal, first_data)
			_check(not first.is_empty(), id + " " + preset + " variation")
			_check(
				base.atlas == first_data.atlas and base.flow == first_data.flow,
				id + " " + preset + " stable UVs"
			)
			_check(base.triangles == first_data.triangles, id + " stable topology")
			_check(_finite(first_data.vertices), id + " finite skinned geometry")
			_check(
				_same_lengths(reference, animal.bone_poses(), animal),
				id + " no limb stretching or scaling"
			)
			if animal.source_info.locomotion != "free":
				if first.get("grounding", "surface") == "authored":
					_check(
						_minimum_y(first_data.vertices) >= -0.0001,
						id + " authored motion preserves clearance"
					)
				else:
					_check(absf(_minimum_y(first_data.vertices)) < 0.0001, id + " grounded surface")
			max_error = maxf(max_error, first.get("max_contact_error", INF))
			max_delta = maxf(max_delta, first.get("max_leg_delta_degrees", INF))
			var second := animal.pose(preset, 81, 1, {"phase": 0.25})
			var second_data := animal.snapshot()
			_check(not second.is_empty(), id + " second variation")
			if _distance(first_data.vertices, second_data.vertices) > 0.0001:
				changed_presets += 1
			animal.pose(preset, 12, 1, {"phase": 0.25})
			_check(
				first_hash == _signature(animal, animal.snapshot()),
				id + " deterministic reset after another seed"
			)
			var before := _signature(animal, animal.snapshot())
			await process_frame
			await process_frame
			_check(
				before == _signature(animal, animal.snapshot()),
				id + " pose remains frozen over frames"
			)
			if (
				id in preview_ids
				and preset == ("idle" if "idle" in animal.available_poses() else "rest")
			):
				for seed_value in [0, 12, 81, 104]:
					var metadata := animal.pose(
						preset, seed_value, 0 if seed_value == 0 else 1, {"phase": 0.25}
					)
					preview.snapshots.append(_preview_snapshot(animal.snapshot(), seed_value))
					_check(not metadata.is_empty(), id + " preview pose")
			pose_count += 1
		_check(max_error < 0.00201, id + " foot fitting tolerance")
		_check(max_delta <= AnimalPoseModel.LEG_LIMIT + 0.01, id + " joint limits")
		_check(changed_presets > 0, id + " seed varies visible geometry at a fixed clip phase")
		if id == "daydaze_lion":
			animal.pose("rest", 0, 0)
			var neutral_vertices: PackedVector3Array = animal.snapshot(false).vertices
			var morph_changes := false
			for instance: MeshInstance3D in animal.find_children(
				"*", "MeshInstance3D", true, false
			):
				for shape in instance.mesh.get_blend_shape_count():
					instance.set_blend_shape_value(shape, 1)
					morph_changes = (
						morph_changes
						or _distance(neutral_vertices, animal.snapshot(false).vertices) > 0.0001
					)
					instance.set_blend_shape_value(shape, 0)
			_check(morph_changes, "lion morph targets affect the CPU skin")
		animal.pose("rest", 0, 0)
		_check(
			_distance(rest.vertices, animal.snapshot(false).vertices) < 0.00001,
			id + " reset restores the imported neutral skin, including morphs"
		)
		var before := _signature(animal, animal.snapshot())
		_check(animal.pose("invented pose").is_empty(), id + " unavailable preset rejected")
		_check(animal.pose("rest", 0, NAN).is_empty(), id + " nonfinite amount rejected")
		_check(
			animal.pose("rest", 0, 1, {"look_yaw": INF}).is_empty(),
			id + " nonfinite control rejected"
		)
		_check(
			before == _signature(animal, animal.snapshot()),
			id + " invalid request preserves previous pose"
		)
		var extremes := animal.pose("rest", 2, 7, {"look_yaw": 900, "stance_width": -800})
		_check(
			not extremes.is_empty() and extremes.amount == 1 and extremes.controls.look_yaw == 1,
			id + " oversized finite controls clamped"
		)
		if not preview.snapshots.is_empty():
			FileAccess.open(out.path_join(id + ".json"), FileAccess.WRITE).store_string(
				JSON.stringify(preview)
			)
		reports.append(
			{
				"model": id,
				"presets": pose_count,
				"varying_presets": changed_presets,
				"max_contact_error": max_error,
				"max_leg_delta": max_delta
			}
		)
		print(
			id,
			": ",
			pose_count,
			" presets, ",
			changed_presets,
			" varied; contact error ",
			max_error
		)
		animal.free()
	FileAccess.open(out.path_join("validation.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"failures": failures, "models": reports}, "\t")
	)
	print(
		(
			"%s: %d models, %d failures"
			% ["FAILED" if failures else "PASSED", reports.size(), failures]
		)
	)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)


func _signature(animal: AnimalPoseModel, data: Dictionary) -> int:
	return hash([animal.bone_poses(), data.vertices, data.atlas, data.flow])


func _same_lengths(
	before: Array[Transform3D], after: Array[Transform3D], animal: AnimalPoseModel
) -> bool:
	for i in before.size():
		if not before[i].basis.get_scale().is_equal_approx(after[i].basis.get_scale()):
			return false
		# Independent weighted paw/controller roots are positional goals. Other
		# deform-bone translations must remain unchanged, including joint lengths.
		var name_value := animal.skeleton.get_bone_name(i)
		var controller := (
			name_value.begins_with("IK")
			or name_value.begins_with("FrontFoot")
			or name_value.begins_with("BackFoot")
		)
		if not controller and not before[i].origin.is_equal_approx(after[i].origin):
			return false
	return true


func _distance(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size():
		return INF
	var maximum := 0.0
	for i in a.size():
		maximum = maxf(maximum, a[i].distance_to(b[i]))
	return maximum


func _finite(points: PackedVector3Array) -> bool:
	for point in points:
		if not point.is_finite():
			return false
	return true


func _minimum_y(points: PackedVector3Array) -> float:
	var minimum := INF
	for point in points:
		minimum = minf(minimum, point.y)
	return minimum


func _preview_snapshot(data: Dictionary, seed_value: int) -> Dictionary:
	var result := {
		"vertices": [],
		"normals": [],
		"atlas": [],
		"flow": [],
		"colors": [],
		"triangles": [],
		"phase": seed_value
	}
	for key in ["vertices", "normals"]:
		for v: Vector3 in data[key]:
			result[key].append([v.x, -v.z, v.y])  # CPU preview's Z-up convention
	for key in ["atlas", "flow"]:
		for v: Vector2 in data[key]:
			result[key].append([v.x, v.y])
	for color: Color in data.colors:
		result.colors.append([color.r, color.g, color.b])
	for i in range(0, data.triangles.size(), 3):
		result.triangles.append([data.triangles[i], data.triangles[i + 1], data.triangles[i + 2]])
	return result

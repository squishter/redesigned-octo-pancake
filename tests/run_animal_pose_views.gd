extends SceneTree
## Species eligibility, custom targets, gait phases and orthographic crops.

const PreviewIO = preload("res://experiments/animal_3d/pose_preview_io.gd")
var failures := 0
var out := "/tmp/animal-pose-views"
var view_count := 0
var cases := 0
var names := {}
var reports := []
var gait_cases := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("_run")


func _run() -> void:
	for id: String in AnimalPoseLibrary.model_ids():
		var animal := AnimalPoseLibrary.spawn(root, id)
		_check(animal != null, id + " spawn")
		if animal == null:
			continue
		_eligibility(animal)
		var count := 0
		for preset: String in animal.available_poses():
			names[preset] = true
			var result := animal.pose(preset, 12, 0.8, {"phase": 0.37})
			_check(not result.is_empty(), id + " " + preset)
			if result.is_empty():
				continue
			var points: PackedVector3Array = animal.snapshot(false).vertices
			var head: PackedVector3Array = animal.head_vertices()
			if preset == "rest" and head.size() >= 12:
				_portrait_attributes(animal)
			for view: String in AnimalCameraPresets.available(animal):
				var samples := head if view.begins_with("head_") else points
				var aspects := [0.7, 1.0, 1.5] if preset == "rest" else [1.0]
				for aspect: float in aspects:
					var frame := AnimalCameraPresets.frame(animal, view, aspect)
					_check(_contains(frame, samples), id + " " + preset + " " + view + " in frame")
					view_count += 1
				if view.begins_with("head_"):
					_check(head.size() < points.size(), id + " portrait isolates a head region")
			if preset == "look_back":
				_check(
					AnimalCameraPresets.frame(animal, "head_front").is_empty(),
					id + " occluded reverse-head crop withheld"
				)
			if preset == "trot":
				var contacts := []
				for foot: Dictionary in result.custom.feet:
					if foot.contact:
						contacts.append(foot.key)
				_check(contacts.size() == 2, id + " trot has two stance feet")
				_check(
					("front_left" in contacts) == ("hind_right" in contacts),
					id + " trot uses diagonal pairs"
				)
			if result.origin == "procedural":
				_check(
					absf(result.ground_shift) < 0.035, id + " " + preset + " avoids buried joints"
				)
			cases += 1
			count += 1
		if id == "ultimate_husky":
			_target_api(animal)
		if "trot" in animal.available_poses():
			_gait_phases(animal)
		if (
			id
			in [
				"ultimate_husky",
				"ultimate_fox",
				"ultimate_horse",
				"farm_pug",
				"daydaze_labrador",
				"vol2_cat",
				"toon_cat_toon_cat_free",
				"tuxedo_cat_tuxedo_cat",
				"daydaze_lion",
				"daydaze_elephant",
				"gobkit_corgi"
			]
		):
			_export_review(animal)
		reports.append({"model": id, "presets": count})
		print(id, ": ", count, " eligible poses and cameras checked")
		animal.free()
	_check(names.size() >= 20, "broad distinct pose repertoire")
	_studio_preview()
	FileAccess.open(out.path_join("validation.json"), FileAccess.WRITE).store_string(
		JSON.stringify(
			{
				"failures": failures,
				"pose_cases": cases,
				"camera_cases": view_count,
				"distinct_poses": names.keys(),
				"gait_cases": gait_cases,
				"models": reports
			},
			"\t"
		)
	)
	print(
		(
			"%s: %d pose cases, %d camera frames, %d distinct poses, %d failures"
			% ["FAILED" if failures else "PASSED", cases, view_count, names.size(), failures]
		)
	)
	quit(1 if failures else 0)


func _eligibility(animal: AnimalPoseModel) -> void:
	var choices := animal.available_poses()
	var kind := AnimalPoseCatalog.anatomy(animal.model_id)
	if "sit" in choices:
		_check(kind in ["canine", "feline"], animal.model_id + " sitting anatomy")
	if "trot" in choices:
		_check(kind == "equine", animal.model_id + " trotting anatomy")
	if "play_bow" in choices:
		_check(kind == "canine", animal.model_id + " bowing anatomy")
	if "crouch" in choices:
		_check(kind == "feline", animal.model_id + " crouching anatomy")
	if "headbutt" in choices:
		_check(kind in ["bovine", "cervid"], animal.model_id + " headbutt anatomy")
	if "swim" in choices:
		_check(kind == "fish", animal.model_id + " swimming anatomy")
	if "fly" in choices:
		_check(kind == "bat", animal.model_id + " flight anatomy")
	if animal.model_id == "gobkit_corgi":
		_check(
			"sit" not in choices, "single-segment corgi legs do not receive folded sitting recipe"
		)
	if kind in ["equine", "bovine", "cervid"]:
		_check(animal.pose("play_bow").is_empty(), animal.model_id + " rejects canine bow")


func _contains(frame: Dictionary, points: PackedVector3Array) -> bool:
	if frame.is_empty() or not is_finite(frame.size) or frame.size <= 0 or frame.far <= frame.near:
		return false
	var inverse: Transform3D = frame.transform.affine_inverse()
	for point in points:
		var p := inverse * point
		if (
			not p.is_finite()
			or absf(p.x) > frame.size * frame.aspect * 0.50001
			or absf(p.y) > frame.size * 0.50001
		):
			return false
		if -p.z < frame.near - 0.0001 or -p.z > frame.far + 0.0001:
			return false
	return true


func _portrait_attributes(animal: AnimalPoseModel) -> void:
	var full := animal.snapshot()
	var head := animal.portrait_snapshot()
	var source := {}
	for index in full.vertices.size():
		source[[full.vertices[index], full.atlas[index], full.flow[index]]] = true
	for index in head.vertices.size():
		_check(
			source.has([head.vertices[index], head.atlas[index], head.flow[index]]),
			animal.model_id + " portrait keeps posed vertices and their original UVs"
		)
	for index in head.triangles:
		_check(index >= 0 and index < head.vertices.size(), animal.model_id + " portrait topology")
	_check(
		head.triangles.size() < full.triangles.size(), animal.model_id + " body triangles removed"
	)


func _studio_preview() -> void:
	var studio: Variant = load("res://tools/animal_pose_studio.tscn").instantiate()
	root.add_child(studio)
	for id in ["ultimate_husky", "daydaze_elephant", "gobkit_corgi"]:
		for index in studio._models.item_count:
			if studio._models.get_item_metadata(index) == id:
				studio._models.select(index)
		studio._load_model()
		for index in studio._views.item_count:
			if studio._views.get_item_metadata(index) == "head_front":
				studio._views.select(index)
		studio._frame_camera()
		_check(
			not studio._animal.visible and studio._portrait.visible, id + " studio head isolation"
		)
		_check(studio._portrait.mesh.get_surface_count() == 1, id + " studio portrait mesh")
		studio._views.select(studio._views.item_count - 1)
		studio._frame_camera()
		_check(studio._animal.visible and not studio._portrait.visible, id + " studio whole animal")
		_check(studio._camera.far == 100.0, id + " manual camera clears portrait depth clipping")
	studio.free()


func _target_api(animal: AnimalPoseModel) -> void:
	animal.pose("rest", 0, 0)
	var reference := animal.snapshot()
	var legs: Array[Dictionary] = animal._capture_legs()
	var front: Dictionary = legs.filter(func(row): return row.leg.key == "front_left")[0]
	var target: Vector3 = front.c + animal.forward_direction() * 0.015
	var result := animal.pose_targets({"feet": {"front_left": {"at": target, "contact": true}}})
	_check(not result.is_empty(), "explicit custom foot target solved")
	_check(result.definition.feet.front_left.at == target, "custom request saved for reproduction")
	_check(reference.atlas == animal.snapshot().atlas, "target-based pose preserves UVs")
	var before := hash([animal.bone_poses(), animal.snapshot(false).vertices])
	for spec in [
		{"feet": {"missing_leg": {"at": Vector3.ZERO}}},
		{"body": "bad"},
		{"feet": {"front_left": {"at": Vector3(NAN, 0, 0)}}},
		{"feet": {"front_left": {"at": target, "contact": "bad"}}},
		{"feet": {"front_left": {"at": Vector3(10, 10, 10)}}}
	]:
		_check(animal.pose_targets(spec).is_empty(), "invalid/unreachable target rejected")
		_check(
			before == hash([animal.bone_poses(), animal.snapshot(false).vertices]),
			"failed custom request rolls back exactly"
		)


func _gait_phases(animal: AnimalPoseModel) -> void:
	for step in 17:
		var phase := step / 16.0
		for amount in [0.0, 0.8]:
			for preset in ["trot", "gallop"]:
				if preset not in animal.available_poses():
					continue
				var result := animal.pose(preset, 12, amount, {"phase": phase})
				_check(not result.is_empty(), "%s %s phase %.4f" % [animal.model_id, preset, phase])
				gait_cases += 1


func _export_review(animal: AnimalPoseModel) -> void:
	var shots := []
	for preset in [
		"sit",
		"lie_down",
		"play_bow",
		"crouch",
		"stretch",
		"look_back",
		"walk",
		"trot",
		"gallop",
		"jump",
		"kick"
	]:
		if preset not in animal.available_poses():
			continue
		var phases := [0.125, 0.375, 0.625] if preset in ["gallop", "trot"] else [0.25]
		for phase: float in phases:
			if animal.pose(preset, 0, 0, {"phase": phase}).is_empty():
				continue
			shots.append(
				PreviewIO.snapshot(animal, "three_quarter_left", "%s %.3f" % [preset, phase])
			)
	_write(animal.model_id + "_poses", shots)
	shots = []
	var pose_name := "sit" if "sit" in animal.available_poses() else "rest"
	animal.pose(pose_name, 0, 0)
	for view: String in AnimalCameraPresets.available(animal):
		if not view.begins_with("head_"):
			shots.append(PreviewIO.snapshot(animal, view, view))
	_write(animal.model_id + "_views", shots)
	shots = []
	animal.pose("idle" if "idle" in animal.available_poses() else "rest", 0, 0, {"phase": 0.12})
	for view: String in AnimalCameraPresets.available(animal):
		if view.begins_with("head_"):
			shots.append(PreviewIO.snapshot(animal, view, view))
	_write(animal.model_id + "_heads", shots)


func _write(name_value: String, snapshots: Array) -> void:
	if not snapshots.is_empty():
		FileAccess.open(out.path_join(name_value + ".json"), FileAccess.WRITE).store_string(
			JSON.stringify({"source": name_value, "snapshots": snapshots})
		)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

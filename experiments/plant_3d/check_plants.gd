extends SceneTree
## Actual animal projection helpers -> region topology -> collage and kit.
## godot --headless -s res://experiments/plant_3d/check_plants.gd -- --input=/tmp/plant-library-v2

const PlantProjection := preload("res://experiments/plant_3d/projection.gd")

var _input := "/tmp/plant-library-v2"
var _out := ""
var _failures := 0
var _reports := []
var _worker_result := {}
var _pipelines := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--input="):
			_input = argument.trim_prefix("--input=")
	_out = _input.path_join("previews")
	DirAccess.make_dir_recursive_absolute(_out)
	call_deferred("_run")


func _run() -> void:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(_input.path_join("catalog.json")))
	if not catalog is Dictionary:
		printerr("Build the study's meshes first with build_plants.py")
		quit(1)
		return
	_check(catalog.stems.size() == 3, "three branching stem structures")
	_check(catalog.leaves.size() == 24, "twenty-four leaf families")
	_check(catalog.flowers.size() == 37, "thirty-two flowers and five buds")
	_check(catalog.variants.size() == 183, "three additional mutations of all sixty-one families")
	for group: String in ["stems", "leaves", "flowers", "variants"]:
		for entry: Dictionary in catalog[group]:
			var component := PlantProjection.load_surface(_input.path_join(entry.data))
			var component_group: String = entry.recipe.group if entry.has("recipe") else group
			var family: String = entry.get("family", entry.id)
			var view := "high" if component_group == "flowers" else "front"
			if family in ["bell", "trumpet", "calla", "fuchsia", "lavender", "iris", "bleeding_heart"]:
				view = "three_quarter"
			elif family.ends_with("bud") or family == "anthurium":
				view = "front"
			var result := PlantProjection.project(component, view, 256)
			_check_projection(result, "component_" + entry.id, 1)
			if group != "variants":
				var document := GLTFDocument.new()
				var state := GLTFState.new()
				_check(document.append_from_file(_input.path_join(entry.file), state) == OK, entry.id + " GLB imports")
	var surfaces := {}
	for entry: Dictionary in catalog.plants:
		var data := PlantProjection.load_surface(_input.path_join(entry.data))
		_check(not data.is_empty(), entry.id + " loads")
		surfaces[entry.id] = data
		var views: Array = PlantProjection.VIEWS.keys() if entry.pose == "upright" else ["three_quarter"]
		for view: String in views:
			var result := PlantProjection.project(data, view)
			_check_projection(result, entry.id + "_" + view)
			if view == "three_quarter" and entry.pose == "upright":
				_pipeline(result, entry.id)
		# Validate that Godot can import the portable three-group GLBs.
		if entry.pose == "upright":
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			var error := document.append_from_file(_input.path_join(entry.mesh), state)
			_check(error == OK, entry.id + " GLB imports")
			if error == OK:
				var scene := document.generate_scene(state)
				_check(scene.find_children("*", "MeshInstance3D", true, false).size() == 3,
					entry.id + " separate stem, leaf and flower groups")
				scene.free()
	var first: Dictionary = surfaces[catalog.plants[0].id]
	var task := WorkerThreadPool.add_task(func() -> void:
		_worker_result = PlantProjection.project(first, "three_quarter"))
	while not WorkerThreadPool.is_task_completed(task):
		await process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	var main_result := PlantProjection.project(first, "three_quarter")
	_check(_worker_result.labels == main_result.labels, "worker and main thread produce identical visibility")
	_check(_worker_result.design.polylines == main_result.design.polylines, "deterministic contour graph")
	_occlusion()
	FileAccess.open(_out.path_join("validation.json"), FileAccess.WRITE).store_string(JSON.stringify({
		"failures": _failures, "projections": _reports.size(), "puzzle_pairs": _pipelines, "cases": _reports,
	}, "\t"))
	print("%s: %d projections, %d collage/kit pairs, %d failures" % [
		"FAILED" if _failures else "PASSED", _reports.size(), _pipelines, _failures])
	quit(1 if _failures else 0)


func _check_projection(result: Dictionary, name_value: String, minimum_regions := 5) -> void:
	_check(not result.is_empty(), name_value + " projects")
	if result.is_empty():
		return
	var lines := PlantProjection.puzzle_lines(result)
	var map := RegionMap.build(lines.mask, lines.width, lines.height, 0)
	var background: int = map.labels[0]
	var owners := {}
	for mark: Dictionary in lines.motifs.areas:
		var p: Vector2 = mark.at
		var region: int = map.labels[int(p.y) * map.width + int(p.x)]
		if region < 0:
			continue
		_check(region != background, name_value + " organ leaks to background")
		if owners.has(region):
			_check(owners[region] == mark.family, name_value + " different paint families leak together")
		owners[region] = mark.family
	_check(owners.size() >= minimum_regions, name_value + " has paintable organs")
	result.image.save_png(_out.path_join(name_value + "_model.png"))
	AnimalSurfaceProjection.line_image(result.design, 512).save_png(_out.path_join(name_value + "_lines.png"))
	_reports.append({"id": name_value, "regions": map.regions.size(), "marked": owners.size(),
		"paths": result.design.polylines.size()})
	print(name_value, ": ", owners.size(), " paint regions")


func _pipeline(result: Dictionary, name_value: String) -> void:
	_pipelines += 1
	var lines := PlantProjection.puzzle_lines(result, 384)
	var opts := {"theme": "garden", "setting": "metal", "sparsity": 0., "seed": 41}
	# Inject the experiment through the same downstream APIs as posed animals.
	var collage := PictureSources.mandala_collage(41, opts, lines)
	collage.source.plant_mesh = result.design.metadata
	_check(not collage.slots.is_empty(), name_value + " playable collage")
	var image := PictureSources.mandala_image(41, opts, lines)
	image.save_png(_out.path_join(name_value + "_game_colors.png"))
	var kit := KitGenerator.generate(image, {"size": "small", "colors": 10, "seed": 41})
	kit.source = {"variant": "plant_mesh", "plant_mesh": result.design.metadata}
	_check(kit.cells.size() == kit.width * kit.height, name_value + " complete kit")
	var path := _out.path_join(name_value + "_collage.json")
	PatternIO.save(collage, path)
	var replay := PatternIO.load_file(path)
	_check(replay.source.plant_mesh == collage.source.plant_mesh, name_value + " metadata JSON round trip")
	print("  ", collage.slots.size(), " collage slots; ", kit.width, "x", kit.height, " kit")


func _occlusion() -> void:
	# Identical triangles at different depths: the hidden bloom must not add
	# either an outline or a family mark to the frontmost leaf.
	var vertices := PackedVector3Array([
		Vector3(-.4, 0, .1), Vector3(.4, 0, .1), Vector3(0, .8, .1),
		Vector3(-.4, 0, 0), Vector3(.4, 0, 0), Vector3(0, .8, 0),
	])
	var data := {"vertices": vertices, "triangles": PackedInt32Array([0, 1, 2, 3, 4, 5]),
		"colors": PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]),
		"labels": PackedInt32Array([2, 2, 2, 3, 3, 3]), "parts": PackedInt32Array([1, 1, 1, 2, 2, 2]),
		"palette": PackedColorArray([Color.WHITE, Color.GREEN, Color.GREEN, Color.PINK]), "metadata": {}}
	# Use a precisely front-facing frame so the rear triangle stays covered.
	var camera := {"transform": Transform3D(Basis.IDENTITY, Vector3(0, .4, 3)),
		"size": 1., "near": .01, "far": 100.}
	var raster := AnimalSurfaceProjection._raster(data, camera, 128)
	for triangle in raster.triangle:
		_check(triangle < 3, "rear petal does not contribute visible pixels")
	data.triangles = PackedInt32Array([0, 1, 2])
	var front := AnimalSurfaceProjection._raster(data, camera, 128)
	_check(front.depth == raster.depth, "hidden geometry does not change the depth buffer")


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", message)

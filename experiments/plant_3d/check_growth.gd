extends "res://experiments/plant_3d/check_plants.gd"
## Reuse the library's region/puzzle checks for the independent stem controls.


func _initialize() -> void:
	_input = "/tmp/plant-stems-v4"
	super._initialize()


func _run() -> void:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(_input.path_join("catalog.json")))
	if not catalog is Dictionary:
		printerr("Run build_stems.py first")
		quit(1)
		return
	_check(catalog.stems.size() == 9, "nine curve/branch combinations")
	_check(catalog.plants.filter(func(e): return e.group == "matrix").size() == 27, "27 independent bloom combinations")
	for entry: Dictionary in catalog.stems:
		var data := PlantProjection.load_surface(_input.path_join(entry.data))
		_check_projection(PlantProjection.project(data, "front"), entry.id, 1)
	var first := {}
	for entry: Dictionary in catalog.plants:
		var data := PlantProjection.load_surface(_input.path_join(entry.data))
		if first.is_empty():
			first = data
		for view: String in entry.views:
			var result := PlantProjection.project(data, view)
			_check_projection(result, entry.id + "_" + view)
			if entry.pipeline and view == entry.views[0]:
				_pipeline(result, entry.id)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error := document.append_from_file(_input.path_join(entry.mesh), state)
		_check(error == OK, entry.id + " GLB imports")
		if error == OK:
			var scene := document.generate_scene(state)
			_check(scene.find_children("*", "MeshInstance3D", true, false).size() == 3, entry.id + " three mesh groups")
			scene.free()
	var task := WorkerThreadPool.add_task(func() -> void:
		_worker_result = PlantProjection.project(first, "front"))
	while not WorkerThreadPool.is_task_completed(task):
		await process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_check(_worker_result.labels == PlantProjection.project(first, "front").labels, "worker visibility matches")
	FileAccess.open(_out.path_join("validation.json"), FileAccess.WRITE).store_string(JSON.stringify({
		"failures": _failures, "projections": _reports.size(), "puzzle_pairs": _pipelines, "cases": _reports,
	}, "\t"))
	print("%s: %d stem/plant projections, %d puzzle pairs, %d failures" % [
		"FAILED" if _failures else "PASSED", _reports.size(), _pipelines, _failures])
	quit(1 if _failures else 0)

extends "res://experiments/plant_3d/check_plants.gd"
## Fixed camera/scale across each opening progression; actual puzzle topology checks.


func _initialize() -> void:
	_input = "/tmp/plant-blooms"
	super._initialize()


func _run() -> void:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(_input.path_join("catalog.json")))
	if not catalog is Dictionary:
		printerr("Run build_blooms.py first")
		quit(1)
		return
	var entries: Array = catalog.components + catalog.plants
	var surfaces := {}
	var group_points := {}
	for entry: Dictionary in entries:
		var data := PlantProjection.load_surface(_input.path_join(entry.data))
		surfaces[entry.id] = data
		if not group_points.has(entry.frame_group):
			group_points[entry.frame_group] = PackedVector3Array()
		group_points[entry.frame_group].append_array(data.vertices)
	for entry: Dictionary in entries:
		var data: Dictionary = surfaces[entry.id]
		for view: String in entry.views:
			var camera := PlantProjection.frame_camera({"vertices": group_points[entry.frame_group]}, view)
			var result := PlantProjection.project(data, view, 320, camera)
			_check_projection(result, entry.id + "_" + view, 1)
			if entry.get("pipeline", false) and view == entry.views[0]:
				_pipeline(result, entry.id)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		_check(document.append_from_file(_input.path_join(entry.mesh), state) == OK, entry.id + " GLB imports")
	var report := {"failures": _failures, "projections": _reports.size(), "puzzle_pairs": _pipelines, "cases": _reports}
	FileAccess.open(_out.path_join("validation.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("%s: %d bloom projections, %d puzzle pairs, %d failures" % [
		"FAILED" if _failures else "PASSED", _reports.size(), _pipelines, _failures])
	quit(1 if _failures else 0)

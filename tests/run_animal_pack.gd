extends SceneTree
## Run against --main-pack to catch omitted non-resource pose/credit files.


func _initialize() -> void:
	var models: Dictionary = AnimalMeshGenerator.CATALOG.data.models
	var failures := 0
	for id: String in models:
		var info: Dictionary = models[id]
		if (
			not FileAccess.file_exists(info.file)
			or FileAccess.get_sha256(info.file) != info.data_sha256
		):
			failures += 1
			printerr("Missing or changed packaged animal data: ", id)
	for path in [
		"res://assets/animals/CREDITS.md",
		"res://assets/animals/licenses/dreamnoms-tuxedo-cat-CCBY4.md"
	]:
		if not FileAccess.file_exists(path):
			failures += 1
			printerr("Missing packaged attribution: ", path)
	if failures:
		quit(1)
		return
	var design := AnimalMeshGenerator.generate(
		7721, {"model": "ultimate_horse", "pose": "trot", "coat": "pinto", "camera": "side_left"}
	)
	if design.is_empty() or design.polylines.is_empty():
		printerr("Packaged surface projection failed")
		quit(1)
		return
	print(
		"PACK PASSED: ",
		models.size(),
		" pose datasets verified; credits present; live line-art generation"
	)
	quit()

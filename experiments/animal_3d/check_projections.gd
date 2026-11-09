extends SceneTree
## Checks projected vector art through the existing app's region, collage
## and kit pipelines. --input=/absolute/path/to/projections

const ProjectionSource = preload("res://experiments/animal_3d/projection_source.gd")

var failures := 0


func _init() -> void:
	var input := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--input="):
			input = arg.trim_prefix("--input=")
	if input.is_empty() or not DirAccess.dir_exists_absolute(input):
		printerr("Pass --input=/absolute/path/to/projections")
		quit(1)
		return
	var files := DirAccess.get_files_at(input)
	var checked := 0
	for file in files:
		if not file.ends_with("_lines.json"):
			continue
		var lines := ProjectionSource.load_lines(input.path_join(file))
		check(not lines.is_empty(), "%s: could not load" % file)
		if lines.is_empty():
			continue
		var map := RegionMap.build(lines["mask"], lines["width"], lines["height"], 0)
		check(map.regions.size() >= 4, "%s: too few closed areas" % file)
		var owners := {}
		for mark: Dictionary in lines["motifs"]["areas"]:
			var at: Vector2 = mark["at"]
			var label: int = map.labels[int(at.y) * map.width + int(at.x)]
			if label < 0:
				continue
			check(label != map.labels[0], "%s: an animal area leaks to the background" % file)
			if owners.has(label):
				check(owners[label] == mark["family"], "%s: different coat families leak together" % file)
			owners[label] = mark["family"]
		checked += 1
		print("%s: %d regions, %d marked regions" % [file, map.regions.size(), owners.size()])
		# One end-to-end puzzle for each morphology; every projection gets
		# the topology checks above.
		if file.ends_with("stand_35_lines.json"):
			var opts := {"variant": "animal", "theme": "sunset", "setting": "metal", "sparsity": 0.0}
			var collage := PictureSources.mandala_collage(9842, opts, lines)
			check(not collage["slots"].is_empty(), "%s: no playable collage slots" % file)
			check(collage["source"]["variant"] == "animal", "%s: lost app source metadata" % file)
			var image := PictureSources.mandala_image(9842, opts, lines)
			image.save_png(input.path_join(file.trim_suffix("_lines.json") + "_game_colors.png"))
			var kit := KitGenerator.generate(image, {"seed": 9842, "size": "small", "colors": 8})
			check(kit["cells"].size() == kit["width"] * kit["height"], "%s: incomplete kit" % file)
			print("  app pipeline: %d collage slots, %dx%d kit" % [collage["slots"].size(), kit["width"], kit["height"]])
	check(checked == 21, "expected 7 posed meshes at 3 angles, checked %d" % checked)
	for species in ["cat", "wolf", "horse"]:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error := document.append_from_file(input.get_base_dir().path_join(species + ".glb"), state)
		check(error == OK, "%s: Godot could not import the skinned GLB" % species)
		if error != OK:
			continue
		var scene := document.generate_scene(state)
		var skeletons := scene.find_children("*", "Skeleton3D", true, false)
		check(skeletons.size() == 1, "%s: expected one imported Skeleton3D" % species)
		if skeletons.size() == 1:
			check(skeletons[0].get_bone_count() == 26, "%s: imported skeleton lost bones" % species)
		print("%s: skinned GLB imported into Godot" % species)
		scene.free()
	print("%s: %d projections, %d failures" % ["FAILED" if failures else "PASSED", checked, failures])
	quit(1 if failures else 0)


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

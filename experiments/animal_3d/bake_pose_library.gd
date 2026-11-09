extends SceneTree
## Bake reviewed poses as compressed plain arrays for worker-thread generation.
## No scene, skeleton or rendering server is needed to make a puzzle on device.
## Files use AnimalPoseData's format. Options:
##   --attributes-only  refresh static surface attributes, keep the poses
##   --repack           rewrite existing files in the current format, keeping
##                      their poses exactly (no re-posing)

var out := "res://assets/animals/posed"
var failures := 0
var attributes_only := false
var repack := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		if arg == "--attributes-only":
			attributes_only = true
		if arg == "--repack":
			repack = true
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("_run")


func _run() -> void:
	var manifest := {"version": 1, "pose_version": 2, "models": {}}
	if attributes_only or repack:
		manifest = JSON.parse_string(FileAccess.get_file_as_string(out.path_join("catalog.json")))
	manifest.format = AnimalPoseData.VERSION
	if repack:
		for id: String in manifest.models:
			var path := out.path_join(id + ".dat")
			var stored := _read(path)
			_write(
				path,
				AnimalPoseData.pack(
					stored.attributes, stored.head_indices, AnimalPoseData.unpacked_states(stored)
				)
			)
			manifest.models[id].data_sha256 = FileAccess.get_sha256(path)
			print(id, ": repacked, ", FileAccess.get_file_as_bytes(path).size() / 1024, " KiB")
		_save_manifest(manifest)
		quit()
		return
	for id: String in AnimalPoseLibrary.model_ids():
		var animal := AnimalPoseLibrary.spawn(root, id)
		var static_data := animal.snapshot()
		static_data.erase("vertices")
		static_data.erase("normals")
		if attributes_only:
			var path := out.path_join(id + ".dat")
			var stored := _read(path)
			_write(
				path,
				AnimalPoseData.pack(
					static_data, stored.head_indices, AnimalPoseData.unpacked_states(stored)
				)
			)
			manifest.models[id].data_sha256 = FileAccess.get_sha256(path)
			animal.free()
			print(id, ": surface attributes refreshed")
			continue
		var states := []
		for preset: String in animal.available_poses():
			var samples := [[12, 0.25], [81, 0.25]]
			if preset in ["walk", "run", "trot", "gallop", "jump"]:
				samples.append_array([[12, 0.125], [81, 0.625]])
			for sample: Array in samples:
				var record := animal.pose(preset, sample[0], 0.75, {"phase": sample[1]})
				if record.is_empty():
					failures += 1
					printerr("Could not bake ", id, " ", preset, " ", sample)
					continue
				var geometry := animal.snapshot()
				var cameras := {}
				for view: String in AnimalCameraPresets.available(animal):
					cameras[view] = AnimalCameraPresets.frame(animal, view)
				states.append({"pose": record, "vertices": geometry.vertices, "cameras": cameras})
		var path := out.path_join(id + ".dat")
		_write(path, AnimalPoseData.pack(static_data, animal._head_indices(), states))
		manifest.models[id] = {
			"data_sha256": FileAccess.get_sha256(path),
			"file": path,
			"states": states.size(),
			"presets": Array(animal.available_poses()),
			"source_sha256": animal.source_info.sha256,
			"name": animal.source_info.display_name,
			"anatomy": AnimalPoseCatalog.anatomy(id)
		}
		print(id, ": ", states.size(), " frozen pose variants")
		animal.free()
	_save_manifest(manifest)
	print("BAKED ", manifest.models.size(), " models; ", failures, " failures")
	quit(1 if failures else 0)


func _read(path: String) -> Dictionary:
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var stored: Dictionary = file.get_var()
	file.close()
	return stored


func _write(path: String, stored: Dictionary) -> void:
	var file := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	file.store_var(stored)
	file.close()


func _save_manifest(manifest: Dictionary) -> void:
	FileAccess.open(out.path_join("catalog.json"), FileAccess.WRITE).store_string(
		JSON.stringify(manifest, "\t")
	)

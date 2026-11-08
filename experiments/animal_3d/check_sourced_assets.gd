extends SceneTree
## Import and sample downloaded animal rigs without changing their files.
## godot --headless -s res://experiments/animal_3d/check_sourced_assets.gd -- --input=/path/to/models

var failures := 0
var checked := 0
var hashes := {}
var any_animation := false
var require_uv := 0
var sample_start := 0.05


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var input := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--input="):
			input = arg.trim_prefix("--input=")
		elif arg == "--any-animation":
			any_animation = true
		elif arg.begins_with("--require-uv="):
			require_uv = int(arg.trim_prefix("--require-uv="))
		elif arg.begins_with("--sample-start="):
			sample_start = float(arg.trim_prefix("--sample-start="))
	if input.is_empty() or not DirAccess.dir_exists_absolute(input):
		printerr("Pass --input=/path/to/downloaded/models")
		quit(1)
		return
	await _directory(input)
	print("%s: %d distinct sourced GLBs, %d failures" % ["FAILED" if failures else "PASSED", checked, failures])
	quit(1 if failures or checked == 0 else 0)


func _directory(path: String) -> void:
	for file in DirAccess.get_files_at(path):
		if not file.ends_with(".glb"):
			continue
		var full_path := path.path_join(file)
		var digest := FileAccess.get_sha256(full_path)
		if hashes.has(digest):
			continue
		hashes[digest] = true
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(full_path, state) != OK:
			_fail("%s: import failed" % file)
			continue
		var scene := document.generate_scene(state)
		root.add_child(scene)
		if require_uv > 0:
			for instance in scene.find_children("*", "MeshInstance3D", true, false):
				for surface in instance.mesh.get_surface_count():
					var arrays: Array = instance.mesh.surface_get_arrays(surface)
					var count: int = arrays[Mesh.ARRAY_VERTEX].size()
					if arrays[Mesh.ARRAY_TEX_UV] == null or arrays[Mesh.ARRAY_TEX_UV].size() != count:
						_fail("%s: missing primary UVs" % file)
					if require_uv > 1 and (arrays[Mesh.ARRAY_TEX_UV2] == null or arrays[Mesh.ARRAY_TEX_UV2].size() != count):
						_fail("%s: missing coat flow UVs" % file)
		var skeletons := scene.find_children("*", "Skeleton3D", true, false)
		var players := scene.find_children("*", "AnimationPlayer", true, false)
		if skeletons.is_empty() or players.is_empty():
			_fail("%s: missing skeleton or animations" % file)
		else:
			var skeleton: Skeleton3D = skeletons[0]
			var player: AnimationPlayer = players[0]
			var clips := player.get_animation_list()
			var walk := ""
			for clip in clips:
				if "walk" in clip.to_lower():
					walk = clip
			if walk.is_empty() and any_animation:
				for clip in clips:
					if clip != "RESET":
						walk = clip
						break
			if walk.is_empty():
				_fail("%s: no walking clip" % file)
			else:
				player.play(walk)
				player.advance(sample_start)
				var before := []
				for bone in skeleton.get_bone_count():
					before.append(skeleton.get_bone_pose(bone))
				player.advance(0.31)
				var changed := false
				for bone in skeleton.get_bone_count():
					changed = changed or not before[bone].is_equal_approx(skeleton.get_bone_pose(bone))
				if not changed:
					_fail("%s: walking did not change the pose" % file)
			print("%s: %d imported bones, %d clips, sampled %s" % [file, skeleton.get_bone_count(), clips.size(), walk])
		checked += 1
		scene.queue_free()
		await process_frame
	for directory in DirAccess.get_directories_at(path):
		await _directory(path.path_join(directory))


func _fail(message: String) -> void:
	failures += 1
	printerr("FAIL: ", message)

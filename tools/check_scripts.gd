extends SceneTree
## Loads every script in the project and exits with code 1 if any fails to
## compile. tools/build_apk.sh runs it before exporting, since Godot's export
## packs a broken script without complaint.
##
##   godot --headless --path . -s res://tools/check_scripts.gd

const DIRS := ["res://game", "res://gen", "res://render", "res://scenes", "res://tests", "res://tools"]


func _initialize() -> void:
	var broken := []
	var count := 0
	for dir: String in DIRS:
		for path: String in _scripts(dir):
			if path == get_script().resource_path:
				continue  # reloading the running script breaks it
			count += 1
			var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
			if script == null or not script.can_instantiate():
				broken.append(path)
	if broken.is_empty():
		print("%d scripts compile." % count)
		quit(0)
	else:
		printerr("Scripts that don't compile:\n  " + "\n  ".join(PackedStringArray(broken)))
		quit(1)


static func _scripts(dir: String) -> Array:
	var out := []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in da.get_directories():
		out.append_array(_scripts(dir.path_join(d)))
	return out

extends SceneTree
## Contact sheets of the posed plants, for looking at: each plant's painted
## line art beside its collage on the game's paper.
##
##   godot --headless -s res://tests/plant_sheet.gd -- --out=/tmp/plants --seeds=1,8 [--cell=512]
##       [--layout=cluster] [--aura=auto|none|<style>] [--flower=rose] [--leaf=fern] [--camera=front] ...
##
## Other --key=value options go to the picture as they are (see
## MandalaGenerator and CollageGenerator).

const CollageSheet := preload("res://tests/collage_sheet.gd")
## The paper collages lie on in the game (GemBoard3D.PAPER_COLOR, as sRGB).
const PAPER := Color("#eeede9")


func _init() -> void:
	var out_dir := "user://plants"
	var first := 1
	var count := 8
	var cell := 512
	var opts := {"variant": "plant_mesh", "layout": PuzzleMaker.LAYOUT, "theme": "garden"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--seeds="):
			var parts := arg.trim_prefix("--seeds=").split(",")
			first = int(parts[0])
			count = int(parts[1]) if parts.size() > 1 else 8
		elif arg.begins_with("--cell="):
			cell = int(arg.trim_prefix("--cell="))
		elif arg.begins_with("--"):
			var kv := arg.trim_prefix("--").split("=")
			var value: Variant = kv[1] if kv.size() > 1 else true
			if value is String and (value as String).is_valid_int():
				value = int(value)
			opts[kv[0]] = value
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cols := mini(4, count)
	var sheet := Image.create(cell * 2 * cols, cell * ceili(count / float(cols)), false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	var recent := []
	for i in count:
		var seed_value := first + i
		var o := opts.duplicate()
		o["recent"] = recent
		var t0 := Time.get_ticks_msec()
		var lines := PictureSources.mandala_lines(seed_value, o)
		var info: Dictionary = lines["mandala"]["plant_mesh"]
		if info.is_empty():
			print("seed %d: no plant" % seed_value)
			continue
		recent.append(info)
		var painted := PictureSources.mandala_image(seed_value, o, lines)
		var p := PictureSources.mandala_collage(seed_value, o, lines)
		var ms := Time.get_ticks_msec() - t0
		var collage := CollageSheet.render(p, PAPER)
		var at := Vector2i((i % cols) * cell * 2, (i / cols) * cell)
		for img: Image in [painted, collage]:
			img.convert(Image.FORMAT_RGBA8)
			img.resize(cell, cell, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(img, Rect2i(0, 0, cell, cell), at)
			at.x += cell
		var aura: Dictionary = p.get("aura", {})
		print("seed %d (%d ms): %s with %s leaves, %s/%s/%s, %s, %s; %d stones, %d in the %s aura" % [seed_value, ms,
				info["flower"], info["leaf"], info["curve"], info["branching"], info["flowers"], info["pose"],
				info["camera"], p["slots"].size(), aura.get("stones", 0), aura.get("style", "none")])
	var path := out_dir.path_join("plants_%d.png" % first)
	sheet.save_png(path)
	print("wrote %s" % path)
	quit()

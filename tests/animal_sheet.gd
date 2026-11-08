extends SceneTree
## Contact sheets of the animal generators' line art, for looking at.
##
##   godot --headless -s res://tests/animal_sheet.gd -- --out=/tmp/animals --seeds=1,24 [--species=horse]

var out_dir := "user://animals"


func _init() -> void:
	var first := 1
	var count := 24
	var opts := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--seeds="):
			var parts := arg.trim_prefix("--seeds=").split(",")
			first = int(parts[0])
			count = int(parts[1]) if parts.size() > 1 else 24
		elif arg.begins_with("--"):
			var kv := arg.trim_prefix("--").split("=")
			opts[kv[0]] = kv[1] if kv.size() > 1 else true
	DirAccess.make_dir_recursive_absolute(out_dir)
	var variant: String = opts.get("variant", "animal")
	opts["variant"] = variant
	opts["frame"] = false
	var cell: int = int(opts.get("cell", 320))
	opts.erase("cell")
	var cols: int = mini(6, count)
	var sheet := Image.create(cell * cols, cell * ceili(count / float(cols)), false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	var recent := []
	var total_ms := 0
	for i in count:
		var seed_value := first + i
		var o := opts.duplicate()
		o["recent"] = recent
		var t0 := Time.get_ticks_msec()
		var lines := PictureSources.mandala_lines(seed_value, o)
		var ms := Time.get_ticks_msec() - t0
		total_ms += ms
		var info: Dictionary = lines["mandala"][variant]
		recent.append(info)
		var w: int = lines["width"]
		var h: int = lines["height"]
		var map := RegionMap.build(lines["mask"], w, h, int(w * h * 0.0005))
		var groups := RegionPaint.motif_groups(map, RegionPaint.symmetry_groups(map, "none"), lines["motifs"]["areas"])
		var colors := RegionPaint.theme_colors(map, "none", Palettes.theme_colors("sunset"), seed_value, groups)
		var img := RegionPaint.render(map, colors, PictureSources.LINE_COLOR, PictureSources.BACKGROUND)
		img.resize(cell, cell, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i((i % cols) * cell, (i / cols) * cell))
		var desc := []
		for k in info:
			desc.append("%s=%s" % [k, info[k]])
		print("seed %d (%d ms, %d regions): %s" % [seed_value, ms, map.regions.size(), ", ".join(PackedStringArray(desc))])
	var name := "%s_%d.png" % [variant, first]
	sheet.save_png(out_dir.path_join(name))
	print("avg %d ms; wrote %s" % [total_ms / count, out_dir.path_join(name)])
	quit()

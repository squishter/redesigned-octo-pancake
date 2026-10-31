extends SceneTree
## Renders the same line art under several pattern seeds, to eyeball the gem
## patterns:
##
##   godot --headless -s res://tests/collage_sheet.gd -- --out=/tmp/sheet --seeds=1000,1003 --patterns=3
##
## Options: --setting=gems|metal, --lines=<GemLines style>,
## --layout=classic|dense|both (both renders each pattern in both layouts,
## to compare them).


func _init() -> void:
	var out_dir := "user://previews"
	var seeds := [1000, 1001, 1003]
	var patterns := 3
	var extra := {}
	var layouts := ["classic"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--seeds="):
			seeds = Array(arg.trim_prefix("--seeds=").split(",")).map(func(v: String) -> int: return int(v))
		elif arg.begins_with("--patterns="):
			patterns = int(arg.trim_prefix("--patterns="))
		elif arg.begins_with("--setting="):
			extra["setting"] = arg.trim_prefix("--setting=")
		elif arg.begins_with("--lines="):
			extra["line_gems"] = arg.trim_prefix("--lines=")
		elif arg.begins_with("--layout="):
			var layout: String = arg.trim_prefix("--layout=")
			layouts = CollageGenerator.LAYOUTS if layout == "both" else [layout]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var themes := Palettes.theme_names()
	for s: int in seeds:
		var variant: String = MandalaGenerator.VARIANTS[s % MandalaGenerator.VARIANTS.size()]
		for pattern in patterns:
			for layout: String in layouts:
				var opts := {"variant": variant, "theme": themes[s % themes.size()], "frame": false, "pattern_seed": pattern,
						"layout": layout}
				opts.merge(extra, true)
				var t0 := Time.get_ticks_msec()
				var p := PictureSources.mandala_collage(s, opts)
				var styles := {}
				for r in p["regions"]:
					if r["kind"] == "area":
						styles[r["style"]] = styles.get(r["style"], 0) + 1
				print("seed %d pattern %d %s: %s %s radial %s tiers %s, %d slots, %d gem types, unit %.1f, %d ms, %s" % [
						s, pattern, layout, p["setting"], p["line_gems"], p["radial_size"], p["tiers"], p["slots"].size(),
						p["gem_types"], p["unit"], Time.get_ticks_msec() - t0, styles])
				var suffix := "" if layouts.size() == 1 and layout == "classic" else "_" + layout
				render(p).save_png(out_dir.path_join("sheet_%d_%s_p%d%s.png" % [s, variant, pattern, suffix]))
	quit()


static func render(p: Dictionary) -> Image:
	var w: int = p["width"]
	var h: int = p["height"]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("#2a1f3d"))
	for slot in p["slots"]:
		var poly := GemShapes.slot_polygon(slot, 16)
		var box := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			box = box.expand(v)
		var c: Color = slot["target_color"]
		for y in range(maxi(0, int(box.position.y)), mini(h, int(box.end.y) + 1)):
			for x in range(maxi(0, int(box.position.x)), mini(w, int(box.end.x) + 1)):
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
					img.set_pixel(x, y, c)
	var drawn: PackedByteArray = p["lines_visible"]
	for i in w * h:
		if drawn[i]:
			img.set_pixel(i % w, i / w, Color("#d4af5a"))
	return img

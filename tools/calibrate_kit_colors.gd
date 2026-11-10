extends SceneTree
## Measures how every gem color actually looks as a kit drill on the 3D
## board and writes gen/kit_seen_colors.gd, which KitGenerator matches
## pictures against (a drill's own color is not what the eye sees: the shader
## lights its facets, and paper and shadows show between drills).
##
## Each gem fills a block of BLOCK x BLOCK drills; the middle drills of each
## block are averaged in linear light, whole cells at a time (drill, the paper
## around it and the shadows on it), over several light positions and at two
## zooms: drills drawn as meshes and as tiny flat outlines (impostors).
##
## Needs a real renderer:
##   xvfb-run -a godot --rendering-method mobile -s res://tools/calibrate_kit_colors.gd
## Add -- --sheet=/path/dir to also save the rendered boards.

const OUT := "res://gen/kit_seen_colors.gd"
const BLOCK := 5
## Inner drills measured per block (centered), away from neighbors' shadows.
const INNER := 3
const COLUMNS := 11
## Screen px per drill: meshes, and impostors (below GemBoard3D.IMPOSTOR_PX).
const SCALES := [18, 7]
const LIGHT_TIMES := [0.0, 9.0, 17.0, 26.0, 40.0]

var _sheet := ""


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sheet="):
			_sheet = arg.trim_prefix("--sheet=")
	_run.call_deferred()


func _run() -> void:
	var gems := GemCatalog.all_colors()
	var tables := {}
	for drill in ["round", "square"]:
		var sums := []
		sums.resize(gems.size())
		sums.fill(Vector3.ZERO)
		var n := 0
		for px: int in SCALES:
			for t: float in LIGHT_TIMES:
				var img := await _render(gems, drill, px, t)
				if _sheet != "" and t == 0.0:
					DirAccess.make_dir_recursive_absolute(_sheet)
					img.save_png(_sheet.path_join("%s_%dpx.png" % [drill, px]))
				for i in gems.size():
					sums[i] += _measure(img, i, px)
				n += 1
		var seen := {}
		for i in gems.size():
			var lin: Vector3 = sums[i] / n
			seen[gems[i]["id"]] = Color(lin.x, lin.y, lin.z).linear_to_srgb()
		tables[drill] = seen
		print("%s drills measured" % drill)
	_write(gems, tables)
	quit()


## A board of every gem as a block of drills, `px` screen px per drill, with
## the light where it is `t` seconds into its drift.
func _render(gems: Array, drill: String, px: int, t: float) -> Image:
	var rows := ceili(float(gems.size()) / COLUMNS)
	var w := COLUMNS * BLOCK
	var h := rows * BLOCK
	var cells := PackedByteArray()
	cells.resize(w * h)
	var palette := []
	for i in gems.size():
		palette.append({"color": gems[i]["color"], "gem_color_id": gems[i]["id"]})
	# Blocks past the last gem repeat the first; they aren't measured.
	for y in h:
		for x in w:
			var i := (y / BLOCK) * COLUMNS + x / BLOCK
			cells[y * w + x] = i if i < gems.size() else 0
	var vp := SubViewport.new()
	vp.size = Vector2i(w * px, h * px)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var board := GemBoard3D.new()
	board.size = vp.size
	board.margin = 0.0
	board.animate = false
	board.use_sensor = false
	board.input_enabled = false
	vp.add_child(board)
	await process_frame
	board.show_kit({"width": w, "height": h, "drill": drill, "palette": palette, "cells": cells})
	board.light_time = t
	board.update_light()
	for i in 8:
		await process_frame
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	vp.queue_free()
	await process_frame
	return img


## The mean linear color of gem `i`'s inner drills, whole cells.
func _measure(img: Image, i: int, px: int) -> Vector3:
	var x0 := ((i % COLUMNS) * BLOCK + (BLOCK - INNER) / 2) * px
	var y0 := ((i / COLUMNS) * BLOCK + (BLOCK - INNER) / 2) * px
	var sum := Vector3.ZERO
	for y in range(y0, y0 + INNER * px):
		for x in range(x0, x0 + INNER * px):
			var c := img.get_pixel(x, y).srgb_to_linear()
			sum += Vector3(c.r, c.g, c.b)
	return sum / float(INNER * px * INNER * px)


func _write(gems: Array, tables: Dictionary) -> void:
	var s := "class_name KitSeenColors\nextends RefCounted\n"
	s += "## How each gem color looks as a kit drill on the board, seen from a\n"
	s += "## little way off: the mean color of a whole cell (drill, paper and\n"
	s += "## shadow), measured on the 3D board by tools/calibrate_kit_colors.gd\n"
	s += "## over several light positions, as meshes and as impostors.\n"
	s += "## Generated: run that tool again after changing the gem shaders, the\n"
	s += "## paper or the gem colors.\n"
	s += "\n## The plain gems' own colors (shimmer stones left out: they look like\n"
	s += "## nothing else), which KitGenerator predicts other colors' looks from.\n"
	s += "const PLAIN := {\n"
	for g in gems:
		if g["finish"] == "":
			var c: Color = g["color"]
			s += "\t\"%s\": Color(%.4f, %.4f, %.4f),\n" % [g["id"], c.r, c.g, c.b]
	s += "}\n"
	for drill in ["round", "square"]:
		s += "\n## How each gem looks as a %s drill.\n" % drill
		s += "const %s := {\n" % drill.to_upper()
		for g in gems:
			var c: Color = tables[drill][g["id"]]
			s += "\t\"%s\": Color(%.4f, %.4f, %.4f),\n" % [g["id"], c.r, c.g, c.b]
		s += "}\n"
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(s)
	f.close()
	print("Wrote ", ProjectSettings.globalize_path(OUT))

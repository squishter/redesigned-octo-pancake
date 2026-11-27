extends SceneTree
## Renders a GemBoard3D under a real (software) renderer and prints what each
## render draws: triangles, draw calls and objects, at several zooms.
##
##   godot --rendering-driver opengl3 --path <project> -s <this file> -- --kit=large --zooms=1,6,20 --placed=1.0
##
## --kit=small|medium|large|xlarge or --cols=N --rows=N   (kit grid; default large)
## --drill=round|square      --shapes=round,oval,heart   (mixed shapes instead of kit drills, like a collage)
## --zooms=1,6                (1 = whole picture; GemBoard3D.MAX_ZOOM is 40)
## --placed=1.0               (share of stones shown; the rest hidden as unplaced ones are)
## --size=1080x1600           (board px)   --frames=20   (renders averaged per zoom)
## --debug_test="no shadows"  (one of GemBoard3D.DEBUG_TESTS)
##
## Triangles and draw calls are what to compare. Milliseconds come from a CPU
## rasterizer and say nothing about a phone.

const KITS := {"small": Vector2i(38, 50), "medium": Vector2i(69, 90), "large": Vector2i(100, 130),
		"xlarge": Vector2i(192, 250)}


func _init() -> void:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var grid: Vector2i = KITS.get(str(args.get("kit", "large")), KITS["large"])
	if args.has("cols"):
		grid = Vector2i(int(args["cols"]), int(args.get("rows", args["cols"])))
	var size_parts := str(args.get("size", "1080x1600")).split("x")
	var zooms: Array = []
	for z: String in str(args.get("zooms", "1,6")).split(","):
		zooms.append(float(z))
	var placed := float(args.get("placed", "1.0"))
	var frames := int(args.get("frames", "20"))

	var holder := Control.new()
	root.add_child(holder)
	var board := GemBoard3D.new()
	board.size = Vector2(float(size_parts[0]), float(size_parts[1]))
	if args.has("debug_test"):
		board.debug_test = str(args["debug_test"])
	holder.add_child(board)
	var palette := [Color("#d6164f"), Color("#1f5fd6"), Color("#10a060"), Color("#ffd23f"), Color("#efe8e2")]
	var n := grid.x * grid.y
	if args.has("shapes"):
		var shapes := str(args["shapes"]).split(",")
		var slots := []
		for i in n:
			var shape := shapes[i % shapes.size()]
			slots.append({"id": i, "region": 0, "shape": shape, "cut": "", "x": (i % grid.x + 0.5) * 10.0,
					"y": (i / grid.x + 0.5) * 10.0, "rotation": 0.0, "size": 9.0,
					"width": 9.0 if shape == "round" else 6.0, "target_gem": "ruby", "target_color": palette[i % 5]})
		board.show_collage({"width": grid.x * 10.0, "height": grid.y * 10.0, "slots": slots})
	else:
		var cells := PackedByteArray()
		cells.resize(n)
		for i in n:
			cells[i] = (i * 7 + i / grid.x) % palette.size()
		var pal := []
		for c: Color in palette:
			pal.append({"color": c})
		board.show_kit({"width": grid.x, "height": grid.y, "cells": cells, "palette": pal,
				"drill": str(args.get("drill", "round"))})
	if placed < 1.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		for i in n:
			if rng.randf() >= placed:
				board.set_slot_shown(i, false)
	var vp := board.render_viewport_rid()
	var info := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	print("%d stones (%dx%d), %.0f%% placed, %d MultiMesh layers" % [n, grid.x, grid.y, placed * 100.0,
			board._layer_slots.size()])
	for zoom: float in zooms:
		board.reset_view()
		board._zoom_at(board.size / 2.0, zoom)
		await process_frame
		await process_frame
		var tri := 0
		var calls := 0
		var objects := 0
		var t0 := Time.get_ticks_usec()
		for f in frames:
			board._redraw()
			await process_frame
			tri = RenderingServer.viewport_get_render_info(vp, info, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
			calls = RenderingServer.viewport_get_render_info(vp, info, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
			objects = RenderingServer.viewport_get_render_info(vp, info, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
		print("zoom %5.1f: triangles %8d  draw calls %4d  objects %4d  (%.0f ms/frame, software)" % [zoom, tri, calls,
				objects, ms])
	quit()

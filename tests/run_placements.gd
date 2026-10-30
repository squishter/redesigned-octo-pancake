extends SceneTree
## Compare against main's original motion, then exercise the real play screen.

const PlayScreen := preload("res://scenes/game/play_screen.gd")
const GameTheme := preload("res://scenes/game/game_theme.gd")
const STYLES := ["fly", "drop", "spin", "bounce", "comet", "firework", "beam", "halo"]
var _before: Script
var _checks := 0
var _failures := 0
var _icon: ImageTexture


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1080, 2400)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.theme = GameTheme.build()
	_before = load("res://build/placement-checks/legacy_gem_flights.gd")
	if _before == null:
		printerr("Run python3 tests/prepare_placement_baseline.py first")
		quit(1)
		return
	var image := Image.create(150, 150, false, Image.FORMAT_RGBA8)
	image.fill(Color("#7760cf"))
	_icon = ImageTexture.create_from_image(image)
	await _motion_regressions()
	await _saturation_and_cleanup()
	for style: String in ["pop", "twinkle"] + STYLES:
		await _play_through(style)
	await _leave_mid_flight()
	for style: String in ["fly", "comet", "beam", "halo"]:
		await _big_brush(style)
	print("Placement animations: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)


func _board() -> GemBoard3D:
	var board := GemBoard3D.new()
	board.size = Vector2(1080, 1800)
	board.animate = false
	board.use_sensor = false
	root.add_child(board)
	board.show_collage(_picture())
	board.set_process(false)
	return board


func _flights(board: GemBoard3D, before: bool) -> Control:
	var flights: Control = _before.new() if before else GemFlights.new()
	flights.set("board", board)
	flights.size = Vector2(1080, 2400)
	root.add_child(flights)
	flights.set_process(false)
	return flights


func _send(flights: Control, style: String, slot := 0) -> bool:
	seed(4891 + slot)
	return flights.call("send", style, slot, _icon, 0.62, Vector2(180, 2130), 150.0,
		Vector2(160 + slot * 5, 260), 18.0, 0.6, -0.2, Color("#7760cf"))


func _motion_regressions() -> void:
	print("Original paths, scale/rotation easing, duration and landing event")
	var board := _board()
	for style: String in STYLES:
		var old := _flights(board, true)
		var updated := _flights(board, false)
		var landed := [0, 0]
		old.connect("landed", func(_slot: int) -> void: landed[0] += 1)
		updated.connect("landed", func(_slot: int) -> void: landed[1] += 1)
		_check(_send(old, style) and _send(updated, style), style + " accepts a placement")
		var original: Dictionary = old.get("_flights")[0]
		var current: Dictionary = updated.get("_flights")[0]
		_check(is_equal_approx(original["length"], current["length"]), style + " retains its duration")
		_check(original["from"].is_equal_approx(current["from"]), style + " retains its origin")
		var previous := 0.0
		for fraction: float in [0.15, 0.5, 0.85, 0.999]:
			# A pan/zoom during flight must still use the same projected slot.
			board._center += Vector2(2, -3)
			board._zoom = 1.0 + fraction
			board._apply_view()
			var step: float = (fraction - previous) * original["length"]
			old.call("_process", step)
			updated.call("_process", step)
			if is_equal_approx(fraction, 0.5):
				await process_frame
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
			var a: Sprite2D = original["sprite"]
			var b: Sprite2D = current["sprite"]
			_check(a.position.is_equal_approx(b.position), style + " follows the original path while panning")
			_check(a.scale.is_equal_approx(b.scale), style + " retains its size easing")
			_check(is_equal_approx(a.rotation, b.rotation), style + " retains its rotation")
			_check(a.visible == b.visible and landed == [0, 0], style + " does not land early")
			previous = fraction
		old.call("_process", original["length"] * 0.002)
		updated.call("_process", original["length"] * 0.002)
		_check(landed == [1, 1], style + " lands exactly once at the original time")
		old.call("land_all")
		updated.call("land_all")
		_check(landed == [1, 1], style + " cannot land twice on dismissal")
		old.queue_free()
		updated.queue_free()
		await process_frame
	board.queue_free()
	await process_frame


func _saturation_and_cleanup() -> void:
	print("Flight limit, queued crowds, rapid brush impacts, and finite cleanup")
	var board := _board()
	var flights := _flights(board, false) as GemFlights
	var landed := {}
	var repeats := [0]
	flights.landed.connect(func(slot: int) -> void:
		if landed.has(slot):
			repeats[0] += 1
		landed[slot] = true)
	# A big brush's worth in one frame: a grid over the whole picture, plus a
	# few far off screen.
	var crowd := 240
	var accepted := 0
	for i in crowd:
		var at := Vector2(20 + (i % 20) * 19, 20 + (i / 20) * 40)
		if flights.send("beam", i, _icon, 0.62, Vector2(180, 2130), 150, at, 18.0, 0, 0, Color.WHITE):
			accepted += 1
	for i in 5:
		if flights.send("beam", 1000 + i, _icon, 0.62, Vector2(180, 2130), 150, Vector2(-9000, -9000), 18.0, 0, 0,
				Color.WHITE):
			accepted += 1
	_check(accepted == crowd + 5, "A crowd of gems is accepted rather than popped in")
	_check(flights._flights.size() == GemFlights.SEND_AT_ONCE, "A frame's first few gems fly at once")
	_check(flights.flying() == crowd + 5, "The rest wait their turn and count as on their way")
	flights._process(0.0)
	_check(landed.size() == 5 and landed.has(1000), "Gems bound off screen land without flying")
	_check(flights._flights.size() == int(GemFlights.LAUNCH_BURST), "Queued gems launch up to the burst allowance")
	var per_cell := {}
	for f: Dictionary in flights._flights.slice(GemFlights.SEND_AT_ONCE):
		var cell := Vector2i(((f["to"] as Vector2) / GemFlights.CROWD_CELL).floor())
		per_cell[cell] = per_cell.get(cell, 0) + 1
	_check(per_cell.size() >= 12 and per_cell.values().max() <= 3,
		"Chosen flights spread over the stroke (%d cells, at most %d in one)" % [per_cell.size(), per_cell.values().max()])
	for _k in 9:
		flights._process(1.0 / 30.0)
	_check(flights._flights.size() > int(GemFlights.LAUNCH_BURST) and flights._flights.size() <= GemFlights.MAX_FLYING,
		"More launch as the rate allows, within the flight limit (%d)" % flights._flights.size())
	flights._process(GemFlights.MAX_WAIT)
	_check(flights._queue.is_empty(), "Nothing waits longer than MAX_WAIT")
	flights._process(0.5)
	_check(flights.flying() == 0 and landed.size() == crowd + 5 and repeats[0] == 0,
		"Every gem in the crowd lands exactly once (%d of %d, %d repeats)" % [landed.size(), crowd + 5, repeats[0]])
	_check(flights._shafts == 0 and flights._shaft_pool.size() <= GemFlights.MAX_SHAFTS,
		"Beam shafts are bounded and returned to the pool")
	var sprites := flights._gem_layer.get_child_count()
	_check(sprites <= GemFlights.MAX_FLYING and sprites == flights._sprite_pool.size(), "Gem sprites are reused")

	landed.clear()
	for i in GemFlights.MAX_FLYING + 20:
		flights.send("halo", i, _icon, 0.62, Vector2.ZERO, 150, Vector2(160, 260), 18.0, 0, 0, Color.WHITE)
	flights.land_all()
	flights.land_all()
	_check(landed.size() == GemFlights.MAX_FLYING + 20 and repeats[0] == 0 and flights.flying() == 0,
		"Leaving lands every flying and waiting gem exactly once")
	landed.clear()
	for i in GemFlights.MAX_QUEUED + GemFlights.SEND_AT_ONCE:
		flights.send("fly", i, _icon, 0.62, Vector2.ZERO, 150, Vector2(160, 260), 18.0, 0, 0, Color.WHITE)
	_check(not _send(flights, "fly", 99), "A full queue refuses more, so the screen pops them in")
	flights.land_all()

	for _i in 300:
		flights.burst(Vector2(160, 260), 18, Color.WHITE)
	_check(flights._impacts.size() == GemFlights.MAX_IMPACTS, "Rapid strokes keep a bounded number of lingering effects")
	_check(flights.flying() == 0, "Landing glints never count as unfinished placements")
	flights._process(0.41)
	await process_frame
	flights._process(0.6)
	_check(flights._impacts.is_empty() and flights._fading.is_empty(), "Every landing effect and trail expires")
	var count := landed.size()
	flights._process(1.0)
	_check(landed.size() == count and repeats[0] == 0, "Cleanup never repeats a landing event")
	landed.clear()
	flights.send("halo", 200, _icon, 0.62, Vector2.ZERO, 150, Vector2(160, 260), 0.2, 0, 0, Color.WHITE)
	flights._process(0.39)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	flights._process(0.02)
	_check(flights.flying() == 0 and repeats[0] == 0, "A tiny far-zoomed Halo remains valid through its final drawing frame")
	flights.queue_free()
	board.queue_free()
	await process_frame


func _big_brush(style: String) -> void:
	var profile := SaveStore.upgrade({"wallet": {"coins": 0, "picks": 0}})
	var picture := _picture()
	var slots := []
	for i in 300:
		slots.append({"id": i, "region": 0, "shape": "round", "cut": "brilliant", "x": 12 + (i % 25) * 15,
			"y": 20 + (i / 25) * 40, "rotation": 0.0, "size": 10.0, "width": 10.0, "target_gem": "ruby",
			"target_color": Color.RED})
	picture["slots"] = slots
	var meta := SaveStore.add_puzzle(profile, picture)
	var play := PlayScreen.new()
	play.profile = profile
	play.puzzle_id = meta["id"]
	root.add_child(play)
	for _i in 4:
		await process_frame
	play._fill_animation = style
	play._flights.set_process(false)
	var shown := {}
	play._flights.landed.connect(func(slot: int) -> void: shown[slot] = shown.get(slot, 0) + 1)
	var started := Time.get_ticks_usec()
	for i in 300:
		play._fill(i)
	var fill_ms := (Time.get_ticks_usec() - started) / 1000.0
	_check(play._filled == 300 and not play._done, style + " brush: every stone counts, the finale waits")
	_check(play._flights.flying() == 300, style + " brush: nothing pops in while there's room to queue")
	var worst := 0.0
	for _k in 30:
		started = Time.get_ticks_usec()
		play._flights._process(1.0 / 30.0)
		worst = maxf(worst, (Time.get_ticks_usec() - started) / 1000.0)
		await process_frame
	_check(shown.size() == 300 and shown.values().max() == 1, style + " brush: every stone lands once")
	_check(play._done, style + " brush: the finale starts after the last stone lands")
	print("  %s brush: 300 stones queued in %.1f ms, slowest flight update %.1f ms" % [style, fill_ms, worst])
	play._flights.land_all()
	play.queue_free()
	await process_frame
	SaveStore.delete_puzzle(profile, meta["id"])


func _picture() -> Dictionary:
	var slots := []
	for i in 3:
		slots.append({"id": i, "region": 0, "shape": "round", "cut": "brilliant", "x": 140 + i * 30, "y": 260,
			"rotation": 0.0, "size": 18.0, "width": 18.0, "target_gem": "ruby", "target_color": Color.RED})
	return {"type": "collage", "width": 400, "height": 520, "slots": slots,
		"regions": [{"id": 0, "color": Color.RED}], "puzzle": {"type": "mandala", "theme": "rainbow"}}


func _play_through(style: String) -> void:
	var profile := SaveStore.upgrade({"wallet": {"coins": 0, "picks": 0}})
	var meta := SaveStore.add_puzzle(profile, _picture())
	var play := PlayScreen.new()
	play.profile = profile
	play.puzzle_id = meta["id"]
	root.add_child(play)
	for _i in 4:
		await process_frame
	play._fill_animation = style
	play._flights.set_process(false)
	for i in 3:
		play._fill(i)
	_check(play._filled == 3, style + " records each placed gem")
	if style in STYLES:
		_check(not play._done and Packs.coins(profile) == 0, style + " waits for the final gem before rewarding")
		play._flights._process(0.6)
	_check(play._done and play._board.is_celebrating(), style + " starts the tap-to-end finale")
	_check(Packs.coins(profile) == 10 and Packs.picks(profile) == 1, style + " rewards the puzzle once")
	var saved := SaveStore.load_profile()
	_check(saved["puzzles"][0]["done"] and saved["puzzles"][0]["filled"] == 3, style + " saves all placed gems")
	play._flights.land_all()
	play._finish(true)
	_check(Packs.coins(profile) == 10 and Packs.picks(profile) == 1, style + " cannot award completion twice")
	play.go_back()
	_check(not play._board.is_celebrating() and play._reward_dialog.visible, style + " opens rewards after the finale")
	play.queue_free()
	await process_frame
	SaveStore.delete_puzzle(profile, meta["id"])


func _leave_mid_flight() -> void:
	var profile := SaveStore.upgrade({"wallet": {"coins": 0, "picks": 0}})
	var meta := SaveStore.add_puzzle(profile, _picture())
	var play := PlayScreen.new()
	play.profile = profile
	play.puzzle_id = meta["id"]
	root.add_child(play)
	for _i in 4:
		await process_frame
	play._fill_animation = "beam"
	play._flights.set_process(false)
	play._fill(0)
	play._flights._process(0.1)
	play.go_back()
	_check(play._flights.flying() == 0 and not play._done, "Back lands an in-flight gem without finishing the puzzle")
	var progress := SaveStore.load_progress(meta["id"], 3)
	_check(progress[0] == 1 and progress[1] == 0 and Packs.coins(profile) == 0, "Leaving mid-flight saves progress without a reward")
	play.queue_free()
	await process_frame
	SaveStore.delete_puzzle(profile, meta["id"])

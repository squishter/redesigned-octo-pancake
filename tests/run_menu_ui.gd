extends SceneTree
## Interaction and layout checks. Use an isolated XDG_DATA_HOME, since the
## purchase checks intentionally save and reload their test profile.
## godot --headless --path . -s res://tests/run_menu_ui.gd

const GameTheme := preload("res://scenes/game/game_theme.gd")
const MainMenu := preload("res://scenes/game/main_menu.gd")
const CollectionScreen := preload("res://scenes/game/collection_screen.gd")
const AppScene := preload("res://scenes/game/app.tscn")
const PlayScreen := preload("res://scenes/game/play_screen.gd")
var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# The headless display reports a square physical window. Test the actual
	# phone layout instead of expanding that square to a 2400-pixel-wide canvas.
	root.content_scale_size = Vector2i(1080, 2400)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.theme = GameTheme.build()
	await _test_menu_layout()
	await _test_creation_choices()
	await _test_carousel()
	await _test_purchases()
	await _test_reward_kinds()
	await _test_transitions()
	await _test_completion_rewards()
	await _test_unlock_all()
	_test_camera_helper()
	print("Menu UI: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: ", message)


func _layout_frames() -> void:
	for _i in 4:
		await process_frame


func _check_button_widths(node: Node, width: float) -> void:
	for child in node.get_children():
		if child is Button and child.is_visible_in_tree():
			var rect: Rect2 = child.get_global_rect()
			_check(rect.position.x >= -1 and rect.end.x <= width + 1,
				"Button fits horizontally: %s (%s in %s)" % [child.text, rect, width])
		_check_button_widths(child, width)


func _check_dialog(dialog: GameDialog) -> void:
	var rect := dialog.card.get_global_rect()
	_check(rect.position.y >= 0 and rect.end.y <= dialog.size.y,
		"Dialog stays within the portrait screen: %s" % dialog.title_label.text)
	var actions := dialog.actions.get_global_rect()
	_check(actions.end.y <= dialog.size.y, "Dialog actions remain on screen")


func _test_menu_layout() -> void:
	print("Menu layouts")
	var menu := MainMenu.new()
	menu.profile = SaveStore.upgrade({})
	root.add_child(menu)
	await _layout_frames()
	_check_button_widths(menu, menu.size.x)
	menu._open_new({})
	await _layout_frames()
	_check(menu._new_panel.visible, "New-puzzle form opens")
	_check_dialog(menu._new_panel)
	_check_button_widths(menu, menu.size.x)
	menu.go_back()
	_check(not menu._new_panel.visible, "Back closes the new-puzzle form")
	menu.queue_free()
	await process_frame


func _test_unlock_all() -> void:
	print("Debug unlock-all setting")
	var profile := SaveStore.upgrade({})
	SaveStore.save_profile(profile)
	var own := (profile["unlocks"] as Dictionary).duplicate(true)
	var menu := MainMenu.new()
	menu.profile = profile
	root.add_child(menu)
	await _layout_frames()
	var toggle: Button = menu._settings_panel.body.find_child("UnlockAll", true, false)
	_check(toggle != null and toggle.text.ends_with("Off"), "Debug builds offer unlock-all in settings, off")
	var reloads := [0]
	menu.reload_requested.connect(func() -> void: reloads[0] += 1)
	toggle.pressed.emit()
	_check(reloads[0] == 1, "Turning it on shows the menu afresh")
	var all := Unlockables.all_unlocks()
	_check(profile["unlocks"] == all, "Everything is unlocked while it's on")
	_check(GemCatalog.unlocked_themes(profile["unlocks"]).size() == GemCatalog.THEMES.size(), "Every theme is unlocked")
	var missing := []
	for kind: String in Unlockables.KINDS:
		for item: Dictionary in Unlockables.items(kind):
			if kind != "power" and not Unlockables.has(profile["unlocks"], item):
				missing.append(item["id"])
	_check(missing.is_empty(), "Every item but power-up charges is had: missing %s" % [missing])
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveStore.DIR + "/profile.json"))
	_check(raw["unlocks"] == own and not raw.has(SaveStore.REAL_UNLOCKS), "Her own unlocks are what's saved")
	var loaded := SaveStore.load_profile()
	_check(SaveStore.is_unlock_all(loaded) and loaded["unlocks"] == all, "The setting stays on after reloading")
	SaveStore.set_unlock_all(loaded, false)
	_check(loaded["unlocks"] == own and not loaded["settings"].has(SaveStore.UNLOCK_ALL),
		"Turning it off gives back exactly her own unlocks")
	SaveStore.save_profile(loaded)
	_check(not SaveStore.is_unlock_all(SaveStore.load_profile()), "Off stays off after reloading")
	menu.queue_free()
	await process_frame


func _test_creation_choices() -> void:
	print("Creation choices, photo controls, and dialog navigation")
	var menu := MainMenu.new()
	menu.profile = SaveStore.upgrade({})
	menu.show_developer_tools = false
	root.add_child(menu)
	menu._open_new({})
	await _layout_frames()
	_check(menu._menu_scroll.process_mode == Node.PROCESS_MODE_DISABLED, "Workshop freezes the background menu")
	_check_dialog(menu._new_panel)
	menu._mode_buttons[1].pressed.emit()
	_check(menu._is_kit(), "Diamond kit card changes the puzzle mode")
	_check((menu._kit_size.get_meta("row") as Control).is_visible_in_tree(), "Kits offer picture size")
	menu._source.select(menu._source.item_count - 1)
	menu._source.item_selected.emit(menu._source.selected)
	await _layout_frames()
	_check(menu._photo_actions.visible and not menu._start.visible, "Photo kit offers library and camera actions")
	_check((menu._kit_colors.get_meta("row") as Control).is_visible_in_tree(), "Photo kits offer drill color choices")
	_check_button_widths(menu, menu.size.x)
	menu._mode_buttons[0].pressed.emit()
	_check(menu._is_photo() and not menu._is_kit(), "Changing mode preserves the photo source")
	_check((menu._subject.get_meta("row") as Control).is_visible_in_tree(), "Photo collage offers composition choices")
	menu._open_new({"type": "mandala", "theme": "rainbow"})
	_check(menu._mode_buttons.all(func(button: Button) -> bool: return button.disabled),
		"Recoloring keeps the original puzzle mode fixed")
	menu.go_back()
	_check(menu._menu_scroll.process_mode == Node.PROCESS_MODE_INHERIT, "Closing a dialog restores menu input")
	menu._settings_panel.open()
	await _layout_frames()
	_check_dialog(menu._settings_panel)
	_check_button_widths(menu, menu.size.x)
	menu.go_back()
	_check(not menu._settings_panel.visible, "Back closes settings")
	_check(menu._camera.player_style, "The player's camera opts into the game styling")
	var lab_camera := CameraCapture.new()
	_check(not lab_camera.player_style, "Developer camera styling remains opt-in")
	lab_camera.free()
	menu.queue_free()
	await process_frame


func _test_carousel() -> void:
	print("Carousel wrap, swipe and spring settling")
	var carousel := PackCarousel.new()
	carousel.size = Vector2(1000, 710)
	root.add_child(carousel)
	carousel.set_process(false)
	_check(carousel.current_pack() == "colors", "First pack is selected")
	carousel.rotate_by(-1)
	for _i in 480:
		carousel._process(1.0 / 120.0)
	_check(carousel.current_pack() == "all", "Previous wraps to the last pack")
	_check(absf(carousel._velocity) < 0.01, "Rotation settles")
	for swing: float in carousel._swing:
		_check(absf(swing) < 0.01, "Hanger settles after rotation")
	carousel.rotate_by(1)
	for _i in 480:
		carousel._process(1.0 / 120.0)
	_check(carousel.current_pack() == "colors", "Next wraps to the first pack")
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = Vector2(700, 350)
	carousel._gui_input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(400, 350)
	carousel._gui_input(drag)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = drag.position
	carousel._gui_input(up)
	for _i in 480:
		carousel._process(1.0 / 120.0)
	_check(carousel.current_pack() != "colors", "A left swipe advances the display")
	_check(not carousel._dragging, "Touch release ends the drag")
	_check(absf(carousel._angle / carousel._step - roundf(carousel._angle / carousel._step)) < 0.01,
		"Swipe snaps to a complete pack")
	carousel.rotate_by(1)
	carousel._process(0.1)
	_check(carousel._swing.any(func(s: float) -> bool: return absf(s) > 0.002), "Packs swing while rotating")
	for _i in 100:
		carousel._process(0.5)
	_check(is_finite(carousel._angle), "A slow frame cannot destabilize the springs")
	carousel.queue_free()
	await process_frame


func _test_purchases() -> void:
	print("Pack purchase, skip, back and save safety")
	var screen := CollectionScreen.new()
	screen.profile = SaveStore.upgrade({"wallet": {"coins": 60, "picks": 2}})
	root.add_child(screen)
	await _layout_frames()
	_check_button_widths(screen, screen.size.x)
	_check(screen._carousel.get_parent() == screen._packs_list, "Pack picker is the carousel")
	screen._show_tab(false)
	for category: String in ["shapes", "extras", "colors"]:
		screen._select_collection(category)
		await _layout_frames()
		_check_button_widths(screen, screen.size.x)
	_check(screen._collection_filter == "colors", "Collection categories can be switched without changing unlocks")
	screen._show_tab(true)
	var before: int = screen.profile["unlocks"]["colors"].size()
	screen._open("colors", true)
	screen._open("colors", true)
	_check(Packs.picks(screen.profile) == 1, "Repeated opening spends a single pick")
	_check(screen.profile["unlocks"]["colors"].size() == before + 1, "Exactly one reward is granted")
	var pack_layers := screen._carousel._hangers.map(func(hanger: Control) -> int: return hanger.z_index)
	_check(screen._opening.z_index > int(pack_layers.max()), "Opening overlay draws above every carousel hanger")
	var saved := SaveStore.load_profile()
	_check(Packs.picks(saved) == 1 and saved["unlocks"]["colors"].size() == before + 1,
		"Reward and payment are saved before the animation")
	screen.go_back()
	_check(screen._opening._revealed, "Back during the animation reveals the saved reward")
	screen.go_back()
	screen._opening._keep.disabled = true
	await create_timer(0.25).timeout
	_check(not is_instance_valid(screen._opening), "Back after the reveal dismisses it")
	_check(Packs.picks(screen.profile) == 1, "Dismissal never draws again")
	screen._open("powers", false)
	_check(Packs.coins(screen.profile) == 50, "Coin purchase charges the selected pack's price")
	var opening := screen._opening
	opening._timeline.custom_step(10.0)
	_check(opening._revealed and opening._front.visible, "The complete tear, rise and flip timeline reveals the card")
	opening.show_reward()
	_check(Packs.coins(screen.profile) == 50, "Skip after completion cannot spend again")
	opening.close()
	await create_timer(0.25).timeout
	for shape: Dictionary in Unlockables.items("shape"):
		Unlockables.grant(screen.profile, shape)
	screen._update_pack("shapes")
	_check(screen._free.disabled and screen._buy.disabled, "A completed pack cannot be bought")
	var coins := Packs.coins(screen.profile)
	screen._open("shapes", false)
	_check(Packs.coins(screen.profile) == coins, "Sold-out opening leaves the wallet alone")
	screen.profile["wallet"]["coins"] = 0
	screen.profile["wallet"]["picks"] = 0
	screen._update_pack("powers")
	_check(screen._free.disabled and screen._buy.disabled, "Unaffordable payment controls are disabled")
	screen.queue_free()
	await process_frame


func _test_reward_kinds() -> void:
	print("Reward cards for every unlock kind")
	for kind: String in Unlockables.KINDS:
		var reward: Dictionary = Unlockables.items(kind)[0].duplicate()
		var opening := PackOpening.new()
		opening.item = reward
		opening.pack = Unlockables.KINDS[kind]["pack"]
		if opening.pack == "":
			opening.pack = "colors"
		root.add_child(opening)
		opening.show_reward()
		await _layout_frames()
		_check(opening._front.visible and opening.picture != null, "%s has artwork and a revealed card" % kind)
		var card := opening._card.get_global_rect()
		var button := opening._keep.get_global_rect()
		_check(card.end.y <= button.position.y, "%s reward text fits above the continue button" % kind)
		opening.queue_free()
		await process_frame
	var long_reward := PackOpening.new()
	long_reward.item = Unlockables.items("color")[0].duplicate()
	long_reward.item["themes"] = GemCatalog.THEMES.keys()
	root.add_child(long_reward)
	long_reward.show_reward()
	await _layout_frames()
	_check(long_reward._card.get_global_rect().end.y <= long_reward._keep.get_global_rect().position.y,
		"Many completed themes scroll inside the reward card")
	long_reward.queue_free()
	await process_frame


func _test_transitions() -> void:
	print("Screen transitions and board entry")
	var app = AppScene.instantiate()
	root.add_child(app)
	await create_timer(0.65).timeout
	_check(not app._transitioning and not app._veil.visible, "Initial menu transition completes")
	app._show_collection()
	app._show_collection()
	await create_timer(0.8).timeout
	_check(app._screen.get_script() == CollectionScreen and not app._transitioning,
		"Repeated navigation creates one collection screen and completes")
	# A minimal saved puzzle exercises the real board entry without generation.
	var picture := {"type": "collage", "width": 100, "height": 100, "slots": [
		{"id": 0, "region": 0, "shape": "round", "cut": "brilliant", "x": 50, "y": 50,
			"rotation": 0.0, "size": 20.0, "width": 20.0, "target_gem": "ruby", "target_color": Color.RED}],
		"regions": [{"id": 0, "color": Color.RED}], "puzzle": {"type": "mandala", "theme": "rainbow"}}
	var meta := SaveStore.add_puzzle(app.profile, picture)
	app._play(meta["id"])
	await create_timer(0.8).timeout
	_check(not app._transitioning and app._screen.puzzle_id == meta["id"], "Menu-to-board transition completes")
	_check_button_widths(app._screen, app._screen.size.x)
	_check(not app._screen._hint.disabled, "A new puzzle starts with an available hint")
	app._screen._use_hint()
	_check(app._screen._hint.disabled and int(meta["hints"]) == 0 and app._screen._ring_slot >= 0,
		"Hint focuses an open slot and spends its charge")
	app._screen.go_back()
	await create_timer(0.8).timeout
	_check(app._screen.get_script() == MainMenu and not app._veil.visible, "Board-to-menu transition completes")
	SaveStore.delete_puzzle(app.profile, meta["id"])
	app.queue_free()
	await process_frame


func _test_completion_rewards() -> void:
	print("Completion rewards, modal input, saved summaries, and replay safety")
	var profile := SaveStore.upgrade({"wallet": {"coins": 0, "picks": 0}})
	var picture := {"type": "collage", "width": 100, "height": 100, "slots": [
		{"id": 0, "region": 0, "shape": "round", "cut": "brilliant", "x": 50, "y": 50,
			"rotation": 0.0, "size": 20.0, "width": 20.0, "target_gem": "ruby", "target_color": Color.RED}],
		"regions": [{"id": 0, "color": Color.RED}], "puzzle": {"type": "mandala", "theme": "rainbow"}}
	var meta := SaveStore.add_puzzle(profile, picture)
	var play := PlayScreen.new()
	play.profile = profile
	play.puzzle_id = meta["id"]
	root.add_child(play)
	await _layout_frames()
	play._toggle_powers()
	await _layout_frames()
	_check(not play._board.input_enabled, "Power-up dialog blocks board input")
	_check_dialog(play._powers_panel)
	_check_button_widths(play, play.size.x)
	play.go_back()
	_check(not play._powers_panel.visible and play._board.input_enabled, "Back closes power-ups and restores the board")
	play._overlay.placed[0] = 1
	play._filled = 1
	play._powers_on.append("double_coins")
	play._finish(true)
	await create_timer(3.5).timeout
	_check(play._board.is_celebrating() and not is_instance_valid(play._reward_dialog),
		"The finale keeps playing until she taps")
	_check(not play._board.input_enabled, "The board ignores gestures during the finale")
	var tap := InputEventScreenTouch.new()
	tap.position = play.size / 2.0
	tap.pressed = true
	Input.parse_input_event(tap)
	await process_frame
	_check(play._board.is_celebrating(), "Pressing alone doesn't end the finale")
	tap = tap.duplicate()
	tap.pressed = false
	Input.parse_input_event(tap)
	await process_frame
	_check(not play._board.is_celebrating(), "Letting go of a tap ends the finale")
	await _layout_frames()
	var saved := SaveStore.load_profile()
	_check(Packs.coins(saved) == 20 and Packs.picks(saved) == 1, "Double coins and the daily pick are saved before the dialog")
	_check(play._reward_dialog.visible and not play._board.input_enabled, "Completion dialog blocks board input")
	_check_dialog(play._reward_dialog)
	_check_button_widths(play, play.size.x)
	var texts := []
	for label: Label in play._reward_dialog.find_children("*", "Label", true, false):
		texts.append(label.text)
	_check("+20 coins" in texts and "+1 free pick" in texts, "Reward cards show the exact coins and pick earned")
	play._finish(true)
	play.go_back()
	_check(play._board.input_enabled, "Admiring the completed picture restores board gestures")
	play._show_rewards()
	_check(Packs.coins(profile) == 20 and Packs.picks(profile) == 1, "Reopening rewards never grants them twice")
	play._reward_dialog.close()
	play.queue_free()
	await process_frame
	var reopened := PlayScreen.new()
	reopened.profile = saved
	reopened.puzzle_id = meta["id"]
	root.add_child(reopened)
	await _layout_frames()
	reopened._show_rewards()
	_check(reopened._reward_dialog.reward.get("coins") == 20, "The earned summary survives reopening the saved puzzle")
	_check(Packs.coins(saved) == 20 and Packs.picks(saved) == 1, "Reopening a finished puzzle leaves the wallet unchanged")
	reopened.queue_free()
	await process_frame
	SaveStore.save_progress(meta["id"], PackedByteArray())
	var replay := PlayScreen.new()
	replay.profile = saved
	replay.puzzle_id = meta["id"]
	root.add_child(replay)
	replay._overlay.placed[0] = 1
	replay._filled = 1
	replay._finish(true)
	replay._show_rewards()
	_check(int(replay._reward_dialog.reward["coins"]) == 0 and not replay._reward_dialog.reward["pick"],
		"Replaying an already rewarded picture shows no new rewards")
	_check(Packs.coins(saved) == 20 and Packs.picks(saved) == 1, "Replays cannot farm coins or daily picks")
	replay.queue_free()
	await process_frame
	SaveStore.delete_puzzle(saved, meta["id"])


func _test_camera_helper() -> void:
	var interleaved := Image.create_from_data(4, 1, false, Image.FORMAT_R8, PackedByteArray([90, 140, 100, 150]))
	var paired := CameraCapture.chroma_pairs(interleaved)
	_check(paired.get_width() == 2 and paired.get_format() == Image.FORMAT_RG8,
		"Camera's missing helper identifies alternating chroma bytes")
	_check(paired.get_data() == interleaved.get_data(), "Camera conversion preserves Cb/Cr pairs")

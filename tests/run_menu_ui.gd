extends SceneTree
## Interaction and layout checks. Use an isolated XDG_DATA_HOME, since the
## purchase checks intentionally save and reload their test profile.
## godot --headless --path . -s res://tests/run_menu_ui.gd

const GameTheme := preload("res://scenes/game/game_theme.gd")
const MainMenu := preload("res://scenes/game/main_menu.gd")
const CollectionScreen := preload("res://scenes/game/collection_screen.gd")
const App := preload("res://scenes/game/app.gd")
var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.theme = GameTheme.build()
	await _test_menu_layout()
	await _test_carousel()
	await _test_purchases()
	await _test_reward_kinds()
	await _test_transitions()
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
	_check_button_widths(menu, menu.size.x)
	menu.go_back()
	_check(not menu._new_panel.visible, "Back closes the new-puzzle form")
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
	var before: int = screen.profile["unlocks"]["colors"].size()
	screen._open("colors", true)
	screen._open("colors", true)
	_check(Packs.picks(screen.profile) == 1, "Repeated opening spends a single pick")
	_check(screen.profile["unlocks"]["colors"].size() == before + 1, "Exactly one reward is granted")
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
	var app := App.new()
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
	app._screen.go_back()
	await create_timer(0.8).timeout
	_check(app._screen.get_script() == MainMenu and not app._veil.visible, "Board-to-menu transition completes")
	SaveStore.delete_puzzle(app.profile, meta["id"])
	app.queue_free()
	await process_frame


func _test_camera_helper() -> void:
	var interleaved := Image.create_from_data(4, 1, false, Image.FORMAT_R8, PackedByteArray([90, 140, 100, 150]))
	var paired := CameraCapture.chroma_pairs(interleaved)
	_check(paired.get_width() == 2 and paired.get_format() == Image.FORMAT_RG8,
		"Camera's missing helper identifies alternating chroma bytes")
	_check(paired.get_data() == interleaved.get_data(), "Camera conversion preserves Cb/Cr pairs")

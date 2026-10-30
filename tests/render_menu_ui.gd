extends SceneTree
## Captures the actual player UI with a real rendering driver (for example,
## xvfb-run -a godot --path . --resolution 1080x2400 -s res://tests/render_menu_ui.gd).

const GameTheme := preload("res://scenes/game/game_theme.gd")
const MenuBackdrop := preload("res://scenes/game/menu_backdrop.gd")
const MainMenu := preload("res://scenes/game/main_menu.gd")
const CollectionScreen := preload("res://scenes/game/collection_screen.gd")
const PlayScreen := preload("res://scenes/game/play_screen.gd")
var _out := "res://build/ui-renders"


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_capture.call_deferred()


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	root.theme = GameTheme.build()
	RenderingServer.set_default_clear_color(GameTheme.BG)
	var backdrop := MenuBackdrop.new()
	root.add_child(backdrop)
	var profile := SaveStore.upgrade({"wallet": {"coins": 90, "picks": 3}})
	var menu := MainMenu.new()
	menu.profile = profile
	menu.show_developer_tools = false
	menu.show_debug_settings = false
	root.add_child(menu)
	await create_timer(0.8).timeout
	await _snapshot("01-main-menu.png")
	menu._open_new({})
	await create_timer(0.35).timeout
	await _snapshot("05-puzzle-creation.png")
	menu._new_panel.close()
	menu._settings_panel.open()
	await create_timer(0.35).timeout
	await _snapshot("11-settings.png")
	menu.queue_free()
	await process_frame
	var collection := CollectionScreen.new()
	collection.profile = profile
	root.add_child(collection)
	await create_timer(1.2).timeout
	await _snapshot("02-pack-picker.png")
	collection._carousel.rotate_by(-1)
	await create_timer(1.5).timeout
	await _snapshot("16-everything-pack.png")
	collection._carousel.rotate_by(-1)
	await create_timer(1.5).timeout
	await _snapshot("17-power-up-pack.png")
	collection._carousel.rotate_by(2)
	await create_timer(1.5).timeout
	collection._rng.seed = 20261030
	collection._open("colors", true)
	var opening: PackOpening = collection._opening
	opening._timeline.pause()
	opening._timeline.custom_step(0.95)
	opening.set_process(false)
	await _snapshot("03-opening-the-foil.png")
	opening.show_reward()
	opening._burst = 0.45
	opening.queue_redraw()
	await create_timer(0.3).timeout
	await _snapshot("04-unlocked-card.png")
	opening.close()
	await create_timer(0.3).timeout
	await _capture_bundle(collection)
	collection._show_tab(false)
	await create_timer(0.4).timeout
	await _snapshot("06-collection.png")
	collection.queue_free()
	await process_frame
	await _capture_studio(profile)
	print("UI renders saved to ", ProjectSettings.globalize_path(_out))
	quit()


func _capture_bundle(collection: Control) -> void:
	# Use the real purchase API with an example five-reward pack definition.
	# A larger test-only bundle also exercises scrolling through many rewards.
	var catalog: Dictionary = Packs.PACKS.duplicate(true)
	catalog["all"]["rewards"] = 5
	var rng := RandomNumberGenerator.new()
	rng.seed = 8421
	var rewards := Packs.open(collection.profile, "all", false, rng, catalog)
	SaveStore.save_profile(collection.profile)
	collection._refresh()
	collection._reveal("all", rewards)
	var opening: PackOpening = collection._opening
	opening._timeline.custom_step(10)
	await create_timer(0.3).timeout
	await _snapshot("12-bundle-first.png")
	opening._advance()
	await create_timer(0.75).timeout
	await _snapshot("13-bundle-next.png")
	opening.show_all_rewards()
	await create_timer(0.4).timeout
	await _snapshot("14-bundle-summary.png")
	opening.advance_or_close()
	await create_timer(0.3).timeout


func _capture_studio(profile: Dictionary) -> void:
	# Representative saved progress using the real generator, save format and board.
	var picture := PuzzleMaker.make({"type": "mandala", "seed": 3, "pattern_seed": 21, "theme": "rainbow"},
		profile["unlocks"])
	if picture.is_empty():
		push_error("Could not generate the render fixture")
		quit(1)
		return
	var meta := SaveStore.add_puzzle(profile, picture)
	meta["powers"] = ["double_coins"]
	var placed := PackedByteArray()
	placed.resize(picture["slots"].size())
	for i in placed.size() / 3:
		placed[i] = 1
	meta["filled"] = placed.size() / 3
	SaveStore.save_progress(meta["id"], placed)
	SaveStore.save_thumbnail(meta["id"], Thumbnail.render(picture, placed, 400))
	for power: String in ["big_brush", "finder", "sprinkle"]:
		profile["powers"][power] = 2
	SaveStore.save_profile(profile)
	var studio := MainMenu.new()
	studio.profile = profile
	studio.show_developer_tools = false
	root.add_child(studio)
	await create_timer(0.35).timeout
	await _snapshot("07-saved-puzzles.png")
	studio.queue_free()
	await process_frame
	var play := PlayScreen.new()
	play.profile = profile
	play.puzzle_id = meta["id"]
	root.add_child(play)
	await create_timer(0.8).timeout
	await _snapshot("08-game-controls.png")
	play._open_settings()
	await create_timer(0.35).timeout
	await _snapshot("15-board-settings.png")
	play.go_back()
	play._toggle_powers()
	await create_timer(0.35).timeout
	await _snapshot("09-power-ups.png")
	play._powers_panel.close()
	play._overlay.placed.fill(1)
	play._filled = placed.size()
	play._board.show_collage(play._picture, play._overlay.placed)
	play._update_progress()
	play._finish(true)
	play._show_rewards()
	await create_timer(0.5).timeout
	await _snapshot("10-completion-rewards.png")
	play.queue_free()
	await process_frame
	SaveStore.delete_puzzle(profile, meta["id"])


func _snapshot(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	if capture == null or capture.is_empty():
		push_error("No rendered image: use a real display/rendering driver, not --headless.")
		quit(1)
		return
	var error := capture.save_png(_out.path_join(filename))
	if error != OK:
		push_error("Could not save " + filename)
		quit(1)
	print("Captured ", filename, " ", capture.get_size())

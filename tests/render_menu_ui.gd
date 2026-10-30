extends SceneTree
## Captures the actual player UI with a real rendering driver (for example,
## xvfb-run -a godot --path . --resolution 1080x2400 -s res://tests/render_menu_ui.gd).

const GameTheme := preload("res://scenes/game/game_theme.gd")
const MenuBackdrop := preload("res://scenes/game/menu_backdrop.gd")
const MainMenu := preload("res://scenes/game/main_menu.gd")
const CollectionScreen := preload("res://scenes/game/collection_screen.gd")
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
	root.add_child(menu)
	await create_timer(0.8).timeout
	await _snapshot("01-main-menu.png")
	menu.queue_free()
	await process_frame
	var collection := CollectionScreen.new()
	collection.profile = profile
	root.add_child(collection)
	await create_timer(1.2).timeout
	await _snapshot("02-pack-picker.png")
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
	print("UI renders saved to ", ProjectSettings.globalize_path(_out))
	quit()


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

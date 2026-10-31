extends SceneTree
## Actual splash and gem reveal captures. Run with a real display/rendering driver.
## Pass -- --frames to also export a 30 fps sequence for an animation preview.
## Use an isolated XDG_DATA_HOME: this writes a fixture profile for the capture.

const AppScene := preload("res://scenes/game/app.tscn")
const GemMenuReveal := preload("res://scenes/game/gem_menu_reveal.gd")
var _out := "res://build/splash-renders"
var _frames := false


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--frames":
			_frames = true
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_capture.call_deferred()


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var profile := SaveStore.upgrade({"wallet": {"coins": 90, "picks": 3}})
	profile["daily"]["opened"] = Packs.today()
	SaveStore.save_profile(profile)
	var app = AppScene.instantiate()
	root.add_child(app)
	app._splash._timer.stop()
	await create_timer(1.0).timeout
	await _snapshot("01-splash.png")
	app._splash._finish()
	while app._reveal._motion == null:
		await process_frame
	var reveal: Control = app._reveal
	reveal._motion.pause()
	if _frames:
		var frames := ceili(GemMenuReveal.DURATION * 30.0) + 1
		for frame in frames:
			reveal._set_progress(float(frame) / float(frames - 1))
			await _snapshot("reveal-%02d.png" % frame)
	else:
		reveal._set_progress(0.45)
		await _snapshot("02-gem-reveal.png")
	reveal._set_progress(1.0)
	await _snapshot("03-revealed-menu.png")
	reveal._motion.kill()
	app._finish_reveal()
	await _snapshot("04-live-menu.png")
	print("Splash captures saved to ", ProjectSettings.globalize_path(_out))
	quit()


func _snapshot(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	if capture == null or capture.is_empty() or capture.save_png(_out.path_join(filename)) != OK:
		push_error("Could not capture the splash. Use a real display, not --headless.")
		quit(1)
		return
	print("Captured ", filename)

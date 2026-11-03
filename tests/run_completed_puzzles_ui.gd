extends SceneTree
## Isolate XDG_DATA_HOME: checks exercise real puzzle saves, restart and recolor.
## godot --headless --path . -s res://tests/run_completed_puzzles_ui.gd

const GameTheme := preload("res://scenes/game/game_theme.gd")
const MainMenu := preload("res://scenes/game/main_menu.gd")
const PlayScreen := preload("res://scenes/game/play_screen.gd")
var _checks := 0
var _failures := 0
var _played := []


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: ", message)


func _frames() -> void:
	for _i in 8:
		await process_frame


func _settle(dialog: GameDialog) -> void:
	if dialog._motion != null and dialog._motion.is_valid():
		dialog._motion.kill()
	dialog.card.scale = Vector2.ONE
	await _frames()


func _run() -> void:
	root.content_scale_size = Vector2i(1080, 2400)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.theme = GameTheme.build()
	var profile := SaveStore.upgrade({"wallet": {"coins": 25, "picks": 2}})
	profile["unlocks"] = Unlockables.all_unlocks()
	var completed := []
	for type: String in ["mandala", "flower", "heart", "butterfly", "kit", "photo_collage", "photo_kit", "snowflake"]:
		completed.append(_save_fixture(profile, type, true)["id"])
	for _i in 2:
		_save_fixture(profile, "mandala", false)
	SaveStore.save_profile(profile)
	var menu := MainMenu.new()
	menu.profile = profile
	menu.play_requested.connect(func(id: String) -> void: _played.append(id))
	root.add_child(menu)
	await _frames()
	await _test_gallery(menu, completed)
	await _test_cancel_recolor(menu, completed[0])
	await _test_admire(menu, completed[0])
	await _test_restart(menu, completed[1])
	for id: String in [completed[0], completed[4], completed[5], completed[6]]:
		await _test_recolor_copy(menu, id)
	_test_recolor_colors()
	menu.queue_free()
	await process_frame
	for meta: Dictionary in profile["puzzles"].duplicate():
		SaveStore.delete_puzzle(profile, meta["id"])
	print("Completed puzzles UI: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _save_fixture(profile: Dictionary, type: String, done: bool) -> Dictionary:
	var picture := _kit(type) if type in ["kit", "photo_kit"] else _collage(type)
	var meta := SaveStore.add_puzzle(profile, picture)
	var placed := PackedByteArray()
	placed.resize(picture["slots"].size())
	placed.fill(1 if done else 0)
	meta["done"] = done
	meta["filled"] = placed.size() if done else 0
	meta["rewarded"] = done
	SaveStore.save_progress(meta["id"], placed)
	SaveStore.save_thumbnail(meta["id"], Thumbnail.render(picture, placed))
	return meta


func _collage(type: String, count := 4) -> Dictionary:
	var slots := []
	var regions := []
	for i in count:
		slots.append({"id": i, "region": i, "shape": "round", "cut": "brilliant", "x": 10.0 + i % 8 * 10,
			"y": 20.0 + i / 8 * 20, "rotation": 0.0, "size": 8.0, "width": 8.0,
			"tone": 0, "part": 0, "target_gem": "ruby", "target_color": GemCatalog.color_of("ruby")})
		regions.append({"id": i, "group": i / 2, "color": GemCatalog.color_of("ruby")})
	return {"version": 2, "type": "collage", "width": 100, "height": 100, "slots": slots,
		"regions": regions, "lines": PackedByteArray(), "lines_visible": PackedByteArray(),
		"source": {"kind": "photo" if type == "photo_collage" else "mandala"},
		"puzzle": {"type": type, "seed": 42, "pattern_seed": 7, "layout": "dense", "theme": "rainbow"}}


func _kit(type: String) -> Dictionary:
	var picture := {"version": 2, "type": "collage", "kind": "kit", "width": 20, "height": 20,
		"lines": PackedByteArray(), "lines_visible": PackedByteArray(), "regions": [],
		"kit_grid": {"cols": 2, "rows": 2, "cells": PackedByteArray([0, 1, 1, 0]), "drill": "round", "cut": "brilliant",
			"palette": [{"gem": "ruby", "color": GemCatalog.color_of("ruby")},
				{"gem": "sapphire", "color": GemCatalog.color_of("sapphire")}]},
		"source": {"kind": "photo" if type == "photo_kit" else "mandala"},
		"puzzle": {"type": type, "seed": 42, "pattern_seed": 7, "theme": "rainbow", "kit_size": "small"}}
	picture["slots"] = PuzzleMaker.kit_slots(picture)
	return picture


func _test_gallery(menu: Control, completed: Array) -> void:
	_check(menu._list.get_child_count() == 2, "The studio contains only unfinished puzzles")
	_check(menu._completed._tiles.size() == completed.size(), "Finished puzzles have their own section")
	_check(menu._completed._grid.columns == 3, "The completed gallery always has three columns")
	var scrolls := menu.find_children("*", "ScrollContainer", true, false).filter(
		func(sc: ScrollContainer) -> bool: return sc.is_visible_in_tree())
	_check(scrolls == [menu._menu_scroll], "The menu is one scroll, with no list scrolling inside it")
	var order: Array = (menu._list.get_parent() as Control).get_children()
	_check(order.find(menu._studio_heading) < order.find(menu._list) and order.find(menu._list) < order.find(menu._completed),
		"In-progress puzzles come first, then the completed ones")
	_check(menu._studio_heading.title == "In your studio · 2" and menu._completed._heading.title.ends_with("· %d" % completed.size()),
		"Each section's heading counts its puzzles")
	menu._studio_heading.pressed.emit()
	_check(not menu._list.visible and menu.profile["settings"][menu.STUDIO_OPEN_KEY] == false,
		"In your studio folds away, and remembers it")
	_check(SaveStore.load_profile()["settings"].get(menu.STUDIO_OPEN_KEY) == false, "The folded section is saved")
	menu._completed._heading.pressed.emit()
	_check(not menu._completed._body.visible and menu.profile["settings"][menu.COMPLETED_OPEN_KEY] == false,
		"Completed puzzles fold away, and remember it")
	menu._refresh_list()
	_check(not menu._list.visible and not menu._completed._body.visible, "Refreshing the list keeps folded sections folded")
	menu._studio_heading.pressed.emit()
	menu._completed._heading.pressed.emit()
	_check(menu._list.visible and menu._completed._body.visible and menu.profile["settings"][menu.STUDIO_OPEN_KEY]
		and menu.profile["settings"][menu.COMPLETED_OPEN_KEY], "Tapping the headings opens both again")
	for viewport: Vector2i in [Vector2i(1080, 2400), Vector2i(900, 1600), Vector2i(720, 1280)]:
		root.content_scale_size = viewport
		await _frames()
		var tiles: Array = menu._completed._grid.get_children()
		for i in tiles.size():
			var tile: Button = tiles[i]
			_check(tile.get_global_rect().position.x >= 0 and tile.get_global_rect().end.x <= viewport.x,
				"Completed thumbnail fits at %d: %s" % [viewport.x, tile.get_global_rect()])
			_check(is_equal_approx(tile.position.y, tiles[i / 3 * 3].position.y), "Completed pictures share rows of three")
			if i >= 3:
				_check(tile.position.y > tiles[i - 3].position.y, "Additional pictures create another row")
		var bar: ScrollBar = menu._menu_scroll.get_v_scroll_bar()
		menu._menu_scroll.scroll_vertical = int(bar.max_value - bar.page)
		await _frames()
		_check(tiles.back().get_global_rect().intersects(menu._menu_scroll.get_global_rect()), "The last completed row is reachable")
		(menu._completed._tiles[completed[0]] as Button).pressed.emit()
		await _settle(menu._completed_panel)
		var card: Rect2 = menu._completed_panel.card.get_global_rect()
		_check(card.position.x >= 0 and card.end.x <= viewport.x, "Completed actions fit the screen")
		_check(menu._completed_panel.actions.get_global_rect().end.y <= viewport.y, "Completed actions stay reachable")
		menu.go_back()
	root.content_scale_size = Vector2i(1080, 2400)
	var empty := CompletedPuzzles.new()
	empty.set_puzzles([])
	_check(empty._empty.visible and not empty._grid.visible, "An empty gallery has a helpful empty state")
	empty.free()


func _snapshot(menu: Control, id: String) -> Dictionary:
	return {"meta": JSON.stringify(SaveStore.find(menu.profile, id)),
		"picture": FileAccess.get_file_as_bytes(SaveStore.DIR.path_join(id + ".json")),
		"progress": FileAccess.get_file_as_bytes(SaveStore.DIR.path_join(id + ".progress")),
		"thumbnail": FileAccess.get_file_as_bytes(SaveStore.DIR.path_join(id + ".png"))}


func _test_cancel_recolor(menu: Control, id: String) -> void:
	var before := _snapshot(menu, id)
	var profile_text := FileAccess.get_file_as_string(SaveStore.DIR.path_join("profile.json"))
	for mode: String in ["back", "close", "cancel"]:
		(menu._completed._tiles[id] as Button).pressed.emit()
		menu._completed_panel._recolor.pressed.emit()
		_check(menu._story_picker.visible and not menu._new_panel.visible and not menu._completed_panel.visible,
			"Recolor opens color selection directly without confirmation")
		_check(menu._direct_recolor and menu._task_id == -1, "Recolor waits for a color choice before doing any work")
		if mode == "back":
			menu.go_back()
		elif mode == "close":
			menu._story_picker._close.pressed.emit()
		else:
			for button: Button in menu._story_picker.actions.find_children("*", "Button", true, false):
				if button.text == "Cancel":
					button.pressed.emit()
		_check(not menu._direct_recolor and not menu._busy.visible and menu._task_id == -1, "Cancel leaves no pending recolor")
		_check(_snapshot(menu, id) == before, "Cancelling recolor leaves all original puzzle files and metadata unchanged")
		_check(FileAccess.get_file_as_string(SaveStore.DIR.path_join("profile.json")) == profile_text,
			"Cancelling color selection never writes the profile")
	# Making a custom story works even when the creation workshop has never opened.
	menu._open_completed(id)
	menu._completed_panel._recolor.pressed.emit()
	menu._story_picker._make.pressed.emit()
	for gem: String in ["ruby", "sapphire"]:
		menu._story_editor._toggle(gem)
	menu._story_editor._save.pressed.emit()
	_check(menu._story_picker.visible and menu._direct_recolor, "A custom story can be created while choosing recolor colors")
	menu.go_back()
	_check(_snapshot(menu, id) == before, "Cancelling after story creation still preserves the completed puzzle")


func _test_admire(menu: Control, id: String) -> void:
	var before := _snapshot(menu, id)
	var wallet: Dictionary = menu.profile["wallet"].duplicate()
	menu._open_completed(id)
	menu._completed_panel._admire.pressed.emit()
	_check(_played.back() == id and not menu._completed_panel.visible, "Admire opens the selected completed puzzle")
	_check(_snapshot(menu, id) == before, "Choosing Admire never resets the puzzle")
	var play := PlayScreen.new()
	play.profile = menu.profile
	play.puzzle_id = id
	root.add_child(play)
	await _frames()
	_check(play._done and not play._palette.visible and not play._overlay.visible, "Admire loads the completed viewing mode")
	_check(not play._board.is_celebrating() and menu.profile["wallet"] == wallet, "Admiring grants no new rewards or finale")
	play.queue_free()
	await process_frame


func _test_restart(menu: Control, id: String) -> void:
	var before := _snapshot(menu, id)
	var wallet: Dictionary = menu.profile["wallet"].duplicate()
	menu._open_completed(id)
	menu._completed_panel._restart.pressed.emit()
	_check(menu._completed_panel._confirming, "Restart prompts for confirmation")
	_check(_snapshot(menu, id) == before, "Showing the restart prompt leaves progress untouched")
	menu._completed_panel._cancel.pressed.emit()
	_check(not menu._completed_panel._confirming and _snapshot(menu, id) == before, "Cancelling restart keeps the completed picture")
	menu._completed_panel._restart.pressed.emit()
	menu.go_back()
	_check(not menu._completed_panel._confirming and menu._completed_panel.visible, "Back cancels confirmation before leaving")
	menu._completed_panel._restart.pressed.emit()
	menu._completed_panel._restart.pressed.emit()
	await _frames()
	var meta := SaveStore.find(menu.profile, id)
	_check(not meta["done"] and meta["filled"] == 0, "Confirmed restart clears the completion state")
	_check(not 1 in SaveStore.load_progress(id, meta["total"]), "Confirmed restart clears the saved placed gems")
	_check(_played.back() == id, "Confirmed restart opens the puzzle to play again")
	_check(not menu._completed._tiles.has(id) and menu._list.get_child_count() == 3,
		"Restart moves the picture back into the studio")
	_check(menu.profile["wallet"] == wallet and meta["rewarded"], "Restart preserves the reward ledger and wallet")
	_check(FileAccess.get_file_as_bytes(SaveStore.DIR.path_join(id + ".json")) == before["picture"],
		"Restart retains the saved layout")


func _test_recolor_copy(menu: Control, id: String) -> void:
	var before := _snapshot(menu, id)
	var picture := SaveStore.load_picture(id)
	var count: int = menu.profile["puzzles"].size()
	menu._open_completed(id)
	menu._completed_panel._recolor.pressed.emit()
	(menu._story_picker._buttons["primary"] as Button).pressed.emit()
	for _i in 120:
		if menu._task_id < 0:
			break
		await process_frame
	_check(menu._task_id < 0 and menu.profile["puzzles"].size() == count + 1, "Choosing colors creates one playable copy")
	var new_id: String = _played.back()
	var meta := SaveStore.find(menu.profile, new_id)
	_check(new_id != id and not meta["done"] and meta["filled"] == 0, "Recolor starts a new unfinished puzzle")
	_check(meta["theme"] == "primary", "The copy uses the chosen story")
	_check(meta["layout"] == SaveStore.find(menu.profile, id).get("layout", "classic"), "The copy retains its saved layout version")
	var copy := SaveStore.load_picture(new_id)
	_check_layout_unchanged(picture, copy)
	_check(copy["slots"].all(func(slot: Dictionary) -> bool: return slot["target_gem"] in GemCatalog.THEMES["primary"]["gems"]),
		"Every recolored gem belongs to the chosen story")
	_check(_snapshot(menu, id) == before, "Recoloring preserves every file and metadata field of the completed original")
	_check(SaveStore.find(SaveStore.load_profile(), id)["done"], "The completed original remains completed after reloading")
	menu._busy.hide()  # The real app switches to the emitted play screen here.


func _test_recolor_colors() -> void:
	var picture := _collage("mandala", 16)
	var original := PatternIO.to_json(picture)
	for gems: Array in [["ruby", "sapphire"], GemCatalog.THEMES["kaleidoscope"]["gems"]]:
		var copy := PuzzleRecolor.make(picture, {"type": "mandala", "theme": "mine_test", "theme_gems": gems})
		_check_layout_unchanged(picture, copy)
		var used := {}
		for slot: Dictionary in copy["slots"]:
			used[slot["target_gem"]] = true
		_check(used.size() == gems.size(), "Saved-layout recoloring supports two and eight colors")
		_check(copy["slots"][0]["target_color"] == copy["slots"][1]["target_color"], "Symmetric regions keep matching colors")
	_check(PatternIO.to_json(picture) == original, "The recolorer never mutates its source")


func _check_layout_unchanged(original: Dictionary, copy: Dictionary) -> void:
	_check(original["slots"].size() == copy["slots"].size(), "Recolor preserves every gem slot")
	for i in original["slots"].size():
		for key: String in ["id", "region", "shape", "cut", "x", "y", "rotation", "size", "width", "tone", "part"]:
			_check(original["slots"][i].get(key) == copy["slots"][i].get(key), "Recolor preserves slot %d %s" % [i, key])
	if original.has("kit_grid"):
		_check(original["kit_grid"]["cells"] == copy["kit_grid"]["cells"], "Kit colors survive saving as the same grid")

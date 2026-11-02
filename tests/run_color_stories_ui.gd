extends SceneTree
## Use an isolated XDG_DATA_HOME: saving and deleting exercise the real profile API.
## godot --headless --path . -s res://tests/run_color_stories_ui.gd

const GameTheme := preload("res://scenes/game/game_theme.gd")
const MainMenu := preload("res://scenes/game/main_menu.gd")
var _checks := 0
var _failures := 0


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: ", message)


func _frames() -> void:
	for _i in 5:
		await process_frame


func _run() -> void:
	root.content_scale_size = Vector2i(1080, 2400)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.theme = GameTheme.build()
	var menu := MainMenu.new()
	menu.profile = SaveStore.upgrade({})
	menu.profile["unlocks"] = Unlockables.all_unlocks()
	root.add_child(menu)
	menu._open_new({})
	await _frames()
	for i in menu._theme.item_count:
		var id: String = menu._theme.get_item_metadata(i)
		var gems: Array = menu._theme_gems(id)
		menu._theme.select(i)
		menu._theme.item_selected.emit(i)
		_check(menu._theme.get_item_icon(i) != null, "Selector previews " + id)
		_check(menu._theme_preview.get_child_count() == gems.size(), "Every selected color is shown: " + id)
		_check(str(gems.size()) in menu._theme_count.text, "The selected count matches " + id)
		var image := menu._theme.get_item_icon(i).get_image()
		for at in gems.size():
			_check(image.get_pixel(at * 32 + 8, 8).is_equal_approx(GemCatalog.color_of(gems[at])),
				"Thumbnail preserves the ordered palette: %s %d" % [id, at])
	var editor: ColorStoryEditor = menu._story_editor
	editor.edit()
	await _frames()
	_check(editor._save.disabled, "An empty story cannot save")
	var choices: Array = editor._swatches.keys().slice(0, GemCatalog.MAX_THEME_COLORS + 1)
	for i in GemCatalog.MAX_THEME_COLORS:
		(editor._swatches[choices[i]] as Button).pressed.emit()
		_check(editor._save.disabled == (i + 1 < CustomThemes.MIN_COLORS), "Save follows the color limits")
	var picked := editor._picked.duplicate()
	(editor._swatches[choices.back()] as Button).pressed.emit()
	_check(editor._picked == picked, "A ninth color cannot be added")
	_check("Remove a color" in editor._note.text, "The maximum explains how to make room")
	_check(editor._strip.get_child_count() == GemCatalog.MAX_THEME_COLORS, "Every selected color is removable")
	await _frames()
	_check(editor._strip.get_child(0).position.y < editor._strip.get_child(GemCatalog.MAX_THEME_COLORS - 1).position.y,
		"Eight selected colors wrap instead of overflowing")
	editor._reverse.pressed.emit()
	picked.reverse()
	_check(editor._picked == picked, "Reverse changes the actual saved color order")
	(editor._strip.get_child(0) as Button).pressed.emit()
	_check(editor._picked.size() == GemCatalog.MAX_THEME_COLORS - 1, "Tapping the selected palette removes a color")
	(editor._swatches[choices.back()] as Button).pressed.emit()
	_check(editor._picked.size() == GemCatalog.MAX_THEME_COLORS, "Removing makes room for a replacement")
	editor._search.text = "  SaPpHiRe  "
	editor._search.text_changed.emit(editor._search.text)
	_check((editor._swatches["sapphire"] as Button).visible and not (editor._swatches["ruby"] as Button).visible,
		"Search is case insensitive, trims spaces and filters by name")
	editor._hue.select(GemCatalog.HUE_ORDER.find("red") + 1)
	editor._hue.item_selected.emit(editor._hue.selected)
	_check(editor._empty.visible, "Search and family filters combine with empty-state feedback")
	_check(editor._picked.size() == GemCatalog.MAX_THEME_COLORS and not editor._save.disabled,
		"Filtering never loses the selected colors")
	editor._name.text = "Eight colors"
	var expected := editor._picked.duplicate()
	editor._save.pressed.emit()
	var custom_id: String = menu._selected_theme()
	_check(CustomThemes.find(menu.profile, custom_id).get("gems") == expected, "Saving preserves all eight colors in order")
	_check(menu._theme_preview.get_child_count() == GemCatalog.MAX_THEME_COLORS and menu._edit_story.visible,
		"The saved story is selected and editable in the workshop")
	_check(CustomThemes.find(SaveStore.load_profile(), custom_id).get("gems") == expected, "The saved order survives reloading")
	await _frames()
	for viewport: Vector2i in [Vector2i(1080, 2400), Vector2i(900, 1600), Vector2i(720, 1280)]:
		root.content_scale_size = viewport
		editor.edit(custom_id)
		await _frames()
		_check_layout(editor, viewport.x)
		editor.close()
		await _frames()
		_check_layout(menu._new_panel, viewport.x)
	root.content_scale_size = Vector2i(1080, 2400)
	editor.edit(custom_id)
	editor._clear.pressed.emit()
	_check(editor._picked.is_empty() and editor._save.disabled and editor._strip.get_child_count() == 0,
		"Clear resets the palette and validation")
	for gem: String in ["ruby", "sapphire"]:
		(editor._swatches[gem] as Button).pressed.emit()
	_check(not editor._save.disabled, "The custom minimum of two colors is supported")
	editor._save.pressed.emit()
	_check(CustomThemes.find(menu.profile, custom_id)["gems"] == ["ruby", "sapphire"], "Editing keeps the story id")
	editor.edit(custom_id)
	editor._delete.pressed.emit()
	_check(not CustomThemes.find(menu.profile, custom_id).is_empty(), "Deletion requires a second tap")
	editor._delete.pressed.emit()
	_check(CustomThemes.find(menu.profile, custom_id).is_empty() and not CustomThemes.is_custom(menu._selected_theme()),
		"Deleting selects an available collection theme")
	# A full story library blocks creation while still allowing existing stories to be edited.
	for i in CustomThemes.MAX_THEMES:
		CustomThemes.save(menu.profile, "Story %d" % i, ["ruby", "sapphire"])
	editor.edit()
	for gem: String in ["ruby", "sapphire"]:
		(editor._swatches[gem] as Button).pressed.emit()
	_check(editor._save.disabled and "make room" in editor._note.text, "The story limit is explained before saving")
	editor.edit(CustomThemes.list(menu.profile)[0]["id"])
	_check(not editor._save.disabled, "An existing story can still be edited at the limit")
	editor.close()
	menu._refresh_new()
	_check(menu._make_story.disabled, "Creation is disabled at the library limit")
	menu.queue_free()
	await process_frame
	# Starter profiles expose only owned colors.
	var owned := ColorStoryEditor.new()
	owned.profile = SaveStore.upgrade({})
	root.add_child(owned)
	owned.edit()
	_check(owned._swatches.keys().all(func(g: String) -> bool: return g in owned.profile["unlocks"]["colors"]),
		"Locked colors are never offered in the editor")
	owned.queue_free()
	await process_frame
	print("Color stories UI: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check_layout(dialog: GameDialog, width: float) -> void:
	var card := dialog.card.get_global_rect()
	_check(card.position.x >= -1 and card.end.x <= width + 1,
		"Dialog fits at %d: %s %s" % [width, dialog.title_label.text, card])
	_check(dialog.actions.get_global_rect().end.y <= dialog.size.y, "Actions stay on screen at %d" % width)
	for control: Control in dialog.find_children("*", "Control", true, false):
		if control is Button and control.is_visible_in_tree():
			_check(control.get_global_rect().end.x <= card.end.x + 1, "Button fits the dialog at %d: %s" % [width, control.tooltip_text])

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


func _settle(dialog: GameDialog) -> void:
	# Keep entrance animation out of coordinate comparisons.
	if dialog._motion != null and dialog._motion.is_valid():
		dialog._motion.kill()
	dialog.card.scale = Vector2.ONE
	await _frames()


func _run() -> void:
	root.content_scale_size = Vector2i(1080, 2400)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.theme = GameTheme.build()
	var menu := MainMenu.new()
	menu.profile = SaveStore.upgrade({})
	menu.profile["unlocks"] = Unlockables.all_unlocks()
	root.add_child(menu)
	menu._open_new({})
	await _settle(menu._new_panel)
	await _test_picker(menu)
	var custom_id: String = await _test_editor(menu)
	await _test_layouts(menu, custom_id)
	await _test_lifecycle(menu, custom_id)
	_test_capacity(menu)
	menu.queue_free()
	await process_frame
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


func _test_picker(menu: Control) -> void:
	var picker: ColorStoryPicker = menu._story_picker
	_check(menu._theme.get_parent().get_child_count() == 2,
		"The workshop has one color-story field with no separate duplicate preview")
	_check(picker.actions.is_ancestor_of(picker._make) and not menu._new_panel.is_ancestor_of(picker._make),
		"Create my own story lives inside color selection")
	menu._theme.pressed.emit()
	await _settle(picker)
	_check(picker.visible and not menu._new_panel.can_process(), "Color selection opens and freezes the workshop")
	var bar := picker.body_scroll.get_v_scroll_bar()
	_check(bar.max_value > bar.page, "The entire story library scrolls inside the selector")
	for story: Dictionary in picker.stories:
		var button: Button = picker._buttons[story["id"]]
		var art: TextureRect = button.find_children("*", "TextureRect", true, false)[0]
		var image := art.texture.get_image()
		for at in story["gems"].size():
			_check(image.get_pixel(at * 48 + 8, 8).is_equal_approx(GemCatalog.color_of(story["gems"][at])),
				"Story browser shows every color in order: %s %d" % [story["id"], at])
	await _check_touch_scroll(picker.body_scroll)
	picker.body_scroll.scroll_vertical = 0
	await _frames()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = picker.body_scroll.get_global_rect().get_center()
	root.push_input(wheel, true)
	await _frames()
	_check(picker.body_scroll.scroll_vertical > 0, "Mouse wheel scrolls the story library")
	picker.body_scroll.scroll_vertical = int(bar.max_value - bar.page)
	await _frames()
	var last: Button = picker._buttons[picker.stories.back()["id"]]
	_check(last.get_global_rect().intersects(picker.body_scroll.get_global_rect()), "The last story can be reached")
	picker._search.text = "  sApPhIrE  "
	picker._search.text_changed.emit(picker._search.text)
	_check((picker._buttons["primary"] as Button).visible, "Stories can be searched by color name")
	picker._search.text = "no matching story"
	picker._search.text_changed.emit(picker._search.text)
	_check(picker._empty.visible, "An empty story search explains the result")
	menu.go_back()
	_check(not picker.visible and menu._new_panel.can_process(), "Back returns to the workshop")
	for id: String in ["primary", "kaleidoscope"]:
		menu._theme.pressed.emit()
		(picker._buttons[id] as Button).pressed.emit()
		_check(menu._selected_theme() == id and not picker.visible, "Tapping a story applies it and returns")
		_check(menu._theme.icon.get_width() == menu._theme_gems(id).size() * 32,
			"The single selected preview supports small and large palettes")


func _check_touch_scroll(scroll: ScrollContainer) -> void:
	var drag: DragScroll
	for child in scroll.get_children():
		if child is DragScroll:
			drag = child
	_check(drag != null, "The scroll area supports finger dragging")
	if drag == null:
		return
	var start := scroll.get_global_transform_with_canvas() * (scroll.size / 2.0)
	var touch := InputEventScreenTouch.new()
	touch.index = 7
	touch.pressed = true
	touch.position = start
	drag._input(touch)
	var motion := InputEventScreenDrag.new()
	motion.index = 7
	motion.position = start - Vector2(0, 120)
	drag._input(motion)
	touch.pressed = false
	touch.position = motion.position
	drag._input(touch)
	drag._fling = 0
	await _frames()
	_check(scroll.scroll_vertical > 0, "Dragging a story card scrolls the list")


func _test_editor(menu: Control) -> String:
	var picker: ColorStoryPicker = menu._story_picker
	var editor: ColorStoryEditor = menu._story_editor
	menu._theme.pressed.emit()
	picker._make.pressed.emit()
	await _settle(editor)
	_check(editor.visible and picker.visible and not picker.can_process(), "Creating a story opens from selection")
	_check(editor.pinned.is_ancestor_of(editor._strip) and not editor.body_scroll.is_ancestor_of(editor._strip),
		"Selected colors are pinned above the scrolling available colors")
	_check(editor._save.disabled, "An empty story cannot save")
	editor.body_scroll.scroll_vertical = 500
	await _frames()
	var viewport := editor.body_scroll.get_global_rect()
	var pinned := editor._strip.get_global_rect()
	var offset := editor.body_scroll.scroll_vertical
	var palette_at := editor._palette.get_global_rect().position
	var choices: Array = editor._swatches.keys().slice(0, GemCatalog.MAX_THEME_COLORS + 1)
	for i in GemCatalog.MAX_THEME_COLORS:
		(editor._swatches[choices[i]] as Button).pressed.emit()
		await _frames()
		_check(editor._save.disabled == (i + 1 < CustomThemes.MIN_COLORS), "Save follows the color limits")
		_check(editor.body_scroll.get_global_rect().is_equal_approx(viewport), "Adding a color never resizes the list")
		_check(editor._strip.get_global_rect().is_equal_approx(pinned), "Selected colors stay pinned as colors are added")
		_check(editor.body_scroll.scroll_vertical == offset and editor._palette.get_global_rect().position.is_equal_approx(palette_at),
			"Adding a color never shifts the available colors or scroll position")
	var picked := editor._picked.duplicate()
	(editor._swatches[choices.back()] as Button).pressed.emit()
	_check(editor._picked == picked and "Remove a color" in editor._note.text, "The maximum explains how to make room")
	editor._reverse.pressed.emit()
	picked.reverse()
	_check(editor._picked == picked, "Reverse changes the saved color order")
	(editor._strip.get_child(0) as Button).pressed.emit()
	_check(editor._picked.size() == GemCatalog.MAX_THEME_COLORS - 1, "The pinned palette can remove a color")
	(editor._swatches[choices.back()] as Button).pressed.emit()
	_check(editor._picked.size() == GemCatalog.MAX_THEME_COLORS, "Removing makes room for a replacement")
	editor._search.text = "  SaPpHiRe  "
	editor._search.text_changed.emit(editor._search.text)
	_check((editor._swatches["sapphire"] as Button).visible and not (editor._swatches["ruby"] as Button).visible,
		"Color search trims spaces and ignores case")
	editor._hue.select(GemCatalog.HUE_ORDER.find("red") + 1)
	editor._hue.item_selected.emit(editor._hue.selected)
	_check(editor._empty.visible, "Search and family filters combine with empty-state feedback")
	_check(editor._picked.size() == GemCatalog.MAX_THEME_COLORS and not editor._save.disabled, "Filtering keeps the selected colors")
	editor._name.text = "W".repeat(CustomThemes.MAX_NAME)
	var expected := editor._picked.duplicate()
	editor._save.pressed.emit()
	var custom_id: String = menu._selected_theme()
	_check(picker.visible and not editor.visible and picker.can_process(), "Saving returns to color selection")
	_check(CustomThemes.find(menu.profile, custom_id).get("gems") == expected, "Saving preserves eight colors in order")
	_check(picker._edit.visible, "The new story can be edited from color selection")
	_check(CustomThemes.find(SaveStore.load_profile(), custom_id).get("gems") == expected, "The saved order survives reloading")
	menu.go_back()
	return custom_id


func _test_layouts(menu: Control, custom_id: String) -> void:
	var editor: ColorStoryEditor = menu._story_editor
	var picker: ColorStoryPicker = menu._story_picker
	for viewport: Vector2i in [Vector2i(1080, 2400), Vector2i(900, 1600), Vector2i(720, 1280)]:
		root.content_scale_size = viewport
		menu._theme.pressed.emit()
		editor.edit(custom_id)
		await _settle(picker)
		await _settle(editor)
		_check_layout(editor, viewport.x)
		var selected := editor._strip.get_global_rect()
		_check(selected.end.y <= editor.body_scroll.get_global_rect().position.y, "Selected colors stay above the color list")
		var list_rect := editor.body_scroll.get_global_rect()
		editor.body_scroll.scroll_vertical = 800
		await _frames()
		_check(editor._strip.get_global_rect().is_equal_approx(selected), "Scrolling never hides the selected colors")
		_check(editor.body_scroll.size.y >= 140, "The color list has usable scrolling space at %d" % viewport.x)
		var offset := editor.body_scroll.scroll_vertical
		var gem: String = editor._picked[0]
		editor._toggle(gem)
		await _frames()
		_check(editor.body_scroll.get_global_rect().is_equal_approx(list_rect) and editor.body_scroll.scroll_vertical == offset,
			"Removing a color never shifts the list at %d" % viewport.x)
		editor._toggle(gem)
		menu.go_back()
		_check(picker.visible and picker.can_process(), "Back from editing returns to color selection")
		_check_layout(picker, viewport.x)
		var card: Button = picker._buttons[custom_id]
		var art: TextureRect = card.find_children("*", "TextureRect", true, false)[0]
		_check(art.get_global_rect().end.y <= card.get_global_rect().end.y,
			"Long story names never push the palette beyond its card at %d" % viewport.x)
		menu.go_back()
		await _settle(menu._new_panel)
		_check_layout(menu._new_panel, viewport.x)
	root.content_scale_size = Vector2i(1080, 2400)


func _test_lifecycle(menu: Control, custom_id: String) -> void:
	var picker: ColorStoryPicker = menu._story_picker
	var editor: ColorStoryEditor = menu._story_editor
	menu._theme.pressed.emit()
	picker._edit.pressed.emit()
	editor._clear.pressed.emit()
	_check(editor._picked.is_empty() and editor._save.disabled and editor._strip.get_child_count() == GemCatalog.MAX_THEME_COLORS,
		"Clear resets validation while preserving the pinned area height")
	for gem: String in ["ruby", "sapphire"]:
		(editor._swatches[gem] as Button).pressed.emit()
	_check(not editor._save.disabled, "The custom minimum of two colors is supported")
	editor._save.pressed.emit()
	_check(CustomThemes.find(menu.profile, custom_id)["gems"] == ["ruby", "sapphire"], "Editing preserves the story id")
	picker._edit.pressed.emit()
	editor._delete.pressed.emit()
	_check(not CustomThemes.find(menu.profile, custom_id).is_empty(), "Deletion requires a second tap")
	editor._delete.pressed.emit()
	_check(CustomThemes.find(menu.profile, custom_id).is_empty() and not CustomThemes.is_custom(menu._selected_theme()),
		"Deleting selects another available story")
	picker._make.pressed.emit()
	editor._toggle("ruby")
	menu.go_back()
	_check(picker.visible and CustomThemes.list(menu.profile).is_empty(), "Cancel returns to selection without saving")
	menu.go_back()


func _test_capacity(menu: Control) -> void:
	for i in CustomThemes.MAX_THEMES:
		CustomThemes.save(menu.profile, "Story %d" % i, ["ruby", "sapphire"])
	menu._fill_themes()
	menu._theme.pressed.emit()
	_check(menu._story_picker._make.disabled, "Creation is disabled inside selection at the library limit")
	var editor: ColorStoryEditor = menu._story_editor
	editor.edit()
	for gem: String in ["ruby", "sapphire"]:
		(editor._swatches[gem] as Button).pressed.emit()
	_check(editor._save.disabled and "make room" in editor._note.text, "The story limit is explained before saving")
	editor.edit(CustomThemes.list(menu.profile)[0]["id"])
	_check(not editor._save.disabled, "An existing story remains editable at the limit")
	menu.go_back()
	menu.go_back()


func _check_layout(dialog: GameDialog, width: float) -> void:
	var card := dialog.card.get_global_rect()
	_check(card.position.x >= -1 and card.end.x <= width + 1,
		"Dialog fits at %d: %s %s" % [width, dialog.title_label.text, card])
	_check(dialog.actions.get_global_rect().end.y <= dialog.size.y, "Actions stay on screen at %d" % width)
	for control: Control in dialog.find_children("*", "Control", true, false):
		if control is Button and control.is_visible_in_tree():
			_check(control.get_global_rect().end.x <= card.end.x + 1, "Button fits the dialog at %d: %s" % [width, control.tooltip_text])

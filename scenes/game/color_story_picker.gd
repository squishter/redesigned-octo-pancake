class_name ColorStoryPicker
extends GameDialog
## Scrollable color-story browsing; creation and editing live in this selector.
## Stories are shown by how many colors they have, then by name, one
## collapsible section per count (a search opens every section it matches in).

signal chosen(theme_id: String)
signal cancelled
signal create_requested
signal edit_requested(theme_id: String)

var stories: Array = []
var selected_id := ""
var can_create := true

var _search: LineEdit
var _make: Button
var _edit: Button
var _empty: Label
var _buttons := {}
## Each color count's section: {header, cards, label}, by count.
var _sections := {}
## Color counts she has folded away, kept while the menu is up.
var _collapsed := {}


func _init() -> void:
	super("Choose a color story", "Browse the colors, then tap a story to use it.", "palette")
	preferred_height = 1840
	pinned.show()
	_search = LineEdit.new()
	_search.placeholder_text = "Search stories or colors"
	_search.clear_button_enabled = true
	_search.custom_minimum_size.y = GameTheme.TAP_HEIGHT
	_search.add_theme_font_size_override("font_size", 30)
	_search.text_changed.connect(func(_text: String) -> void: _filter())
	pinned.add_child(_search)
	_make = _action(actions, "Create my own story", func() -> void: create_requested.emit())
	_make.icon = GameTheme.icon("palette")
	_make.theme_type_variation = "PrimaryButton"
	var row := HBoxContainer.new()
	actions.add_child(row)
	_edit = _action(row, "Edit story", func() -> void: edit_requested.emit(selected_id))
	_action(row, "Cancel", close)


func set_stories(choices: Array, select_id := "") -> void:
	stories = choices.duplicate()
	stories.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["gems"].size() != b["gems"].size():
			return a["gems"].size() < b["gems"].size()
		var x: String = a["name"].to_lower()
		var y: String = b["name"].to_lower()
		return x < y if x != y else str(a["id"]) < str(b["id"]))
	selected_id = ""
	for story: Dictionary in stories:
		if story["id"] == select_id:
			selected_id = select_id
	if selected_id == "" and not stories.is_empty():
		selected_id = stories.pick_random()["id"]
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_sections.clear()
	for story: Dictionary in stories:
		var count: int = story["gems"].size()
		if not _sections.has(count):
			_sections[count] = _section(count)
		var button := _story_card(story)
		(_sections[count]["cards"] as VBoxContainer).add_child(button)
		_buttons[story["id"]] = button
	_empty = UI.label("No stories match. Try another name or color.", 28, GameTheme.TEXT_DIM)
	body.add_child(_empty)
	_search.text = ""
	_filter()
	_update_selection()
	body_scroll.scroll_vertical = 0


func open() -> void:
	_search.text = ""
	_filter()
	body_scroll.scroll_vertical = 0
	super.open()


func close() -> void:
	var was_visible := visible
	super.close()
	if was_visible:
		cancelled.emit()


## A color count's heading, tapped to fold its stories away or open them.
func _section(count: int) -> Dictionary:
	var header := Button.new()
	header.custom_minimum_size.y = GameTheme.TAP_HEIGHT
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.theme_type_variation = "QuietButton"
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 24
	row.offset_right = -20
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(row)
	var label := UI.label("", 28, GameTheme.MINT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var chevron := UI.icon("chevron_down", 40)
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chevron.resized.connect(func() -> void: chevron.pivot_offset = chevron.size / 2.0)
	row.add_child(chevron)
	body.add_child(header)
	var cards := VBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	body.add_child(cards)
	var section := {"header": header, "cards": cards, "label": label, "chevron": chevron}
	header.pressed.connect(func() -> void:
		_collapsed[count] = not _collapsed.get(count, false)
		_filter())
	return section


func _story_card(story: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = 204
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.theme_type_variation = "ChoiceButton"
	button.toggle_mode = true
	button.tooltip_text = "%s · %d colors\n%s" % [story["name"], story["gems"].size(),
		ColorStorySwatches.names(story["gems"])]
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.minimum_size_changed.connect(func() -> void:
		button.custom_minimum_size.y = maxf(204, inset.get_combined_minimum_size().y))
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 18)
	button.add_child(inset)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 8)
	inset.add_child(copy)
	var title := UI.label(story["name"], 32, GameTheme.GOLD)
	title.max_lines_visible = 2
	copy.add_child(title)
	var about := UI.label("%d colors · %s" % [story["gems"].size(),
		"Your story" if CustomThemes.is_custom(story["id"]) else "Collection story"], 25, GameTheme.TEXT_DIM)
	copy.add_child(about)
	var palette := TextureRect.new()
	palette.texture = ColorStorySwatches.thumbnail(story["gems"], 48)
	palette.custom_minimum_size.y = 48
	palette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	palette.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	copy.add_child(palette)
	for child: Control in button.find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.pressed.connect(func() -> void: _choose(story["id"]))
	return button


func _choose(theme_id: String) -> void:
	if not _buttons.has(theme_id):
		return
	selected_id = theme_id
	_update_selection()
	super.close()
	chosen.emit(theme_id)


## Whether the stories with `colors` colors are folded away.
func is_collapsed(colors: int) -> bool:
	return _collapsed.get(colors, false)


func _update_selection() -> void:
	for id: String in _buttons:
		(_buttons[id] as Button).set_pressed_no_signal(id == selected_id)
	_edit.visible = CustomThemes.is_custom(selected_id)
	_make.disabled = not can_create
	_make.tooltip_text = "Edit or delete a story to make room for another." if not can_create else ""
	contain_focus.call_deferred()


func _filter() -> void:
	var query := _search.text.strip_edges().to_lower()
	var count := 0
	var shown := {}
	for story: Dictionary in stories:
		var button: Button = _buttons[story["id"]]
		button.visible = query == "" or query in button.tooltip_text.to_lower()
		if button.visible:
			count += 1
			shown[story["gems"].size()] = shown.get(story["gems"].size(), 0) + 1
	for colors: int in _sections:
		var section: Dictionary = _sections[colors]
		var n: int = shown.get(colors, 0)
		# A search shows every match, folded away or not.
		var open: bool = query != "" or not _collapsed.get(colors, false)
		(section["header"] as Button).visible = n > 0
		(section["cards"] as Control).visible = n > 0 and open
		(section["label"] as Label).text = "%d COLORS  ·  %d %s" % [colors, n, "story" if n == 1 else "stories"]
		(section["chevron"] as Control).rotation = 0.0 if open else -PI / 2.0
		(section["header"] as Button).tooltip_text = ("Hide" if open else "Show") + " %d-color stories" % colors
	if is_instance_valid(_empty):
		_empty.visible = count == 0
	contain_focus.call_deferred()


func _action(parent: Control, text: String, action: Callable) -> Button:
	var button := GameTheme.button(text)
	button.add_theme_font_size_override("font_size", 30)
	button.theme_type_variation = "QuietButton"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button

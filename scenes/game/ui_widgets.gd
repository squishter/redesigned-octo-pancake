extends RefCounted
## Shared player-facing cards, labels, and meters.

const GameTheme := preload("res://scenes/game/game_theme.gd")


static func label(text: String, px := 32, color := GameTheme.TEXT, centered := false) -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("font_size", px)
	node.add_theme_color_override("font_color", color)
	if centered:
		node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return node


static func icon(glyph: String, px := 72.0) -> TextureRect:
	var node := TextureRect.new()
	node.texture = GameTheme.icon(glyph)
	node.custom_minimum_size = Vector2.ONE * px
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func panel(accent := false, padding := 28) -> PanelContainer:
	var node := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = GameTheme.PANEL
	box.border_color = GameTheme.GOLD if accent else Color("#45526a")
	box.set_border_width_all(2)
	box.set_corner_radius_all(26)
	box.set_content_margin_all(padding)
	node.add_theme_stylebox_override("panel", box)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func progress(value: float) -> ProgressBar:
	var node := ProgressBar.new()
	node.show_percentage = false
	node.custom_minimum_size.y = 14
	node.value = clampf(value, 0, 1) * 100.0
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#141d30")
	track.set_corner_radius_all(7)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = GameTheme.MINT
	node.add_theme_stylebox_override("background", track)
	node.add_theme_stylebox_override("fill", fill)
	return node


static func field(parent: Control, title: String, glyph := "gem") -> OptionButton:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var caption := label(title.to_upper(), 26, GameTheme.MINT)
	row.add_child(caption)
	var options := OptionButton.new()
	options.custom_minimum_size.y = GameTheme.TAP_HEIGHT
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.fit_to_longest_item = false
	options.icon = GameTheme.icon(glyph)
	options.set_meta("row", row)
	options.set_meta("label", caption)
	row.add_child(options)
	return options


static func choice(title: String, about: String, glyph: String) -> Button:
	var node := GameTheme.button("")
	node.icon = null
	node.toggle_mode = true
	node.theme_type_variation = "ChoiceButton"
	node.custom_minimum_size.y = 180
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	row.add_child(icon(glyph, 68))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_theme_constant_override("separation", 6)
	row.add_child(copy)
	for child: Label in [label(title, 34, GameTheme.GOLD), label(about, 25, GameTheme.TEXT_DIM)]:
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.add_child(child)
	return node


static func item(parent: Control, title: String, about: String, glyph: String, bright := true) -> VBoxContainer:
	var card := panel()
	parent.add_child(card)
	var row := HBoxContainer.new()
	card.add_child(row)
	var art := icon(glyph, 74)
	if not bright:
		art.modulate = Color(GameTheme.TEXT_DIM, 0.5)
	row.add_child(art)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 10)
	row.add_child(copy)
	copy.add_child(label(title, 36, GameTheme.GOLD if bright else GameTheme.TEXT_DIM))
	copy.add_child(label(about, 28, GameTheme.TEXT_DIM))
	return copy

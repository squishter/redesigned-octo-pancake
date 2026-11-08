class_name CompletedPuzzles
extends VBoxContainer
## Finished pictures form a three-column gallery in the main page's scroll area,
## under a heading that folds the gallery away or opens it (`open_changed`).

signal chosen(puzzle_id: String)
## The heading was tapped: the gallery is now `open` or folded away.
signal open_changed(open: bool)

const GameTheme := preload("res://scenes/game/game_theme.gd")
const UI := preload("res://scenes/game/ui_widgets.gd")
## Whether the gallery shows, or is folded away under its heading.
var open: bool:
	get:
		return _heading.open
	set(value):
		_heading.open = value
		_body.visible = value
var _heading: SectionHeading
## Everything under the heading.
var _body: VBoxContainer
var _empty: Label
var _grid: GridContainer
var _tiles := {}


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading = SectionHeading.new("Completed puzzles")
	_heading.open_changed.connect(func(shown: bool) -> void:
		_body.visible = shown
		open_changed.emit(shown))
	add_child(_heading)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	add_child(_body)
	_body.add_child(UI.label("Tap a picture to admire it, restart it, or give it new colors.", 28, GameTheme.TEXT_DIM))
	_empty = UI.label("Your finished pictures will appear here.", 28, GameTheme.TEXT_DIM)
	_body.add_child(_empty)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 20)
	_grid.add_theme_constant_override("v_separation", 20)
	_body.add_child(_grid)


func set_puzzles(puzzles: Array) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_tiles.clear()
	for meta: Dictionary in puzzles:
		if not meta.get("done", false):
			continue
		var tile := _tile(meta)
		_grid.add_child(tile)
		_tiles[meta["id"]] = tile
	_heading.title = "Completed puzzles · %d" % _tiles.size()
	_empty.visible = _tiles.is_empty()
	_grid.visible = not _tiles.is_empty()


static func color_name(meta: Dictionary) -> String:
	return str(meta.get("theme_name", "From your photo" if GemCatalog.PHOTO_MODES.has(meta["type"])
		else GemCatalog.theme_name(meta.get("theme", ""))))


func _tile(meta: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size.x = 160
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.theme_type_variation = "ChoiceButton"
	button.tooltip_text = "%s · %s" % [GemCatalog.puzzle_title(meta), color_name(meta)]
	button.set_meta("puzzle_id", meta["id"])
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 12)
	button.add_child(inset)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 8)
	inset.add_child(copy)
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = SaveStore.load_thumbnail(meta["id"])
	if art.texture == null:
		art.texture = GameTheme.icon("picture")
	copy.add_child(art)
	var title := UI.label(GemCatalog.puzzle_title(meta), 24, GameTheme.GOLD, true)
	title.max_lines_visible = 2
	title.custom_minimum_size.y = 68
	copy.add_child(title)
	var colors := UI.label(color_name(meta), 22, GameTheme.TEXT_DIM, true)
	colors.max_lines_visible = 2
	colors.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	colors.custom_minimum_size.y = 62
	copy.add_child(colors)
	button.resized.connect(func() -> void: art.custom_minimum_size.y = maxf(128, button.size.x - 24))
	inset.minimum_size_changed.connect(func() -> void:
		button.custom_minimum_size.y = inset.get_combined_minimum_size().y)
	for child: Control in button.find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.pressed.connect(func() -> void: chosen.emit(meta["id"]))
	return button

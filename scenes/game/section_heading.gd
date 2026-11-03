class_name SectionHeading
extends Button
## A section's title that folds the section away, or opens it again, when
## tapped; its chevron points down while open and to the side while folded.
## The section itself shows or hides its content on `open_changed`.

signal open_changed(open: bool)

const GameTheme := preload("res://scenes/game/game_theme.gd")
const UI := preload("res://scenes/game/ui_widgets.gd")

var open := true:
	set(value):
		open = value
		if _chevron != null:
			_chevron.rotation = 0.0 if open else -PI / 2.0
		if _label != null:
			tooltip_text = ("Hide " if open else "Show ") + _label.text
var title: String:
	get:
		return _label.text
	set(value):
		_label.text = value
		open = open

var _label: Label
var _chevron: TextureRect


func _init(text_ := "", px := 48) -> void:
	flat = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = maxf(GameTheme.TAP_HEIGHT, px * 1.6)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_label = UI.label(text_, px, GameTheme.GOLD)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)
	_chevron = UI.icon("chevron_down", 44)
	_chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chevron.resized.connect(func() -> void: _chevron.pivot_offset = _chevron.size / 2.0)
	row.add_child(_chevron)
	open = true
	pressed.connect(func() -> void:
		open = not open
		open_changed.emit(open))

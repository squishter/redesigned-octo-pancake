extends Button
## The player's hint button uses the same jewel artwork as the toolbar.
## A quiet meter along its lower edge shows progress toward the next hint.

const GameTheme := preload("res://scenes/game/game_theme.gd")
var progress := 0.0:
	set(value):
		value = clampf(value, 0, 1)
		if absf(value - progress) >= 0.002 or (value == 0.0) != (progress == 0.0):
			progress = value
			if _meter != null:
				_meter.queue_redraw()

var _meter: Control


func _ready() -> void:
	icon = GameTheme.icon("hint")
	add_theme_font_size_override("font_size", 32)
	_meter = Control.new()
	_meter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter.draw.connect(func() -> void:
		var length := maxf(0, size.x - 56)
		_meter.draw_line(Vector2(28, size.y - 15), Vector2(size.x - 28, size.y - 15), GameTheme.BG, 5, true)
		if progress > 0:
			_meter.draw_line(Vector2(28, size.y - 15), Vector2(28 + length * progress, size.y - 15),
				GameTheme.MINT, 5, true))
	add_child(_meter)
	resized.connect(_meter.queue_redraw)

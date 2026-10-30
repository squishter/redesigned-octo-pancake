extends Button
## The play screen's Hint button: an ordinary button whose background fills
## from the left, a shade lighter, as the next hint comes closer. The fill
## stays low in contrast so it reads as a quiet clock, not a call to act.
## The background and fill are drawn by a child behind the button, so the
## label stays on top.

const LabTheme := preload("res://scenes/dev/lab_theme.gd")
## The fill: a little lighter than the button, well short of hover.
const FILL := Color("#433463")

## 0..1: how much of the background is filled.
var progress := 0.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if absf(value - progress) >= 0.002 or (value == 0.0) != (progress == 0.0):
			progress = value
			if _back != null:
				_back.queue_redraw()

var _back: Control


func _ready() -> void:
	_back = Control.new()
	_back.show_behind_parent = true
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_back.draw.connect(_draw_back)
	add_child(_back)
	var clear := StyleBoxEmpty.new()
	var box := LabTheme._box(LabTheme.FIELD)
	clear.content_margin_left = box.content_margin_left
	clear.content_margin_right = box.content_margin_right
	clear.content_margin_top = box.content_margin_top
	clear.content_margin_bottom = box.content_margin_bottom
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, clear)
	for sig in [mouse_entered, mouse_exited, button_down, button_up]:
		sig.connect(_back.queue_redraw)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW and _back != null:
		_back.queue_redraw()


func _draw_back() -> void:
	var base := LabTheme.FIELD
	match get_draw_mode():
		DRAW_PRESSED, DRAW_HOVER_PRESSED:
			base = LabTheme.FIELD_PRESSED
		DRAW_HOVER:
			base = LabTheme.FIELD_HOVER
		DRAW_DISABLED:
			base = LabTheme.FIELD.darkened(0.3)
	var rect := Rect2(Vector2.ZERO, size)
	_back.draw_style_box(LabTheme._box(base), rect)
	if progress > 0.0:
		var fill := LabTheme._box(FILL)
		# Keep the rounded corners whole while the fill is narrower than them.
		var w := maxf(size.x * progress, fill.corner_radius_top_left * 2.0)
		fill.bg_color = FILL if base == LabTheme.FIELD else base.lightened(0.05)
		_back.draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(w, size.y)))

extends Control
## Quiet geometric ornament behind the player menus, drawn at any resolution.

const GameTheme := preload("res://scenes/game/game_theme.gd")
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), GameTheme.BG)
	var center := Vector2(size.x * 0.5, size.y * 0.21)
	for i in range(18, 0, -1):
		var radius := size.x * (0.2 + i * 0.048)
		draw_circle(center, radius, Color(0.16, 0.22, 0.31, 0.018))
	for i in 32:
		var point := Vector2(fmod(i * 317.0 + 57.0, maxf(1.0, size.x)),
			fmod(i * 431.0 + 120.0, maxf(1.0, size.y)))
		point.y += sin(_time * 0.35 + i) * 8.0
		var radius := 3.0 + float(i % 3) * 2.0
		var color := Color(GameTheme.GOLD, 0.08 + 0.06 * sin(_time * 0.7 + i))
		draw_line(point - Vector2(radius, 0), point + Vector2(radius, 0), color, 1.5, true)
		draw_line(point - Vector2(0, radius), point + Vector2(0, radius), color, 1.5, true)
	for side in [-1.0, 1.0]:
		var corner := Vector2(size.x * (0.5 + side * 0.47), size.y * 0.09)
		var points := PackedVector2Array([corner + Vector2(0, -65), corner + Vector2(38, 0),
			corner + Vector2(0, 65), corner + Vector2(-38, 0), corner + Vector2(0, -65)])
		draw_polyline(points, Color(GameTheme.GOLD, 0.12), 2.0, true)

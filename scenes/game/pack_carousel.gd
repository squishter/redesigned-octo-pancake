class_name PackCarousel
extends Control
## Packs hang from an elliptical display. Rotation drives damped pendulums;
## horizontal swipes have momentum and settle on a pack, wrapping forever.

signal selected(pack: String)

const GameTheme := preload("res://scenes/game/game_theme.gd")
const DRAG_SLOP := 16.0
var _packs: Array = Packs.PACKS.keys()
var _step: float = TAU / _packs.size()
var _hangers: Array[Control] = []
var _swing: Array[float] = []
var _swing_speed: Array[float] = []
var _angle := 0.0
var _target := 0.0
var _velocity := 0.0
var _previous_velocity := 0.0
var _dragging := false
var _press_at := Vector2.ZERO
var _last_at := Vector2.ZERO
var _last_time := 0.0
var _travel := 0.0
var _selected_index := 0
var _touch := -1


func _ready() -> void:
	custom_minimum_size = Vector2(0, 710)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	clip_contents = true
	for pack: String in _packs:
		var hanger := Control.new()
		hanger.size = Vector2(300, 510)
		hanger.pivot_offset = Vector2(150, 0)
		hanger.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hanger)
		var string_art := Control.new()
		string_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hanger.add_child(string_art)
		string_art.draw.connect(func() -> void:
			string_art.draw_line(Vector2(150, 0), Vector2(150, 54), Color("#c8b58a"), 3, true)
			string_art.draw_arc(Vector2(150, 55), 9, 0, TAU, 24, GameTheme.GOLD, 3, true))
		var foil := PackVisual.new()
		foil.pack = pack
		foil.position = Vector2(0, 66)
		foil.scale = Vector2.ONE * (300.0 / 360.0)
		hanger.add_child(foil)
		_hangers.append(hanger)
		_swing.append(0.0)
		_swing_speed.append(0.0)
	_layout()


func current_pack() -> String:
	return _packs[_selected_index]


func rotate_by(direction: int) -> void:
	_target = (roundf(_target / _step) + direction) * _step
	for i in _swing_speed.size():
		_swing_speed[i] += direction * 0.65


func _process(delta: float) -> void:
	# Small substeps keep the springs stable even after a slow mobile frame.
	var steps := maxi(1, ceili(minf(delta, 0.1) / (1.0 / 120.0)))
	var dt := minf(delta, 0.1) / steps
	for _step in steps:
		if not _dragging:
			_velocity += ((_target - _angle) * 48.0 - _velocity * 12.0) * dt
			_angle += _velocity * dt
		var acceleration := clampf((_velocity - _previous_velocity) / maxf(dt, 0.001), -35.0, 35.0)
		_previous_velocity = _velocity
		for i in _hangers.size():
			var relative := i * _step - _angle
			var force := -acceleration * cos(relative) * 0.24
			_swing_speed[i] += (-27.0 * _swing[i] - 4.8 * _swing_speed[i] + force) * dt
			_swing[i] = clampf(_swing[i] + _swing_speed[i] * dt, -0.42, 0.42)
	var index := posmod(roundi(_angle / _step), _packs.size())
	if index != _selected_index:
		_selected_index = index
		selected.emit(current_pack())
	_layout()
	queue_redraw()


func _layout() -> void:
	var radius := size.x * 0.405
	var art_scale := minf(1.0, size.y / 710.0)
	for i in _hangers.size():
		var relative := i * _step - _angle
		var depth := (cos(relative) + 1.0) / 2.0
		var s := (0.48 + 0.52 * depth) * art_scale
		var hanger := _hangers[i]
		hanger.position = Vector2(size.x * 0.5 + sin(relative) * radius - 150,
			size.y * 0.13 + depth * size.y * 0.12)
		hanger.scale = Vector2(s * (0.72 + 0.28 * absf(cos(relative))), s)
		hanger.rotation = _swing[i]
		hanger.modulate = Color(0.55 + depth * 0.45, 0.6 + depth * 0.4, 0.7 + depth * 0.3,
			0.24 + 0.76 * pow(depth, 2.5))
		hanger.z_index = roundi(depth * 100)


func _draw() -> void:
	var center := Vector2(size.x / 2.0, size.y * 0.19)
	var radius := Vector2(size.x * 0.405, size.y * 0.06)
	var ring := PackedVector2Array()
	for i in 97:
		var a := i * TAU / 96.0
		ring.append(center + Vector2(sin(a) * radius.x, cos(a) * radius.y))
	draw_polyline(ring, Color(GameTheme.GOLD, 0.35), 4, true)
	draw_line(Vector2(center.x, 0), Vector2(center.x, center.y - radius.y), Color(GameTheme.GOLD, 0.24), 3, true)
	for i in _packs.size():
		var relative := i * _step - _angle
		var point := center + Vector2(sin(relative) * radius.x, cos(relative) * radius.y)
		draw_circle(point, 6, Color(GameTheme.GOLD, 0.7))
	# A pool of warm light beneath the front pack.
	for i in range(8, 0, -1):
		_draw_oval(Vector2(size.x * 0.5, size.y * 0.96), Vector2(130 + i * 11, 8 + i * 2),
			Color(GameTheme.GOLD, 0.015))


func _draw_oval(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 48:
		var a := i * TAU / 48.0
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(points, color)


func _gui_input(event: InputEvent) -> void:
	# Ignore synthetic duplicates from the project's mouse-to-touch emulation.
	if event.device == -1:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch < 0:
			_touch = event.index
			_begin_drag(event.position)
		elif not event.pressed and event.index == _touch:
			_touch = -1
			_end_drag(event.position)
		accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _touch:
			_drag(event.position)
		accept_event()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_drag(event.position)
			else:
				_end_drag(event.position)
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			rotate_by(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag(event.position)
		accept_event()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		rotate_by(1 if event.is_action_pressed("ui_right") else -1)
		accept_event()


func _begin_drag(at: Vector2) -> void:
	grab_focus()
	_dragging = true
	_press_at = at
	_last_at = at
	_last_time = Time.get_ticks_msec() / 1000.0
	_travel = 0.0
	_target = _angle
	_velocity = 0.0


func _drag(at: Vector2) -> void:
	if not _dragging:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var dx := at.x - _last_at.x
	_travel += absf(dx)
	var radians := -dx / maxf(160, size.x * 0.405)
	var dt := maxf(1.0 / 120.0, now - _last_time)
	_velocity = lerpf(_velocity, clampf(radians / dt, -9.0, 9.0), 0.6)
	_angle += radians
	_target = _angle
	_last_at = at
	_last_time = now


func _end_drag(at: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	if _travel < DRAG_SLOP and at.distance_to(_press_at) < DRAG_SLOP:
		_tap(at)
	else:
		if Time.get_ticks_msec() / 1000.0 - _last_time > 0.12:
			_velocity = 0.0
		_target = roundf((_angle + _velocity * 0.14) / _step) * _step


func _tap(at: Vector2) -> void:
	var order := range(_hangers.size())
	order.sort_custom(func(a: int, b: int) -> bool: return _hangers[a].z_index > _hangers[b].z_index)
	for i: int in order:
		var local := _hangers[i].get_transform().affine_inverse() * at
		if Rect2(0, 66, 300, 450).has_point(local):
			_target = _angle + wrapf(i * _step - _angle, -PI, PI)
			return
	_target = roundf(_angle / _step) * _step


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _dragging:
		_dragging = false
		_touch = -1
		_target = roundf(_angle / _step) * _step

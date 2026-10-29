extends Control
## Draws a generated picture: a collage (setting lines + slots), a kit
## pattern (colored cells with legend symbols) or raw line art. It keeps the
## picture's line art beside it, so `line_art` flips between the two without
## regenerating anything (and keeps the zoom, to compare one spot).
##
## Pinch to zoom, drag to pan and double-tap to fit again (mouse wheel zooms
## on desktop). The picture is drawn once into a child node; zooming and
## panning only move and scale that node, so they stay smooth on phones.

const VELVET := Color("#2a1f3d")
const GOLD := Color("#d4af5a")
const CANVAS := Color("#f4eee6")
const MAX_ZOOM := 40.0
const DOUBLE_TAP_MS := 300
const DOUBLE_TAP_SLOP := 60.0

var collage: Dictionary = {}
var kit: Dictionary = {}
var view := "collage"  # collage | kit | lines: the main picture
## Draw the line art instead of the main picture.
var line_art := false:
	set(value):
		line_art = value
		_content.queue_redraw()
var _lines_tex: ImageTexture
var _art_tex: ImageTexture
## Collage slot outlines in picture pixels, built once per picture.
var _slot_polys: Array[PackedVector2Array] = []

var _content := Node2D.new()
var _zoom := 1.0
## Where the unzoomed view's top-left corner lands, in this control's pixels.
var _origin := Vector2.ZERO
## Fingers down on the canvas: index -> position in this control's pixels.
var _touches := {}
var _last_tap_ms := -DOUBLE_TAP_MS
var _last_tap_pos := Vector2.ZERO


func _ready() -> void:
	add_child(_content)
	_content.draw.connect(_draw_content)
	resized.connect(func() -> void:
		_apply_view()
		_content.queue_redraw())


## Back to the whole picture.
func reset_view() -> void:
	_zoom = 1.0
	_origin = Vector2.ZERO
	_apply_view()


func show_collage(picture: Dictionary) -> void:
	collage = picture
	kit = {}
	view = "collage"
	_lines_tex = _mask_texture(picture.get("lines_visible", picture["lines"]), picture["width"], picture["height"])
	_slot_polys.clear()
	for slot in picture["slots"]:
		_slot_polys.append(GemShapes.slot_polygon(slot, 16))
	_content.queue_redraw()


func show_kit(pattern: Dictionary) -> void:
	kit = pattern
	collage = {}
	view = "kit"
	_content.queue_redraw()


## Shows line art as the main picture.
func show_lines(mask: PackedByteArray, w: int, h: int) -> void:
	collage = {}
	kit = {}
	view = "lines"
	set_line_art(mask, w, h)


## The line art behind the main picture, drawn while `line_art` is on.
func set_line_art(mask: PackedByteArray, w: int, h: int) -> void:
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	var inverted := PackedByteArray()
	inverted.resize(mask.size())
	for i in mask.size():
		inverted[i] = 255 - mask[i]
	img.set_data(w, h, false, Image.FORMAT_L8, inverted)
	_art_tex = ImageTexture.create_from_image(img)
	_content.queue_redraw()


## White texture whose alpha is the mask, so it can be tinted when drawn.
static func _mask_texture(mask: PackedByteArray, w: int, h: int) -> ImageTexture:
	var data := PackedByteArray()
	data.resize(w * h * 2)
	for i in w * h:
		data[i * 2] = 255
		data[i * 2 + 1] = mask[i]
	return ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_LA8, data))


func _fit(w: float, h: float) -> Rect2:
	var s := minf(size.x / w, size.y / h)
	var fitted := Vector2(w, h) * s
	return Rect2((size - fitted) / 2.0, fitted)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var p := _local(event.position)
		if event.pressed:
			if not Rect2(Vector2.ZERO, size).has_point(p):
				return
			_touches[event.index] = p
			if _touches.size() == 1:
				var now := Time.get_ticks_msec()
				if now - _last_tap_ms < DOUBLE_TAP_MS and p.distance_to(_last_tap_pos) < DOUBLE_TAP_SLOP:
					reset_view()
					now = -DOUBLE_TAP_MS
				_last_tap_ms = now
				_last_tap_pos = p
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var p := _local(event.position)
		var prev: Vector2 = _touches[event.index]
		if _touches.size() == 1:
			_origin += p - prev
			_apply_view()
		else:
			# Pinch with the first other finger: follow the midpoint, scale by the spread.
			var other: Vector2 = _touches[_touches.keys().filter(func(k: int) -> bool: return k != event.index)[0]]
			var old_mid := (prev + other) / 2.0
			var mid := (p + other) / 2.0
			_origin += mid - old_mid
			var old_spread := prev.distance_to(other)
			if old_spread > 1.0:
				_zoom_at(mid, p.distance_to(other) / old_spread)
			else:
				_apply_view()
		_touches[event.index] = p
	elif event is InputEventMouseButton and event.pressed:
		var p := _local(event.position)
		if not Rect2(Vector2.ZERO, size).has_point(p):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(p, 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(p, 1.0 / 1.15)
	elif event is InputEventMagnifyGesture and _touches.is_empty():
		# Trackpads; on touch screens the fingers above already did the work.
		var p := _local(event.position)
		if Rect2(Vector2.ZERO, size).has_point(p):
			_zoom_at(p, event.factor)


func _local(viewport_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_pos


func _zoom_at(p: Vector2, factor: float) -> void:
	var z := clampf(_zoom * factor, 1.0, MAX_ZOOM)
	_origin = p - (p - _origin) * (z / _zoom)
	_zoom = z
	_apply_view()


## Moves and scales the drawn picture, keeping it covering the canvas so it
## can't be lost off-screen.
func _apply_view() -> void:
	_origin = _origin.clamp(size * (1.0 - _zoom), Vector2.ZERO)
	_content.position = _origin
	_content.scale = Vector2(_zoom, _zoom)


func _draw_content() -> void:
	match "lines" if line_art else view:
		"collage":
			if not collage.is_empty():
				_draw_collage()
		"kit":
			if not kit.is_empty():
				_draw_kit()
		"lines":
			if _art_tex:
				_content.draw_texture_rect(_art_tex, _fit(_art_tex.get_width(), _art_tex.get_height()), false)


func _draw_collage() -> void:
	var w: float = collage["width"]
	var h: float = collage["height"]
	var rect := _fit(w, h)
	var s := rect.size.x / w
	_content.draw_rect(rect, VELVET)
	_content.draw_set_transform(rect.position, 0.0, Vector2(s, s))
	var slots: Array = collage["slots"]
	for i in slots.size():
		var poly := _slot_polys[i]
		var c: Color = slots[i]["target_color"]
		_content.draw_colored_polygon(poly, c)
		var ring := poly.duplicate()
		ring.append(poly[0])
		_content.draw_polyline(ring, c.lightened(0.45), -1.0)
	_content.draw_texture_rect(_lines_tex, Rect2(0.0, 0.0, w, h), false, GOLD)
	_content.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_kit() -> void:
	var w: int = kit["width"]
	var h: int = kit["height"]
	var rect := _fit(w, h)
	var cell := rect.size.x / w
	_content.draw_rect(rect, CANVAS)
	var cells: PackedByteArray = kit["cells"]
	var palette: Array = kit["palette"]
	var font := ThemeDB.fallback_font
	var font_size := int(cell * 0.6)
	var round_drill: bool = kit["drill"] == "round"
	for y in h:
		for x in w:
			var entry: Dictionary = palette[cells[y * w + x]]
			var c: Color = entry["color"]
			var pos := rect.position + Vector2(x, y) * cell
			if round_drill:
				_content.draw_circle(pos + Vector2(cell, cell) / 2.0, cell * 0.46, c)
			else:
				_content.draw_rect(Rect2(pos, Vector2(cell, cell)), c)
			if font_size >= 7:
				var ink: Color = Color.BLACK if c.get_luminance() > 0.5 else Color.WHITE
				_content.draw_string(font, pos + Vector2(0, cell * 0.72), entry["symbol"],
						HORIZONTAL_ALIGNMENT_CENTER, cell, font_size, Color(ink, 0.55))

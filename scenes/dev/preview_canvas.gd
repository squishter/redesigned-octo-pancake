extends Control
## Draws a generated picture: a collage (setting lines + slots), a kit
## pattern (colored cells with legend symbols) or raw line art.

const VELVET := Color("#2a1f3d")
const GOLD := Color("#d4af5a")
const CANVAS := Color("#f4eee6")

var collage: Dictionary = {}
var kit: Dictionary = {}
var view := "collage"  # collage | kit | lines
var _lines_tex: ImageTexture
var _art_tex: ImageTexture


func show_collage(picture: Dictionary) -> void:
	collage = picture
	kit = {}
	view = "collage"
	_lines_tex = _mask_texture(picture["lines"], picture["width"], picture["height"])
	queue_redraw()


func show_kit(pattern: Dictionary) -> void:
	kit = pattern
	collage = {}
	view = "kit"
	queue_redraw()


func show_lines(mask: PackedByteArray, w: int, h: int) -> void:
	collage = {}
	kit = {}
	view = "lines"
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	var inverted := PackedByteArray()
	inverted.resize(mask.size())
	for i in mask.size():
		inverted[i] = 255 - mask[i]
	img.set_data(w, h, false, Image.FORMAT_L8, inverted)
	_art_tex = ImageTexture.create_from_image(img)
	queue_redraw()


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


func _draw() -> void:
	match view:
		"collage":
			if not collage.is_empty():
				_draw_collage()
		"kit":
			if not kit.is_empty():
				_draw_kit()
		"lines":
			if _art_tex:
				draw_texture_rect(_art_tex, _fit(_art_tex.get_width(), _art_tex.get_height()), false)


func _draw_collage() -> void:
	var w: float = collage["width"]
	var h: float = collage["height"]
	var rect := _fit(w, h)
	var s := rect.size.x / w
	draw_rect(rect, VELVET)
	var xf := Transform2D(0.0, Vector2(s, s), 0.0, rect.position)
	for slot in collage["slots"]:
		var poly := xf * GemShapes.slot_polygon(slot, 16)
		var c: Color = slot["target_color"]
		draw_colored_polygon(poly, c)
		poly.append(poly[0])
		draw_polyline(poly, c.lightened(0.45), 1.0, true)
	draw_texture_rect(_lines_tex, rect, false, GOLD)


func _draw_kit() -> void:
	var w: int = kit["width"]
	var h: int = kit["height"]
	var rect := _fit(w, h)
	var cell := rect.size.x / w
	draw_rect(rect, CANVAS)
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
				draw_circle(pos + Vector2(cell, cell) / 2.0, cell * 0.46, c)
			else:
				draw_rect(Rect2(pos, Vector2(cell, cell)), c)
			if font_size >= 7:
				var ink: Color = Color.BLACK if c.get_luminance() > 0.5 else Color.WHITE
				draw_string(font, pos + Vector2(0, cell * 0.72), entry["symbol"],
						HORIZONTAL_ALIGNMENT_CENTER, cell, font_size, Color(ink, 0.55))

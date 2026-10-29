extends RefCounted
## A touch-friendly theme for the dev screens: big text, finger-sized buttons,
## lists and sliders, in the game's velvet and gold. The project's viewport is
## 1080 px wide, so sizes here are in those pixels (about 400 per inch on a phone).

const FONT_SIZE := 40
const SMALL_FONT_SIZE := 30
## Smallest height of anything tappable: about 9 mm on a phone.
const TAP_HEIGHT := 112

const BG := Color("#1d1530")
const PANEL := Color("#2a1f3d")
const FIELD := Color("#3a2c55")
const FIELD_HOVER := Color("#4a3a6a")
const FIELD_PRESSED := Color("#5b4880")
const GOLD := Color("#d4af5a")
const TEXT := Color("#f4eee6")
const TEXT_DIM := Color("#b9aecb")


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE

	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _box(FIELD))
		t.set_stylebox("hover", type, _box(FIELD_HOVER))
		t.set_stylebox("pressed", type, _box(FIELD_PRESSED))
		t.set_stylebox("hover_pressed", type, _box(FIELD_PRESSED))
		t.set_stylebox("disabled", type, _box(FIELD.darkened(0.3)))
		t.set_stylebox("focus", type, _box(Color.TRANSPARENT, GOLD))
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(state, type, TEXT)
		t.set_color("font_pressed_color", type, GOLD)
	t.set_constant("arrow_margin", "OptionButton", 24)
	t.set_icon("arrow", "OptionButton", _triangle(28, TEXT_DIM))

	t.set_stylebox("normal", "LineEdit", _box(FIELD))
	t.set_stylebox("focus", "LineEdit", _box(Color.TRANSPARENT, GOLD))
	t.set_stylebox("read_only", "LineEdit", _box(FIELD.darkened(0.3)))
	t.set_color("font_color", "LineEdit", TEXT)
	# Number fields get big - and + buttons beside them instead (see the lab).
	var none := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for icon in ["updown", "up", "up_hover", "up_pressed", "up_disabled", "down", "down_hover", "down_pressed",
			"down_disabled"]:
		t.set_icon(icon, "SpinBox", none)
	t.set_constant("buttons_width", "SpinBox", 0)
	t.set_constant("field_and_buttons_separation", "SpinBox", 0)

	var popup := _box(PANEL, GOLD)
	popup.set_content_margin_all(12)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(FIELD_PRESSED))
	t.set_constant("v_separation", "PopupMenu", 36)
	t.set_constant("item_start_padding", "PopupMenu", 24)
	t.set_constant("item_end_padding", "PopupMenu", 24)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	t.set_icon("radio_checked", "PopupMenu", _dot(28, GOLD))
	t.set_icon("radio_unchecked", "PopupMenu", _dot(28, Color.TRANSPARENT))

	var track := StyleBoxFlat.new()
	track.bg_color = FIELD
	track.set_corner_radius_all(8)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	t.set_stylebox("slider", "HSlider", track)
	var filled := track.duplicate()
	filled.bg_color = GOLD.darkened(0.25)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	t.set_icon("grabber", "HSlider", _dot(64, GOLD))
	t.set_icon("grabber_highlight", "HSlider", _dot(64, GOLD.lightened(0.3)))

	var bar := StyleBoxFlat.new()
	bar.bg_color = FIELD_HOVER
	bar.set_corner_radius_all(6)
	bar.content_margin_left = 10
	bar.content_margin_right = 10
	t.set_stylebox("grabber", "VScrollBar", bar)
	t.set_stylebox("grabber_highlight", "VScrollBar", bar)
	t.set_stylebox("grabber_pressed", "VScrollBar", bar)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())

	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(24)
	panel.set_content_margin_all(24)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("separation", "HBoxContainer", 16)
	t.set_constant("separation", "VBoxContainer", 16)
	t.set_constant("h_separation", "GridContainer", 20)
	t.set_constant("v_separation", "GridContainer", 16)
	t.set_constant("h_separation", "HFlowContainer", 16)
	t.set_constant("v_separation", "HFlowContainer", 16)
	return t


static func _box(color: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(18)
	b.content_margin_left = 28
	b.content_margin_right = 28
	b.content_margin_top = 20
	b.content_margin_bottom = 20
	if border.a > 0.0:
		b.border_color = border
		b.set_border_width_all(3)
	return b


static func _dot(px: int, color: Color) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := Vector2(px, px) / 2.0
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			img.set_pixel(x, y, Color(color, color.a * clampf(px / 2.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## A downward triangle, for list arrows.
static func _triangle(px: int, color: Color) -> ImageTexture:
	var h := px * 2 / 3
	var img := Image.create(px, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var half := px / 2.0 * (1.0 - float(y) / h)
		for x in px:
			var inside := clampf(half - absf(x + 0.5 - px / 2.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(color, inside))
	return ImageTexture.create_from_image(img)

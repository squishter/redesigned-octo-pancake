class_name ColorStorySwatches
extends RefCounted
## Shared, ordered palette previews for the selector and color-story editor.

const GameTheme := preload("res://scenes/game/game_theme.gd")
const UI := preload("res://scenes/game/ui_widgets.gd")


## Fixed-size tiles wrap onto another line instead of squeezing or clipping colors.
static func flow() -> HFlowContainer:
	var node := HFlowContainer.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_constant_override("h_separation", 12)
	node.add_theme_constant_override("v_separation", 12)
	return node


static func names(gems: Array) -> String:
	var titles := PackedStringArray()
	for gem: String in gems:
		titles.append(GemCatalog.color_name(gem))
	return ", ".join(titles)


## Thumbnails made so far, by size and colors: the story browser shows
## hundreds, and opens often.
static var _thumbnails := {}


## A thumbnail keeps every color visible in the field and the story browser.
static func thumbnail(gems: Array, px := 32) -> ImageTexture:
	var key := "%d|%s" % [px, ",".join(PackedStringArray(gems))]
	if not _thumbnails.has(key):
		_thumbnails[key] = _make_thumbnail(gems, px)
	return _thumbnails[key]


static func _make_thumbnail(gems: Array, px: int) -> ImageTexture:
	var image := Image.create(maxi(1, gems.size()) * px, px, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for i in gems.size():
		image.fill_rect(Rect2i(i * px, 0, px - 4, px), GameTheme.TEXT_DIM)
		image.fill_rect(Rect2i(i * px + 2, 2, px - 8, px - 4), GemCatalog.color_of(gems[i]))
	return ImageTexture.create_from_image(image)


## A named swatch, readable on light and dark gem colors alike.
## Buttons can be used for adding/removing colors; static previews ignore input.
static func tile(gem: String, interactive := false, compact := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(120, 100) if compact else Vector2(180, 152)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.theme_type_variation = "ChoiceButton"
	b.focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	b.tooltip_text = GemCatalog.color_name(gem)
	b.set_meta("gem", gem)
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 8 if compact else 12)
	b.add_child(inset)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 4 if compact else 8)
	inset.add_child(copy)
	var paint := PanelContainer.new()
	paint.custom_minimum_size.y = 30 if compact else 52
	var box := StyleBoxFlat.new()
	box.bg_color = GemCatalog.color_of(gem)
	box.border_color = GameTheme.TEXT_DIM
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	paint.add_theme_stylebox_override("panel", box)
	copy.add_child(paint)
	var number := UI.label("", 22 if compact else 25, Color.WHITE, true)
	number.name = "Order"
	number.add_theme_color_override("font_color",
		Color("#14182b") if box.bg_color.get_luminance() > 0.45 else Color.WHITE)
	paint.add_child(number)
	var title := UI.label(GemCatalog.color_name(gem), 20 if compact else 23, GameTheme.TEXT, true)
	title.custom_minimum_size.x = 104 if compact else 156
	copy.add_child(title)
	# The button owns pointer input; its decorative children must not intercept taps.
	for child: Control in b.find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## Empty slots reserve the same space as selected tiles, keeping the catalog still.
static func empty_slot(number: int) -> PanelContainer:
	var slot := UI.panel(false, 8)
	slot.custom_minimum_size = Vector2(120, 100)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := UI.label(str(number), 22, GameTheme.TEXT_DIM, true)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)
	return slot

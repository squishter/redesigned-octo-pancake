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


## A thumbnail keeps every color visible in both the field and its popup menu.
static func thumbnail(gems: Array, px := 32) -> ImageTexture:
	var image := Image.create(maxi(1, gems.size()) * px, px, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for i in gems.size():
		image.fill_rect(Rect2i(i * px, 0, px - 4, px), GameTheme.TEXT_DIM)
		image.fill_rect(Rect2i(i * px + 2, 2, px - 8, px - 4), GemCatalog.color_of(gems[i]))
	return ImageTexture.create_from_image(image)


## A named swatch, readable on light and dark gem colors alike.
## Buttons can be used for adding/removing colors; static previews ignore input.
static func tile(gem: String, interactive := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(180, 152)
	b.theme_type_variation = "ChoiceButton"
	b.focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	b.tooltip_text = GemCatalog.color_name(gem)
	b.set_meta("gem", gem)
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 12)
	b.add_child(inset)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 8)
	inset.add_child(copy)
	var paint := PanelContainer.new()
	paint.custom_minimum_size.y = 52
	var box := StyleBoxFlat.new()
	box.bg_color = GemCatalog.color_of(gem)
	box.border_color = GameTheme.TEXT_DIM
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	paint.add_theme_stylebox_override("panel", box)
	copy.add_child(paint)
	var number := UI.label("", 25, Color.WHITE, true)
	number.name = "Order"
	number.add_theme_color_override("font_color",
		Color("#14182b") if box.bg_color.get_luminance() > 0.45 else Color.WHITE)
	paint.add_child(number)
	var title := UI.label(GemCatalog.color_name(gem), 23, GameTheme.TEXT, true)
	title.custom_minimum_size.x = 156
	copy.add_child(title)
	# The button owns pointer input; its decorative children must not intercept taps.
	for child: Control in b.find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

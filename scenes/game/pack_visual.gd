class_name PackVisual
extends Control
## A foil booster with a separately movable, crimped tear strip.

const GameTheme := preload("res://scenes/game/game_theme.gd")
var pack := "colors"
var cap: TextureRect
var _slit := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art: Texture2D = load("res://assets/ui/pack_%s.svg" % pack)
	var body := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = art
	atlas.region = Rect2(0, 58, 360, 482)
	body.texture = atlas
	body.position = Vector2(0, 58)
	body.size = Vector2(360, 482)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.show_behind_parent = true
	add_child(body)
	cap = TextureRect.new()
	var top := AtlasTexture.new()
	top.atlas = art
	top.region = Rect2(0, 0, 360, 58)
	cap.texture = top
	cap.size = Vector2(360, 58)
	cap.pivot_offset = Vector2(330, 30)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cap)
	var brand := _label("PAINT WITH GEMS", Rect2(28, 93, 304, 40), 24)
	brand.add_theme_color_override("font_color", GameTheme.GOLD)
	var emblem := TextureRect.new()
	emblem.texture = GameTheme.icon(GameTheme.pack_glyph(pack))
	emblem.position = Vector2(113, 187)
	emblem.size = Vector2(134, 134)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(emblem)
	var title: String = Packs.PACKS.get(pack, {}).get("name", "Gem pack")
	_label(title.trim_suffix(" pack").to_upper(), Rect2(26, 393, 308, 42), 30)
	var contents := "A DISCOVERY + BONUS CHANCE"
	if pack == "powers":
		contents = "%d POWER-UPS + BONUS CHANCE" % Packs.reward_count(pack)
	elif pack == "all":
		contents = "%d UNLOCKABLES + BONUS CHANCE" % Packs.reward_count(pack)
	_label(contents, Rect2(25, 441, 310, 25), 16)


func unseal() -> void:
	_slit = true
	queue_redraw()


func _draw() -> void:
	if _slit:
		draw_colored_polygon(PackedVector2Array([Vector2(9, 59), Vector2(351, 59),
			Vector2(338, 81), Vector2(22, 76)]), Color("#080f1e"))
		draw_line(Vector2(14, 61), Vector2(347, 61), GameTheme.GOLD, 3, true)


func _label(text: String, rect: Rect2, px: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", px)
	label.add_theme_color_override("font_color", GameTheme.TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

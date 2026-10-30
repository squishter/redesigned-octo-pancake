extends Control
## Collection & packs: what she has unlocked, and packs to open for more.
##
## Packs: every pack (see Packs) with what it gives, how much is left in it,
## and buttons to open it with a free pick or coins; opening one shows what
## came out. Collection: every gem color and every shape in every cut as
## real rendered gems (cut from one off-screen GemBoard3D, like the play
## screen's gem row), then themes, picture types, flourishes, animations,
## finales and power-up charges. Locked things stay a mystery: gems show
## only as flat silhouettes, and names, theme colors and descriptions are
## hidden until found.

signal back_requested

const LabTheme := preload("res://scenes/dev/lab_theme.gd")
const ICON_PX := 128
const ICON_CELL := 100.0
const ICON_COLUMNS := 10
const CELL_SIZE := Vector2(150, 196)
## Shapes in Collection are shown in these colors, one per shape in turn.
const SHAPE_COLORS := ["sapphire", "ruby", "sunflower", "leaf", "amethyst", "tangerine", "diamond", "indigo"]
## Locked gems are drawn in this flat color: their outline, nothing more.
const SILHOUETTE := Color(0.0, 0.0, 0.0, 0.9)


## A gem's outline filled flat, as its icon would show it (stone as made
## by _stone, in icon-cell units scaled by `px_per_unit`).
class Silhouette:
	extends Control
	var _poly: PackedVector2Array

	func _init(stone: Dictionary, px_per_unit: float) -> void:
		custom_minimum_size = Vector2.ONE * ICON_CELL * px_per_unit
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var local := GemShapes.outline(stone["shape"], stone["size"], stone["width"], 32)
		var xf := Transform2D(stone["rotation"], custom_minimum_size / 2.0).scaled_local(
				Vector2.ONE * px_per_unit)
		_poly = xf * local

	func _draw() -> void:
		draw_colored_polygon(_poly, SILHOUETTE)
const HIDDEN_SWATCH := Color("#3a2c55")

## The player's profile (SaveStore), shared with the app; set before adding.
var profile: Dictionary = {}

var _wallet: Label
var _packs_view: Control
var _collection_view: Control
var _packs_list: VBoxContainer
var _collection_list: VBoxContainer
var _tab_packs: Button
var _tab_collection: Button
var _sheet: GemBoard3D
## Icon of each color id and of each "shape|cut", cut from the sheet.
var _icons := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()
	_build_sheet()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	add_child(root)
	SafeArea.apply(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	_button(top, "‹ Menu", func() -> void: back_requested.emit())
	_wallet = Label.new()
	_wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wallet.add_theme_color_override("font_color", LabTheme.GOLD)
	top.add_child(_wallet)

	var tabs := HBoxContainer.new()
	root.add_child(tabs)
	var group := ButtonGroup.new()
	_tab_packs = _button(tabs, "Packs", func() -> void: _show_tab(true))
	_tab_collection = _button(tabs, "Collection", func() -> void: _show_tab(false))
	for b in [_tab_packs, _tab_collection]:
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_packs_view = _scroll(root)
	_packs_list = _packs_view.get_child(0)
	_collection_view = _scroll(root)
	_collection_list = _collection_view.get_child(0)
	_refresh()
	_show_tab(true)


## Android's back button.
func go_back() -> void:
	back_requested.emit()


func _show_tab(packs: bool) -> void:
	_packs_view.visible = packs
	_collection_view.visible = not packs
	_tab_packs.set_pressed_no_signal(packs)
	_tab_collection.set_pressed_no_signal(not packs)


func _refresh() -> void:
	_wallet.text = "%d coins · %d free pick%s" % [Packs.coins(profile), Packs.picks(profile),
			"" if Packs.picks(profile) == 1 else "s"]
	_fill_packs()
	_fill_collection()


# --- packs -------------------------------------------------------------------

func _fill_packs() -> void:
	_clear(_packs_list)
	_note(_packs_list, ("Free picks: one for opening the game each day, and one for your first finished puzzle "
			+ "each day. Each finished puzzle also pays %d coins, so every 3 puzzles buy a pack.") % Packs.COINS_PER_PUZZLE)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_packs_list.add_child(grid)
	for pack: String in Packs.PACKS:
		grid.add_child(_pack_card(pack))


func _pack_card(pack: String) -> Control:
	var info: Dictionary = Packs.PACKS[pack]
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	card.add_child(box)
	var title := Label.new()
	title.text = info["name"]
	title.add_theme_color_override("font_color", LabTheme.GOLD)
	box.add_child(title)
	var about := _note(box, info["about"])
	about.custom_minimum_size.y = 80
	var left := Packs.pool(pack, profile).size()
	var out := left == 0
	var stock := _note(box, "Sold out: you have it all!" if out else (
			"Always in stock" if pack in ["powers", "all"] else "%d left to find" % left))
	stock.add_theme_color_override("font_color", LabTheme.GOLD.darkened(0.2) if out else LabTheme.TEXT_DIM)
	var free := _button(box, "Use a free pick", func() -> void: _open(pack, true))
	free.disabled = out or Packs.picks(profile) <= 0
	var buy := _button(box, "%d coins" % Packs.price(pack), func() -> void: _open(pack, false))
	buy.disabled = out or Packs.coins(profile) < Packs.price(pack)
	for b: Button in [free, buy]:
		b.add_theme_font_size_override("font_size", LabTheme.SMALL_FONT_SIZE)
	if out:
		card.modulate = Color(1, 1, 1, 0.55)
	return card


func _open(pack: String, with_pick: bool) -> void:
	var before: Dictionary = (profile["unlocks"] as Dictionary).duplicate(true)
	var item := Packs.open(profile, pack, with_pick, _rng)
	if item.is_empty():
		return
	SaveStore.save_profile(profile)
	_refresh()
	# A new color may complete themes: say so on the same card.
	var themes := Unlockables.themes_gained(before, profile["unlocks"])
	if not themes.is_empty():
		item["themes"] = themes
	_reveal(item)


## Shows what came out of a pack: a card that pops up with a burst of sparkles.
func _reveal(item: Dictionary) -> void:
	var shade := ColorRect.new()
	shade.color = Color(LabTheme.BG, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(760, 0)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(box)
	var kind := Label.new()
	kind.text = _kind_name(item)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.add_theme_color_override("font_color", LabTheme.TEXT_DIM)
	box.add_child(kind)
	var picture := _item_picture(item, 300.0)
	if picture != null:
		var holder := CenterContainer.new()
		holder.add_child(picture)
		box.add_child(holder)
	var title := Label.new()
	title.text = item["name"] + (" ×%d" % item["charges"] if item["kind"] == "power" else "")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", LabTheme.GOLD)
	box.add_child(title)
	var about := _note(box, item.get("about", ""))
	about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for t: String in item.get("themes", []):
		var done := Label.new()
		done.text = "Completes the %s theme!" % GemCatalog.theme_name(t)
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done.add_theme_color_override("font_color", LabTheme.GOLD)
		box.add_child(done)
		var holder := CenterContainer.new()
		holder.add_child(_swatches(t, 44.0))
		box.add_child(holder)
	var ok := _button(box, "Lovely!", func() -> void: shade.queue_free())
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.custom_minimum_size.x = 360
	# Pop in, with sparkles behind.
	var sparkles := _sparkles()
	sparkles.position = size / 2.0
	shade.add_child(sparkles)
	shade.move_child(sparkles, 0)
	sparkles.emitting = true
	card.resized.connect(func() -> void: card.pivot_offset = card.size / 2.0)
	card.scale = Vector2(0.4, 0.4)
	card.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card, "modulate:a", 1.0, 0.25)
	Input.vibrate_handheld(40, 0.6)


func _kind_name(item: Dictionary) -> String:
	return Unlockables.KINDS.get(item["kind"], {}).get("found", "New!")


## A picture of an item: the rendered gem for colors, shapes and cuts, a
## swatch strip for themes; null for the rest.
func _item_picture(item: Dictionary, px: float) -> Control:
	var key := ""
	match item["kind"]:
		"color":
			key = item["id"]
		"shape", "cut":
			key = "%s|%s" % [item["shape"], item["cut"]]
		"theme":
			return _swatches(item["id"], px / 6.0)
	if not _icons.has(key):
		return null
	var icon := TextureRect.new()
	icon.texture = _icons[key]
	icon.custom_minimum_size = Vector2(px, px)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


func _sparkles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 60
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.9
	p.spread = 180.0
	p.gravity = Vector2(0, 120)
	p.initial_velocity_min = 300.0
	p.initial_velocity_max = 900.0
	p.damping_min = 200.0
	p.damping_max = 400.0
	p.scale_amount_min = 6.0
	p.scale_amount_max = 14.0
	var ramp := Gradient.new()
	ramp.set_color(0, LabTheme.GOLD.lightened(0.3))
	ramp.set_color(1, Color(LabTheme.GOLD, 0.0))
	p.color_ramp = ramp
	return p


# --- collection --------------------------------------------------------------

## Every gem color and shape-and-cut on one transparent board, kept off screen.
func _build_sheet() -> void:
	var stones := []
	var keys := []
	for g in GemCatalog.all_colors():
		keys.append(g["id"])
		stones.append(_stone("round", "brilliant", g["color"], g["id"]))
	var shape_index := {}
	for pair: Array in GemCatalog.all_cuts():
		var shape: String = pair[0]
		if not shape_index.has(shape):
			shape_index[shape] = shape_index.size()
		var gem: String = SHAPE_COLORS[shape_index[shape] % SHAPE_COLORS.size()]
		keys.append("%s|%s" % pair)
		stones.append(_stone(shape, pair[1], GemCatalog.color_of(gem), gem))
	var cols := ICON_COLUMNS
	var rows := ceili(float(stones.size()) / cols)
	for k in stones.size():
		stones[k]["x"] = (k % cols + 0.5) * ICON_CELL
		stones[k]["y"] = (k / cols + 0.5) * ICON_CELL
	_sheet = GemBoard3D.new()
	_sheet.margin = 0.0
	_sheet.input_enabled = false
	_sheet.shadows = false
	_sheet.set_transparent()
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.position = Vector2(-100000.0, 0.0)
	_sheet.size = Vector2(cols, rows) * ICON_PX
	add_child(_sheet)
	_sheet.set_always_render()
	_sheet.show_collage({"width": cols * ICON_CELL, "height": rows * ICON_CELL, "slots": stones})
	for k in stones.size():
		var icon := AtlasTexture.new()
		icon.atlas = _sheet.get_view_texture()
		icon.region = Rect2(Vector2(k % cols, k / cols) * ICON_PX, Vector2(ICON_PX, ICON_PX))
		_icons[keys[k]] = icon


static func _stone(shape: String, cut: String, color: Color, gem: String) -> Dictionary:
	return GemIcons.stone(shape, cut, color, gem, 0.5, ICON_CELL, Vector2.ZERO)


func _fill_collection() -> void:
	_clear(_collection_list)
	var unlocks: Dictionary = profile["unlocks"]

	var colors := GemCatalog.all_colors()
	var colors_owned := colors.filter(func(g: Dictionary) -> bool: return g["id"] in unlocks["colors"])
	_heading(_collection_list, "Gem colors", colors_owned.size(), colors.size())
	for hue: String in GemCatalog.HUE_ORDER:
		var of_hue := colors.filter(func(g: Dictionary) -> bool: return g["hue"] == hue)
		var have_hue := of_hue.filter(func(g: Dictionary) -> bool: return g["id"] in unlocks["colors"])
		_subheading(_collection_list, "%s  %d / %d" % [hue.capitalize(), have_hue.size(), of_hue.size()])
		var color_flow := _flow(_collection_list)
		for g: Dictionary in of_hue:
			var have: bool = g["id"] in unlocks["colors"]
			color_flow.add_child(_gem_cell(g["id"], g["name"] if have else "?", have))

	var pairs := GemCatalog.all_cuts()
	var owned := 0
	for pair: Array in pairs:
		if GemCatalog.has_cut(unlocks, pair[0], pair[1]):
			owned += 1
	_heading(_collection_list, "Shapes and cuts", owned, pairs.size())
	for shape: String in GemCatalog.ALL_SHAPES:
		var have_shape: bool = unlocks["shapes"].has(shape)
		_subheading(_collection_list, shape.capitalize() if have_shape else "???", have_shape)
		var flow := _flow(_collection_list)
		for cut: String in GemCuts.for_shape(shape):
			var have := GemCatalog.has_cut(unlocks, shape, cut)
			flow.add_child(_gem_cell("%s|%s" % [shape, cut], cut if have else "?", have))

	# Themes come with their colors: a locked one shows only the colors
	# she has found so far, and how many it needs.
	var themes: Array = GemCatalog.unlocked_themes(unlocks)
	_heading(_collection_list, "Color themes", themes.size(), GemCatalog.THEMES.size())
	_note(_collection_list, "A theme is yours once you have all its colors.")
	for t: String in GemCatalog.THEMES:
		var have := GemCatalog.has_theme(unlocks, t)
		var row := HBoxContainer.new()
		_collection_list.add_child(row)
		var name_label := Label.new()
		var gems: Array = GemCatalog.THEMES[t]["gems"]
		var found := gems.filter(func(g: String) -> bool: return g in unlocks["colors"]).size()
		name_label.text = GemCatalog.theme_name(t) if have else "?  (%d / %d colors)" % [found, gems.size()]
		name_label.custom_minimum_size.x = 400
		name_label.add_theme_color_override("font_color", LabTheme.TEXT if have else LabTheme.TEXT_DIM)
		row.add_child(name_label)
		row.add_child(_swatches(t, 48.0, not have, unlocks["colors"]))

	# Every other kind of unlockable, as a list (a new kind shows up here).
	for kind: String in Unlockables.KINDS:
		if not kind in ["color", "shape", "cut", "theme", "power"]:
			_kind_section(kind)

	# Power-ups she has never had stay a mystery too.
	_heading(_collection_list, "Power-ups", -1, -1)
	for p: String in GemCatalog.POWERS:
		var info: Dictionary = GemCatalog.POWERS[p]
		var n := Packs.charges(profile, p)
		if profile["powers"].has(p):
			_item_row(_collection_list, "%s  ×%d" % [info["name"], n], info["about"], n > 0)
		else:
			_item_row(_collection_list, "?", "Find it in a power-up pack.", false)


func _kind_section(kind: String) -> void:
	var unlocks: Dictionary = profile["unlocks"]
	var all := Unlockables.items(kind)
	var owned := all.filter(func(item: Dictionary) -> bool: return Unlockables.has(unlocks, item))
	_heading(_collection_list, Unlockables.KINDS[kind]["title"], owned.size(), all.size())
	for item: Dictionary in all:
		var have := Unlockables.has(unlocks, item)
		_item_row(_collection_list, item["name"] if have else "?", item["about"] if have else "Find it in a pack.", have)


## A gem in Collection: rendered when she has it, else only its outline.
func _gem_cell(key: String, caption: String, have: bool) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = CELL_SIZE
	box.add_theme_constant_override("separation", 0)
	if have:
		var icon := TextureRect.new()
		icon.texture = _icons.get(key)
		icon.custom_minimum_size = Vector2(CELL_SIZE.x, CELL_SIZE.x)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(icon)
	else:
		var shape := key.split("|")[0] if "|" in key else "round"
		box.add_child(Silhouette.new(_stone(shape, "", Color.BLACK, ""), CELL_SIZE.x / ICON_CELL))
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", LabTheme.SMALL_FONT_SIZE - 6)
	label.add_theme_color_override("font_color", LabTheme.TEXT if have else LabTheme.TEXT_DIM)
	box.add_child(label)
	return box


## A theme's colors as a strip of squares; when `hidden`, only the ones in
## `shown` (colors she has) show and the rest are blank.
func _swatches(theme_id: String, px: float, hidden := false, shown: Array = []) -> Control:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	var gems: Array = GemCatalog.THEMES.get(theme_id, {"gems": []})["gems"]
	for gem: String in gems:
		var swatch := ColorRect.new()
		swatch.color = HIDDEN_SWATCH if hidden and not gem in shown else GemCatalog.color_of(gem)
		swatch.custom_minimum_size = Vector2(px, px)
		strip.add_child(swatch)
	return strip


func _heading(parent: Control, text: String, have: int, total: int) -> void:
	var l := Label.new()
	l.text = text if total < 0 else "%s  %d / %d" % [text, have, total]
	l.add_theme_font_size_override("font_size", 48)
	l.add_theme_color_override("font_color", LabTheme.GOLD)
	parent.add_child(l)


func _subheading(parent: Control, text: String, bright := true) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", LabTheme.SMALL_FONT_SIZE)
	l.add_theme_color_override("font_color", LabTheme.TEXT if bright else LabTheme.TEXT_DIM)
	parent.add_child(l)


func _item_row(parent: Control, title: String, about: String, have: bool) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	parent.add_child(box)
	var t := Label.new()
	t.text = title
	t.add_theme_color_override("font_color", LabTheme.TEXT if have else LabTheme.TEXT_DIM)
	box.add_child(t)
	var a := _note(box, about)
	if not have:
		a.modulate = Color(1, 1, 1, 0.6)


func _flow(parent: Control) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(flow)
	return flow


# --- helpers -----------------------------------------------------------------

func _scroll(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	DragScroll.attach(scroll)
	return scroll


func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _note(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 100
	l.add_theme_font_size_override("font_size", LabTheme.SMALL_FONT_SIZE)
	l.add_theme_color_override("font_color", LabTheme.TEXT_DIM)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = LabTheme.TAP_HEIGHT
	b.pressed.connect(action)
	parent.add_child(b)
	return b

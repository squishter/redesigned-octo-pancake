extends Control
## Collection & packs: what she has unlocked, and packs to open for more.
##
## Packs: a swipeable hanging display with what each pack gives, its stock,
## and buttons to open it with a free pick or coins; opening one shows what
## came out. Collection: every gem color and every shape in every cut as
## real rendered gems (cut from one off-screen GemBoard3D, like the play
## screen's gem row), then themes, picture types, flourishes, animations,
## finales and power-up charges. Locked things stay a mystery: gems show
## only as flat silhouettes, and names, theme colors and descriptions are
## hidden until found.

signal back_requested

const GameTheme := preload("res://scenes/game/game_theme.gd")
const UI := preload("res://scenes/game/ui_widgets.gd")
const ICON_PX := 128
const ICON_CELL := 100.0
const ICON_COLUMNS := 10
const CELL_SIZE := Vector2(176, 224)
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
var _carousel: PackCarousel
var _pack_title: Label
var _pack_about: Label
var _pack_stock: Label
var _pack_index: Label
var _free: Button
var _buy: Button
var _opening: PackOpening
var _collection_filter := "colors"


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
	_button(top, "Menu", go_back)
	_wallet = Label.new()
	_wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wallet.add_theme_color_override("font_color", GameTheme.GOLD)
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
	if is_instance_valid(_opening):
		_opening.advance_or_close()
	else:
		back_requested.emit()


func _show_tab(packs: bool) -> void:
	_packs_view.visible = packs
	_collection_view.visible = not packs
	GameTheme.appear(_packs_view if packs else _collection_view)
	_tab_packs.set_pressed_no_signal(packs)
	_tab_collection.set_pressed_no_signal(not packs)
	_carousel.set_process(packs)


func _refresh() -> void:
	_wallet.text = "%d coins · %d free pick%s" % [Packs.coins(profile), Packs.picks(profile),
			"" if Packs.picks(profile) == 1 else "s"]
	if _carousel == null:
		_fill_packs()
	else:
		_update_pack(_carousel.current_pack())
	_fill_collection()


# --- packs -------------------------------------------------------------------

func _fill_packs() -> void:
	var heading := Label.new()
	heading.text = "A little wonder, wrapped"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 56)
	heading.add_theme_color_override("font_color", GameTheme.GOLD)
	_packs_list.add_child(heading)
	var hint := _note(_packs_list, "Spin the display. Find your next little discovery.")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_carousel = PackCarousel.new()
	_carousel.selected.connect(_update_pack)
	_packs_list.add_child(_carousel)
	var navigation := HBoxContainer.new()
	navigation.alignment = BoxContainer.ALIGNMENT_CENTER
	_packs_list.add_child(navigation)
	var previous := _button(navigation, "", func() -> void: _carousel.rotate_by(-1))
	previous.icon = GameTheme.icon("back")
	previous.custom_minimum_size.x = 120
	previous.tooltip_text = "Previous pack"
	_pack_index = Label.new()
	_pack_index.custom_minimum_size.x = 400
	_pack_index.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pack_index.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pack_index.add_theme_font_size_override("font_size", 28)
	navigation.add_child(_pack_index)
	var next := _button(navigation, "", func() -> void: _carousel.rotate_by(1))
	next.icon = GameTheme.icon("next")
	next.custom_minimum_size.x = 120
	next.tooltip_text = "Next pack"
	var details := PanelContainer.new()
	_packs_list.add_child(details)
	var box := VBoxContainer.new()
	details.add_child(box)
	_pack_title = Label.new()
	_pack_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pack_title.add_theme_font_size_override("font_size", 52)
	_pack_title.add_theme_color_override("font_color", GameTheme.GOLD)
	box.add_child(_pack_title)
	_pack_about = _note(box, "")
	_pack_about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pack_stock = _note(box, "")
	_pack_stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var actions := HBoxContainer.new()
	box.add_child(actions)
	_free = _button(actions, "Use a free pick", func() -> void: _open(_carousel.current_pack(), true))
	_free.theme_type_variation = "PrimaryButton"
	_buy = _button(actions, "", func() -> void: _open(_carousel.current_pack(), false))
	_buy.icon = GameTheme.icon("coin")
	for button: Button in [_free, _buy]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 34)
	var note := _note(_packs_list, "A free pick every day you visit, and another for your first finished picture. "
		+ "Finish pictures to earn coins. Every discovery is yours to keep.")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_update_pack(_carousel.current_pack())


func _update_pack(pack: String) -> void:
	var info: Dictionary = Packs.PACKS[pack]
	_pack_title.text = info["name"]
	_pack_about.text = info["about"]
	var count := Packs.reward_count(pack)
	if count > 1:
		_pack_about.text += "\nUp to %d distinct discoveries, plus any completed themes." % count
	var left := Packs.pool(pack, profile).size()
	_pack_stock.text = "Collection complete — you found them all!" if left == 0 else (
		"Always a little more magic" if pack in ["powers", "all"] else "%d discoveries still to find" % left)
	_pack_index.text = "SWIPE TO SPIN   ·   %02d / %02d" % [Packs.PACKS.keys().find(pack) + 1, Packs.PACKS.size()]
	_free.disabled = left == 0 or Packs.picks(profile) <= 0
	_buy.disabled = left == 0 or Packs.coins(profile) < Packs.price(pack)
	_buy.text = "%d coins" % Packs.price(pack)


func _open(pack: String, with_pick: bool) -> void:
	if is_instance_valid(_opening):
		return
	var rewards := Packs.open(profile, pack, with_pick, _rng)
	if rewards.is_empty():
		return
	SaveStore.save_profile(profile)
	_refresh()
	_reveal(pack, rewards)


## The complete paid bundle is already saved. Presentation never draws again.
func _reveal(pack: String, rewards: Array[Dictionary]) -> void:
	_opening = PackOpening.new()
	_opening.pack = pack
	_opening.rewards = rewards
	_opening.picture_factory = _item_picture
	_opening.dismissed.connect(func() -> void:
		_opening = null
		_carousel.set_process(_packs_view.visible)
		if not _free.disabled:
			_free.grab_focus()
		elif not _buy.disabled:
			_buy.grab_focus()
		else:
			_carousel.grab_focus())
	_carousel.set_process(false)
	add_child(_opening)


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
	_collection_list.add_child(UI.label("YOUR JEWEL BOX", 27, GameTheme.MINT, true))
	_collection_list.add_child(UI.label("Little discoveries, all yours", 52, GameTheme.GOLD, true))
	var navigation := HBoxContainer.new()
	_collection_list.add_child(navigation)
	for entry: Array in [["colors", "Gem colors", "gem"], ["shapes", "Shapes & cuts", "collage"],
			["extras", "Discoveries", "sparkle"]]:
		var tab := GameTheme.button(entry[1])
		tab.icon = GameTheme.icon(entry[2])
		tab.add_theme_constant_override("icon_max_width", 38)
		tab.add_theme_font_size_override("font_size", 30)
		tab.theme_type_variation = "ChoiceButton"
		tab.toggle_mode = true
		tab.set_pressed_no_signal(_collection_filter == entry[0])
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_select_collection.bind(entry[0]))
		navigation.add_child(tab)
	var unlocks: Dictionary = profile["unlocks"]
	match _collection_filter:
		"colors":
			_collection_colors(unlocks)
		"shapes":
			_collection_shapes(unlocks)
		_:
			_collection_extras(unlocks)


func _select_collection(category: String) -> void:
	_collection_filter = category
	_fill_collection()
	(_collection_view as ScrollContainer).scroll_vertical = 0
	GameTheme.appear(_collection_view)


func _collection_colors(unlocks: Dictionary) -> void:
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


func _collection_shapes(unlocks: Dictionary) -> void:
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


func _collection_extras(unlocks: Dictionary) -> void:
	# Themes come with their colors: a locked one shows only the colors
	# she has found so far, and how many it needs.
	var themes: Array = GemCatalog.unlocked_themes(unlocks)
	_heading(_collection_list, "Color themes", themes.size(), GemCatalog.THEMES.size())
	_note(_collection_list, "A theme is yours once you have all its colors.")
	for t: String in GemCatalog.THEMES:
		var have := GemCatalog.has_theme(unlocks, t)
		var gems: Array = GemCatalog.THEMES[t]["gems"]
		var found := gems.filter(func(g: String) -> bool: return g in unlocks["colors"]).size()
		var title := GemCatalog.theme_name(t) if have else "An undiscovered color story"
		var copy := UI.item(_collection_list, title, "%d / %d colors collected" % [found, gems.size()],
			"palette" if have else "lock", have)
		copy.add_child(_swatches(t, 44, not have, unlocks["colors"]))

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
	var card := UI.panel(false, 12)
	card.custom_minimum_size = CELL_SIZE
	card.size_flags_horizontal = Control.SIZE_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var art_size := CELL_SIZE.x - 24
	if have:
		var icon := TextureRect.new()
		icon.texture = _icons.get(key)
		icon.custom_minimum_size = Vector2.ONE * art_size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(icon)
	else:
		var shape := key.split("|")[0] if "|" in key else "round"
		box.add_child(Silhouette.new(_stone(shape, "", Color.BLACK, ""), art_size / ICON_CELL))
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", GameTheme.TEXT if have else GameTheme.TEXT_DIM)
	box.add_child(label)
	card.tooltip_text = caption if have else "A little discovery still to find"
	return card


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
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(UI.label(text, 44, GameTheme.GOLD))
	if total >= 0:
		var count := UI.label("%d / %d" % [have, total], 30, GameTheme.MINT)
		count.autowrap_mode = TextServer.AUTOWRAP_OFF
		count.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(count)
		parent.add_child(UI.progress(float(have) / maxi(1, total)))


func _subheading(parent: Control, text: String, bright := true) -> void:
	parent.add_child(UI.label(text.to_upper(), 28, GameTheme.MINT if bright else GameTheme.TEXT_DIM))


func _item_row(parent: Control, title: String, about: String, have: bool) -> void:
	UI.item(parent, title if have else "Undiscovered", about, "sparkle" if have else "lock", have)


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
		node.remove_child(child)
		child.queue_free()


func _note(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 100
	l.add_theme_font_size_override("font_size", GameTheme.SMALL_FONT_SIZE)
	l.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := GameTheme.button(text)
	b.custom_minimum_size.y = GameTheme.TAP_HEIGHT
	b.pressed.connect(action)
	parent.add_child(b)
	return b

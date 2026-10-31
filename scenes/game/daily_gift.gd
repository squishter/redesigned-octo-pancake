extends GameDialog
## Celebrates an already saved daily free pick. Presentation never grants or spends it.

signal packs_requested

var profile: Dictionary = {}
var _choose: Button


class GiftArtwork:
	extends Control
	var _time := 0.0
	var _packs: Array[PackVisual] = []

	func _ready() -> void:
		custom_minimum_size.y = 520
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for category: String in ["shapes", "animations", "colors"]:
			var foil := PackVisual.new()
			foil.pack = category
			foil.size = Vector2(360, 540)
			foil.pivot_offset = foil.size / 2.0
			add_child(foil)
			_packs.append(foil)
		visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
		set_process(is_visible_in_tree())
		resized.connect(_layout_packs)
		_layout_packs()

	func _process(delta: float) -> void:
		_time += delta
		_layout_packs()
		queue_redraw()

	func _layout_packs() -> void:
		var scale_factor := minf(0.72, size.x / 880.0)
		var center := size / 2.0
		for i in _packs.size():
			var foil := _packs[i]
			var side := float(i * 2 - 1) if i < 2 else 0.0
			foil.scale = Vector2.ONE * scale_factor * (0.86 if i < 2 else 1.0)
			foil.rotation = side * 0.18 + sin(_time * 0.8 + i) * 0.025
			foil.position = center + Vector2(side * 280 * scale_factor,
					18.0 if i < 2 else -8.0) - foil.pivot_offset
			foil.position.y += sin(_time * 1.2 + i * 1.5) * 7.0

	func _draw() -> void:
		var center := size / 2.0
		var radius := minf(size.x * 0.43, 258.0)
		for i in range(12, 0, -1):
			draw_circle(center, radius * i / 12.0, Color(GameTheme.GOLD, 0.014))
		for i in 12:
			var angle := TAU * i / 12.0 + _time * 0.025
			var ray := PackedVector2Array([center + Vector2.from_angle(angle - 0.025) * radius * 0.3,
					center + Vector2.from_angle(angle - 0.065) * radius * 1.15,
					center + Vector2.from_angle(angle + 0.065) * radius * 1.15,
					center + Vector2.from_angle(angle + 0.025) * radius * 0.3])
			draw_colored_polygon(ray, Color(GameTheme.GOLD, 0.05))
		for i in 24:
			var angle := i * 2.39996
			var orbit := radius * (0.65 + float(i % 5) * 0.12)
			var at := center + Vector2(cos(angle) * orbit * 1.35, sin(angle) * orbit * 0.85)
			at.y += sin(_time * 0.7 + i) * 10.0
			var glow := 0.4 + 0.6 * pow(sin(_time * 1.4 + i), 2.0)
			var width := (4.0 + i % 4 * 2.0) * glow
			var color := Color(GameTheme.MINT if i % 3 == 0 else GameTheme.GOLD, glow * 0.8)
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -width * 1.6),
					at + Vector2(width * 0.45, 0), at + Vector2(0, width * 1.6),
					at + Vector2(-width * 0.45, 0)]), color)


func _init() -> void:
	super("Your daily sparkle", "A little thank-you for stopping by.", "sparkle")
	preferred_height = 1580
	hide()


func _ready() -> void:
	super()
	body.add_child(UI.label("A NEW DAY. A LITTLE MORE MAGIC.", 26, GameTheme.MINT, true))
	body.add_child(GiftArtwork.new())
	body.add_child(UI.label("A free pack, just for you.", 48, GameTheme.GOLD, true))
	var gift := UI.panel(true, 24)
	var style := gift.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.bg_color = Color("#2b3949")
	style.border_color = GameTheme.MINT
	style.shadow_color = Color(GameTheme.MINT, 0.12)
	style.shadow_size = 16
	gift.add_theme_stylebox_override("panel", style)
	body.add_child(gift)
	var row := HBoxContainer.new()
	gift.add_child(row)
	row.add_child(UI.icon("pack", 90))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 6)
	row.add_child(copy)
	copy.add_child(UI.label("+1 FREE PICK", 44, GameTheme.GOLD))
	copy.add_child(UI.label("Already added to your wallet", 28, GameTheme.MINT))
	body.add_child(UI.label("Choose a pack and uncover your next little treasure. "
			+ "Your pick is yours to save or spend whenever you like.", 31, GameTheme.TEXT, true))
	body.add_child(UI.label("Use on any pack except Everything.  ·  %d free pick%s saved" % [
			Packs.picks(profile), "" if Packs.picks(profile) == 1 else "s"], 25, GameTheme.TEXT_DIM, true))
	_choose = GameTheme.button("Choose my free pack", true)
	_choose.icon = GameTheme.icon("pack")
	_choose.pressed.connect(_choose_pack)
	actions.add_child(_choose)
	var later := GameTheme.button("Save it for later")
	later.theme_type_variation = "QuietButton"
	later.icon = GameTheme.icon("close")
	later.pressed.connect(close)
	actions.add_child(later)


func open() -> void:
	super()
	_choose.grab_focus()


func _choose_pack() -> void:
	if not visible:
		return
	close()
	packs_requested.emit()

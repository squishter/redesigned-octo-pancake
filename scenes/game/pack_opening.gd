class_name PackOpening
extends Control
## Presentation only: the caller grants and saves the reward before opening.
## Skipping, Android back, and dismissal never touch the wallet or draw again.

signal dismissed

const GameTheme := preload("res://scenes/game/game_theme.gd")
var pack := "colors"
var item: Dictionary = {}
var picture: Control
var _stage: Control
var _foil: PackVisual
var _card: PanelContainer
var _front: VBoxContainer
var _front_scroll: ScrollContainer
var _back: TextureRect
var _keep: Button
var _skip: Button
var _heading: Label
var _timeline: Tween
var _revealed := false
var _closing := false
var _burst := -1.0
var _glow := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(GameTheme.BG, 0.97)
	shade.show_behind_parent = true
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_stage = Control.new()
	_stage.size = Vector2(900, 1500)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_heading = _label("A little magic inside…", Rect2(40, 10, 820, 100), 54)
	_heading.add_theme_color_override("font_color", GameTheme.GOLD)
	_skip = GameTheme.button("Skip animation")
	_skip.icon = null
	_skip.position = Vector2(580, 120)
	_skip.size = Vector2(280, 90)
	_skip.add_theme_font_size_override("font_size", 28)
	_skip.custom_minimum_size.y = 90
	_skip.pressed.connect(show_reward)
	_stage.add_child(_skip)
	_build_card()
	_foil = PackVisual.new()
	_foil.pack = pack
	_foil.position = Vector2(270, 500)
	_foil.size = Vector2(360, 540)
	_foil.pivot_offset = Vector2(180, 280)
	_stage.add_child(_foil)
	_keep = GameTheme.button("Keep the sparkle", true)
	_keep.position = Vector2(140, 1300)
	_keep.size = Vector2(620, 130)
	_keep.visible = false
	_keep.pressed.connect(close)
	_stage.add_child(_keep)
	for button: Button in [_skip, _keep]:
		# Keep keyboard/controller focus within the opening overlay.
		button.focus_next = button.get_path()
		button.focus_previous = button.get_path()
		for direction: String in ["top", "bottom", "left", "right"]:
			button.set("focus_neighbor_" + direction, button.get_path())
	_skip.grab_focus()
	resized.connect(_layout)
	_layout()
	_animate()


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.position = Vector2(150, 260)
	_card.size = Vector2(600, 910)
	_card.pivot_offset = Vector2(300, 455)
	_card.scale = Vector2.ONE * 0.48
	_card.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#28324a")
	style.border_color = GameTheme.GOLD
	style.set_border_width_all(5)
	style.set_corner_radius_all(34)
	style.set_content_margin_all(38)
	style.shadow_color = Color(GameTheme.GOLD, 0.13)
	style.shadow_size = 22
	_card.add_theme_stylebox_override("panel", style)
	_stage.add_child(_card)
	_front_scroll = ScrollContainer.new()
	_front_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_front_scroll.hide()
	_card.add_child(_front_scroll)
	DragScroll.attach(_front_scroll)
	_front = VBoxContainer.new()
	_front.alignment = BoxContainer.ALIGNMENT_CENTER
	_front.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_front.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_front.add_theme_constant_override("separation", 24)
	_front.visible = false
	_front_scroll.add_child(_front)
	var kind := Label.new()
	kind.text = Unlockables.KINDS.get(item.get("kind", ""), {}).get("found", "A new discovery!").to_upper()
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kind.add_theme_font_size_override("font_size", 28)
	kind.add_theme_color_override("font_color", GameTheme.MINT)
	_front.add_child(kind)
	var holder := CenterContainer.new()
	_front.add_child(holder)
	if picture == null:
		var art := TextureRect.new()
		var glyph := GameTheme.pack_glyph(str(item.get("pack", pack)))
		art.texture = GameTheme.icon(glyph)
		art.custom_minimum_size = Vector2(260, 260)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture = art
	holder.add_child(picture)
	var title := Label.new()
	title.text = str(item.get("name", "A new discovery"))
	if item.get("kind", "") == "power":
		title.text += " ×%d" % item.get("charges", 1)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", GameTheme.GOLD)
	_front.add_child(title)
	var about := Label.new()
	about.text = item.get("about", "")
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	about.add_theme_font_size_override("font_size", 30)
	_front.add_child(about)
	for theme_id: String in item.get("themes", []):
		var theme_label := Label.new()
		theme_label.text = "✦ %s theme completed!" % GemCatalog.theme_name(theme_id)
		theme_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		theme_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		theme_label.add_theme_font_size_override("font_size", 26)
		theme_label.add_theme_color_override("font_color", GameTheme.MINT)
		_front.add_child(theme_label)
	var collected := Label.new()
	collected.text = "YOURS TO CREATE WITH"
	collected.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	collected.add_theme_font_size_override("font_size", 23)
	collected.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	_front.add_child(collected)
	_back = TextureRect.new()
	_back.texture = GameTheme.icon("collection")
	_back.custom_minimum_size = Vector2(400, 600)
	_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card.add_child(_back)


func _layout() -> void:
	var factor := minf(size.x / 960.0, size.y / 1640.0)
	_stage.scale = Vector2.ONE * factor
	_stage.position = (size - Vector2(900, 1500) * factor) / 2.0


func _animate() -> void:
	_timeline = create_tween()
	# The foil flexes before its crimped top peels away.
	_timeline.tween_property(_foil, "position:y", 455.0, 0.32).set_trans(Tween.TRANS_SINE)
	for angle in [-0.045, 0.045, -0.025, 0.0]:
		_timeline.tween_property(_foil, "rotation", angle, 0.08)
	_timeline.tween_callback(func() -> void:
		_foil.unseal()
		_heading.text = "A little magic, unwrapped…"
		Input.vibrate_handheld(25, 0.35))
	_timeline.tween_property(_foil.cap, "position", Vector2(280, -155), 0.4).set_trans(Tween.TRANS_CUBIC)
	_timeline.parallel().tween_property(_foil.cap, "rotation", 0.65, 0.4)
	_timeline.parallel().tween_property(_foil.cap, "modulate:a", 0.0, 0.45)
	_timeline.parallel().tween_property(self, "_glow", 1.0, 0.4)
	_timeline.tween_callback(func() -> void: _card.show())
	# The card starts behind the wrapper, rises out, then turns face up.
	_timeline.tween_property(_card, "position:y", 220.0, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_timeline.parallel().tween_property(_card, "scale", Vector2.ONE * 0.9, 0.65)
	_timeline.parallel().tween_property(_foil, "position:y", 1020.0, 0.65).set_delay(0.1)
	_timeline.parallel().tween_property(_foil, "rotation", 0.18, 0.65)
	_timeline.parallel().tween_property(_foil, "modulate:a", 0.0, 0.4).set_delay(0.35)
	_timeline.tween_property(_card, "scale:x", 0.0, 0.16).set_trans(Tween.TRANS_SINE)
	_timeline.tween_callback(func() -> void:
		_back.hide()
		_front.show()
		_front_scroll.show()
		_burst = 0.0
		_stage.move_child(_card, _stage.get_child_count() - 1)
		Input.vibrate_handheld(45, 0.6))
	_timeline.tween_property(_card, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_timeline.tween_callback(_settle)


func _settle() -> void:
	_revealed = true
	_heading.text = "Look what you found!"
	_skip.hide()
	GameTheme.appear(_keep)
	_keep.grab_focus()


func show_reward() -> void:
	if _revealed or _closing:
		return
	if _timeline != null and _timeline.is_valid():
		_timeline.kill()
	_foil.hide()
	_card.show()
	_card.position = Vector2(150, 220)
	_card.scale = Vector2.ONE
	_front.show()
	_front_scroll.show()
	_back.hide()
	_glow = 1.0
	_burst = 0.0
	_settle()


func advance_or_close() -> void:
	if _revealed:
		close()
	else:
		show_reward()


func close() -> void:
	if not _revealed or _closing:
		return
	_closing = true
	_keep.disabled = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func() -> void:
		dismissed.emit()
		queue_free())


func _process(delta: float) -> void:
	if _burst >= 0.0:
		_burst += delta
	queue_redraw()


func _draw() -> void:
	if _stage == null:
		return
	var factor := _stage.scale.x
	var origin := _stage.position + Vector2(450, 680) * factor
	for i in range(16, 0, -1):
		draw_circle(origin, (130 + i * 22) * factor, Color(GameTheme.pack_color(pack), _glow * 0.012))
	if _burst < 0.0:
		return
	var colors := [GameTheme.GOLD, GameTheme.MINT, Color("#d9a1cf"), Color("#a4baf2")]
	for i in 84:
		var angle := i * 2.39996
		var velocity := Vector2(cos(angle) * (180 + i % 7 * 35), -absf(sin(angle)) * (250 + i % 11 * 28))
		var at := origin + (velocity * _burst + Vector2(0, 170 * _burst * _burst)) * factor
		var alpha := clampf(1.0 - _burst / 3.2, 0.0, 1.0)
		var radius := (5.0 + i % 4 * 2.0) * factor
		var x := radius * cos(_burst * 5.0 + i)
		var points := PackedVector2Array([at + Vector2(-x, 0), at + Vector2(0, -radius),
			at + Vector2(x, 0), at + Vector2(0, radius)])
		if absf(x) > 0.1:
			draw_colored_polygon(points, Color(colors[i % colors.size()], alpha))
	# Small, slow glints remain around the reward after the confetti settles.
	for i in 9:
		var angle := i * TAU / 9.0 + _burst * 0.08
		var at := origin + Vector2(cos(angle) * 360, sin(angle) * 470) * factor
		var radius := (3.0 + 5.0 * absf(sin(_burst * 1.6 + i))) * factor
		draw_line(at - Vector2(radius, 0), at + Vector2(radius, 0), Color(GameTheme.GOLD, 0.65), 2, true)
		draw_line(at - Vector2(0, radius), at + Vector2(0, radius), Color(GameTheme.GOLD, 0.65), 2, true)


func _label(text: String, rect: Rect2, px: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", px)
	_stage.add_child(label)
	return label

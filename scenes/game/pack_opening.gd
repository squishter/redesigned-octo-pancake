class_name PackOpening
extends Control
## Presentation only: the caller grants and saves all rewards before opening.
## Skipping, Android back, and dismissal never touch the wallet or draw again.

signal dismissed

const GameTheme := preload("res://scenes/game/game_theme.gd")
const UI := preload("res://scenes/game/ui_widgets.gd")
var rewards: Array[Dictionary] = []
var picture_factory: Callable
## Legacy single-card inputs are normalized to a one-item bundle at entry.
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
var _index := 0
var _transitioning := false
var _showing_summary := false
var _summary: GameDialog


func _ready() -> void:
	if rewards.is_empty() and not item.is_empty():
		rewards.append(item)
	if rewards.is_empty():
		_reject_empty.call_deferred()
		return
	rewards = rewards.duplicate(true)
	item = rewards[0]
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
	_keep.pressed.connect(_advance)
	_stage.add_child(_keep)
	_update_focus()
	_skip.grab_focus()
	resized.connect(_layout)
	_layout()
	_animate()


func _build_card() -> void:
	if picture_factory.is_valid():
		picture = picture_factory.call(item, 300.0)
	elif _index > 0:
		picture = null
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
	kind.text = "BONUS COLOR STORY" if item.get("bonus", false) else (
		Unlockables.KINDS.get(item.get("kind", ""), {}).get("found", "A new discovery!").to_upper())
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
	_transitioning = false
	_keep.disabled = false
	if rewards.size() > 1:
		_heading.text = "Discovery %d of %d" % [_index + 1, rewards.size()]
		_keep.text = "Next discovery" if _index + 1 < rewards.size() else "See everything you found"
		_keep.icon = GameTheme.icon("next" if _index + 1 < rewards.size() else "collection")
		_skip.text = "Show all rewards"
		_skip.show()
	else:
		_heading.text = "Look what you found!"
		_skip.hide()
	GameTheme.appear(_keep)
	_update_focus()
	_keep.grab_focus()


func _update_focus() -> void:
	var buttons: Array[Button] = []
	for button: Button in [_skip, _keep]:
		if button.visible and not button.disabled:
			buttons.append(button)
	for i in buttons.size():
		var next := buttons[(i + 1) % buttons.size()].get_path()
		buttons[i].focus_next = next
		buttons[i].focus_previous = next
		for direction: String in ["top", "bottom", "left", "right"]:
			buttons[i].set("focus_neighbor_" + direction, next)


func _advance() -> void:
	if _closing or _transitioning or not _revealed:
		return
	if _index + 1 >= rewards.size():
		if rewards.size() > 1:
			show_all_rewards()
		else:
			close()
		return
	_transitioning = true
	_revealed = false
	_keep.disabled = true
	_update_focus()
	_skip.grab_focus()
	_timeline = create_tween()
	_timeline.tween_property(_card, "position:x", 90.0, 0.18).set_trans(Tween.TRANS_QUAD)
	_timeline.parallel().tween_property(_card, "modulate:a", 0.0, 0.18)
	_timeline.tween_callback(_next_card)


func _next_card() -> void:
	_stage.remove_child(_card)
	_card.queue_free()
	_index += 1
	item = rewards[_index]
	_build_card()
	_card.position = Vector2(150, 220)
	_card.scale = Vector2(0, 0.92)
	_card.show()
	_back.hide()
	_front.show()
	_front_scroll.show()
	_heading.text = "Discovery %d of %d" % [_index + 1, rewards.size()]
	_burst = 0.0
	_timeline = create_tween()
	_timeline.tween_property(_card, "scale", Vector2.ONE, 0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_timeline.tween_callback(_settle)
	Input.vibrate_handheld(25, 0.4)


## Skip is presentation only. For bundles it always exposes the full receipt,
## including cards that have not animated yet.
func show_reward() -> void:
	if _closing or _showing_summary or rewards.is_empty():
		return
	if rewards.size() > 1:
		show_all_rewards()
		return
	if _revealed:
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


func show_all_rewards() -> void:
	if _closing or _showing_summary or rewards.is_empty():
		return
	if _timeline != null and _timeline.is_valid():
		_timeline.kill()
	_transitioning = false
	_revealed = true
	_showing_summary = true
	_stage.hide()
	_summary = GameDialog.new("Everything you found", "%d discoveries, all saved to your collection." % rewards.size(),
		"collection")
	_summary.preferred_height = 1700
	for reward: Dictionary in rewards:
		var title: String = reward.get("name", "A new discovery")
		if reward.get("kind") == "power":
			title += " ×%d" % reward.get("charges", 1)
		if reward.get("bonus", false):
			title = "Bonus · " + title
		var copy := UI.item(_summary.body, title, reward.get("about", ""),
			GameTheme.pack_glyph(reward.get("pack", pack)))
		if picture_factory.is_valid():
			var art: Control = picture_factory.call(reward, 84.0)
			if art != null:
				var row := copy.get_parent()
				var placeholder := row.get_child(0)
				row.remove_child(placeholder)
				placeholder.queue_free()
				row.add_child(art)
				row.move_child(art, 0)
	var done := GameTheme.button("Keep all the sparkle", true)
	done.pressed.connect(_summary.close)
	_summary.actions.add_child(done)
	_summary.closed.connect(close)
	_summary.hide()
	add_child(_summary)
	_summary.open()


func advance_or_close() -> void:
	if _showing_summary:
		close()
	elif rewards.size() > 1:
		show_all_rewards()
	elif _revealed:
		close()
	else:
		show_reward()


func close() -> void:
	if _closing:
		return
	if rewards.size() > 1 and not _showing_summary:
		show_all_rewards()
		return
	if not _revealed:
		return
	_closing = true
	_keep.disabled = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func() -> void:
		dismissed.emit()
		queue_free())


func _reject_empty() -> void:
	dismissed.emit()
	queue_free()


func _process(delta: float) -> void:
	if _showing_summary:
		return
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

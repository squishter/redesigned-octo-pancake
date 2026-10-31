extends Control
## Branded launch cover. A tap or keyboard action can shorten the three-second hold.

signal finished

const GameTheme := preload("res://scenes/game/game_theme.gd")
const UI := preload("res://scenes/game/ui_widgets.gd")
const COVER := preload("res://assets/splash/cover.png")
const TITLE_FONT := preload("res://assets/fonts/DMSerifDisplay-Regular.ttf")
const HOLD_TIME := 3.0
const MIN_HOLD := 0.35

var _elapsed := 0.0
var _finished := false
var _art: TextureRect
var _timer: Timer
var _hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_art = TextureRect.new()
	_art.texture = COVER
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_art)
	resized.connect(func() -> void: _art.pivot_offset = size / 2.0)
	_art.pivot_offset = size / 2.0
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	gradient.colors = PackedColorArray([Color(0.02, 0.07, 0.12, 0.25), Color.TRANSPARENT,
			Color.TRANSPARENT, Color(0.02, 0.07, 0.12, 0.65)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	shade.texture = texture
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var brand := VBoxContainer.new()
	brand.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	brand.anchor_left = 0.12
	brand.anchor_right = 0.88
	brand.anchor_top = 0.065
	brand.anchor_bottom = 0.30
	brand.add_theme_constant_override("separation", 0)
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(brand)
	SafeArea.apply(brand)
	var paint := _label("Paint With", 56, Color("#e2f3e7"))
	brand.add_child(paint)
	var gems := _label("Gems", 166, Color("#fff0c9"))
	gems.add_theme_font_override("font", TITLE_FONT)
	brand.add_child(gems)
	brand.add_child(_label("Find your calm. Make it sparkle.", 30, Color("#e2f3e7")))
	brand.modulate.a = 0.0
	var entrance := create_tween()
	entrance.tween_property(brand, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	var footer := VBoxContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	footer.anchor_top = 0.87
	footer.anchor_bottom = 1.0
	footer.offset_bottom = -48
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 16)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer)
	SafeArea.apply(footer)
	footer.add_child(_label("ONE GEM AT A TIME", 24, Color("#fff0c9")))
	_hint = _label("Tap to continue", 27, Color("#e2f3e7"))
	_hint.modulate.a = 0.0
	footer.add_child(_hint)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = HOLD_TIME
	_timer.timeout.connect(_finish)
	add_child(_timer)
	_timer.start()


func _label(text: String, px: int, color: Color) -> Label:
	var label := UI.label(text, px, color, true)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_shadow_color", Color(0.01, 0.04, 0.07, 0.8))
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.add_theme_constant_override("shadow_outline_size", 3)
	return label


func _process(delta: float) -> void:
	_elapsed += delta
	_art.scale = Vector2.ONE * (1.005 + minf(_elapsed / HOLD_TIME, 1.0) * 0.005)
	_hint.modulate.a = clampf((_elapsed - 0.65) / 0.5, 0.0, 0.85)


func _gui_input(event: InputEvent) -> void:
	if ((event is InputEventScreenTouch and event.pressed)
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)):
		go_back()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		go_back()
		get_viewport().set_input_as_handled()


func go_back() -> void:
	if _elapsed >= MIN_HOLD:
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_timer.stop()
	finished.emit()

class_name GameDialog
extends Control
## A responsive player dialog with a scrollable body, fixed actions, and focus containment.

signal closed

const GameTheme := preload("res://scenes/game/game_theme.gd")
const UI := preload("res://scenes/game/ui_widgets.gd")
var body: VBoxContainer
var actions: VBoxContainer
var title_label: Label
var subtitle_label: Label
var card: PanelContainer
var preferred_height := 1620.0
var _close: Button
var _previous_focus: Control
var _motion: Tween


func _init(title := "", subtitle := "", glyph := "sparkle") -> void:
	z_index = 220
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(GameTheme.BG, 0.95)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	card = UI.panel(true, 36)
	add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 28)
	card.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	header.add_child(UI.icon(glyph, 84))
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 10)
	header.add_child(titles)
	title_label = UI.label(title, 50, GameTheme.GOLD)
	titles.add_child(title_label)
	subtitle_label = UI.label(subtitle, 29, GameTheme.TEXT_DIM)
	titles.add_child(subtitle_label)
	_close = GameTheme.button("")
	_close.icon = GameTheme.icon("close")
	_close.custom_minimum_size = Vector2(100, 100)
	_close.tooltip_text = "Close"
	_close.pressed.connect(close)
	header.add_child(_close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	DragScroll.attach(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	actions = VBoxContainer.new()
	column.add_child(actions)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	card.size = Vector2(minf(980, maxf(0, size.x - 72)), minf(preferred_height, maxf(0, size.y - 160)))
	card.position = (size - card.size) / 2.0


func open() -> void:
	_previous_focus = get_viewport().gui_get_focus_owner()
	GameTheme.appear(self)
	_layout()
	if _motion != null and _motion.is_valid():
		_motion.kill()
	card.pivot_offset = card.size / 2.0
	card.scale = Vector2.ONE * 0.96
	_motion = create_tween()
	_motion.tween_property(card, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	contain_focus.call_deferred()
	_close.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()


func contain_focus() -> void:
	var controls: Array[Control] = []
	for child: Control in find_children("*", "Control", true, false):
		if child.is_visible_in_tree() and child.focus_mode != Control.FOCUS_NONE:
			controls.append(child)
	for i in controls.size():
		controls[i].focus_next = controls[(i + 1) % controls.size()].get_path()
		controls[i].focus_previous = controls[posmod(i - 1, controls.size())].get_path()

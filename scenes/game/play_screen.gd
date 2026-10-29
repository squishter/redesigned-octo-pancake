extends Control
## Playing one saved puzzle: fill every slot with its gem.
##
## Up top, the gems still to place, fully rendered (cut from one small
## GemBoard3D of single stones, so they glint too), each with its number
## and how many are left; a type goes once all its slots are filled. Pick
## one and its open slots stand out on the board (SlotOverlay); tap a slot,
## or drag across several, and each flies in from the gem row (GemFlights)
## or pops into place (the fill_animation setting) with a tiny buzz. The
## row scrolls with a drag (and flings) and picks a gem with a tap. A
## drag that doesn't start on one of the selected gem's slots pans, two
## fingers pinch. When the last stone is in, the picture ripples and
## sparkles, and from then on it's only for looking at, zoomed and panned
## at will. Progress saves every few seconds and on leaving.

signal back_requested

const LabTheme := preload("res://scenes/dev/lab_theme.gd")
## The icon board: px per icon, its cells in board units, and icons per row.
const ICON_PX := 150
const ICON_CELL := 100.0
const ICON_COLUMNS := 8
const ITEM_SIZE := Vector2(168, 236)
const SAVE_EVERY := 2.0
## The buzz for each placed stone, and the least time between buzzes.
const BUZZ_MS := 18
const BUZZ_AMPLITUDE := 0.45
const BUZZ_GAP_MS := 35
## How far off a slot a touch may land and still fill it (screen px):
## more for a tap, less while dragging so a stroke doesn't sweep in neighbors.
const TAP_SLOP := 12.0
const DRAG_SLOP := 4.0
## The gem row: how far a finger moves before a touch scrolls instead of
## picking a gem, and how fast a fling slows (per second).
const ROW_DEADZONE := 20.0
const FLING_DECAY := 4.0

## Set before adding to the tree.
var puzzle_id := ""
var profile: Dictionary = {}

var _meta: Dictionary = {}
var _picture: Dictionary = {}
## Gem types, numbered from 1 in this order: [{shape, cut, gem, color, count, left, ratio}].
var _types: Array[Dictionary] = []
var _type_of := PackedInt32Array()
var _filled := 0
var _board: GemBoard3D
var _overlay: SlotOverlay
var _icons: GemBoard3D
var _palette: ScrollContainer
var _row: HBoxContainer
## Gem row cards by gem type, their icons and "left" labels.
var _items := {}
var _item_icons := {}
var _left_labels := {}
var _card_style: StyleBoxFlat
var _picked_style: StyleBoxFlat
## The finger on the gem row (-1 none), where it went down and last was,
## whether it has scrolled, the row's scroll and its fling speed (px/s).
var _row_touch := -1
var _row_start := Vector2.ZERO
var _row_last := Vector2.ZERO
var _row_last_ms := 0
var _row_moved := false
var _scroll_x := 0.0
var _fling := 0.0
var _flights: GemFlights
## "fly" or "pop" (see SaveStore.DEFAULT_SETTINGS).
var _fill_animation := "fly"
## The last stone is placed and the finale waits for gems still flying.
var _finish_pending := false
var _progress: Label
var _done_bar: Control
var _area: Control
var _selected := -1
## The gem type the current stroke fills.
var _stroke_type := -1
var _done := false
var _dirty := false
var _since_save := 0.0
var _last_buzz := -BUZZ_GAP_MS


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	add_child(root)
	SafeArea.apply(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	_button(top, "‹ Menu", _leave)
	_progress = Label.new()
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.add_theme_color_override("font_color", LabTheme.TEXT_DIM)
	top.add_child(_progress)
	_button(top, "Fit", func() -> void: _board.reset_view())

	# The gem row scrolls by hand (see _input): its cards ignore touches, so
	# a drag that starts on one scrolls rather than getting stuck on it.
	_palette = ScrollContainer.new()
	_palette.custom_minimum_size.y = ITEM_SIZE.y + 24
	_palette.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_palette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_palette)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 14)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_palette.add_child(_row)
	_card_style = _card(LabTheme.FIELD, Color.TRANSPARENT)
	_picked_style = _card(LabTheme.FIELD_PRESSED, LabTheme.GOLD)
	_fill_animation = profile.get("settings", {}).get("fill_animation", "fly")

	_done_bar = HBoxContainer.new()
	_done_bar.custom_minimum_size.y = _palette.custom_minimum_size.y
	_done_bar.visible = false
	root.add_child(_done_bar)
	var done_label := Label.new()
	done_label.text = "Finished! Pinch and drag to admire it."
	done_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	done_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	done_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	done_label.add_theme_color_override("font_color", LabTheme.GOLD)
	_done_bar.add_child(done_label)

	_area = Control.new()
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area.clip_contents = true
	root.add_child(_area)
	_board = GemBoard3D.new()
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_area.add_child(_board)
	_overlay = SlotOverlay.new()
	_overlay.board = _board
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_area.add_child(_overlay)
	_board.stroke_filter = _can_stroke
	_board.stroke_started.connect(_on_stroke_started)
	_board.stroke_moved.connect(_on_stroke_moved)
	_board.stroke_ended.connect(func() -> void: _stroke_type = -1)
	# Over everything, so gems fly from the row down onto the board.
	_flights = GemFlights.new()
	_flights.board = _board
	_flights.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flights.landed.connect(_on_landed)
	add_child(_flights)

	_load()


func _load() -> void:
	_meta = SaveStore.find(profile, puzzle_id)
	_picture = SaveStore.load_picture(puzzle_id)
	if _picture.is_empty() or _meta.is_empty():
		_progress.text = "This puzzle couldn't be loaded."
		_palette.visible = false
		return
	var slots: Array = _picture["slots"]
	var placed := SaveStore.load_progress(puzzle_id, slots.size())
	_number_types(slots)
	var colors := PackedColorArray()
	for t in _types:
		colors.append(t["color"])
	_filled = 0
	for i in slots.size():
		if placed[i] != 0:
			_filled += 1
			_types[_type_of[i]]["left"] -= 1
	_overlay.setup(_picture, _type_of, colors, placed)
	_board.show_collage(_picture, placed)
	_build_icons()
	_build_palette()
	_update_progress()
	if _filled >= slots.size():
		_finish(false)
	else:
		_select(_next_open(-1))


## Gives each gem type (shape, cut and color) a number, the most used first.
func _number_types(slots: Array) -> void:
	var by_key := {}
	for s: Dictionary in slots:
		var key := _type_key(s)
		if not by_key.has(key):
			by_key[key] = {"key": key, "shape": s["shape"], "cut": s.get("cut", ""), "gem": s.get("target_gem"),
					"color": s["target_color"], "count": 0, "ratios": []}
		by_key[key]["count"] += 1
		by_key[key]["ratios"].append(float(s["width"]) / maxf(float(s["size"]), 0.001))
	var list := by_key.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["count"] > b["count"] or (a["count"] == b["count"] and a["key"] < b["key"]))
	_types.clear()
	var index := {}
	for t: Dictionary in list:
		var ratios: Array = t["ratios"]
		ratios.sort()
		t["ratio"] = clampf(ratios[ratios.size() / 2], 0.3, 1.0)
		t["left"] = t["count"]
		t.erase("ratios")
		index[t["key"]] = _types.size()
		_types.append(t)
	_type_of.resize(slots.size())
	for i in slots.size():
		_type_of[i] = index[_type_key(slots[i])]


static func _type_key(s: Dictionary) -> String:
	var gem: Variant = s.get("target_gem")
	var color := str(gem) if gem != null else (s["target_color"] as Color).to_html(false)
	return "%s|%s|%s" % [s["shape"], s.get("cut", ""), color]


## One stone of every gem type on a small board of its own, kept off screen;
## the palette shows its cells, so the icons are real lit gems.
func _build_icons() -> void:
	var n := _types.size()
	var cols := maxi(1, mini(n, ICON_COLUMNS))
	var rows := maxi(1, ceili(float(n) / cols))
	var stones := []
	for t in n:
		var ty := _types[t]
		var shape: String = ty["shape"]
		var long := shape in GemVariety.LONG_FAMILY or shape in GemVariety.BOX_FAMILY
		var length := ICON_CELL * (0.8 if long else 0.62)
		stones.append({
			"x": (t % cols + 0.5) * ICON_CELL,
			"y": (t / cols + 0.5) * ICON_CELL,
			"size": length,
			"width": length * ty["ratio"] if long else length,
			"rotation": -PI / 4.0 if long else SlotPacker.upright(shape),
			"shape": shape,
			"cut": ty["cut"],
			"target_color": ty["color"],
			"target_gem": ty["gem"],
		})
	_icons = GemBoard3D.new()
	_icons.margin = 0.0
	_icons.input_enabled = false
	_icons.shadows = false
	_icons.set_transparent()
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icons.position = Vector2(-100000.0, 0.0)
	_icons.size = Vector2(cols, rows) * ICON_PX
	add_child(_icons)
	_icons.set_always_render()
	_icons.show_collage({"width": cols * ICON_CELL, "height": rows * ICON_CELL, "slots": stones})
	for t in n:
		var icon := AtlasTexture.new()
		icon.atlas = _icons.get_view_texture()
		icon.region = Rect2(Vector2(t % cols, t / cols) * ICON_PX, Vector2(ICON_PX, ICON_PX))
		_types[t]["icon"] = icon
		_types[t]["icon_share"] = stones[t]["size"] / ICON_CELL
		_types[t]["icon_rotation"] = stones[t]["rotation"]


func _build_palette() -> void:
	for t in _types.size():
		if _types[t]["left"] > 0:
			_row.add_child(_make_item(t))


## A gem row card: the rendered gem, its number and how many are left.
func _make_item(t: int) -> PanelContainer:
	var b := PanelContainer.new()
	b.custom_minimum_size = ITEM_SIZE
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("panel", _card_style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	b.add_child(box)
	var icon := TextureRect.new()
	icon.texture = _types[t]["icon"]
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var number := Label.new()
	number.text = str(t + 1)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(number)
	var left := Label.new()
	left.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_font_size_override("font_size", LabTheme.SMALL_FONT_SIZE - 4)
	left.add_theme_color_override("font_color", LabTheme.TEXT_DIM)
	box.add_child(left)
	_items[t] = b
	_item_icons[t] = icon
	_left_labels[t] = left
	_update_left(t)
	return b


static func _card(color: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(18)
	box.set_content_margin_all(12)
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(5)
	return box


func _update_left(t: int) -> void:
	if _left_labels.has(t):
		(_left_labels[t] as Label).text = "× %d" % _types[t]["left"]


## Selects a gem type (-1 for none): its slots stand out on the board.
func _select(t: int) -> void:
	if _items.has(_selected):
		(_items[_selected] as Control).add_theme_stylebox_override("panel", _card_style)
	_selected = t
	_overlay.selected = t
	if _items.has(t):
		(_items[t] as Control).add_theme_stylebox_override("panel", _picked_style)


func _apply_scroll() -> void:
	var most := maxf(0.0, _row.size.x - _palette.size.x)
	_scroll_x = clampf(_scroll_x, 0.0, most)
	_palette.scroll_horizontal = int(_scroll_x)


## The gem row's touches: a drag scrolls it (and flings on letting go), a
## tap picks the gem under the finger (or lets go of the picked one).
func _input(event: InputEvent) -> void:
	if not _palette.is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var p := _row_point(event.position)
		if event.pressed and _row_touch < 0 and Rect2(Vector2.ZERO, _palette.size).has_point(p):
			_row_touch = event.index
			_row_start = event.position
			_row_last = event.position
			_row_last_ms = Time.get_ticks_msec()
			_row_moved = false
			_fling = 0.0
		elif not event.pressed and event.index == _row_touch:
			_row_touch = -1
			if not _row_moved:
				_tap_row(p)
	elif event is InputEventScreenDrag and event.index == _row_touch:
		var dx: float = event.position.x - _row_last.x
		if not _row_moved and absf(event.position.x - _row_start.x) > ROW_DEADZONE:
			_row_moved = true
		if _row_moved:
			_scroll_x -= dx / _row_scale()
			_apply_scroll()
			var now := Time.get_ticks_msec()
			var dt := maxf((now - _row_last_ms) / 1000.0, 0.004)
			_fling = lerpf(_fling, -dx / _row_scale() / dt, 0.5)
			_row_last_ms = now
		_row_last = event.position
	elif event is InputEventMouseButton and event.pressed:
		if Rect2(Vector2.ZERO, _palette.size).has_point(_row_point(event.position)):
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT]:
				_scroll_x -= ITEM_SIZE.x
				_apply_scroll()
			elif event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT]:
				_scroll_x += ITEM_SIZE.x
				_apply_scroll()


## A point on screen in the row's px, and the row's px per screen px.
func _row_point(at: Vector2) -> Vector2:
	return _palette.get_global_transform_with_canvas().affine_inverse() * at


func _row_scale() -> float:
	return _palette.get_global_transform_with_canvas().get_scale().x


func _tap_row(p: Vector2) -> void:
	var at := p + Vector2(_scroll_x, 0.0)
	for t: int in _items:
		var b: Control = _items[t]
		if Rect2(b.position, b.size).has_point(at):
			_select(-1 if t == _selected else t)
			return


## The first gem type after `t` with slots left (wrapping round), or -1.
func _next_open(t: int) -> int:
	for k in _types.size():
		var u := (t + 1 + k) % _types.size()
		if _types[u]["left"] > 0:
			return u
	return -1


func _can_stroke(at: Vector2) -> bool:
	return not _done and _selected >= 0 and _overlay.slot_at(at, _selected, TAP_SLOP / _board.scale_px()) >= 0


func _on_stroke_started(at: Vector2) -> void:
	_stroke_type = _selected
	_fill_at(at, TAP_SLOP)


## Fills every slot the finger passed over, sampling the way in short steps.
func _on_stroke_moved(from: Vector2, to: Vector2) -> void:
	var step := maxf(float(_picture.get("unit", 6.0)) * 0.5, 0.5)
	var n := maxi(1, ceili(from.distance_to(to) / step))
	for k in range(1, n + 1):
		_fill_at(from.lerp(to, float(k) / n), DRAG_SLOP)


func _fill_at(at: Vector2, slop: float) -> void:
	if _stroke_type < 0 or _done:
		return
	var i := _overlay.slot_at(at, _stroke_type, slop / _board.scale_px())
	if i >= 0:
		_fill(i)


func _fill(i: int) -> void:
	var t := _type_of[i]
	_overlay.place(i)
	if not (_fill_animation == "fly" and _fly(i, t)):
		_board.fill_slot(i)
		_buzz()
	_filled += 1
	_types[t]["left"] -= 1
	_update_left(t)
	_update_progress()
	_dirty = true
	if _types[t]["left"] <= 0:
		_retire(t)
	if _filled >= _type_of.size():
		_finish_pending = true
		_try_finish()


## Sends the gem flying from its card into slot i, from wherever the card
## is, scrolled out of view or not; false if it couldn't go.
func _fly(i: int, t: int) -> bool:
	var ty := _types[t]
	if not _item_icons.has(t) or not ty.has("icon"):
		return false
	var icon: Control = _item_icons[t]
	var from := icon.get_global_rect().get_center()
	from = _flights.get_global_transform_with_canvas().affine_inverse() * from
	var s: Dictionary = _overlay.slots[i]
	var size := minf(icon.size.x, icon.size.y)
	return _flights.send(i, ty["icon"], ty["icon_share"], from, size, Vector2(s["x"], s["y"]), s["size"],
			s["rotation"], ty["icon_rotation"], ty["color"])


func _on_landed(i: int) -> void:
	_board.land_slot(i)
	_buzz()
	_try_finish()


## The finale, once the last stone is in and nothing is still flying.
func _try_finish() -> void:
	if _finish_pending and _flights.flying() == 0 and not _done:
		_finish_pending = false
		_finish(true)


## A gem type with nothing left to place leaves the palette; the next one
## is picked up, so she can carry on.
func _retire(t: int) -> void:
	var b: Control = _items.get(t)
	_items.erase(t)
	_item_icons.erase(t)
	_left_labels.erase(t)
	if b != null:
		var fade := create_tween()
		fade.tween_property(b, "modulate:a", 0.0, 0.25)
		fade.tween_callback(b.queue_free)
	if _selected == t:
		_select(_next_open(t))


func _buzz() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_buzz < BUZZ_GAP_MS:
		return
	_last_buzz = now
	Input.vibrate_handheld(BUZZ_MS, BUZZ_AMPLITUDE)


func _update_progress() -> void:
	var total := _type_of.size()
	_progress.text = "%d / %d gems" % [_filled, total] if _filled < total else "All %d gems placed" % total


## The picture is done: from now on it's only for looking at. `celebrate`
## plays the finale (not when reopening a finished picture).
func _finish(celebrate: bool) -> void:
	_done = true
	_stroke_type = -1
	_select(-1)
	_board.stroke_filter = Callable()
	_overlay.visible = false
	_palette.visible = false
	_done_bar.visible = true
	if not celebrate:
		return
	_save(true)
	var w: float = _picture["width"]
	var h: float = _picture["height"]
	var lasts := _board.celebrate(Vector2(w, h) / 2.0)
	Input.vibrate_handheld(70, 0.7)
	var banner := Label.new()
	banner.text = "Finished!"
	banner.add_theme_font_size_override("font_size", 120)
	banner.add_theme_color_override("font_color", LabTheme.GOLD)
	banner.add_theme_color_override("font_outline_color", LabTheme.BG)
	banner.add_theme_constant_override("outline_size", 24)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_area.add_child(banner)
	banner.pivot_offset = _area.size / 2.0
	banner.scale = Vector2(0.3, 0.3)
	banner.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(banner, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(banner, "modulate:a", 1.0, 0.3)
	tw.tween_interval(maxf(lasts, 1.5))
	tw.tween_property(banner, "modulate:a", 0.0, 0.8)
	tw.tween_callback(banner.queue_free)


func _process(delta: float) -> void:
	if _row_touch < 0 and absf(_fling) > 10.0:
		_scroll_x += _fling * delta
		_fling *= exp(-delta * FLING_DECAY)
		_apply_scroll()
		if _scroll_x <= 0.0 or _scroll_x >= _row.size.x - _palette.size.x:
			_fling = 0.0
	if not _dirty:
		return
	_since_save += delta
	if _since_save >= SAVE_EVERY:
		_save(false)


## Writes progress and the profile; `thumbnail` redraws the menu's picture too.
func _save(thumbnail: bool) -> void:
	if _picture.is_empty() or _meta.is_empty():
		return
	_dirty = false
	_since_save = 0.0
	SaveStore.save_progress(puzzle_id, _overlay.placed)
	_meta["filled"] = _filled
	_meta["done"] = _done
	_meta["updated"] = int(Time.get_unix_time_from_system())
	SaveStore.save_profile(profile)
	if thumbnail:
		SaveStore.save_thumbnail(puzzle_id, Thumbnail.render(_picture, _overlay.placed))


func _leave() -> void:
	_flights.land_all()
	_save(true)
	back_requested.emit()


## Android's back button.
func go_back() -> void:
	_leave()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		if _dirty:
			_save(true)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = LabTheme.TAP_HEIGHT
	b.pressed.connect(action)
	parent.add_child(b)
	return b

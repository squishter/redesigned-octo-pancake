extends PanelContainer
## The generator lab's web line-art catalog (WebArtCatalog): a search box over
## a scrolling grid of line-art thumbnails. Thumbnails load a few per frame,
## nearest the top of the list first, so long lists open at once. Tapping a
## card emits `picked`; its credit shows under the search box.

signal picked(item: Dictionary)

const LabTheme := preload("res://scenes/dev/lab_theme.gd")
const CARD := Vector2(300, 360)
const THUMBS_PER_FRAME := 4

var catalog: WebArtCatalog

var _search: LineEdit
var _count: Label
var _credit: Label
var _grid: HFlowContainer
var _scroll: ScrollContainer
## Cards still waiting for their thumbnail, in list order.
var _pending: Array[Button] = []


func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_search = LineEdit.new()
	_search.placeholder_text = "Search: bird, flower, vase…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size.y = LabTheme.TAP_HEIGHT
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	top.add_child(_search)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size.y = LabTheme.TAP_HEIGHT
	close.pressed.connect(hide)
	top.add_child(close)
	_count = _small_label()
	box.add_child(_count)
	_credit = _small_label()
	_credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_credit)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	DragScroll.attach(_scroll)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)
	if catalog == null:
		catalog = WebArtCatalog.open()
	_fill()


## Shows the browser, the search box ready to type in.
func open() -> void:
	show()
	_search.grab_focus()


func _small_label() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", LabTheme.SMALL_FONT_SIZE)
	l.add_theme_color_override("font_color", LabTheme.TEXT_DIM)
	return l


func _fill() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_pending.clear()
	if catalog.items.is_empty():
		_count.text = "No catalog at %s yet: build one with tools/web_art/build_catalog.py." % catalog.dir
		return
	var found := catalog.search(_search.text)
	_count.text = "%d of %d pictures" % [found.size(), catalog.items.size()]
	for item: Dictionary in found:
		var b := Button.new()
		b.custom_minimum_size = CARD
		b.text = item.get("title", "")
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.clip_text = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.expand_icon = true
		b.add_theme_font_size_override("font_size", LabTheme.SMALL_FONT_SIZE)
		b.tooltip_text = WebArtCatalog.credit(item)
		b.set_meta("item", item)
		b.pressed.connect(func() -> void:
			_credit.text = WebArtCatalog.credit(item)
			picked.emit(item))
		_grid.add_child(b)
		_pending.append(b)
	_scroll.scroll_vertical = 0


func _process(_delta: float) -> void:
	if not visible or _pending.is_empty():
		return
	# Cards in view (or just below it) first, a few per frame.
	var view := Rect2(Vector2(0.0, _scroll.scroll_vertical), _scroll.size).grow_individual(0, 0, 0, CARD.y * 2.0)
	var done := 0
	for b in _pending.duplicate():
		if done >= THUMBS_PER_FRAME:
			break
		if not is_instance_valid(b):
			_pending.erase(b)
			continue
		if b.get_rect().intersects(view):
			var img := catalog.image(b.get_meta("item"), "thumb")
			if img != null:
				b.icon = ImageTexture.create_from_image(img)
			_pending.erase(b)
			done += 1

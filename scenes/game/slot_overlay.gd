class_name SlotOverlay
extends Control
## Drawn over the GemBoard3D while playing: every open slot as a thin
## outline of its shape with its gem type's number in it. The selected
## type's open slots stand out (darker outlines over a tint of its color).
## Numbers are drawn at screen size, scaling with the zoom, and hide where a
## slot is too small to hold them.
##
## Outlines are drawn once in board units into a child node that only moves
## and scales with the view; they are rebuilt per gem type, and only for the
## types whose slots changed. Also finds the open slot of a type under a point.

const OUTLINE := Color(0.33, 0.28, 0.4, 0.38)
const OUTLINE_SELECTED := Color(0.13, 0.08, 0.2, 0.95)
const NUMBER := Color(0.3, 0.25, 0.36, 0.7)
const NUMBER_SELECTED := Color(0.1, 0.05, 0.16, 1.0)
const TINT_ALPHA := 0.32
## Numbers show when the slot is at least this many px across (the font is
## about half of it, up to MAX_FONT).
const MIN_LABEL_PX := 44.0
const MAX_FONT := 72

var board: GemBoard3D
var slots: Array = []
## Each slot's gem type (an index into `type_colors`).
var type_of := PackedInt32Array()
var type_colors := PackedColorArray()
## 1 for placed slots.
var placed := PackedByteArray()
## The selected gem type, or -1.
var selected := -1:
	set(value):
		selected = value
		_tint_dirty = true
		_shapes.queue_redraw()
		_labels.queue_redraw()

var _shapes := Node2D.new()
var _labels := Control.new()
## Slot outlines in board units, and each type's open-slot outlines as line
## segments (dirty types rebuild on the next frame).
var _polys: Array[PackedVector2Array] = []
var _lines: Array[PackedVector2Array] = []
var _of_type: Array[Array] = []
var _dirty := {}
var _tint: ArrayMesh
var _tint_dirty := true
## Slots by grid cell: every cell a slot's box touches, and only the cell
## of its center (for labels).
var _grid := {}
var _by_center := {}
var _cell := 16.0
var _max_minor := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	add_child(_shapes)
	_shapes.draw.connect(_draw_shapes)
	_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_labels.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_labels)
	_labels.draw.connect(_draw_labels)
	board.view_changed.connect(_follow_view)
	resized.connect(_follow_view)


## Starts showing a puzzle: its slots, their types and which are placed.
func setup(picture: Dictionary, types: PackedInt32Array, colors: PackedColorArray, done: PackedByteArray) -> void:
	slots = picture["slots"]
	type_of = types
	type_colors = colors
	placed = done
	_polys.clear()
	_grid.clear()
	_by_center.clear()
	_max_minor = 0.0
	_cell = maxf(float(picture.get("unit", 6.0)) * 4.0, 8.0)
	for i in slots.size():
		var s: Dictionary = slots[i]
		_polys.append(GemShapes.slot_polygon(s, 16))
		var c := Vector2(s["x"], s["y"])
		var reach := maxf(s["size"], s["width"]) / 2.0
		var lo := Vector2i(((c - Vector2(reach, reach)) / _cell).floor())
		var hi := Vector2i(((c + Vector2(reach, reach)) / _cell).floor())
		for gy in range(lo.y, hi.y + 1):
			for gx in range(lo.x, hi.x + 1):
				_grid.get_or_add(Vector2i(gx, gy), []).append(i)
		_by_center.get_or_add(Vector2i((c / _cell).floor()), []).append(i)
		_max_minor = maxf(_max_minor, minf(s["size"], s["width"]))
	_lines.clear()
	_lines.resize(colors.size())
	_of_type.clear()
	_of_type.resize(colors.size())
	for t in colors.size():
		_of_type[t] = []
	for i in slots.size():
		_of_type[type_of[i]].append(i)
	for t in colors.size():
		_dirty[t] = true
	_tint_dirty = true
	_follow_view()


## Marks a slot placed; its outline and number go.
func place(i: int) -> void:
	placed[i] = 1
	_dirty[type_of[i]] = true
	if type_of[i] == selected:
		_tint_dirty = true
	_labels.queue_redraw()


## The open slot of `gem_type` under board point `at` (within `tolerance`
## board units of its outline), nearest its center first; -1 if none.
func slot_at(at: Vector2, gem_type: int, tolerance: float) -> int:
	var cell := Vector2i((at / _cell).floor())
	var best := -1
	var best_q := INF
	for gy in range(cell.y - 1, cell.y + 2):
		for gx in range(cell.x - 1, cell.x + 2):
			for i: int in _grid.get(Vector2i(gx, gy), []):
				if placed[i] != 0 or type_of[i] != gem_type:
					continue
				var s: Dictionary = slots[i]
				var d := (at - Vector2(s["x"], s["y"])).rotated(-float(s["rotation"]))
				var a: float = s["size"] / 2.0 + tolerance
				var b: float = s["width"] / 2.0 + tolerance
				var q := (d.x * d.x) / (a * a) + (d.y * d.y) / (b * b)
				if q <= 1.0 and q < best_q:
					best_q = q
					best = i
	return best


func _process(_delta: float) -> void:
	if _dirty.is_empty() and not _tint_dirty:
		return
	for t: int in _dirty:
		_rebuild_type(t)
	_dirty.clear()
	if _tint_dirty:
		_tint_dirty = false
		_rebuild_tint()
	_shapes.queue_redraw()


func _rebuild_type(t: int) -> void:
	var segs := PackedVector2Array()
	for i in _of_type[t]:
		if placed[i] != 0:
			continue
		var poly := _polys[i]
		var n := poly.size()
		for j in n:
			segs.append(poly[j])
			segs.append(poly[(j + 1) % n])
	_lines[t] = segs


## One mesh of the selected type's open slots, to tint them.
func _rebuild_tint() -> void:
	_tint = null
	if selected < 0:
		return
	var verts := PackedVector2Array()
	var index := PackedInt32Array()
	for i in _of_type[selected]:
		if placed[i] != 0:
			continue
		var poly := _polys[i]
		var tris := Geometry2D.triangulate_polygon(poly)
		var base := verts.size()
		verts.append_array(poly)
		for k in tris:
			index.append(base + k)
	if index.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = index
	_tint = ArrayMesh.new()
	_tint.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _follow_view() -> void:
	if board == null:
		return
	_shapes.transform = board.view_transform()
	_labels.queue_redraw()


func _draw_shapes() -> void:
	if _tint != null and selected >= 0:
		_shapes.draw_mesh(_tint, null, Transform2D.IDENTITY, Color(type_colors[selected], TINT_ALPHA))
	for t in _lines.size():
		if t != selected and _lines[t].size() >= 2:
			_shapes.draw_multiline(_lines[t], OUTLINE)
	if selected >= 0 and selected < _lines.size() and _lines[selected].size() >= 2:
		_shapes.draw_multiline(_lines[selected], OUTLINE_SELECTED)


## Numbers for the open slots in view that are big enough to hold one.
func _draw_labels() -> void:
	if board == null or slots.is_empty():
		return
	var k := board.scale_px()
	if _max_minor * k < MIN_LABEL_PX:
		return
	var font := get_theme_default_font()
	var xf := board.view_transform()
	var lo := Vector2i((board.screen_to_board(Vector2.ZERO) / _cell).floor()) - Vector2i.ONE
	var hi := Vector2i((board.screen_to_board(size) / _cell).floor()) + Vector2i.ONE
	for gy in range(lo.y, hi.y + 1):
		for gx in range(lo.x, hi.x + 1):
			for i: int in _by_center.get(Vector2i(gx, gy), []):
				if placed[i] != 0:
					continue
				var s: Dictionary = slots[i]
				var across := minf(s["size"], s["width"]) * k
				if across < MIN_LABEL_PX:
					continue
				var font_size := mini(int(across * 0.5), MAX_FONT)
				var text := str(type_of[i] + 1)
				var at := xf * Vector2(s["x"], s["y"])
				var color := NUMBER_SELECTED if type_of[i] == selected else NUMBER
				var line := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
				var baseline := at + Vector2(-line.x / 2.0, (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0)
				_labels.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

class_name DragScroll
extends Node
## Makes a ScrollContainer scroll with a finger wherever the drag starts,
## buttons and cards included (on their own they catch the touch, so the
## list barely moves), and fling on letting go. A touch that turns into a
## scroll cancels the button it started on, so scrolling never presses
## anything; a touch that doesn't move is left alone as a tap.
##
##   DragScroll.attach(scroll_container)

## How far a finger moves before a touch scrolls, and how fast a fling
## slows (per second).
const DEADZONE := 20.0
const FLING_DECAY := 4.0

var scroll: ScrollContainer
var horizontal := false

var _touch := -1
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _last_ms := 0
var _moved := false
var _at := 0.0
var _fling := 0.0


## Adds a DragScroll to `container` (vertical, or `horizontal`).
static func attach(container: ScrollContainer, along_x := false) -> DragScroll:
	var d := DragScroll.new()
	d.scroll = container
	d.horizontal = along_x
	container.add_child(d)
	return d


func _input(event: InputEvent) -> void:
	if scroll == null or not scroll.is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch < 0 and _inside(event.position):
			_touch = event.index
			_start = event.position
			_last = event.position
			_last_ms = Time.get_ticks_msec()
			_moved = false
			_fling = 0.0
			_at = _position()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			if not _moved:
				_fling = 0.0
	elif event is InputEventScreenDrag and event.index == _touch:
		var along := _along(event.position - _start)
		if not _moved and absf(along) > DEADZONE:
			_moved = true
			_cancel_presses(_start)
		if _moved:
			var step := _along(event.position - _last) / _scale()
			_at -= step
			_apply()
			var now := Time.get_ticks_msec()
			var dt := maxf((now - _last_ms) / 1000.0, 0.004)
			_fling = lerpf(_fling, -step / dt, 0.5)
			_last_ms = now
		_last = event.position


func _process(delta: float) -> void:
	if _touch >= 0 or absf(_fling) < 10.0:
		return
	_at += _fling * delta
	_fling *= exp(-delta * FLING_DECAY)
	if not _apply():
		_fling = 0.0


## Scrolls to _at (clamped); false if it hit an end.
func _apply() -> bool:
	var bar: ScrollBar = scroll.get_h_scroll_bar() if horizontal else scroll.get_v_scroll_bar()
	var most := maxf(0.0, bar.max_value - bar.page)
	var clamped := clampf(_at, 0.0, most)
	var free := clamped == _at
	_at = clamped
	if horizontal:
		scroll.scroll_horizontal = int(_at)
	else:
		scroll.scroll_vertical = int(_at)
	return free


func _position() -> float:
	return float(scroll.scroll_horizontal if horizontal else scroll.scroll_vertical)


func _along(v: Vector2) -> float:
	return v.x if horizontal else v.y


func _inside(screen_at: Vector2) -> bool:
	var p := scroll.get_global_transform_with_canvas().affine_inverse() * screen_at
	return Rect2(Vector2.ZERO, scroll.size).has_point(p)


func _scale() -> float:
	return scroll.get_global_transform_with_canvas().get_scale().y


## Lets go of any button being held under the finger, without pressing it:
## disabling a button drops the press in progress.
func _cancel_presses(screen_at: Vector2) -> void:
	for b: BaseButton in scroll.find_children("*", "BaseButton", true, false):
		if b.is_visible_in_tree() and not b.disabled and b.get_global_rect().has_point(screen_at):
			b.disabled = true
			b.disabled = false

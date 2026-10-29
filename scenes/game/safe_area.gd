class_name SafeArea
extends RefCounted
## Keeps a screen's layout clear of notches and rounded corners.


static func apply(root: Control) -> void:
	var safe := DisplayServer.get_display_safe_area()
	var window := Vector2(DisplayServer.window_get_size())
	if safe.size.x <= 0 or window.x <= 0.0:
		return
	var px := root.get_viewport_rect().size / window
	var top := safe.position.y * px.y
	var bottom := (window.y - safe.end.y) * px.y
	root.offset_top = maxf(root.offset_top, top)
	root.offset_bottom = minf(root.offset_bottom, -bottom)

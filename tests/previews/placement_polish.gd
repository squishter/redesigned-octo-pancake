extends GemFlights
## Render-only study. Inherits production trajectories, durations and landing.
## Nothing in scenes/game loads this script.

var treatment := "soft"
var _impacts: Array[Dictionary] = []


func _process(delta: float) -> void:
	for impact in _impacts:
		impact["age"] += delta
	_impacts = _impacts.filter(func(i: Dictionary) -> bool: return i["age"] < 0.4)
	super._process(delta)
	queue_redraw()


func _particles(color: Color, amount: int, life: float, is_burst: bool) -> CPUParticles2D:
	# Keep the same sparkle trail, with fewer dots behind a defined light ribbon.
	return super._particles(color, mini(amount, 12), life, is_burst)


func burst(at: Vector2, length: float, color: Color, big := false) -> void:
	_impacts.append({"at": at, "length": length, "color": color, "big": big, "age": 0.0})
	queue_redraw()


func _draw_fx(fx: Node2D, f: Dictionary) -> void:
	var u: float = f.get("u", 0.0)
	var to: Vector2 = f.get("to", Vector2.ZERO)
	var color: Color = f["color"]
	var slot_px: float = f["slot_length"] * board.scale_px()
	match f["style"]:
		"beam":
			_beam(fx, to, u, slot_px, color)
		"halo":
			var e := u * u * (3.0 - 2.0 * u)
			var r := lerpf(maxf(HALO_START, slot_px * 4.0), slot_px * 0.55, e)
			var a := (0.65 + 0.35 * sin(PI * u)) * (1.0 - smoothstep(0.84, 1.0, u))
			fx.draw_arc(to, r, 0.0, TAU, 96, Color(color, a * 0.14), 13.0, true)
			fx.draw_arc(to, r, 0.0, TAU, 96, Color(color, a * 0.8), 3.5, true)
			fx.draw_arc(to, r - 2.0, 0.0, TAU, 96, Color(color.lightened(0.7), a), 1.5, true)
			fx.draw_arc(to, r * 0.86, 0.0, TAU, 96, Color(color, a * 0.3), 1.0, true)
			for i in 4:
				var angle := i * TAU / 4.0 + u * 0.55
				_glint(fx, to + Vector2.from_angle(angle) * r, 5.0 * a, Color(color.lightened(0.6), a))
		"firework":
			var p: Vector2 = f.get("spark", f["from"])
			var behind: Vector2 = (f["from"] as Vector2).lerp(to, 1.0 - pow(1.0 - maxf(0.0, u - 0.12), 2.0))
			fx.draw_line(behind, p, Color(color, 0.18), 13.0, true)
			fx.draw_line(behind, p, Color(color.lightened(0.3), 0.65), 4.0, true)
			fx.draw_line(behind, p, Color.WHITE, 1.2, true)
			fx.draw_texture_rect(_sparkle, Rect2(p - Vector2(17, 17), Vector2(34, 34)), false,
				Color(color.lightened(0.5), 0.8))
			_glint(fx, p, 7.0, Color.WHITE)
		_:
			super._draw_fx(fx, f)


func _beam(fx: Node2D, to: Vector2, u: float, slot_px: float, color: Color) -> void:
	var energy := smoothstep(0.0, 0.1, u) * (1.0 - smoothstep(0.52, 1.0, u))
	var head := to.y * smoothstep(0.0, 0.3, u)
	var width := maxf(30.0, slot_px * 1.08)
	var prism := treatment == "prism"
	# Nested translucent tapers feather the shaft without a hard rectangle edge.
	for i in range(18, 0, -1):
		var fraction := float(i) / 18.0
		var top_w := width * fraction * (0.9 if prism else 0.65)
		var end_w := top_w * 0.42
		var points := PackedVector2Array([Vector2(to.x - top_w, 0), Vector2(to.x + top_w, 0),
			Vector2(to.x + end_w, head), Vector2(to.x - end_w, head)])
		var top_color := Color(color, energy * 0.025)
		var end_color := Color(color.lightened(0.2), energy * 0.055)
		fx.draw_polygon(points, PackedColorArray([top_color, top_color, end_color, end_color]))
	var center := Vector2(to.x, head)
	fx.draw_line(Vector2(to.x, 0), center, Color(color.lightened(0.5), energy * 0.7), 5.0, true)
	fx.draw_line(Vector2(to.x, 0), center, Color.WHITE * Color(1, 1, 1, energy * 0.85), 1.6, true)
	if prism:
		for side in [-1.0, 1.0]:
			var points := PackedVector2Array([Vector2(to.x + side * width * 0.45, 0),
				Vector2(to.x + side * width * 0.18, head * 0.64), center])
			fx.draw_polyline(points, Color(color.lightened(0.55), energy * 0.8), 1.5, true)
	# Sparse fragments travel DOWN the column, reinforcing its direction.
	for i in (7 if prism else 3):
		var travel := fposmod(u * 2.1 + i * 0.173, 1.0)
		var y := travel * to.y
		if y > head:
			continue
		var x := to.x + sin(i * 2.4) * width * (0.3 if prism else 0.12)
		var a := energy * sin(PI * travel)
		fx.draw_line(Vector2(x, y - 10), Vector2(x, y + 7), Color(color.lightened(0.6), a), 1.5, true)
		if prism:
			_glint(fx, Vector2(x, y), 3.0 * a, Color.WHITE * Color(1, 1, 1, a))
	var contact := smoothstep(0.25, 0.4, u) * energy
	if contact > 0.0:
		var radius := width * (0.57 if prism else 0.48)
		for i in range(8, 0, -1):
			_ellipse(fx, to, Vector2(radius * i / 8.0, radius * i / 21.0), Color(color, 0.025 * contact))
		# A short horizontal flare reads as light meeting the paper; a large
		# diamond here would look like an arrow pointing at the slot.
		var flare := radius * 0.9 * contact
		fx.draw_line(to - Vector2(flare, 0), to + Vector2(flare, 0),
			Color(color.lightened(0.3), contact * 0.65), 2.5, true)
		fx.draw_line(to - Vector2(flare * 0.7, 0), to + Vector2(flare * 0.7, 0),
			Color(1, 1, 1, contact * 0.9), 1.0, true)


func _draw() -> void:
	for f in _flights:
		if not f["style"] in ["comet", "fly", "drop", "bounce"]:
			continue
		var sprite: Sprite2D = f["sprite"]
		var u: float = clampf(f["time"] / f["length"], 0.0, 1.0)
		var color: Color = f["color"]
		if f["style"] == "comet":
			var to := _screen_at(f["at"])
			for i in range(12, 0, -1):
				var earlier := maxf(0.0, u - i * 0.017)
				var near := maxf(0.0, u - (i - 1) * 0.017)
				var a := pow(1.0 - i / 13.0, 1.2)
				var p: Vector2 = (f["from"] as Vector2).lerp(to, earlier * earlier)
				var q: Vector2 = (f["from"] as Vector2).lerp(to, near * near)
				draw_line(p, q, Color(color, a * 0.15), 14.0 * a, true)
				draw_line(p, q, Color(color.lightened(0.4), a * 0.8), 4.0 * a, true)
				draw_line(p, q, Color(1, 1, 1, a), 1.2 * a, true)
		else:
			_glint(self, sprite.position + Vector2(-5, -5), 3.0 * sin(PI * u), Color(color.lightened(0.6), 0.7))
	for impact in _impacts:
		_draw_impact(impact)


func _draw_impact(impact: Dictionary) -> void:
	var u: float = impact["age"] / 0.4
	var to := _screen_at(impact["at"])
	var color: Color = impact["color"]
	var large: bool = impact["big"]
	var px := maxf(12.0, float(impact["length"]) * board.scale_px())
	var count := 14 if large else 6
	var reach := maxf(78.0, px * 1.8) if large else clampf(px * 0.8, 15, 40)
	var alpha := pow(1.0 - u, 1.4)
	for i in count:
		var angle := i * TAU / count + 0.3
		var ray := Vector2.from_angle(angle)
		var distance := lerpf(px * 0.3, reach * (0.65 + 0.35 * sin(i * 1.7)), 1.0 - pow(1.0 - u, 2.0))
		var p := to + ray * distance + Vector2(0, 15 * u * u)
		if large:
			draw_line(p - ray * 12.0 * alpha, p, Color(color, alpha * 0.45), 2.0, true)
		_glint(self, p, (6.0 if large else 4.0) * alpha, Color(color.lightened(0.3), alpha))
	if u < 0.32:
		_glint(self, to, px * 0.45 * (1.0 - u / 0.32), Color(color.lightened(0.65), 1.0 - u / 0.32))


func _glint(canvas: CanvasItem, at: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.1:
		return
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-radius, 0), at + Vector2(0, -radius * 1.6),
		at + Vector2(radius, 0), at + Vector2(0, radius * 1.6)]), color)


func _ellipse(canvas: CanvasItem, at: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 40:
		points.append(at + Vector2.from_angle(i * TAU / 40.0) * radius)
	canvas.draw_colored_polygon(points, color)

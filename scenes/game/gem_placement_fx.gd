extends RefCounted
## Visuals only. GemFlights owns movement, timing and the one landing event.

const BEAM_SHADER := preload("res://render/placement_beam.gdshader")
const BEAM_WIDTH := 30.0
const HALO_START := 130.0
const IMPACT_TIME := 0.4
static var _pool: GradientTexture2D


static func prepare() -> void:
	if _pool != null:
		return
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	_pool = GradientTexture2D.new()
	_pool.width = 64
	_pool.height = 64
	_pool.gradient = gradient
	_pool.fill = GradientTexture2D.FILL_RADIAL
	_pool.fill_from = Vector2(0.5, 0.5)
	_pool.fill_to = Vector2(1.0, 0.5)


static func make_beam(color: Color) -> ColorRect:
	var shaft := ColorRect.new()
	shaft.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shaft.show_behind_parent = true
	var material := ShaderMaterial.new()
	material.shader = BEAM_SHADER
	material.set_shader_parameter("beam_color", color)
	shaft.material = material
	return shaft


static func update_beam(shaft: ColorRect, to: Vector2, u: float, slot_px: float) -> void:
	var width := maxf(BEAM_WIDTH, slot_px * 1.08)
	var head := to.y * smoothstep(0.0, 0.3, u)
	shaft.visible = head > 0.0
	shaft.position = Vector2(to.x - width * 0.65, 0)
	shaft.size = Vector2(width * 1.3, maxf(1.0, head))
	(shaft.material as ShaderMaterial).set_shader_parameter("energy", _beam_energy(u))


static func draw_fx(canvas: CanvasItem, f: Dictionary, board_scale: float, sparkle: Texture2D) -> void:
	var u: float = f.get("u", 0.0)
	var to: Vector2 = f.get("to", Vector2.ZERO)
	var color: Color = f["color"]
	var slot_px: float = f["slot_length"] * board_scale
	match f["style"]:
		"beam":
			_draw_beam(canvas, to, u, slot_px, color)
		"halo":
			_draw_halo(canvas, to, u, slot_px, color)
		"firework":
			var p: Vector2 = f.get("spark", f["from"])
			var behind: Vector2 = (f["from"] as Vector2).lerp(to, 1.0 - pow(1.0 - maxf(0.0, u - 0.12), 2.0))
			canvas.draw_line(behind, p, Color(color, 0.18), 13.0, true)
			canvas.draw_line(behind, p, Color(color.lightened(0.3), 0.65), 4.0, true)
			canvas.draw_line(behind, p, Color.WHITE, 1.2, true)
			canvas.draw_texture_rect(sparkle, Rect2(p - Vector2(17, 17), Vector2(34, 34)), false,
				Color(color.lightened(0.5), 0.8))
			_glint(canvas, p, 7.0, Color.WHITE)


static func _beam_energy(u: float) -> float:
	return smoothstep(0.0, 0.1, u) * (1.0 - smoothstep(0.52, 1.0, u))


static func _draw_beam(canvas: CanvasItem, to: Vector2, u: float, slot_px: float, color: Color) -> void:
	var energy := _beam_energy(u)
	var head := to.y * smoothstep(0.0, 0.3, u)
	var width := maxf(BEAM_WIDTH, slot_px * 1.08)
	var center := Vector2(to.x, head)
	canvas.draw_line(Vector2(to.x, 0), center, Color(color.lightened(0.5), energy * 0.7), 5.0, true)
	canvas.draw_line(Vector2(to.x, 0), center, Color(1, 1, 1, energy * 0.85), 1.6, true)
	for i in 3:
		var travel := fposmod(u * 2.1 + i * 0.173, 1.0)
		var y := travel * to.y
		if y > head:
			continue
		var x := to.x + sin(i * 2.4) * width * 0.12
		canvas.draw_line(Vector2(x, y - 10), Vector2(x, y + 7),
			Color(color.lightened(0.6), energy * sin(PI * travel)), 1.5, true)
	var contact := smoothstep(0.25, 0.4, u) * energy
	if contact <= 0.0:
		return
	var radius := width * 0.48
	var extent := Vector2(radius, radius * 8.0 / 21.0)
	canvas.draw_texture_rect(_pool, Rect2(to - extent, extent * 2.0), false, Color(color, 0.2 * contact))
	var flare := radius * 0.9 * contact
	canvas.draw_line(to - Vector2(flare, 0), to + Vector2(flare, 0),
		Color(color.lightened(0.3), contact * 0.65), 2.5, true)
	canvas.draw_line(to - Vector2(flare * 0.7, 0), to + Vector2(flare * 0.7, 0),
		Color(1, 1, 1, contact * 0.9), 1.0, true)


static func _draw_halo(canvas: CanvasItem, to: Vector2, u: float, slot_px: float, color: Color) -> void:
	var e := u * u * (3.0 - 2.0 * u)
	var radius := lerpf(maxf(HALO_START, slot_px * 4.0), slot_px * 0.55, e)
	var alpha := (0.65 + 0.35 * sin(PI * u)) * (1.0 - smoothstep(0.84, 1.0, u))
	# About one segment per 4 px of rim: a closing ring needs fewer as it shrinks.
	var segments := clampi(ceili(radius * TAU / 4.0), 16, 96)
	canvas.draw_arc(to, radius, 0, TAU, segments, Color(color, alpha * 0.14), 13.0, true)
	canvas.draw_arc(to, radius, 0, TAU, segments, Color(color, alpha * 0.8), 3.5, true)
	canvas.draw_arc(to, maxf(radius - 2.0, 0.25), 0, TAU, segments, Color(color.lightened(0.7), alpha), 1.5, true)
	canvas.draw_arc(to, radius * 0.86, 0, TAU, segments, Color(color, alpha * 0.3), 1.0, true)
	for i in 4:
		var angle := i * TAU / 4.0 + u * 0.55
		_glint(canvas, to + Vector2.from_angle(angle) * radius, 5.0 * alpha, Color(color.lightened(0.6), alpha))


static func draw_flights(canvas: CanvasItem, flights: Array[Dictionary]) -> void:
	for f in flights:
		if not f["style"] in ["comet", "fly", "drop", "bounce"]:
			continue
		var sprite: Sprite2D = f["sprite"]
		var u := clampf(float(f["time"]) / float(f["length"]), 0.0, 1.0)
		var color: Color = f["color"]
		if f["style"] == "comet":
			var earlier := maxf(0.0, u - 0.204)
			var start: Vector2 = (f["from"] as Vector2).lerp(f["to"], earlier * earlier)
			_ribbon(canvas, start, sprite.position, 14.0, Color(color, 0.15))
			_ribbon(canvas, start, sprite.position, 4.0, Color(color.lightened(0.4), 0.8))
			_ribbon(canvas, start, sprite.position, 1.2, Color.WHITE)
		else:
			_glint(canvas, sprite.position + Vector2(-5, -5), 3.0 * sin(PI * u), Color(color.lightened(0.6), 0.7))


static func _ribbon(canvas: CanvasItem, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	if from.distance_squared_to(to) < 0.01:
		return
	var side := (to - from).normalized().orthogonal() * width * 0.5
	canvas.draw_polygon(PackedVector2Array([from, to - side, to + side]),
		PackedColorArray([Color(color, 0), color, color]))


## A landing glint; `sparse` (many on screen at once) draws fewer sparks.
static func draw_impact(canvas: CanvasItem, impact: Dictionary, to: Vector2, slot_px: float, sparse := false) -> void:
	var u: float = clampf(impact["age"] / IMPACT_TIME, 0, 1)
	var color: Color = impact["color"]
	var large: bool = impact["big"]
	var px := maxf(12.0, slot_px)
	var count := (7 if large else 3) if sparse else (14 if large else 6)
	var reach := maxf(78.0, px * 1.8) if large else clampf(px * 0.8, 15, 40)
	var alpha := pow(1.0 - u, 1.4)
	for i in count:
		var ray := Vector2.from_angle(i * TAU / count + 0.3)
		var distance := lerpf(px * 0.3, reach * (0.65 + 0.35 * sin(i * 1.7)), 1.0 - pow(1.0 - u, 2.0))
		var point := to + ray * distance + Vector2(0, 15 * u * u)
		if large:
			canvas.draw_line(point - ray * 12.0 * alpha, point, Color(color, alpha * 0.45), 2.0, true)
		_glint(canvas, point, (6.0 if large else 4.0) * alpha, Color(color.lightened(0.3), alpha))
	if u < 0.32:
		_glint(canvas, to, px * 0.45 * (1.0 - u / 0.32), Color(color.lightened(0.65), 1.0 - u / 0.32))


## Below half a px a glint can't be seen, and its tiny diamond fails to
## triangulate.
static func _glint(canvas: CanvasItem, at: Vector2, radius: float, color: Color) -> void:
	if radius < 0.5:
		return
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-radius, 0), at + Vector2(0, -radius * 1.6),
		at + Vector2(radius, 0), at + Vector2(0, radius * 1.6)]), color)

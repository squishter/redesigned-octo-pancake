class_name GemFlights
extends Control
## Gems moving into their slots, in a style (see GemCatalog.ANIMATIONS):
## "fly": a copy of the row's rendered gem swoops from its card along a
##   curve, growing or shrinking to the slot's size on screen and turning
##   to its angle, with a short trail of sparkles;
## "drop": it falls in from above the slot, speeding up, with a trail;
## "spin": it twirls in on the slot as it grows;
## and ones made to be seen even zoomed far out, drawn at screen size:
## "bounce": it leaps from its card in a high arc;
## "comet": it streaks in from off screen with a long sparkle tail;
## "firework": a spark rises from the bottom of the screen and bursts over
##   the slot, leaving the gem;
## "beam": a column of light shines down onto the slot and the gem appears;
## "halo": a ring of light closes in on the slot from a screen-sized circle.
## Each lands with a tiny burst (burst() makes one on its own, for gems that
## twinkle in). The slot follows the board while the gem moves, so panning
## mid-flight still lands it right.

## Called with the slot when a gem arrives.
signal landed(slot: int)

## Flight time: a base plus a little per px travelled, at most MAX_TIME.
const BASE_TIME := 0.2
const PER_PX := 1.0 / 6000.0
const MAX_TIME := 0.42
const DROP_TIME := 0.3
const SPIN_TIME := 0.34
## How far above its slot a dropped gem starts: this many slot lengths, at
## least DROP_MIN px.
const DROP_HEIGHT := 6.0
const DROP_MIN := 260.0
const BOUNCE_TIME := 0.48
const COMET_TIME := 0.42
const FIREWORK_TIME := 0.5
const BEAM_TIME := 0.42
const HALO_TIME := 0.4
## Screen-sized effects never get smaller than these (px): a halo's ring at
## its start, a beam's width, how high a bounce goes.
const HALO_START := 130.0
const BEAM_WIDTH := 44.0
const BOUNCE_HEIGHT := 240.0
## Styles that bring the gem from elsewhere on screen, rather than growing it
## in place, start from a sprite of it; the rest show it only at the end.
const SHOWN_AT_END := ["firework", "beam", "halo"]
## How far the path bows out sideways, as a share of its length, and how
## much the gem swells mid-flight.
const BOW := 0.22
const LIFT := 0.25
## More flights than this at once and the rest land straight away.
const MAX_FLYING := 48
const SPARKLE_PX := 32
## A spinning gem overshoots its size a little as it settles.
const OVERSHOOT := 1.70158

var board: GemBoard3D

## Each flight: {slot, style, sprite, trail, from, at (board units), time,
## length (its duration), bow, rot_to, size_from, stone_share, slot_length,
## color}.
var _flights: Array[Dictionary] = []
static var _sparkle: ImageTexture
static var _masks := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _sparkle == null:
		_sparkle = _make_sparkle(SPARKLE_PX)


func flying() -> int:
	return _flights.size()


## Sends a gem in `style` ("fly", "drop" or "spin") to slot `slot` at board
## point `at`; a flying one starts at `from` (this control's px), `icon_size`
## across. `icon` is the gem's rendered picture, `stone_share` how much of
## the icon the stone spans; `length` the slot's length (board units) and
## `slot_rotation` its angle, `icon_rotation` the icon stone's. Returns false
## (sending nothing) when too many are on their way.
func send(style: String, slot: int, icon: Texture2D, stone_share: float, from: Vector2, icon_size: float,
		at: Vector2, length: float, slot_rotation: float, icon_rotation: float, color: Color) -> bool:
	if _flights.size() >= MAX_FLYING:
		return false
	var to := _screen_at(at)
	var px := float(icon.get_width())
	var duration := minf(BASE_TIME + from.distance_to(to) * PER_PX, MAX_TIME)
	var size_from := icon_size / px
	var start := from
	match style:
		"drop":
			duration = DROP_TIME
			size_from = -1.0  # the slot's own size all the way
		"spin":
			duration = SPIN_TIME
			size_from = 0.0
		"bounce":
			duration = BOUNCE_TIME
		"comet":
			duration = COMET_TIME
			# From off screen, somewhere across the top.
			var view := get_viewport_rect().size
			start = Vector2(randf_range(-0.2, 1.2) * view.x, -0.15 * view.y)
		"firework":
			duration = FIREWORK_TIME
			start = Vector2(to.x, size.y + 40.0)
		"beam":
			duration = BEAM_TIME
		"halo":
			duration = HALO_TIME
	var sprite := Sprite2D.new()
	sprite.texture = icon
	sprite.material = _round_mask(px)
	sprite.position = start if style in ["fly", "bounce", "comet"] else to
	sprite.scale = Vector2.ONE * maxf(size_from, 0.0)
	sprite.visible = not style in SHOWN_AT_END
	add_child(sprite)
	var trail: CPUParticles2D = null
	match style:
		"spin", "beam", "halo":
			pass
		"comet", "firework":
			trail = _particles(color, 40, 0.5, false)
			trail.scale_amount_min = 0.6
			trail.scale_amount_max = 1.4
		_:
			trail = _particles(color, 16, 0.25, false)
	if trail != null:
		trail.position = sprite.position
		add_child(trail)
	var f := {
		"slot": slot, "style": style, "sprite": sprite, "trail": trail, "from": start, "at": at, "time": 0.0,
		"length": duration, "bow": (1.0 if randf() < 0.5 else -1.0) * BOW,
		"rot_to": wrapf(slot_rotation - icon_rotation, -PI, PI), "size_from": size_from,
		"stone_share": stone_share, "slot_length": length, "color": color, "fx": null,
	}
	if style in ["firework", "beam", "halo"]:
		var fx := Node2D.new()
		add_child(fx)
		fx.draw.connect(func() -> void: _draw_fx(fx, f))
		f["fx"] = fx
	_flights.append(f)
	_process(0.0)
	return true


## A burst of tiny sparkles at slot board point `at`, for a stone `length`
## board units long, in `color`; `big` for a firework's, screen-sized.
func burst(at: Vector2, length: float, color: Color, big := false) -> void:
	var slot_px := length * board.scale_px()
	var b := _particles(color, 28 if big else 12, 0.6 if big else 0.4, true)
	b.position = _screen_at(at)
	b.initial_velocity_min = 160.0 if big else clampf(slot_px * 1.5, 30.0, 90.0)
	b.initial_velocity_max = 460.0 if big else clampf(slot_px * 4.0, 70.0, 220.0)
	if big:
		b.scale_amount_min = 0.6
		b.scale_amount_max = 1.3
	add_child(b)
	b.emitting = true
	_free_later(b, 0.5)


func _process(delta: float) -> void:
	var done := []
	for f in _flights:
		f["time"] += delta
		var u := clampf(f["time"] / f["length"], 0.0, 1.0)
		var to := _screen_at(f["at"])
		var sprite: Sprite2D = f["sprite"]
		# The sprite's whole cell, sized so the stone in it matches the slot on screen.
		var size_to: float = f["slot_length"] * board.scale_px() / f["stone_share"] / sprite.texture.get_width()
		var turn: float = f["rot_to"]
		var p := to
		match f["style"]:
			"drop":
				var high := maxf(DROP_MIN, f["slot_length"] * board.scale_px() * DROP_HEIGHT)
				p = to - Vector2(0.0, high * (1.0 - u * u))
				sprite.rotation = turn
				sprite.scale = Vector2.ONE * size_to
			"spin":
				var grow := 1.0 + (OVERSHOOT + 1.0) * pow(u - 1.0, 3.0) + OVERSHOOT * pow(u - 1.0, 2.0)
				sprite.rotation = turn - TAU * (1.0 - u) * (1.0 - u)
				sprite.scale = Vector2.ONE * size_to * maxf(grow, 0.0)
			"bounce":
				var from: Vector2 = f["from"]
				var high := maxf(BOUNCE_HEIGHT, from.distance_to(to) * 0.45)
				p = from.lerp(to, u) - Vector2(0.0, high * 4.0 * u * (1.0 - u))
				sprite.rotation = turn * u
				sprite.scale = Vector2.ONE * lerpf(f["size_from"], size_to, u)
			"comet":
				var e := u * u
				p = (f["from"] as Vector2).lerp(to, e)
				sprite.rotation = turn
				sprite.scale = Vector2.ONE * size_to * (1.0 + 0.8 * (1.0 - u))
			"firework":
				# A spark rising, slowing as it nears the slot (drawn in _draw_fx).
				var e := 1.0 - (1.0 - u) * (1.0 - u)
				p = (f["from"] as Vector2).lerp(to, e)
				f["spark"] = p
			"beam", "halo":
				sprite.rotation = turn
				sprite.scale = Vector2.ONE * size_to
			_:
				var e := u * u * (3.0 - 2.0 * u)
				var from: Vector2 = f["from"]
				var mid := (from + to) / 2.0 + (to - from).orthogonal() * float(f["bow"])
				p = from.lerp(mid, e).lerp(mid.lerp(to, e), e)
				sprite.rotation = turn * e
				sprite.scale = Vector2.ONE * lerpf(f["size_from"], size_to, e) * (1.0 + LIFT * sin(PI * u))
		sprite.position = p
		if f["trail"] != null:
			(f["trail"] as CPUParticles2D).position = p
		if f["fx"] != null:
			f["u"] = u
			f["to"] = to
			(f["fx"] as Node2D).queue_redraw()
		if u >= 1.0:
			done.append(f)
	for f in done:
		_flights.erase(f)
		_land(f)


func _land(f: Dictionary) -> void:
	(f["sprite"] as Node).queue_free()
	if f["fx"] != null:
		(f["fx"] as Node).queue_free()
	if f["trail"] != null:
		var trail: CPUParticles2D = f["trail"]
		trail.emitting = false
		_free_later(trail, 0.6)
	burst(f["at"], f["slot_length"], f["color"], f["style"] == "firework")
	landed.emit(f["slot"])


## The screen-sized parts of a firework, beam or halo, as they stand at
## the flight's `u` (0..1).
func _draw_fx(fx: Node2D, f: Dictionary) -> void:
	var u: float = f.get("u", 0.0)
	var to: Vector2 = f.get("to", Vector2.ZERO)
	var color: Color = f["color"]
	var glow := color.lightened(0.55)
	var slot_px: float = f["slot_length"] * board.scale_px()
	match f["style"]:
		"firework":
			var p: Vector2 = f.get("spark", f["from"])
			fx.draw_texture_rect(_sparkle, Rect2(p - Vector2(28, 28), Vector2(56, 56)), false, glow)
			fx.draw_circle(p, 6.0, Color(1, 1, 1, 0.95))
		"beam":
			var a := sin(PI * u)
			var w := maxf(BEAM_WIDTH, slot_px * 1.3) * (0.6 + 0.4 * a)
			var top := Vector2(to.x, 0.0)
			fx.draw_rect(Rect2(top.x - w / 2.0, 0.0, w, to.y), Color(glow, 0.45 * a))
			fx.draw_rect(Rect2(top.x - w / 4.0, 0.0, w / 2.0, to.y), Color(color.lightened(0.3), 0.5 * a))
			fx.draw_rect(Rect2(top.x - w / 10.0, 0.0, w / 5.0, to.y), Color(1, 1, 1, 0.85 * a))
			fx.draw_circle(to, w * 0.6, Color(glow, 0.5 * a))
		"halo":
			var e := u * u * (3.0 - 2.0 * u)
			var r := lerpf(maxf(HALO_START, slot_px * 4.0), slot_px * 0.55, e)
			var a := 0.35 + 0.65 * sin(PI * minf(u * 1.2, 1.0))
			fx.draw_arc(to, r, 0.0, TAU, 64, Color(glow, a), 9.0, true)
			fx.draw_arc(to, r * 0.8, 0.0, TAU, 64, Color(color, a * 0.7), 4.0, true)


## Lands everything still flying (leaving the screen, or finishing).
func land_all() -> void:
	var all := _flights.duplicate()
	_flights.clear()
	for f in all:
		_land(f)


func _screen_at(board_at: Vector2) -> Vector2:
	var on_board := board.get_global_transform_with_canvas() * (board.view_transform() * board_at)
	return get_global_transform_with_canvas().affine_inverse() * on_board


## Tiny sparkles in the gem's color (strong enough to read on the pale
## paper), lightening as they fade out: a burst all at once, or a trail that
## keeps emitting where it's moved.
func _particles(color: Color, amount: int, life: float, burst: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _sparkle
	p.amount = amount
	p.lifetime = life
	p.one_shot = burst
	p.explosiveness = 1.0 if burst else 0.0
	p.local_coords = false
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 40.0
	p.damping_min = 60.0
	p.damping_max = 120.0
	p.scale_amount_min = 0.45 if burst else 0.35
	p.scale_amount_max = 0.95 if burst else 0.8
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = shrink
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.lightened(0.15), 1.0))
	ramp.add_point(0.45, Color(color.lightened(0.45), 0.85))
	ramp.set_color(ramp.get_point_count() - 1, Color(color.lightened(0.8), 0.0))
	p.color_ramp = ramp
	p.emitting = not burst
	return p


func _free_later(node: Node, seconds: float) -> void:
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(node):
			node.queue_free())


## Shows only the round middle of a moving gem's icon cell (`px` across), so
## whatever is near the cell's edges never turns with it.
static func _round_mask(px: float) -> ShaderMaterial:
	if not _masks.has(px):
		var shader := Shader.new()
		shader.code = """shader_type canvas_item;
uniform float half_px = 75.0;
varying vec2 local;
void vertex() {
	local = VERTEX / half_px;
}
void fragment() {
	COLOR.a *= 1.0 - smoothstep(0.9, 0.98, length(local));
}
"""
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("half_px", px / 2.0)
		_masks[px] = m
	return _masks[px]


## A soft dot with a four-point glint, white, for the sparkles.
static func _make_sparkle(px: int) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := px / 2.0
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - c, y + 0.5 - c) / c
			var glow := pow(clampf(1.0 - d.length(), 0.0, 1.0), 2.0)
			var star := pow(clampf(1.0 - absf(d.x * d.y) * 18.0 - d.length() * 0.6, 0.0, 1.0), 2.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(glow + star, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

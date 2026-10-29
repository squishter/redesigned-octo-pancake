class_name GemFlights
extends Control
## Gems flying from the gem row into their slots: a copy of the row's
## rendered gem swoops along a curve, growing or shrinking to the slot's
## size on screen and turning to its angle, with a short trail of sparkles,
## then lands with a tiny burst. The slot follows the board while it flies,
## so panning mid-flight still lands it right.

## Called with the slot when a gem arrives.
signal landed(slot: int)

## Flight time: a base plus a little per px travelled, at most MAX_TIME.
const BASE_TIME := 0.2
const PER_PX := 1.0 / 6000.0
const MAX_TIME := 0.42
## How far the path bows out sideways, as a share of its length, and how
## much the gem swells mid-flight.
const BOW := 0.22
const LIFT := 0.25
## More flights than this at once and the rest land straight away.
const MAX_FLYING := 48
const SPARKLE_PX := 32

var board: GemBoard3D

## Each flight: {slot, sprite, trail, from, at (board units), time, length
## (its duration), bow, rot_to, size_from, stone_share, slot_length, color}.
var _flights: Array[Dictionary] = []
static var _sparkle: ImageTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _sparkle == null:
		_sparkle = _make_sparkle(SPARKLE_PX)


func flying() -> int:
	return _flights.size()


## Sends a gem from `from` (this control's px) to slot `slot` at board point
## `at`. `icon` is the gem's rendered picture, `stone_share` how much of the
## icon the stone spans; `length` the slot's length (board units) and
## `slot_rotation` its angle, `icon_rotation` the icon stone's. Returns false
## (sending nothing) when too many are flying.
func send(slot: int, icon: Texture2D, stone_share: float, from: Vector2, icon_size: float, at: Vector2,
		length: float, slot_rotation: float, icon_rotation: float, color: Color) -> bool:
	if _flights.size() >= MAX_FLYING:
		return false
	var sprite := Sprite2D.new()
	sprite.texture = icon
	sprite.position = from
	var px := float(icon.get_width())
	sprite.scale = Vector2.ONE * icon_size / px
	add_child(sprite)
	var trail := _particles(color, 16, 0.25, false)
	trail.position = from
	add_child(trail)
	var to := _screen_at(at)
	var turn := wrapf(slot_rotation - icon_rotation, -PI, PI)
	_flights.append({
		"slot": slot, "sprite": sprite, "trail": trail, "from": from, "at": at, "time": 0.0,
		"length": minf(BASE_TIME + from.distance_to(to) * PER_PX, MAX_TIME),
		"bow": (1.0 if randf() < 0.5 else -1.0) * BOW, "rot_to": turn,
		"size_from": icon_size / px, "stone_share": stone_share, "slot_length": length, "color": color,
	})
	return true


func _process(delta: float) -> void:
	var done := []
	for f in _flights:
		f["time"] += delta
		var u := clampf(f["time"] / f["length"], 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		var from: Vector2 = f["from"]
		var to := _screen_at(f["at"])
		var bend := (to - from).orthogonal() * float(f["bow"])
		var mid := (from + to) / 2.0 + bend
		var p := from.lerp(mid, e).lerp(mid.lerp(to, e), e)
		var sprite: Sprite2D = f["sprite"]
		sprite.position = p
		sprite.rotation = float(f["rot_to"]) * e
		# The sprite's whole cell, sized so the stone in it matches the slot on screen.
		var size_to: float = f["slot_length"] * board.scale_px() / f["stone_share"] / sprite.texture.get_width()
		sprite.scale = Vector2.ONE * lerpf(f["size_from"], size_to, e) * (1.0 + LIFT * sin(PI * u))
		(f["trail"] as CPUParticles2D).position = p
		if u >= 1.0:
			done.append(f)
	for f in done:
		_flights.erase(f)
		_land(f)


func _land(f: Dictionary) -> void:
	var at := _screen_at(f["at"])
	(f["sprite"] as Node).queue_free()
	var trail: CPUParticles2D = f["trail"]
	trail.emitting = false
	_free_later(trail, 0.3)
	var slot_px: float = f["slot_length"] * board.scale_px()
	var burst := _particles(f["color"], 12, 0.4, true)
	burst.position = at
	burst.initial_velocity_min = clampf(slot_px * 1.5, 30.0, 90.0)
	burst.initial_velocity_max = clampf(slot_px * 4.0, 70.0, 220.0)
	add_child(burst)
	burst.emitting = true
	_free_later(burst, 0.5)
	landed.emit(f["slot"])


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

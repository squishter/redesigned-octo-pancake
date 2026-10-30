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
##
## Big brush can send hundreds of gems in a moment. Up to MAX_FLYING fly at
## once; the rest wait in a short queue, and each frame the ones on screen
## where the fewest gems are flying go first, so the flights spread over the
## stroke instead of bunching where it began. A gem that waits too long, or
## whose slot is off screen, lands without flying (with its glint). Sprites
## and beam shafts are reused, and trails and glints are drawn rather than
## simulated, thinning out as more are on screen.

## Called with the slot when a gem arrives.
signal landed(slot: int)

const PlacementFx := preload("res://scenes/game/gem_placement_fx.gd")

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
const HALO_START := PlacementFx.HALO_START
const BEAM_WIDTH := PlacementFx.BEAM_WIDTH
const BOUNCE_HEIGHT := 240.0
## Styles that bring the gem from elsewhere on screen, rather than growing it
## in place, start from a sprite of it; the rest show it only at the end.
const SHOWN_AT_END := ["firework", "beam", "halo"]
## Styles with screen-sized effects drawn over the gems.
const FX_STYLES := ["firework", "beam", "halo"]
## How far the path bows out sideways, as a share of its length, and how
## much the gem swells mid-flight.
const BOW := 0.22
const LIFT := 0.25
## At most this many flights at once; more wait in the queue.
const MAX_FLYING := 160
## Gems waiting for a flight: at most MAX_QUEUED (send() refuses more), each
## for at most MAX_WAIT seconds before it lands without flying.
const MAX_QUEUED := 600
const MAX_WAIT := 0.3
## New flights per second, with a burst of LAUNCH_BURST allowed. A frame's
## first SEND_AT_ONCE gems go straight away (a tap or a drag); a crowd beyond
## them waits for the next frame, to be chosen from (see _launch_queued).
const LAUNCH_RATE := 360.0
const LAUNCH_BURST := 32.0
const SEND_AT_ONCE := 4
## Queued gems are spread out by screen cells this size (px), and off-screen
## ones (beyond this margin, px) don't fly.
const CROWD_CELL := 140.0
const VIEW_MARGIN := 40.0
## Bound lingering glints independently: they never delay a gem's landing.
## Past IMPACT_DETAIL at once, each is drawn with fewer sparks.
const MAX_IMPACTS := 240
const IMPACT_DETAIL := 60
const SPARKLE_PX := 32
## Trail sparkles per flight, and at most this many over all flights.
const TRAIL_SPARKS := 12
const TRAIL_BUDGET := 384
## Beam shafts are full-height quads; past this many the rest show only
## their core.
const MAX_SHAFTS := 32
## A spinning gem overshoots its size a little as it settles.
const OVERSHOOT := 1.70158

static var _sparkle: ImageTexture
static var _masks := {}

var board: GemBoard3D

## Each flight: {slot, style, sprite, from, at (board units), to (px), time,
## length (its duration), bow, rot_to, size_from, stone_share, slot_length,
## color, trail_life (0: none), seed}.
var _flights: Array[Dictionary] = []
## Gems waiting to fly: send()'s arguments and when they were queued.
var _queue: Array[Dictionary] = []
## Landed flights whose trail sparkles are still fading.
var _fading: Array[Dictionary] = []
var _impacts: Array[Dictionary] = []
## Flights that have landed this frame but not yet said so.
var _landing := 0
var _clock := 0.0
var _tokens := LAUNCH_BURST
var _sent_this_frame := 0
## Board units to this control's px, as of the last frame.
var _xf := Transform2D.IDENTITY
## Gem sprites (under) and trails, firework/beam/halo effects (over).
var _gem_layer: Node2D
var _fx_layer: Node2D
var _sprite_pool: Array[Sprite2D] = []
var _shaft_pool: Array[ColorRect] = []
var _shafts := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	PlacementFx.prepare()
	if _sparkle == null:
		_sparkle = _make_sparkle(SPARKLE_PX)
	_gem_layer = Node2D.new()
	add_child(_gem_layer)
	_fx_layer = Node2D.new()
	_fx_layer.draw.connect(_draw_over)
	add_child(_fx_layer)


## Gems still on their way: flying, waiting to fly or landing.
func flying() -> int:
	return _flights.size() + _queue.size() + _landing


## Sends a gem in `style` (see the top) to slot `slot` at board point `at`;
## a flying one starts at `from` (this control's px), `icon_size` across.
## `icon` is the gem's rendered picture, `stone_share` how much of the icon
## the stone spans; `length` the slot's length (board units) and
## `slot_rotation` its angle, `icon_rotation` the icon stone's. It flies now
## or waits its turn; returns false (sending nothing) only when the queue is
## full.
func send(style: String, slot: int, icon: Texture2D, stone_share: float, from: Vector2, icon_size: float,
		at: Vector2, length: float, slot_rotation: float, icon_rotation: float, color: Color) -> bool:
	var order := {"style": style, "slot": slot, "icon": icon, "stone_share": stone_share, "from": from,
		"icon_size": icon_size, "at": at, "length": length, "slot_rotation": slot_rotation,
		"icon_rotation": icon_rotation, "color": color}
	if (_queue.is_empty() and _sent_this_frame < SEND_AT_ONCE and _flights.size() < MAX_FLYING
			and _tokens >= 1.0):
		_xf = _board_xf()
		_launch(order)
		return true
	if _queue.size() >= MAX_QUEUED:
		return false
	order["queued"] = _clock
	_queue.append(order)
	return true


func _launch(o: Dictionary) -> void:
	_tokens -= 1.0
	_sent_this_frame += 1
	var style: String = o["style"]
	var icon: Texture2D = o["icon"]
	var from: Vector2 = o["from"]
	var at: Vector2 = o["at"]
	var to := _xf * at
	var px := float(icon.get_width())
	var duration := minf(BASE_TIME + from.distance_to(to) * PER_PX, MAX_TIME)
	var size_from: float = o["icon_size"] / px
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
	var sprite: Sprite2D = _sprite_pool.pop_back() if not _sprite_pool.is_empty() else null
	if sprite == null:
		sprite = Sprite2D.new()
		_gem_layer.add_child(sprite)
	sprite.texture = icon
	sprite.material = _round_mask(px)
	sprite.position = start if style in ["fly", "bounce", "comet"] else to
	sprite.rotation = 0.0
	sprite.scale = Vector2.ONE * maxf(size_from, 0.0)
	sprite.visible = not style in SHOWN_AT_END
	var trail_life := 0.0
	match style:
		"spin", "beam", "halo":
			pass
		"comet", "firework":
			trail_life = 0.5
		_:
			trail_life = 0.25
	# The trail's seed is drawn before the bow, as its emitter's used to be.
	var trail_seed := randi() if trail_life > 0.0 else 0
	var f := {
		"slot": o["slot"], "style": style, "sprite": sprite, "from": start, "at": at, "to": to, "time": 0.0,
		"length": duration, "bow": (1.0 if randf() < 0.5 else -1.0) * BOW,
		"rot_to": wrapf(o["slot_rotation"] - o["icon_rotation"], -PI, PI), "size_from": size_from,
		"stone_share": o["stone_share"], "slot_length": o["length"], "color": o["color"],
		"trail_life": trail_life, "seed": trail_seed, "u": 0.0,
	}
	if style == "beam" and _shafts < MAX_SHAFTS:
		var shaft: ColorRect = _shaft_pool.pop_back() if not _shaft_pool.is_empty() else null
		if shaft == null:
			shaft = PlacementFx.make_beam(o["color"])
			_fx_layer.add_child(shaft)
		else:
			(shaft.material as ShaderMaterial).set_shader_parameter("beam_color", o["color"])
		shaft.show()
		_shafts += 1
		f["shaft"] = shaft
	_flights.append(f)
	_advance(f, board.scale_px())


## A burst of tiny sparkles at slot board point `at`, for a stone `length`
## board units long, in `color`; `big` for a firework's, screen-sized.
func burst(at: Vector2, length: float, color: Color, big := false) -> void:
	if _impacts.size() >= MAX_IMPACTS:
		_impacts.pop_front()
	_impacts.append({"at": at, "length": length, "color": color, "big": big, "age": 0.0})
	queue_redraw()


func _process(delta: float) -> void:
	var had_effects := not _flights.is_empty() or not _impacts.is_empty() or not _fading.is_empty()
	_clock += delta
	_sent_this_frame = 0
	_tokens = minf(_tokens + delta * LAUNCH_RATE, LAUNCH_BURST)
	_xf = _board_xf()
	var scale_px := board.scale_px()
	if not _impacts.is_empty():
		var kept: Array[Dictionary] = []
		for impact in _impacts:
			impact["age"] += delta
			if impact["age"] < PlacementFx.IMPACT_TIME:
				kept.append(impact)
		_impacts = kept
	if not _fading.is_empty():
		var kept: Array[Dictionary] = []
		for f in _fading:
			f["time"] += delta
			if f["time"] < f["length"] + f["trail_life"]:
				kept.append(f)
		_fading = kept
	var done: Array[Dictionary] = []
	var flying_on: Array[Dictionary] = []
	for f in _flights:
		f["time"] += delta
		_advance(f, scale_px)
		if f["u"] >= 1.0:
			done.append(f)
		else:
			flying_on.append(f)
	if not done.is_empty():
		_flights = flying_on
		_landing += done.size()
		for f in done:
			_landing -= 1
			_land(f)
	_launch_queued()
	if had_effects or not _impacts.is_empty() or not _flights.is_empty() or not _fading.is_empty():
		queue_redraw()
		_fx_layer.queue_redraw()


## Moves flight `f` to where it is at its time.
func _advance(f: Dictionary, scale_px: float) -> void:
	var u := clampf(f["time"] / f["length"], 0.0, 1.0)
	var to := _xf * (f["at"] as Vector2)
	f["to"] = to
	f["u"] = u
	var sprite: Sprite2D = f["sprite"]
	# The sprite's whole cell, sized so the stone in it matches the slot on screen.
	var size_to: float = f["slot_length"] * scale_px / f["stone_share"] / sprite.texture.get_width()
	var turn: float = f["rot_to"]
	var p := _path(f, u, to, scale_px)
	match f["style"]:
		"drop":
			sprite.rotation = turn
			sprite.scale = Vector2.ONE * size_to
		"spin":
			var grow := 1.0 + (OVERSHOOT + 1.0) * pow(u - 1.0, 3.0) + OVERSHOOT * pow(u - 1.0, 2.0)
			sprite.rotation = turn - TAU * (1.0 - u) * (1.0 - u)
			sprite.scale = Vector2.ONE * size_to * maxf(grow, 0.0)
		"bounce":
			sprite.rotation = turn * u
			sprite.scale = Vector2.ONE * lerpf(f["size_from"], size_to, u)
		"comet":
			sprite.rotation = turn
			sprite.scale = Vector2.ONE * size_to * (1.0 + 0.8 * (1.0 - u))
		"firework":
			# A spark rising, slowing as it nears the slot (drawn in _draw_over).
			f["spark"] = p
		"beam", "halo":
			sprite.rotation = turn
			sprite.scale = Vector2.ONE * size_to
		_:
			var e := u * u * (3.0 - 2.0 * u)
			sprite.rotation = turn * e
			sprite.scale = Vector2.ONE * lerpf(f["size_from"], size_to, e) * (1.0 + LIFT * sin(PI * u))
	sprite.position = p
	if f.has("shaft"):
		PlacementFx.update_beam(f["shaft"], to, u, f["slot_length"] * scale_px)


## Where flight `f` is at `u` (0..1), landing at `to` (px).
static func _path(f: Dictionary, u: float, to: Vector2, scale_px: float) -> Vector2:
	var from: Vector2 = f["from"]
	match f["style"]:
		"drop":
			var high := maxf(DROP_MIN, f["slot_length"] * scale_px * DROP_HEIGHT)
			return to - Vector2(0.0, high * (1.0 - u * u))
		"bounce":
			var high := maxf(BOUNCE_HEIGHT, from.distance_to(to) * 0.45)
			return from.lerp(to, u) - Vector2(0.0, high * 4.0 * u * (1.0 - u))
		"comet":
			return from.lerp(to, u * u)
		"firework":
			return from.lerp(to, 1.0 - (1.0 - u) * (1.0 - u))
		"spin", "beam", "halo":
			return to
	var e := u * u * (3.0 - 2.0 * u)
	var mid := (from + to) / 2.0 + (to - from).orthogonal() * float(f["bow"])
	return from.lerp(mid, e).lerp(mid.lerp(to, e), e)


## Starts queued gems while there's room: those waiting too long or off
## screen land straight away, and of the rest, the ones where the fewest gems
## are flying go first (then the longest waiting).
func _launch_queued() -> void:
	if _queue.is_empty():
		return
	var view := Rect2(Vector2.ZERO, size).grow(VIEW_MARGIN)
	var waiting: Array[Dictionary] = []
	var expired: Array[Dictionary] = []
	for o in _queue:
		var to := _xf * (o["at"] as Vector2)
		if _clock - o["queued"] >= MAX_WAIT or not view.has_point(to):
			expired.append(o)
		else:
			o["cell"] = Vector2i((to / CROWD_CELL).floor())
			waiting.append(o)
	_queue = waiting
	_land_quietly(expired)
	if _queue.is_empty() or _flights.size() >= MAX_FLYING or _tokens < 1.0:
		return
	var crowd := {}
	for f in _flights:
		var cell := Vector2i(((f["to"] as Vector2) / CROWD_CELL).floor())
		crowd[cell] = crowd.get(cell, 0) + 1
	while not _queue.is_empty() and _flights.size() < MAX_FLYING and _tokens >= 1.0:
		var best := 0
		var best_score := INF
		for k in _queue.size():
			var o := _queue[k]
			var score: float = crowd.get(o["cell"], 0) + (o["queued"] - _clock) / (MAX_WAIT * 2.0)
			if score < best_score:
				best_score = score
				best = k
		var chosen := _queue[best]
		_queue.remove_at(best)
		crowd[chosen["cell"]] = crowd.get(chosen["cell"], 0) + 1
		_launch(chosen)


## Lands queued gems that won't fly, each with its glint.
func _land_quietly(orders: Array[Dictionary]) -> void:
	_landing += orders.size()
	for o in orders:
		_landing -= 1
		burst(o["at"], o["length"], o["color"])
		landed.emit(o["slot"])


func _draw() -> void:
	PlacementFx.draw_flights(self, _flights)
	var scale_px := board.scale_px()
	var sparse := _impacts.size() > IMPACT_DETAIL
	var view := Rect2(Vector2.ZERO, size).grow(VIEW_MARGIN * 4.0)
	for impact in _impacts:
		var at := _xf * (impact["at"] as Vector2)
		if view.has_point(at):
			PlacementFx.draw_impact(self, impact, at, impact["length"] * scale_px, sparse)


## Over the gems: trails, then the screen-sized parts of fireworks, beams
## and halos.
func _draw_over() -> void:
	var scale_px := board.scale_px()
	var trails := _fading.size()
	for f in _flights:
		if f["trail_life"] > 0.0:
			trails += 1
	if trails > 0:
		var sparks := clampi(TRAIL_BUDGET / trails, 3, TRAIL_SPARKS)
		for f in _flights:
			_draw_trail(f, sparks, scale_px)
		for f in _fading:
			_draw_trail(f, sparks, scale_px)
	for f in _flights:
		if f["style"] in FX_STYLES:
			PlacementFx.draw_fx(_fx_layer, f, scale_px, _sparkle)


## A light sparkle trail behind a moving gem: `sparks` sparkles, each
## shed from where the gem was when it was born, drifting out, shrinking and
## fading over the trail's life. They stop being shed when the gem lands.
func _draw_trail(f: Dictionary, sparks: int, scale_px: float) -> void:
	var life: float = f["trail_life"]
	if life <= 0.0:
		return
	var t: float = f["time"]
	var end: float = f["length"]
	var color: Color = f["color"]
	var big: bool = f["style"] in ["comet", "firework"]
	var bright := Color(color.lightened(0.15), 1.0)
	var mid := Color(color.lightened(0.45), 0.85)
	var out := Color(color.lightened(0.8), 0.0)
	for k in sparks:
		var phase := life * k / sparks
		var round_no := floorf((t - phase) / life)
		var born := round_no * life + phase
		if born < 0.0 or born > end:
			continue
		var age := t - born
		var x := age / life
		var h: int = hash(Vector3i(f["seed"], k, int(round_no)))
		var r1 := float(h & 1023) / 1023.0
		var r2 := float((h >> 10) & 1023) / 1023.0
		var r3 := float((h >> 20) & 1023) / 1023.0
		var speed := lerpf(10.0, 40.0, r1)
		var damping := lerpf(60.0, 120.0, r2)
		var moving := minf(age, speed / damping)
		var at := _path(f, born / end, f["to"], scale_px) \
				+ Vector2.from_angle(r3 * TAU) * (speed * moving - 0.5 * damping * moving * moving)
		var px := SPARKLE_PX * (lerpf(0.6, 1.4, r1) if big else lerpf(0.35, 0.8, r2)) * lerpf(1.0, 0.2, x)
		var tint := bright.lerp(mid, x / 0.45) if x < 0.45 else mid.lerp(out, (x - 0.45) / 0.55)
		_fx_layer.draw_texture_rect(_sparkle, Rect2(at - Vector2(px, px) / 2.0, Vector2(px, px)), false, tint)


func _land(f: Dictionary) -> void:
	var sprite: Sprite2D = f["sprite"]
	sprite.hide()
	_sprite_pool.append(sprite)
	if f.has("shaft"):
		var shaft: ColorRect = f["shaft"]
		shaft.hide()
		_shaft_pool.append(shaft)
		_shafts -= 1
		f.erase("shaft")
	if f["trail_life"] > 0.0:
		_fading.append(f)
	burst(f["at"], f["slot_length"], f["color"], f["style"] == "firework")
	landed.emit(f["slot"])


## Lands everything still flying or waiting (leaving the screen, or
## finishing).
func land_all() -> void:
	var all := _flights
	var waiting := _queue
	_flights = []
	_queue = []
	_landing += all.size()
	for f in all:
		_landing -= 1
		_land(f)
	_land_quietly(waiting)


## Board units to this control's px.
func _board_xf() -> Transform2D:
	return get_global_transform_with_canvas().affine_inverse() * board.get_global_transform_with_canvas() \
			* board.view_transform()


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

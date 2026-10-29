class_name MandalaDesign
extends RefCounted
## Seeded mandalas that differ in their rings, outer silhouette and the
## extras around them, so mandalas look clearly different from each other.
##
## A mandala is a center, then 3-6 rings out to its body radius, then a
## silhouette band, then optional extras outside it:
##   rings: each ring is either one SINGULAR pattern or a combination of
##       layers: something RISING from the ring's inner circle, something
##       HANGING from its outer circle and FLOATING shapes in the free space.
##       Sizes are set so the layers never collide and nothing gets too thin
##       for stones. A ring's pattern is drawn once in a wedge and repeated
##       6-32 times around.
##   silhouette: the mandala's outline beyond its last ring (SILHOUETTES).
##   extras: decorations outside the mandala (EXTRAS); the mandala shrinks
##       to make room for them.
## Rarely (ZOOM_CHANCE) the mandala is drawn twice as big with its center
## near a corner and cropped to a frame, so the picture shows about a
## quarter of it with the same size of stones.
##
## Output matches MandalaGenerator: polylines in unit space (-1..1, y down).

## Center motifs: a rosette of petals, a star, a circle in a circle, or a
## spiral of seeds.
const CENTERS := ["rosette", "star", "nested", "seeds"]
## Patterns that fill a ring alone: crossing diagonals, a zigzag, two
## interlaced zigzags, spokes with dots, a wave, offset bricks, a chain of
## circles.
const SINGULAR := ["lattice", "zigzag", "weave", "spokes", "wave", "bricks", "chain"]
## Patterns that combine, by layer.
const RISING := ["petals", "arches", "teeth", "tulips"]
const HANGING := ["scallops", "drips", "bells"]
const FLOATING := ["dots", "diamonds", "rings", "teardrops"]
const LAYERS := {"rising": RISING, "hanging": HANGING, "floating": FLOATING}
## Which layers a combined ring uses (never all three, which would crowd).
const LAYER_SETS := [["rising", "floating"], ["hanging", "floating"], ["rising", "hanging"], ["rising"],
		["hanging"], ["floating"]]
const SINGULAR_CHANCE := 0.25
## circle; scalloped (bumps); polygon (tangent to the body); star (points);
## petal_edge (pointed petals); sun (spaced rays); beaded (a rim of beads).
const SILHOUETTES := ["circle", "scalloped", "polygon", "star", "petal_edge", "sun", "beaded"]
## satellites (small rings around the mandala), sparkles (four-point stars),
## corners (fans in the picture's corners), frame (a square border), rays
## (lens-shaped rays pointing out).
const EXTRAS := ["satellites", "sparkles", "corners", "frame", "rays"]
const EXTRA_CHANCE := 0.45
const ZOOM_CHANCE := 0.05
const FOLDS := [6, 8, 10, 12, 16]
## Shapes on a ring's edge need at least this depth, or the space they
## enclose against the circle is too thin for stones.
const MIN_DEPTH := 0.065
## Recent silhouettes and extras skip this many; ring patterns skip 3.
const AVOID_RECENT := 2

var rng := RandomNumberGenerator.new()
var wobble := 0.0
var polylines: Array[PackedVector2Array] = []
var closed := PackedByteArray()
var _used_patterns := []


## options:
##   wobble: 0..1, the "semi-symmetric" strength (default 0)
##   silhouette: one of SILHOUETTES, or "random" (default)
##   extras: Array of EXTRAS to use instead of a random pick
##   zoom: true / false to force or forbid the zoomed-in crop (default:
##         ZOOM_CHANCE)
##   recent: Array of earlier results' {"silhouette", "center", "extras",
##           "rings"} for mandalas made in a row; recent choices are skipped
##           and the least used preferred
## Returns {"seed", "folds", "silhouette", "center", "rings" (each ring's
## patterns, inside out), "extras", "zoom", "polylines", "closed"}.
static func generate(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var g := MandalaDesign.new()
	g.rng.seed = seed_value
	g.wobble = clampf(options.get("wobble", 0.0), 0.0, 1.0)
	var recent: Array = options.get("recent", [])
	var silhouette: String = options.get("silhouette", "random")
	if not silhouette in SILHOUETTES:
		silhouette = g._least_used(SILHOUETTES, _history(recent, "silhouette"), AVOID_RECENT)
	var center := g._least_used(CENTERS, _history(recent, "center"), 1)
	var zoom: bool = options.get("zoom", g.rng.randf() < ZOOM_CHANCE)
	var extras: Array = options.get("extras", [] if zoom else g._pick_extras(_history(recent, "extras")))
	for r in recent:
		for ring in r.get("rings", []):
			g._used_patterns.append_array(ring)
	var folds: int = FOLDS[g.rng.randi_range(0, FOLDS.size() - 1)]
	var rings := g._build(folds, center, silhouette, extras)
	if zoom:
		g._crop()
	return {
		"seed": seed_value,
		"folds": folds,
		"silhouette": silhouette,
		"center": center,
		"rings": rings,
		"extras": extras,
		"zoom": zoom,
		"polylines": g.polylines,
		"closed": g.closed,
	}


static func _history(recent: Array, key: String) -> Array:
	var out := []
	for r in recent:
		var v: Variant = r.get(key)
		if v is Array:
			out.append_array(v)
		elif v != null:
			out.append(v)
	return out


## A name from `names`, skipping the last `avoid` of `recent` and preferring
## the least used.
func _least_used(names: Array, recent: Array, avoid: int) -> String:
	var skip := recent.slice(maxi(0, recent.size() - avoid))
	var choices := []
	var fewest := recent.size() + 1
	for n in names:
		if n in skip:
			continue
		var uses := recent.count(n)
		if uses < fewest:
			fewest = uses
			choices.clear()
		if uses == fewest:
			choices.append(n)
	if choices.is_empty():
		choices = names
	return choices[rng.randi_range(0, choices.size() - 1)]


## None, one, or now and then two extras (never corners with a frame).
func _pick_extras(used: Array) -> Array:
	var out := []
	if rng.randf() >= EXTRA_CHANCE:
		return out
	out.append(_least_used(EXTRAS, used, AVOID_RECENT))
	if rng.randf() < 0.35:
		var left := []
		for e in EXTRAS:
			if e != out[0] and not ((e == "frame" and out[0] == "corners") or (e == "corners" and out[0] == "frame")):
				left.append(e)
		out.append(_least_used(left, used, AVOID_RECENT))
	return out


func _add(points: PackedVector2Array, is_closed: bool = false) -> void:
	polylines.append(points)
	closed.append(1 if is_closed else 0)


static func _circle(r: float, segments: int = 0, center: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	return MandalaGenerator.circle(center, r, segments)


# --- the design ----------------------------------------------------------------------

## Builds center, rings, silhouette and extras. Returns each ring's patterns.
func _build(n: int, center: String, silhouette: String, extras: Array) -> Array:
	var reach := 0.74 if not extras.is_empty() else 1.0
	var band := 0.0 if silhouette == "circle" else rng.randf_range(0.1, 0.15)
	var body := reach - band
	var rc := rng.randf_range(0.09, 0.14)
	_build_center(center, rc, n)
	var rings := []
	var r := rc
	var last := []
	while r < body - 0.02:
		var w := rng.randf_range(0.1, 0.17)
		if body - (r + w) < 0.08:
			w = body - r
		var r1 := r + w
		var m := n
		# Outer rings have room for twice the repeats.
		if TAU * (r + r1) / 2.0 / (2 * n) > 0.075 and rng.randf() < 0.6:
			m = 2 * n
		var alpha := TAU / m
		var combo := _pick_ring(last, rings)
		var made := _ring_parts(combo, r, r1, alpha)
		combo = made[1]
		rings.append(combo)
		last = combo
		var turn := alpha / 2.0 if rng.randf() < 0.5 else 0.0
		_add_ring(made[0], m, r, r1, turn)
		_add(_circle(r1), true)
		r = r1
	_build_silhouette(silhouette, body, reach, n)
	for e in extras:
		_build_extra(e, reach, n)
	return rings


func _pick_ring(last: Array, rings: Array) -> Array:
	var used := _used_patterns.duplicate()
	for ring in rings:
		used.append_array(ring)
	if rng.randf() < SINGULAR_CHANCE:
		return [_least_used(_without(SINGULAR, last), used, 3)]
	var layers: Array = LAYER_SETS[rng.randi_range(0, LAYER_SETS.size() - 1)]
	var combo := []
	for layer in layers:
		var names: Array = LAYERS[layer]
		# Wide arches leave no room for hanging shapes beside them.
		if layer == "rising" and "hanging" in layers:
			names = _without(names, ["arches"])
		combo.append(_least_used(_without(names, last), used, 3))
	if layers == ["floating"] and rng.randf() < 0.6:
		combo.append(_least_used(_without(FLOATING, combo), used, 3))
	return combo


static func _without(names: Array, drop: Array) -> Array:
	var out := []
	for n in names:
		if not n in drop:
			out.append(n)
	return out


static func _has_any(list: Array, of: Array) -> bool:
	for item in list:
		if item in of:
			return true
	return false


## One wedge of a ring, in polar points Vector2(radius, angle from the
## wedge's center line), as [[points, closed], ...]. Returns [parts, the
## patterns actually used] (a hanging layer is dropped if the ring is too
## narrow for it beside a rising one).
func _ring_parts(source: Array, r0: float, r1: float, alpha: float) -> Array:
	var combo := source.duplicate()
	var w := r1 - r0
	var half := alpha / 2.0
	var has_r := _has_any(combo, RISING)
	var has_h := _has_any(combo, HANGING)
	var has_f := _has_any(combo, FLOATING)
	var h_in := 0.0
	var h_out := 0.0
	if has_r and has_h:
		h_out = maxf(MIN_DEPTH, 0.28 * w)
		h_in = w - h_out - maxf(0.045, 0.22 * w)
		if h_in < MIN_DEPTH:
			combo = _without(combo, HANGING)
			has_h = false
	if not (has_r and has_h):
		h_in = maxf(MIN_DEPTH, w * (0.58 if has_f else rng.randf_range(0.75, 0.92)))
		h_out = maxf(MIN_DEPTH, w * (0.32 if has_f else rng.randf_range(0.45, 0.65)))
	# Hanging shapes sit between rising ones.
	var off := half if has_r else 0.0
	var parts := []
	for c in combo:
		match c:
			"lattice":
				parts.append([PackedVector2Array([Vector2(r0, -half), Vector2(r1, half)]), false])
				parts.append([PackedVector2Array([Vector2(r0, half), Vector2(r1, -half)]), false])
			"zigzag":
				parts.append([PackedVector2Array([Vector2(r0, -half), Vector2(r1, 0.0), Vector2(r0, half)]), false])
			"weave":
				parts.append([PackedVector2Array([Vector2(r0, -half), Vector2(r1, 0.0), Vector2(r0, half)]), false])
				parts.append([PackedVector2Array([Vector2(r1, -half), Vector2(r0, 0.0), Vector2(r1, half)]), false])
			"spokes":
				parts.append([PackedVector2Array([Vector2(r0, 0.0), Vector2(r1, 0.0)]), false])
				parts.append([_polar_dot(r0 + w * 0.5, half, minf(w * 0.18, r0 * alpha * 0.2)), true])
			"wave":
				var wave := PackedVector2Array()
				for i in 25:
					wave.append(Vector2(r0 + w * (0.5 + 0.28 * cos(PI * (2.0 * i / 24.0 - 1.0))), -half + alpha * i / 24.0))
				parts.append([wave, false])
			"bricks":
				var mid := r0 + w / 2.0
				parts.append([PackedVector2Array([Vector2(mid, -half), Vector2(mid, half)]), false])
				parts.append([PackedVector2Array([Vector2(r0, 0.0), Vector2(mid, 0.0)]), false])
				parts.append([PackedVector2Array([Vector2(mid, half), Vector2(r1, half)]), false])
			"chain":
				var rr := minf(w * 0.42, (r0 + w / 2.0) * sin(half) * 0.98)
				parts.append([_polar_dot(r0 + w / 2.0, 0.0, rr), true])
				if rr >= 0.07:
					parts.append([_polar_dot(r0 + w / 2.0, 0.0, rr * 0.4), true])
			"petals":
				var shape := "round" if rng.randf() < 0.5 else "pointed"
				parts.append([_petal(r0, h_in, half * rng.randf_range(0.8, 1.0), shape), false])
			"arches":
				parts.append([_petal(r0, h_in * 0.8, half, "round"), false])
				# A smaller arch inside, when there's room between them.
				if h_in * 0.35 >= 0.05:
					parts.append([_petal(r0, h_in * 0.45, half * 0.5, "round"), false])
			"teeth":
				parts.append([PackedVector2Array([Vector2(r0, -half), Vector2(r0 + h_in, 0.0), Vector2(r0, half)]), false])
			"tulips":
				parts.append([_tulip(r0, h_in, half * 0.85), false])
			"scallops":
				var arc := PackedVector2Array()
				for i in 25:
					var u := -1.0 + 2.0 * i / 24.0
					arc.append(Vector2(r1 - h_out * sqrt(maxf(0.0, 1.0 - u * u)), off + u * half))
				parts.append([arc, false])
			"drips":
				parts.append([PackedVector2Array([Vector2(r1, off - half), Vector2(r1 - h_out, off), Vector2(r1, off + half)]),
						false])
			"bells":
				var bell := PackedVector2Array()
				for v in _petal(r1, -h_out, half * 0.7, "round"):
					bell.append(Vector2(v.x, v.y + off))
				parts.append([bell, false])
			_:
				_floating(c, combo, r0, r1, half, has_r, has_h, h_in, h_out, parts)
	return [parts, combo]


## A floating shape in the ring's free space: above the rising shapes, below
## the hanging ones, or in one of two rows when floating shapes are alone.
func _floating(kind: String, combo: Array, r0: float, r1: float, half: float, has_r: bool, has_h: bool,
		h_in: float, h_out: float, parts: Array) -> void:
	var lo := r0
	var hi := r1
	var t := 0.0
	if has_r:
		lo = r0 + h_in
	elif has_h:
		hi = r1 - h_out
	elif combo.find(kind) > 0:
		t = half
	var rm := (lo + hi) / 2.0
	var size := minf((hi - lo) / 2.0 * 0.62, rm * half * 0.62)
	if size < 0.012:
		return
	match kind:
		"dots":
			parts.append([_polar_dot(rm, t, size), true])
		"rings":
			parts.append([_polar_dot(rm, t, size), true])
			# Too small for a ring around it: just the dot.
			if size >= 0.07:
				parts.append([_polar_dot(rm, t, size * 0.4), true])
		"diamonds":
			parts.append([PackedVector2Array([Vector2(rm - size * 1.3, t), Vector2(rm, t + size / rm),
					Vector2(rm + size * 1.3, t), Vector2(rm, t - size / rm)]), true])
		"teardrops":
			var a := Vector2.from_angle(t) * (rm - size * 1.3)
			var b := Vector2.from_angle(t) * (rm + size * 1.3)
			parts.append([_to_polar(MandalaGenerator._lens(a, b, 0.5)), true])


## Repeats a wedge `m` times around the center. The wobble nudges each copy
## a little; it fades to zero at the ring's circles, so regions stay closed.
func _add_ring(parts: Array, m: int, r0: float, r1: float, turn: float) -> void:
	var alpha := TAU / m
	for k in m:
		var wa := rng.randf_range(-1.0, 1.0) * 0.05 * wobble * alpha
		var wr := rng.randf_range(-1.0, 1.0) * 0.07 * wobble * (r1 - r0)
		var base := turn + k * alpha
		for part in parts:
			var src: PackedVector2Array = part[0]
			var out := PackedVector2Array()
			for v in src:
				var taper := 0.0
				if r1 > r0:
					taper = sin(PI * clampf((v.x - r0) / (r1 - r0), 0.0, 1.0))
				out.append(Vector2.from_angle(base + v.y + wa * taper) * (v.x + wr * taper))
			_add(out, part[1])


func _build_center(kind: String, rc: float, n: int) -> void:
	_add(_circle(rc), true)
	match kind:
		"rosette":
			_add_ring([[_petal(rc * 0.35, rc * 0.62, PI / n, "round"), false]], n, rc * 0.35, rc, 0.0)
			_add(_circle(rc * 0.35), true)
		"star":
			var star := PackedVector2Array()
			for i in 2 * n:
				star.append(Vector2.from_angle(PI * i / n) * rc * (0.9 if i % 2 == 0 else 0.45))
			_add(star, true)
		"nested":
			_add(_circle(rc * 0.5), true)
		_:
			var golden := PI * (3.0 - sqrt(5.0))
			for i in 9:
				var f := sqrt((i + 0.5) / 9.0)
				_add(_circle(rc * 0.14 * (0.75 + 0.25 * f), 18, Vector2.from_angle(i * golden) * rc * 0.74 * f), true)


func _build_silhouette(kind: String, body: float, reach: float, n: int) -> void:
	var k := n if n <= 10 else n / 2
	match kind:
		"scalloped":
			var m := 2 * n
			var edge := PackedVector2Array()
			for i in 480:
				var t := TAU * i / 480.0
				edge.append(Vector2.from_angle(t) * (body + (reach - body) * absf(sin(m * t / 2.0))))
			_add(edge, true)
		"polygon":
			# Tangent to the body circle, so each corner is its own region.
			var r := minf(body / cos(PI / k), reach)
			var poly := PackedVector2Array()
			for i in k:
				poly.append(Vector2.from_angle(PI / k + TAU * i / k) * r)
			_add(poly, true)
		"star":
			var m := 2 * k
			var star := PackedVector2Array()
			for i in 2 * m:
				star.append(Vector2.from_angle(TAU * i / (2 * m)) * (reach if i % 2 == 0 else body * 0.985))
			_add(star, true)
		"petal_edge":
			var m := 2 * n if n <= 8 else n
			_add_ring([[_petal(body * 0.995, reach - body, PI / m, "pointed"), false]], m, body, reach, 0.0)
		"sun":
			var m := 2 * n
			var a := TAU / m * 0.3
			_add_ring([[PackedVector2Array([Vector2(body * 0.995, -a), Vector2(reach, 0.0), Vector2(body * 0.995, a)]),
					false]], m, body, reach, 0.0)
		"beaded":
			var mid := (body + reach) / 2.0
			var m := maxi(12, int(TAU * mid / ((reach - body) * 1.15)))
			_add(_circle(reach), true)
			for i in m:
				_add(_circle((reach - body) * 0.32, 20, Vector2.from_angle(TAU * i / m) * mid), true)


func _build_extra(kind: String, reach: float, n: int) -> void:
	var k := n if n <= 8 else n / 2
	match kind:
		"satellites":
			var rr := rng.randf_range(0.07, 0.09)
			for i in k:
				var c := Vector2.from_angle(TAU * (i + 0.5) / k) * (reach + 0.06 + rr)
				_add(_circle(rr, 32, c), true)
				_add(_circle(rr * 0.45, 20, c), true)
		"sparkles":
			for i in k:
				var c := Vector2.from_angle(TAU * (i + 0.5) / k) * (reach + 0.13)
				var sparkle := PackedVector2Array()
				for j in 8:
					sparkle.append(c + Vector2.from_angle(PI * j / 4.0) * (0.09 if j % 2 == 0 else 0.0315))
				_add(sparkle, true)
		"corners":
			# A fan in each corner of the picture, closed against its edges.
			for corner in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
				var a0 := (-corner).angle() - PI / 4.0
				for rr in [0.32, 0.22]:
					var arc := PackedVector2Array()
					for i in 17:
						arc.append(corner + Vector2.from_angle(a0 + PI / 2.0 * i / 16.0) * rr)
					_add(arc)
				_add(PackedVector2Array([corner + Vector2(0.0, -corner.y * 0.32), corner]))
				_add(PackedVector2Array([corner + Vector2(-corner.x * 0.32, 0.0), corner]))
				for i in range(1, 4):
					var d := Vector2.from_angle(a0 + PI / 2.0 * i / 4.0)
					_add(PackedVector2Array([corner + d * 0.22, corner + d * 0.32]))
		"frame":
			for f in [0.98, 0.9]:
				_add(PackedVector2Array([Vector2(-f, -f), Vector2(f, -f), Vector2(f, f), Vector2(-f, f)]), true)
			for corner in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
				_add(_circle(0.03, 16, corner * 0.94), true)
		"rays":
			var m := n if n >= 10 else 2 * n
			for i in m:
				var d := Vector2.from_angle(TAU * (i + 0.5) / m)
				_add(MandalaGenerator._lens(d * (reach + 0.04), d * (reach + 0.24), 0.36), true)


## Doubles the size, moves the center near a corner and keeps only what
## falls inside a frame, so the picture shows about a quarter of the mandala
## with stones the same size as usual.
func _crop() -> void:
	var c := Vector2(0.85 if rng.randf() < 0.5 else -0.85, 0.85 if rng.randf() < 0.5 else -0.85)
	var f := 0.97
	var frame := PackedVector2Array([Vector2(-f, -f), Vector2(f, -f), Vector2(f, f), Vector2(-f, f)])
	var lines: Array[PackedVector2Array] = []
	var flags := PackedByteArray()
	for i in polylines.size():
		var path := PackedVector2Array()
		for v in polylines[i]:
			path.append(c + v * 2.0)
		if closed[i]:
			path.append(path[0])
		for piece in Geometry2D.intersect_polyline_with_polygon(path, frame):
			lines.append(piece)
			flags.append(0)
	polylines = lines
	closed = flags
	_add(frame, true)


# --- shapes, in polar points Vector2(radius, angle) ------------------------------------

## A small circle around the polar point (r, t), in polar points.
static func _polar_dot(r: float, t: float, radius: float, n: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var p := Vector2(r + radius * cos(TAU * i / n), radius * sin(TAU * i / n))
		pts.append(Vector2(p.length(), p.angle() + t))
	return pts


static func _to_polar(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.length(), p.angle()))
	return out


## A petal from (r_in, -half_w) out to a tip of height h and back (h < 0
## hangs inward).
static func _petal(r_in: float, h: float, half_w: float, shape: String, n: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var u := -1.0 + 2.0 * i / n
		var f: float = pow(cos(u * PI / 2.0), 0.7) if shape == "round" else pow(1.0 - absf(u), 0.75)
		pts.append(Vector2(r_in + h * f, u * half_w))
	return pts


## A tulip: a round petal with a dip at the top and shoulders at the sides.
static func _tulip(r_in: float, h: float, half_w: float, n: int = 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var u := -1.0 + 2.0 * i / n
		var f := pow(cos(u * PI / 2.0), 0.6)
		var dip := 0.25 * exp(-pow(u / 0.22, 2.0))
		var side := 0.15 * exp(-pow((absf(u) - 0.55) / 0.15, 2.0))
		pts.append(Vector2(r_in + h * (f - dip + side), u * half_w))
	return pts

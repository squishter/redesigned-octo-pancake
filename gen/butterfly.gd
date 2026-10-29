class_name ButterflyGenerator
extends RefCounted
## Seeded butterflies that differ in wing shape, wing borders, the patterns on
## each wing, the body and the antennae, so butterflies look clearly different
## from each other.
##
## The right wings are built around an anchor beside the body, then mirrored.
## The forewing sits in front of the hindwing and the body in front of both:
## hidden parts of lines are clipped where they go under, and every visible
## piece ends on another line, so all regions stay closed. Lines also stop at
## the center line, so the left and right wings meet there.
##
## Each wing gets 1-3 patterns of its own, so forewings and hindwings can
## differ. Holes (eyespot, window) are placed first and the other patterns
## flow around them.
##
## Output matches MandalaGenerator: polylines in unit space (-1..1, y down).

## Where the current lines may draw: anywhere, inside the wing's inner area,
## in its border band, or inside its outline.
enum Area { ANY, INNER, BAND, WING }

## Wing shapes. fore and hind are [start angle, end angle (degrees, measured
## from the anchor, y down), size, fullness]: the wing's radius goes as
## sin(PI t)^fullness, so low is flat-topped and high is round.
## tail: a swallowtail's paddle on the hindwing; scallop: depth of edge waves.
const SHAPES := {
	"classic": {"fore": [-88.0, 5.0, 1.0, 0.55], "hind": [10.0, 95.0, 0.7, 0.55], "tail": 0.0, "scallop": 0.0},
	"swallowtail": {"fore": [-88.0, 0.0, 1.0, 0.45], "hind": [15.0, 95.0, 0.66, 0.6], "tail": 0.42, "scallop": 0.0},
	"rounded": {"fore": [-88.0, 8.0, 0.9, 0.85], "hind": [12.0, 100.0, 0.78, 0.85], "tail": 0.0, "scallop": 0.0},
	"glider": {"fore": [-62.0, -12.0, 1.05, 0.5], "hind": [0.0, 80.0, 0.62, 0.6], "tail": 0.0, "scallop": 0.0},
	"scalloped": {"fore": [-88.0, 5.0, 0.98, 0.6], "hind": [10.0, 98.0, 0.74, 0.6], "tail": 0.0, "scallop": 0.07},
	"moth": {"fore": [-78.0, 18.0, 1.0, 0.32], "hind": [25.0, 92.0, 0.58, 0.6], "tail": 0.0, "scallop": 0.0},
	"fairy": {"fore": [-88.0, -12.0, 0.82, 0.6], "hind": [0.0, 102.0, 0.9, 0.75], "tail": 0.0, "scallop": 0.0},
}
## A band along each wing's edge: plain, with a row of spots, with a wavy
## inner edge, divided into cells, or none.
const BORDERS := ["band", "spotted", "scalloped", "cells", "none"]
## Wing patterns. Holes: an eyespot (2-3 rings) or a window (a clear lens).
## Lines: veins from the body, rings following the wing's outline, stripes
## across the wing. Dots: scattered spots or a row of dots near the edge.
const HOLES := ["eyespot", "window"]
const LINES := ["veins", "rings", "stripes"]
const DOTS := ["spots", "dot_row"]
const PATTERNS := HOLES + LINES + DOTS
## Chances of 1, 2 or 3 patterns on a wing.
const PATTERN_COUNT_WEIGHTS := [0.3, 0.45, 0.25]
const BODIES := ["slender", "plump", "segmented"]
const ANTENNAE := ["clubbed", "curled", "feathered"]
## Shapes, borders and patterns used by this many previous butterflies in a
## row are skipped (bodies and antennae skip only the last one).
const AVOID_RECENT := 2
const ANCHOR := Vector2(0.03, -0.05)
const WING_SAMPLES := 120

var rng := RandomNumberGenerator.new()
## Lines for the right half (mirrored at the end) and for the center.
var _right: Array[PackedVector2Array] = []
var _right_closed := PackedByteArray()
var _center: Array[PackedVector2Array] = []
var _center_closed := PackedByteArray()

var _wing: Dictionary
## Shapes in front of the current wing (body, head, thorax, forewing).
var _fronts: Array[PackedVector2Array] = []
var _outline := PackedVector2Array()
var _inner := PackedVector2Array()
var _holes: Array[PackedVector2Array] = []
var _area := Area.ANY
var _spots := PackedVector2Array()


## options:
##   shape, border, body, antennae: one of SHAPES / BORDERS / BODIES /
##       ANTENNAE, or "random" (default)
##   recent: Array of earlier results' {"shape", "border", "body", "antennae",
##           "fore", "hind"} for butterflies made in a row; recent choices are
##           skipped and the least used preferred
## Returns {"seed", "shape", "border", "body", "antennae", "fore", "hind"
## (each wing's patterns), "polylines", "closed"}.
static func generate(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var g := ButterflyGenerator.new()
	g.rng.seed = seed_value
	var recent: Array = options.get("recent", [])
	var shape: String = g._choose(options, "shape", SHAPES.keys(), recent, AVOID_RECENT)
	var border: String = g._choose(options, "border", BORDERS, recent, AVOID_RECENT)
	var body: String = g._choose(options, "body", BODIES, recent, 1)
	var antennae: String = g._choose(options, "antennae", ANTENNAE, recent, 1)
	var used := []
	for r in recent:
		used.append_array(r.get("fore", []))
		used.append_array(r.get("hind", []))
	var fore := g._pick_patterns(used)
	used.append_array(fore)
	var hind := g._pick_patterns(used)

	g._build(SHAPES[shape], border, body, antennae, fore, hind)
	var polylines: Array[PackedVector2Array] = []
	var closed := PackedByteArray()
	polylines.append_array(g._center)
	closed.append_array(g._center_closed)
	for i in g._right.size():
		var mirrored := PackedVector2Array()
		for v in g._right[i]:
			mirrored.append(Vector2(-v.x, v.y))
		polylines.append(g._right[i])
		polylines.append(mirrored)
		closed.append(g._right_closed[i])
		closed.append(g._right_closed[i])
	return {
		"seed": seed_value,
		"shape": shape,
		"border": border,
		"body": body,
		"antennae": antennae,
		"fore": fore,
		"hind": hind,
		"polylines": polylines,
		"closed": closed,
	}


## options[key] when it names one of `names`, else the least used of them.
func _choose(options: Dictionary, key: String, names: Array, recent: Array, avoid: int) -> String:
	var wanted: String = options.get(key, "random")
	if wanted in names:
		return wanted
	var history := []
	for r in recent:
		if r.has(key):
			history.append(r[key])
	return _least_used(names, history, avoid)


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


## 1-3 patterns for one wing, at most one hole and one kind of dots.
func _pick_patterns(used: Array) -> Array:
	var count := PATTERN_COUNT_WEIGHTS.size()
	var pick := rng.randf()
	for i in PATTERN_COUNT_WEIGHTS.size():
		pick -= PATTERN_COUNT_WEIGHTS[i]
		if pick < 0.0:
			count = i + 1
			break
	var out := []
	for _i in count:
		var left := []
		for p in PATTERNS:
			if p in out:
				continue
			if (p in HOLES and _has_any(out, HOLES)) or (p in DOTS and _has_any(out, DOTS)):
				continue
			left.append(p)
		out.append(_least_used(left, used + out, AVOID_RECENT))
	return out


static func _has_any(list: Array, of: Array) -> bool:
	for item in list:
		if item in of:
			return true
	return false


func _add(points: PackedVector2Array, is_closed: bool = false) -> void:
	_right.append(points)
	_right_closed.append(1 if is_closed else 0)


func _add_center(points: PackedVector2Array, is_closed: bool = false) -> void:
	_center.append(points)
	_center_closed.append(1 if is_closed else 0)


# --- wings ------------------------------------------------------------------------

func _make_wing(spec: Array, wobble: float, tail: float, scallop: float, waves: int) -> Dictionary:
	return {
		"phi0": deg_to_rad(spec[0]),
		"phi1": deg_to_rad(spec[1]),
		"size": spec[2] * rng.randf_range(0.95, 1.05),
		"fullness": spec[3],
		"wobble": wobble,
		"tail": tail,
		"scallop": scallop,
		"waves": waves,
	}


static func _angle(wing: Dictionary, t: float) -> float:
	return lerpf(wing["phi0"], wing["phi1"], t)


## The wing's radius at t (0 and 1 are at the anchor), scaled by s.
static func _radius(wing: Dictionary, t: float, s: float = 1.0) -> float:
	var r: float = wing["size"] * pow(sin(PI * t), wing["fullness"]) * (1.0 + wing["wobble"] * cos(3.0 * PI * t))
	r *= 1.0 - wing["scallop"] * absf(sin(wing["waves"] * PI * t))
	if wing["tail"] > 0.0:
		r += wing["tail"] * exp(-pow((t - 0.74) / 0.075, 2.0))
	return r * s


static func _wing_point(wing: Dictionary, t: float, s: float = 1.0) -> Vector2:
	return ANCHOR + Vector2.from_angle(_angle(wing, t)) * _radius(wing, t, s)


## The wing's outline scaled by s about the anchor.
static func _wing_outline(wing: Dictionary, s: float = 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in WING_SAMPLES:
		pts.append(_wing_point(wing, float(i) / WING_SAMPLES, s))
	return pts


func _build(shape: Dictionary, border: String, body: String, antennae: String, fore_patterns: Array,
		hind_patterns: Array) -> void:
	var waves := rng.randi_range(6, 9)
	var fore := _make_wing(shape["fore"], rng.randf_range(0.04, 0.12), 0.0, shape["scallop"], waves)
	var hind := _make_wing(shape["hind"], rng.randf_range(0.03, 0.1), shape["tail"], shape["scallop"], waves)
	var body_parts := _build_body(body)
	var band := rng.randf_range(0.6, 0.7)
	var wings := [[fore, fore_patterns], [hind, hind_patterns]]
	for wi in wings.size():
		_wing = wings[wi][0]
		_fronts = body_parts.duplicate()
		if wi == 1:
			# The forewing covers the hindwing.
			_fronts.append(_wing_outline(fore))
		_outline = _wing_outline(_wing)
		_holes = []
		_area = Area.ANY
		_add_loop(_outline)
		_inner = _outline
		var s := 1.0
		if border != "none":
			_inner = _wing_outline(_wing, band)
			s = band
			_add_loop(_inner)
			_build_border(border, band)
		_build_patterns(wings[wi][1], s)
	_build_antennae(antennae)
	_fit()


## Whether a line may draw at p (see _area), outside the shapes in front,
## the holes and the left half.
func _visible(p: Vector2) -> bool:
	if p.x < 0.0 or not _in_area(p):
		return false
	for f in _fronts:
		if Geometry2D.is_point_in_polygon(p, f):
			return false
	for h in _holes:
		if Geometry2D.is_point_in_polygon(p, h):
			return false
	return true


func _in_area(p: Vector2) -> bool:
	match _area:
		Area.INNER:
			return Geometry2D.is_point_in_polygon(p, _inner)
		Area.BAND:
			return Geometry2D.is_point_in_polygon(p, _outline) and not Geometry2D.is_point_in_polygon(p, _inner)
		Area.WING:
			return Geometry2D.is_point_in_polygon(p, _outline)
	return true


## The visible pieces of a path, sampled every `step` with each end found by
## bisection, so pieces end exactly on the lines that stop them.
func _clip(path: PackedVector2Array, step: float = 0.01) -> Array[PackedVector2Array]:
	var dense := PackedVector2Array()
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var n := maxi(1, int(a.distance_to(b) / step))
		for j in n:
			dense.append(a.lerp(b, float(j) / n))
	dense.append(path[path.size() - 1])
	var pieces: Array[PackedVector2Array] = []
	var cur := PackedVector2Array()
	var prev := Vector2.ZERO
	var prev_shown := false
	for i in dense.size():
		var p := dense[i]
		var shown := _visible(p)
		if shown:
			if i > 0 and not prev_shown:
				cur = PackedVector2Array([_edge(p, prev)])
			cur.append(p)
		elif i > 0 and prev_shown:
			cur.append(_edge(prev, p))
			pieces.append(cur)
			cur = PackedVector2Array()
		prev = p
		prev_shown = shown
	if cur.size() >= 2:
		pieces.append(cur)
	# Drop crumbs where a path only grazes the visible area.
	var out: Array[PackedVector2Array] = []
	for piece in pieces:
		var length := 0.0
		for i in piece.size() - 1:
			length += piece[i].distance_to(piece[i + 1])
		if length > 0.02:
			out.append(piece)
	return out


## Where the segment from visible a to hidden b stops being visible.
func _edge(a: Vector2, b: Vector2) -> Vector2:
	var lo := 0.0
	var hi := 1.0
	for _i in 14:
		var m := (lo + hi) / 2.0
		if _visible(a.lerp(b, m)):
			lo = m
		else:
			hi = m
	return a.lerp(b, hi)


func _add_clipped(path: PackedVector2Array) -> void:
	for piece in _clip(path):
		_add(piece)


func _add_loop(loop: PackedVector2Array) -> void:
	var path := loop.duplicate()
	path.append(loop[0])
	_add_clipped(path)


## Whether a dot of radius r at c is fully visible.
func _clear(c: Vector2, r: float) -> bool:
	if not _visible(c):
		return false
	for i in 16:
		if not _visible(c + Vector2.from_angle(TAU * i / 16) * r):
			return false
	return true


func _build_border(border: String, band: float) -> void:
	var mid := (1.0 + band) / 2.0
	match border:
		"spotted":
			_area = Area.BAND
			var n := rng.randi_range(5, 9)
			for i in n:
				var t := 0.08 + 0.84 * (i + 0.5) / n
				var c := _wing_point(_wing, t, mid)
				var r := minf(_radius(_wing, t) * (1.0 - band) * 0.32, _radius(_wing, t, mid) * 0.84 / n * 1.2)
				if r > 0.012 and _clear(c, r + 0.012):
					_add(MandalaGenerator.circle(c, r, 20), true)
		"scalloped":
			# A wavy line through the band, closer to the inner edge.
			_area = Area.WING
			var k := rng.randi_range(5, 8)
			var wave := PackedVector2Array()
			for i in WING_SAMPLES + 1:
				var t := float(i) / WING_SAMPLES
				wave.append(_wing_point(_wing, t, band + (1.0 - band) * (0.15 + 0.5 * absf(sin(k * PI * t)))))
			_add_clipped(wave)
		"cells":
			_area = Area.BAND
			var n := rng.randi_range(4, 7)
			for i in range(1, n):
				var t := float(i) / n
				_add_clipped(PackedVector2Array([_wing_point(_wing, t, band * 0.98), _wing_point(_wing, t, 1.02)]))


## The wing's patterns inside its border; s is the inner area's scale.
func _build_patterns(patterns: Array, s: float) -> void:
	# Holes first, so lines and dots flow around them.
	_area = Area.INNER
	for p in patterns:
		match p:
			"eyespot":
				var c := _wing_point(_wing, rng.randf_range(0.4, 0.6), s * rng.randf_range(0.55, 0.65))
				var room := INF
				for v in _inner:
					room = minf(room, c.distance_to(v))
				var r := room * 0.8
				if r > 0.05 and _visible(c):
					var ring := MandalaGenerator.circle(c, r, 48)
					_add(ring, true)
					for f in ([0.55] if rng.randf() < 0.5 else [0.62, 0.3]):
						_add(MandalaGenerator.circle(c, r * f, 32), true)
					_holes.append(ring)
			"window":
				var t := rng.randf_range(0.42, 0.58)
				var a := _wing_point(_wing, t, s * 0.3)
				var b := _wing_point(_wing, t, s * 0.8)
				for _try in 6:
					var lens := MandalaGenerator._lens(a, b, rng.randf_range(0.35, 0.5))
					if _lens_fits(lens):
						_add(lens, true)
						_holes.append(lens)
						break
					var mid := (a + b) / 2.0
					a = mid + (a - mid) * 0.85
					b = mid + (b - mid) * 0.85
	for p in patterns:
		match p:
			"veins":
				var n := rng.randi_range(3, 6)
				for i in range(1, n + 1):
					_add_clipped(PackedVector2Array([ANCHOR, _wing_point(_wing, float(i) / (n + 1), 1.2)]))
			"rings":
				for f in ([0.55] if rng.randf() < 0.5 else [0.4, 0.7]):
					_add_loop(_wing_outline(_wing, s * f))
			"stripes":
				var dir := Vector2.from_angle(_angle(_wing, 0.5) + PI / 2.0 + rng.randf_range(-0.3, 0.3))
				var across := Vector2(-dir.y, dir.x)
				var step := rng.randf_range(0.12, 0.17)
				for i in range(1, 12):
					var o := ANCHOR + across * step * i
					_add_clipped(PackedVector2Array([o - dir * 2.0, o + dir * 2.0]))
			"spots":
				var r := rng.randf_range(0.03, 0.045)
				var target := rng.randi_range(4, 7)
				var placed := 0
				for _try in 40:
					var c := _wing_point(_wing, rng.randf_range(0.1, 0.9), s * rng.randf_range(0.25, 0.85))
					if not _clear(c, r + 0.035):
						continue
					var apart := true
					for other in _spots:
						if c.distance_to(other) <= 2.0 * r + 0.04:
							apart = false
							break
					if apart:
						_add(MandalaGenerator.circle(c, r, 20), true)
						_spots.append(c)
						placed += 1
						if placed >= target:
							break
			"dot_row":
				var f := rng.randf_range(0.72, 0.85)
				var n := rng.randi_range(5, 8)
				for i in n:
					var t := 0.1 + 0.8 * (i + 0.5) / n
					var c := _wing_point(_wing, t, s * f)
					var r := minf(0.035, _radius(_wing, t, s * f) * 0.8 / n * 1.1)
					if r > 0.015 and _clear(c, r + 0.025):
						_add(MandalaGenerator.circle(c, r, 20), true)


## Whether a window lens lies inside the wing's inner area, visible and
## clear of its edge.
func _lens_fits(lens: PackedVector2Array) -> bool:
	for v in lens:
		if not _visible(v):
			return false
	for i in range(0, lens.size(), 2):
		for j in range(0, _inner.size(), 2):
			if lens[i].distance_to(_inner[j]) <= 0.04:
				return false
	return true


# --- body ------------------------------------------------------------------------

## Draws the body, thorax and head; returns their outlines, which hide the
## wing lines behind them.
func _build_body(kind: String) -> Array[PackedVector2Array]:
	var widths := {"slender": 0.042, "plump": 0.068, "segmented": 0.055}
	var w: float = widths[kind] * rng.randf_range(0.92, 1.08)
	var body := PackedVector2Array()
	for i in 60:
		var a := TAU * i / 60.0
		body.append(Vector2(w * cos(a), 0.02 + 0.42 * sin(a)))
	_add_center(body, true)
	var thorax_r := w * 1.35
	var thorax := MandalaGenerator.circle(Vector2(0.0, -0.22), thorax_r, 32)
	if kind != "slender":
		_add_center(thorax, true)
	if kind == "segmented":
		for i in range(1, rng.randi_range(4, 6)):
			var y := -0.22 + thorax_r + 0.07 * i
			if y < 0.4:
				# Across the abdomen, from edge to edge.
				var half := w * sqrt(maxf(0.0, 1.0 - pow((y - 0.02) / 0.42, 2.0)))
				_add_center(PackedVector2Array([Vector2(-half, y), Vector2(half, y)]))
	var head := MandalaGenerator.circle(Vector2(0.0, -0.47), 0.06, 32)
	_add_center(head, true)
	var parts: Array[PackedVector2Array] = [body, head]
	if kind != "slender":
		parts.append(thorax)
	return parts


func _build_antennae(kind: String) -> void:
	var spread := rng.randf_range(0.2, 0.3)
	var length := rng.randf_range(0.28, 0.36)
	var pts := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		pts.append(Vector2(0.02 + spread * t * t, -0.52 - length * t))
	var tip := pts[pts.size() - 1]
	match kind:
		"clubbed":
			_add(pts)
			_add(MandalaGenerator.circle(tip, 0.035, 20), true)
		"curled":
			# Curls outward at the tip.
			var c := tip + Vector2(0.035, 0.0)
			for i in range(1, 16):
				var a := PI + i / 15.0 * 1.6 * PI
				var rr := 0.035 * (1.0 - 0.45 * i / 15.0)
				pts.append(c + Vector2(rr * cos(a), -rr * sin(a)))
			_add(pts)
		_:
			# Feathered, like a moth's: a slim leaf along the antenna.
			_add(MandalaGenerator._lens(pts[0], tip, 0.28), true)
			_add(pts)


## Scales and shifts everything to fill the unit square, centered.
func _fit() -> void:
	var max_x := 0.0
	var top := INF
	var bottom := -INF
	for list in [_right, _center]:
		for line in list:
			for v in line:
				max_x = maxf(max_x, absf(v.x))
				top = minf(top, v.y)
				bottom = maxf(bottom, v.y)
	var k := 1.94 / maxf(2.0 * max_x, bottom - top)
	var shift := -(top + bottom) / 2.0
	for list in [_right, _center]:
		for i in list.size():
			var moved := PackedVector2Array()
			for v in list[i]:
				moved.append(Vector2(v.x * k, (v.y + shift) * k))
			list[i] = moved

class_name FlowerGenerator
extends RefCounted
## Seeded flowers built from petal templates, so flowers look clearly
## different from each other rather than like one flower at different sizes.
##
## Each flower picks a template and draws 1-4 rings of petals around a center.
## A ring of 6 or more (an even count) alternates 2 wobbled versions of its
## template (ABAB), so it stays symmetric but not uniform; others repeat one.
## Every ring, and the center, keeps a turn the first ring has (the
## flower's turns), so the whole flower repeats around.
## Inner rings sit in front of outer ones and each petal overlaps the next
## like a pinwheel; hidden parts of outlines are clipped away, and every
## visible piece ends on another outline, so all regions stay closed.
##
## Output matches MandalaGenerator: polylines in unit space (-1..1, y down).

## Petal templates. petals and rings are inclusive ranges, drawn uniformly.
## width: petal width at its widest point as a fraction of the space between
##        neighbors (above 1 overlaps)
## widest: where along the petal (0..1) it is widest
## rise: how fast the sides widen from the base (big = long thin stem first)
## tip: superellipse exponent of the tip (below 1 pointed, 2 round, above 2 blunt)
## base: half-width at the base as a fraction of the widest half-width
## curl, skew: bend along the petal and tilt at its base, in degrees
## notch: depth of a heart notch at the tip as a fraction of the length
## teeth: number of fringe teeth across the tip (0 = smooth)
const TEMPLATES := {
	"oval": {"petals": [8, 16], "rings": [1, 2], "width": [0.75, 0.95], "widest": 0.55, "rise": 0.6, "tip": 2.0,
			"base": 0.35, "curl": 0.0, "skew": 0.0, "notch": 0.0, "teeth": 0},
	"pointed": {"petals": [5, 12], "rings": [1, 3], "width": [0.85, 1.05], "widest": 0.38, "rise": 0.7, "tip": 1.0,
			"base": 0.4, "curl": 0.0, "skew": 0.0, "notch": 0.0, "teeth": 0},
	"heart": {"petals": [5, 8], "rings": [1, 2], "width": [0.95, 1.1], "widest": 0.68, "rise": 0.8, "tip": 2.4,
			"base": 0.3, "curl": 0.0, "skew": 0.0, "notch": 0.16, "teeth": 0},
	"fan": {"petals": [4, 7], "rings": [2, 4], "width": [1.2, 1.5], "widest": 0.72, "rise": 0.7, "tip": 2.8,
			"base": 0.45, "curl": 0.0, "skew": 4.0, "notch": 0.0, "teeth": 0},
	"fringed": {"petals": [6, 10], "rings": [1, 3], "width": [0.9, 1.1], "widest": 0.75, "rise": 0.9, "tip": 3.0,
			"base": 0.3, "curl": 0.0, "skew": 0.0, "notch": 0.0, "teeth": 5},
	"ray": {"petals": [18, 36], "rings": [1, 2], "width": [0.55, 0.75], "widest": 0.6, "rise": 0.5, "tip": 1.4,
			"base": 0.45, "curl": 0.0, "skew": 0.0, "notch": 0.0, "teeth": 0},
	"spoon": {"petals": [8, 14], "rings": [1, 2], "width": [0.6, 0.85], "widest": 0.8, "rise": 3.0, "tip": 2.0,
			"base": 0.3, "curl": 0.0, "skew": 0.0, "notch": 0.0, "teeth": 0},
}
const CENTERS := ["seeds", "stamens", "nested", "star"]
## Templates used by this many previous flowers in a row are skipped.
const AVOID_RECENT := 2
## Headroom so the longest wobbled petal still ends inside the unit circle.
const MAX_LENGTH_SCALE := 1.15 * 1.04
## Narrowest petal half-width (unit space) a ring may have, so even thin rays
## leave room for a row of stones; rings with too many petals get fewer.
const MIN_HALF_WIDTH := 0.024
## Fewest turns a flower keeps when a ring can't share all of its first
## ring's (unless that has fewer).
const MIN_TURNS := 4

var rng := RandomNumberGenerator.new()
var wobble := 0.0
var polylines: Array[PackedVector2Array] = []
var closed := PackedByteArray()


## options:
##   template: one of TEMPLATES, or "random" (default)
##   recent: Array of templates used by the previous flowers in a row (a pack's
##           picture choices). The last AVOID_RECENT of them aren't picked
##           again, and the least used of the rest are preferred, so a run of
##           flowers works through every template.
##   wobble: 0..1, per-petal jitter for the semi-symmetric look (default 0)
## Returns {"seed", "template", "rings": [{"template", "petals"}], "center",
## "polylines", "closed"}.
static func generate(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var g := FlowerGenerator.new()
	g.rng.seed = seed_value
	g.wobble = clampf(options.get("wobble", 0.0), 0.0, 1.0)
	var template: String = options.get("template", "random")
	if not TEMPLATES.has(template):
		template = g._pick_template(options.get("recent", []))
	var rings := g._build(template)
	var turns := 0
	for r in rings:
		turns = _gcd(turns, _turns(r["petals"]))
	var center := g._build_center(rings[0]["rc"], turns)
	var ring_info := []
	for r in rings:
		ring_info.append({"template": r["template"], "petals": r["petals"]})
	return {
		"seed": seed_value,
		"template": template,
		"rings": ring_info,
		"center": center,
		"polylines": g.polylines,
		"closed": g.closed,
	}


func _add(points: PackedVector2Array, is_closed: bool = false) -> void:
	polylines.append(points)
	closed.append(1 if is_closed else 0)


func _pick_template(recent: Array) -> String:
	var skip := recent.slice(maxi(0, recent.size() - AVOID_RECENT))
	var choices := []
	var fewest := recent.size() + 1
	for t in TEMPLATES:
		if t in skip:
			continue
		var uses := recent.count(t)
		if uses < fewest:
			fewest = uses
			choices.clear()
		if uses == fewest:
			choices.append(t)
	return choices[rng.randi_range(0, choices.size() - 1)]


func _range(pair: Array) -> int:
	return rng.randi_range(pair[0], pair[1])


## Lays out the rings from the outside in, then draws them front to back:
## the center covers every ring and each ring covers the ones outside it.
## Returns the rings' specs, outermost first; each has "rc", the center radius.
func _build(template: String) -> Array:
	var rc := rng.randf_range(0.11, 0.17)
	var t := template
	var n := _range(TEMPLATES[t]["petals"])
	var reach := 1.0
	var rotation := rng.randf() * TAU
	var rings := []
	var turns := 0
	for _ring in _range(TEMPLATES[template]["rings"]):
		var p: Dictionary = TEMPLATES[t]
		var width := rng.randf_range(p["width"][0], p["width"][1])
		n = _fitting(n, _max_petals(p, width, reach, rc), turns)
		turns = _gcd(turns, _turns(n))
		rings.append({"template": t, "petals": n, "reach": reach, "rotation": rotation, "width": width, "rc": rc})
		reach = rc + (reach - rc) * rng.randf_range(0.55, 0.8)
		rotation += PI / n
		# The next ring in: sometimes another template, else the same count,
		# half of it, or a fresh count.
		if rng.randf() < 0.3:
			var others := []
			for other in TEMPLATES:
				if other != t:
					others.append(other)
			t = others[rng.randi_range(0, others.size() - 1)]
			n = _range(TEMPLATES[t]["petals"])
		else:
			match rng.randi_range(0, 2):
				1:
					if n >= 10:
						n /= 2
				2:
					n = _range(TEMPLATES[t]["petals"])

	var ring_polys := []
	for ring in rings:
		ring_polys.append(_ring_petals(ring, rc))
	var front: Array[PackedVector2Array] = []
	var front_boxes: Array[Rect2] = []
	for k in range(rings.size() - 1, -1, -1):
		var polys: Array = ring_polys[k]
		var m := polys.size()
		for i in m:
			var poly: PackedVector2Array = polys[i]
			var occluders: Array[PackedVector2Array] = front.duplicate()
			var boxes: Array[Rect2] = front_boxes.duplicate()
			# Pinwheel: each petal tucks under the one before it.
			var prev: PackedVector2Array = polys[(i - 1 + m) % m]
			occluders.append(prev)
			boxes.append(_bounds(prev))
			var path := poly.duplicate()
			path.append(poly[0])
			for piece in _clip(path, rc, occluders, boxes):
				_add(piece)
		for poly in polys:
			front.append(poly)
			front_boxes.append(_bounds(poly))
	_add(MandalaGenerator.circle(Vector2.ZERO, rc), true)
	return rings


## The petal count nearest `want`, at most `cap`, whose ring keeps the
## flower's turns so far (all of them if any count does, else at least
## MIN_TURNS of them).
static func _fitting(want: int, cap: int, turns: int) -> int:
	if turns == 0:
		return mini(want, cap)
	var best := mini(want, cap)
	var best_cost := INF
	for c in range(3, cap + 1):
		var kept := _gcd(_turns(c), turns)
		if kept < mini(turns, MIN_TURNS):
			continue
		var cost: float = absi(c - want) + (0.0 if kept == turns else float(want))
		if cost < best_cost:
			best_cost = cost
			best = c
	return best


## Wobbled versions a ring of n petals alternates.
static func _versions(n: int) -> int:
	return 2 if n % 2 == 0 and n >= 6 else 1


## Turns of a ring of n petals: it repeats every _versions petals.
static func _turns(n: int) -> int:
	return n / _versions(n)


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := a % b
		a = b
		b = t
	return a


## Most petals a ring can hold while its narrowest wobbled version keeps
## MIN_HALF_WIDTH at its widest point.
static func _max_petals(p: Dictionary, width: float, reach: float, rc: float) -> int:
	var base_r := rc * 0.6
	var mid_r: float = base_r + p["widest"] * (reach - base_r) / MAX_LENGTH_SCALE * 0.85
	var s := MIN_HALF_WIDTH / (width * 0.85 * mid_r)
	if s >= 1.0:
		return 3
	return maxi(3, floori(PI / asin(s)))


## Closed petal outlines for one ring, in unit space.
func _ring_petals(ring: Dictionary, rc: float) -> Array:
	var p: Dictionary = TEMPLATES[ring["template"]]
	var n: int = ring["petals"]
	var k := _versions(n)
	var versions := []
	for _v in k:
		versions.append(_wobbled(p))
	var alpha := TAU / n
	var base_r := rc * 0.6
	var out := []
	for i in n:
		var q: Dictionary = versions[i % k]
		var jitter_angle := rng.randf_range(-1.0, 1.0) * deg_to_rad(2.0) * wobble
		var jitter_length := 1.0 + rng.randf_range(-1.0, 1.0) * 0.04 * wobble
		var length: float = (ring["reach"] - base_r) / MAX_LENGTH_SCALE * q["length_scale"] * jitter_length
		var mid_r: float = base_r + q["widest"] * length
		var half_w: float = minf(ring["width"] * q["width_scale"] * mid_r * sin(alpha / 2.0), length * 0.45)
		var local := _petal_outline(q, length, half_w)
		out.append(_place(local, base_r, ring["rotation"] + i * alpha + jitter_angle, length, q["curl"], q["skew"]))
	return out


## One wobbled version of a template: length x0.85-1.15, width x0.85-1.2,
## tip and notch +-20%, curl +-10 degrees, skew +-6 degrees.
func _wobbled(p: Dictionary) -> Dictionary:
	var q := p.duplicate()
	q["length_scale"] = rng.randf_range(0.85, 1.15)
	q["width_scale"] = rng.randf_range(0.85, 1.2)
	q["tip"] = p["tip"] * rng.randf_range(0.8, 1.2)
	q["notch"] = p["notch"] * rng.randf_range(0.8, 1.2)
	q["curl"] = p["curl"] + rng.randf_range(-10.0, 10.0)
	q["skew"] = p["skew"] + rng.randf_range(-6.0, 6.0)
	return q


## A petal outline in local space: x runs from the base (0) to the tip
## (length), y across. Goes up one side, around the tip and back down.
static func _petal_outline(p: Dictionary, length: float, half_w: float, n: int = 28) -> PackedVector2Array:
	var widest: float = p["widest"]
	var rise: float = p["rise"]
	var e: float = p["tip"]
	var notch: float = p["notch"]
	var teeth: int = p["teeth"]
	var b: float = half_w * p["base"]
	var side := PackedVector2Array()
	var half := n / 2
	for i in half:
		var t := widest * i / half
		var s := pow(t / widest, rise)
		side.append(Vector2(t * length, b + (half_w - b) * sin(PI / 2.0 * s)))
	var pts := side.duplicate()
	# The tip: a superellipse arc from the left side (+y) to the right (-y).
	for i in range(1, n):
		var th := PI / 2.0 - PI * i / n
		var c := cos(th)
		var s := sin(th)
		var v := signf(s) * pow(absf(s), 2.0 / e)
		var x := (widest + (1.0 - widest) * pow(absf(c), 2.0 / e)) * length
		if notch > 0.0:
			x -= notch * length * exp(-pow(v / 0.38, 2.0))
		if teeth > 0:
			var saw := absf(fposmod((v + 1.0) / 2.0 * teeth, 1.0) - 0.5) * 2.0
			x -= 0.07 * length * (1.0 - saw) * sqrt(absf(c))
		pts.append(Vector2(x, v * half_w))
	for i in range(side.size() - 1, -1, -1):
		pts.append(Vector2(side[i].x, -side[i].y))
	return pts


## Bends a local outline by `curl` (more toward the tip), tilts it by `skew`,
## and stands it on the ring at `angle` with its base `base_r` from the center.
static func _place(local: PackedVector2Array, base_r: float, angle: float, length: float,
		curl: float, skew: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in local:
		var phi := deg_to_rad(curl) * pow(v.x / length, 2.0) + deg_to_rad(skew)
		out.append((v.rotated(phi) + Vector2(base_r, 0.0)).rotated(angle))
	return out


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		r = r.expand(v)
	return r


static func _hidden(p: Vector2, rc: float, polys: Array[PackedVector2Array], boxes: Array[Rect2]) -> bool:
	if p.length_squared() < rc * rc:
		return true
	for i in polys.size():
		if boxes[i].has_point(p) and Geometry2D.is_point_in_polygon(p, polys[i]):
			return true
	return false


## The parts of `path` outside the center disc and every occluder. Each piece
## starts and ends on an occluder's edge, found by bisection.
static func _clip(path: PackedVector2Array, rc: float, polys: Array[PackedVector2Array],
		boxes: Array[Rect2]) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = []
	var cur := PackedVector2Array()
	var prev := Vector2.ZERO
	var prev_hidden := true
	for i in path.size():
		var p := path[i]
		var hidden := _hidden(p, rc, polys, boxes)
		if not hidden:
			if i > 0 and prev_hidden:
				cur = PackedVector2Array([_crossing(p, prev, rc, polys, boxes)])
			cur.append(p)
		elif i > 0 and not prev_hidden:
			cur.append(_crossing(prev, p, rc, polys, boxes))
			pieces.append(cur)
			cur = PackedVector2Array()
		prev = p
		prev_hidden = hidden
	if cur.size() >= 2:
		pieces.append(cur)
	# The path is closed: when it starts visible, its first and last pieces are one.
	if pieces.size() >= 2 and not _hidden(path[0], rc, polys, boxes):
		var last: PackedVector2Array = pieces.pop_back()
		last.append_array(pieces[0].slice(1))
		pieces[0] = last
	var out: Array[PackedVector2Array] = []
	for piece in pieces:
		if piece.size() >= 2:
			out.append(piece)
	return out


## Where the segment from visible point a to hidden point b goes under.
static func _crossing(a: Vector2, b: Vector2, rc: float, polys: Array[PackedVector2Array], boxes: Array[Rect2]) -> Vector2:
	var lo := 0.0
	var hi := 1.0
	for _i in 12:
		var m := (lo + hi) / 2.0
		if _hidden(a.lerp(b, m), rc, polys, boxes):
			hi = m
		else:
			lo = m
	return a.lerp(b, hi)


## Draws the flower's center inside its disc of radius rc, repeating with
## the flower's turns. Returns its kind.
func _build_center(rc: float, turns: int) -> String:
	var kind: String = CENTERS[rng.randi_range(0, CENTERS.size() - 1)]
	match kind:
		"seeds":
			# Seed dots in two staggered rings around one.
			var n := _count(3, 6, turns)
			_add(MandalaGenerator.circle(Vector2.ZERO, rc * 0.16, 20), true)
			for i in n:
				_add(MandalaGenerator.circle(Vector2.from_angle(TAU * i / n) * rc * 0.42, rc * 0.12, 20), true)
				_add(MandalaGenerator.circle(Vector2.from_angle(TAU * (i + 0.5) / n) * rc * 0.74, rc * 0.14, 20), true)
		"stamens":
			_add(MandalaGenerator.circle(Vector2.ZERO, rc * 0.5), true)
			var n := _count(6, 10, turns)
			for i in n:
				_add(MandalaGenerator.circle(Vector2.from_angle(TAU * i / n) * rc * 0.76, rc * 0.13, 18), true)
		"nested":
			for s in [0.68, 0.38]:
				_add(MandalaGenerator.circle(Vector2.ZERO, rc * s), true)
		_:
			var k := _count(5, 8, turns)
			var star := PackedVector2Array()
			for i in 2 * k:
				star.append(Vector2.from_angle(PI * i / k) * rc * (0.72 if i % 2 == 0 else 0.36))
			_add(star, true)
	return kind


## A count from lo..hi that repeats with `turns` (a multiple of it, else a
## divisor of it of at least 3), or any when none does.
func _count(lo: int, hi: int, turns: int) -> int:
	var fits := []
	for c in range(lo, hi + 1):
		if turns > 0 and c % turns == 0:
			fits.append(c)
	if fits.is_empty():
		for c in range(3, hi + 1):
			if turns > 0 and turns % c == 0:
				fits.append(c)
	if fits.is_empty():
		return rng.randi_range(lo, hi)
	return fits[rng.randi_range(0, fits.size() - 1)]

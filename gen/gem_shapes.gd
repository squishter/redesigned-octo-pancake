class_name GemShapes
extends RefCounted
## Outline polygons for slot and gem shapes, in local space: the shape's long
## axis is +x (a teardrop points toward +x), centered on the origin.
## They draw slots and flat previews, and GemMesh builds the 3D gems on
## them (one per cut, see GemCuts).
##
## Shapes whose native outline fits a circle of diameter `length`:
## round, square, hexagon, triangle, cushion, octagon, pentagon, heart,
## trillion, star, flower, clover, pebble, sunburst, butterfly. A different
## `width` stretches their second axis just as the placed mesh does. Shapes that fit a capsule `length` long and
## `width` wide: oval, marquise, teardrop, kite, lozenge. Baguette and
## emerald fill the whole `length` x `width` box (only for gem lines).

## A square's side as a share of `length`: a little over the inscribed square,
## so it reads as big as the round stones beside it. Kits, whose square drills
## fill their cell, size their slots by it (see drill_length).
const SQUARE_SIDE := 0.75
## These outlines are built from their length, then scaled to the saved
## width. Round/oval and long shapes already use both dimensions below.
const WIDTH_SCALED := ["square", "hexagon", "triangle", "cushion", "octagon", "pentagon", "star", "flower",
		"trillion", "heart", "clover", "pebble", "sunburst", "butterfly"]

## A butterfly's upper wings as ellipses: their center's angle (degrees
## from the head) and distance from the middle, their turn (degrees) and
## half-axes. The lower wings mirror them.
const BUTTERFLY_WINGS := [[55.0, 0.48, 70.0, 0.46, 0.32], [130.0, 0.4, 120.0, 0.36, 0.26]]


static func outline(shape: String, length: float, width: float, segments: int = 24) -> PackedVector2Array:
	var a := length / 2.0
	var b := width / 2.0
	var pts := PackedVector2Array()
	match shape:
		"marquise":
			for i in segments + 1:
				var t := -1.0 + 2.0 * i / segments
				pts.append(Vector2(a * t, b * (1.0 - t * t)))
			for i in range(segments - 1, 0, -1):
				var t := -1.0 + 2.0 * i / segments
				pts.append(Vector2(a * t, -b * (1.0 - t * t)))
		"teardrop":
			# Round at -x, pointed at +x; scaled so it is exactly `width` wide.
			var raw := PackedVector2Array()
			var max_y := 0.0
			for i in segments:
				var th := TAU * i / segments
				var y := sin(th) * sqrt((1.0 - cos(th)) / 2.0)
				raw.append(Vector2(cos(th), y))
				max_y = maxf(max_y, absf(y))
			for p in raw:
				pts.append(Vector2(p.x * a, p.y / max_y * b))
		"baguette":
			pts = PackedVector2Array([Vector2(-a, -b), Vector2(a, -b), Vector2(a, b), Vector2(-a, b)])
		"square":
			var s := a * SQUARE_SIDE
			pts = PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)])
		"hexagon":
			for i in 6:
				pts.append(Vector2.from_angle(PI / 3.0 * i) * a * 0.95)
		"triangle":
			# A corner at +x, so it mirrors onto itself across its axis.
			for i in 3:
				pts.append(Vector2.from_angle(TAU / 3.0 * i) * a)
		"emerald":
			# Keep the existing 3D silhouette: each axis loses 35% at its
			# corners. Using the width's clip on both axes would expand long
			# stones past their old silhouette and can crowd gem-line neighbors.
			var cx := a * 0.35
			var cy := b * 0.35
			pts = PackedVector2Array([Vector2(-a + cx, -b), Vector2(a - cx, -b), Vector2(a, -b + cy), Vector2(a, b - cy),
					Vector2(a - cx, b), Vector2(-a + cx, b), Vector2(-a, b - cy), Vector2(-a, -b + cy)])
		"kite":
			# Pointed at +x, with its shoulders behind the middle, kept inside
			# the capsule's straight stretch so it fits a capsule slot.
			var xs := -minf(a * 0.35, a - b)
			pts = PackedVector2Array([Vector2(a, 0.0), Vector2(xs, b), Vector2(-a, 0.0), Vector2(xs, -b)])
		"lozenge":
			pts = PackedVector2Array([Vector2(a, 0.0), Vector2(0.0, b), Vector2(-a, 0.0), Vector2(0.0, -b)])
		"cushion":
			# A squircle (|x|^4 + |y|^4 = s^4) whose corners touch the circle.
			var s := a / pow(2.0, 0.25)
			var n := maxi(segments, 32)
			for i in n:
				var th := TAU * i / n
				var c := cos(th)
				var sn := sin(th)
				pts.append(Vector2(signf(c) * sqrt(absf(c)), signf(sn) * sqrt(absf(sn))) * s)
		"octagon":
			# Asscher-like: flat sides facing the axes.
			for i in 8:
				pts.append(Vector2.from_angle(PI / 8.0 + PI / 4.0 * i) * a)
		"pentagon":
			for i in 5:
				pts.append(Vector2.from_angle(TAU / 5.0 * i) * a)
		"star":
			for i in 10:
				pts.append(Vector2.from_angle(PI / 5.0 * i) * a * (1.0 if i % 2 == 0 else 0.5))
		"flower":
			# Rose cut with six rounded petals.
			var n := maxi(segments, 48)
			for i in n:
				var th := TAU * i / n
				pts.append(Vector2.from_angle(th) * a * (0.8 + 0.2 * cos(6.0 * th)))
		"trillion":
			# A triangle with gently bulging sides, a corner at +x.
			var per := maxi(4, segments / 3)
			for k in 3:
				var p0 := Vector2.from_angle(TAU / 3.0 * k) * a
				var p1 := Vector2.from_angle(TAU / 3.0 * (k + 1)) * a
				var out := Vector2.from_angle(TAU / 3.0 * k + PI / 3.0)
				for i in per:
					var t := float(i) / per
					pts.append(p0.lerp(p1, t) + out * a * 0.12 * sin(PI * t))
		"clover":
			# A four-leaf clover: a leaf along each axis, each with a little
			# notch at its tip so it reads as a heart, pinched between leaves.
			var n := maxi(segments, 64)
			for i in n:
				var th := TAU * i / n
				var u := fposmod(th + PI / 4.0, PI / 2.0) - PI / 4.0  # from the nearest leaf's middle
				var leaf := sqrt(maxf(cos(2.0 * u), 0.0))
				var notch := 0.14 * exp(-pow(u / 0.12, 2.0))
				pts.append(Vector2.from_angle(th) * a * (0.5 + 0.5 * leaf - notch))
		"pebble":
			# A river pebble: a soft, slightly squared egg, narrower toward +x.
			var raw := PackedVector2Array()
			var n := maxi(segments, 32)
			for i in n:
				var th := TAU * i / n
				var c := cos(th)
				var sn := sin(th)
				raw.append(Vector2(signf(c) * pow(absf(c), 0.9), signf(sn) * pow(absf(sn), 0.9) * 0.8 * (1.0 - 0.1 * c)))
			pts = _fit_circle(raw, a)
		"sunburst":
			# A sun of twelve short rays, one pointing along +x.
			for i in 24:
				pts.append(Vector2.from_angle(PI / 12.0 * i) * a * (1.0 if i % 2 == 0 else 0.8))
		"butterfly":
			# Seen from above, its head at +x: two big forewings, two smaller
			# hindwings (BUTTERFLY_WINGS, mirrored) and a slim body, traced as
			# far as each ray from the middle reaches into them.
			var raw := PackedVector2Array()
			var n := maxi(segments, 96)
			for i in n:
				var d := Vector2.from_angle(TAU * i / n)
				var r := _ellipse_reach(d, Vector2(0.12, 0.0), 0.0, Vector2(0.5, 0.1))
				for side: float in [1.0, -1.0]:
					for wing: Array in BUTTERFLY_WINGS:
						var center: Vector2 = Vector2.from_angle(deg_to_rad(wing[0])) * float(wing[1]) * Vector2(1.0, side)
						var axes := Vector2(float(wing[3]), float(wing[4]))
						r = maxf(r, _ellipse_reach(d, center, deg_to_rad(wing[2]) * side, axes))
				raw.append(d * r)
			pts = _fit_circle(raw, a)
		"heart":
			# The classic heart curve, its point at +x, centered and scaled to
			# fit the circle.
			var raw := PackedVector2Array()
			var n := maxi(segments, 40)
			for i in n:
				var t := TAU * i / n
				var hx := 16.0 * pow(sin(t), 3.0)
				var hy := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
				raw.append(Vector2(-hy, hx))
			pts = _fit_circle(raw, a)
		_:  # round, oval
			for i in segments:
				var th := TAU * i / segments
				pts.append(Vector2(a * cos(th), b * sin(th)))
	if shape in WIDTH_SCALED:
		var ratio := width / maxf(length, 0.001)
		for i in pts.size():
			pts[i].y *= ratio
	return pts


## How far a ray from the origin along unit `d` reaches through an ellipse
## centered at `c`, turned by `turn`, with half-axes `axes`: where it leaves
## it, or 0 if it misses.
static func _ellipse_reach(d: Vector2, c: Vector2, turn: float, axes: Vector2) -> float:
	var p := (-c).rotated(-turn) / axes
	var q := d.rotated(-turn) / axes
	var qa := q.dot(q)
	var qb := 2.0 * p.dot(q)
	var disc := qb * qb - 4.0 * qa * (p.dot(p) - 1.0)
	if disc < 0.0:
		return 0.0
	return maxf(0.0, (-qb + sqrt(disc)) / (2.0 * qa))


## Centers points on their bounding box and scales them to reach radius r.
static func _fit_circle(raw: PackedVector2Array, r: float) -> PackedVector2Array:
	var box := Rect2(raw[0], Vector2.ZERO)
	for p in raw:
		box = box.expand(p)
	var c := box.get_center()
	var reach := 0.0
	for p in raw:
		reach = maxf(reach, p.distance_to(c))
	var out := PackedVector2Array()
	for p in raw:
		out.append((p - c) / reach * r)
	return out


## Outline of a slot dictionary ({shape, x, y, rotation, size, width}) in
## picture coordinates.
static func slot_polygon(slot: Dictionary, segments: int = 24) -> PackedVector2Array:
	var local := outline(slot["shape"], slot["size"], slot["width"], segments)
	var xf := Transform2D(slot["rotation"], Vector2(slot["x"], slot["y"]))
	return xf * local


## The slot length that makes a `shape` drill `across` wide edge to edge in
## a kit's grid: squares draw smaller than their slot (SQUARE_SIDE).
static func drill_length(shape: String, across: float) -> float:
	return across / SQUARE_SIDE if shape == "square" else across

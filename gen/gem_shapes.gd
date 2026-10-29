class_name GemShapes
extends RefCounted
## Outline polygons for slot and gem shapes, in local space: the shape's long
## axis is +x (a teardrop points toward +x), centered on the origin.
## The real gem art (masks and normal maps) comes with the gem rendering
## milestone; these outlines draw slots and previews until then.
##
## Shapes that fit a circle of diameter `length` (`width` is ignored):
## round, square, hexagon, triangle, cushion, octagon, pentagon, heart,
## trillion, star, flower. Shapes that fit a capsule `length` long and
## `width` wide: oval, marquise, teardrop, kite, lozenge. Baguette and
## emerald fill the whole `length` x `width` box (only for gem lines).


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
			var s := a * 0.75
			pts = PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)])
		"hexagon":
			for i in 6:
				pts.append(Vector2.from_angle(PI / 3.0 * i) * a * 0.95)
		"triangle":
			# A corner at +x, so it mirrors onto itself across its axis.
			for i in 3:
				pts.append(Vector2.from_angle(TAU / 3.0 * i) * a)
		"emerald":
			# Step cut: a rectangle with its corners clipped.
			var c := b * 0.35
			pts = PackedVector2Array([Vector2(-a + c, -b), Vector2(a - c, -b), Vector2(a, -b + c), Vector2(a, b - c),
					Vector2(a - c, b), Vector2(-a + c, b), Vector2(-a, b - c), Vector2(-a, -b + c)])
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
	return pts


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

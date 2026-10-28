class_name GemShapes
extends RefCounted
## Outline polygons for slot and gem shapes, in local space: the shape's long
## axis is +x (a teardrop points toward +x), centered on the origin.
## The real gem art (masks and normal maps) comes with the gem rendering
## milestone; these outlines draw slots and previews until then.


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
			for i in 3:
				pts.append(Vector2.from_angle(TAU / 3.0 * i - PI / 2.0) * a)
		_:  # round, oval
			for i in segments:
				var th := TAU * i / segments
				pts.append(Vector2(a * cos(th), b * sin(th)))
	return pts


## Outline of a slot dictionary ({shape, x, y, rotation, size, width}) in
## picture coordinates.
static func slot_polygon(slot: Dictionary, segments: int = 24) -> PackedVector2Array:
	var local := outline(slot["shape"], slot["size"], slot["width"], segments)
	var xf := Transform2D(slot["rotation"], Vector2(slot["x"], slot["y"]))
	return xf * local

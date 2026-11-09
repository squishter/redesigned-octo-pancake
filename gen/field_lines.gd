class_name FieldLines
extends RefCounted
## Line art from scalar fields sampled on a square grid laid over unit space
## (x and y in -1..1, y down, `n` cells a side, sampled at cell centers):
## iso-lines (marching squares, from Contours), bilinear sampling, and
## clipping lines to where a test holds, so a clipped line ends exactly on
## the line that bounds it and every region stays closed.
##
## AnimalGenerator builds its pictures this way:
## shapes and coat markings are fields, and their outlines are iso-lines.

## Clipped lines run on past where they leave by this much (unit space), so
## their ends always reach the line they stop on once drawn.
const OVERSHOOT := 0.004
## Bisection steps when finding where a line leaves.
const BISECT := 10


## The unit-space center of cell `i` along an axis.
static func cell_center(i: int, n: int) -> float:
	return -1.0 + (i + 0.5) * 2.0 / n


## The cell an axis coordinate falls in (clamped to the grid).
static func cell_of(x: float, n: int) -> int:
	return clampi(floori((x + 1.0) * n * 0.5), 0, n - 1)


## The field at unit-space point `p`, bilinear between cell centers.
static func sample(field: PackedFloat32Array, n: int, p: Vector2) -> float:
	var gx := clampf((p.x + 1.0) * n * 0.5 - 0.5, 0.0, n - 1.001)
	var gy := clampf((p.y + 1.0) * n * 0.5 - 0.5, 0.0, n - 1.001)
	var x0 := int(gx)
	var y0 := int(gy)
	var fx := gx - x0
	var fy := gy - y0
	var i := y0 * n + x0
	var top := lerpf(field[i], field[i + 1], fx)
	var bottom := lerpf(field[i + n], field[i + n + 1], fx)
	return lerpf(top, bottom, fy)


## Iso-lines of `field` at `level` within `box` (cells), in unit space:
## [{"points", "closed"}], longer than `min_length`. Inside is >= level.
static func iso(field: PackedFloat32Array, n: int, level: float, box: Rect2i, min_length := 0.0) -> Array:
	var labels := PackedInt32Array()
	labels.resize(n * n)
	var found: Array = Contours.iso_lines(field, labels, n, n, 0, box, PackedFloat32Array([level]))[0]
	var out := []
	var k := 2.0 / n
	for line: Dictionary in found:
		var pts: PackedVector2Array = line["points"]
		for i in pts.size():
			pts[i] = pts[i] * k - Vector2.ONE
		if Contours.length(pts, line["closed"]) >= min_length:
			out.append({"points": pts, "closed": line["closed"]})
	return out


## The pieces of a line where `inside` (a Callable taking a unit-space point,
## returning bool) holds: [{"points", "closed"}]. A piece ends where the line
## leaves (found by bisection), run on by OVERSHOOT; a closed line that never
## leaves stays closed.
static func clip(pts: PackedVector2Array, is_closed: bool, inside: Callable) -> Array:
	var n := pts.size()
	if n < 2:
		return []
	var flags := PackedByteArray()
	flags.resize(n)
	var any_in := false
	var all_in := true
	for i in n:
		var ok: bool = inside.call(pts[i])
		flags[i] = 1 if ok else 0
		any_in = any_in or ok
		all_in = all_in and ok
	if all_in:
		return [{"points": pts, "closed": is_closed}]
	if not any_in:
		return []
	var out := []
	var run := PackedVector2Array()
	var start := 0
	var steps := n
	if is_closed:
		# Start just after a point outside, and go all the way round to it.
		while flags[start]:
			start += 1
		steps = n + 1
	for k in steps:
		var i := (start + k) % n
		if flags[i]:
			if run.is_empty() and (is_closed or k > 0):
				var prev := (start + k - 1 + n) % n
				run.append(_leave(pts[i], pts[prev], inside))
			run.append(pts[i])
		elif not run.is_empty():
			var last := (start + k - 1 + n) % n
			run.append(_leave(pts[last], pts[i], inside))
			out.append({"points": run, "closed": false})
			run = PackedVector2Array()
	if run.size() >= 2:
		out.append({"points": run, "closed": false})
	return out


## Where the segment from `a` (inside) to `b` (outside) leaves, run on past it.
static func _leave(a: Vector2, b: Vector2, inside: Callable) -> Vector2:
	var lo := a
	var hi := b
	for _i in BISECT:
		var mid := (lo + hi) * 0.5
		if inside.call(mid):
			lo = mid
		else:
			hi = mid
	var d := b - a
	return hi + (d.normalized() * OVERSHOOT if d.length_squared() > 0.0 else Vector2.ZERO)


## The piece (from clip) that passes nearest `p`.
static func nearest_piece(pieces: Array, p: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for piece: Dictionary in pieces:
		for q in piece["points"]:
			var d := p.distance_squared_to(q)
			if d < best_d:
				best_d = d
				best = piece
	return best

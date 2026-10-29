class_name Symmetry
extends RefCounted
## Geometry for keeping symmetric copies identical: the rotations about the
## picture's center and the reflections across lines through it that carry
## one region or line onto another (or a region onto itself). SlotPacker
## uses it for areas, GemLines for lines.
##
## A transform is {"xf": Transform2D, "turn", "axis", "mirrored"}: a
## rotation by `turn`, or a reflection across the line at angle `axis`.
## Every gem shape is symmetric about its own long axis, so a stone turned
## to angle a lands turned to a + turn, or to 2 * axis - a when mirrored.

## Most folds a ring is checked for.
const MAX_FOLDS := 32
## Share of a ring's samples that must land back on it under a symmetry.
const RING_MATCH := 0.97
## Samples a ring is checked with, at most.
const RING_SAMPLES := 1200


## The rotation by `turn` about o, or the reflection across the line through
## o at angle `axis`.
static func make(o: Vector2, turn: float, axis: float, mirrored: bool) -> Dictionary:
	var to_o := Transform2D(0.0, o)
	var m := Transform2D(turn, Vector2.ZERO)
	if mirrored:
		var d := Vector2.from_angle(axis)
		# Reflection across direction d: [[cos 2a, sin 2a], [sin 2a, -cos 2a]].
		m = Transform2D(Vector2(d.x * d.x - d.y * d.y, 2.0 * d.x * d.y), Vector2(2.0 * d.x * d.y, d.y * d.y - d.x * d.x),
				Vector2.ZERO)
	return {"xf": to_o * m * to_o.affine_inverse(), "turn": turn, "axis": axis, "mirrored": mirrored}


## A stone's rotation after transform t.
static func rotation(t: Dictionary, rot: float) -> float:
	return (2.0 * t["axis"] - rot) if t["mirrored"] else rot + t["turn"]


## The transforms that may carry something whose middle is at a onto
## something whose middle is at b: the rotation about o, then the reflection
## across the line halfway between them. None if either middle sits on o.
## With `sym` (a ring_symmetry of where they lie), the turn snaps to a whole
## number of its folds and the axis to one of its mirror axes, so middles
## found a pixel or two off still give the exact symmetry.
static func candidates(o: Vector2, a: Vector2, b: Vector2, side: float, sym: Dictionary = {}) -> Array:
	var da := a - o
	var db := b - o
	if da.length() < side * 0.01 or db.length() < side * 0.01:
		return []
	var turn := db.angle() - da.angle()
	var axis := (da.angle() + db.angle()) / 2.0
	if not sym.is_empty() and sym["folds"] < MAX_FOLDS:
		# Only small corrections: a few px where the middles are.
		var most := 3.0 / maxf(da.length(), db.length())
		var step: float = TAU / sym["folds"]
		var snapped := roundf(turn / step) * step
		if absf(snapped - turn) <= most:
			turn = snapped
		if not is_nan(sym["axis"]):
			snapped = sym["axis"] + roundf((axis - sym["axis"]) / (step / 2.0)) * step / 2.0
			if absf(snapped - axis) <= most / 2.0:
				axis = snapped
	return [make(o, turn, axis, false), make(o, turn, axis, true)]


## The transform that carries region src onto region dst (landing at least
## 92% of src's pixels inside dst), or {}.
static func region_transform(map: RegionMap, src: Dictionary, dst: Dictionary, o: Vector2) -> Dictionary:
	var tries := candidates(o, src["centroid"], dst["centroid"], minf(map.width, map.height))
	if tries.is_empty():
		return {}
	var pts := sample_pixels(map, src, 600)
	var best := {}
	var best_share := 0.92
	for t: Dictionary in tries:
		var share := landing_share(map, pts, t["xf"], dst["id"])
		if share >= best_share:
			best_share = share
			best = t
	return best


## The angle of a mirror axis through o that maps the region onto itself, or
## NAN. A region off the center can only mirror across the line through the
## center and its centroid; one around the center is tried across the
## vertical, the horizontal and its own axes.
static func self_axis(map: RegionMap, region: Dictionary, o: Vector2) -> float:
	var c: Vector2 = region["centroid"]
	var tries := []
	if c.distance_to(o) > minf(map.width, map.height) * 0.01:
		tries.append((c - o).angle())
	else:
		tries.append_array([PI / 2.0, 0.0, region["axis"], region["axis"] + PI / 2.0])
	var pts := sample_pixels(map, region, 600)
	for a: float in tries:
		if landing_share(map, pts, make(o, 0.0, a, true)["xf"], region["id"]) >= 0.95:
			return a
	return NAN


## The rotation nearest `rot` that a stone on a mirror axis at angle `axis`
## can take and still mirror onto itself: along the axis (either way), or
## across it for stones that are symmetric both ways.
static func axis_rotation(shape: String, rot: float, axis: float) -> float:
	var both_ways := shape in ["round", "oval", "marquise", "lozenge", "baguette", "emerald"]
	var best := axis
	for k in 4:
		if k % 2 == 1 and not both_ways:
			continue
		var a := axis + PI / 2.0 * k
		if absf(angle_difference(rot, a)) < absf(angle_difference(rot, best)):
			best = a
	return best


## Up to about n pixels of a region, on an even grid.
static func sample_pixels(map: RegionMap, region: Dictionary, n: int) -> PackedVector2Array:
	var bbox: Rect2i = region["bbox"]
	var step := maxi(1, int(sqrt(region["area"] / float(n))))
	var pts := PackedVector2Array()
	for y in range(bbox.position.y, bbox.end.y, step):
		for x in range(bbox.position.x, bbox.end.x, step):
			if map.labels[y * map.width + x] == region["id"]:
				pts.append(Vector2(x + 0.5, y + 0.5))
	return pts


## Share of the points that `xf` carries into region `id`, with a pixel of
## slack for rasterizing.
static func landing_share(map: RegionMap, pts: PackedVector2Array, xf: Transform2D, id: int) -> float:
	return _share(pts, xf, func(q: Vector2) -> bool: return map.label_at(int(q.x), int(q.y)) == id)


## The transform that carries centerline a onto centerline b (both
## {points, closed}, as from Contours.centerlines, of the lines in `map`):
## tried on their middles (snapped to `sym`, see candidates), and kept if
## all along a it lands on the lines. The two may differ a little in length
## where thinning put their junctions a few pixels apart. {} if none fits.
static func line_transform(a: Dictionary, b: Dictionary, o: Vector2, map: RegionMap, sym: Dictionary = {}) -> Dictionary:
	var pa: PackedVector2Array = a["points"]
	var la := Contours.length(pa, a["closed"])
	var lb := Contours.length(b["points"], b["closed"])
	if absf(la - lb) > maxf(3.0, 0.15 * la):
		return {}
	var on_line := func(q: Vector2) -> bool: return map.label_at(int(q.x), int(q.y)) == RegionMap.LINE
	var pts := PackedVector2Array()
	for i in 12:
		pts.append(Contours.sample(pa, a["closed"], la * (i + 0.5) / 12.0)[0])
	for t: Dictionary in candidates(o, line_middle(a), line_middle(b), minf(map.width, map.height), sym):
		if _share(pts, t["xf"], on_line, 1.0) >= 1.0:
			return t
	return {}


## A centerline's middle: halfway along it, or a loop's center.
static func line_middle(path: Dictionary) -> Vector2:
	var pts: PackedVector2Array = path["points"]
	if not path["closed"]:
		return Contours.sample(pts, false, Contours.length(pts, false) / 2.0)[0]
	var at := Vector2.ZERO
	for q in pts:
		at += q
	return at / pts.size()


## The symmetry of a ring around o (a loop around the picture's center, or a
## region around it), as sampled by `pts` with `lands(q)` telling whether q
## still falls on the same kind of thing: "folds", the largest k up to
## MAX_FOLDS for which a k-th of a turn lands nearly all of them (1 if none
## does), and "axis", the angle of a mirror axis through o (NAN if none).
## A ring of stones keeps the picture's symmetry when its count is a
## multiple of folds and its first stone sits on the axis.
static func ring_symmetry(pts: PackedVector2Array, o: Vector2, lands: Callable) -> Dictionary:
	if pts.size() > RING_SAMPLES:
		var few := PackedVector2Array()
		for i in RING_SAMPLES:
			few.append(pts[i * pts.size() / RING_SAMPLES])
		pts = few
	var folds := 1
	for k in range(MAX_FOLDS, 1, -1):
		if _share(pts, make(o, TAU / k, 0.0, false)["xf"], lands, RING_MATCH) >= RING_MATCH:
			folds = k
			break
	var axis := NAN
	var best := RING_MATCH
	var steps := 60
	for i in steps:
		var a := PI / folds * i / steps
		var share := _share(pts, make(o, 0.0, a, true)["xf"], lands, best)
		if share > best:
			best = share
			axis = a
	return {"folds": folds, "axis": axis}


## ring_symmetry of the lines around a ring: the line pixels of `map`
## (RegionMap.LINE) between r0 and r1 px from o.
static func ring_near(map: RegionMap, o: Vector2, r0: float, r1: float) -> Dictionary:
	r0 = maxf(0.0, r0)
	var box := Rect2i(Vector2i(o - Vector2(r1, r1)), Vector2i(ceili(r1 * 2.0) + 1, ceili(r1 * 2.0) + 1))
	box = box.intersection(Rect2i(0, 0, map.width, map.height))
	# About 1500 samples; lines cover roughly a sixth of a band.
	var band := PI * (r1 * r1 - r0 * r0) / 6.0
	var step := maxi(1, int(sqrt(band / 1500.0)))
	var pts := PackedVector2Array()
	for y in range(box.position.y, box.end.y, step):
		for x in range(box.position.x, box.end.x, step):
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(o)
			if d >= r0 and d <= r1 and map.labels[y * map.width + x] == RegionMap.LINE:
				pts.append(p)
	return ring_symmetry(pts, o, func(q: Vector2) -> bool: return map.label_at(int(q.x), int(q.y)) == RegionMap.LINE)


## Share of the points that `xf` carries to where `lands` is true, with a
## pixel of slack; 0 as soon as it can't reach `need`.
static func _share(pts: PackedVector2Array, xf: Transform2D, lands: Callable, need := 0.0) -> float:
	var hits := 0
	var misses_left := int((1.0 - need) * pts.size())
	for p in pts:
		var q := xf * p
		var hit := false
		for off: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			if lands.call(q + off):
				hit = true
				break
		if hit:
			hits += 1
		elif need > 0.0:
			misses_left -= 1
			if misses_left < 0:
				return 0.0
	return float(hits) / maxi(1, pts.size())


## Count and start for `n` stones evenly spaced around a ring with
## ring_symmetry `sym`: n rounded down to a multiple of its folds (twice
## them when there's room, so alternating stones line up too; a divisor of
## them when there are fewer; any count when the ring is round all the way,
## at MAX_FOLDS), and the arc length along pts where the first one goes (on
## the mirror axis).
static func ring_layout(n: int, sym: Dictionary, pts: PackedVector2Array, o: Vector2) -> Array:
	var folds: int = sym["folds"]
	var step := folds * 2 if n >= folds * 2 else folds
	if folds < MAX_FOLDS:
		if n >= step:
			n = n / step * step
		else:
			# Too few for every fold: the most that still divide them evenly.
			while n > 1 and folds % n != 0:
				n -= 1
	var start := 0.0
	if not is_nan(sym["axis"]):
		var dir := Vector2.from_angle(sym["axis"])
		var best := INF
		var s := 0.0
		for i in pts.size():
			var a := pts[i]
			var off := a - o
			# Closest to the axis on the side it points to.
			var miss := absf(off.cross(dir)) - (off.dot(dir) * 0.001)
			if off.dot(dir) > 0.0 and miss < best:
				best = miss
				start = s
			s += a.distance_to(pts[(i + 1) % pts.size()])
	return [n, start]

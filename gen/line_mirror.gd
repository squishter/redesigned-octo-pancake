class_name LineMirror
extends RefCounted
## Makes gem-line stones exactly as symmetric as the line art they follow.
##
## The stones are laid along centerlines thinned from the rasterized line
## art, and thinning traces small curly shapes a pixel or two differently on
## every copy, so stones (and the channels carved around them, and so the
## areas between) drift apart. Here the picture is cut into bands around the
## center; each band takes its symmetry from the line art itself (see
## Symmetry.ring_symmetry: its folds and mirror axis), keeps the stones of
## one wedge and repeats them around. Stones on a mirror axis snap onto it,
## and a stone and its copies shrink alike to clear what is already there
## (or are left out together). Mirror pictures use the vertical axis.
## Bands whose lines are only circles keep their stones as laid.

## Band width, in line stones.
const BAND := 4.0
## Most line-art samples a band's symmetry is read from.
const SAMPLES := 1500


## stones: GemLines slots, in placing order (junctions first). mask: the line
## art (w x h, nonzero on lines). r, gap, cell: as in GemLines.place.
## tight: {class: share of the gap} for dense classes of lines, whose stones
## keep that smaller gap (see GemLines.DENSE_GAP).
## Returns the symmetric stones, renumbered.
static func apply(stones: Array[Dictionary], mask: PackedByteArray, w: int, h: int, symmetry: String, r: float,
		gap: float, cell: float, tight: Dictionary = {}) -> Array[Dictionary]:
	if symmetry == "none" or stones.is_empty():
		return stones
	var o := Vector2(w, h) / 2.0
	var line_px := _line_pixels(mask, w, h, o)
	var lands := func(q: Vector2) -> bool:
		return q.x >= 0.0 and q.y >= 0.0 and q.x < w and q.y < h and mask[int(q.y) * w + int(q.x)] != 0
	var band_w := maxf(8.0, r * BAND)
	var bands := {}
	var out: Array[Dictionary] = []
	var hash := {}
	for s: Dictionary in stones:
		var c := Vector2(s["x"], s["y"])
		var sym: Dictionary
		if symmetry == "mirror":
			sym = {"folds": 1, "axis": PI / 2.0}
		else:
			var b := floori(c.distance_to(o) / band_w)
			if not bands.has(b):
				bands[b] = _band_symmetry(line_px, o, b * band_w, (b + 1) * band_w, r, lands)
			sym = bands[b]
		var rr: float = s["width"] / 2.0
		var hh: float = s["size"] / 2.0 - rr
		var g: float = gap * tight.get(s["part"], 1.0)
		if sym["folds"] >= Symmetry.MAX_FOLDS or (sym["folds"] <= 1 and is_nan(sym["axis"])):
			_place(out, hash, cell, g, s, [c], [float(s["rotation"])], rr, hh)
			continue
		var kept := _keep(s, c, o, sym, rr, hh, g)
		if kept.is_empty():
			continue
		c = kept[0]
		var rot: float = kept[1]
		var at := []
		var turns := []
		for t: Dictionary in _group(o, sym):
			var q: Vector2 = t["xf"] * c
			var seen := false
			for p: Vector2 in at:
				if p.distance_to(q) < 1.0:
					seen = true
					break
			if not seen:
				at.append(q)
				turns.append(Symmetry.rotation(t, rot))
		_place(out, hash, cell, g, s, at, turns, rr, hh)
	for i in out.size():
		out[i]["id"] = i
	return out


## Pixels of the line art (every other one each way), by distance from the
## center, nearest first: [distances, points].
static func _line_pixels(mask: PackedByteArray, w: int, h: int, o: Vector2) -> Array:
	var pairs := []
	# Every other pixel each way is plenty.
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			if mask[y * w + x] != 0:
				var p := Vector2(x + 0.5, y + 0.5)
				pairs.append([p.distance_to(o), p])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var dist := PackedFloat32Array()
	var pts := PackedVector2Array()
	for e: Array in pairs:
		dist.append(e[0])
		pts.append(e[1])
	return [dist, pts]


## Folds and mirror axis of the line art in a band (widened until it shows
## more than circles), or MAX_FOLDS when it never does.
static func _band_symmetry(line_px: Array, o: Vector2, lo: float, hi: float, r: float, lands: Callable) -> Dictionary:
	var dist: PackedFloat32Array = line_px[0]
	var pts: PackedVector2Array = line_px[1]
	var sym := {"folds": Symmetry.MAX_FOLDS, "axis": NAN}
	for margin in [r * 3.0, r * 6.0, r * 12.0]:
		var a := dist.bsearch(maxf(0.0, lo - margin))
		var b := dist.bsearch(hi + margin, false)
		if b - a < 20:
			continue
		var few := PackedVector2Array()
		var n := mini(SAMPLES, b - a)
		for i in n:
			few.append(pts[a + i * (b - a) / n])
		sym = Symmetry.ring_symmetry(few, o, lands)
		if sym["folds"] < Symmetry.MAX_FOLDS:
			break
	return sym


## The stone moved into the kept wedge, as [center, rotation], or [] when it
## lies in another wedge (its copies from the kept one take its place).
## The kept wedge runs from the mirror axis (or angle 0) one wedge around;
## stones on its mirror edges (or straddling them) snap onto them, and
## stones at the center onto it.
static func _keep(s: Dictionary, c: Vector2, o: Vector2, sym: Dictionary, r: float, h: float, gap: float) -> Array:
	var rot: float = s["rotation"]
	var shape: String = s["shape"]
	var mirrored := not is_nan(sym["axis"])
	var folds: int = maxi(1, sym["folds"])
	var wedge := (PI if mirrored else TAU) / folds
	var base: float = sym["axis"] if mirrored else 0.0
	var off := c - o
	var reach := r + h
	if off.length() < maxf(1.0, reach * 0.6):
		return [o, Symmetry.axis_rotation(shape, rot, base) if mirrored else rot]
	if mirrored:
		for e: float in [base, base + wedge]:
			var dir := Vector2.from_angle(e)
			var d := absf(off.cross(dir))
			if off.dot(dir) > 0.0 and (d <= maxf(1.0, r * 0.25) or (d - gap / 2.0) / reach < 0.6):
				return [o + dir * off.dot(dir), Symmetry.axis_rotation(shape, rot, e)]
	if fposmod(off.angle() - base, TAU) < wedge:
		return [c, rot]
	return []


## The band's symmetries: its turns about o, and as many reflections when it
## has a mirror axis.
static func _group(o: Vector2, sym: Dictionary) -> Array:
	var folds: int = maxi(1, sym["folds"])
	var out := []
	for j in folds:
		out.append(Symmetry.make(o, TAU * j / folds, 0.0, false))
	if not is_nan(sym["axis"]):
		for j in folds:
			out.append(Symmetry.make(o, 0.0, sym["axis"] + PI * j / folds, true))
	return out


## Places a stone's copies (centers `at`, rotations `turns`), all shrunk
## alike to clear the stones already placed and each other, or none if
## that leaves them under 55% of their size.
static func _place(out: Array[Dictionary], hash: Dictionary, cell: float, gap: float, s: Dictionary, at: Array,
		turns: Array, r: float, h: float) -> void:
	var k := 1.0
	for i in at.size():
		k = minf(k, room_at(hash, cell, gap, at[i], turns[i], h) / r)
		for j in i:
			var d: float = (at[i] as Vector2).distance_to(at[j])
			if d < 2.0 * (r + h) + gap:
				k = minf(k, (d - gap) / (2.0 * (r + h)))
	if k < 0.55 or r * k < 1.5:
		return
	for i in at.size():
		var slot := s.duplicate()
		slot["x"] = (at[i] as Vector2).x
		slot["y"] = (at[i] as Vector2).y
		slot["rotation"] = wrapf(turns[i], -PI, PI)
		slot["width"] = 2.0 * r * k
		slot["size"] = 2.0 * (r + h) * k
		out.append(slot)
		var key := Vector2i(floori(slot["x"] / cell), floori(slot["y"] / cell))
		if not hash.has(key):
			hash[key] = []
		hash[key].append(slot)


## Room for a stone (a capsule: center c, rotation rot, half-length h) among
## the stones placed so far: the distance to the nearest one, less the gap.
static func room_at(hash: Dictionary, cell: float, gap: float, c: Vector2, rot: float, h: float) -> float:
	var dir := Vector2.from_angle(rot)
	var cx := floori(c.x / cell)
	var cy := floori(c.y / cell)
	var room := INF
	for yy in range(cy - 1, cy + 2):
		for xx in range(cx - 1, cx + 2):
			for s: Dictionary in hash.get(Vector2i(xx, yy), []):
				var sr: float = s["width"] / 2.0
				var sh: float = s["size"] / 2.0 - sr
				var sc := Vector2(s["x"], s["y"])
				var sd := Vector2.from_angle(s["rotation"]) * sh
				var pts := Geometry2D.get_closest_points_between_segments(c - dir * h, c + dir * h, sc - sd, sc + sd)
				room = minf(room, pts[0].distance_to(pts[1]) - sr - gap)
	return room

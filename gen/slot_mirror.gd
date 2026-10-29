class_name SlotMirror
extends RefCounted
## Keeps SlotPacker's patterns symmetric where the picture is:
##
##   copy_region: a region that is a rotated or mirrored copy of one already
##     packed gets that one's stones, carried over stone for stone, instead
##     of a pattern packed on its own (which lands differently on every copy);
##   symmetrize: a region that maps onto itself (a petal or a band between
##     two rays across its mirror axis, a ring around the center under its
##     turns too) gets a pattern just as symmetric.
##
## Both work on the packer's current region through its free field (see
## SlotPacker), and the geometry comes from Symmetry.


## Copies the master's stones ({region, slots}) onto `region`, a symmetric
## copy of it (see Symmetry.region_transform). Stones shrink a little where
## the copy's edge is a pixel closer. Returns false (placing nothing) when
## no transform fits or too many stones would be lost.
static func copy_region(p: SlotPacker, region: Dictionary, master: Dictionary) -> bool:
	var src: Dictionary = master["region"]
	var area_ratio: float = float(region["area"]) / src["area"]
	if area_ratio < 0.9 or area_ratio > 1.1:
		return false
	var t := Symmetry.region_transform(p.map, src, region, p._pic_center)
	if t.is_empty():
		return false
	var xf: Transform2D = t["xf"]
	# Where each stone lands, and how much it must shrink to stay inside.
	var moved := []
	var lost := 0
	for s: Dictionary in master["slots"]:
		var c: Vector2 = xf * Vector2(s["x"], s["y"])
		var rot := Symmetry.rotation(t, s["rotation"])
		var r: float = s["width"] / 2.0
		var h: float = s["size"] / 2.0 - r
		var k := minf(1.0, (p._edge_room(c, Vector2.from_angle(rot), h, region["id"]) - p.gap) / r)
		if k < 0.6:
			lost += 1
			continue
		moved.append([s, c, rot, r * k, h * k])
	if lost > maxi(1, master["slots"].size() / 50):
		return false
	p._begin_region(region)
	region["style"] = src.get("style", "")
	for m in moved:
		var s: Dictionary = m[0]
		p._tone = s["tone"]
		p._part = s["part"]
		p._place(s["shape"], m[1], m[2], m[3], m[4])
	p._tone = 0
	return true


## Makes the current region's pattern (its slots from `first` on) as
## symmetric as the region: `folds` turns about the picture's center map it
## onto itself, and so does a reflection across `axis` (an angle through the
## center; NAN if none). The stones in one wedge (between two mirror axes,
## or one turn's worth) stay and are repeated around; stones on a mirror
## axis snap onto it, and copies that would touch shrink apart. With `fill`
## (full patterns), gaps the seams leave are then filled the same way. If
## that loses too much (the region is only roughly symmetric), the pattern
## stays as it was packed.
static func symmetrize(p: SlotPacker, region: Dictionary, first: int, fill: bool, folds: int, axis: float) -> void:
	var mirrored := not is_nan(axis)
	if p.slots.size() <= first or (folds <= 1 and not mirrored):
		return
	var o := p._pic_center
	var group := _group(o, folds, axis)
	var placed := p.slots.slice(first)
	p.slots.resize(first)
	var biggest: Dictionary = placed[0]
	var last_part := 0
	for s: Dictionary in placed:
		if s["width"] * s["size"] > biggest["width"] * biggest["size"]:
			biggest = s
		last_part = maxi(last_part, s["part"])
	# Wedges start on a mirror axis, or else with the biggest stone in the
	# middle of one; the wedge holding the most stone area stays.
	var wedge := (PI if mirrored else TAU) / folds
	var base := axis if mirrored else (Vector2(biggest["x"], biggest["y"]) - o).angle() - wedge / 2.0
	var area_in := PackedFloat32Array()
	area_in.resize(roundi(TAU / wedge))
	for s: Dictionary in placed:
		area_in[_wedge_of(Vector2(s["x"], s["y"]) - o, base, wedge, area_in.size())] += s["width"] * s["size"]
	var keep := 0
	for j in area_in.size():
		if area_in[j] > area_in[keep]:
			keep = j
	var edges := [base + wedge * keep, base + wedge * (keep + 1)]
	p._reset_free(region)
	for s: Dictionary in placed:
		var c := Vector2(s["x"], s["y"])
		var r: float = s["width"] / 2.0
		var h: float = s["size"] / 2.0 - r
		var rot: float = s["rotation"]
		var shape: String = s["shape"]
		var on := maxf(1.0, r * 0.25)
		var inside := _wedge_of(c - o, base, wedge, area_in.size()) == keep
		var snapped := false
		if (c - o).length() < maxf(on, (r + h) * 0.6):
			# At the center: one stone there.
			c = o
			rot = Symmetry.axis_rotation(shape, rot, axis if mirrored else rot)
			snapped = true
		elif mirrored:
			# On a mirror edge of the wedge (or straddling it): onto it.
			for e: float in edges:
				var dir := Vector2.from_angle(e)
				var d := absf((c - o).cross(dir))
				if (c - o).dot(dir) > 0.0 and (d <= on or (d - p.gap / 2.0) / (r + h) < 0.6):
					c = o + dir * (c - o).dot(dir)
					rot = Symmetry.axis_rotation(shape, rot, e)
					snapped = true
					break
		if not inside and not snapped:
			continue  # another wedge: the copies of this one take its place
		p._tone = s["tone"]
		p._part = s["part"]
		_place_orbit(p, group, shape, c, rot, r, h)
	p._tone = 0
	p._part = last_part
	if fill:
		var u := p.unit
		var biggest_r: float = biggest["width"] / 2.0
		_fill(p, [minf(u * 0.8, biggest_r), minf(u * 0.6, biggest_r), u * SlotPacker.MIN_STONE], group)
	if _stone_area(p.slots.slice(first)) < 0.6 * _stone_area(placed):
		p.slots.resize(first)
		p._reset_free(region)
		for s: Dictionary in placed:
			p._tone = s["tone"]
			p._part = s["part"]
			var r: float = s["width"] / 2.0
			p._place(s["shape"], Vector2(s["x"], s["y"]), s["rotation"], r, s["size"] / 2.0 - r)
		p._tone = 0


## The symmetries: `folds` turns about o, and as many reflections when
## there is a mirror axis.
static func _group(o: Vector2, folds: int, axis: float) -> Array:
	var out := []
	for j in folds:
		out.append(Symmetry.make(o, TAU * j / folds, 0.0, false))
	if not is_nan(axis):
		for j in folds:
			out.append(Symmetry.make(o, 0.0, axis + PI * j / folds, true))
	return out


## Which of n wedges (each `wedge` wide, the first starting at angle base)
## the offset from the center points into.
static func _wedge_of(off: Vector2, base: float, wedge: float, n: int) -> int:
	if off.is_zero_approx():
		return 0
	return clampi(floori(fposmod(off.angle() - base, TAU) / wedge), 0, n - 1)


## Places a stone and all its images under `group` (images that coincide,
## for a stone on an axis or at the center, count once), all shrunk alike
## to clear each other and fit where they land; none if that's too small.
## Returns whether they were placed.
static func _place_orbit(p: SlotPacker, group: Array, shape: String, c: Vector2, rot: float, r: float,
		h: float) -> bool:
	var at := PackedVector2Array()
	var turns := PackedFloat32Array()
	for t: Dictionary in group:
		var q: Vector2 = t["xf"] * c
		var seen := false
		for a in at:
			if a.distance_to(q) < 1.0:
				seen = true
				break
		if not seen:
			at.append(q)
			turns.append(Symmetry.rotation(t, rot))
	var k := 1.0
	for i in at.size():
		k = minf(k, (p._room(at[i], Vector2.from_angle(turns[i]), h) - p.gap) / r)
		for j in i:
			var d := at[i].distance_to(at[j])
			if d < 2.0 * (r + h) + p.gap:
				k = minf(k, (d - p.gap) / (2.0 * (r + h)))
	if not _shrunk_ok(p, r, k):
		return false
	for i in at.size():
		p._place(shape, at[i], turns[i], r * k, h * k)
	return true


## Fills what is left, biggest stones first, a stone and its images under
## `group` at a time.
static func _fill(p: SlotPacker, sizes: Array, group: Array) -> void:
	p._part += 1
	var r_min: float = sizes[-1]
	while true:
		var peak := p._argmax()
		if peak < 0:
			return
		p._cur_max = p.free[peak]
		var avail := p.free[peak] - p.gap
		if avail < r_min:
			return
		var r := r_min
		for s: float in sizes:
			if s <= avail:
				r = s
				break
		var c := _snap(p, group, p._center(peak), r)
		if not _place_orbit(p, group, "round", c, 0.0, r, 0.0):
			# Nothing fits here symmetrically: rule the spot out.
			p._stamp(c, Vector2.RIGHT, 0.0, avail)


## A spot moved onto the center or a mirror axis when a stone of radius r
## there would touch its own image across it.
static func _snap(p: SlotPacker, group: Array, c: Vector2, r: float) -> Vector2:
	var off := c - p._pic_center
	if off.length() < r:
		return p._pic_center
	for t: Dictionary in group:
		if t["mirrored"]:
			var dir := Vector2.from_angle(t["axis"])
			if off.dot(dir) > 0.0 and absf(off.cross(dir)) < r + p.gap / 2.0:
				return p._pic_center + dir * off.dot(dir)
	return c


## True if a stone of radius r shrunk by k is still worth placing.
static func _shrunk_ok(p: SlotPacker, r: float, k: float) -> bool:
	return k >= 0.5 and r * k >= p.unit * SlotPacker.MIN_STONE * 0.75


static func _stone_area(stones: Array) -> float:
	var total := 0.0
	for s: Dictionary in stones:
		total += s["width"] * s["size"]
	return total

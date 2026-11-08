class_name AnimalPrintGenerator
extends RefCounted
## Seeded animal prints: a coat's markings (CoatPatterns.PRINTS: tiger,
## zebra, cow, pinto, dalmatian, cheetah, leopard, giraffe, dapple) all over
## a board, a circle or a lopsided blob. Stripes flow in a direction of their
## own, bending as they go. Sometimes a sweeping curve splits the picture
## between two prints (tiger meets leopard). Nothing is symmetric.
##
## Each side's markings and plain coat are families (see SwirlGenerator), so
## a collage gives all of one print's spots one pattern and colors.
##
## Output matches MandalaGenerator: polylines in unit space (-1..1, y down),
## plus "families", "family_names" and "marks".

const SHAPES := ["board", "round", "blob"]
const SPLIT_CHANCE := 0.4
## Prints used by this many previous prints in a row are skipped.
const AVOID_RECENT := 3
const N := 320
const REACH := 0.95
## Patchy coats are made for a whole animal; a print shows more of them.
const PATCH_ZOOM := {"pinto": 2.2, "cow": 1.5}

var rng := RandomNumberGenerator.new()
var polylines: Array[PackedVector2Array] = []
var closed := PackedByteArray()
var families := PackedInt32Array()
var family_names := PackedStringArray()
var marks := []

var _shape := "board"
## A blob's radius: harmonics [amplitude, frequency, phase].
var _wobble := []
## The split: a curve across the picture in a turned frame, [angle, offset,
## amplitude, frequency, phase]; empty for none.
var _split := []
## Per side: {"coat": CoatPatterns, "angle", "bend", "zoom", "field"}.
var _sides := []


## options:
##   coat: one of CoatPatterns.PRINTS, or "random" (default)
##   coat2: the other side's print when split
##   shape: one of SHAPES, or "random"
##   split: true / false, or omit for a chance of SPLIT_CHANCE
##   recent: Array of earlier results' {"coats"}; recent prints are skipped
## Returns {"seed", "coats" (one or two), "shape", "split", "angle" (the
## first print's flow, degrees), "polylines", "closed", "families",
## "family_names", "marks"}.
static func generate(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var g := AnimalPrintGenerator.new()
	g.rng.seed = seed_value
	var used := []
	for r in options.get("recent", []):
		if r is Dictionary:
			used.append_array(r.get("coats", []))
	var shape: String = options.get("shape", "random")
	if not shape in SHAPES:
		shape = SHAPES[g.rng.randi_range(0, SHAPES.size() - 1)]
	var split: bool = options.get("split", g.rng.randf() < SPLIT_CHANCE)
	var coats := []
	for key: String in (["coat", "coat2"] if split else ["coat"]):
		var c: String = options.get(key, "random")
		if not c in CoatPatterns.PRINTS or c in coats:
			var left := CoatPatterns.PRINTS.filter(func(p: String) -> bool: return not p in coats)
			c = g._least_used(left, used + coats, AVOID_RECENT)
		coats.append(c)
	g._shape = shape
	g._build_outline()
	if split:
		g._split = [g.rng.randf() * TAU, g.rng.randf_range(-0.25, 0.25), g.rng.randf_range(0.1, 0.25),
				g.rng.randf_range(1.5, 3.0), g.rng.randf() * TAU]
	for i in coats.size():
		g._sides.append(g._make_side(coats[i], seed_value + 101 * i))
	g._fields()
	g._draw()
	g._mark()
	return {
		"seed": seed_value,
		"coats": coats,
		"shape": shape,
		"split": split,
		"angle": int(round(rad_to_deg(g._sides[0]["angle"]))),
		"polylines": g.polylines,
		"closed": g.closed,
		"families": g.families,
		"family_names": g.family_names,
		"marks": g.marks,
	}


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


func _make_side(coat: String, seed_value: int) -> Dictionary:
	# zoom: coat-space units per unit, so the print shows 6-10 stripes or a
	# few dozen spots across: bold enough for gems.
	var zoom: float = rng.randf_range(0.48, 0.68) * PATCH_ZOOM.get(coat, 1.0)
	return {
		"coat": CoatPatterns.make(coat, seed_value, Rect2(Vector2(-1.2, -1.2) * zoom, Vector2(2.4, 2.4) * zoom)),
		"angle": rng.randf() * TAU,
		"bend": [rng.randf_range(0.05, 0.2), rng.randf_range(1.0, 3.0), rng.randf() * TAU],
		"taper": [rng.randf_range(0.6, 1.6), rng.randf() * TAU],
		"zoom": zoom,
		"seed": seed_value,
		"field": PackedFloat32Array(),
	}


func _build_outline() -> void:
	if _shape == "blob":
		for _k in 3:
			_wobble.append([rng.randf_range(0.03, 0.08), rng.randi_range(2, 5), rng.randf() * TAU])
	var pts := PackedVector2Array()
	match _shape:
		"round":
			pts = MandalaGenerator.circle(Vector2.ZERO, REACH, 240)
		"blob":
			for i in 240:
				var t := TAU * i / 240.0
				pts.append(Vector2.from_angle(t) * _radius_at(t))
		_:
			for k in 4:
				var a := Vector2(-REACH, -REACH).rotated(PI / 2.0 * k)
				var b := Vector2(-REACH, -REACH).rotated(PI / 2.0 * (k + 1))
				for i in 60:
					pts.append(a.lerp(b, i / 60.0))
	_add(pts, true, "outline")


func _radius_at(t: float) -> float:
	var r := REACH * 0.88
	for h: Array in _wobble:
		r += h[0] * sin(h[1] * t + h[2])
	return minf(r, REACH)


func _inside(p: Vector2) -> bool:
	match _shape:
		"round":
			return p.length() < REACH
		"blob":
			return p.length() < _radius_at(p.angle())
	return absf(p.x) < REACH and absf(p.y) < REACH


## Which side of the split p is on: 0, or 1 past the curve.
func _side(p: Vector2) -> int:
	if _split.is_empty():
		return 0
	var q := p.rotated(-_split[0])
	return 1 if q.y > _split[1] + _split[2] * sin(q.x * _split[3] + _split[4]) else 0


## Each side's coat on the grid; a coat whose markings miss its side (or
## cover it) tries again with another seed.
func _fields() -> void:
	for s in _sides.size():
		var side: Dictionary = _sides[s]
		for attempt in 5:
			if attempt > 0:
				var coat: CoatPatterns = side["coat"]
				var zoom: float = side["zoom"]
				side["coat"] = CoatPatterns.make(coat.coat, side["seed"] + 7919 * attempt,
						Rect2(Vector2(-1.2, -1.2) * zoom, Vector2(2.4, 2.4) * zoom))
			var coverage := _side_field(side, s)
			if coverage > 0.04 and coverage < 0.85:
				break


## One side's coat on the grid; returns the share of its side inside the
## markings.
func _side_field(side: Dictionary, index: int) -> float:
	var step := 2.0 / N
	var inside := 0
	var marked := 0
	var coat: CoatPatterns = side["coat"]
	var f := PackedFloat32Array()
	f.resize(N * N)
	var zoom: float = side["zoom"]
	var turn: float = side["angle"]
	var bend: Array = side["bend"]
	var taper: Array = side["taper"]
	for cy in N:
		for cx in N:
			var p := Vector2(-1.0 + (cx + 0.5) * step, -1.0 + (cy + 0.5) * step)
			var q := p.rotated(-turn)
			# Stripes flow across q.x, bending as they go; v makes some
			# bands of them thin out.
			var phi: float = (q.x + bend[0] * sin(q.y * bend[1] + bend[2])) * zoom
			var v: float = sin(q.y * taper[0] + taper[1])
			var value := coat.value(p * zoom, phi, v)
			f[cy * N + cx] = value
			if (cx + cy) % 3 == 0 and _inside(p) and _side(p) == index:
				inside += 1
				if value > 0.0:
					marked += 1
	side["field"] = f
	return marked / float(maxi(1, inside))


func _family(name: String) -> int:
	var id := family_names.find(name)
	if id < 0:
		id = family_names.size()
		family_names.append(name)
	return id


func _add(pts: PackedVector2Array, is_closed: bool, family: String) -> void:
	if pts.size() < 2:
		return
	polylines.append(pts)
	closed.append(1 if is_closed else 0)
	families.append(_family(family))


func _draw() -> void:
	var box := Rect2i(0, 0, N, N)
	if not _split.is_empty():
		var curve := PackedVector2Array()
		for i in 161:
			var x := -1.5 + 3.0 * i / 160.0
			var q := Vector2(x, _split[1] + _split[2] * sin(x * _split[3] + _split[4]))
			curve.append(q.rotated(_split[0]))
		for piece: Dictionary in FieldLines.clip(curve, false, _inside):
			_add(piece["points"], false, "split")
	for s in _sides.size():
		var side_i := s
		var inside := func(p: Vector2) -> bool: return _inside(p) and _side(p) == side_i
		for line: Dictionary in FieldLines.iso(_sides[s]["field"], N, 0.0, box, 0.03):
			for piece: Dictionary in FieldLines.clip(line["points"], line["closed"], inside):
				_add(piece["points"], piece["closed"], "markings_%d" % s)


func _area_at(p: Vector2) -> String:
	if not _inside(p):
		return ""
	var s := _side(p)
	var inside: bool = FieldLines.sample(_sides[s]["field"], N, p) > 0.0
	return ("markings_%d" if inside else "coat_%d") % s


func _mark() -> void:
	# A lattice over the picture; a point is marked when its neighbors are
	# in the same area (so it's clear of every line), loosely spaced first,
	# then a tighter look for thin areas (slivers along the edge).
	for pass_i in 2:
		var stride := 4 if pass_i == 0 else 2
		var reach := 0.022 if pass_i == 0 else 0.0085
		var around := []
		for k in 8:
			around.append(Vector2.from_angle(TAU * k / 8.0) * reach)
		var taken := {}
		for cy in range(stride / 2, N, stride):
			for cx in range(stride / 2, N, stride):
				var p := Vector2(FieldLines.cell_center(cx, N), FieldLines.cell_center(cy, N))
				var area := _area_at(p)
				if area == "" or (pass_i == 1 and taken.has([cx / 8, cy / 8, area])):
					continue
				var ok := true
				for d: Vector2 in around:
					if _area_at(p + d) != area:
						ok = false
						break
				if ok:
					taken[[cx / 8, cy / 8, area]] = true
					marks.append({"at": p, "family": _family(area)})
	# Small markings the lattice missed: spot centers and the like.
	for s in _sides.size():
		var coat: CoatPatterns = _sides[s]["coat"]
		var zoom: float = _sides[s]["zoom"]
		for a in coat.mark_points():
			var p := a / zoom
			if _area_at(p) == "markings_%d" % s:
				marks.append({"at": p, "family": _family("markings_%d" % s)})

class_name SnowflakeGenerator
extends RefCounted
## Seeded snowflakes that differ in their center, arms, tips, what fills the
## space between the arms and their inner details, so snowflakes look clearly
## different from each other.
##
## One arm (along +x) and one wedge of in-between content (at +30 degrees)
## are built, then rotated six times. Shapes come in two kinds:
##   merged: arm cores, branches, spikes, webs, the stellar plate. Their
##       outlines only show where no other shape covers them, so together
##       they draw one clean silhouette.
##   features: the center, plates, tips, petals, floating diamonds and dots.
##       Their outlines are always drawn (unless an earlier feature covers
##       them), so they split the silhouette into regions.
## Details (ribs, dots, inner outlines) are drawn inside, stopping at the
## lines around them, so every region stays closed.
##
## Output matches MandalaGenerator: polylines in unit space (-1..1, y down).

## hexagon; nested (an inner hexagon turned 30 degrees); star (a 12-point
## star); rosette (a ring of lenses around a circle); spoked (spokes between
## two hexagons); flower (six lens petals around a circle).
const CENTERS := ["hexagon", "nested", "star", "rosette", "spoked", "flower"]
## plain; branched (2-3 pairs of side branches); fern (4-5 pairs of short
## ones); plates (hexagonal plates along the arm); arrows (chevrons along the
## arm); spear (a diamond along the arm); crystal (a wide, faceted arm).
const ARMS := ["plain", "branched", "fern", "plates", "arrows", "spear", "crystal"]
const TIPS := ["point", "plate", "diamond", "fork", "ring"]
## What fills the space between the arms: a stellar plate joining them, web
## bars bridging them, short spikes, petals, floating diamonds or dots. Most
## snowflakes get one or two; NONE_CHANCE get none.
const BETWEEN := ["plate", "webs", "spikes", "petals", "diamonds", "dots"]
const NONE_CHANCE := 0.08
## In-between content that can't be combined.
const CLASHES := [["plate", "webs"], ["plate", "petals"], ["spikes", "petals"], ["diamonds", "dots"],
		["webs", "spikes"]]
## Arms whose side branches already fill the space spikes and petals need.
const BRANCHY := ["branched", "fern"]
## ribs: lines along every arm and branch; dots: small circles in plates and
## diamonds; inner: inner outlines of plates, tips, petals and crystal arms.
const DETAILS := ["ribs", "dots", "inner"]
## How many details a snowflake gets, picked evenly from this list.
const DETAIL_COUNTS := [0, 1, 1, 2]
## Centers, arms, tips and in-between content used by this many previous
## snowflakes in a row are skipped (details skip only the last one).
const AVOID_RECENT := 2
const TIP_R := 1.0

var rng := RandomNumberGenerator.new()
var polylines: Array[PackedVector2Array] = []
var closed := PackedByteArray()

var _merged: Array[PackedVector2Array] = []
var _merged_boxes: Array[Rect2] = []
var _features: Array[PackedVector2Array] = []
var _features_boxes: Array[Rect2] = []
var _holes: Array[PackedVector2Array] = []
## What the current clip tests: 0 merged outline `_skip`, 1 feature `_skip`,
## 2 inside the snowflake and outside holes, 3 outside every feature.
var _mode := 0
var _skip := -1


## options:
##   center, arm, tip: one of CENTERS / ARMS / TIPS, or "random" (default)
##   between, details: Arrays to use instead of random picks
##   recent: Array of earlier results' {"center", "arm", "tip", "between",
##           "details"} for snowflakes made in a row; recent choices are
##           skipped and the least used preferred
## Returns {"seed", "center", "arm", "tip", "between", "details",
## "polylines", "closed"}.
static func generate(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var g := SnowflakeGenerator.new()
	g.rng.seed = seed_value
	var recent: Array = options.get("recent", [])
	var center: String = g._choose(options, "center", CENTERS, recent)
	var arm: String = g._choose(options, "arm", ARMS, recent)
	var tip: String = g._choose(options, "tip", TIPS, recent)
	var between: Array = options.get("between", g._pick_between(arm, _history(recent, "between")))
	var details: Array = options.get("details", g._pick_details(_history(recent, "details")))
	g._build(center, arm, tip, between, details)
	return {
		"seed": seed_value,
		"center": center,
		"arm": arm,
		"tip": tip,
		"between": between,
		"details": details,
		"polylines": g.polylines,
		"closed": g.closed,
	}


## Every value of `key` in the recent results, flattening Arrays.
static func _history(recent: Array, key: String) -> Array:
	var out := []
	for r in recent:
		var v: Variant = r.get(key)
		if v is Array:
			out.append_array(v)
		elif v != null:
			out.append(v)
	return out


func _choose(options: Dictionary, key: String, names: Array, recent: Array) -> String:
	var wanted: String = options.get(key, "random")
	if wanted in names:
		return wanted
	return _least_used(names, _history(recent, key), AVOID_RECENT)


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


## 0-2 kinds of in-between content that fit together and with the arm.
func _pick_between(arm: String, used: Array) -> Array:
	var out := []
	if rng.randf() < NONE_CHANCE:
		return out
	for _i in (1 if rng.randf() < 0.55 else 2):
		var left := []
		for b in BETWEEN:
			if not b in out and _between_fits(b, arm, out):
				left.append(b)
		if left.is_empty():
			break
		out.append(_least_used(left, used + out, AVOID_RECENT))
	return out


static func _between_fits(b: String, arm: String, chosen: Array) -> bool:
	if b in ["spikes", "petals"] and arm in BRANCHY:
		return false
	for c in chosen:
		for pair in CLASHES:
			if (pair[0] == b and pair[1] == c) or (pair[0] == c and pair[1] == b):
				return false
	return true


func _pick_details(used: Array) -> Array:
	var out := []
	for _i in DETAIL_COUNTS[rng.randi_range(0, DETAIL_COUNTS.size() - 1)]:
		var left := []
		for d in DETAILS:
			if not d in out:
				left.append(d)
		out.append(_least_used(left, used, 1))
	return out


func _add(points: PackedVector2Array, is_closed: bool = false) -> void:
	polylines.append(points)
	closed.append(1 if is_closed else 0)


# --- shapes ------------------------------------------------------------------------

static func _hexagon(c: Vector2, r: float, turn: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(c + Vector2.from_angle(turn + TAU * i / 6.0) * r)
	return pts


## A diamond from a to b, half_w wide at the middle.
static func _rhombus(a: Vector2, b: Vector2, half_w: float) -> PackedVector2Array:
	var n := (b - a).normalized().orthogonal() * half_w
	var m := (a + b) / 2.0
	return PackedVector2Array([a, m - n, b, m + n])


## A bar from a to b, half_w wide, with a pointed end at b when `pointed`.
static func _bar(a: Vector2, b: Vector2, half_w: float, pointed: bool = true) -> PackedVector2Array:
	var u := (b - a).normalized()
	var n := u.orthogonal() * half_w
	var e := b - u * (half_w * 1.6 if pointed else 0.0)
	return PackedVector2Array([a - n, e - n, b, e + n, a + n])


static func _at(r: float) -> Vector2:
	return Vector2.from_angle(PI / 6.0) * r


static func _rotated(poly: PackedVector2Array, angle: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append(v.rotated(angle))
	return out


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		r = r.expand(v)
	return r


# --- building ------------------------------------------------------------------------

func _build(center: String, arm: String, tip: String, between: Array, details: Array) -> void:
	var rc := rng.randf_range(0.15, 0.22)
	var w := rng.randf_range(0.045, 0.065)
	# One arm along +x: merged shapes, features, ribs, inner outlines, dots
	# ([center, radius]); always_inner are inner outlines drawn regardless.
	var part := {"merged": [], "features": [], "ribs": [], "inner": [], "always_inner": [], "dots": []}
	var core_end := _build_tip(tip, w, part)
	var span0 := rc + 0.06
	var span1: float = part["span1"]
	_build_arm(arm, rc, w, core_end, tip == "point", span0, span1, part)
	_build_between(between, rc, w, part)
	var center_part := {"merged": [], "features": [], "inner": [], "extra": []}
	_build_center(center, rc, center_part)

	var ribs: Array[PackedVector2Array] = []
	var inner: Array[PackedVector2Array] = []
	var always_inner: Array[PackedVector2Array] = []
	var dots := []
	for k in 6:
		var a := TAU * k / 6.0
		for p in part["merged"]:
			_merged.append(_rotated(p, a))
		for p in part["features"]:
			_features.append(_rotated(p, a))
		for p in part["ribs"]:
			ribs.append(_rotated(p, a))
		for p in part["inner"]:
			inner.append(_rotated(p, a))
		for p in part["always_inner"]:
			always_inner.append(_rotated(p, a))
		for d in part["dots"]:
			dots.append([(d[0] as Vector2).rotated(a), d[1]])
	for p in center_part["merged"]:
		_merged.append(p)
	if part.has("plate"):
		_merged.append(part["plate"])
	for p in center_part["features"]:
		_features.append(p)
	for p in center_part["inner"]:
		always_inner.append(p)
	for p in _merged:
		_merged_boxes.append(_bounds(p))
	for p in _features:
		_features_boxes.append(_bounds(p))

	# The silhouette, then the features' outlines.
	_mode = 0
	for i in _merged.size():
		_skip = i
		_add_loop(_merged[i])
	_mode = 1
	for i in _features.size():
		_skip = i
		_add_loop(_features[i])
	# A stellar plate's rim, stopping at features.
	_mode = 3
	if part.has("rim"):
		_add_loop(part["rim"])
	for p in always_inner:
		_add(p, true)
		_holes.append(p)
	for e in center_part["extra"]:
		var poly: PackedVector2Array = e
		_add(poly, poly.size() > 2)
		if poly.size() > 2:
			_holes.append(poly)
	if "inner" in details:
		for p in inner:
			_add(p, true)
			_holes.append(p)
	if "dots" in details:
		for d in dots:
			var dot := MandalaGenerator.circle(d[0], d[1], 18)
			if _clear_of_holes(dot):
				_add(dot, true)
				_holes.append(dot)
	if "ribs" in details:
		_mode = 2
		for path in ribs:
			for piece in _clip(path):
				_add(piece)
	_fit()


## Adds the tip's shapes to `part`, sets part["span1"] (where arm decorations
## must stop) and returns where the arm's core ends.
func _build_tip(tip: String, w: float, part: Dictionary) -> float:
	match tip:
		"plate":
			var pr := rng.randf_range(0.1, 0.13)
			var c := Vector2(TIP_R - pr, 0.0)
			part["features"].append(_hexagon(c, pr))
			part["inner"].append(_hexagon(c, pr * 0.5))
			part["dots"].append([c, pr * 0.28])
			part["span1"] = c.x - pr - 0.04
			return c.x
		"diamond":
			var a := TIP_R - rng.randf_range(0.2, 0.26)
			var hw := rng.randf_range(0.08, 0.1)
			part["features"].append(_rhombus(Vector2(a, 0.0), Vector2(TIP_R, 0.0), hw))
			var reach := TIP_R - a
			part["inner"].append(_rhombus(Vector2(a + reach * 0.3, 0.0), Vector2(TIP_R - reach * 0.3, 0.0), hw * 0.4))
			part["dots"].append([Vector2((a + TIP_R) / 2.0, 0.0), 0.025])
			part["span1"] = a - 0.04
			return (a + TIP_R) / 2.0
		"ring":
			var rr := rng.randf_range(0.08, 0.1)
			var c := Vector2(TIP_R - rr, 0.0)
			part["features"].append(MandalaGenerator.circle(c, rr, 40))
			part["always_inner"].append(MandalaGenerator.circle(c, rr * 0.5, 28))
			part["span1"] = c.x - rr * 0.5 - 0.04
			return c.x - rr * 0.5
		"fork":
			var fx := TIP_R - rng.randf_range(0.18, 0.24)
			var dir := Vector2.from_angle(deg_to_rad(rng.randf_range(30.0, 42.0)))
			var length := (TIP_R - fx) * 1.05
			for side in [1.0, -1.0]:
				var d := Vector2(dir.x, dir.y * side)
				var base := Vector2(fx, 0.0)
				part["merged"].append(_bar(base, base + d * length, w * 0.8))
				part["ribs"].append(PackedVector2Array([base, base + d * length * 0.9]))
			part["span1"] = fx - 0.06
			return fx + w
	part["span1"] = TIP_R - 0.18
	return TIP_R


func _build_arm(arm: String, rc: float, w: float, core_end: float, pointed: bool, span0: float, span1: float,
		part: Dictionary) -> void:
	var end := TIP_R if pointed else core_end
	if arm == "crystal":
		var cw := rng.randf_range(0.08, 0.1)
		var a := rc * 0.7
		var shoulder := end - cw * (1.4 if pointed else 0.3)
		part["merged"].append(PackedVector2Array([Vector2(a, cw * 0.5), Vector2(a + cw, cw), Vector2(shoulder, cw),
				Vector2(end, 0.0), Vector2(shoulder, -cw), Vector2(a + cw, -cw), Vector2(a, -cw * 0.5)]))
		part["inner"].append(PackedVector2Array([Vector2(a + cw * 1.2, 0.0), Vector2(a + cw * 1.8, cw * 0.45),
				Vector2(end - cw * 2.0, cw * 0.45), Vector2(end - cw * 1.6, 0.0), Vector2(end - cw * 2.0, -cw * 0.45),
				Vector2(a + cw * 1.8, -cw * 0.45)]))
	else:
		part["merged"].append(_bar(Vector2.ZERO, Vector2(end, 0.0), w, pointed))
	part["ribs"].append(PackedVector2Array([Vector2.ZERO, Vector2(TIP_R * (0.94 if pointed else 1.0), 0.0)]))
	var room := span1 - span0
	match arm:
		"branched", "fern":
			var n := rng.randi_range(2, 3) if arm == "branched" else rng.randi_range(4, 5)
			var dir := Vector2.from_angle(deg_to_rad(rng.randf_range(52.0, 62.0)))
			var bw := w * (0.85 if arm == "branched" else 0.62)
			for i in n:
				var x := span0 + room * (i + 0.3) / n
				var length := maxf(0.1, (1.05 - x) * (rng.randf_range(0.55, 0.7) if arm == "branched" else 0.42))
				for side in [1.0, -1.0]:
					var base := Vector2(x, 0.0)
					var tip := base + Vector2(dir.x, dir.y * side) * length
					part["merged"].append(_bar(base, tip, bw))
					part["ribs"].append(PackedVector2Array([base, base.lerp(tip, 0.92)]))
		"plates":
			var k := 2 if room > 0.5 else 1
			var pr := minf(rng.randf_range(0.09, 0.12), room / (2.3 * k))
			for i in k:
				var c := Vector2(span0 + room * (i + 0.5) / k, 0.0)
				part["features"].append(_hexagon(c, pr, PI / 6.0))
				if pr >= 0.09:
					part["inner"].append(_hexagon(c, pr * 0.5, PI / 6.0))
				part["dots"].append([c, pr * 0.28])
		"arrows":
			var k := rng.randi_range(2, 3)
			for i in k:
				var x := span0 + room * (i + 0.6) / k
				var back := rng.randf_range(0.09, 0.12)
				for side in [1.0, -1.0]:
					part["merged"].append(_bar(Vector2(x, 0.0), Vector2(x - back, side * back * 1.15), w * 0.7))
		"spear":
			var a := span0 + room * 0.15
			var b := span0 + room * 0.85
			var hw := rng.randf_range(0.1, 0.13)
			part["features"].append(_rhombus(Vector2(a, 0.0), Vector2(b, 0.0), hw))
			part["inner"].append(_rhombus(Vector2(a + (b - a) * 0.25, 0.0), Vector2(b - (b - a) * 0.25, 0.0), hw * 0.45))
			part["dots"].append([Vector2((a + b) / 2.0, 0.0), 0.025])


## The content between two arms, built around the 30 degree line.
func _build_between(between: Array, rc: float, w: float, part: Dictionary) -> void:
	for b in between:
		match b:
			"spikes":
				var length := rng.randf_range(0.38, 0.52)
				part["merged"].append(_bar(Vector2.ZERO, _at(length), w * 0.75))
				part["ribs"].append(PackedVector2Array([Vector2.ZERO, _at(length * 0.92)]))
			"plate":
				# A stellar plate: a hexagon with its corners on the arms.
				var r := rng.randf_range(0.42, 0.58)
				part["plate"] = _hexagon(Vector2.ZERO, r)
				part["rim"] = _hexagon(Vector2.ZERO, r * rng.randf_range(0.72, 0.8))
			"webs":
				# Bars bridging neighboring arms, at one or two radii.
				for rw in ([rng.randf_range(0.45, 0.6)] if rng.randf() < 0.5 else [0.4, 0.68]):
					part["merged"].append(_bar(Vector2(rw, 0.0), Vector2.from_angle(PI / 3.0) * rw, w * 0.6, false))
			"petals":
				var r0 := rc + 0.03
				var r1 := rng.randf_range(0.45, 0.55)
				# As wide as fits between the arms.
				var bulge := minf(0.5, ((r0 + r1) / 2.0 * 0.5 - w - 0.05) * 2.0 / (r1 - r0))
				part["features"].append(MandalaGenerator._lens(_at(r0), _at(r1), bulge, 20))
				part["inner"].append(MandalaGenerator._lens(_at(r0 + (r1 - r0) * 0.3), _at(r1 - (r1 - r0) * 0.2),
						bulge * 0.6, 14))
			"diamonds", "dots":
				# Inside the stellar plate's rim when there is one, else floating.
				var r := rng.randf_range(0.42, 0.52)
				var size := 0.08
				if "plate" in between:
					r = 0.0
				if b == "diamonds" and r > 0.0:
					part["features"].append(_rhombus(_at(r - size), _at(r + size), 0.045))
				elif r > 0.0:
					part["features"].append(MandalaGenerator.circle(_at(r), rng.randf_range(0.035, 0.045), 24))
	if part.has("rim") and ("diamonds" in between or "dots" in between):
		var r := (part["rim"][0] as Vector2).length() * 0.62
		if "diamonds" in between:
			part["features"].append(_rhombus(_at(r - 0.07), _at(r + 0.07), 0.04))
		else:
			part["features"].append(MandalaGenerator.circle(_at(r), 0.035, 24))


func _build_center(center: String, rc: float, part: Dictionary) -> void:
	match center:
		"hexagon", "nested", "spoked":
			part["features"].append(_hexagon(Vector2.ZERO, rc, PI / 6.0))
			if center == "nested":
				part["inner"].append(_hexagon(Vector2.ZERO, rc * 0.55))
			elif center == "spoked":
				part["inner"].append(_hexagon(Vector2.ZERO, rc * 0.35, PI / 6.0))
				for i in 6:
					var d := Vector2.from_angle(PI / 6.0 + TAU * i / 6.0)
					part["extra"].append(PackedVector2Array([d * rc * 0.35, d * rc]))
		"star":
			var star := PackedVector2Array()
			for i in 12:
				star.append(Vector2.from_angle(TAU * i / 12.0) * rc * (1.15 if i % 2 == 0 else 0.66))
			part["features"].append(star)
			part["inner"].append(_hexagon(Vector2.ZERO, rc * 0.4, PI / 6.0))
		"rosette":
			part["features"].append(MandalaGenerator.circle(Vector2.ZERO, rc, 60))
			part["inner"].append(MandalaGenerator.circle(Vector2.ZERO, rc * 0.45, 40))
			for i in 6:
				var d := Vector2.from_angle(PI / 6.0 + TAU * i / 6.0)
				part["extra"].append(MandalaGenerator._lens(d * rc * 0.45, d * rc, 0.55))
		_:
			for i in 6:
				var d := Vector2.from_angle(PI / 6.0 + TAU * i / 6.0)
				part["merged"].append(MandalaGenerator._lens(Vector2.ZERO, d * rc * 1.25, 0.6, 20))
			part["features"].append(MandalaGenerator.circle(Vector2.ZERO, rc * 0.4, 36))


# --- clipping ------------------------------------------------------------------------

func _in_shapes(p: Vector2, shapes: Array[PackedVector2Array], boxes: Array[Rect2], skip: int,
		before: int = -1) -> bool:
	var n := shapes.size() if before < 0 else before
	for i in n:
		if i != skip and boxes[i].has_point(p) and Geometry2D.is_point_in_polygon(p, shapes[i]):
			return true
	return false


## Whether the current line may draw at p (see _mode).
func _visible(p: Vector2) -> bool:
	match _mode:
		0:
			return not _in_shapes(p, _merged, _merged_boxes, _skip) \
					and not _in_shapes(p, _features, _features_boxes, -1)
		1:
			# Earlier features are in front of later ones.
			return not _in_shapes(p, _features, _features_boxes, _skip, _skip)
		2:
			if not (_in_shapes(p, _merged, _merged_boxes, -1) or _in_shapes(p, _features, _features_boxes, -1)):
				return false
			for h in _holes:
				if Geometry2D.is_point_in_polygon(p, h):
					return false
			return true
	return not _in_shapes(p, _features, _features_boxes, -1)


func _clear_of_holes(poly: PackedVector2Array) -> bool:
	for v in poly:
		for h in _holes:
			if Geometry2D.is_point_in_polygon(v, h):
				return false
	return true


## The visible pieces of a path, sampled every `step` with each end found by
## bisection, so pieces end exactly on the lines that stop them. A closed
## path that starts visible keeps its first and last pieces joined.
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
	if pieces.size() >= 2 and path[0].is_equal_approx(path[path.size() - 1]) and _visible(path[0]):
		var last: PackedVector2Array = pieces.pop_back()
		last.append_array(pieces[0].slice(1))
		pieces[0] = last
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


func _add_loop(loop: PackedVector2Array) -> void:
	var path := loop.duplicate()
	path.append(loop[0])
	for piece in _clip(path):
		_add(piece)


## Scales everything so the snowflake reaches radius 0.97.
func _fit() -> void:
	var reach := 0.0
	for line in polylines:
		for v in line:
			reach = maxf(reach, v.length())
	var k := 0.97 / maxf(reach, 1e-6)
	for i in polylines.size():
		var scaled := PackedVector2Array()
		for v in polylines[i]:
			scaled.append(v * k)
		polylines[i] = scaled

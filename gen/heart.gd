class_name HeartGenerator
extends RefCounted
## Seeded hearts that differ in outline, collar and the patterns inside, so
## hearts look clearly different from each other.
##
## A heart is three choices:
##   shape: the outline's proportions (SHAPES)
##   collar: a band just inside the outline, plain or divided (COLLARS)
##   patterns: 1-3 inner patterns combined: an optional center motif (MOTIFS)
##             and up to two fill patterns (FIELDS). Two fills split the heart
##             along a mirrored divider (DIVIDERS), and fills flow around the
##             motif, so every combination still has closed regions.
## Everything is mirror-symmetric about the vertical axis.
##
## Output matches MandalaGenerator: polylines in unit space (-1..1, y down).

## Outline proportions for the heart curve x = 16 sin^p t,
## y = a cos t - b cos 2t - c cos 3t - d cos 4t, stretched by sx and sy.
## b sets the cleft's depth, c and d the tip, p how full the lobes are.
const SHAPES := {
	"classic": {"p": 3.0, "a": 13.0, "b": 5.0, "c": 2.0, "d": 1.0, "sx": 1.0, "sy": 1.0},
	"plump": {"p": 2.5, "a": 13.0, "b": 4.0, "c": 2.0, "d": 1.0, "sx": 1.12, "sy": 0.94},
	"slim": {"p": 3.0, "a": 13.0, "b": 5.0, "c": 2.6, "d": 1.0, "sx": 0.84, "sy": 1.06},
	"sweetheart": {"p": 3.0, "a": 13.0, "b": 6.5, "c": 2.0, "d": 1.5, "sx": 1.0, "sy": 1.0},
	"puffy": {"p": 2.2, "a": 13.0, "b": 3.5, "c": 1.2, "d": 0.8, "sx": 1.06, "sy": 0.96},
	"pointed": {"p": 3.2, "a": 13.0, "b": 5.0, "c": 3.0, "d": 0.5, "sx": 0.95, "sy": 1.1},
}
## plain: one band; rays: the band divided by spokes; beads: a row of round
## stones; scallops: a wavy line splits the band; petals: leaf shapes across
## the band; double: two bands with staggered spokes; none: no collar.
const COLLARS := ["plain", "rays", "beads", "scallops", "petals", "double", "none"]
## Center motifs: a heart (sometimes with a smaller one inside), two hearts
## with spokes between them, a flower, or a rosette (a wheel of spokes).
## Combined with fills, round motifs sit in a circular frame.
const MOTIFS := ["heart", "double_heart", "flower", "rosette"]
## Fill patterns: horizontal stripes, chevrons, a diamond lattice, rays from
## the motif, waves, rows of dots, a square grid, and echoes (copies of the
## motif's outline, growing outward).
const FIELDS := ["stripes", "chevrons", "lattice", "rays", "waves", "dots", "grid", "echoes"]
## The line between two fills: straight, an arc, a wave or a V.
const DIVIDERS := ["line", "arc", "wave", "vee"]
## Chances of combining 1, 2 or 3 inner patterns.
const PATTERN_COUNT_WEIGHTS := [0.25, 0.45, 0.3]
## Shapes, collars and fills used by this many previous hearts in a row are
## skipped (motifs skip only the last one, as there are just four).
const AVOID_RECENT := 2
const SAMPLES := 240

var rng := RandomNumberGenerator.new()
var polylines: Array[PackedVector2Array] = []
var closed := PackedByteArray()

var _p: Dictionary
var _scale := 1.0
var _offset_y := 0.0
## Point the inner hearts scale about, a little above the middle.
var _c0 := Vector2.ZERO
var _outline := PackedVector2Array()
var _normals := PackedVector2Array()
var _band := 0.0
var _boundary := PackedVector2Array()
var _holes: Array[PackedVector2Array] = []
var _zone := 0
var _divider := {}


## options:
##   shape, collar: one of SHAPES / COLLARS, or "random" (default)
##   patterns: Array of inner patterns to use (at most one motif and two
##             fields), or empty for random (default)
##   recent: Array of earlier results' {"shape", "collar", "patterns"} for
##           hearts made in a row; recent choices are skipped and the least
##           used preferred, so a run of hearts works through them all
## Returns {"seed", "shape", "collar", "patterns", "motif", "fields",
## "divider", "polylines", "closed"}.
static func generate(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var g := HeartGenerator.new()
	g.rng.seed = seed_value
	var recent: Array = options.get("recent", [])
	var shape: String = options.get("shape", "random")
	if not SHAPES.has(shape):
		shape = g._least_used(SHAPES.keys(), _recent_of(recent, "shape", []), AVOID_RECENT)
	var collar: String = options.get("collar", "random")
	if not collar in COLLARS:
		collar = g._least_used(COLLARS, _recent_of(recent, "collar", []), AVOID_RECENT)
	var motif := ""
	var fields := []
	var wanted: Array = options.get("patterns", [])
	if wanted.is_empty():
		var count := g._weighted_count()
		if count == 3 or g.rng.randf() < 0.6:
			motif = g._least_used(MOTIFS, _recent_of(recent, "patterns", MOTIFS), 1)
		var used := _recent_of(recent, "patterns", FIELDS)
		for _i in count - (1 if motif != "" else 0):
			var left := []
			for f in FIELDS:
				if not f in fields:
					left.append(f)
			fields.append(g._least_used(left, used, AVOID_RECENT))
	else:
		for p in wanted:
			if p in MOTIFS and motif == "":
				motif = p
			elif p in FIELDS and fields.size() < 2:
				fields.append(p)

	g._setup(SHAPES[shape])
	g._build_collar(collar)
	g._build_inside(motif, fields)
	var patterns := ([motif] if motif != "" else []) + fields
	return {
		"seed": seed_value,
		"shape": shape,
		"collar": collar,
		"patterns": patterns,
		"motif": motif,
		"fields": fields,
		"divider": g._divider.get("kind", ""),
		"polylines": g.polylines,
		"closed": g.closed,
	}


## Every value of `key` in the recent results, in order; for "patterns",
## only those in `only`.
static func _recent_of(recent: Array, key: String, only: Array) -> Array:
	var out := []
	for r in recent:
		var v: Variant = r.get(key)
		if v is Array:
			for item in v:
				if only.is_empty() or item in only:
					out.append(item)
		elif v != null:
			out.append(v)
	return out


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


func _weighted_count() -> int:
	var pick := rng.randf()
	for i in PATTERN_COUNT_WEIGHTS.size():
		pick -= PATTERN_COUNT_WEIGHTS[i]
		if pick < 0.0:
			return i + 1
	return PATTERN_COUNT_WEIGHTS.size()


func _add(points: PackedVector2Array, is_closed: bool = false) -> void:
	polylines.append(points)
	closed.append(1 if is_closed else 0)


# --- outline ---------------------------------------------------------------------

## Varies the shape a little, then fits the heart into the unit square.
func _setup(shape: Dictionary) -> void:
	_p = shape.duplicate()
	_p["sx"] *= rng.randf_range(0.95, 1.05)
	_p["sy"] *= rng.randf_range(0.95, 1.05)
	_p["b"] *= rng.randf_range(0.9, 1.1)
	var box := Rect2(_raw(0.0), Vector2.ZERO)
	for i in SAMPLES:
		box = box.expand(_raw(TAU * i / SAMPLES))
	_scale = 1.94 / maxf(box.size.x, box.size.y)
	_offset_y = -box.get_center().y
	var top := (box.position.y + _offset_y) * _scale
	var bottom := (box.end.y + _offset_y) * _scale
	_c0 = Vector2(0.0, top + 0.44 * (bottom - top))

	_outline = _curve(1.0)
	_normals.resize(SAMPLES)
	for i in SAMPLES:
		var tangent := _outline[(i + 1) % SAMPLES] - _outline[(i - 1 + SAMPLES) % SAMPLES]
		_normals[i] = Vector2(-tangent.y, tangent.x).normalized()
	# Point the normals inward, tested on the right lobe.
	var q := SAMPLES / 4
	if not Geometry2D.is_point_in_polygon(_outline[q] + _normals[q] * 0.02, _outline):
		for i in SAMPLES:
			_normals[i] = -_normals[i]
	_add(_outline, true)


## The heart curve in its own units, y down. t = 0 is the cleft, PI the tip.
func _raw(t: float) -> Vector2:
	var s := sin(t)
	var x: float = 16.0 * signf(s) * pow(absf(s), _p["p"]) * _p["sx"]
	var y: float = -(_p["a"] * cos(t) - _p["b"] * cos(2.0 * t) - _p["c"] * cos(3.0 * t) - _p["d"] * cos(4.0 * t)) * _p["sy"]
	return Vector2(x, y)


## The point at t on the heart scaled by s about _c0, in unit space.
func _point(t: float, s: float = 1.0) -> Vector2:
	var raw := _raw(t)
	var v := Vector2(raw.x * _scale, (raw.y + _offset_y) * _scale)
	return _c0 + (v - _c0) * s


func _curve(s: float, n: int = SAMPLES) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		pts.append(_point(TAU * i / n, s))
	return pts


## A copy of the heart scaled by s with its _c0 moved to pos.
func _copy_at(pos: Vector2, s: float, n: int = 120) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for v in _curve(1.0, n):
		pts.append(pos + (v - _c0) * s)
	return pts


## The outline moved inward by d, or by d * f(t) when f is given. Loops the
## offset forms at the sharp tip are cut out.
func _inset(d: float, f: Callable = Callable()) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in SAMPLES:
		var dd := d
		if f.is_valid():
			dd *= f.call(TAU * i / SAMPLES)
		pts.append(_outline[i] + _normals[i] * dd)
	return _untangle(pts)


## The outline point at t moved inward by d (an end of a spoke).
func _at(t: float, d: float) -> Vector2:
	var i := roundi(t / TAU * SAMPLES) % SAMPLES
	return _outline[i] + _normals[i] * d


## Wherever the closed outline crosses itself, cuts out the shorter side of
## the crossing, until it no longer crosses.
static func _untangle(source: PackedVector2Array) -> PackedVector2Array:
	var pts := source
	var changed := true
	while changed:
		changed = false
		var n := pts.size()
		for i in n:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			for j in range(i + 2, n):
				if (j + 1) % n == i:
					continue
				var x: Variant = Geometry2D.segment_intersects_segment(a, b, pts[j], pts[(j + 1) % n])
				if x == null:
					continue
				var cut := PackedVector2Array()
				if j - i <= n - (j - i):
					cut.append_array(pts.slice(0, i + 1))
					cut.append(x)
					cut.append_array(pts.slice(j + 1))
				else:
					cut.append(x)
					cut.append_array(pts.slice(i + 1, j + 1))
				pts = cut
				changed = true
				break
			if changed:
				break
	return pts


static func _mirrored(ts: Array) -> Array:
	var out := []
	for t in ts:
		out.append(t)
		out.append(TAU - t)
	return out


## n parameters on the right half of the heart, kept off the cleft and the
## tip where the band pinches; `half` shifts them half a step.
static func _span(n: int, half: bool) -> Array:
	var out := []
	for i in n:
		if half:
			out.append(PI * (0.08 + 0.72 * (i + 0.5) / n))
		else:
			out.append(PI * (0.08 + 0.72 * i / maxi(1, n - 1)))
	return out


# --- collar ----------------------------------------------------------------------

func _build_collar(collar: String) -> void:
	var d := rng.randf_range(0.13, 0.19)
	if collar == "none":
		_band = 0.0
		_boundary = _outline
		return
	_band = d
	_boundary = _inset(d)
	_add(_boundary, true)
	match collar:
		"rays":
			for t in _mirrored(_span(rng.randi_range(5, 9), false)):
				_add(PackedVector2Array([_at(t, d), _at(t, 0.0)]))
		"beads":
			var n := rng.randi_range(6, 10)
			for t in _span(n, true):
				# Sized on the right half, so each mirrored pair matches.
				var step := _at(t, d / 2.0).distance_to(_at(t + 0.72 * PI / n, d / 2.0))
				for u in [t, TAU - t]:
					var mid := (_at(u, 0.0) + _at(u, d)) / 2.0
					_add(MandalaGenerator.circle(mid, minf(d * 0.32, step * 0.36), 24), true)
		"scallops":
			var m := 2 * rng.randi_range(4, 7)
			_add(_inset(d, func(t: float) -> float: return 0.75 - 0.5 * absf(sin(m * t / 2.0))), true)
		"petals":
			for t in _mirrored(_span(rng.randi_range(5, 8), true)):
				_add(MandalaGenerator._lens(_at(t, d * 0.97), _at(t, d * 0.03), 0.5), true)
		"double":
			_add(_inset(d / 2.0), true)
			var n := rng.randi_range(6, 10)
			for t in _mirrored(_span(n, false)):
				_add(PackedVector2Array([_at(t, d / 2.0), _at(t, 0.0)]))
			for t in _mirrored(_span(n - 1, true)):
				_add(PackedVector2Array([_at(t, d), _at(t, d / 2.0)]))


# --- inside ----------------------------------------------------------------------

func _build_inside(motif: String, fields: Array) -> void:
	var k := 1.0 - _band * 1.4
	var box := Rect2(_boundary[0], Vector2.ZERO)
	for v in _boundary:
		box = box.expand(v)
	var center := _c0
	if motif != "":
		center = _build_motif(motif, k, fields.is_empty())
	var zones := [0]
	if fields.size() == 2:
		_pick_divider(box.position.y, box.end.y)
		zones = [1, 2]
		_zone = 0
		var line := PackedVector2Array()
		for i in 241:
			var x := i / 100.0 - 1.2
			line.append(Vector2(x, _divider_y(x)))
		for piece in _clip(line):
			_add(piece)
	for i in fields.size():
		_zone = zones[i]
		_build_field(fields[i], center, box.position.y, box.end.y)


func _pick_divider(top: float, bottom: float) -> void:
	_divider = {
		"kind": DIVIDERS[rng.randi_range(0, DIVIDERS.size() - 1)],
		"y": top + (bottom - top) * rng.randf_range(0.45, 0.58),
		"a": rng.randf_range(0.08, 0.16) * (1.0 if rng.randf() < 0.5 else -1.0),
	}


func _divider_y(x: float) -> float:
	var y0: float = _divider["y"]
	var a: float = _divider["a"]
	match _divider["kind"]:
		"arc":
			return y0 - a + a * x * x * 1.6
		"wave":
			return y0 + a * 0.6 * cos(x * PI * 2.2)
		"vee":
			return y0 - a + absf(x) * a * 1.4
	return y0


## Whether a field may draw at p: inside the collar, in the current zone and
## outside every motif outline.
func _visible(p: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(p, _boundary):
		return false
	if _zone == 1 and p.y >= _divider_y(p.x):
		return false
	if _zone == 2 and p.y <= _divider_y(p.x):
		return false
	for h in _holes:
		if Geometry2D.is_point_in_polygon(p, h):
			return false
	return true


## The visible pieces of a path, sampled every `step` with each end found by
## bisection, so pieces end exactly on the lines that stop them.
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
	var out: Array[PackedVector2Array] = []
	for piece in pieces:
		if piece.size() >= 2 and piece[0].distance_to(piece[piece.size() - 1]) > 0.02:
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


func _add_clipped(path: PackedVector2Array) -> void:
	for piece in _clip(path):
		_add(piece)


## Whether pts lies inside the collar, at least margin from it and from each
## of `others`.
func _fits(pts: PackedVector2Array, margin: float, others: Array[PackedVector2Array]) -> bool:
	for v in pts:
		if not Geometry2D.is_point_in_polygon(v, _boundary):
			return false
	var all_others: Array[PackedVector2Array] = [_boundary]
	all_others.append_array(others)
	for other in all_others:
		for i in range(0, pts.size(), 3):
			for j in range(0, other.size(), 2):
				if pts[i].distance_to(other[j]) <= margin:
					return false
	return true


## The largest scale up to s, and a position near (x, y), at which a heart
## copy fits (see _fits). y defaults to _c0's. Returns [scale, position].
func _fit(s: float, margin: float, x: float = 0.0, y: float = NAN,
		others: Array[PackedVector2Array] = []) -> Array:
	var cy := _c0.y if is_nan(y) else y
	while s > 0.04:
		for dy in [0.0, 0.04, -0.04, 0.08, -0.08, 0.13, -0.13, 0.19, 0.25]:
			var pos := Vector2(x, cy + dy)
			if _fits(_copy_at(pos, s), margin, others):
				return [s, pos]
		s *= 0.92
	return [0.0, Vector2(x, cy)]


## Draws the center motif, sets _holes to its outline, and returns its
## center. Alone it fills the heart; with fills it is smaller.
func _build_motif(kind: String, k: float, alone: bool) -> Vector2:
	var size := 1.0 if alone else 0.62
	if kind in ["heart", "double_heart"]:
		var fit := _fit(k * (0.42 if kind == "heart" else 0.62) * size, 0.09)
		var s1: float = fit[0]
		var pos: Vector2 = fit[1]
		var h1 := _copy_at(pos, s1, SAMPLES)
		_add(h1, true)
		if kind == "double_heart":
			var h2 := _copy_at(pos, s1 * rng.randf_range(0.5, 0.58), SAMPLES)
			_add(h2, true)
			var n := rng.randi_range(3, 5)
			var ts := []
			for i in n:
				ts.append((0.12 + 0.7 * i / (n - 1)) * PI)
			for t in _mirrored(ts):
				var i := int(t / TAU * SAMPLES) % SAMPLES
				_add(PackedVector2Array([h2[i], h1[i]]))
		elif rng.randf() < 0.5:
			_add(_copy_at(pos, s1 * 0.5), true)
		_holes = [h1]
		return pos

	# Round motifs sit where the middle line has the most room.
	var box := Rect2(_boundary[0], Vector2.ZERO)
	for v in _boundary:
		box = box.expand(v)
	var best_r := 0.0
	var best_y := _c0.y
	for i in 21:
		var y := box.position.y + box.size.y * (0.2 + 0.5 * i / 20.0)
		var p := Vector2(0.0, y)
		if not Geometry2D.is_point_in_polygon(p, _boundary):
			continue
		var r := INF
		for v in _boundary:
			r = minf(r, p.distance_to(v))
		if r > best_r:
			best_r = r
			best_y = y
	var radius := best_r * 0.86 * size
	var c := Vector2(0.0, best_y)
	var frame := MandalaGenerator.circle(c, radius * 1.06, 96)
	if kind == "flower":
		var names := ["oval", "heart", "spoon", "pointed"]
		var p: Dictionary = FlowerGenerator.TEMPLATES[names[rng.randi_range(0, names.size() - 1)]]
		var n := rng.randi_range(5, 8)
		var rc := radius * 0.26
		var base_r := rc * 0.6
		var length := (radius - base_r) / 1.04
		var alpha := TAU / n
		var half_w := minf(0.85 * (base_r + p["widest"] * length) * sin(alpha / 2.0), length * 0.45)
		var none: Array[PackedVector2Array] = []
		var no_boxes: Array[Rect2] = []
		for i in n:
			var petal := FlowerGenerator._place(FlowerGenerator._petal_outline(p, length, half_w), base_r,
					-PI / 2.0 + i * alpha, length, 0.0, 0.0)
			petal.append(petal[0])
			for piece in FlowerGenerator._clip(petal, rc, none, no_boxes):
				var moved := PackedVector2Array()
				for v in piece:
					moved.append(v + c)
				_add(moved)
		_add(MandalaGenerator.circle(c, rc), true)
		_add(MandalaGenerator.circle(c, rc * 0.5), true)
	else:
		# Rosette: a wheel of spokes between a hub and the frame.
		_add(MandalaGenerator.circle(c, radius * 0.45), true)
		var n := 2 * rng.randi_range(3, 6)
		var turn := 0.0 if rng.randf() < 0.5 else PI / n
		for i in n:
			var dir := Vector2.from_angle(-PI / 2.0 + turn + TAU * i / n)
			_add(PackedVector2Array([c + dir * radius * 0.45, c + dir * radius * 1.06]))
	if not alone or kind == "rosette":
		_add(frame, true)
	_holes = [frame]
	return c


func _build_field(kind: String, center: Vector2, top: float, bottom: float) -> void:
	match kind:
		"stripes":
			var step := rng.randf_range(0.13, 0.19)
			var y := top + step * rng.randf_range(0.5, 1.0)
			while y < bottom:
				_add_clipped(PackedVector2Array([Vector2(-1.2, y), Vector2(1.2, y)]))
				y += step
		"waves":
			var step := rng.randf_range(0.15, 0.2)
			var amp := step * rng.randf_range(0.2, 0.35)
			var f := rng.randf_range(2.0, 3.2)
			var y := top + step * 0.7
			while y < bottom:
				var wave := PackedVector2Array()
				for i in 145:
					var x := i / 60.0 - 1.2
					wave.append(Vector2(x, y + amp * cos(f * PI * x)))
				_add_clipped(wave)
				y += step
		"chevrons":
			var step := rng.randf_range(0.15, 0.2)
			var dip := rng.randf_range(0.2, 0.4) * (1.0 if rng.randf() < 0.5 else -1.0)
			var y := top + step * 0.6
			while y < bottom + 0.6:
				_add_clipped(PackedVector2Array([Vector2(-1.2, y - dip * 1.2), Vector2(0.0, y), Vector2(1.2, y - dip * 1.2)]))
				y += step
		"lattice":
			var step := rng.randf_range(0.17, 0.24)
			var dir := Vector2.from_angle(deg_to_rad(rng.randf_range(38.0, 52.0)))
			for i in range(-12, 13):
				var off := (i + 0.5) * step
				var q := Vector2(off * dir.y, center.y - off * dir.x)
				_add_clipped(PackedVector2Array([q - dir * 2.2, q + dir * 2.2]))
				var mq := Vector2(-q.x, q.y)
				var mdir := Vector2(-dir.x, dir.y)
				_add_clipped(PackedVector2Array([mq - mdir * 2.2, mq + mdir * 2.2]))
		"grid":
			var step := rng.randf_range(0.17, 0.24)
			for i in range(-12, 13):
				var off := (i + 0.5) * step
				_add_clipped(PackedVector2Array([Vector2(off, -1.2), Vector2(off, 1.2)]))
				_add_clipped(PackedVector2Array([Vector2(-1.2, center.y + off), Vector2(1.2, center.y + off)]))
		"rays":
			var n := rng.randi_range(4, 7)
			for i in n:
				var dir := Vector2.from_angle(-PI / 2.0 + PI * (i + 0.5) / n)
				_add_clipped(PackedVector2Array([center, center + dir * 3.0]))
				_add_clipped(PackedVector2Array([center, center + Vector2(-dir.x, dir.y) * 3.0]))
			_add_clipped(PackedVector2Array([center, center + Vector2(0.0, -3.0)]))
			_add_clipped(PackedVector2Array([center, center + Vector2(0.0, 3.0)]))
		"echoes":
			if not _holes.is_empty():
				var base := _holes[0]
				for f in [1.45, 1.95, 2.5, 3.1, 3.8]:
					var echo := PackedVector2Array()
					for v in base:
						echo.append(center + (v - center) * f)
					echo.append(echo[0])
					_add_clipped(echo)
			else:
				for s in [0.7, 0.45, 0.22]:
					var echo := _curve(s * (1.0 - _band))
					echo.append(echo[0])
					_add_clipped(echo)
		"dots":
			var step := rng.randf_range(0.15, 0.2)
			var r := step * rng.randf_range(0.22, 0.3)
			var stagger := rng.randf() < 0.5
			var row := 0
			var y := top + step * 0.5
			while y < bottom:
				var x := step / 2.0 if stagger and row % 2 == 1 else 0.0
				while x < 1.1:
					for side in ([1.0] if x == 0.0 else [1.0, -1.0]):
						var c := Vector2(x * side, y)
						if _clear(c, r + 0.03):
							_add(MandalaGenerator.circle(c, r, 20), true)
					x += step
				y += step
				row += 1


## Whether a dot of radius r at c is fully visible.
func _clear(c: Vector2, r: float) -> bool:
	if not _visible(c):
		return false
	for i in 16:
		if not _visible(c + Vector2.from_angle(TAU * i / 16) * r):
			return false
	return true

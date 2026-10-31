class_name SwirlGenerator
extends RefCounted
## Seeded free-form line art: flowing curves, ribbons, leaves, curls, drops
## and orbs inside an organic outline. Nothing about the shapes is symmetric;
## they are just meant to be pretty.
##
## A swirl is a layout (LAYOUTS) inside an outline (SHAPES: a lopsided blob,
## a paisley with a curled tip, a tilted pebble, a cloud of uneven bumps, a
## squarish tile, a bean, a big leaf, a fan shell, a lopsided star, a
## teardrop, a panel with wavy edges, an egg or a rounded crystal), each
## with its own random proportions, or no outline at all ("none"): the
## layout fills the whole square board, or a patch of it cut off by one
## sweeping curve, the rest left open. The layouts look nothing alike:
##   garden: strings and motifs (below) scattered over the outline
##   waves: stacked flowing bands across the outline, alternating, some
##          with crests that curl over like breakers
##   whirl: 2-4 big spirals of different sizes, their tails sweeping out to
##          the outline
##   pebbles: a mosaic of lopsided stones of mixed sizes, big ones ringed
##   bloom: 2-4 free-form flowers of their own petal counts on curving stems
##   fan: rays from a hub near the edge crossed by arcs, straight or
##        twisting, cells in a checkerboard
##   branches: curving branches forking from the edge, tipped with leaves,
##             buds or curls
##   lattice: two sets of flowing lines crossing in a warped net, cells in a
##            checkerboard
##   ripples: lopsided contour rings around 1-3 centers, meeting where they
##            run into each other
##   ribbons: 2-4 ribbons crossing, each plain, tied or twisted
##   scales: rows of overlapping fish-scale arcs, gently warped, colored by row
##   truchet: quarter-circle tiles linking into meandering curves and loops,
##            their areas in two families like a checkerboard
##   seeds: dots in a sunflower spiral around an off-center point, colored
##          along the spiral's arms
##   paisleys: nested paisley teardrops with bent tails, mixed sizes
##   chevrons: stacked zigzag bands, stepping through 3 families
## The other layouts may add a filler or two from FILLERS. A garden is:
##   strings: 2-4 curves that cross the outline and divide it, each drawn as
##            one of STRINGS: a sweep, a wave, a loop-de-loop or a ribbon (two
##            edges, plain, tied into cells or twisted, see RIBBONS); some
##            end where they meet an earlier string
##   motifs: 2-4 decorations from MOTIFS, added wherever they fit: echoes
##           (lines following a sweep), scallops along a string, leaves
##           budding off the strings, curls, floating drops and orbs
## Unrelated lines keep CLEAR apart, and strings only ever cross steeply, so
## every area has room for stones.
##
## The lines aren't symmetric, but every one belongs to a family (all the
## leaves, all first echoes, each style of string...), and so do the areas
## inside motifs (marked by a point in each). PictureSources passes families
## on to the collage, where a family stands in for a set of symmetric copies:
## its lines share a gem type, a size profile and a sequence, and its areas
## a pattern and colors.
##
## Output matches MandalaGenerator: polylines in unit space (-1..1, y down),
## plus "families" (an id per polyline), "family_names" (by id) and "marks"
## ([{"at": unit-space point, "family": id}], one inside each motif's areas).

const LAYOUTS := ["garden", "waves", "whirl", "pebbles", "bloom", "fan", "branches", "lattice", "ripples", "ribbons",
		"scales", "truchet", "seeds", "paisleys", "chevrons"]
const SHAPES := ["blob", "paisley", "pebble", "cloud", "tile", "bean", "leaf", "shell", "star", "drop", "panel", "egg",
		"crystal", "none"]
## With no outline, the layout covers only part of the board this often,
## cut off by a sweeping curve.
const PATCH_CHANCE := 0.5
const STRINGS := ["sweep", "wave", "loop", "ribbon"]
## How often each string style comes up.
const STRING_WEIGHTS := {"sweep": 0.35, "wave": 0.25, "loop": 0.15, "ribbon": 0.25}
## plain: two parallel edges; ties: rungs across, making a row of cells;
## twist: the edges cross back and forth, making a chain of lenses.
const RIBBONS := ["plain", "ties", "twist"]
const MOTIFS := ["echoes", "scallops", "leaves", "curls", "drops", "orbs"]
## Motifs the other layouts may add where there's room (blooms always get
## leaves on their stems).
const FILLERS := {"waves": ["drops", "orbs"], "whirl": ["orbs", "drops"], "pebbles": [], "bloom": ["curls", "orbs"],
		"fan": [], "branches": ["orbs", "drops"], "lattice": [], "ripples": [], "ribbons": ["scallops", "curls", "orbs"],
		"scales": [], "truchet": [], "seeds": [], "paisleys": [], "chevrons": []}
## Chances of 2, 3 or 4 strings, and of 2, 3 or 4 motifs.
const STRING_COUNT_WEIGHTS := [0.35, 0.45, 0.2]
const MOTIF_COUNT_WEIGHTS := [0.15, 0.5, 0.35]
## A later string ends on an earlier one this often (when it crosses one).
const T_JUNCTION_CHANCE := 0.35
## Motifs used by this many previous swirls in a row are skipped; layouts
## and outlines skip more, so a run of swirls looks different every time.
const AVOID_RECENT := 2
const AVOID_RECENT_LAYOUTS := 4
const AVOID_RECENT_SHAPES := 8
## Unrelated lines keep at least this far apart (unit space), so the areas
## between them hold stones.
const CLEAR := 0.055
## Where a string comes closer than CLEAR*0.9 to a line it must be crossing
## it: the close stretch may be at most this long (about a 35 degree
## crossing), and at most END_RUN where it starts or ends on a line.
const CROSS_RUN := CLEAR * 3.2
const END_RUN := CLEAR * 1.8
## Spacing of the line points kept for clearance checks.
const STEP := 0.006
## The picture fills this much of the unit square.
const REACH := 0.95
const SAMPLES := 360

var rng := RandomNumberGenerator.new()
var polylines: Array[PackedVector2Array] = []
var closed := PackedByteArray()
var families := PackedInt32Array()
var family_names := PackedStringArray()
var marks := []

## The area the layout fills (the outline, or a patch of the board).
var _outline := PackedVector2Array()
var _patch := false
## Strings drawn so far: {"pts", "owner" (polyline index), "style"}.
var _strings := []
## Line points by grid cell (CLEAR wide), and the polyline each belongs to.
var _grid := {}
var _owners := {}


## options:
##   layout: one of LAYOUTS, or "random" (default)
##   shape: one of SHAPES, or "random" (default)
##   strings: Array of STRINGS to draw, in order, or empty for random (default;
##            garden layout only)
##   ribbon: one of RIBBONS, or "random" (default)
##   motifs: Array of MOTIFS to add, or empty for random (default; garden
##           layout only, the others pick from their FILLERS)
##   recent: Array of earlier results' {"layout", "shape", "motifs"} for
##           swirls made in a row; recent choices are skipped and the least
##           used preferred
## Returns {"seed", "layout", "shape", "patch", "strings", "ribbon", "motifs",
## "polylines", "closed", "families", "family_names", "marks"} ("patch":
## whether an outline-less swirl covers only part of the board). "strings"
## and "motifs" list only what found room.
static func generate(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var g := SwirlGenerator.new()
	g.rng.seed = seed_value
	var recent: Array = options.get("recent", [])
	var layout: String = options.get("layout", "random")
	if not layout in LAYOUTS:
		layout = g._least_used(LAYOUTS, _recent_of(recent, "layout"), AVOID_RECENT_LAYOUTS)
	var shape: String = options.get("shape", "random")
	if not shape in SHAPES:
		shape = g._least_used(SHAPES, _recent_of(recent, "shape"), AVOID_RECENT_SHAPES)
	var ribbon: String = options.get("ribbon", "random")
	if not ribbon in RIBBONS:
		ribbon = RIBBONS[g.rng.randi_range(0, RIBBONS.size() - 1)]
	var motifs := []
	var strings := []
	if layout == "garden":
		motifs = options.get("motifs", []).filter(func(m: String) -> bool: return m in MOTIFS)
		if motifs.is_empty():
			var used := _recent_of(recent, "motifs")
			for _i in 2 + g._weighted(MOTIF_COUNT_WEIGHTS):
				var left := MOTIFS.filter(func(m: String) -> bool: return not m in motifs)
				motifs.append(g._least_used(left, used, AVOID_RECENT))
		strings = options.get("strings", []).filter(func(st: String) -> bool: return st in STRINGS)
		if strings.is_empty():
			for _i in 2 + g._weighted(STRING_COUNT_WEIGHTS):
				strings.append(g._pick(STRING_WEIGHTS))
			# Ribbons go first (they need the most room); echoes and leaves want
			# a sweep to follow.
			strings.sort_custom(func(a: String, b: String) -> bool: return a == "ribbon" and b != "ribbon")
			if ("echoes" in motifs or "leaves" in motifs) and not "sweep" in strings:
				strings[strings.size() - 1] = "sweep"
	else:
		# A filler or two, sometimes none.
		var fillers: Array = FILLERS[layout]
		for f: String in fillers:
			if g.rng.randf() < 0.4:
				motifs.append(f)
		if motifs.is_empty() and layout == "whirl":
			motifs.append(fillers[g.rng.randi_range(0, fillers.size() - 1)])
		if layout == "bloom":
			motifs.append("leaves")

	g._build_outline(shape)
	var drawn := []
	for i in strings.size():
		if g._add_string(strings[i], ribbon, i > 0):
			drawn.append(strings[i])
	if layout != "garden":
		g.call("_build_" + layout)
	var placed := []
	# Motifs that follow the strings first, then ones that float in what's left.
	for motif: String in MOTIFS:
		if motif in motifs and g.call("_add_" + motif):
			placed.append(motif)
	return {
		"seed": seed_value,
		"layout": layout,
		"shape": shape,
		"patch": g._patch,
		"strings": drawn,
		"ribbon": ribbon if "ribbon" in drawn else "",
		"motifs": placed,
		"polylines": g.polylines,
		"closed": g.closed,
		"families": g.families,
		"family_names": g.family_names,
		"marks": g.marks,
	}


## Every value of `key` in the recent results, in order.
static func _recent_of(recent: Array, key: String) -> Array:
	var out := []
	for r in recent:
		var v: Variant = r.get(key) if r is Dictionary else null
		if v is Array:
			out.append_array(v)
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


## An index into `weights`, picked by weight.
func _weighted(weights: Array) -> int:
	var x := rng.randf()
	for i in weights.size():
		x -= weights[i]
		if x <= 0.0:
			return i
	return weights.size() - 1


func _pick(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var x := rng.randf() * total
	for k in weights:
		x -= weights[k]
		if x <= 0.0:
			return k
	return weights.keys()[0]


## The id of a family, by name.
func _family(name: String) -> int:
	var id := family_names.find(name)
	if id < 0:
		id = family_names.size()
		family_names.append(name)
	return id


## Draws a line of `family` and remembers its points for clearance checks.
## Returns its polyline index.
func _add(pts: PackedVector2Array, is_closed: bool, family: String) -> int:
	var owner := polylines.size()
	polylines.append(pts)
	closed.append(1 if is_closed else 0)
	families.append(_family(family))
	for q in _even(pts, is_closed, STEP):
		var key := Vector2i(floori(q.x / CLEAR), floori(q.y / CLEAR))
		if not _grid.has(key):
			_grid[key] = PackedVector2Array()
			_owners[key] = PackedInt32Array()
		_grid[key].append(q)
		_owners[key].append(owner)
	return owner


func _mark(at: Vector2, family: String) -> void:
	marks.append({"at": at, "family": _family(family)})


## The nearest line point to p within `radius`, ignoring polylines in
## `skip`: [distance, point] ([radius, p] if there is none).
func _nearest(p: Vector2, radius: float, skip: Array = []) -> Array:
	var best := radius
	var at := p
	var c := Vector2i(floori(p.x / CLEAR), floori(p.y / CLEAR))
	var span := ceili(radius / CLEAR)
	for dy in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var key := Vector2i(c.x + dx, c.y + dy)
			if not _grid.has(key):
				continue
			var pts: PackedVector2Array = _grid[key]
			var own: PackedInt32Array = _owners[key]
			for i in pts.size():
				var d := p.distance_to(pts[i])
				if d < best and (skip.is_empty() or not own[i] in skip):
					best = d
					at = pts[i]
	return [best, at]


func _inside(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, _outline)


# --- outline -------------------------------------------------------------------------

func _build_outline(shape: String) -> void:
	var pts := PackedVector2Array()
	match shape:
		"paisley":
			# A teardrop whose tip curls around the body.
			var m := rng.randf_range(0.8, 1.2)
			var curl := rng.randf_range(0.45, 0.75) * (1.0 if rng.randf() < 0.5 else -1.0)
			var body := Vector2(0.0, 0.3)
			for i in SAMPLES:
				var t := TAU * i / SAMPLES
				var p := Vector2(sin(t) * pow(sin(t / 2.0), m) * 0.8, -cos(t))
				var u := clampf((-p.y - 0.1) / 0.9, 0.0, 1.0)
				pts.append(body + (p - body).rotated(curl * u * u))
			pts = _turned(pts, rng.randf_range(-0.5, 0.5))
		"pebble":
			var b := rng.randf_range(0.6, 0.8)
			var n := rng.randf_range(2.4, 3.2)
			var wob := _harmonics(0.03)
			for i in SAMPLES:
				var t := TAU * i / SAMPLES
				var r := pow(pow(absf(cos(t)), n) + pow(absf(sin(t)) / b, n), -1.0 / n)
				pts.append(Vector2.from_angle(t) * r * _radius_at(wob, t))
			pts = _turned(pts, rng.randf_range(-0.6, 0.6))
		"tile":
			# A squarish panel with rounded corners, upright.
			var b := rng.randf_range(0.75, 1.0)
			var n := rng.randf_range(4.0, 6.0)
			for i in SAMPLES:
				var t := TAU * i / SAMPLES
				pts.append(Vector2.from_angle(t) * pow(pow(absf(cos(t)), n) + pow(absf(sin(t)) / b, n), -1.0 / n))
		"bean":
			var wob := _harmonics(0.04)
			var dent := rng.randf_range(0.2, 0.32)
			var width := rng.randf_range(0.5, 0.8)
			var at := rng.randf() * TAU
			for i in SAMPLES:
				var t := TAU * i / SAMPLES
				var off := angle_difference(t, at)
				var r := _radius_at(wob, t) * (1.0 - dent * exp(-off * off / (width * width)))
				pts.append(Vector2.from_angle(t) * r * Vector2(1.0, 0.72))
			pts = _turned(pts, rng.randf_range(-0.5, 0.5))
		"leaf":
			# Two sides of different fullness about a bent midrib.
			var upper := rng.randf_range(0.35, 0.6)
			var lower := rng.randf_range(0.3, 0.55)
			var bend := rng.randf_range(-0.25, 0.25)
			var widest := rng.randf_range(0.7, 1.2)
			var half := SAMPLES / 2
			for i in half:
				var t := float(i) / half
				var mid := bend * (1.0 - pow(2.0 * t - 1.0, 2.0))
				pts.append(Vector2(2.0 * t - 1.0, mid - upper * pow(sin(PI * pow(t, widest)), 0.9)))
			for i in half:
				var t := 1.0 - float(i) / half
				var mid := bend * (1.0 - pow(2.0 * t - 1.0, 2.0))
				pts.append(Vector2(2.0 * t - 1.0, mid + lower * pow(sin(PI * pow(t, widest)), 0.9)))
			pts = _turned(pts, rng.randf_range(-0.8, 0.8))
		"shell":
			# A fan from a hinge, its rim scalloped, one side longer.
			var left := rng.randf_range(0.6, 1.1)
			var right := rng.randf_range(0.6, 1.1)
			var bumps := rng.randi_range(6, 10)
			var depth := rng.randf_range(0.04, 0.08)
			var hinge := Vector2(0.0, 0.0)
			for i in SAMPLES:
				var u := float(i) / SAMPLES
				var t := -PI / 2.0 - left + (left + right) * u
				var r := 1.0 - depth * absf(sin(PI * bumps * u))
				pts.append(hinge + Vector2.from_angle(t) * r)
			pts.append(hinge + Vector2.from_angle(-PI / 2.0 + right) * 0.18)
			pts.append(hinge)
			pts.append(hinge + Vector2.from_angle(-PI / 2.0 - left) * 0.18)
			pts = _turned(_even(pts, true, 0.01), rng.randf_range(-0.6, 0.6))
		"star":
			var arms := rng.randi_range(4, 7)
			var base_r := rng.randf_range(0.4, 0.55)
			var a0 := rng.randf() * TAU
			var dirs := []
			for k in arms:
				dirs.append([a0 + TAU * (k + rng.randf_range(-0.2, 0.2)) / arms, rng.randf_range(0.75, 1.0)])
			var spread := TAU / arms * rng.randf_range(0.28, 0.4)
			for i in SAMPLES:
				var t := TAU * i / SAMPLES
				var r := base_r
				for arm: Array in dirs:
					var off := angle_difference(t, arm[0])
					r = maxf(r, base_r + (arm[1] - base_r) * exp(-off * off / (spread * spread)))
				pts.append(Vector2.from_angle(t) * r)
		"drop":
			var m := rng.randf_range(0.5, 0.9)
			var fat := rng.randf_range(0.65, 0.85)
			for i in SAMPLES:
				var t := TAU * i / SAMPLES
				pts.append(Vector2(sin(t) * pow(sin(t / 2.0), m) * fat, -cos(t)))
			pts = _turned(pts, rng.randf_range(-PI, PI))
		"panel":
			# A rectangle whose top and bottom edges wave, of different lengths.
			var h := rng.randf_range(0.6, 0.85)
			var waves := [rng.randf_range(0.04, 0.09), rng.randf_range(1.0, 2.5), rng.randf() * TAU]
			var waves2 := [rng.randf_range(0.03, 0.09), rng.randf_range(1.0, 2.5), rng.randf() * TAU]
			var side := rng.randf_range(-0.08, 0.08)
			var q := SAMPLES / 4
			for i in q:
				var x := -1.0 + 2.0 * i / q
				pts.append(Vector2(x, -h + waves[0] * sin(PI * waves[1] * x + waves[2])))
			for i in q:
				var y := -h + 2.0 * h * i / q
				pts.append(Vector2(1.0 + side * sin(PI * (y + h) / (2.0 * h)), y))
			for i in q:
				var x := 1.0 - 2.0 * i / q
				pts.append(Vector2(x, h + waves2[0] * sin(PI * waves2[1] * x + waves2[2])))
			for i in q:
				var y := h - 2.0 * h * i / q
				pts.append(Vector2(-1.0 - side * sin(PI * (y + h) / (2.0 * h)), y))
			pts = _turned(_even(_closed_spline(pts, 1), true, 0.01), rng.randf_range(-0.25, 0.25))
		"egg":
			var b := rng.randf_range(0.65, 0.85)
			var k := rng.randf_range(0.12, 0.25)
			for i in SAMPLES:
				var t := TAU * i / SAMPLES
				pts.append(Vector2(cos(t), sin(t) * b * (1.0 + k * cos(t))))
			pts = _turned(pts, rng.randf_range(-PI, PI))
		"crystal":
			# An uneven polygon with rounded corners.
			var corners := rng.randi_range(5, 7)
			var ctrl := PackedVector2Array()
			var a0 := rng.randf() * TAU
			for k in corners:
				var t := a0 + TAU * (k + rng.randf_range(-0.25, 0.25)) / corners
				var r := rng.randf_range(0.75, 1.0)
				ctrl.append(Vector2.from_angle(t) * r)
				# Straight-ish sides: a point partway to the next corner.
				var t2 := a0 + TAU * (k + 0.5 + rng.randf_range(-0.1, 0.1)) / corners
				ctrl.append(Vector2.from_angle(t2) * r * cos(PI / corners) * 1.02)
			pts = _even(_closed_spline(ctrl, 24), true, 0.01)
		"cloud":
			var base := _harmonics(0.05)
			# Bumps of uneven widths and heights around the edge.
			var count := rng.randi_range(7, 11)
			var edges := PackedFloat32Array([0.0])
			for _i in count:
				edges.append(edges[edges.size() - 1] + rng.randf_range(0.6, 1.4))
			var heights := PackedFloat32Array()
			for _i in count:
				heights.append(rng.randf_range(0.05, 0.1))
			var start := rng.randf() * TAU
			var j := 0
			for i in SAMPLES:
				var at := float(i) / SAMPLES * edges[count]
				while j < count - 1 and at > edges[j + 1]:
					j += 1
				var u := (at - edges[j]) / (edges[j + 1] - edges[j])
				var t := start + TAU * i / SAMPLES
				pts.append(Vector2.from_angle(t) * _radius_at(base, t) * (1.0 + heights[j] * pow(sin(PI * u), 0.7)))
		_:
			var wob := _harmonics(0.1)
			for i in SAMPLES:
				var t := TAU * i / SAMPLES
				pts.append(Vector2.from_angle(t) * _radius_at(wob, t))
	if shape == "none":
		_build_board()
		return
	# Centered in the square, as big as it goes.
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	var k := REACH * 2.0 / maxf(box.size.x, box.size.y)
	for i in pts.size():
		pts[i] = (pts[i] - box.get_center()) * k
	_outline = pts
	_add(pts, true, "outline")


## No outline: the board's own square edge. Sometimes a sweeping curve from
## one edge to another cuts off a patch for the layout to fill, the rest
## of the board left open.
func _build_board() -> void:
	var square := PackedVector2Array()
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for k in 4:
		var a: Vector2 = corners[k] * REACH
		var b: Vector2 = corners[(k + 1) % 4] * REACH
		for i in SAMPLES / 4:
			square.append(a.lerp(b, float(i) / (SAMPLES / 4)))
	_outline = square
	_add(square, true, "outline")
	if rng.randf() >= PATCH_CHANCE:
		return
	for _attempt in 20:
		var cut := _clip(_curve())
		if cut.size() < 2:
			continue
		# The board's edge from where the cut ends round to where it starts
		# closes the patch on one side of it.
		var i0 := _closest_index(square, cut[0])
		var i1 := _closest_index(square, cut[cut.size() - 1])
		var n := square.size()
		var walk := PackedVector2Array()
		var forward := rng.randf() < 0.5
		var i := i1
		while i != i0:
			walk.append(square[i])
			i = (i + (1 if forward else -1) + n) % n
		var patch := cut.duplicate()
		patch.append_array(walk)
		var area := absf(_area(patch))
		if area < 4.0 * REACH * REACH * 0.35 or area > 4.0 * REACH * REACH * 0.75:
			continue
		_strings.append({"pts": cut, "owner": _add(cut, false, "patch_edge"), "style": "sweep"})
		_outline = patch
		_patch = true
		return


static func _closest_index(pts: PackedVector2Array, p: Vector2) -> int:
	var best := 0
	for i in pts.size():
		if pts[i].distance_squared_to(p) < pts[best].distance_squared_to(p):
			best = i
	return best


## Signed area of a polygon.
static func _area(pts: PackedVector2Array) -> float:
	var sum := 0.0
	for i in pts.size():
		sum += pts[i].cross(pts[(i + 1) % pts.size()])
	return sum / 2.0


## Lopsided radius harmonics: 2-, 3- and 4-fold waves of random phase,
## about `amp`, `amp` / 2 and `amp` / 4 strong.
func _harmonics(amp: float) -> Array:
	var out := []
	for k in [2, 3, 4]:
		out.append([k, rng.randf_range(0.6, 1.4) * amp * 2.0 / k, rng.randf() * TAU])
	return out


static func _radius_at(harmonics: Array, t: float) -> float:
	var r := 1.0
	for h: Array in harmonics:
		r += h[1] * cos(h[0] * t + h[2])
	return r


static func _turned(pts: PackedVector2Array, angle: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p.rotated(angle))
	return out


# --- strings -------------------------------------------------------------------------

## Draws one string across the outline, trying a few curves until one meets
## the lines already there cleanly. `may_end`: it may stop at an earlier string.
func _add_string(style: String, ribbon: String, may_end: bool) -> bool:
	for _attempt in 40:
		var curve := _curve()
		match style:
			"ribbon":
				if _add_ribbon(curve, ribbon):
					return true
				continue
			"wave":
				curve = _waved(_clip(curve))
			"loop":
				curve = _looped(_clip(curve))
			_:
				curve = _clip(curve)
		if curve.size() < 2 or Contours.length(curve, false) < 0.4:
			continue
		if may_end and style != "loop" and rng.randf() < T_JUNCTION_CHANCE:
			curve = _ended(curve)
		if not _crosses_cleanly(curve):
			continue
		_strings.append({"pts": curve, "owner": _add(curve, false, "string_" + style), "style": style})
		return true
	return false


## A smooth curve between two points of the outline far apart along it,
## bowing to one side or in an S, running on a little past both ends.
func _curve() -> PackedVector2Array:
	var n := _outline.size()
	var i := rng.randi_range(0, n - 1)
	var j := (i + n / 2 + rng.randi_range(-n / 5, n / 5)) % n
	var a := _outline[i]
	var b := _outline[j]
	var d := b - a
	var side := Vector2(-d.y, d.x)
	var bow := rng.randf_range(0.08, 0.3) * (1.0 if rng.randf() < 0.5 else -1.0)
	var s_bend := rng.randf() < 0.4
	var ctrl := PackedVector2Array([
		a - d * 0.25,
		a,
		a + d * rng.randf_range(0.28, 0.38) + side * bow,
		a + d * rng.randf_range(0.62, 0.72) + side * bow * (-0.8 if s_bend else rng.randf_range(0.5, 1.1)),
		b,
		b + d * 0.25,
	])
	return _even(_spline(ctrl, 48), false, STEP)


## The curve with a sideways wave that fades out at both ends.
func _waved(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var amp := rng.randf_range(0.045, 0.07)
	var wavelength := rng.randf_range(0.45, 0.65)
	var phase := rng.randf() * TAU
	var length := Contours.length(pts, false)
	var normals := _normals(pts, false)
	var out := PackedVector2Array()
	var s := 0.0
	for i in pts.size():
		if i > 0:
			s += pts[i].distance_to(pts[i - 1])
		var fade := smoothstep(0.0, 0.12, s) * smoothstep(0.0, 0.12, length - s)
		out.append(pts[i] + normals[i] * amp * fade * sin(TAU * s / wavelength + phase))
	return out


## The curve with a loop-de-loop near its middle: it rises to one side,
## curls back over the top and crosses itself on the way down, like a
## joined-up letter e. The loop follows the curve, so it joins smoothly.
func _looped(pts: PackedVector2Array) -> PackedVector2Array:
	var length := Contours.length(pts, false)
	var r := rng.randf_range(0.07, 0.1)
	if length < r * 10.0:
		return PackedVector2Array()
	var mid := length * rng.randf_range(0.35, 0.65)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	# The loop in the curve's own frame: x along it from `mid`, y to the side.
	var local := _spline(PackedVector2Array([
		Vector2(-4.0, 0.0), Vector2(-3.0, 0.0), Vector2(-1.2, 0.1), Vector2(0.2, 0.6), Vector2(0.6, 1.4),
		Vector2(0.0, 2.0), Vector2(-0.7, 1.4), Vector2(-0.3, 0.5), Vector2(0.9, 0.05), Vector2(3.0, 0.0),
		Vector2(4.0, 0.0),
	]), 16)
	var normals := _normals(pts, false)
	var out := PackedVector2Array()
	var s := 0.0
	var looped := false
	for i in pts.size():
		if i > 0:
			s += pts[i].distance_to(pts[i - 1])
		if absf(s - mid) > r * 3.0:
			out.append(pts[i])
		elif not looped:
			looped = true
			for q in local:
				var at := clampf(mid + q.x * r, 0.0, length)
				var k := clampi(int(at / length * (pts.size() - 1)), 0, pts.size() - 1)
				out.append(Contours.sample(pts, false, at)[0] + normals[k] * q.y * r * side)
	return out


## The curve stopped where it first crosses an earlier line (past its
## first stretch), ending exactly on that line. Unchanged if it crosses none.
func _ended(pts: PackedVector2Array) -> PackedVector2Array:
	var probe := _even(pts, false, CLEAR / 4.0)
	var far_seen := false
	var best := -1
	var best_d := INF
	for i in probe.size():
		var hit: Array = _nearest(probe[i], CLEAR)
		var close: bool = hit[0] < CLEAR * 0.9
		if not close:
			far_seen = true
			if best >= 0:
				break
		elif far_seen and i * CLEAR / 4.0 > 0.3 and hit[0] < best_d:
			best = i
			best_d = hit[0]
	if best < 0:
		return pts
	var out := probe.slice(0, best + 1)
	out.append(_nearest(probe[best], CLEAR)[1])
	return out


## A ribbon along the curve: two edges, plain, tied into cells or twisted
## into a chain of lenses, with its areas marked.
func _add_ribbon(curve: PackedVector2Array, kind: String) -> bool:
	var w := rng.randf_range(0.055, 0.075)
	var wavelength := rng.randf_range(0.34, 0.46)
	var normals := _normals(curve, false)
	var edges: Array[PackedVector2Array] = []
	for sgn: float in [1.0, -1.0]:
		var edge := PackedVector2Array()
		var s := 0.0
		for i in curve.size():
			if i > 0:
				s += curve[i].distance_to(curve[i - 1])
			var off := w * (sin(TAU * s / wavelength) if kind == "twist" else 1.0)
			edge.append(curve[i] + normals[i] * off * sgn)
		edges.append(_clip(edge))
	var middle := _clip(curve)
	if middle.size() < 2 or Contours.length(middle, false) < 0.5:
		return false
	for edge in edges:
		if edge.size() < 2 or not _crosses_cleanly(edge):
			return false
	var owners := [_add(edges[0], false, "ribbon"), _add(edges[1], false, "ribbon")]
	_strings.append({"pts": middle, "owner": owners[0], "style": "ribbon"})
	var length := Contours.length(middle, false)
	var mid_normals := _normals(middle, false)
	var spacing := wavelength / 2.0 if kind == "twist" else rng.randf_range(0.14, 0.2)
	var s := spacing * 0.5
	# The twist's edges cross every half wavelength from where the curve
	# started (before it was clipped), so its lenses sit between.
	if kind == "twist":
		var cut := _arc_to(curve, middle[0])
		s = spacing * (ceilf(cut / spacing - 0.5) + 0.5) - cut
	while s < length - 0.02:
		var at: Vector2 = Contours.sample(middle, false, s)[0]
		var k := clampi(int(s / length * (middle.size() - 1)), 0, middle.size() - 1)
		var n := mid_normals[k]
		if kind == "ties" and s + spacing * 0.5 < length - 0.04:
			# A rung across, half a cell on.
			var c: Vector2 = Contours.sample(middle, false, s + spacing * 0.5)[0]
			var rung := PackedVector2Array([c + n * w * 1.05, c - n * w * 1.05])
			if _inside(rung[0]) and _inside(rung[1]) and _nearest(c, CLEAR * 0.6, owners)[0] >= CLEAR * 0.6:
				_add(rung, false, "ribbon_tie")
		if _inside(at) and _nearest(at, w * 0.5, owners)[0] >= w * 0.5:
			_mark(at, "ribbon" if kind == "plain" else "ribbon_cell")
		s += spacing
	return true


## Arc length along `pts` to its point nearest `p`.
static func _arc_to(pts: PackedVector2Array, p: Vector2) -> float:
	var s := 0.0
	var best := INF
	var at := 0.0
	for i in pts.size():
		if i > 0:
			s += pts[i].distance_to(pts[i - 1])
		var d := pts[i].distance_squared_to(p)
		if d < best:
			best = d
			at = s
	return at


## Whether a new string meets the lines already drawn cleanly: wherever it
## comes within CLEAR of one it must be crossing it (or starting or ending
## on it) steeply, never running alongside, and it stays inside the outline.
func _crosses_cleanly(pts: PackedVector2Array, skip: Array = []) -> bool:
	var step := CLEAR / 4.0
	var probe := _even(pts, false, step)
	var run := 0.0
	var first := true
	for i in probe.size():
		if i > 0 and i < probe.size() - 1 and not _inside(probe[i]):
			return false
		if _nearest(probe[i], CLEAR, skip)[0] < CLEAR * 0.9:
			run += step
		else:
			if run > (END_RUN if first else CROSS_RUN):
				return false
			run = 0.0
			first = false
	return run <= END_RUN


## The stretches of a line that meet the lines already drawn cleanly (see
## _crosses_cleanly): where it runs alongside one it is cut, leaving
## the stretches between that are at least 0.12 long.
func _clean_parts(pts: PackedVector2Array) -> Array[PackedVector2Array]:
	var step := CLEAR / 4.0
	var probe := _even(pts, false, step)
	var close := PackedByteArray()
	for q in probe:
		close.append(1 if _nearest(q, CLEAR)[0] < CLEAR * 0.9 else 0)
	# Runs of close points that are too long are cut out.
	var bad := PackedByteArray()
	bad.resize(probe.size())
	var i := 0
	while i < probe.size():
		if not close[i]:
			i += 1
			continue
		var j := i
		while j < probe.size() and close[j]:
			j += 1
		var at_end := i == 0 or j == probe.size()
		if (j - i) * step > (END_RUN if at_end else CROSS_RUN):
			for k in range(i, j):
				bad[k] = 1
		i = j
	var out: Array[PackedVector2Array] = []
	var cur := PackedVector2Array()
	for k in probe.size():
		if bad[k]:
			if Contours.length(cur, false) >= 0.12:
				out.append(cur)
			cur = PackedVector2Array()
		else:
			cur.append(probe[k])
	if Contours.length(cur, false) >= 0.12:
		out.append(cur)
	return out


## Whether a motif's line stays inside the outline and `k` x CLEAR from
## every line (but the polylines in `skip`), except within `free` of the
## points in `attach`, where it may touch the line it grows from.
func _fits(pts: PackedVector2Array, is_closed: bool, k: float, attach := PackedVector2Array(),
		free := 0.0, skip: Array = []) -> bool:
	for q in _even(pts, is_closed, CLEAR / 4.0):
		var near := false
		for a in attach:
			if q.distance_to(a) < free:
				near = true
		if near:
			continue
		if not _inside(q) or _nearest(q, CLEAR * k, skip)[0] < CLEAR * k:
			return false
	return true


# --- layouts -------------------------------------------------------------------------

## Waves: stacked flowing lines across the outline, the bands between them in
## two alternating families, some crests curling over like breakers.
func _build_waves() -> void:
	var d := Vector2.from_angle(rng.randf_range(-0.45, 0.45) + (PI / 2.0 if rng.randf() < 0.3 else 0.0))
	var n := Vector2(-d.y, d.x)
	var span := _extent(n)
	var count := rng.randi_range(4, 8)
	var wavelength := rng.randf_range(0.5, 1.0)
	var amp := rng.randf_range(0.02, 0.09)
	var drift := rng.randf_range(-0.8, 0.8)
	var phase := rng.randf() * TAU
	var step := (span.y - span.x) / (count + 1)
	var waves := _wave_set(d, n, span.x, step, count, wavelength, amp, drift, phase, "wave_%d")
	for i in waves.size() - 1:
		_mark_between(d, n, waves[i], waves[i + 1], wavelength, "wave_band_%d" % (i % 2))
	if rng.randf() < 0.4:
		return
	# Crests (the lowest points toward -n) curl over the way the wind blows.
	var wind := 1.0 if rng.randf() < 0.5 else -1.0
	var r := clampf(step * 0.3, 0.07, 0.12)
	var every := rng.randi_range(1, 2)
	for i in range(0, waves.size(), every):
		var x := -1.6
		var prev := INF
		var falling := false
		while x <= 1.6:
			var off := _wave_at(waves[i], x, wavelength)
			if falling and off > prev:
				var at := d * (x - STEP) + n * prev
				var dir := (-n + d * wind * 0.7).normalized()
				for turn: float in [wind, -wind]:
					var curl := _curl(at, dir, r * rng.randf_range(0.85, 1.15), turn)
					if _inside(at) and _fits(curl, false, 0.8, PackedVector2Array([at]), CLEAR * 1.3):
						_add(curl, false, "crest")
						break
			falling = off < prev
			prev = off
			x += 0.01


## How far the outline reaches along n: (least, most).
func _extent(n: Vector2) -> Vector2:
	var lo := INF
	var hi := -INF
	for p in _outline:
		lo = minf(lo, p.dot(n))
		hi = maxf(hi, p.dot(n))
	return Vector2(lo, hi)


## A wave's offset across at x along: [position, amplitude, phase], plus a
## fourth value for a zigzag.
static func _wave_at(wave: Array, x: float, wavelength: float) -> float:
	if wave.size() > 3:
		# A zigzag.
		return wave[0] + wave[1] * asin(sin(TAU * x / wavelength + wave[2])) * 2.0 / PI
	return (wave[0] + wave[1] * sin(TAU * x / wavelength + wave[2])
			+ wave[1] * 0.35 * sin(TAU * x / (wavelength * 2.3) + wave[2] * 1.7))


## `count` waving lines along d, stacked `step` apart across (n) from `lo`,
## each a little out of phase with the last (zigzags if `zigzag`). Families alternate by
## `family` % (index % 2). Returns the [position, amplitude, phase] of the
## lines drawn, in order.
func _wave_set(d: Vector2, n: Vector2, lo: float, step: float, count: int, wavelength: float, amp: float,
		drift: float, phase: float, family: String, zigzag := false) -> Array:
	var waves := []
	for i in count:
		for _attempt in 8:
			var wave := [lo + step * (i + 1) + rng.randf_range(-0.2, 0.2) * step, amp * rng.randf_range(0.6, 1.4),
					phase + drift * i + rng.randf_range(-0.3, 0.3)]
			if zigzag:
				wave.append(1.0)
			var pts := PackedVector2Array()
			var x := -1.6
			while x <= 1.6:
				pts.append(d * x + n * _wave_at(wave, x, wavelength))
				x += STEP
			pts = _clip(pts)
			if pts.size() < 2 or Contours.length(pts, false) < 0.3 or not _crosses_cleanly(pts):
				continue
			_strings.append({"pts": pts, "owner": _add(pts, false, family % (i % 2)), "style": "wave"})
			waves.append(wave)
			break
	return waves


## Marks the band between two waves of a set every so often.
func _mark_between(d: Vector2, n: Vector2, a: Array, b: Array, wavelength: float, family: String) -> void:
	var x := -1.6
	while x <= 1.6:
		var at := d * x + n * (_wave_at(a, x, wavelength) + _wave_at(b, x, wavelength)) / 2.0
		if _inside(at) and _nearest(at, CLEAR * 0.5)[0] >= CLEAR * 0.5:
			_mark(at, family)
		x += 0.1


## Whirl: 2-4 big spirals of different sizes, each winding out from its
## center and sweeping off in a tail to the outline. The lanes between their
## turns are one family.
func _build_whirl() -> void:
	var count := rng.randi_range(3, 5)
	var gap := rng.randf_range(0.075, 0.1)
	var biggest := rng.randf_range(0.38, 0.55)
	var flare := rng.randf_range(0.12, 0.3)
	for i in count:
		for _attempt in 25:
			var c := _random_inside()
			var room: float = _nearest(c, biggest + CLEAR)[0] - CLEAR
			var r_max := minf(room, biggest * (1.0 if i == 0 else rng.randf_range(0.5, 0.85)))
			if r_max < gap * 2.0:
				continue
			var turn := 1.0 if rng.randf() < 0.5 else -1.0
			var a0 := rng.randf() * TAU
			var r0 := gap * 0.6
			var pts := PackedVector2Array()
			var theta := 0.0
			var end := INF
			while theta < end + TAU:
				var r := r0 + gap * theta / TAU
				if r >= r_max and end == INF:
					end = theta
				if theta > end:
					r += flare * pow(theta - end, 2.0)
				var p := c + Vector2.from_angle(a0 + theta * turn) * r
				pts.append(p)
				if not _inside(p):
					break
				theta += STEP / r
			# It may have run into the outline before winding out to full size.
			end = minf(end, theta)
			pts = _clip(pts)
			if pts.size() < 2 or not _crosses_cleanly(pts):
				continue
			_strings.append({"pts": pts, "owner": _add(pts, false, "whirl"), "style": "whirl"})
			var t := TAU * 0.5
			while t < end - 0.5:
				_mark(c + Vector2.from_angle(a0 + t * turn) * (r0 + gap * (t / TAU + 0.5)), "whirl_lane")
				t += 1.3
			break


## Pebbles: a mosaic of lopsided stones of mixed sizes, each the biggest that
## fits where it lands; big ones sometimes ringed.
func _build_pebbles() -> void:
	var gap := CLEAR * rng.randf_range(0.85, 1.1)
	var biggest := rng.randf_range(0.14, 0.24)
	var lumpy := rng.randf_range(0.03, 0.09)
	var ringed := rng.randf_range(0.3, 0.8)
	for _p in 40:
		var best_r := 0.0
		var best_c := Vector2.ZERO
		for _try in 30:
			var c := _random_inside()
			var r := minf(_nearest(c, biggest + gap)[0] - gap, biggest * rng.randf_range(0.55, 1.0))
			if r > best_r:
				best_r = r
				best_c = c
		if best_r < 0.065:
			break
		var wob := _harmonics(lumpy)
		var turn := rng.randf() * TAU
		var shape := PackedVector2Array()
		for i in 64:
			var t := TAU * i / 64.0
			shape.append(Vector2.from_angle(t + turn) * _radius_at(wob, t) / (1.0 + lumpy * 2.5))
		var outer := PackedVector2Array()
		for q in shape:
			outer.append(best_c + q * best_r)
		_add(outer, true, "pebble")
		if best_r >= 0.12 and rng.randf() < ringed:
			var inner := PackedVector2Array()
			for q in shape:
				inner.append(best_c + q * best_r * 0.5)
			_add(inner, true, "pebble_core")
			_mark(best_c, "pebble_core")
			_mark(best_c + Vector2.from_angle(turn) * best_r * 0.72, "pebble_ring")
		else:
			_mark(best_c, "pebble_big" if best_r >= 0.12 else "pebble")


## Bloom: 2-4 free-form flowers, each with its own petal count and lean, on
## stems that curve down to the outline.
func _build_bloom() -> void:
	var count := rng.randi_range(2, 4)
	var petal_base := rng.randi_range(5, 9)
	var down := Vector2.DOWN.rotated(rng.randf_range(-0.6, 0.6))
	var ratio := rng.randf_range(0.22, 0.34)
	var long_short := rng.randf() < 0.3
	for i in count:
		var want := rng.randf_range(0.22, 0.36) * (1.0 if i == 0 else rng.randf_range(0.65, 0.9))
		for _attempt in 3:
			# The roomiest of a few spots, the flower sized to it.
			var c := Vector2.ZERO
			var room := 0.0
			for _try in 40:
				var q := _random_inside()
				var d: float = _nearest(q, want * 1.45 + CLEAR)[0]
				if d > room:
					room = d
					c = q
			var rc := rng.randf_range(0.22, 0.32)
			var length := minf(want, (room - CLEAR) / (rc + 1.15))
			rc *= length
			if length < 0.1:
				break
			var n := clampi(petal_base + rng.randi_range(-1, 1), 4, 12)
			var mid := rc + length * 0.4
			var w := minf(length * ratio, mid * sin(PI / n) - CLEAR * 0.3)
			if w < 0.025:
				continue
			var a0 := rng.randf() * TAU
			var curl := rng.randf_range(-0.25, 0.25)
			_add(MandalaGenerator.circle(c, rc, 32), true, "bloom_center")
			_mark(c, "bloom_center")
			var stem_at := Vector2.ZERO
			var stem_dir := Vector2.ZERO
			for k in n:
				var dir := Vector2.from_angle(a0 + TAU * k / n + rng.randf_range(-0.06, 0.06))
				var petal_len := length * (rng.randf_range(0.88, 1.12) if not long_short else (1.0 if k % 2 == 0 else 0.7))
				var petal := _leaf(c + dir * rc, dir, petal_len, curl, w / length)
				_add(petal["outline"], true, "petal")
				_mark(petal["inside"], "petal")
				if stem_dir == Vector2.ZERO or dir.dot(down) > stem_dir.dot(down):
					stem_dir = dir
					stem_at = c + dir * (rc + petal_len)
			_add_stem(stem_at, stem_dir, down)
			break


## A stem from a petal tip curving down to the outline (if it can).
func _add_stem(from: Vector2, dir: Vector2, down: Vector2) -> void:
	for _attempt in 10:
		var to := from
		var best := -INF
		for q in _outline:
			var score := (q - from).normalized().dot(down.rotated(rng.randf_range(-0.5, 0.5))) - q.distance_to(from) * 0.3
			if score > best:
				best = score
				to = q
		var across := (to - from).orthogonal() * rng.randf_range(-0.25, 0.25)
		var stem := _clip(_even(_spline(PackedVector2Array([from - dir * 0.2, from, from.lerp(to, 0.5) + across, to,
				to + (to - from) * 0.2]), 32), false, STEP))
		if stem.size() > 2 and _crosses_cleanly(stem):
			_strings.append({"pts": stem, "owner": _add(stem, false, "stem"), "style": "stem"})
			return


## Fan: rays from a hub near the edge, straight or twisting, crossed by arcs
## around it; the cells between take two families in a checkerboard.
func _build_fan() -> void:
	var edge := _outline[rng.randi_range(0, _outline.size() - 1)]
	var o := edge.lerp(Vector2.ZERO, rng.randf_range(0.15, 0.35))
	var r0 := rng.randf_range(0.1, 0.16)
	var wavy := rng.randf_range(0.015, 0.03) if rng.randf() < 0.4 else 0.0
	for piece: Array in _clip_all(MandalaGenerator.circle(o, r0, 64), true):
		_add(piece[0], piece[1], "fan_hub")
	if _inside(o):
		_mark(o, "fan_hub")
	var radii := [r0]
	var r := r0
	var spacing := rng.randf_range(0.13, 0.2)
	var grow := rng.randf_range(1.0, 1.2)
	while r < 2.6:
		r += spacing
		spacing *= grow
		var ring := PackedVector2Array()
		var waves := maxi(3, roundi(TAU * r / 0.3))
		var segs := maxi(64, int(r * 400.0))
		for i in segs:
			var t := TAU * i / segs
			ring.append(o + Vector2.from_angle(t) * (r + wavy * sin(waves * t)))
		var drawn := false
		for piece: Array in _clip_all(ring, true):
			if piece[1] or _crosses_cleanly(piece[0]):
				_add(piece[0], piece[1], "fan_arc")
				drawn = true
		if drawn:
			radii.append(r)
	var count := clampi(rng.randi_range(7, 14), 5, int(TAU * r0 / (CLEAR * 1.3)))
	var twist := rng.randf_range(0.6, 1.4) * (1.0 if rng.randf() < 0.5 else -1.0) if rng.randf() < 0.5 else 0.0
	var a0 := rng.randf() * TAU
	var angles := []
	for i in count:
		angles.append(a0 + TAU * (i + rng.randf_range(-0.2, 0.2)) / count)
	var drawn_rays := []
	for i in count:
		var ray := PackedVector2Array()
		var rr := r0
		while rr < 2.8:
			ray.append(o + Vector2.from_angle(angles[i] + twist * (rr - r0)) * rr)
			rr += STEP
		ray = _clip(ray)
		var ok := ray.size() > 2 and _crosses_cleanly(ray)
		if ok:
			_add(ray, false, "fan_ray")
		drawn_rays.append(ok)
	for i in count:
		if not drawn_rays[i] or not drawn_rays[(i + 1) % count]:
			continue
		var next: float = angles[(i + 1) % count] + (TAU if i == count - 1 else 0.0)
		for j in radii.size() - 1:
			var rm: float = (radii[j] + radii[j + 1]) / 2.0
			var at := o + Vector2.from_angle((angles[i] + next) / 2.0 + twist * (rm - r0)) * rm
			if _inside(at) and _nearest(at, CLEAR * 0.5)[0] >= CLEAR * 0.5:
				_mark(at, "fan_cell_%d" % ((i + j) % 2))


## Branches: curving branches from the edge that fork two or three times,
## each tip ending in a leaf, a bud or a curl.
func _build_branches() -> void:
	var tips: String = ["leaf", "bud", "curl", "mixed"][rng.randi_range(0, 3)]
	var bend := rng.randf_range(0.6, 1.8)
	var spread := rng.randf_range(0.4, 0.75)
	for _root in rng.randi_range(1, 3):
		for _attempt in 20:
			var q := _outline[rng.randi_range(0, _outline.size() - 1)]
			var dir := (-q).normalized().rotated(rng.randf_range(-0.5, 0.5))
			if _branch(q, dir, rng.randf_range(0.45, 0.7), 0, bend, spread, tips):
				break


## One branch from p along dir, then its forks (or its tip). Returns false,
## drawing nothing, if it doesn't fit.
func _branch(p: Vector2, dir: Vector2, length: float, depth: int, bend: float, spread: float, tips: String) -> bool:
	var kappa := rng.randf_range(-bend, bend)
	var pts := PackedVector2Array([p])
	var d := dir
	var s := 0.0
	while s < length:
		d = d.rotated(kappa * STEP)
		pts.append(pts[pts.size() - 1] + d * STEP)
		s += STEP
	if not _crosses_cleanly(pts):
		return false
	var owner := _add(pts, false, "branch")
	_strings.append({"pts": pts, "owner": owner, "style": "stem"})
	var end := pts[pts.size() - 1]
	var forked := 0
	if depth < 3 and length * 0.7 >= 0.13:
		var forks := 3 if rng.randf() < 0.2 else 2
		for k in forks:
			var turn := spread * (float(k) / (forks - 1) * 2.0 - 1.0) * rng.randf_range(0.8, 1.2)
			if _branch(end, d.rotated(turn), length * rng.randf_range(0.6, 0.78), depth + 1, bend, spread, tips):
				forked += 1
	if forked == 0:
		_branch_tip(end, d, owner, tips)
	return true


func _branch_tip(at: Vector2, dir: Vector2, owner: int, tips: String) -> void:
	var kind := tips
	if kind == "mixed":
		kind = ["leaf", "bud", "curl"][rng.randi_range(0, 2)]
	match kind:
		"leaf":
			var leaf := _leaf(at, dir, rng.randf_range(0.14, 0.2), rng.randf_range(-0.2, 0.2))
			if _fits(leaf["outline"], true, 0.75, PackedVector2Array([at]), CLEAR * 0.6, [owner]):
				_add(leaf["outline"], true, "branch_leaf")
				_mark(leaf["inside"], "branch_leaf")
		"bud":
			var r := rng.randf_range(0.04, 0.06)
			var bud := MandalaGenerator.circle(at + dir * r, r, 40)
			if _fits(bud, true, 0.75, PackedVector2Array([at]), CLEAR * 0.6, [owner]):
				_add(bud, true, "bud")
				_mark(at + dir * r, "bud")
		_:
			var curl := _curl(at, dir, rng.randf_range(0.07, 0.1), 1.0 if rng.randf() < 0.5 else -1.0)
			if _fits(curl, false, 0.8, PackedVector2Array([at]), CLEAR * 0.6, [owner]):
				_add(curl, false, "branch_curl")


## Lattice: two sets of flowing lines crossing in a warped net; its cells
## take two families in a checkerboard.
func _build_lattice() -> void:
	var a := rng.randf() * PI
	var sets := []
	for k in 2:
		var d := Vector2.from_angle(a + (rng.randf_range(0.9, 1.6) if k == 1 else 0.0))
		var n := Vector2(-d.y, d.x)
		var span := _extent(n)
		var count := rng.randi_range(3, 6)
		var wavelength := rng.randf_range(0.6, 1.2)
		var step := (span.y - span.x) / (count + 1)
		var waves := _wave_set(d, n, span.x, step, count, wavelength, rng.randf_range(0.0, 0.07),
				rng.randf_range(-0.5, 0.5), rng.randf() * TAU, "lattice_%d" % k + "_%d")
		sets.append({"d": d, "n": n, "waves": waves, "wavelength": wavelength})
	var s0: Dictionary = sets[0]
	var s1: Dictionary = sets[1]
	var w0: Array = s0["waves"]
	var w1: Array = s1["waves"]
	var det: float = s0["n"].x * s1["n"].y - s0["n"].y * s1["n"].x
	if absf(det) < 0.1:
		return
	for i in w0.size() - 1:
		for j in w1.size() - 1:
			# Where the middles of the two bands cross, found by refining.
			var p := Vector2.ZERO
			for _k in 6:
				var t0 := (_wave_at(w0[i], p.dot(s0["d"]), s0["wavelength"])
						+ _wave_at(w0[i + 1], p.dot(s0["d"]), s0["wavelength"])) / 2.0
				var t1 := (_wave_at(w1[j], p.dot(s1["d"]), s1["wavelength"])
						+ _wave_at(w1[j + 1], p.dot(s1["d"]), s1["wavelength"])) / 2.0
				p = Vector2(t0 * s1["n"].y - t1 * s0["n"].y, t1 * s0["n"].x - t0 * s1["n"].x) / det
			if _inside(p) and _nearest(p, CLEAR * 0.5)[0] >= CLEAR * 0.5:
				_mark(p, "lattice_cell_%d" % ((i + j) % 2))


## Ripples: lopsided contour rings around 1-3 centers, grown together until
## they run into each other or the outline; bands step through 3 families
## outward.
func _build_ripples() -> void:
	var gap := rng.randf_range(0.075, 0.095)
	var centers := []
	for _c in rng.randi_range(1, 3):
		for _try in 20:
			var c := _random_inside()
			var ok: bool = _nearest(c, gap * 3.0)[0] >= gap * 3.0
			for other: Dictionary in centers:
				ok = ok and c.distance_to(other["c"]) > gap * 6.0
			if ok:
				centers.append({"c": c, "wob": _harmonics(rng.randf_range(0.03, 0.08)), "drift": rng.randf_range(-0.15, 0.15),
						"bands": 0, "misses": 0, "done": false})
				break
	for k in 40:
		var growing := false
		for ctr: Dictionary in centers:
			if ctr["done"]:
				continue
			growing = true
			var c: Vector2 = ctr["c"]
			var r := gap * (k + 1)
			var ring := PackedVector2Array()
			var segs := maxi(48, int(r * 300.0))
			for i in segs:
				var t := TAU * i / segs
				ring.append(c + Vector2.from_angle(t) * r * _radius_at(ctr["wob"], t + k * ctr["drift"]))
			var pieces := _clip_all(ring, true)
			var drawn := false
			for piece: Array in pieces:
				if piece[1]:
					if _fits(piece[0], true, 0.9):
						_add(piece[0], true, "ripple")
						drawn = true
					continue
				for part in _clean_parts(piece[0]):
					_add(part, false, "ripple")
					drawn = true
			if drawn:
				# The band just inside this ring.
				var family := "ripple_core" if ctr["bands"] == 0 else "ripple_%d" % (ctr["bands"] % 3)
				for i in 8:
					var t := TAU * i / 8.0
					var at: Vector2 = c + Vector2.from_angle(t) * (r - gap * 0.5) * _radius_at(ctr["wob"], t + k * ctr["drift"])
					if ctr["bands"] == 0:
						at = c
					if _inside(at) and _nearest(at, gap * 0.3)[0] >= gap * 0.3:
						_mark(at, family)
				ctr["bands"] += 1
				ctr["misses"] = 0
			else:
				ctr["misses"] += 1
			if pieces.is_empty() or ctr["misses"] >= 6:
				ctr["done"] = true
		if not growing:
			break


## Ribbons: 2-4 ribbons crossing, each plain, tied or twisted, and now and
## then a plain sweep.
func _build_ribbons() -> void:
	for i in rng.randi_range(2, 4):
		_add_string("ribbon", RIBBONS[rng.randi_range(0, RIBBONS.size() - 1)], i > 0)
	if rng.randf() < 0.4:
		_add_string("sweep", "", true)


## Scales: rows of fish-scale arcs, each row's ends resting on the tops of
## the row before, the whole sheet turned and gently warped; scales are
## colored by row.
func _build_scales() -> void:
	var r := rng.randf_range(0.14, 0.19)
	var turn := rng.randf() * TAU
	var warp := rng.randf_range(0.03, 0.1)
	var warp_k := rng.randf_range(1.5, 3.5)
	var warp_phase := rng.randf() * TAU
	var rows := rng.randi_range(2, 3)
	var to_world := func(q: Vector2) -> Vector2:
		var p := q.rotated(turn)
		return p + Vector2(sin(q.y * warp_k + warp_phase), cos(q.x * warp_k * 0.7 + warp_phase)) * warp
	var k := 0
	var y := -1.7
	while y < 1.7:
		var x := -1.7 + (r if k % 2 == 1 else 0.0)
		while x < 1.7:
			var arc := PackedVector2Array()
			for i in 17:
				arc.append(to_world.call(Vector2(x, y) + Vector2.from_angle(PI * i / 16.0) * r))
			for piece: Array in _clip_all(arc, false):
				if Contours.length(piece[0], false) > 0.04:
					_add(piece[0], false, "scale")
			var inside: Vector2 = to_world.call(Vector2(x, y + r * 0.55))
			if _inside(inside) and _nearest(inside, r * 0.3)[0] >= r * 0.3:
				_mark(inside, "scale_%d" % (k % rows))
			x += r * 2.0
		y += r
		k += 1


## Truchet: a turned grid of square tiles, each holding two quarter circles
## around opposite corners, one way or the other at random, so they link
## into meandering curves and loops. Every area holds grid corners of one
## parity only, so the corners' parity colors them like a checkerboard.
func _build_truchet() -> void:
	var c := rng.randf_range(0.17, 0.25)
	var turn := rng.randf() * TAU
	var shift := Vector2(rng.randf(), rng.randf()) * c
	var span := ceili(1.5 / c)
	for i in range(-span, span):
		for j in range(-span, span):
			var o := Vector2(i, j) * c + shift
			var flip := rng.randf() < 0.5
			var corners := [Vector2(0, 0), Vector2(1, 1)] if flip else [Vector2(1, 0), Vector2(0, 1)]
			for corner: Vector2 in corners:
				var q := o + corner * c
				var mid := ((o + Vector2(0.5, 0.5) * c) - q).angle()
				var arc := PackedVector2Array()
				for a in 13:
					arc.append((q + Vector2.from_angle(mid - PI / 4.0 + PI / 2.0 * a / 12.0) * c * 0.5).rotated(turn))
				for piece: Array in _clip_all(arc, false):
					if Contours.length(piece[0], false) > 0.03:
						_add(piece[0], false, "truchet")
			var v := o.rotated(turn)
			if _inside(v) and _nearest(v, c * 0.3)[0] >= c * 0.3:
				_mark(v, "truchet_%d" % (posmod(i + j, 2)))


## Seeds: dots set out like a sunflower's (each a golden angle round from the
## last) around a point off the middle, sized up a little outward; the
## spiral's arms take 3 families in turn.
func _build_seeds() -> void:
	var o := _random_inside() * rng.randf_range(0.3, 0.8)
	var c := rng.randf_range(0.11, 0.14)
	var golden := PI * (3.0 - sqrt(5.0))
	var arms: int = [8, 13, 21][rng.randi_range(0, 2)]
	var grow := rng.randf_range(0.0, 0.25)
	var a0 := rng.randf() * TAU
	for k in range(1, 900):
		var rr := c * sqrt(k)
		if rr > 3.0:
			break
		var at := o + Vector2.from_angle(a0 + k * golden) * rr
		var size := c * 0.4 * (1.0 + grow * minf(rr, 1.5))
		var dot := MandalaGenerator.circle(at, size, 32)
		if _inside(at) and _fits(dot, true, 0.7):
			_add(dot, true, "seed")
			_mark(at, "seed_%d" % ((k % arms) % 3))


## Paisleys: nested paisley teardrops with bent tails, each the biggest that
## fits where it lands, big ones with one or two echoes inside.
func _build_paisleys() -> void:
	var biggest := rng.randf_range(0.17, 0.27)
	var bend := rng.randf_range(0.4, 0.9) * (1.0 if rng.randf() < 0.5 else -1.0)
	var mixed := rng.randf() < 0.4
	for _p in 30:
		var placed := false
		for _try in 6:
			# The roomiest of a few spots, the paisley sized to it.
			var c := Vector2.ZERO
			var room := 0.0
			for _spot in 30:
				var q := _random_inside()
				var d: float = _nearest(q, biggest * 1.6 + CLEAR)[0]
				if d > room:
					room = d
					c = q
			var r := minf(biggest * rng.randf_range(0.6, 1.0), (room - CLEAR) / 1.6)
			if r < 0.07:
				break
			var sgn := -1.0 if mixed and rng.randf() < 0.5 else 1.0
			var outer := _paisley(c, Vector2.from_angle(rng.randf() * TAU), r, bend * sgn)
			if not _fits(outer, true, 0.9):
				continue
			_add(outer, true, "paisley")
			var rings := 2 if r >= 0.17 else (1 if r >= 0.12 else 0)
			for k in rings:
				var scale := 0.55 if k == 0 else 0.25
				var inner := PackedVector2Array()
				for q in outer:
					inner.append(c + (q - c) * scale)
				_add(inner, true, "paisley_%d" % (k + 1))
			_mark(c, "paisley_core" if rings > 0 else "paisley")
			if rings > 0:
				_mark(c + (outer[outer.size() / 2] - c) * 0.78, "paisley")
			placed = true
			break
		if not placed:
			break


## A paisley around c: a teardrop's round end there, its tail along `dir`
## bending to one side by `bend`.
static func _paisley(c: Vector2, dir: Vector2, r: float, bend: float) -> PackedVector2Array:
	var across := Vector2(-dir.y, dir.x)
	var out := PackedVector2Array()
	for q in _drop(Vector2.ZERO, Vector2.RIGHT, r):
		var x := maxf(0.0, q.x) / (r * 1.5)
		out.append(c + dir * q.x + across * (q.y + bend * r * x * x))
	return out


## Chevrons: stacked zigzag lines, the bands between stepping through 3
## families.
func _build_chevrons() -> void:
	var d := Vector2.from_angle(rng.randf_range(-0.5, 0.5) + (PI / 2.0 if rng.randf() < 0.4 else 0.0))
	var n := Vector2(-d.y, d.x)
	var span := _extent(n)
	var count := rng.randi_range(5, 9)
	var wavelength := rng.randf_range(0.3, 0.55)
	var step := (span.y - span.x) / (count + 1)
	var amp := minf(rng.randf_range(0.05, 0.12), step * 0.6)
	var drift := rng.randf_range(-0.6, 0.6) if rng.randf() < 0.4 else 0.0
	var waves := _wave_set(d, n, span.x, step, count, wavelength, amp, drift, rng.randf() * TAU, "chevron_%d", true)
	for i in waves.size() - 1:
		_mark_between(d, n, waves[i], waves[i + 1], wavelength, "chevron_band_%d" % (i % 3))


# --- motifs that follow the strings ----------------------------------------------------

## Strings of these styles, as [{pts, owner, style}].
func _strings_of(styles: Array) -> Array:
	return _strings.filter(func(st: Dictionary) -> bool: return st["style"] in styles)


## Lines following a sweep at even steps to one side (sometimes both), like
## contour lines; the bands between are marked by how far out they are.
func _add_echoes() -> bool:
	var sources := _strings_of(["sweep"])
	if sources.is_empty():
		return false
	var gap := rng.randf_range(0.065, 0.085)
	var count := rng.randi_range(1, 3)
	var both := rng.randf() < 0.35
	var added := false
	for st: Dictionary in sources.slice(0, 2):
		var src: PackedVector2Array = st["pts"]
		# Run on past both ends, so the echoes reach the outline too.
		var t0 := (src[1] - src[0]).normalized()
		var t1 := (src[src.size() - 1] - src[src.size() - 2]).normalized()
		var ext := PackedVector2Array([src[0] - t0 * 0.3])
		ext.append_array(src)
		ext.append(src[src.size() - 1] + t1 * 0.3)
		ext = _even(ext, false, STEP)
		var normals := _normals(ext, false)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		for sgn: float in ([side, -side] if both else [side]):
			var skip := [st["owner"]]
			for k in range(1, count + 1):
				var echo := PackedVector2Array()
				for i in ext.size():
					echo.append(ext[i] + normals[i] * gap * k * sgn)
				echo = _clip(echo)
				if echo.size() < 2 or Contours.length(echo, false) < 0.25 or not _crosses_cleanly(echo, skip):
					break
				skip.append(_add(echo, false, "echo_%d" % k))
				added = true
				var en := _normals(echo, false)
				for i in range(0, echo.size(), int(0.08 / STEP)):
					# Halfway back toward the line it follows.
					var at := echo[i] - en[i] * gap * 0.5 * sgn
					if _inside(at) and _nearest(at, gap * 0.35)[0] >= gap * 0.35:
						_mark(at, "band_%d" % k)
	return added


## Rows of bumps along a stretch of a string, on one side or both, like a
## scalloped trim.
func _add_scallops() -> bool:
	var sources := _strings_of(["sweep", "wave"])
	if sources.is_empty():
		return false
	var spacing := rng.randf_range(0.13, 0.18)
	var both := rng.randf() < 0.3
	var added := false
	if sources.size() > 1 and rng.randf() < 0.5:
		sources.reverse()
	for st: Dictionary in sources.slice(0, rng.randi_range(1, 2)):
		var pts: PackedVector2Array = st["pts"]
		var length := Contours.length(pts, false)
		var span := minf(length - 0.2, length * rng.randf_range(0.4, 0.8))
		if span < spacing * 3.0:
			continue
		var start := rng.randf_range(0.1, length - span - 0.1)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var n := int(span / spacing)
		for sgn: float in ([side, -side] if both else [side]):
			for i in n:
				var a: Vector2 = Contours.sample(pts, false, start + i * spacing)[0]
				var b: Vector2 = Contours.sample(pts, false, start + (i + 1) * spacing)[0]
				var d := b - a
				var normal := Vector2(-d.y, d.x).normalized() * sgn
				var arc := PackedVector2Array()
				for j in 17:
					var t := j / 16.0
					arc.append(a + d * t + normal * spacing * 0.55 * sin(PI * t))
				if not _fits(arc, false, 0.75, PackedVector2Array([a, b]), CLEAR * 0.6, [st["owner"]]):
					continue
				_add(arc, false, "scallop")
				_mark(a + d * 0.5 + normal * spacing * 0.27, "scallop")
				added = true
	return added


## Leaves budding off the strings, alternating sides or in pairs, leaning
## the way the string runs; some have a vein down the middle.
func _add_leaves() -> bool:
	var sources := _strings_of(["sweep", "wave", "loop", "stem"])
	if sources.is_empty():
		return false
	var spacing := rng.randf_range(0.17, 0.24)
	var pairs := rng.randf() < 0.3
	var veins := rng.randf() < 0.5
	var lean := rng.randf_range(0.6, 1.0)
	var size := rng.randf_range(0.17, 0.24)
	var flip := 1.0 if rng.randf() < 0.5 else -1.0
	var added := false
	for st: Dictionary in sources:
		var pts: PackedVector2Array = st["pts"]
		var length := Contours.length(pts, false)
		var s := rng.randf_range(0.08, 0.08 + spacing)
		var side := 1.0
		while s < length - 0.08:
			for sgn: float in ([1.0, -1.0] if pairs else [side]):
				var sample: Array = Contours.sample(pts, false, s)
				var tangent: Vector2 = (sample[1] as Vector2).normalized() * flip
				var leaf := _leaf(sample[0], tangent.rotated(lean * sgn), size * rng.randf_range(0.85, 1.15),
						rng.randf_range(-0.2, 0.2))
				# Clear of every other line; of its own string only past its base,
				# so it can't lie along it.
				if (_fits(leaf["outline"], true, 0.75, PackedVector2Array([sample[0]]), CLEAR * 0.6, [st["owner"]])
						and _fits(leaf["outline"], true, 0.45, PackedVector2Array([sample[0]]), size * 0.5)):
					_add(leaf["outline"], true, "leaf")
					if veins:
						_add(leaf["vein"], false, "vein")
					_mark(leaf["inside"], "leaf")
					added = true
			side = -side
			s += spacing
	return added


## A leaf from `base` along `dir`: pointed at both ends, widest 40% of the way
## (`ratio` x its length across), its midrib bent by `curl`. Returns {"outline", "vein", "inside"}.
static func _leaf(base: Vector2, dir: Vector2, length: float, curl: float, ratio := 0.27) -> Dictionary:
	var across := Vector2(-dir.y, dir.x)
	var width := length * ratio
	var n := 24
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var vein := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var axis := base + dir * length * t + across * length * curl * sin(PI * t) * t
		var half := width * pow(sin(PI * pow(t, 0.8)), 1.4)
		left.append(axis + across * half)
		right.append(axis - across * half)
		if t <= 0.7:
			vein.append(axis)
	var outline := PackedVector2Array()
	outline.append_array(left)
	for i in range(n - 1, 0, -1):
		outline.append(right[i])
	var mid := base + dir * length * 0.45 + across * length * curl * sin(PI * 0.45) * 0.45
	return {"outline": outline, "vein": vein, "inside": mid + across * width * 0.45}


## Tendrils that leave a string (or the outline) at an angle and curl up in a
## spiral.
func _add_curls() -> bool:
	var sources := _strings_of(["sweep", "wave", "loop", "ribbon", "stem"])
	sources.append({"pts": _outline, "owner": 0, "style": "outline"})
	var want := rng.randi_range(2, 5)
	var size := rng.randf_range(0.1, 0.14)
	var placed := 0
	for _attempt in want * 12:
		if placed >= want:
			break
		var st: Dictionary = sources[rng.randi_range(0, sources.size() - 1)]
		var pts: PackedVector2Array = st["pts"]
		var is_outline: bool = st["style"] == "outline"
		var length := Contours.length(pts, is_outline)
		var sample: Array = Contours.sample(pts, is_outline, rng.randf_range(0.08, length - 0.08))
		var tangent: Vector2 = (sample[1] as Vector2).normalized()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var base: Vector2 = sample[0]
		if is_outline:
			# Inward, whichever way the outline runs.
			side = 1.0 if _inside(base + Vector2(-tangent.y, tangent.x) * 0.02) else -1.0
		if st["style"] == "ribbon":
			base = _nearest(base + Vector2(-tangent.y, tangent.x) * side * 0.08, 0.12)[1]
		var dir := tangent.rotated(side * rng.randf_range(0.7, 1.1)) * (1.0 if rng.randf() < 0.5 else -1.0)
		if not _inside(base + dir * 0.03):
			dir = dir.reflect(tangent)
		var curl := _curl(base, dir, size * rng.randf_range(0.8, 1.2), 1.0 if rng.randf() < 0.5 else -1.0)
		if _fits(curl, false, 0.8, PackedVector2Array([base]), CLEAR * 1.3):
			_add(curl, false, "curl")
			placed += 1
	return placed > 0


## A stem from `base` along `dir` that winds into a spiral of radius r,
## turning `turn` (1 or -1) way, its turns CLEAR apart.
static func _curl(base: Vector2, dir: Vector2, r: float, turn: float) -> PackedVector2Array:
	var stem := r * 0.6
	var start := base + dir * stem
	var center := start + Vector2(-dir.y, dir.x) * r * turn
	var a0 := (start - center).angle()
	var shrink := CLEAR * 1.2 / TAU
	var pts := PackedVector2Array([base])
	var theta := 0.0
	while true:
		var rr := r - shrink * theta
		if rr < CLEAR * 0.35:
			break
		pts.append(center + Vector2.from_angle(a0 + theta * turn) * rr)
		theta += clampf(0.03 / rr, 0.05, 0.4)
	return pts


# --- motifs that float in the space left ------------------------------------------------

## Teardrops scattered through the open space, their tails trailing the way
## the nearest string runs.
func _add_drops() -> bool:
	var flow := _flow()
	var want := rng.randi_range(3, 7)
	var size := rng.randf_range(0.07, 0.1)
	var placed := 0
	for _attempt in want * 15:
		if placed >= want:
			break
		var c := _random_inside()
		var r := size * rng.randf_range(0.75, 1.2)
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var best := INF
		for f: Array in flow:
			var d := c.distance_squared_to(f[0])
			if d < best:
				best = d
				dir = f[1] * (1.0 if dir.dot(f[1]) >= 0.0 else -1.0)
		var drop := _drop(c, dir.rotated(rng.randf_range(-0.3, 0.3)), r)
		if _fits(drop, true, 0.85):
			_add(drop, true, "drop")
			_mark(c, "drop")
			placed += 1
	return placed > 0


## A teardrop around c: a round end of radius r there and a pointed tail
## along `dir`.
static func _drop(c: Vector2, dir: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var length := r * 2.6
	for i in 48:
		var t := TAU * i / 48.0
		# x runs from the tail (t = 0) back over the round end (t = PI).
		var x := cos(t) * length / 2.0
		var y := sin(t) * pow(sin(t / 2.0), 1.4) * r * 1.15
		var local := Vector2(x + length / 2.0 - r * 1.1, y)
		pts.append(c + dir * local.x + Vector2(-dir.y, dir.x) * local.y)
	return pts


## Circles in the roomiest spots left, biggest first; in some pictures big
## ones get a ring inside.
func _add_orbs() -> bool:
	var want := rng.randi_range(3, 7)
	var biggest := rng.randf_range(0.1, 0.15)
	var ringed := rng.randf() < 0.5
	var placed := 0
	for _orb in want:
		var best_r := 0.0
		var best_c := Vector2.ZERO
		for _try in 60:
			var c := _random_inside()
			var r := minf(_nearest(c, biggest + CLEAR)[0] - CLEAR * 0.85, biggest)
			if r > best_r:
				best_r = r
				best_c = c
		if best_r < 0.045:
			break
		_add(MandalaGenerator.circle(best_c, best_r, 64), true, "orb")
		if ringed and best_r >= 0.075:
			_add(MandalaGenerator.circle(best_c, best_r * 0.5, 48), true, "orb_inner")
			_mark(best_c + Vector2(best_r * 0.75, 0.0), "orb_ring")
		_mark(best_c, "orb")
		placed += 1
	return placed > 0


func _random_inside() -> Vector2:
	for _i in 50:
		var p := Vector2(rng.randf_range(-REACH, REACH), rng.randf_range(-REACH, REACH))
		if _inside(p):
			return p
	return Vector2.ZERO


## Where the strings run: [point, direction] every few hundredths along them.
func _flow() -> Array:
	var out := []
	for st: Dictionary in _strings:
		var pts: PackedVector2Array = st["pts"]
		for i in range(1, pts.size(), 5):
			out.append([pts[i], (pts[i] - pts[i - 1]).normalized()])
	return out


# --- curve helpers -------------------------------------------------------------------

## A Catmull-Rom spline through ctrl[1] .. ctrl[size - 2] (the first and last
## points only steer the ends), `per` points per span.
static func _spline(ctrl: PackedVector2Array, per: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, ctrl.size() - 2):
		var p0 := ctrl[i - 1]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[i + 2]
		for j in per:
			var t := float(j) / per
			out.append(0.5 * (p1 * 2.0 + (p2 - p0) * t + (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t * t
					+ (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t * t * t))
	out.append(ctrl[ctrl.size() - 2])
	return out


## A closed Catmull-Rom spline through every point of `ctrl`.
static func _closed_spline(ctrl: PackedVector2Array, per: int) -> PackedVector2Array:
	var n := ctrl.size()
	var wrapped := PackedVector2Array([ctrl[n - 1]])
	wrapped.append_array(ctrl)
	wrapped.append(ctrl[0])
	wrapped.append(ctrl[1])
	var out := _spline(wrapped, per)
	out.resize(out.size() - 1)
	return out


## Every stretch of `pts` inside the outline, as [points, closed], their
## ends moved exactly onto the outline; a line wholly inside comes back whole.
func _clip_all(pts: PackedVector2Array, is_closed: bool) -> Array:
	var n := pts.size()
	var start := -1
	for i in n:
		if not _inside(pts[i]):
			start = i
			break
	if start < 0:
		return [[pts, is_closed]]
	var out := []
	var cur := PackedVector2Array()
	var first := start if is_closed else 0
	var last := start + n if is_closed else n - 1
	for idx in range(first, last + 1):
		var p := pts[idx % n]
		if _inside(p):
			if cur.is_empty() and idx > first:
				cur.append(_cross(pts[(idx - 1) % n], p))
			cur.append(p)
		elif not cur.is_empty():
			cur.append(_cross(pts[(idx - 1) % n], p))
			out.append([cur, false])
			cur = PackedVector2Array()
	if not cur.is_empty():
		out.append([cur, false])
	return out


## Points evenly `step` apart along a polyline.
static func _even(pts: PackedVector2Array, is_closed: bool, step: float) -> PackedVector2Array:
	var src := pts.duplicate()
	if is_closed:
		src.append(pts[0])
	var out := PackedVector2Array([src[0]])
	var carry := 0.0
	for i in range(1, src.size()):
		var a := src[i - 1]
		var b := src[i]
		var seg := a.distance_to(b)
		var t := step - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += step
		carry = seg - (t - step)
	if is_closed:
		if out.size() > 1 and out[out.size() - 1].distance_to(out[0]) < step * 0.5:
			out.resize(out.size() - 1)
	elif out[out.size() - 1].distance_to(src[src.size() - 1]) > step * 0.25:
		out.append(src[src.size() - 1])
	return out


## Unit normals of a polyline (to the left of its direction).
static func _normals(pts: PackedVector2Array, is_closed: bool) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n:
		var a := pts[(i - 1 + n) % n] if is_closed or i > 0 else pts[i]
		var b := pts[(i + 1) % n] if is_closed or i < n - 1 else pts[i]
		var d := (b - a).normalized()
		out.append(Vector2(-d.y, d.x))
	return out


## The longest stretch of `pts` inside the outline, with its ends moved
## exactly onto the outline where it crosses.
func _clip(pts: PackedVector2Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var cur := PackedVector2Array()
	for i in pts.size():
		if _inside(pts[i]):
			if cur.is_empty() and i > 0:
				cur.append(_cross(pts[i - 1], pts[i]))
			cur.append(pts[i])
		elif not cur.is_empty():
			cur.append(_cross(pts[i - 1], pts[i]))
			if cur.size() > best.size():
				best = cur
			cur = PackedVector2Array()
	if cur.size() > best.size():
		best = cur
	return best


## Where segment ab crosses the outline (its middle if it doesn't).
func _cross(a: Vector2, b: Vector2) -> Vector2:
	var n := _outline.size()
	for i in n:
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, _outline[i], _outline[(i + 1) % n])
		if hit != null:
			return hit
	return (a + b) / 2.0

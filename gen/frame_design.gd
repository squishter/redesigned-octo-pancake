class_name FrameDesign
extends RefCounted
## Frames and backgrounds around any generated picture.
##
## A frame is three choices that combine (7 x 8 x 5 = 280 frames):
##   shape: the frame's outline (SHAPES)
##   band: what decorates the band between its outer and inner lines (BANDS)
##   corner: ornaments over the band at its corners (CORNERS)
## The picture is scaled to fit inside. A background pattern (BACKGROUNDS)
## can fill the space between the frame and the picture; backgrounds are
## spaced wider than the pictures' own patterns, so they stay calmer. With a
## background, a halo outline is drawn around the picture and the background
## stops at it, so every region stays closed.
##
## Output matches MandalaGenerator: polylines in unit space (-1..1, y down).

const SHAPES := ["square", "rounded", "circle", "octagon", "arch", "hexagon", "oval"]
## plain: just the two lines; double: a line along the middle; beaded: round
## beads; rope: a zigzag across; segments: ticks across; scallops: a wavy
## line; braid: two crossing waves; weave: two crossing zigzags.
const BANDS := ["plain", "double", "beaded", "rope", "segments", "scallops", "braid", "weave"]
const CORNERS := ["none", "block", "circle", "diamond", "rosette"]
const BACKGROUNDS := ["plain", "stripes", "grid", "lattice", "rays", "rings", "waves", "polka", "sparkles"]
## Chance a picture is framed when nothing forces it either way.
const FRAME_CHANCE := 0.75
## Half-size of the frame's outer edge.
const OUTER := 0.97
const SAMPLES := 480
## How much of the inner half-size a picture may use, for shapes narrower
## than a circle of that radius.
const ROOM := {"oval": 0.84, "hexagon": 0.866}
## Each shape's turns: its outline repeats this many times around (and
## every shape mirrors across the vertical). Beads, ticks and waves along
## the band come in multiples of twice this, so they share both.
const FOLDS := {"square": 4, "rounded": 4, "octagon": 4, "circle": 4, "hexagon": 6, "oval": 2, "arch": 1}
## Gap between the picture and its halo.
const HALO_MARGIN := 0.05
## Shapes, bands and backgrounds used by this many previous frames in a row
## are skipped (corners skip only the last one).
const AVOID_RECENT := 2

var rng := RandomNumberGenerator.new()
var polylines: Array[PackedVector2Array] = []
var closed := PackedByteArray()

var _outer := PackedVector2Array()
var _inner := PackedVector2Array()
var _halo := PackedVector2Array()
var _blocks: Array[PackedVector2Array] = []
## What the current clip tests: 0 outside the corner ornaments, 1 inside the
## band, 2 in the background (between the frame and the halo).
var _mode := 0


## Frames the picture, or not. options:
##   frame: true or false to force it either way (default: FRAME_CHANCE)
##   frame_shape, frame_band, frame_corner, background: a name to use
##       instead of a random pick
##   frame_recent: Array of earlier results' "frame" dictionaries, for
##       pictures made in a row; recent choices are skipped and the least
##       used preferred
## Returns {"polylines", "closed", "frame"}: "frame" is {"shape", "band",
## "corner", "background"}, or empty when the picture isn't framed.
static func apply(lines: Array[PackedVector2Array], line_closed: PackedByteArray, seed_value: int,
		options: Dictionary = {}) -> Dictionary:
	var g := FrameDesign.new()
	g.rng.seed = seed_value * 31 + 7
	var wanted: Variant = options.get("frame", "auto")
	var framed: bool = wanted if wanted is bool else g.rng.randf() < FRAME_CHANCE
	if not framed:
		return {"polylines": lines, "closed": line_closed, "frame": {}}
	var recent: Array = options.get("frame_recent", [])
	var info := {
		"shape": g._choose(options, "frame_shape", "shape", SHAPES, recent, AVOID_RECENT),
		"band": g._choose(options, "frame_band", "band", BANDS, recent, AVOID_RECENT),
		"corner": g._choose(options, "frame_corner", "corner", CORNERS, recent, 1),
		"background": g._choose(options, "background", "background", BACKGROUNDS, recent, AVOID_RECENT),
	}
	g._build(lines, line_closed, info)
	return {"polylines": g.polylines, "closed": g.closed, "frame": info}


func _choose(options: Dictionary, option: String, key: String, names: Array, recent: Array, avoid: int) -> String:
	var wanted: String = options.get(option, "random")
	if wanted in names:
		return wanted
	var history := []
	for r in recent:
		if r is Dictionary and r.has(key):
			history.append(r[key])
	return _least_used(names, history, avoid)


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


func _add(points: PackedVector2Array, is_closed: bool = false) -> void:
	polylines.append(points)
	closed.append(1 if is_closed else 0)


# --- building ------------------------------------------------------------------------

func _build(lines: Array[PackedVector2Array], line_closed: PackedByteArray, info: Dictionary) -> void:
	var shape: String = info["shape"]
	var background: String = info["background"]
	var bw := rng.randf_range(0.09, 0.13)
	_outer = _shape(shape, OUTER)
	_inner = _shape(shape, OUTER - bw)
	var mid := _shape(shape, OUTER - bw / 2.0)

	# The picture, scaled to fit inside with room for the background.
	var inside := OUTER - bw
	var room: float = ROOM.get(shape, 1.0) * inside
	var fill := rng.randf_range(0.74, 0.84) if background != "plain" else 0.9
	var reach := 0.0
	for line in lines:
		for v in line:
			reach = maxf(reach, v.length())
	var k := room * fill / maxf(reach, 1e-6)
	var content: Array[PackedVector2Array] = []
	for i in lines.size():
		var scaled := PackedVector2Array()
		for v in lines[i]:
			scaled.append(v * k)
		content.append(scaled)
		_add(scaled, line_closed[i] != 0)

	_build_corners(info["corner"], shape, bw)
	_mode = 0
	for edge in [_outer, _inner]:
		_add_loop(edge)
	_mode = 1
	_build_band(info["band"], mid, bw, FOLDS[shape])
	if background != "plain":
		_halo = _envelope(content, line_closed, HALO_MARGIN)
		_add(_halo, true)
		_mode = 2
		_build_background(background)


## A frame shape's closed outline at half-size h, evenly spaced, starting
## at its top on the vertical axis (so point i mirrors point SAMPLES - i).
static func _shape(kind: String, h: float) -> PackedVector2Array:
	var poly := PackedVector2Array()
	match kind:
		"circle", "oval":
			var sx := 0.84 if kind == "oval" else 1.0
			for i in SAMPLES:
				var a := -PI / 2.0 + TAU * i / SAMPLES
				poly.append(Vector2(sx * h * cos(a), h * sin(a)))
			return poly
		"square":
			poly = PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
		"octagon":
			var c := h * 0.32
			poly = PackedVector2Array([Vector2(-h + c, -h), Vector2(h - c, -h), Vector2(h, -h + c), Vector2(h, h - c),
					Vector2(h - c, h), Vector2(-h + c, h), Vector2(-h, h - c), Vector2(-h, -h + c)])
		"hexagon":
			for i in 6:
				poly.append(Vector2.from_angle(TAU * i / 6.0) * h)
		"rounded":
			var r := 0.28 * h
			var corners := [[Vector2(h - r, -h + r), -PI / 2.0], [Vector2(h - r, h - r), 0.0],
					[Vector2(-h + r, h - r), PI / 2.0], [Vector2(-h + r, -h + r), PI]]
			for corner in corners:
				for j in 13:
					poly.append(corner[0] + Vector2.from_angle(corner[1] + PI / 2.0 * j / 12.0) * r)
		"arch":
			# Square at the bottom, a half circle on top.
			poly = PackedVector2Array([Vector2(h, 0.0), Vector2(h, h), Vector2(-h, h), Vector2(-h, 0.0)])
			for j in range(1, 40):
				poly.append(Vector2.from_angle(PI + PI * j / 40.0) * h)
	return _resample(_from_top(poly), SAMPLES)


## A closed outline (clockwise on screen, around the center) restarted
## where it crosses the vertical axis at the top.
static func _from_top(poly: PackedVector2Array) -> PackedVector2Array:
	var m := poly.size()
	for i in m:
		var a := poly[i]
		var b := poly[(i + 1) % m]
		if a.x < 0.0 and b.x >= 0.0 and a.y + b.y < 0.0:
			var out := PackedVector2Array()
			var t := -a.x / (b.x - a.x)
			if t < 1.0 - 1e-6:
				out.append(a.lerp(b, t))
			for j in m:
				out.append(poly[(i + 1 + j) % m])
			return out
	return poly


## Where corner ornaments go on a frame shape's band (at half-size h).
static func _corner_points(kind: String, h: float) -> Array:
	match kind:
		"square":
			return [Vector2(h, h), Vector2(h, -h), Vector2(-h, h), Vector2(-h, -h)]
		"rounded":
			var r := 0.28 * h
			var d := h - r + r * 0.7071
			return [Vector2(d, d), Vector2(d, -d), Vector2(-d, d), Vector2(-d, -d)]
		"octagon":
			var d := h - h * 0.16
			return [Vector2(d, d), Vector2(d, -d), Vector2(-d, d), Vector2(-d, -d)]
		"arch":
			return [Vector2(h, h), Vector2(-h, h), Vector2(h, 0.0), Vector2(-h, 0.0)]
		"hexagon":
			var out := []
			for i in 6:
				out.append(Vector2.from_angle(TAU * i / 6.0) * h)
			return out
		"oval":
			return [Vector2(0.0, -h), Vector2(0.0, h), Vector2(0.84 * h, 0.0), Vector2(-0.84 * h, 0.0)]
	return [Vector2(0.0, -h), Vector2(0.0, h), Vector2(h, 0.0), Vector2(-h, 0.0)]


## Points evenly spaced along a closed outline.
static func _resample(pts: PackedVector2Array, n: int) -> PackedVector2Array:
	var m := pts.size()
	var lengths := PackedFloat32Array()
	var total := 0.0
	for i in m:
		var d := pts[i].distance_to(pts[(i + 1) % m])
		lengths.append(d)
		total += d
	var out := PackedVector2Array()
	var i := 0
	var acc := 0.0
	for k in n:
		var target := total * k / n
		while acc + lengths[i] < target and i < m - 1:
			acc += lengths[i]
			i += 1
		var f := (target - acc) / lengths[i] if lengths[i] > 0.0 else 0.0
		out.append(pts[i].lerp(pts[(i + 1) % m], f))
	return out


## Outward unit normals of a closed outline around the center.
static func _normals(pts: PackedVector2Array) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n:
		var t := pts[(i + 1) % n] - pts[(i - 1 + n) % n]
		out.append(Vector2(-t.y, t.x).normalized())
	if pts[0].dot(out[0]) < 0.0:
		for i in n:
			out[i] = -out[i]
	return out


func _build_corners(kind: String, shape: String, bw: float) -> void:
	if kind == "none":
		return
	var r := bw * 0.78
	for c in _corner_points(shape, OUTER - bw / 2.0):
		var block: PackedVector2Array
		match kind:
			"block":
				block = PackedVector2Array([c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r), c + Vector2(-r, r)])
			"diamond":
				var d := r * 1.25
				block = PackedVector2Array([c + Vector2(0.0, -d), c + Vector2(d, 0.0), c + Vector2(0.0, d), c + Vector2(-d, 0.0)])
			_:
				block = MandalaGenerator.circle(c, r, 32)
		_blocks.append(block)
		_add(block, true)
		if kind == "rosette":
			_add(MandalaGenerator.circle(c, r * 0.45, 20), true)


func _build_band(kind: String, mid: PackedVector2Array, bw: float, folds: int) -> void:
	var normals := _normals(mid)
	var n := mid.size()
	var perimeter := 0.0
	for i in n:
		perimeter += mid[i].distance_to(mid[(i + 1) % n])
	match kind:
		"double":
			_add_loop(mid)
		"beaded":
			var r := bw * 0.3
			for at: Array in _along(mid, normals, perimeter, r * 2.7, folds):
				if _clear(at[0], r + 0.012):
					_add(MandalaGenerator.circle(at[0], r, 20), true)
		"rope", "weave":
			var spots := _along(mid, normals, perimeter, bw * 1.1, folds)
			spots.append(spots[0])
			for side in ([1.0] if kind == "rope" else [1.0, -1.0]):
				var zig := PackedVector2Array()
				for j in spots.size():
					zig.append(spots[j][0] + spots[j][1] * (side * (1.0 if j % 2 == 0 else -1.0) * bw * 0.62))
				_add_clipped(zig)
		"segments":
			for at: Array in _along(mid, normals, perimeter, bw * 1.4, folds):
				_add_clipped(PackedVector2Array([at[0] - at[1] * bw, at[0] + at[1] * bw]))
		"scallops":
			var m := _multiple(perimeter / (bw * 1.6), folds)
			var wave := PackedVector2Array()
			for j in n + 1:
				var i := j % n
				wave.append(mid[i] + normals[i] * (-bw * 0.5 + bw * 0.75 * absf(sin(PI * m * j / n))))
			_add_clipped(wave)
		"braid":
			var m := _multiple(perimeter / (bw * 2.2), folds)
			for phase in [0.0, PI]:
				var wave := PackedVector2Array()
				for j in n + 1:
					var i := j % n
					wave.append(mid[i] + normals[i] * (bw * 0.36 * sin(TAU * m * j / n + phase)))
				_add_clipped(wave)


## Spots about `step` apart along a closed outline of evenly spaced points
## that starts on its mirror axis, as [point, outward normal]: an even
## multiple of the shape's folds, starting on the axis, so they share the
## frame's symmetry.
static func _along(pts: PackedVector2Array, normals: PackedVector2Array, perimeter: float, step: float,
		folds: int) -> Array:
	var n := pts.size()
	var k := _multiple(perimeter / step / 2.0, folds) * 2
	var out := []
	for i in k:
		var f := float(i) * n / k
		var j := floori(f)
		var t := f - j
		out.append([pts[j].lerp(pts[(j + 1) % n], t), normals[j].lerp(normals[(j + 1) % n], t).normalized()])
	return out


## The multiple of `folds` nearest x, and at least 4.
static func _multiple(x: float, folds: int) -> int:
	return folds * maxi(ceili(4.0 / folds), roundi(x / folds))


func _build_background(kind: String) -> void:
	match kind:
		"stripes":
			var step := rng.randf_range(0.2, 0.26)
			# Across or along the vertical, to keep its mirror.
			_parallel(0.0 if rng.randf() < 0.5 else PI / 2.0, step, 8)
		"grid", "lattice":
			var step := rng.randf_range(0.24, 0.3)
			var a := 0.0 if kind == "grid" else PI / 4.0
			_parallel(a, step, 6)
			_parallel(a + PI / 2.0, step, 6)
		"rays":
			var counts := [12, 16, 20]
			var m: int = counts[rng.randi_range(0, 2)]
			for i in m:
				_add_clipped(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(TAU * (i + 0.5) / m) * 2.0]))
		"rings":
			var step := rng.randf_range(0.16, 0.2)
			var r := step
			while r < 1.5:
				var ring := MandalaGenerator.circle(Vector2.ZERO, r)
				ring.append(ring[0])
				_add_clipped(ring)
				r += step
		"waves":
			var step := rng.randf_range(0.22, 0.28)
			var y := -1.0 + step / 2.0
			while y < 1.0:
				var wave := PackedVector2Array()
				for i in 145:
					var x := i / 60.0 - 1.2
					wave.append(Vector2(x, y + step * 0.25 * cos(PI * 2.5 * x)))
				_add_clipped(wave)
				y += step
		"polka", "sparkles":
			# A staggered grid centered on the picture.
			var step := rng.randf_range(0.26, 0.32)
			var r := step * 0.16
			var rows := ceili(1.0 / step)
			for row in range(-rows, rows + 1):
				for col in range(-rows - 1, rows + 1):
					var c := Vector2((col + (0.5 if absi(row) % 2 == 1 else 0.0)) * step, row * step)
					if absf(c.x) > 1.0:
						continue
					if _clear(c, r * 2.2):
						if kind == "polka":
							_add(MandalaGenerator.circle(c, r, 18), true)
						else:
							var sparkle := PackedVector2Array()
							for j in 8:
								sparkle.append(c + Vector2.from_angle(PI * j / 4.0) * (r * 2.0 if j % 2 == 0 else r * 0.7))
							_add(sparkle, true)


## Parallel lines at `angle`, `step` apart, `count` on each side of the
## center.
func _parallel(angle: float, step: float, count: int) -> void:
	var d := Vector2.from_angle(angle)
	var across := Vector2(-d.y, d.x)
	for i in range(-count, count):
		var o := across * step * (i + 0.5)
		_add_clipped(PackedVector2Array([o - d * 2.0, o + d * 2.0]))


## A smooth outline around everything in `lines`, `margin` out: the
## farthest point in each direction, widened and smoothed.
static func _envelope(lines: Array[PackedVector2Array], line_closed: PackedByteArray, margin: float,
		bins: int = 360) -> PackedVector2Array:
	var far := PackedFloat32Array()
	far.resize(bins)
	for li in lines.size():
		var line := lines[li]
		var segs := line.size() if line_closed[li] != 0 else line.size() - 1
		for i in segs:
			var a := line[i]
			var b := line[(i + 1) % line.size()]
			var k := maxi(1, int(a.distance_to(b) / 0.01))
			for j in k:
				var p := a.lerp(b, float(j) / k)
				var bin := int(fposmod(p.angle(), TAU) / TAU * bins) % bins
				far[bin] = maxf(far[bin], p.length())
		if line.size() == 1:
			var bin := int(fposmod(line[0].angle(), TAU) / TAU * bins) % bins
			far[bin] = maxf(far[bin], line[0].length())
	var w := 6
	var wide := PackedFloat32Array()
	wide.resize(bins)
	for i in bins:
		for j in range(-w, w + 1):
			wide[i] = maxf(wide[i], far[(i + j + bins) % bins])
	var out := PackedVector2Array()
	for i in bins:
		var sum := 0.0
		for j in range(-w, w + 1):
			sum += wide[(i + j + bins) % bins]
		out.append(Vector2.from_angle(TAU * (i + 0.5) / bins) * (sum / (2 * w + 1) + margin))
	return out


# --- clipping ------------------------------------------------------------------------

## Whether the current line may draw at p (see _mode).
func _visible(p: Vector2) -> bool:
	for b in _blocks:
		if Geometry2D.is_point_in_polygon(p, b):
			return false
	match _mode:
		1:
			return Geometry2D.is_point_in_polygon(p, _outer) and not Geometry2D.is_point_in_polygon(p, _inner)
		2:
			return Geometry2D.is_point_in_polygon(p, _inner) and not Geometry2D.is_point_in_polygon(p, _halo)
	return true


## Whether a shape of radius r around c fits where the current lines may draw.
func _clear(c: Vector2, r: float) -> bool:
	if not _visible(c):
		return false
	for i in 12:
		if not _visible(c + Vector2.from_angle(TAU * i / 12.0) * r):
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


func _add_clipped(path: PackedVector2Array) -> void:
	for piece in _clip(path):
		_add(piece)


func _add_loop(loop: PackedVector2Array) -> void:
	var path := loop.duplicate()
	path.append(loop[0])
	_add_clipped(path)

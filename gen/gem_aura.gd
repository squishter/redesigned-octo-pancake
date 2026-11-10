class_name GemAura
extends RefCounted
## A soft surround of small stones in the empty background around a
## picture's subject (a plant standing on bare paper): like the echo and
## halo patterns it follows the subject's outline, but outside it, quieter,
## and it drifts away and thins to nothing instead of ending at an edge, so
## the subject stays in front and the eye stays on it.
##
## How far the aura reaches differs all the way around the subject (a
## smooth, seeded `reach` field: long plumes here, a row or two there), and
## every stone goes by its `fade`: how far out it is as a share of the reach
## where it sits. Stones get smaller or rarer with the fade and are gone
## before it reaches 1, and nothing runs along the outside, so there is no
## outline to see there. Toward
## the picture's border the reach runs out the same way.
##
## Styles:
##   streams: lines of stones that leave the outline and flow away from it,
##     bending together like grass in a current, each shrinking along its
##     length to nothing (fades by stone size, and the lines spread apart);
##   veil: tufts of short rows that follow the outline in stones of nearly
##     one small size, narrower and rarer the farther out (fades by density).

const STYLES := ["streams", "veil"]
## How often a picture that leaves the style open takes streams.
const STREAMS_CHANCE := 0.7
## The field's grid: one cell per CELL x CELL px.
const CELL := 2
## The biggest aura stone's radius, in units: smaller than the rows inside
## the subject, so it stays in front.
const STONE := 0.55
## The smallest stone kept, in units (SlotPacker.MIN_STONE).
const MIN_STONE := 0.25
## Clear paper between the subject and the aura, in units.
const MARGIN := 1.4
## How far the aura reaches at its longest, as a share of the picture's
## shorter side, and the shortest reach as a share of that.
const REACH := 0.22
const REACH_MIN := 0.3
## The aura fades out within this share of the shorter side from the border.
const BORDER_FADE := 0.1
## Streams start about this many of their stones apart along the outline.
const STREAM_SPACING := 1.35
## The most stones in a stream: with small stones a stream is shorter than
## the reach rather than a long line of stones all nearly alike.
const STREAM_STONES := 9
## How far a veil's rows sway from the outline's shape, as a share of their distance.
const SWAY := 0.5
## Space between rows and between stones along a row, in stone radii: more
## than inside the subject, so the aura reads lighter.
const AIR := 0.9
## A picture needs this share of background for an aura.
const MIN_BACKGROUND := 0.2
## Stones past this share of the reach take the paler outer tone.
const OUTER_TONE := 0.45

var _w := 0
var _h := 0
var _gw := 0
var _gh := 0
## Per grid cell: px to the subject (0 on it), and its smoothed copy for
## the flow's direction.
var _dist := PackedFloat32Array()
var _smooth := PackedFloat32Array()
var _unit := 8.0
var _gap := 2.0
var _reach := 100.0
var _margin := 10.0
var _side := 512.0
## Waves the reach and flow fields are summed from: [direction, phase].
var _waves := []
var _rng := RandomNumberGenerator.new()
var _slots: Array[Dictionary] = []
var _grid := {}
var _bucket := 16.0
## The strand stones are being added to (see _thin).
var _strand := 0
var _min_stone := MIN_STONE


## Stones for an aura around the subject of `lines` (a w x h mask, nonzero
## on the lines; everything the picture's border can't reach without
## crossing a line is the subject). options:
##   style: one of STYLES (default: picked per seed),
##   unit (base stone radius in px), gap (px between stones),
##   reach (the longest reach as a share of the shorter side, default REACH),
##   stone (the biggest stone's radius in units, default STONE),
##   min_stone (the smallest kept, in units, default MIN_STONE),
##   keep_clear: Array of slots (the subject's own) the aura stays off,
##   max_stones: the most stones (default: no limit); an aura with more
##     loses whole strands (a stream, a run of a veil's row), picked per
##     seed all around the subject, so it gets thinner rather than shorter.
## Returns {"style", "slots": [{shape, x, y, rotation, size, width, tone,
## part, fade, strand}]}: all round; tone 1 on the paler outer stones; `fade`
## is 0 beside the subject and 1 where the aura ends; `strand` numbers the
## stream or run of a row a stone belongs to, in the order they were laid. No slots when the picture
## has too little background.
static func place(lines: PackedByteArray, w: int, h: int, seed_value: int, options: Dictionary = {}) -> Dictionary:
	var a := GemAura.new()
	a._rng.seed = hash([seed_value, "aura"])
	var style: String = options.get("style", "")
	var pick := a._rng.randf()
	if not style in STYLES:
		style = "streams" if pick < STREAMS_CHANCE else "veil"
	a._w = w
	a._h = h
	a._side = float(mini(w, h))
	a._unit = options.get("unit", a._side * SlotPacker.UNIT)
	a._gap = options.get("gap", a._unit * SlotPacker.GAP)
	a._reach = a._side * float(options.get("reach", REACH))
	a._margin = a._unit * MARGIN + a._gap
	a._min_stone = options.get("min_stone", MIN_STONE)
	for k in 6:
		a._waves.append([Vector2.from_angle(a._rng.randf() * TAU), a._rng.randf() * TAU])
	if not a._measure(lines):
		return {"style": style, "slots": a._slots}
	var r0: float = a._unit * float(options.get("stone", STONE))
	a._bucket = maxf(4.0, r0 * 4.0)
	for s: Dictionary in options.get("keep_clear", []):
		a._remember(Vector2(s["x"], s["y"]), float(s["size"]) / 2.0)
	var blocked := a._grid.duplicate(true)
	if style == "veil":
		a._veil(r0)
	else:
		a._streams(r0)
	a._grid = blocked
	a._thin(int(options.get("max_stones", -1)))
	return {"style": style, "slots": a._slots}


# --- fields ---------------------------------------------------------------------

## Fills the distance grids from the line mask. False if the picture has no
## subject, or too little background for an aura.
func _measure(lines: PackedByteArray) -> bool:
	var w := _w
	var h := _h
	# The background: what the border reaches without crossing a line.
	var outside := PackedByteArray()
	outside.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		stack.append_array([x, (h - 1) * w + x])
	for y in h:
		stack.append_array([y * w, y * w + w - 1])
	var count := 0
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if outside[i] == 1 or lines[i] != 0:
			continue
		outside[i] = 1
		count += 1
		var x := i % w
		if x > 0:
			stack.append(i - 1)
		if x < w - 1:
			stack.append(i + 1)
		if i >= w:
			stack.append(i - w)
		if i < w * (h - 1):
			stack.append(i + w)
	if count < w * h * MIN_BACKGROUND or count == w * h:
		return false
	_gw = ceili(w / float(CELL))
	_gh = ceili(h / float(CELL))
	var n := _gw * _gh
	_dist.resize(n)
	_dist.fill(1e9)
	for y in h:
		for x in w:
			if outside[y * w + x] == 0:
				_dist[(y / CELL) * _gw + x / CELL] = 0.0
	# Chamfer distance (3-4), in cells.
	var a := 1.0
	var b := 1.4142
	for y in _gh:
		for x in _gw:
			var i := y * _gw + x
			var d := _dist[i]
			if x > 0:
				d = minf(d, _dist[i - 1] + a)
			if y > 0:
				d = minf(d, _dist[i - _gw] + a)
				if x > 0:
					d = minf(d, _dist[i - _gw - 1] + b)
				if x < _gw - 1:
					d = minf(d, _dist[i - _gw + 1] + b)
			_dist[i] = d
	for y in range(_gh - 1, -1, -1):
		for x in range(_gw - 1, -1, -1):
			var i := y * _gw + x
			var d := _dist[i]
			if x < _gw - 1:
				d = minf(d, _dist[i + 1] + a)
			if y < _gh - 1:
				d = minf(d, _dist[i + _gw] + a)
				if x < _gw - 1:
					d = minf(d, _dist[i + _gw + 1] + b)
				if x > 0:
					d = minf(d, _dist[i + _gw - 1] + b)
			_dist[i] = d
	for i in n:
		_dist[i] *= CELL
	# Smoothed for the direction away from the subject: the raw field has a
	# crease along every ridge, which would kink the streams.
	_smooth = _dist.duplicate()
	var radius := maxi(2, int(_unit * 1.5 / CELL))
	for _pass in 2:
		_smooth = _box_blur(_smooth, radius)
	return true


func _box_blur(field: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(field.size())
	var out := PackedFloat32Array()
	out.resize(field.size())
	var span := 2 * radius + 1
	for y in _gh:
		var sum := 0.0
		for k in range(-radius, radius + 1):
			sum += field[y * _gw + clampi(k, 0, _gw - 1)]
		for x in _gw:
			tmp[y * _gw + x] = sum / span
			sum += field[y * _gw + mini(_gw - 1, x + radius + 1)] - field[y * _gw + maxi(0, x - radius)]
	for x in _gw:
		var sum := 0.0
		for k in range(-radius, radius + 1):
			sum += tmp[clampi(k, 0, _gh - 1) * _gw + x]
		for y in _gh:
			out[y * _gw + x] = sum / span
			sum += tmp[mini(_gh - 1, y + radius + 1) * _gw + x] - tmp[maxi(0, y - radius) * _gw + x]
	return out


func _sample(field: PackedFloat32Array, p: Vector2) -> float:
	var gx := clampf(p.x / CELL - 0.5, 0.0, _gw - 1.001)
	var gy := clampf(p.y / CELL - 0.5, 0.0, _gh - 1.001)
	var x := int(gx)
	var y := int(gy)
	var fx := gx - x
	var fy := gy - y
	var i := y * _gw + x
	return lerpf(lerpf(field[i], field[i + 1], fx), lerpf(field[i + _gw], field[i + _gw + 1], fx), fy)


## Smooth seeded noise in 0..1 from waves `from`..`from + 2`, about
## `period` (a share of the shorter side) across.
func _noise(p: Vector2, from: int, period: float) -> float:
	var sum := 0.0
	var amp := 1.0
	var total := 0.0
	var k := TAU / (_side * period)
	for i in 3:
		var wave: Array = _waves[from + i]
		sum += amp * sin(p.dot(wave[0]) * k + wave[1])
		total += amp
		amp *= 0.6
		k *= 1.9
	return clampf(0.5 + 0.5 * sum / total * 1.25, 0.0, 1.0)


## How far the aura reaches at p, in px: uneven all the way around, and
## shorter near the picture's border.
func _reach_at(p: Vector2) -> float:
	var n := _noise(p, 0, 0.7)
	# Mostly middling, with a few long plumes.
	var share := lerpf(REACH_MIN, 1.0, pow(n, 1.5))
	var border := minf(minf(p.x, p.y), minf(_w - p.x, _h - p.y))
	return _reach * share * clampf(border / (_side * BORDER_FADE), 0.0, 1.0)


## The fade at p: 0 at the aura's inner edge (MARGIN from the subject), 1
## where its reach ends; below 0 on the subject and the clear paper.
func _fade_at(p: Vector2) -> float:
	var d := _sample(_dist, p) - _margin
	if d < 0.0:
		return -1.0
	return d / maxf(1.0, _reach_at(p))


# --- styles ---------------------------------------------------------------------

## Rows that follow the subject's outline outward at even steps, swaying
## more the farther out they are, in stones of nearly one small size. Only
## tufts of them are there: patches that reach across several rows beside
## the subject and narrow to a few stones, then none, as the fade grows.
func _veil(r0: float) -> void:
	var r_row := r0 * 0.8
	var pitch := 2.0 * r_row + r_row * AIR + _gap
	var levels := PackedFloat32Array()
	var d := r_row
	while d <= _reach and levels.size() < 24:
		levels.append(d)
		d += pitch
	if levels.is_empty():
		return
	var field := PackedFloat32Array()
	field.resize(_gw * _gh)
	var labels := PackedInt32Array()
	labels.resize(_gw * _gh)
	for y in _gh:
		for x in _gw:
			var i := y * _gw + x
			var out := _dist[i] - _margin
			labels[i] = 0 if out > -_margin else -1
			# The sway: nothing beside the subject, up to SWAY of the distance.
			field[i] = out * (1.0 + SWAY * (_noise(Vector2((x + 0.5) * CELL, (y + 0.5) * CELL), 3, 0.45) - 0.5))
	var paths := Contours.iso_lines(field, labels, _gw, _gh, 0, Rect2i(0, 0, _gw, _gh), levels)
	var r_min := _unit * _min_stone
	for k in levels.size():
		for path: Dictionary in paths[k]:
			var pts: PackedVector2Array = path["points"]
			for i in pts.size():
				pts[i] *= CELL
			var closed: bool = path["closed"]
			var length := Contours.length(pts, closed)
			var s := _rng.randf() * r_row
			_strand += 1
			while s < length:
				var p: Vector2 = Contours.sample(pts, closed, s)[0]
				var t := _fade_at(p)
				if t < 0.0 or t >= 1.0:
					s += r_min * 2.0
					_strand += 1
					continue
				var r := r_row * lerpf(1.0, 0.8, t)
				s += 2.0 * r + r * AIR + _gap
				# The tufts: one field for every row, so they line up across rows.
				var tuft := _noise(p, 0, 0.2)
				if r >= r_min and tuft > lerpf(0.15, 0.9, pow(t, 0.7)) and _rng.randf() > t * 0.3 and _add(p, r, t, k):
					continue
				# A gap: the next stone starts another run.
				_strand += 1


## Lines of stones flowing away from the subject: each starts beside it,
## heads straight out and then bends with a flow field its neighbors share,
## like grass in a current. A line runs most of the reach where it starts
## (less where the subject closes in again or another line is in the way),
## its stones shrinking evenly to the smallest by its end, so long plumes
## and short wisps both taper to nothing. Where the reach is short fewer start.
func _streams(r0: float) -> void:
	var field := PackedFloat32Array()
	field.resize(_gw * _gh)
	var labels := PackedInt32Array()
	labels.resize(_gw * _gh)
	for i in _gw * _gh:
		field[i] = _dist[i] - _margin
		labels[i] = 0 if field[i] > -_margin else -1
	var starts := Contours.iso_lines(field, labels, _gw, _gh, 0, Rect2i(0, 0, _gw, _gh), PackedFloat32Array([r0]))
	var r_min := _unit * _min_stone
	var part := 0
	for path: Dictionary in starts[0]:
		var pts: PackedVector2Array = path["points"]
		for i in pts.size():
			pts[i] *= CELL
		var closed: bool = path["closed"]
		var length := Contours.length(pts, closed)
		var s := _rng.randf() * r0
		while s < length:
			var p: Vector2 = Contours.sample(pts, closed, s)[0]
			var reach := _reach_at(p)
			var scale := reach / _reach
			var r := r0 * lerpf(0.7, 1.0, scale) * _rng.randf_range(0.85, 1.0)
			s += (2.0 * r0 + _gap) * _rng.randf_range(STREAM_SPACING * 0.8, STREAM_SPACING * 1.2)
			if _rng.randf() > lerpf(0.6, 1.0, scale):
				continue
			part += 1
			_strand += 1
			# How far this line can run: most of the reach here, or as far as
			# there is room (the subject closing in again, another line).
			var run := reach * _rng.randf_range(0.55, 1.0)
			var room := 0.0
			var q := p
			while room < run:
				var t := _fade_at(q)
				if t < 0.0 or t >= 1.0 or not _free(q, r_min):
					break
				q += _flow(q, t) * r_min
				room += r_min
			# As many stones as fill that, shrinking evenly from r to r_min: a
			# line cut short still tapers to nothing. Laid out before any is
			# placed: if one doesn't fit (the stones are wider than the path
			# just walked), the line is laid again with as many as did.
			var count := mini(int((room - r) / (r + r_min + _gap)), STREAM_STONES)
			for _try in 4:
				if count < 2:
					break
				var shrink := pow(r_min / r, 1.0 / count)
				var line := []
				var at := p
				var ri := r
				for _i in count + 1:
					var t := _fade_at(at)
					if t < 0.0 or t >= 1.0 or not _free(at, ri):
						break
					line.append([at, ri, t])
					var nr := ri * shrink
					at += _flow(at, t) * (ri + nr + _gap)
					ri = nr
				if line.size() == count + 1:
					for stone: Array in line:
						_add(stone[0], stone[1], stone[2], part % 2)
					break
				count = line.size() - 1


## The way out from the subject at p, turned by the flow field: not at all
## beside the subject, more with the fade t.
func _flow(p: Vector2, t: float) -> Vector2:
	var e := float(CELL) * 2.0
	var grad := Vector2(_sample(_smooth, p + Vector2(e, 0)) - _sample(_smooth, p - Vector2(e, 0)),
			_sample(_smooth, p + Vector2(0, e)) - _sample(_smooth, p - Vector2(0, e)))
	if grad.length_squared() < 1e-6:
		grad = Vector2.UP
	var turn := (_noise(p, 3, 0.8) - 0.5) * 1.8 * minf(1.0, 0.25 + t * 1.5)
	return grad.normalized().rotated(turn)


## Leaves out whole strands, in a seeded order, until at most `most` stones
## are left (no limit below 0).
func _thin(most: int) -> void:
	if most < 0 or _slots.size() <= most:
		return
	var sizes := {}
	for s in _slots:
		sizes[s["strand"]] = sizes.get(s["strand"], 0) + 1
	var order := sizes.keys()
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	var gone := {}
	var left := _slots.size()
	for strand: int in order:
		if left <= most:
			break
		gone[strand] = true
		left -= sizes[strand]
	var kept: Array[Dictionary] = []
	for s in _slots:
		if not gone.has(s["strand"]):
			kept.append(s)
	_slots = kept


# --- stones ---------------------------------------------------------------------

## Adds a round stone unless it would touch another, the subject's clear
## paper or the picture's edge. Returns whether it was added.
func _add(p: Vector2, r: float, fade: float, part: int) -> bool:
	if not _free(p, r):
		return false
	_remember(p, r)
	_slots.append({"shape": "round", "x": p.x, "y": p.y, "rotation": 0.0, "size": 2.0 * r, "width": 2.0 * r,
			"tone": 1 if fade > OUTER_TONE else 0, "part": part, "fade": fade, "strand": _strand})
	return true


## Whether a stone of radius r fits at p: inside the picture, off the
## subject's clear paper and a gap from every other stone.
func _free(p: Vector2, r: float) -> bool:
	if p.x < r + 2.0 or p.y < r + 2.0 or p.x > _w - r - 2.0 or p.y > _h - r - 2.0:
		return false
	if _sample(_dist, p) < _margin + r:
		return false
	var key := Vector2i(floori(p.x / _bucket), floori(p.y / _bucket))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for other: Vector3 in _grid.get(key + Vector2i(dx, dy), []):
				if Vector2(other.x, other.y).distance_to(p) < other.z + r + _gap:
					return false
	return true


func _remember(p: Vector2, r: float) -> void:
	# Stones bigger than a bucket (the subject's) go in every bucket they reach.
	var x0 := floori((p.x - r) / _bucket)
	var x1 := floori((p.x + r) / _bucket)
	var y0 := floori((p.y - r) / _bucket)
	var y1 := floori((p.y + r) / _bucket)
	if r <= _bucket * 0.5:
		x0 = floori(p.x / _bucket)
		x1 = x0
		y0 = floori(p.y / _bucket)
		y1 = y0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var key := Vector2i(x, y)
			if not _grid.has(key):
				_grid[key] = []
			_grid[key].append(Vector3(p.x, p.y, r))

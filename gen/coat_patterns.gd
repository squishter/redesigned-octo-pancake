class_name CoatPatterns
extends RefCounted
## Animal coat markings as scalar fields: value() is positive inside a
## marking (a stripe, a patch, a spot) and negative on the plain coat, so the
## markings' outlines are its zero iso-line (see FieldLines). Nothing about
## them is symmetric.
##
## Coordinates are "coat space": a part of an animal unrolled (along the
## part, and across it in body lengths; see AnimalGenerator). Striped coats also take a flow coordinate
## `phi` (distance along the part, so stripes cross it) and `v` (-1 on its
## top edge to 1 on its bottom, scaled by how much the part tapers its
## stripes toward the belly).
##
##   tiger: narrow stripes across the flow, forking and thinning to the belly
##   zebra: bold, even stripes, belly to back
##   cow: big irregular patches (Holstein)
##   pinto: very large patches, taller than wide (a paint horse)
##   dalmatian: round spots, scattered
##   cheetah: small solid spots, close together
##   leopard: rosettes, rings broken into 2-4 pieces
##   giraffe: a net of patches with narrow coat between
##   dapple: soft round spots of mixed sizes, in clusters
## Markings that belong to a body's shape (a pale belly, a blanket over the
## rump, socks) are AnimalGenerator's.

const COATS := ["tiger", "zebra", "cow", "pinto", "dalmatian", "cheetah", "leopard", "giraffe", "dapple"]
const LATTICE := 64

var coat := "solid"
var rng := RandomNumberGenerator.new()
## Scale of the markings (1 = sized for a body 1 long).
var scale := 1.0
var _lattice := PackedFloat32Array()
var _shift := Vector2.ZERO
var _p := {}
## Spots, rosettes or giraffe cells: [center, radius, aspect, angle, extra]
## by grid cell (Vector2i of `_cell`-sized cells).
var _spots := {}
var _cell := 0.2


## A coat (any name not in COATS has no markings). `bounds` is the
## coat-space area markings are scattered over.
static func make(coat_name: String, seed_value: int, bounds: Rect2, scale_by := 1.0) -> CoatPatterns:
	var c := CoatPatterns.new()
	c.coat = coat_name if coat_name in COATS else "solid"
	c.rng.seed = hash([seed_value, "coat", c.coat])
	c.scale = scale_by
	c._lattice.resize(LATTICE * LATTICE)
	for i in c._lattice.size():
		c._lattice[i] = c.rng.randf_range(-1.0, 1.0)
	c._shift = Vector2(c.rng.randf_range(0.0, 50.0), c.rng.randf_range(0.0, 50.0))
	c._setup(bounds)
	return c


func _setup(bounds: Rect2) -> void:
	var k := scale
	match coat:
		"tiger":
			_p = {"spacing": rng.randf_range(0.085, 0.12) * k, "warp": rng.randf_range(0.25, 0.45),
					"freq": rng.randf_range(2.5, 4.0) / k, "cut": rng.randf_range(0.42, 0.58), "taper": 0.38,
					"bend": rng.randf_range(-0.6, 0.6)}
		"zebra":
			_p = {"spacing": rng.randf_range(0.075, 0.095) * k, "warp": rng.randf_range(0.1, 0.2),
					"freq": rng.randf_range(1.5, 2.5) / k, "cut": rng.randf_range(-0.12, 0.08), "taper": 0.0,
					"bend": rng.randf_range(-0.4, 0.4)}
		"cow":
			_p = {"freq": rng.randf_range(2.2, 3.0) / k, "cut": rng.randf_range(0.0, 0.14)}
		"pinto":
			_p = {"freq": rng.randf_range(1.2, 1.7) / k, "cut": rng.randf_range(-0.08, 0.08)}
		"dalmatian":
			_scatter(bounds, 0.13 * k, 0.034 * k, 0.058 * k, 0.0)
		"cheetah":
			_scatter(bounds, 0.1 * k, 0.03 * k, 0.04 * k, 0.0)
		"dapple":
			_scatter(bounds, 0.11 * k, 0.034 * k, 0.07 * k, 0.35)
		"leopard":
			_scatter(bounds, 0.22 * k, 0.06 * k, 0.078 * k, 0.0)
			for key: Vector2i in _spots:
				for s: Array in _spots[key]:
					# Two to four gaps round each ring: [angle, half width].
					var gaps := []
					var count := rng.randi_range(2, 4)
					var a0 := rng.randf() * TAU
					for g in count:
						gaps.append([a0 + TAU * (g + rng.randf_range(-0.2, 0.2)) / count, rng.randf_range(0.22, 0.4)])
					s[4] = gaps
			_p = {"width": 0.034 * k}
		"giraffe":
			var spacing := rng.randf_range(0.16, 0.2) * k
			_cell = spacing
			var x := bounds.position.x - spacing
			while x < bounds.end.x + spacing:
				var y := bounds.position.y - spacing
				while y < bounds.end.y + spacing:
					var c := Vector2(x, y) + Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35)) * spacing
					_put([c, 0.0, 1.0, 0.0, null])
					y += spacing
				x += spacing
			_p = {"gap": rng.randf_range(0.024, 0.03) * k}


## Positive inside a marking. `a` in coat space; `phi` and `v` see above.
func value(a: Vector2, phi: float, v: float) -> float:
	match coat:
		"tiger", "zebra":
			var warp: float = _p["warp"] * _noise(a * _p["freq"])
			var s: float = phi / _p["spacing"] + warp + _p["bend"] * v * v * 0.5
			var cut: float = _p["cut"] + _p["taper"] * clampf(v, 0.0, 1.0) + 0.12 * _noise(a * _p["freq"] * 0.7 + Vector2(9, 3))
			return cos(TAU * s) - cut
		"cow":
			return _fbm(a * _p["freq"]) - _p["cut"]
		"pinto":
			return _fbm(Vector2(a.x, a.y * 0.6) * _p["freq"]) - _p["cut"]
		"dalmatian", "cheetah", "dapple":
			return _spot_value(a)
		"leopard":
			return _rosette_value(a)
		"giraffe":
			return _giraffe_value(a)
	return -1.0


## Coat-space points inside the markings, when the coat knows them (spot
## centers, the middle of each piece of a rosette, giraffe patches), so
## small markings get marked too; empty for the others.
func mark_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if not coat in ["dalmatian", "cheetah", "dapple", "leopard", "giraffe"]:
		return out
	for key: Vector2i in _spots:
		for spot: Array in _spots[key]:
			var c: Vector2 = spot[0]
			if coat != "leopard":
				out.append(c)
				continue
			var gaps: Array = spot[4]
			for g in gaps.size():
				var a: float = gaps[g][0]
				var b: float = gaps[(g + 1) % gaps.size()][0] + (TAU if g == gaps.size() - 1 else 0.0)
				out.append(c + Vector2.from_angle((a + b) * 0.5) * spot[1])
	return out


## Scatters spots `apart` apart (dart throwing) with radii in r0..r1;
## `cluster` > 0 thins them out where a low-frequency noise is low.
func _scatter(bounds: Rect2, apart: float, r0: float, r1: float, cluster: float) -> void:
	_cell = apart
	var area := (bounds.size.x + 2.0 * apart) * (bounds.size.y + 2.0 * apart)
	var tries := int(area / (apart * apart) * 4.0)
	for _i in tries:
		var c := Vector2(rng.randf_range(bounds.position.x - apart, bounds.end.x + apart),
				rng.randf_range(bounds.position.y - apart, bounds.end.y + apart))
		if cluster > 0.0 and _noise(c * 3.0 / scale) < -cluster:
			continue
		var r := rng.randf_range(r0, r1)
		var ok := true
		for s: Array in _near(c):
			var other: Vector2 = s[0]
			if c.distance_to(other) < apart * (0.6 + 0.4 * (r + s[1]) / (2.0 * r1)):
				ok = false
				break
		if ok:
			var spot := [c, r, rng.randf_range(0.7, 1.0), rng.randf() * PI, null]
			_put(spot)


func _put(spot: Array) -> void:
	var c: Vector2 = spot[0]
	var key := Vector2i(floori(c.x / _cell), floori(c.y / _cell))
	if not _spots.has(key):
		_spots[key] = []
	_spots[key].append(spot)


## Spots in the 3x3 cells around `p`.
func _near(p: Vector2) -> Array:
	var out := []
	var cx := floori(p.x / _cell)
	var cy := floori(p.y / _cell)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(cx + dx, cy + dy)
			if _spots.has(key):
				out.append_array(_spots[key])
	return out


func _spot_value(a: Vector2) -> float:
	var best := -1.0
	for s: Array in _near(a):
		var q: Vector2 = (a - s[0]).rotated(-s[3])
		q.y /= s[2]
		best = maxf(best, s[1] - q.length())
	return best


func _rosette_value(a: Vector2) -> float:
	var best := -1.0
	var half: float = _p["width"] * 0.5
	for s: Array in _near(a):
		var d: Vector2 = a - s[0]
		var dist := d.length()
		var ring: float = half - absf(dist - s[1])
		var angle := d.angle()
		for gap: Array in s[4]:
			ring = minf(ring, (absf(angle_difference(angle, gap[0])) - gap[1]) * dist * 0.6)
		best = maxf(best, ring)
	return best


func _giraffe_value(a: Vector2) -> float:
	var q := a + Vector2(_noise(a * 6.0 / scale), _noise(a * 6.0 / scale + Vector2(17, 5))) * 0.02 * scale
	var f1 := INF
	var f2 := INF
	for s: Array in _near(q):
		var d := q.distance_to(s[0])
		if d < f1:
			f2 = f1
			f1 = d
		elif d < f2:
			f2 = d
	if f2 == INF:
		return -1.0
	return (f2 - f1) * 0.5 - _p["gap"]


# --- noise -------------------------------------------------------------------------

## Smooth value noise, -1..1.
func _noise(p: Vector2) -> float:
	var q := p + _shift
	var x0 := floori(q.x)
	var y0 := floori(q.y)
	var fx := q.x - x0
	var fy := q.y - y0
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _lat(x0, y0)
	var b := _lat(x0 + 1, y0)
	var c := _lat(x0, y0 + 1)
	var d := _lat(x0 + 1, y0 + 1)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


func _lat(x: int, y: int) -> float:
	return _lattice[posmod(y, LATTICE) * LATTICE + posmod(x, LATTICE)]


func _fbm(p: Vector2) -> float:
	return _noise(p) * 0.65 + _noise(p * 2.1 + Vector2(31, 7)) * 0.3 + _noise(p * 4.3 + Vector2(3, 41)) * 0.12

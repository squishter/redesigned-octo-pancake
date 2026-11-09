class_name AnimalSurfaceCoat
extends RefCounted
## Seeded continuous fields in neutral skin space, never screen space. The
## projector evaluates them at visible surface points, not just mesh vertices.
##
## Natural coats follow the species and may be irregular, like real markings.
## Decorative coats are strictly repeating motifs (stripes, dots, checks...)
## with no noise, laid out on a seamless per-part surface chart (see fit()), so
## every boundary is a clean, regular outline rather than a blob.

const VERSION := 2
const DECORATIVE := [
	"stripes",
	"polka_dots",
	"checks",
	"gingham",
	"harlequin",
	"chevrons",
	"waves",
	"stars",
	"petals",
	"hearts",
	"scales"
]
const NATURAL := {
	"canine": ["source", "saddle", "patches", "spots", "tuxedo"],
	"feline": ["source", "tabby", "tuxedo", "points", "rosettes"],
	"equine": ["source", "pinto", "dapple", "socks"],
	"bovine": ["source", "patches"],
	"cervid": ["source", "spots"],
	"camelid": ["source", "socks"],
	"ovine": ["source", "patches"],
	"porcine": ["source", "patches"]
}
const LABELS := [
	"background",
	"coat",
	"markings",
	"pale coat",
	"dark features",
	"ivory features",
	"warm features"
]
## Motif repeat in neutral body lengths (the torso is normalized to length 1)
## at coat scale 1. About a dozen repeats along the body: big enough to paint.
const PERIOD := 0.13
## Busier motifs repeat at a larger size so each piece stays paintable.
const STYLE_SIZE := {"gingham": 1.5, "petals": 1.15, "scales": 1.1}
## Number of motif repeats around a part must be a multiple of this, so the
## pattern closes seamlessly around legs, tails and the torso.
const AROUND_MULTIPLE := {"checks": 2, "scales": 3}
## Orthographic view size (in neutral model heights) at which motifs have
## their nominal size. Closer crops, such as head portraits, get finer motifs
## (up to MAX_DETAIL times), so a portrait shows a pattern rather than blobs.
const VIEW_REFERENCE := 1.2
## Skin closer to a part's axis than this fraction of its mean radius (the
## chest front, the rump, the end of the snout) is a "cap" where a cylinder
## would pinch every motif into a starburst; caps use a flat chart instead.
const CAP_RADIUS := 0.5
const MAX_DETAIL := 2.5

var style := "source"
var seed_value := 0
var scale_value := 1.0
var palette := PackedColorArray()
var _noise := FastNoiseLite.new()
var _cells := FastNoiseLite.new()
var _phase := 0.0
var _kind := ""
var _offset := Vector2.ZERO
var _charts := {}
var _detail := 1.0
var _portrait := false


static func available(model_id: String, mode := "all") -> PackedStringArray:
	var kind := AnimalPoseCatalog.anatomy(model_id)
	var natural: Array = NATURAL.get(kind, ["source"]).duplicate()
	if model_id == "farm_zebra":
		natural = ["source", "zebra"]
	if model_id == "daydaze_lion":
		natural = ["source", "spots"]
	if mode == "decorative":
		return PackedStringArray(DECORATIVE)
	if mode != "natural":
		natural.append_array(DECORATIVE)
	return PackedStringArray(natural)


static func make(
	model_id: String, name_value: String, seed: int, scale_by := 1.0
) -> AnimalSurfaceCoat:
	if (
		name_value not in available(model_id)
		or not is_finite(scale_by)
		or scale_by < 0.5
		or scale_by > 1.8
	):
		return null
	var coat := AnimalSurfaceCoat.new()
	coat.style = name_value
	coat.seed_value = seed
	coat.scale_value = scale_by
	coat._kind = AnimalPoseCatalog.anatomy(model_id)
	coat._noise.seed = seed
	coat._noise.frequency = 3.5 / scale_by
	coat._noise.fractal_octaves = 2
	coat._cells.seed = seed + 137
	coat._cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	coat._cells.fractal_type = FastNoiseLite.FRACTAL_NONE
	coat._cells.frequency = 6.0 / scale_by
	coat._cells.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	coat._cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	coat._phase = rng.randf() * TAU
	coat._offset = Vector2(rng.randf(), rng.randf())
	coat.palette = PackedColorArray(
		[
			Color("faf8f3"),
			Color("c79358"),
			Color("594438"),
			Color("f4e8cf"),
			Color("292634"),
			Color("f6f0dc"),
			Color("bf727d")
		]
	)
	if name_value in DECORATIVE:
		var hue := rng.randf()
		coat.palette[1] = Color.from_hsv(hue, 0.42, 0.88)
		coat.palette[2] = Color.from_hsv(fposmod(hue + 0.46, 1), 0.64, 0.48)
		coat.palette[3] = Color.from_hsv(fposmod(hue + 0.13, 1), 0.20, 1.0)
	elif name_value in ["zebra", "tuxedo", "patches"]:
		coat.palette[1] = Color("eee9dc")
		coat.palette[2] = Color("45414c")
	elif name_value in ["pinto", "socks"]:
		coat.palette[1] = Color("af744e")
		coat.palette[2] = Color("f5e8cc")
	return coat


func metadata() -> Dictionary:
	return {"version": VERSION, "style": style, "seed": seed_value, "scale": scale_value}


func is_fitted() -> bool:
	return not _charts.is_empty()


## Matches the motif layout to the orthographic camera that will show it:
## size from its view size in model heights, and for head portraits a flat
## front-facing grid, centred on the face, instead of rings around the snout.
func set_view(camera: Dictionary) -> void:
	var view_size: float = camera.get("size", VIEW_REFERENCE)
	_detail = (
		clampf(VIEW_REFERENCE / view_size, 1.0, MAX_DETAIL)
		if is_finite(view_size) and view_size > 0
		else 1.0
	)
	_portrait = camera.get("head", false)


## Lays out the decorative surface chart from a model's neutral coordinates.
## Pass the whole animal (rest + regions), even when projecting a head crop,
## so the neck carries the same motifs as in a full-body view. Only depends on
## pose-independent attributes, so any snapshot of the model gives one result.
func fit(data: Dictionary) -> void:
	_charts = {}
	var rest: PackedVector3Array = data.get("rest", PackedVector3Array())
	var regions: PackedInt32Array = data.get("regions", PackedInt32Array())
	var groups := {}
	for index in mini(rest.size(), regions.size()):
		var region := regions[index]
		if region == 7:
			region = 1  # Ears continue the head's motifs.
		if not groups.has(region):
			groups[region] = PackedVector3Array()
		groups[region].append(rest[index])
	var everything := PackedVector3Array(rest)
	if everything.is_empty():
		everything.append(Vector3.ZERO)
	var torso: PackedVector3Array = groups.get(0, everything)
	var body_center := _mean(torso)
	_charts[-1] = _chart(everything, Vector3.BACK, Vector3.UP, _mean(everything))
	_charts[0] = _chart(torso, Vector3.BACK, Vector3.UP, Vector3(body_center.x, body_center.y, 0))
	for region: int in groups:
		var points: PackedVector3Array = groups[region]
		var center := _mean(points)
		if region == 1:
			# Around the forward axis, like the torso: side views see an even
			# grid continuing from the neck, front views a ring pattern
			# centred on the (protected) nose.
			_charts[1] = _chart(points, Vector3.BACK, Vector3.UP, Vector3(center.x, center.y, 0))
		elif region in [2, 3, 4, 5, 6]:
			var axis := _principal_axis(points, center)
			if region == 6:
				if axis.dot(center - body_center) < 0:
					axis = -axis
			elif axis.y > 0:
				axis = -axis
			var reference := Vector3.BACK if region != 6 else Vector3.UP
			if absf(axis.dot(reference)) > 0.9:
				reference = Vector3.RIGHT
			_charts[region] = _chart(points, axis, reference, center)


static func _mean(points: PackedVector3Array) -> Vector3:
	var total := Vector3.ZERO
	for point in points:
		total += point
	return total / maxf(1, points.size())


static func _principal_axis(points: PackedVector3Array, center: Vector3) -> Vector3:
	var xx := 0.0
	var xy := 0.0
	var xz := 0.0
	var yy := 0.0
	var yz := 0.0
	var zz := 0.0
	for point in points:
		var d := point - center
		xx += d.x * d.x
		xy += d.x * d.y
		xz += d.x * d.z
		yy += d.y * d.y
		yz += d.y * d.z
		zz += d.z * d.z
	var axis := Vector3(0.05, -1, 0.1).normalized()
	for step in 24:
		var next := Vector3(
			xx * axis.x + xy * axis.y + xz * axis.z,
			xy * axis.x + yy * axis.y + yz * axis.z,
			xz * axis.x + yz * axis.y + zz * axis.z
		)
		if next.length_squared() < 1e-12:
			return Vector3.DOWN
		axis = next.normalized()
	return axis


## A cylinder around `axis` through `center`: (along, angle) maps the part's
## skin with near-equal spacing in both directions.
static func _chart(
	points: PackedVector3Array, axis: Vector3, reference: Vector3, center: Vector3
) -> Dictionary:
	var first := (reference - axis * reference.dot(axis)).normalized()
	var second := axis.cross(first)
	var radius := 0.0
	for point in points:
		var d := point - center
		radius += (d - axis * d.dot(axis)).length()
	radius /= maxf(1, points.size())
	return {
		"center": center,
		"axis": axis,
		"first": first,
		"second": second,
		"radius": radius,
		"circumference": maxf(0.001, radius * TAU)
	}


# A classification table deliberately has one return per semantic case.
# gdlint: disable=max-returns
func label_at(
	rest: Vector3, flow: Vector3, face: Vector3, region: int, original: Color, protect: float
) -> int:
	if protect > 0.5:
		if (
			original.r > original.g * 1.5
			and original.r > original.b * 1.1
			and original.b > original.g * 0.8
		):
			return 6
		return 5 if original.get_luminance() > 0.5 else 4
	if style == "source":
		var light := original.get_luminance()
		return 3 if light > 0.6 else 2 if light < 0.11 else 1
	if style in DECORATIVE:
		return _motif(_cell(rest, region))
	var field := _field(rest, flow, face, region)
	if style in ["saddle", "tuxedo", "socks", "points"]:
		if (
			region in [2, 3, 4, 5]
			and flow.z > (0.72 if style != "points" else 0.62) + sin(_phase + region) * 0.08
		):
			return 2 if style == "points" else 3
		if region == 1 and absf(face.x) < 0.13 + (1 - face.y) * 0.07 and face.z > 0.5:
			return 3
	return 2 if field > 0 else 1


## Chart coordinates in motif cells: x runs along the part (body length, down
## a leg, out along the tail, up the head), y wraps around it a whole number
## of times so no seam ever cuts a motif.
func _cell(rest: Vector3, region: int) -> Vector2:
	if _charts.is_empty():
		fit({})
	var key := 1 if region == 7 else region
	var chart: Dictionary = _charts.get(key, _charts[-1])
	var period: float = PERIOD * scale_value * STYLE_SIZE.get(style, 1.0) / _detail
	if _portrait:
		var face: Dictionary = _charts.get(1, _charts[-1])
		var flat: Vector3 = rest - face.center
		return Vector2(-flat.y / period + _offset.x, flat.x / period + 0.5)
	var d: Vector3 = rest - chart.center
	var side := Vector2(d.dot(chart.first), d.dot(chart.second))
	if side.length() < chart.radius * CAP_RADIUS:
		return side / period + _offset
	var around := side.angle() / TAU
	var multiple: int = AROUND_MULTIPLE.get(style, 1)
	var repeats := maxi(multiple, roundi(chart.circumference / period / multiple) * multiple)
	return Vector2(d.dot(chart.axis) / period, around * repeats) + _offset


func _motif(p: Vector2) -> int:
	var cell := Vector2(fposmod(p.x, 1), fposmod(p.y, 1))
	match style:
		"stripes":
			return 2 if cell.x < 0.46 else 1
		"checks":
			return 2 if posmod(floori(p.x) + floori(p.y), 2) == 0 else 1
		"gingham":
			# Two crossing bands: plain, single band, and their darker overlap.
			var bands := int(cell.x < 0.5) + int(cell.y < 0.5)
			return [3, 1, 2][bands]
		"harlequin":
			return 2 if posmod(floori(p.x + p.y) + floori(p.x - p.y), 2) == 0 else 1
		"chevrons":
			var zig := absf(cell.y - 0.5) * 2.0
			return 2 if fposmod(p.x + zig * 0.6, 1) < 0.5 else 1
		"waves":
			return 2 if fposmod(p.x + sin(p.y * TAU) * 0.2, 1) < 0.5 else 1
		"scales":
			return _scale(p)
	# Spaced motifs on a staggered (brick) lattice.
	var row := floori(p.x)
	var local := Vector2(cell.x, fposmod(p.y + 0.5 * (row & 1), 1)) - Vector2.ONE * 0.5
	match style:
		"polka_dots":
			return 2 if local.length() < 0.27 else 1
		"stars":
			return 2 if _in_star(local, 0.36, 0.16) else 1
		"petals":
			if local.length() < 0.1:
				return 3
			var angle := atan2(local.y, local.x)
			return 2 if local.length() < 0.34 * (0.5 + 0.5 * absf(cos(angle * 2.5))) else 1
		"hearts":
			# Unit heart curve (x² + y² − 1)³ − x²y³ ≤ 0, tip pointing along x.
			var q := Vector2(local.y, -local.x) / 0.27 + Vector2(0, 0.12)
			var a := q.x * q.x + q.y * q.y - 1
			return 2 if a * a * a - q.x * q.x * q.y * q.y * q.y <= 0 else 1
	return 1


## A straight-edged five-pointed star of tip radius `outer`.
static func _in_star(local: Vector2, outer: float, inner: float) -> bool:
	var sector := TAU / 5
	# Fold into one point's half-sector: 0 at the tip, sector / 2 at a valley.
	var angle := sector * 0.5 - absf(fposmod(atan2(local.y, local.x), sector) - sector * 0.5)
	var point := Vector2(cos(angle), sin(angle)) * local.length()
	var tip := Vector2(outer, 0)
	var valley := Vector2(cos(sector * 0.5), sin(sector * 0.5)) * inner
	var edge := valley - tip
	var to_point := point - tip
	return edge.x * to_point.y - edge.y * to_point.x >= 0


## Overlapping round scales on a staggered lattice, each row tucked under the
## next (closer-packed than the disc size), three-colored so neighbouring
## scales never share a paint and every scale keeps its own outline.
func _scale(p: Vector2) -> int:
	var spacing := 0.55
	var top := floori(p.x / spacing) + 1
	for row: int in range(top, top - 4, -1):
		var shift := 0.5 * (row & 1)
		var column := roundi(p.y - shift)
		var reach := Vector2(p.x - row * spacing, p.y - column - shift)
		if reach.length() < 0.62 or row == top - 3:
			# Axial coordinates on the triangular lattice; (q − r) mod 3 never
			# matches between touching scales.
			var axial := column - (row - (row & 1)) / 2
			return 1 + posmod(axial - row, 3)
	return 1


func _field(p: Vector3, uv: Vector3, face: Vector3, region: int) -> float:
	var warp := _noise.get_noise_3dv(p)
	var u := uv.x / scale_value
	match style:
		"tabby", "zebra":
			var bands := sin(u * TAU * (7 if style == "zebra" else 5.5) + warp * 2.2) - 0.22
			if region == 1:
				var facial := sin((face.y + absf(face.x) * 0.55) * TAU * 3.5 + warp) - 0.4
				return lerpf(bands, facial, smoothstep(0.15, 0.65, face.z))
			return bands
		"spots", "dapple":
			return -0.67 - _cells.get_noise_3dv(p)
		"rosettes":
			var distance := _cells.get_noise_3dv(p)
			return 0.065 - absf(distance + 0.62) - maxf(0, warp - 0.2) * 0.4
		"patches", "pinto":
			return _noise.get_noise_3dv(p * (0.7 if style == "pinto" else 1.0)) + 0.03
		"saddle":
			return (
				p.y - 0.36 + sin(p.z * 4 + _phase) * 0.07
				if region == 0
				else absf(face.x) - 0.55 if region == 1 else -1.0
			)
		"tuxedo":
			return p.y - 0.3 if region == 0 else absf(face.x) - 0.38 if region == 1 else 1.0
		"socks":
			return -1.0
		"points":
			return (
				0.65 - face.y + absf(face.x) * 0.15
				if region in [1, 7]
				else 1.0 if region == 6 else -1.0
			)
	return -1.0

class_name AnimalSurfaceCoat
extends RefCounted
## Seeded continuous fields in neutral skin space, never screen space. The
## projector evaluates them at visible surface points, not just mesh vertices.

const DECORATIVE := ["ribbons", "petals", "scales", "stars", "mosaic", "lace"]
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

var style := "source"
var seed_value := 0
var scale_value := 1.0
var palette := PackedColorArray()
var _noise := FastNoiseLite.new()
var _cells := FastNoiseLite.new()
var _phase := 0.0
var _kind := ""


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
	if name_value == "mosaic":
		coat._cells.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	coat._phase = rng.randf() * TAU
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
	return {"version": 1, "style": style, "seed": seed_value, "scale": scale_value}


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
	var field := _field(rest, flow, face, region)
	if style in ["saddle", "tuxedo", "socks", "points"]:
		if (
			region in [2, 3, 4, 5]
			and flow.z > (0.72 if style != "points" else 0.62) + sin(_phase + region) * 0.08
		):
			return 2 if style == "points" else 3
		if region == 1 and absf(face.x) < 0.13 + (1 - face.y) * 0.07 and face.z > 0.5:
			return 3
	if style == "mosaic":
		return 1 + posmod(floori((_cells.get_noise_3dv(rest) + 1.0) * 2.9), 3)
	return 2 if field > 0 else 1


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
		"ribbons":
			return sin(u * TAU * 4 + sin(p.y * 9 + p.x * 4 + _phase) * 1.4 + warp) - 0.1
		"lace":
			return 0.24 - absf(sin(u * TAU * 4 + warp) * cos(p.y * 13 + p.x * 5 + _phase))
		"petals", "stars", "scales":
			var q := (
				Vector2(u, p.y / scale_value + p.x * 0.2) * 4.5
				+ Vector2(_phase / TAU, _phase * 0.317)
			)
			q.y += sin(q.x * TAU * 0.5) * 0.12
			q = Vector2(fposmod(q.x + 0.5, 1), fposmod(q.y + 0.5, 1)) - Vector2.ONE * 0.5
			var angle := q.angle()
			var radius := 0.29 + 0.09 * cos(angle * (5 if style == "stars" else 6))
			if style == "scales":
				return 0.035 - absf(q.distance_to(Vector2(0, -0.35)) - 0.52)
			return radius - q.length()
	return -1.0

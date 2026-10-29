class_name MandalaGenerator
extends RefCounted
## Seeded symmetric line art: mandalas, flowers, snowflakes, hearts and
## butterflies. The same seed and options always give the same picture.
##
## Output is vector polylines in unit space (x and y in -1..1, y down), so it
## is crisp at any size. LineRaster turns it into a mask for the slot packer,
## and RegionPaint fills it with a theme for Kit mode.
##
## Mandalas are built as rings from the center outward. Each ring picks a
## motif, drawn once in a wedge (symmetric about the wedge's center line),
## then rotated 6, 8, 10 or 12 times. The optional wobble nudges each wedge
## copy a little so it looks hand-drawn; it fades to zero at the ring
## boundaries, so every region stays closed.
##
## Flowers come from FlowerGenerator's petal templates, hearts from
## HeartGenerator, butterflies from ButterflyGenerator and snowflakes from
## SnowflakeGenerator.

const VARIANTS := ["mandala", "flower", "snowflake", "heart", "butterfly"]
const MOTIFS := ["petals", "scallops", "dots", "zigzag", "lattice", "leaves"]

var rng := RandomNumberGenerator.new()
var wobble := 0.0
var polylines: Array[PackedVector2Array] = []
var closed := PackedByteArray()


## options: variant (one of VARIANTS, default "mandala"), wobble (0..1, the
## "semi-symmetric" strength, default 0); flowers also take FlowerGenerator's
## template and recent, hearts HeartGenerator's shape, collar, patterns and
## recent, butterflies ButterflyGenerator's shape, border, body, antennae and
## recent, snowflakes SnowflakeGenerator's center, arm, tip, between, details
## and recent. Returns
## {"seed", "variant", "symmetry": "radial" | "mirror", "polylines", "closed"},
## plus "flower" (FlowerGenerator's template, rings and center) for flowers,
## "heart" (shape, collar, patterns, divider) for hearts, "butterfly"
## (shape, border, body, antennae, fore, hind) for butterflies and
## "snowflake" (center, arm, tip, between, details) for snowflakes.
static func generate(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var g := MandalaGenerator.new()
	g.rng.seed = seed_value
	g.wobble = clampf(options.get("wobble", 0.0), 0.0, 1.0)
	var variant: String = options.get("variant", "mandala")
	if variant == "random":
		variant = VARIANTS[g.rng.randi_range(0, VARIANTS.size() - 1)]
	match variant:
		"flower":
			var f := FlowerGenerator.generate(seed_value, options)
			return {
				"seed": seed_value,
				"variant": variant,
				"symmetry": "radial",
				"polylines": f["polylines"],
				"closed": f["closed"],
				"flower": {"template": f["template"], "rings": f["rings"], "center": f["center"]},
			}
		"snowflake":
			var f := SnowflakeGenerator.generate(seed_value, options)
			return {
				"seed": seed_value,
				"variant": variant,
				"symmetry": "radial",
				"polylines": f["polylines"],
				"closed": f["closed"],
				"snowflake": {"center": f["center"], "arm": f["arm"], "tip": f["tip"], "between": f["between"],
						"details": f["details"]},
			}
		"heart":
			var h := HeartGenerator.generate(seed_value, options)
			return {
				"seed": seed_value,
				"variant": variant,
				"symmetry": "mirror",
				"polylines": h["polylines"],
				"closed": h["closed"],
				"heart": {"shape": h["shape"], "collar": h["collar"], "patterns": h["patterns"], "divider": h["divider"]},
			}
		"butterfly":
			var b := ButterflyGenerator.generate(seed_value, options)
			return {
				"seed": seed_value,
				"variant": variant,
				"symmetry": "mirror",
				"polylines": b["polylines"],
				"closed": b["closed"],
				"butterfly": {"shape": b["shape"], "border": b["border"], "body": b["body"],
						"antennae": b["antennae"], "fore": b["fore"], "hind": b["hind"]},
			}
		_:
			variant = "mandala"
			g._build_mandala()
	return {
		"seed": seed_value,
		"variant": variant,
		"symmetry": "mirror" if variant in ["heart", "butterfly"] else "radial",
		"polylines": g.polylines,
		"closed": g.closed,
	}


# --- helpers ------------------------------------------------------------------

func _add(points: PackedVector2Array, is_closed: bool = false) -> void:
	polylines.append(points)
	closed.append(1 if is_closed else 0)


static func _polar(r: float, a: float) -> Vector2:
	return Vector2(r * cos(a), r * sin(a))


static func circle(center: Vector2, r: float, segments: int = 0) -> PackedVector2Array:
	if segments <= 0:
		segments = maxi(24, int(240.0 * minf(1.0, r * 2.0 + 0.1)))
	var pts := PackedVector2Array()
	for i in segments:
		pts.append(center + _polar(r, TAU * i / segments))
	return pts


func _pick(list: Array) -> Variant:
	return list[rng.randi_range(0, list.size() - 1)]


## Repeats a wedge motif `m` times around the center. `motif` is an Array of
## [PackedVector2Array of (r, theta) points, closed: bool], with theta measured
## from the wedge's center line.
func _add_ring_motif(motif: Array, m: int, r_in: float, r_out: float, rotation: float = 0.0) -> void:
	var alpha := TAU / m
	for k in m:
		var wa := rng.randf_range(-1.0, 1.0) * 0.05 * wobble * alpha
		var wr := rng.randf_range(-1.0, 1.0) * 0.07 * wobble * (r_out - r_in)
		var base := rotation + k * alpha
		for part in motif:
			var src: PackedVector2Array = part[0]
			var out := PackedVector2Array()
			out.resize(src.size())
			for i in src.size():
				var r := src[i].x
				var t := src[i].y
				var taper := 0.0
				if r_out > r_in:
					taper = sin(PI * clampf((r - r_in) / (r_out - r_in), 0.0, 1.0))
				out[i] = _polar(r + wr * taper, base + t + wa * taper)
			_add(out, part[1])


## A small circle around the polar point (r, t), returned in polar coords so
## it rotates with its wedge.
static func _dot(r: float, t: float, radius: float, n: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		var p := Vector2(r + radius * cos(a), radius * sin(a))
		pts.append(Vector2(p.length(), p.angle() + t))
	return pts


static func _to_polar(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.length(), p.angle()))
	return out


## Petal outline from (r_in, -half_w) out to a tip of height h and back.
static func _petal(r_in: float, h: float, half_w: float, shape: String, n: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var u := -1.0 + 2.0 * i / n
		var f: float
		if shape == "round":
			f = pow(cos(u * PI / 2.0), 0.7)
		else:
			f = pow(1.0 - absf(u), 0.75)
		pts.append(Vector2(r_in + h * f, u * half_w))
	return pts


## A leaf-like lens between two points, bulging by `bulge` x its length.
static func _lens(a: Vector2, b: Vector2, bulge: float, n: int = 16) -> PackedVector2Array:
	var d := b - a
	var normal := Vector2(-d.y, d.x).normalized()
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		pts.append(a + d * t + normal * (bulge * d.length() * sin(PI * t) * 0.5))
	for i in range(n - 1, 0, -1):
		var t := float(i) / n
		pts.append(a + d * t - normal * (bulge * d.length() * sin(PI * t) * 0.5))
	return pts


# --- ring motifs: each returns parts for one wedge of angular width alpha ---------

func _motif(name: String, r_in: float, r_out: float, alpha: float) -> Array:
	var w := r_out - r_in
	var rmid := (r_in + r_out) / 2.0
	var parts := []
	match name:
		"petals":
			var shape: String = _pick(["round", "pointed"])
			var half: float = alpha if rng.randf() < 0.35 else alpha / 2.0  # wide petals overlap
			parts.append([_petal(r_in, w * rng.randf_range(0.8, 1.0), half, shape), false])
			if rng.randf() < 0.7:
				parts.append([_petal(r_in, w * rng.randf_range(0.4, 0.6), half * 0.55, shape), false])
		"scallops":
			var h := w * rng.randf_range(0.45, 0.7)
			var pts := PackedVector2Array()
			for i in 25:
				var u := -1.0 + 2.0 * i / 24.0
				pts.append(Vector2(r_out - h * sqrt(maxf(0.0, 1.0 - u * u)), u * alpha / 2.0))
			parts.append([pts, false])
			var dr := minf(h * 0.28, (r_out - h * 0.45) * alpha * 0.18)
			if dr > 0.008:
				parts.append([_dot(r_out - h * 0.45, 0.0, dr), true])
		"dots":
			var big := minf(w * 0.34, rmid * sin(alpha / 2.0) * 0.62)
			parts.append([_dot(rmid, 0.0, big), true])
			var small := minf(w * 0.18, big * 0.5)
			if small > 0.008:
				parts.append([_dot(rmid, alpha / 2.0, small), true])
		"zigzag":
			parts.append([PackedVector2Array([Vector2(r_in, -alpha / 2.0), Vector2(r_out, 0.0), Vector2(r_in, alpha / 2.0)]), false])
			if rng.randf() < 0.6:
				var a := r_in + w * 0.12
				var b := r_in + w * 0.62
				parts.append([PackedVector2Array([Vector2(a, -alpha * 0.22), Vector2(b, 0.0), Vector2(a, alpha * 0.22)]), true])
		"lattice":
			parts.append([PackedVector2Array([Vector2(r_in, -alpha / 2.0), Vector2(r_out, alpha / 2.0)]), false])
			parts.append([PackedVector2Array([Vector2(r_in, alpha / 2.0), Vector2(r_out, -alpha / 2.0)]), false])
		"leaves":
			var base := Vector2(r_in, 0.0)
			for side in [-1.0, 1.0]:
				var tip := _polar(r_in + w * 0.92, side * alpha * 0.32)
				parts.append([_to_polar(_lens(base, tip, 0.28)), true])
			var rd := minf(w * 0.14, r_out * alpha * 0.12)
			if rd > 0.008:
				parts.append([_dot(r_out - w * 0.22, 0.0, rd), true])
	return parts


# --- variants -----------------------------------------------------------------

func _build_mandala() -> void:
	var n: int = _pick([6, 8, 10, 12])
	var rc := rng.randf_range(0.08, 0.13)
	_add(circle(Vector2.ZERO, rc), true)
	_add_ring_motif(_motif("petals", rc * 0.35, rc, TAU / n), n, rc * 0.35, rc)
	_add(circle(Vector2.ZERO, rc * 0.35), true)
	var r := rc
	var last := ""
	while r < 0.97:
		var w := rng.randf_range(0.09, 0.17)
		if 1.0 - (r + w) < 0.08:
			w = 1.0 - r
		var r_out := r + w
		var choices := []
		for motif_name in MOTIFS:
			if motif_name != last:
				choices.append(motif_name)
		var motif: String = _pick(choices)
		last = motif
		# Outer rings have room for twice the repeats.
		var m := n
		if TAU * (r + r_out) / 2.0 / (2 * n) > 0.075 and rng.randf() < 0.6:
			m = 2 * n
		var alpha := TAU / m
		var parts := _motif(motif, r, r_out, alpha)
		var rot: float = alpha / 2.0 if rng.randf() < 0.5 else 0.0
		_add_ring_motif(parts, m, r, r_out, rot)
		_add(circle(Vector2.ZERO, r_out), true)
		r = r_out

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
## Flowers come from FlowerGenerator's petal templates.

const VARIANTS := ["mandala", "flower", "snowflake", "heart", "butterfly"]
const MOTIFS := ["petals", "scallops", "dots", "zigzag", "lattice", "leaves"]

var rng := RandomNumberGenerator.new()
var wobble := 0.0
var polylines: Array[PackedVector2Array] = []
var closed := PackedByteArray()


## options: variant (one of VARIANTS, default "mandala"), wobble (0..1, the
## "semi-symmetric" strength, default 0); flowers also take FlowerGenerator's
## template and recent. Returns
## {"seed", "variant", "symmetry": "radial" | "mirror", "polylines", "closed"},
## plus "flower" (FlowerGenerator's template, rings and center) for flowers.
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
			g._build_snowflake()
		"heart":
			g._build_heart()
		"butterfly":
			g._build_butterfly()
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


func _build_snowflake() -> void:
	var w := rng.randf_range(0.035, 0.055)
	var c0 := rng.randf_range(0.14, 0.22)
	for s in [c0, c0 * 0.55]:
		var hex := PackedVector2Array()
		for i in 6:
			hex.append(_polar(s, TAU * i / 6.0 + TAU / 12.0))
		_add(hex, true)
	# One arm along +x, then rotated six times.
	var x0 := c0 * cos(TAU / 12.0) - 0.002
	var parts: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(x0, -w), Vector2(0.88, -w), Vector2(1.0, 0.0), Vector2(0.88, w), Vector2(x0, w)]),
	]
	var branches := rng.randi_range(2, 3)
	for i in branches:
		var bx := x0 + (1.0 - x0) * (0.22 + 0.45 * i / maxf(1.0, branches - 1.0)) * rng.randf_range(0.95, 1.05)
		var bl := (1.0 - bx) * rng.randf_range(0.5, 0.7) + 0.1
		var bw := w * rng.randf_range(1.6, 2.0)
		var dir := Vector2.from_angle(deg_to_rad(rng.randf_range(50.0, 60.0)))
		var normal := Vector2(dir.y, -dir.x)
		var mid := Vector2(bx, w) + dir * bl * 0.35
		# A blade whose base sits on the arm's edge, so it closes against it,
		# widest a third of the way out. Built on the +y side, then mirrored.
		var blade := PackedVector2Array([
			Vector2(bx - bw, w),
			mid - normal * bw * 0.75,
			Vector2(bx, w) + dir * bl,
			mid + normal * bw * 0.75,
			Vector2(bx + bw, w),
		])
		parts.append(blade)
		var mirrored := PackedVector2Array()
		for v in blade:
			mirrored.append(Vector2(v.x, -v.y))
		parts.append(mirrored)
	var dx := x0 + (1.0 - x0) * 0.62
	parts.append(PackedVector2Array([Vector2(dx - 0.05, 0), Vector2(dx, -w * 0.55), Vector2(dx + 0.05, 0), Vector2(dx, w * 0.55)]))
	for k in 6:
		var rot := TAU * k / 6.0
		for p in parts:
			var pts := PackedVector2Array()
			for v in p:
				pts.append(v.rotated(rot))
			_add(pts, true)


static func _heart_point(t: float, s: float) -> Vector2:
	var x := 16.0 * pow(sin(t), 3)
	var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
	# Scale about a point near the heart's middle so nested hearts stay centered.
	return Vector2(x / 17.0 * s, -y / 17.0 * s - 0.05 * (1.0 - s) + 0.08)


func _build_heart() -> void:
	var scales := [1.0, rng.randf_range(0.66, 0.74), rng.randf_range(0.36, 0.44)]
	for s in scales:
		var pts := PackedVector2Array()
		for i in 240:
			pts.append(_heart_point(TAU * i / 240.0, s))
		_add(pts, true)
	# Rays between the outer and middle heart, mirror-symmetric, with a dot per cell.
	var k := rng.randi_range(5, 8)
	for i in range(1, k + 1):
		var t := PI * i / (k + 1)
		for tt in [t, TAU - t]:
			_add(PackedVector2Array([_heart_point(tt, scales[1]), _heart_point(tt, scales[0])]))
	for i in k + 1:
		var t := PI * (i + 0.5) / (k + 1)
		for tt in [t, TAU - t]:
			var a := _heart_point(tt, scales[1])
			var b := _heart_point(tt, scales[0])
			_add(circle((a + b) / 2.0, a.distance_to(b) * 0.2, 28), true)
	var k2 := rng.randi_range(3, 5)
	for i in range(1, k2 + 1):
		var t := PI * i / (k2 + 1)
		for tt in [t, TAU - t]:
			_add(PackedVector2Array([_heart_point(tt, scales[2]), _heart_point(tt, scales[1])]))


func _build_butterfly() -> void:
	var anchor := Vector2(0.03, -0.05)
	var wings := [
		# phi0, phi1, size, wobble, veins
		[deg_to_rad(-100.0), deg_to_rad(5.0), rng.randf_range(0.95, 1.05), rng.randf_range(0.05, 0.12), rng.randi_range(3, 4)],
		[deg_to_rad(10.0), deg_to_rad(95.0), rng.randf_range(0.62, 0.75), rng.randf_range(0.03, 0.1), rng.randi_range(2, 3)],
	]
	var parts := []  # [points, closed]
	for wing in wings:
		var phi0: float = wing[0]
		var phi1: float = wing[1]
		var radius_at := func(t: float) -> float:
			return wing[2] * pow(sin(PI * t), 0.55) * (1.0 + wing[3] * cos(3.0 * PI * t))
		var outline := PackedVector2Array()
		for i in 81:
			var t := i / 80.0
			outline.append(anchor + _polar(radius_at.call(t), lerpf(phi0, phi1, t)))
		parts.append([outline, true])
		var inner_s := rng.randf_range(0.55, 0.65)
		var inner := PackedVector2Array()
		for p in outline:
			inner.append(anchor + (p - anchor) * inner_s)
		parts.append([inner, true])
		var veins: int = wing[4]
		for i in range(1, veins + 1):
			var t := float(i) / (veins + 1)
			parts.append([PackedVector2Array([anchor, anchor + _polar(radius_at.call(t), lerpf(phi0, phi1, t))]), false])
		# A spot in each cell of the outer band.
		for i in veins + 1:
			var t := (i + 0.5) / (veins + 1)
			var rr: float = radius_at.call(t)
			var size := rr * (1.0 - inner_s) * 0.22
			if size > 0.012:
				parts.append([circle(anchor + _polar(rr * (1.0 + inner_s) / 2.0, lerpf(phi0, phi1, t)), size, 24), true])
	for part in parts:
		_add(part[0], part[1])
		var mirrored := PackedVector2Array()
		for p in part[0]:
			mirrored.append(Vector2(-p.x, p.y))
		_add(mirrored, part[1])
	# Body, head and antennae.
	var body := PackedVector2Array()
	for i in 60:
		body.append(Vector2(0.05 * cos(TAU * i / 60.0), 0.42 * sin(TAU * i / 60.0)))
	_add(body, true)
	_add(circle(Vector2(0, -0.47), 0.06, 32), true)
	for s in [-1.0, 1.0]:
		var antenna := PackedVector2Array()
		for i in 13:
			var t := i / 12.0
			antenna.append(Vector2(s * (0.02 + 0.25 * t * t), -0.52 - 0.32 * t))
		_add(antenna)
		_add(circle(Vector2(s * 0.27, -0.85), 0.035, 20), true)

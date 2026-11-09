class_name SlotPatterns
extends RefCounted
## Some of SlotPacker's patterns, kept apart to keep that file short: they
## work on the packer's current region and free field.


## Straight parallel rows across the region (along its axis, turned by
## `turn`), each clipped to the region and evenly spaced inside, with the
## middle row through the centroid; rows away from the middle are `grade`
## times the size of the row before. Rows alternate tones when `banded`.
static func stripes(p: SlotPacker, region: Dictionary, r0: float, shape: String, turn: float, banded: bool,
		grade: float, spaced: bool) -> void:
	var c: Vector2 = region["centroid"]
	var dir := Vector2.from_angle(region["axis"] + turn)
	var nrm := dir.orthogonal()
	var bbox: Rect2i = region["bbox"]
	var reach := Vector2(bbox.size).length() / 2.0 + 2.0
	# Row offsets from the middle row outward on both sides, each row `grade`
	# times the size of the one nearer the middle.
	# With spacers, every other row is a thin row of small stones.
	var offsets := [0.0]
	var sizes := [r0]
	var off := 0.0
	var r := r0
	var main := r0
	var i := 0
	while off < reach and offsets.size() < 200:
		i += 1
		var nr: float
		if spaced and i % 2 == 1:
			nr = r0 * SlotPacker.SPACER
		else:
			main = clampf(main * grade, p.unit * 0.45, p.unit * 1.6)
			nr = main
		off += r + p.gap + nr
		r = nr
		offsets.append_array([off, -off])
		sizes.append_array([r, r])
	var part0 := p._part
	for k in offsets.size():
		r = sizes[k]
		# Rows the same distance from the middle are one part, so the stripes
		# stay mirror-symmetric when parts change type.
		var ring := (k + 1) / 2
		p._tone = (1 if spaced and ring % 2 == 1 else ((ring % 2) if banded else 0))
		p._part = part0 + 1 + ring
		var base: Vector2 = c + nrm * float(offsets[k])
		# Inside stretches of this row, where a full stone could sit.
		var run_start := NAN
		var t := -reach
		while t <= reach + 1.0:
			var q := base + dir * t
			var inside := t <= reach and p._free_at(q) >= r * 0.6 + p.gap
			if inside and is_nan(run_start):
				run_start = t
			elif not inside and not is_nan(run_start):
				var pts := PackedVector2Array([base + dir * run_start, base + dir * (t - 1.0)])
				p._along(pts, false, r, shape)
				run_start = NAN
			t += 1.0
	p._part = part0 + 1 + (offsets.size() + 1) / 2
	p._tone = 0


## A center stone, then rings of stones on shared spokes, each ring's stones
## as big as the spacing between spokes allows, so they grow outward.
static func sunburst(p: SlotPacker, region: Dictionary, r_row: float, toning: String) -> void:
	var peak := p._peak()
	if peak < 0:
		return
	var c := p._center(peak)
	var rc := minf(p.free[peak] - p.gap, r_row * 1.6)
	if rc < p.unit * 0.4:
		return
	p._part += 1
	p._place("round", c, 0.0, rc, 0.0)
	var spokes := clampi(int(TAU * (rc + p.gap + r_row * 0.6) / (r_row * 1.2 + p.gap)), 6, 24)
	if spokes % 2 == 1:
		spokes += 1
	var turned := p._spokes(region, spokes)
	spokes = turned[0]
	var a0: float = turned[1]
	var rad := rc + p.gap
	var ring := 0
	var reach: float = Vector2(region["bbox"].size).length()
	while rad < reach and ring < 30:
		# Stones touch their neighbors on the ring: r = R sin(pi / n), so R = r / sin.
		var rr := minf(r_row * 1.3, (rad + r_row) * sin(PI / spokes) - p.gap / 2.0)
		rr = maxf(rr, p.unit * 0.35)
		var at := rad + rr
		p._tone = (ring % 2) if toning == "rows" else p._tone
		p._part += 1
		for j in spokes:
			var a := a0 + TAU * j / spokes + (PI / spokes if ring % 2 == 1 and toning == "rows" else 0.0)
			var q := c + Vector2.from_angle(a) * at
			var rf := minf(rr, p._free_at(q) - p.gap)
			if rf >= rr * 0.6:
				p._place("round", q, 0.0, rf, 0.0)
		rad = at + rr + p.gap
		ring += 1
	p._tone = 0


## Stones of radius r along `curve` (points about a pixel or two apart),
## only along the stretches inside the region where a stone could sit.
static func along_inside(p: SlotPacker, curve: PackedVector2Array, r: float, shape: String) -> void:
	var run := PackedVector2Array()
	for q in curve:
		if p._free_at(q) >= r * 0.6 + p.gap:
			run.append(q)
		else:
			if run.size() > 1:
				p._along(run, false, r, shape)
			run = PackedVector2Array()
	if run.size() > 1:
		p._along(run, false, r, shape)


## A center stone, then `arms` interleaved spiral rows of stones winding out
## from it, rows a stone and a gap apart, `spin` (1 or -1) the way they
## wind. Each arm is a part in its own tone (0, 1, 2...), so the arms read
## apart.
static func spiral(p: SlotPacker, region: Dictionary, r: float, shape: String, arms: int, spin: float) -> void:
	var peak := p._peak()
	if peak < 0:
		return
	var c := p._center(peak)
	var rc := minf(p.free[peak] - p.gap, r * 1.3)
	if rc < p.unit * 0.3:
		return
	p._part += 1
	p._place("round", c, 0.0, rc, 0.0)
	var reach: float = Vector2(region["bbox"].size).length()
	var pitch := arms * (2.0 * r + p.gap)
	var rho0 := rc + p.gap + r
	var a0: float = region["axis"]
	for j in arms:
		p._part += 1
		p._tone = j % 3
		var pts := PackedVector2Array()
		var theta := 0.0
		while pts.size() < 200000:
			var rho := rho0 + pitch * theta / TAU
			if rho > reach:
				break
			pts.append(c + Vector2.from_angle(a0 + TAU * j / arms + spin * theta) * rho)
			theta += 1.5 / rho
		along_inside(p, pts, r, shape)
	p._tone = 0


## Parallel wavy rows (sine waves, or zigzags) across the region along its
## axis turned by `turn`, spaced so neighboring rows keep a gap where they
## run steepest. Rows the same distance from the middle row are one part;
## with `banded`, rows alternate tones.
static func waves(p: SlotPacker, region: Dictionary, r: float, shape: String, turn: float, banded: bool,
		zigzag: bool) -> void:
	var c: Vector2 = region["centroid"]
	var dir := Vector2.from_angle(region["axis"] + turn)
	var nrm := dir.orthogonal()
	var reach := Vector2(region["bbox"].size).length() / 2.0 + 2.0
	var wavelength := r * (8.0 if zigzag else 10.0)
	var amp := r * (1.3 if zigzag else 1.2)
	var slope := (4.0 * amp / wavelength) if zigzag else (TAU * amp / wavelength)
	var pitch := (2.0 * r + p.gap) * sqrt(1.0 + slope * slope)
	var part0 := p._part
	var k := 0
	while k * pitch <= reach + amp and k < 200:
		var ring := k
		p._part = part0 + 1 + ring
		p._tone = (ring % 2) if banded else 0
		for side: float in ([0.0] if k == 0 else [1.0, -1.0]):
			var off := pitch * k * side
			var pts := PackedVector2Array()
			var t := -reach
			while t <= reach:
				var x := t / wavelength
				var y := amp * ((2.0 * absf(2.0 * fposmod(x, 1.0) - 1.0) - 1.0) if zigzag else sin(TAU * x))
				pts.append(c + dir * t + nrm * (off + y))
				t += 1.0
			along_inside(p, pts, r, shape)
		k += 1
	p._part = part0 + 1 + k
	p._tone = 0

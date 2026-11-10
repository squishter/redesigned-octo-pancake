class_name KitGenerator
extends RefCounted
## Turns any picture into a Diamond Kit pattern: a numbered grid of drills
## mapped onto gem colors.
##
## Pipeline: crop to the board aspect -> downscale to the board size ->
## k-means in Lab -> snap to owned gem colors -> clean up isolated cells ->
## assign legend symbols.

const BOARD_SIZES := {
	"small": Vector2i(40, 50),
	"medium": Vector2i(70, 90),
	"large": Vector2i(100, 130),
}

## Legend symbols, most-used color first. Letters and digits only, minus
## look-alikes (O/0, I/1/l), so they render in any font; a symbol font with
## glyphs like ★ ◆ can replace this list later.
const SYMBOLS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789abdefghkmnqrty"

## A drill doesn't look like its gem's own color on the board: the shader
## lights its facets, and the paper and the stones' shadows show between
## drills (a quarter of the cell around a round drill). From a little way off
## the eye mixes them, so kits match pictures against how each gem looks as
## a drill (`seen_color`), measured on the board (KitSeenColors, made by
## tools/calibrate_kit_colors.gd).
##
## Colors that aren't measured gems (a photo's own colors) are predicted in
## two steps: a straight-line fit (in linear light) from the plain gems'
## own colors to their seen colors, then what the fit still misses at the
## SEEN_NEIGHBORS measured gems nearest the color, weighted by nearness
## (about 1.4 Lab units off for round drills, 3 for square, measured by
## leaving each gem out).
const SEEN_NEIGHBORS := 6
## fit_light's share of cells left at either end of the picture's lightness.
const LIGHT_CLIP := 0.01
## fit_light keeps this share of each color's strength (Lab chroma): a
## color lifted lighter with all its strength reads as another color (a
## brown turns orange), so it gives up some, as a pale brown would.
const LIGHT_CHROMA := 0.5
## Lightness counts this many times over in matching a cell to a drill: the
## drills' lightness span is squeezed, so differences in it would otherwise
## lose out to differences in hue and the picture's detail would fade.
const LIGHT_WEIGHT := 2.0
## Steps of compensated_color's search.
const COMPENSATE_STEPS := 12

## Per drill kind: {fit: the straight-line fit (3 rows of 4), flat: the
## plain gems' own colors (Lab), miss: their seen colors less the fit's
## (Lab)}. Built on first use.
static var _seen_model := {}


## Builds a kit pattern dictionary (see KitPattern for the format).
##
## options:
##   size: "small" | "medium" | "large" or a Vector2i(cols, rows)   (default "small")
##   colors: number of palette colors, 12..40 ("detail")            (default 20)
##   gems: Array of {"id", "color": Color} she owns                 (default starter gems)
##   crop: Rect2 in normalized source coords, or null for a centered crop
##   drill: "round" | "square"                                       (default "round")
##   cleanup: re-color isolated cells                                 (default true)
##   seed: int                                                         (default 1)
##   direct: map each cell straight to its nearest gem (no k-means
##           first, so no colors averaged away), for photos     (default false)
##   exact: with direct, the palette is the picture's own `colors` colors
##          (k-means in Lab), not gem colors: entries have no gem id (default false)
##   dither: 0..1, with direct: how much of each cell's leftover color
##           carries on to its neighbors (Floyd-Steinberg in Lab, back and
##           forth), so two gems side by side read as the color between
##           them                                                      (default 0)
##   fit_light: stretch the picture's lightness onto the range the drills
##              can look on the board (fit_light), so dark parts keep their
##              detail instead of all becoming the darkest drill
##                                                                  (default true)
##   light_chroma: with fit_light, the share of each color's strength kept
##                 (0..1)                                  (default LIGHT_CHROMA)
static func generate(source: Image, options: Dictionary = {}) -> Dictionary:
	var size_opt: Variant = options.get("size", "small")
	var board: Vector2i = size_opt if size_opt is Vector2i else BOARD_SIZES.get(size_opt, BOARD_SIZES["small"])
	var n_colors: int = options.get("colors", 20)
	# Pictures map only to colors she owns, so every color she unlocks makes
	# later pictures look better.
	var gems: Array = options.get("gems", Palettes.starter_gems())
	if gems.is_empty():
		gems = Palettes.starter_gems()

	var img := crop_to_aspect(source, float(board.x) / board.y, options.get("crop", null))
	img = downscale(img, board.x, board.y)

	var pixels := PackedColorArray()
	pixels.resize(board.x * board.y)
	for y in board.y:
		for x in board.x:
			pixels[y * board.x + x] = img.get_pixel(x, y)
	var drill: String = options.get("drill", "round")
	if options.get("fit_light", true):
		# The drills she'd use: her gems, or for the picture's own colors any
		# color a drill can be (the measured gems span it).
		var drills := gems
		if options.get("direct", false) and options.get("exact", false):
			drills = measured_gems()
		pixels = fit_light(pixels, light_range(seen_labs(drills, drill)),
				options.get("light_chroma", LIGHT_CHROMA))
	if options.get("direct", false):
		var palette := gems
		if options.get("exact", false):
			palette = own_colors(pixels, n_colors, options.get("seed", 1), drill)
		var direct := map_direct(pixels, board.x, board.y, palette, options.get("dither", 0.0), drill)
		return _build_pattern(direct["cells"], direct["entries"], board, drill)
	var q := ColorQuantizer.quantize(pixels, n_colors, options.get("seed", 1))
	var centers: PackedVector3Array = q["centers"]
	var labels: PackedInt32Array = q["labels"]

	# Palette entries are the snapped gem colors; clusters that land on the
	# same gem merge. Each cluster goes to the gem that looks most like it on
	# the board.
	var entries := []  # {color: Color, gem_id}
	var cluster_to_entry := PackedInt32Array()
	cluster_to_entry.resize(centers.size())
	var gem_lab := _weigh_all(seen_labs(gems, drill))
	var gem_to_entry := {}
	for c in centers.size():
		var gi := LabColor.nearest(_weigh(centers[c]), gem_lab)
		if not gem_to_entry.has(gi):
			gem_to_entry[gi] = entries.size()
			entries.append({"color": gems[gi]["color"], "gem_id": gems[gi]["id"]})
		cluster_to_entry[c] = gem_to_entry[gi]

	var cells := PackedInt32Array()
	cells.resize(labels.size())
	for i in labels.size():
		cells[i] = cluster_to_entry[labels[i]]

	if options.get("cleanup", true):
		for _pass in 2:
			cells = clean_isolated(cells, board.x, board.y)

	return _build_pattern(cells, entries, board, drill)


## The measured seen colors for this drill kind (KitSeenColors), by gem id.
static func seen_table(drill: String) -> Dictionary:
	return KitSeenColors.ROUND if drill == "round" else KitSeenColors.SQUARE


## How a drill of color `gem` (gem id `id`, when it's one) looks on the board
## from a little way off: its measured color when it's a measured gem, else
## predicted from the measured gems nearest it.
static func seen_color(gem: Color, drill: String, id: Variant = null) -> Color:
	var table := seen_table(drill)
	if id != null and table.has(id):
		return table[id]
	return LabColor.to_color(_predict_seen(LabColor.from_color(gem), drill))


## The seen color (Lab) of a drill of Lab color `lab`: the fit's, corrected
## by what the fit misses at its nearest measured gems.
static func _predict_seen(lab: Vector3, drill: String) -> Vector3:
	var model := _model(drill)
	var flat: PackedVector3Array = model["flat"]
	var miss: PackedVector3Array = model["miss"]
	var near := []  # [distance, index], the nearest SEEN_NEIGHBORS
	for i in flat.size():
		var d := lab.distance_to(flat[i])
		if near.size() < SEEN_NEIGHBORS or d < near[-1][0]:
			near.append([d, i])
			near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
			if near.size() > SEEN_NEIGHBORS:
				near.pop_back()
	var sum := Vector3.ZERO
	var weights := 0.0
	for n: Array in near:
		var w := 1.0 / (float(n[0]) + 1.0)
		sum += miss[n[1]] * w
		weights += w
	return LabColor.from_color(_apply_fit(model["fit"], LabColor.to_color(lab))) + sum / weights


static func _model(drill: String) -> Dictionary:
	var kind := "round" if drill == "round" else "square"
	if not _seen_model.has(kind):
		var table := seen_table(kind)
		var ids := []
		for id: String in KitSeenColors.PLAIN:
			if table.has(id):
				ids.append(id)
		var fit := _fit_linear(ids.map(func(id: String) -> Color: return KitSeenColors.PLAIN[id]),
				ids.map(func(id: String) -> Color: return table[id]))
		var flat := PackedVector3Array()
		var miss := PackedVector3Array()
		for id: String in ids:
			var own: Color = KitSeenColors.PLAIN[id]
			flat.append(LabColor.from_color(own))
			miss.append(LabColor.from_color(table[id]) - LabColor.from_color(_apply_fit(fit, own)))
		_seen_model[kind] = {"fit": fit, "flat": flat, "miss": miss}
	return _seen_model[kind]


## Least squares, in linear light: each output channel from (r, g, b, 1).
## Returns 3 rows of 4.
static func _fit_linear(from: Array, to: Array) -> Array:
	var ata := []
	var atb := []
	for i in 4:
		ata.append([0.0, 0.0, 0.0, 0.0])
	for c in 3:
		atb.append([0.0, 0.0, 0.0, 0.0])
	for k in from.size():
		var x := _linear4(from[k])
		var y := _linear4(to[k])
		for i in 4:
			for j in 4:
				ata[i][j] += x[i] * x[j]
			for c in 3:
				atb[c][i] += x[i] * y[c]
	var rows := []
	for c in 3:
		rows.append(_solve4(ata, atb[c]))
	return rows


static func _linear4(c: Color) -> Array:
	var l := c.srgb_to_linear()
	return [l.r, l.g, l.b, 1.0]


static func _apply_fit(fit: Array, c: Color) -> Color:
	var x := _linear4(c)
	var out := [0.0, 0.0, 0.0]
	for ch in 3:
		for i in 4:
			out[ch] += fit[ch][i] * x[i]
	return Color(clampf(out[0], 0.0, 1.0), clampf(out[1], 0.0, 1.0), clampf(out[2], 0.0, 1.0)).linear_to_srgb()


## Solves a 4x4 system (Gaussian elimination with pivoting).
static func _solve4(a_in: Array, b_in: Array) -> Array:
	var a := a_in.duplicate(true)
	var b := b_in.duplicate()
	for i in 4:
		var p := i
		for r in range(i + 1, 4):
			if absf(a[r][i]) > absf(a[p][i]):
				p = r
		var row: Array = a[i]
		a[i] = a[p]
		a[p] = row
		var v: float = b[i]
		b[i] = b[p]
		b[p] = v
		for r in range(i + 1, 4):
			var f: float = a[r][i] / a[i][i]
			for c in range(i, 4):
				a[r][c] -= f * a[i][c]
			b[r] -= f * b[i]
	var x := [0.0, 0.0, 0.0, 0.0]
	for i in range(3, -1, -1):
		var s: float = b[i]
		for c in range(i + 1, 4):
			s -= a[i][c] * x[c]
		x[i] = s / a[i][i]
	return x


## The drill color that looks like `want` on the board (the inverse of
## seen_color), as near as a drill can get: a search that moves the drill's
## color by what its look still misses. Board drills can't look as pale or
## as dark as some colors, so those come as near as the gamut allows.
static func compensated_color(want: Color, drill: String) -> Color:
	var target := LabColor.from_color(want)
	var lab := target
	var best := want
	var best_d := INF
	for _step in COMPENSATE_STEPS:
		var c := LabColor.to_color(lab)
		lab = LabColor.from_color(c)  # back inside the colors a drill can be
		var miss := target - _predict_seen(lab, drill)
		if miss.length() < best_d:
			best_d = miss.length()
			best = c
		lab += miss
	return best


## Drills look far less dark and less bright on the board than their own
## colors (a black round drill, with the paper and its glints, looks a mid
## gray), so a picture can't keep its true lightness: where it is darker
## than any drill looks, every cell would get the darkest drill and its
## detail would be lost. Instead the picture's own lightness span (Lab L,
## from its darkest LIGHT_CLIP of cells to its lightest, so a few specks
## don't waste the range) is stretched evenly onto `range` (light_range),
## keeping its colors' hues and `chroma` of their strength: its lights and
## darks stay in order and use every step of lightness the drills have.
static func fit_light(pixels: PackedColorArray, range: Vector2, chroma: float = LIGHT_CHROMA) -> PackedColorArray:
	var labs := PackedVector3Array()
	labs.resize(pixels.size())
	var ls := PackedFloat32Array()
	ls.resize(pixels.size())
	for i in pixels.size():
		labs[i] = LabColor.from_color(pixels[i])
		ls[i] = labs[i].x
	ls.sort()
	var lo := ls[int((ls.size() - 1) * LIGHT_CLIP)]
	var hi := ls[int((ls.size() - 1) * (1.0 - LIGHT_CLIP))]
	var out := PackedColorArray()
	out.resize(pixels.size())
	for i in pixels.size():
		var t := clampf((labs[i].x - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)
		out[i] = LabColor.to_color(Vector3(lerpf(range.x, range.y, t), labs[i].y * chroma, labs[i].z * chroma))
	return out


## The darkest and lightest (Lab L) of these seen colors.
static func light_range(seen: PackedVector3Array) -> Vector2:
	var lo := INF
	var hi := -INF
	for c in seen:
		lo = minf(lo, c.x)
		hi = maxf(hi, c.x)
	return Vector2(lo, hi)


## The measured plain gems as {id, color}: the colors drills can be.
static func measured_gems() -> Array:
	var out := []
	for id: String in KitSeenColors.PLAIN:
		out.append({"id": id, "color": KitSeenColors.PLAIN[id]})
	return out


## The gems' colors as they look on the board as drills of this kind, in Lab.
static func seen_labs(gems: Array, drill: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	for g in gems:
		out.append(LabColor.from_color(seen_color(g["color"], drill, g.get("id"))))
	return out


## A Lab color with its lightness counted LIGHT_WEIGHT times over.
static func _weigh(lab: Vector3) -> Vector3:
	return Vector3(lab.x * LIGHT_WEIGHT, lab.y, lab.z)


static func _weigh_all(labs: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in labs:
		out.append(_weigh(c))
	return out


## Most a cell's carried-over color may be off (Lab units), so a run of
## colors no gem is near doesn't snowball into streaks.
const MAX_CARRY := 28.0


## Each cell to the gem nearest its color (Lab) as seen on the board (see
## seen_color), with `dither`
## of the leftover color passed on to the cells after it (Floyd-Steinberg,
## rows back and forth). Returns {cells, entries}.
static func map_direct(pixels: PackedColorArray, w: int, h: int, gems: Array, dither: float,
		drill: String = "round") -> Dictionary:
	var gem_lab := _weigh_all(seen_labs(gems, drill))
	var lab := PackedVector3Array()
	lab.resize(pixels.size())
	for i in pixels.size():
		lab[i] = _weigh(LabColor.from_color(pixels[i]))
	var picked := PackedInt32Array()
	picked.resize(pixels.size())
	for y in h:
		var back := y % 2 == 1
		for k in w:
			var x := w - 1 - k if back else k
			var i := y * w + x
			var want := lab[i]
			var gi := LabColor.nearest(want, gem_lab)
			picked[i] = gi
			if dither <= 0.0:
				continue
			var err := want - gem_lab[gi]
			if err.length() > MAX_CARRY:
				err = err.normalized() * MAX_CARRY
			err *= dither
			var ahead := -1 if back else 1
			_carry(lab, w, h, x + ahead, y, err * (7.0 / 16.0))
			_carry(lab, w, h, x - ahead, y + 1, err * (3.0 / 16.0))
			_carry(lab, w, h, x, y + 1, err * (5.0 / 16.0))
			_carry(lab, w, h, x + ahead, y + 1, err * (1.0 / 16.0))
	# Palette entries are the gems used, in the order first used.
	var entries := []
	var entry_of := {}
	var cells := PackedInt32Array()
	cells.resize(pixels.size())
	for i in picked.size():
		var gi := picked[i]
		if not entry_of.has(gi):
			entry_of[gi] = entries.size()
			entries.append({"color": gems[gi]["color"], "gem_id": gems[gi]["id"]})
		cells[i] = entry_of[gi]
	return {"cells": cells, "entries": entries}


static func _carry(lab: PackedVector3Array, w: int, h: int, x: int, y: int, err: Vector3) -> void:
	if x >= 0 and x < w and y < h:
		lab[y * w + x] += err


## The picture's own `n` colors (k-means in Lab), as a palette of
## {id: null, color}. Each color is the drill that looks like it on the
## board (compensated_color), so the finished kit looks like the picture.
static func own_colors(pixels: PackedColorArray, n: int, seed_value: int, drill: String = "round") -> Array:
	var centers: PackedVector3Array = ColorQuantizer.quantize(pixels, n, seed_value)["centers"]
	var out := []
	for c in centers:
		out.append({"id": null, "color": compensated_color(LabColor.to_color(c), drill)})
	return out


## Kit sizes for the game, by the drills on the board's longer side; the
## shorter side follows the picture's shape.
const LONG_SIDES := {"small": 50, "medium": 90, "large": 130, "xlarge": 250}


## A board `long_side` cells along the picture's longer side, the other side
## scaled to its shape.
static func board_long(img: Image, long_side: int) -> Vector2i:
	var iw := float(img.get_width())
	var ih := float(img.get_height())
	if iw >= ih:
		return Vector2i(long_side, maxi(10, int(round(long_side * ih / iw))))
	return Vector2i(maxi(10, int(round(long_side * iw / ih))), long_side)


## A board about `cells` cells big in the photo's own shape, so nothing is
## cropped away.
static func board_for(img: Image, cells: int) -> Vector2i:
	var aspect := float(img.get_width()) / maxf(img.get_height(), 1.0)
	var rows := maxi(10, int(round(sqrt(cells / aspect))))
	return Vector2i(maxi(10, int(round(rows * aspect))), rows)


## Crops to the target aspect (width / height). `crop` is an optional Rect2 in
## normalized coordinates chosen on the crop screen; it is widened or narrowed
## around its center to match the aspect exactly.
static func crop_to_aspect(source: Image, aspect: float, crop: Variant = null) -> Image:
	var w := source.get_width()
	var h := source.get_height()
	var rect := Rect2(0, 0, w, h)
	if crop is Rect2:
		rect = Rect2(crop.position * Vector2(w, h), crop.size * Vector2(w, h))
	var center := rect.get_center()
	var cw := rect.size.x
	var ch := rect.size.y
	if cw / ch > aspect:
		cw = ch * aspect
	else:
		ch = cw / aspect
	var r := Rect2i(int(round(center.x - cw / 2.0)), int(round(center.y - ch / 2.0)), maxi(1, int(cw)), maxi(1, int(ch)))
	r = r.intersection(Rect2i(0, 0, w, h))
	var out := source.get_region(r)
	if out.is_compressed():
		out.decompress()
	out.convert(Image.FORMAT_RGBA8)
	return out


## Area-averaging downscale: halve with a box filter while the image is more
## than twice the target, then finish with a cubic resize. A single resize of
## a big photo to 40 px would alias badly.
static func downscale(img: Image, w: int, h: int) -> Image:
	var out := img.duplicate() as Image
	while out.get_width() >= w * 4 and out.get_height() >= h * 4:
		out.shrink_x2()
	out.resize(w, h, Image.INTERPOLATE_CUBIC)
	return out


## Re-colors cells that share their color with none of their 8 neighbors to
## the most common neighboring color. Returns the cleaned grid.
static func clean_isolated(cells: PackedInt32Array, w: int, h: int) -> PackedInt32Array:
	var src := cells
	var out := cells.duplicate()
	for y in h:
		for x in w:
			var me := src[y * w + x]
			var counts := {}
			var same := false
			for dy in range(-1, 2):
				var ny := y + dy
				if ny < 0 or ny >= h:
					continue
				for dx in range(-1, 2):
					var nx := x + dx
					if (dx == 0 and dy == 0) or nx < 0 or nx >= w:
						continue
					var v := src[ny * w + nx]
					if v == me:
						same = true
						break
					counts[v] = counts.get(v, 0) + 1
				if same:
					break
			if same or counts.is_empty():
				continue
			var best := me
			var best_n := 0
			for v in counts:
				if counts[v] > best_n:
					best_n = counts[v]
					best = v
			out[y * w + x] = best
	return out


## Number of cells that share their color with none of their 8 neighbors.
static func count_isolated(cells: PackedInt32Array, w: int, h: int) -> int:
	var cleaned := clean_isolated(cells, w, h)
	var n := 0
	for i in cells.size():
		if cleaned[i] != cells[i]:
			n += 1
	return n


## Drops unused palette entries, orders the legend by how often each color is
## used and gives every entry a symbol.
static func _build_pattern(cells: PackedInt32Array, entries: Array, board: Vector2i, drill: String) -> Dictionary:
	var counts := PackedInt32Array()
	counts.resize(entries.size())
	for v in cells:
		counts[v] += 1
	var order := []
	for i in entries.size():
		if counts[i] > 0:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return counts[a] > counts[b])
	var remap := PackedInt32Array()
	remap.resize(entries.size())
	var palette := []
	for rank in order.size():
		var i: int = order[rank]
		remap[i] = rank
		palette.append({
			"symbol": SYMBOLS[rank % SYMBOLS.length()],
			"color": entries[i]["color"],
			"gem_color_id": entries[i]["gem_id"],
			"count": counts[i],
		})
	var grid := PackedByteArray()
	grid.resize(cells.size())
	for i in cells.size():
		grid[i] = remap[cells[i]]
	return {
		"version": 1,
		"type": "kit",
		"width": board.x,
		"height": board.y,
		"drill": drill,
		"palette": palette,
		"cells": grid,
	}

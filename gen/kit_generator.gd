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


## Builds a kit pattern dictionary (see KitPattern for the format).
##
## options:
##   size: "small" | "medium" | "large" or a Vector2i(cols, rows)   (default "small")
##   colors: number of palette colors, 12..40 ("detail")            (default 20)
##   gems: Array of {"id", "color": Color} she owns                 (default starter gems)
##   any_color: keep the quantized colors instead of snapping       (default false)
##   crop: Rect2 in normalized source coords, or null for a centered crop
##   drill: "round" | "square"                                       (default "round")
##   cleanup: re-color isolated cells                                 (default true)
##   seed: int                                                         (default 1)
static func generate(source: Image, options: Dictionary = {}) -> Dictionary:
	var size_opt: Variant = options.get("size", "small")
	var board: Vector2i = size_opt if size_opt is Vector2i else BOARD_SIZES.get(size_opt, BOARD_SIZES["small"])
	var n_colors: int = options.get("colors", 20)
	var gems: Array = options.get("gems", Palettes.starter_gems())
	var any_color: bool = options.get("any_color", false)

	var img := crop_to_aspect(source, float(board.x) / board.y, options.get("crop", null))
	img = downscale(img, board.x, board.y)

	var pixels := PackedColorArray()
	pixels.resize(board.x * board.y)
	for y in board.y:
		for x in board.x:
			pixels[y * board.x + x] = img.get_pixel(x, y)
	var q := ColorQuantizer.quantize(pixels, n_colors, options.get("seed", 1))
	var centers: PackedVector3Array = q["centers"]
	var labels: PackedInt32Array = q["labels"]

	# Palette entries: either the snapped gem colors, merging clusters that
	# land on the same gem, or the raw cluster colors.
	var entries := []  # {color: Color, gem_id}
	var cluster_to_entry := PackedInt32Array()
	cluster_to_entry.resize(centers.size())
	if any_color or gems.is_empty():
		for c in centers.size():
			cluster_to_entry[c] = entries.size()
			entries.append({"color": LabColor.to_color(centers[c]), "gem_id": null})
	else:
		var gem_lab := PackedVector3Array()
		for g in gems:
			gem_lab.append(LabColor.from_color(g["color"]))
		var gem_to_entry := {}
		for c in centers.size():
			var gi := LabColor.nearest(centers[c], gem_lab)
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

	return _build_pattern(cells, entries, board, options.get("drill", "round"))


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

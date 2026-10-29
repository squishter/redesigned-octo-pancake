class_name RegionMap
extends RefCounted
## Closed regions of a line-art mask, plus each pixel's distance to the
## nearest edge of its region.
##
## labels: region id per pixel, or LINE (line pixels and tiny regions merged
## into the setting) or BACKGROUND (areas touching the picture's border).

const LINE := -1
const BACKGROUND := -2

var width := 0
var height := 0
var labels := PackedInt32Array()
## Chamfer distance in px from each region pixel to the nearest pixel outside
## its region (0 on lines and background).
var dist := PackedFloat32Array()
## One Dictionary per region:
## {id, area, centroid: Vector2, bbox: Rect2i, elongation, axis, max_dist, peak: Vector2i}
var regions: Array[Dictionary] = []


## min_area: regions smaller than this many px become part of the lines,
## except the one holding the pixel `keep` (say a mandala's center).
static func build(mask: PackedByteArray, w: int, h: int, min_area: int, keep := Vector2i(-1, -1)) -> RegionMap:
	var map := RegionMap.new()
	map.width = w
	map.height = h
	map._label(mask, min_area, keep)
	map._distance()
	return map


func _label(mask: PackedByteArray, min_area: int, keep: Vector2i) -> void:
	var w := width
	var h := height
	var kept := keep.y * w + keep.x if Rect2i(0, 0, w, h).has_point(keep) else -1
	var raw := PackedInt32Array()
	raw.resize(w * h)
	raw.fill(-1)
	var stack := PackedInt32Array()
	stack.resize(w * h)
	var raw_info := []
	for start in w * h:
		if mask[start] or raw[start] != -1:
			continue
		var rid := raw_info.size()
		raw[start] = rid
		var top := 0
		stack[top] = start
		top += 1
		var area := 0
		var sx := 0.0
		var sy := 0.0
		var sxx := 0.0
		var syy := 0.0
		var sxy := 0.0
		var border := false
		var held := false
		var x0 := w
		var y0 := h
		var x1 := 0
		var y1 := 0
		while top > 0:
			top -= 1
			var i := stack[top]
			var y := i / w
			var x := i - y * w
			area += 1
			held = held or i == kept
			sx += x
			sy += y
			sxx += x * x
			syy += y * y
			sxy += x * y
			x0 = mini(x0, x)
			x1 = maxi(x1, x)
			y0 = mini(y0, y)
			y1 = maxi(y1, y)
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				border = true
			if x > 0 and not mask[i - 1] and raw[i - 1] == -1:
				raw[i - 1] = rid
				stack[top] = i - 1
				top += 1
			if x < w - 1 and not mask[i + 1] and raw[i + 1] == -1:
				raw[i + 1] = rid
				stack[top] = i + 1
				top += 1
			if y > 0 and not mask[i - w] and raw[i - w] == -1:
				raw[i - w] = rid
				stack[top] = i - w
				top += 1
			if y < h - 1 and not mask[i + w] and raw[i + w] == -1:
				raw[i + w] = rid
				stack[top] = i + w
				top += 1
		var cx := sx / area
		var cy := sy / area
		# Principal axis from second moments: elongation 1 = round, larger = longer.
		var a := sxx / area - cx * cx
		var b := sxy / area - cx * cy
		var c := syy / area - cy * cy
		var tr := (a + c) / 2.0
		var det := sqrt(maxf(0.0, (a - c) * (a - c) / 4.0 + b * b))
		var l1 := tr + det
		var l2 := maxf(1e-6, tr - det)
		raw_info.append({
			"area": area,
			"border": border,
			"held": held,
			"centroid": Vector2(cx + 0.5, cy + 0.5),
			"bbox": Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1),
			"elongation": sqrt(l1 / l2),
			"axis": 0.5 * atan2(2.0 * b, a - c),
		})

	# Keep closed regions that are big enough, numbered 0..n-1.
	var remap := PackedInt32Array()
	remap.resize(raw_info.size())
	for r in raw_info.size():
		var info: Dictionary = raw_info[r]
		if info["border"]:
			remap[r] = BACKGROUND
		elif info["area"] < min_area and not info["held"]:
			remap[r] = LINE
		else:
			remap[r] = regions.size()
			info.erase("border")
			info.erase("held")
			info["id"] = regions.size()
			regions.append(info)
	labels.resize(w * h)
	for i in w * h:
		labels[i] = LINE if raw[i] < 0 else remap[raw[i]]


## Two-pass 3-4 chamfer distance, where anything with a different label
## (including the image edge) counts as outside.
func _distance() -> void:
	var w := width
	var h := height
	const BIG := 1 << 28
	var d := PackedInt32Array()
	d.resize(w * h)
	for i in w * h:
		d[i] = BIG if labels[i] >= 0 else 0
	for y in h:
		for x in w:
			var i := y * w + x
			if d[i] == 0:
				continue
			var l := labels[i]
			var best := d[i]
			var v: int
			v = (d[i - 1] if labels[i - 1] == l else 0) + 3 if x > 0 else 3
			best = mini(best, v)
			if y > 0:
				v = (d[i - w] if labels[i - w] == l else 0) + 3
				best = mini(best, v)
				v = (d[i - w - 1] if labels[i - w - 1] == l else 0) + 4 if x > 0 else 4
				best = mini(best, v)
				v = (d[i - w + 1] if labels[i - w + 1] == l else 0) + 4 if x < w - 1 else 4
				best = mini(best, v)
			else:
				best = mini(best, 3)
			d[i] = best
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			if d[i] == 0:
				continue
			var l := labels[i]
			var best := d[i]
			var v: int
			v = (d[i + 1] if labels[i + 1] == l else 0) + 3 if x < w - 1 else 3
			best = mini(best, v)
			if y < h - 1:
				v = (d[i + w] if labels[i + w] == l else 0) + 3
				best = mini(best, v)
				v = (d[i + w + 1] if labels[i + w + 1] == l else 0) + 4 if x < w - 1 else 4
				best = mini(best, v)
				v = (d[i + w - 1] if labels[i + w - 1] == l else 0) + 4 if x > 0 else 4
				best = mini(best, v)
			else:
				best = mini(best, 3)
			d[i] = best

	dist.resize(w * h)
	for r in regions:
		r["max_dist"] = 0.0
		r["peak"] = Vector2i(r["centroid"])
	for i in w * h:
		var v := d[i] / 3.0
		dist[i] = v
		var l := labels[i]
		if l >= 0 and v > regions[l]["max_dist"]:
			regions[l]["max_dist"] = v
			regions[l]["peak"] = Vector2i(i % w, i / w)


func label_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return BACKGROUND
	return labels[y * width + x]


## Distance-field gradient direction at a pixel (points away from the
## nearest edge), or NAN where the field is flat.
func gradient_angle(x: int, y: int) -> float:
	var xl := clampi(x - 1, 0, width - 1)
	var xr := clampi(x + 1, 0, width - 1)
	var yu := clampi(y - 1, 0, height - 1)
	var yd := clampi(y + 1, 0, height - 1)
	var gx := dist[y * width + xr] - dist[y * width + xl]
	var gy := dist[yd * width + x] - dist[yu * width + x]
	if absf(gx) + absf(gy) < 1e-6:
		return NAN
	return atan2(gy, gx)


## For every LINE pixel, the label (region id or BACKGROUND) of the nearest
## non-line pixel, found by a breadth-first walk through the lines; the image
## edge counts as BACKGROUND. Other pixels get their own label.
func line_owners() -> PackedInt32Array:
	var w := width
	var h := height
	var owners := labels.duplicate()
	var queue := PackedInt32Array()
	queue.resize(w * h)
	var tail := 0
	for i in w * h:
		if labels[i] != LINE:
			continue
		var y := i / w
		var x := i - y * w
		var o := LINE
		if x == 0 or y == 0 or x == w - 1 or y == h - 1:
			o = BACKGROUND
		elif labels[i - 1] != LINE:
			o = labels[i - 1]
		elif labels[i + 1] != LINE:
			o = labels[i + 1]
		elif labels[i - w] != LINE:
			o = labels[i - w]
		elif labels[i + w] != LINE:
			o = labels[i + w]
		if o != LINE:
			owners[i] = o
			queue[tail] = i
			tail += 1
	var head := 0
	while head < tail:
		var i := queue[head]
		head += 1
		var y := i / w
		var x := i - y * w
		for j in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w if y > 0 else -1, i + w if y < h - 1 else -1]:
			if j >= 0 and owners[j] == LINE:
				owners[j] = owners[i]
				queue[tail] = j
				tail += 1
	return owners


## Line mask view of the labels (255 on lines, 0 elsewhere): tiny regions
## merged into the lines show up as part of the setting.
func line_mask() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(width * height)
	for i in width * height:
		if labels[i] == LINE:
			out[i] = 255
	return out

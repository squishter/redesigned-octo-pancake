class_name PhotoEdges
extends RefCounted
## Photo -> line art by finding its edges, for photo collages; the result is
## then used like any other line art (CollageGenerator).
##
## 1. Edges: an edge-preserving smoothing (Kuwahara: each pixel takes the
##    calmest of the four squares around it, so fur, grass and cloth flatten
##    while outlines stay sharp), then a color edge detector (Di Zenzo gradients
##    over Lab, so edges between colors of the same brightness count too),
##    thinned to the ridge (non-maximum suppression) and kept where strong,
##    or weak but joined to strong (hysteresis, thresholds set from the
##    photo's own spread of gradients, never below a floor, so smooth
##    gradients don't sprout edges). Short specks are dropped.
## 2. Closing: each loose end reaches on along its direction a little way,
##    joining the edge it meets, so shapes close into regions.
## 3. Subject: each region between the lines gets a background weight from
##    its "boundary connectivity" (Zhu et al. 2014, "Saliency optimization
##    from robust background detection"): how much of the regions that look
##    like it (near it through similar colors) run along the photo's border,
##    against how big they are. Sky, ground and walls connect to the border;
##    a subject, even one running off one edge, hardly does. A region stands
##    out by how unlike the background regions near it it is. If a compact, clearly different subject stands out (not a
##    landscape), only it becomes line art: its edges and its outline,
##    cropped around it. The rest touches the picture's edge, so it stays
##    background without gems. Otherwise the whole photo is used, framed.

## Working size: the photo's longest side, in px.
const MAX_SIZE := 640
## Lines are drawn this many px either side of an edge.
const LINE_RADIUS := 2
## A loose end reaches on up to this share of the longest side.
const REACH := 0.035
## Edges shorter than this share of the longest side are dropped (fewer at
## more detail).
const MIN_EDGE := [0.08, 0.03]
## Share of pixels counted as strong edges (more at more detail).
const STRONG_SHARE := [0.02, 0.07]
const WEAK_RATIO := 0.45
## Strong edges are at least this strong (Sobel over Lab), whatever the photo.
const STRONG_FLOOR := 30.0
## Kuwahara square size, px (smaller at more detail).
const SMOOTH := [5, 3]
## A region running along more than this share of the border is background.
const BORDER_SHARE := 0.15
## A subject: this share of the photo at least and at most, standing out at
## least this many times as much as the rest, at most this background-ish
## on average; the crop keeps this much room around it.
const SUBJECT_AREA := [0.05, 0.7]
const SUBJECT_CONTRAST := 6.0
const SUBJECT_MAX_BG := 0.4
const SUBJECT_MARGIN := 0.06
## Boundary connectivity's color and space scales (Lab units, share of the
## diagonal) and how quickly it makes a region background.
const SIGMA_COLOR := 10.0
const SIGMA_SPACE := 0.25
const SIGMA_BOUNDARY := 1.0
## Regions smaller than this share of the photo are left out of the subject
## search (they'd only slow it: it compares every region with every other).
const MIN_REGION := 0.0008


## options: detail 0..1 (default 0.5), subject: "auto" | "on" | "off"
## (default "auto": only a clear subject). Returns {mask, width, height,
## image (the working photo, cropped like the mask), subject: bool,
## subject_rect (in the uncropped working photo)}.
static func line_art(photo: Image, options: Dictionary = {}) -> Dictionary:
	var detail: float = clampf(options.get("detail", 0.5), 0.0, 1.0)
	var img := photo.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var s := float(MAX_SIZE) / maxi(img.get_width(), img.get_height())
	if s < 1.0:
		img = KitGenerator.downscale(img, maxi(1, int(img.get_width() * s)), maxi(1, int(img.get_height() * s)))
	var w := img.get_width()
	var h := img.get_height()
	var lab := _kuwahara(_lab(img, 1), w, h, int(round(lerpf(SMOOTH[0], SMOOTH[1], detail))))
	var edges := _edges(lab, w, h, detail)
	_close_gaps(edges, w, h, int(maxi(w, h) * REACH))
	var lines := LineRaster.dilate(edges, w, h, LINE_RADIUS)

	var want: String = options.get("subject", "auto")
	var subject := {} if want == "off" else _subject(lines, lab, w, h, want == "on")
	if not subject.has("mask"):
		return {"mask": LineRaster.add_frame(lines, w, h, 3), "width": w, "height": h, "image": img,
				"subject": false, "subject_rect": Rect2i(0, 0, w, h), "scores": subject}
	# Only the subject: its own edges, its outline, cropped around it.
	var inside: PackedByteArray = subject["mask"]
	var near_inside := LineRaster.dilate(inside, w, h, 1)
	var mask := PackedByteArray()
	mask.resize(w * h)
	for i in w * h:
		if (lines[i] != 0 and near_inside[i] != 0) or _outline(inside, w, h, i):
			mask[i] = 255
	mask = LineRaster.dilate(mask, w, h, 1)
	var rect: Rect2i = subject["rect"]
	var room := int(maxi(rect.size.x, rect.size.y) * SUBJECT_MARGIN) + 6
	var crop := rect.grow(room).intersection(Rect2i(0, 0, w, h))
	var cropped := PackedByteArray()
	cropped.resize(crop.size.x * crop.size.y)
	for y in crop.size.y:
		for x in crop.size.x:
			cropped[y * crop.size.x + x] = mask[(crop.position.y + y) * w + crop.position.x + x]
	subject.erase("mask")
	return {"mask": cropped, "width": crop.size.x, "height": crop.size.y, "image": img.get_region(crop),
			"subject": true, "subject_rect": rect, "scores": subject}


## The photo in Lab, lightly blurred first (box blur twice, radius `blur`).
static func _lab(img: Image, blur: int) -> PackedVector3Array:
	var w := img.get_width()
	var h := img.get_height()
	var px := PackedColorArray()
	px.resize(w * h)
	for y in h:
		for x in w:
			px[y * w + x] = img.get_pixel(x, y)
	px = PhotoLineArt.box_blur(PhotoLineArt.box_blur(px, w, h, blur), w, h, blur)
	var out := PackedVector3Array()
	out.resize(w * h)
	for i in px.size():
		out[i] = LabColor.from_color(px[i])
	return out


## Edge-preserving smoothing: each pixel becomes the mean of whichever of the
## four r x r squares meeting at it is calmest (least varied in lightness).
static func _kuwahara(lab: PackedVector3Array, w: int, h: int, r: int) -> PackedVector3Array:
	var sw := w + 1
	var sl := PackedFloat64Array()
	var sa := PackedFloat64Array()
	var sb := PackedFloat64Array()
	var sll := PackedFloat64Array()
	for arr in [sl, sa, sb, sll]:
		arr.resize(sw * (h + 1))
	for y in h:
		var rl := 0.0
		var ra := 0.0
		var rb := 0.0
		var rll := 0.0
		for x in w:
			var c := lab[y * w + x]
			rl += c.x
			ra += c.y
			rb += c.z
			rll += c.x * c.x
			var i := (y + 1) * sw + x + 1
			sl[i] = sl[i - sw] + rl
			sa[i] = sa[i - sw] + ra
			sb[i] = sb[i - sw] + rb
			sll[i] = sll[i - sw] + rll
	var out := PackedVector3Array()
	out.resize(w * h)
	for y in h:
		for x in w:
			var best_var := INF
			var best := lab[y * w + x]
			for q in 4:
				var x0 := x - r if q % 2 == 0 else x
				var y0 := y - r if q < 2 else y
				x0 = maxi(x0, 0)
				y0 = maxi(y0, 0)
				var x1 := mini(x0 + r, w - 1) + 1
				var y1 := mini(y0 + r, h - 1) + 1
				var n := float((x1 - x0) * (y1 - y0))
				var a := y0 * sw + x0
				var b := y0 * sw + x1
				var c := y1 * sw + x0
				var d := y1 * sw + x1
				var ml := (sl[d] - sl[b] - sl[c] + sl[a]) / n
				var v := (sll[d] - sll[b] - sll[c] + sll[a]) / n - ml * ml
				if v < best_var:
					best_var = v
					best = Vector3(ml, (sa[d] - sa[b] - sa[c] + sa[a]) / n, (sb[d] - sb[b] - sb[c] + sb[a]) / n)
			out[y * w + x] = best
	return out


## Thin, connected edges (255) of a Lab image.
static func _edges(lab: PackedVector3Array, w: int, h: int, detail: float) -> PackedByteArray:
	var mag := PackedFloat32Array()
	mag.resize(w * h)
	var dir := PackedByteArray()  # 0: across x, 1: diagonal \, 2: across y, 3: diagonal /
	dir.resize(w * h)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			# Sobel per channel, combined as a color tensor (Di Zenzo).
			var gx := (lab[i - w + 1] + 2.0 * lab[i + 1] + lab[i + w + 1]) - (lab[i - w - 1] + 2.0 * lab[i - 1] + lab[i + w - 1])
			var gy := (lab[i + w - 1] + 2.0 * lab[i + w] + lab[i + w + 1]) - (lab[i - w - 1] + 2.0 * lab[i - w] + lab[i - w + 1])
			var gxx := gx.dot(gx)
			var gyy := gy.dot(gy)
			var gxy := gx.dot(gy)
			var root := sqrt((gxx - gyy) * (gxx - gyy) + 4.0 * gxy * gxy)
			mag[i] = sqrt(maxf(0.5 * (gxx + gyy + root), 0.0))
			var theta := 0.5 * atan2(2.0 * gxy, gxx - gyy)
			dir[i] = int(round(fposmod(theta, PI) / (PI / 4.0))) % 4
	# Keep only ridge pixels: at least as strong as both neighbors across.
	var steps := [1, w + 1, w, w - 1]
	var thin := PackedFloat32Array()
	thin.resize(w * h)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			var d: int = steps[dir[i]]
			if mag[i] > 0.0 and mag[i] >= mag[i + d] and mag[i] >= mag[i - d]:
				thin[i] = mag[i]
	# Thresholds from the photo itself: the strongest share of ridge pixels.
	var ridge := Array(thin).filter(func(v: float) -> bool: return v > 0.0)
	if ridge.is_empty():
		return _zeros(w * h)
	ridge.sort()
	var share := lerpf(STRONG_SHARE[0], STRONG_SHARE[1], detail) * (w * h) / ridge.size()
	var high: float = ridge[clampi(int(ridge.size() * (1.0 - clampf(share, 0.02, 0.6))), 0, ridge.size() - 1)]
	high = maxf(high, STRONG_FLOOR)
	var low := high * WEAK_RATIO
	var out := _zeros(w * h)
	var stack := PackedInt32Array()
	for i in w * h:
		if thin[i] >= high and out[i] == 0:
			out[i] = 255
			stack.append(i)
			while not stack.is_empty():
				var j := stack[stack.size() - 1]
				stack.resize(stack.size() - 1)
				for d: int in [-w - 1, -w, -w + 1, -1, 1, w - 1, w, w + 1]:
					var k := j + d
					if k >= 0 and k < w * h and out[k] == 0 and thin[k] >= low:
						out[k] = 255
						stack.append(k)
	_drop_short(out, w, h, int(maxi(w, h) * lerpf(MIN_EDGE[0], MIN_EDGE[1], detail)))
	return out


static func _zeros(n: int) -> PackedByteArray:
	var z := PackedByteArray()
	z.resize(n)
	return z


## Clears connected edges (8-way) of fewer than `min_px` pixels.
static func _drop_short(edges: PackedByteArray, w: int, h: int, min_px: int) -> void:
	var seen := _zeros(w * h)
	var stack := PackedInt32Array()
	var members := PackedInt32Array()
	for start in w * h:
		if edges[start] == 0 or seen[start] != 0:
			continue
		seen[start] = 1
		stack.append(start)
		members.clear()
		while not stack.is_empty():
			var j := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			members.append(j)
			var y := j / w
			var x := j - y * w
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var xx := x + dx
					var yy := y + dy
					if xx < 0 or yy < 0 or xx >= w or yy >= h:
						continue
					var k := yy * w + xx
					if edges[k] != 0 and seen[k] == 0:
						seen[k] = 1
						stack.append(k)
		if members.size() < min_px:
			for j in members:
				edges[j] = 0


## Loose ends (an edge pixel with one neighbor) reach on along their own
## direction up to `reach` px; when they meet another edge they join it.
static func _close_gaps(edges: PackedByteArray, w: int, h: int, reach: int) -> void:
	var ends := []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			if edges[i] != 0 and _count_neighbors(edges, w, i) == 1:
				ends.append(i)
	for e: int in ends:
		# Walk back along the edge a few px to find which way it was going.
		var trail := [e]
		var at := e
		for _k in 6:
			var next := -1
			for d: int in [-w - 1, -w, -w + 1, -1, 1, w - 1, w, w + 1]:
				var k := at + d
				if k >= 0 and k < w * h and edges[k] != 0 and not k in trail:
					next = k
					break
			if next < 0:
				break
			trail.append(next)
			at = next
		if trail.size() < 3:
			continue
		var p := Vector2(e % w, e / w)
		var back := Vector2(at % w, at / w)
		var way := (p - back).normalized()
		for step in range(2, reach + 1):
			var q := (p + way * step).round()
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
				break
			var k := int(q.y) * w + int(q.x)
			if edges[k] != 0 and not k in trail:
				_draw_line(edges, w, p, q)
				break


static func _count_neighbors(edges: PackedByteArray, w: int, i: int) -> int:
	var n := 0
	for d: int in [-w - 1, -w, -w + 1, -1, 1, w - 1, w, w + 1]:
		if edges[i + d] != 0:
			n += 1
	return n


static func _draw_line(edges: PackedByteArray, w: int, a: Vector2, b: Vector2) -> void:
	var n := int(ceil(a.distance_to(b)))
	for k in n + 1:
		var q := a.lerp(b, float(k) / maxi(n, 1)).round()
		edges[int(q.y) * w + int(q.x)] = 255


## True if pixel i of `inside` (a subject mask) is on its outline.
static func _outline(inside: PackedByteArray, w: int, h: int, i: int) -> bool:
	if inside[i] == 0:
		return false
	var y := i / w
	var x := i - y * w
	if x == 0 or y == 0 or x == w - 1 or y == h - 1:
		return true
	return inside[i - 1] == 0 or inside[i + 1] == 0 or inside[i - w] == 0 or inside[i + w] == 0


## The photo's subject, if it has a clear one: {mask (255 inside), rect,
## share, contrast, background}, else the same scores without a mask.
## `force` takes the best candidate even if it isn't clear.
static func _subject(lines: PackedByteArray, lab: PackedVector3Array, w: int, h: int, force: bool) -> Dictionary:
	var regions := _components(lines, w, h, int(w * h * MIN_REGION))
	var label: PackedInt32Array = regions["labels"]
	var n: int = regions["count"]
	if n == 0:
		return {}
	# Each region's size, mean color, center and length along the border.
	var area := PackedFloat32Array()
	area.resize(n)
	var mean := PackedVector3Array()
	mean.resize(n)
	var center := PackedVector2Array()
	center.resize(n)
	var edge := PackedFloat32Array()
	edge.resize(n)
	for y in h:
		for x in w:
			var r := label[y * w + x]
			if r < 0:
				continue
			area[r] += 1.0
			mean[r] += lab[y * w + x]
			center[r] += Vector2(x, y)
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				edge[r] += 1.0
	for r in n:
		mean[r] /= maxf(area[r], 1.0)
		center[r] /= maxf(area[r], 1.0)
	# Neighbors: regions meeting across a line.
	var reach := LINE_RADIUS + 2
	var links := {}
	for y in range(reach, h - reach):
		for x in range(reach, w - reach):
			var i := y * w + x
			if lines[i] == 0:
				continue
			for d: int in [reach, w * reach]:
				var a := label[i - d]
				var b := label[i + d]
				if a >= 0 and b >= 0 and a != b:
					links[mini(a, b) * n + maxi(a, b)] = true
	var near: Array[PackedInt32Array] = []
	near.resize(n)
	for key: int in links:
		near[key / n].append(key % n)
		near[key % n].append(key / n)
	# Boundary connectivity: from each region, how far (through color
	# changes) every other is; similar ones count toward its spread.
	var diag := Vector2(w, h).length()
	var bg := PackedFloat32Array()
	bg.resize(n)
	var geo: Array[PackedFloat32Array] = []
	for p in n:
		var dist := _geodesic(p, near, mean)
		geo.append(dist)
		var spread := 0.0
		var along := 0.0
		for q in n:
			var sim := exp(-dist[q] * dist[q] / (2.0 * SIGMA_COLOR * SIGMA_COLOR))
			spread += sim * area[q]
			along += sim * edge[q]
		var con := along / sqrt(maxf(spread, 1.0))
		bg[p] = 1.0 - exp(-con * con / (2.0 * SIGMA_BOUNDARY * SIGMA_BOUNDARY))
	# Standing out: unlike the background regions near it.
	var sal := PackedFloat32Array()
	sal.resize(n)
	for p in n:
		var ctr := 0.0
		for q in n:
			var sp := center[p].distance_to(center[q]) / diag
			ctr += mean[p].distance_to(mean[q]) * exp(-sp * sp / (2.0 * SIGMA_SPACE * SIGMA_SPACE)) * bg[q]
		sal[p] = ctr * (1.0 - bg[p])
	var total := 0.0
	var weighted := 0.0
	for r in n:
		total += area[r]
		weighted += sal[r] * area[r]
	var cut := weighted / maxf(total, 1.0)
	var cand := _zeros(w * h)
	var any := false
	for i in w * h:
		var r := label[i]
		if r >= 0 and sal[r] > cut and bg[r] < 0.5:
			cand[i] = 255
			any = true
	if not any:
		return {}
	# Join pieces split by lines, keep the biggest blob, fill its holes.
	var joined := LineRaster.dilate(cand, w, h, LINE_RADIUS + 3)
	var filled := _fill_holes(_biggest_blob(joined, w, h), w, h)
	var inside := 0.0
	var lo := Vector2i(w, h)
	var hi := Vector2i(-1, -1)
	var sal_in := 0.0
	var bg_in := 0.0
	var sal_out := 0.0
	var out_n := 0.0
	for y in h:
		for x in w:
			var i := y * w + x
			var r := label[i]
			if filled[i] != 0:
				inside += 1.0
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
				if r >= 0:
					sal_in += sal[r]
					bg_in += bg[r]
			elif r >= 0:
				sal_out += sal[r]
				out_n += 1.0
	var rect := Rect2i(lo, hi - lo + Vector2i.ONE) if inside > 0.0 else Rect2i()
	var share := inside / (w * h)
	var contrast := (sal_in / maxf(inside, 1.0)) / maxf(sal_out / maxf(out_n, 1.0), 0.01)
	var background := bg_in / maxf(inside, 1.0)
	# A band from edge to edge (a horizon, a row of hills) is scenery, not a subject.
	var fills_frame := ((rect.position.x <= 2 and rect.end.x >= w - 2) or (rect.position.y <= 2 and rect.end.y >= h - 2))
	var clear := (share >= SUBJECT_AREA[0] and share <= SUBJECT_AREA[1] and contrast >= SUBJECT_CONTRAST
			and background <= SUBJECT_MAX_BG and not fills_frame)
	var scores := {"share": snappedf(share, 0.01), "contrast": snappedf(contrast, 0.01),
			"background": snappedf(background, 0.01), "rect": rect}
	if not clear and not (force and inside > 0.0):
		return scores
	scores["mask"] = filled
	return scores


## Shortest color distance (sum of mean-color steps between neighbors) from
## region `from` to every region; INF where unreachable.
static func _geodesic(from: int, near: Array[PackedInt32Array], mean: PackedVector3Array) -> PackedFloat32Array:
	var n := mean.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	dist[from] = 0.0
	var done := PackedByteArray()
	done.resize(n)
	for _k in n:
		var u := -1
		var best := INF
		for v in n:
			if done[v] == 0 and dist[v] < best:
				best = dist[v]
				u = v
		if u < 0:
			break
		done[u] = 1
		for v in near[u]:
			var d := best + mean[u].distance_to(mean[v])
			if d < dist[v]:
				dist[v] = d
	return dist


## 4-connected regions of the pixels off the lines, at least `min_area` px:
## {labels (-1 on lines and smaller regions), count}.
static func _components(lines: PackedByteArray, w: int, h: int, min_area := 0) -> Dictionary:
	var label := PackedInt32Array()
	label.resize(w * h)
	label.fill(-1)
	var stack := PackedInt32Array()
	var members := PackedInt32Array()
	var count := 0
	for start in w * h:
		if lines[start] != 0 or label[start] != -1:
			continue
		label[start] = count
		stack.append(start)
		members.clear()
		while not stack.is_empty():
			var j := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			members.append(j)
			var y := j / w
			var x := j - y * w
			for k: int in [j - 1 if x > 0 else -1, j + 1 if x < w - 1 else -1, j - w if y > 0 else -1,
					j + w if y < h - 1 else -1]:
				if k >= 0 and lines[k] == 0 and label[k] == -1:
					label[k] = count
					stack.append(k)
		if members.size() < min_area:
			for j in members:
				label[j] = -2  # seen, too small
		else:
			count += 1
	for i in w * h:
		if label[i] == -2:
			label[i] = -1
	return {"labels": label, "count": count}


## The largest 4-connected blob of a mask.
static func _biggest_blob(mask: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var comp := PackedInt32Array()
	comp.resize(w * h)
	comp.fill(-1)
	var best := -1
	var best_n := 0
	var stack := PackedInt32Array()
	var id := 0
	for start in w * h:
		if mask[start] == 0 or comp[start] >= 0:
			continue
		var n := 0
		comp[start] = id
		stack.append(start)
		while not stack.is_empty():
			var j := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			n += 1
			var y := j / w
			var x := j - y * w
			for k: int in [j - 1 if x > 0 else -1, j + 1 if x < w - 1 else -1, j - w if y > 0 else -1,
					j + w if y < h - 1 else -1]:
				if k >= 0 and mask[k] != 0 and comp[k] < 0:
					comp[k] = id
					stack.append(k)
		if n > best_n:
			best_n = n
			best = id
		id += 1
	var out := _zeros(w * h)
	for i in w * h:
		if comp[i] == best and best >= 0:
			out[i] = 255
	return out


## Fills the holes of a blob: everything not reachable from the border.
static func _fill_holes(blob: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var outside := _zeros(w * h)
	var stack := PackedInt32Array()
	for y in h:
		for x in w:
			if (x == 0 or y == 0 or x == w - 1 or y == h - 1) and blob[y * w + x] == 0:
				outside[y * w + x] = 1
				stack.append(y * w + x)
	while not stack.is_empty():
		var j := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var y := j / w
		var x := j - y * w
		for k: int in [j - 1 if x > 0 else -1, j + 1 if x < w - 1 else -1, j - w if y > 0 else -1,
				j + w if y < h - 1 else -1]:
			if k >= 0 and blob[k] == 0 and outside[k] == 0:
				outside[k] = 1
				stack.append(k)
	var out := _zeros(w * h)
	for i in w * h:
		if outside[i] == 0:
			out[i] = 255
	return out

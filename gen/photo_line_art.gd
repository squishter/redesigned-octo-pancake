class_name PhotoLineArt
extends RefCounted
## Turns a photo into closed line art for Collage mode.
##
## Blur, quantize to a few colors, smooth the color areas and merge the tiny
## ones, then draw lines where color areas meet. Unlike edge detection this
## always gives closed shapes.


## options:
##   detail: 0..1, the "simpler / more detail" slider (default 0.5)
##   max_size: longest side of the working image in px (default 512)
##   seed: int (default 1)
## Returns {"mask", "width", "height", "image"}: the line mask and the
## working-size photo, for sampling region colors.
static func generate(photo: Image, options: Dictionary = {}) -> Dictionary:
	var detail: float = clampf(options.get("detail", 0.5), 0.0, 1.0)
	var max_size: int = options.get("max_size", 512)
	var img := photo.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var s := float(max_size) / maxi(img.get_width(), img.get_height())
	if s < 1.0:
		img = KitGenerator.downscale(img, maxi(1, int(img.get_width() * s)), maxi(1, int(img.get_height() * s)))
	var w := img.get_width()
	var h := img.get_height()

	var pixels := PackedColorArray()
	pixels.resize(w * h)
	for y in h:
		for x in w:
			pixels[y * w + x] = img.get_pixel(x, y)
	var blur_radius := int(round(lerpf(3.0, 1.0, detail)))
	pixels = box_blur(box_blur(pixels, w, h, blur_radius), w, h, blur_radius)

	var k := int(round(lerpf(6.0, 10.0, detail)))
	var labels: PackedInt32Array = ColorQuantizer.quantize(pixels, k, options.get("seed", 1))["labels"]
	for _pass in 2:
		labels = mode_filter(labels, w, h)
	var min_area := int(w * h * lerpf(0.004, 0.0008, detail))
	for _pass in 3:
		var merged := merge_small_areas(labels, w, h, min_area)
		if merged == labels:
			break
		labels = merged

	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			var i := y * w + x
			if (x < w - 1 and labels[i + 1] != labels[i]) or (y < h - 1 and labels[i + w] != labels[i]):
				mask[i] = 255
	mask = LineRaster.add_frame(LineRaster.dilate(mask, w, h, 1), w, h, 2)
	return {"mask": mask, "width": w, "height": h, "image": img}


## Separable box blur.
static func box_blur(src: PackedColorArray, w: int, h: int, radius: int) -> PackedColorArray:
	if radius <= 0:
		return src
	var tmp := PackedColorArray()
	tmp.resize(w * h)
	for y in h:
		for x in w:
			var sum := Color(0, 0, 0, 0)
			var n := 0
			for xx in range(maxi(0, x - radius), mini(w, x + radius + 1)):
				sum += src[y * w + xx]
				n += 1
			tmp[y * w + x] = sum / n
	var out := PackedColorArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			var sum := Color(0, 0, 0, 0)
			var n := 0
			for yy in range(maxi(0, y - radius), mini(h, y + radius + 1)):
				sum += tmp[yy * w + x]
				n += 1
			out[y * w + x] = sum / n
	return out


## 3x3 majority filter: smooths ragged borders between color areas.
## Labels must be small non-negative ints (quantizer output).
static func mode_filter(labels: PackedInt32Array, w: int, h: int) -> PackedInt32Array:
	var out := labels.duplicate()
	var n_labels := 0
	for v in labels:
		n_labels = maxi(n_labels, v + 1)
	var counts := PackedInt32Array()
	counts.resize(n_labels)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var best := labels[y * w + x]
			var best_n := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var v := labels[(y + dy) * w + x + dx]
					counts[v] += 1
					if counts[v] > best_n:
						best_n = counts[v]
						best = v
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					counts[labels[(y + dy) * w + x + dx]] = 0
			if best_n >= 5:
				out[y * w + x] = best
	return out


## Re-colors connected areas smaller than min_area to the color they share
## the longest border with. Returns the new labels.
static func merge_small_areas(source: PackedInt32Array, w: int, h: int, min_area: int) -> PackedInt32Array:
	var labels := source.duplicate()
	var comp := PackedInt32Array()
	comp.resize(w * h)
	comp.fill(-1)
	var stack := PackedInt32Array()
	stack.resize(w * h)
	var members := PackedInt32Array()
	for start in w * h:
		if comp[start] != -1:
			continue
		var color := labels[start]
		var cid := start
		comp[start] = cid
		var top := 1
		stack[0] = start
		members.clear()
		var border := {}
		while top > 0:
			top -= 1
			var i := stack[top]
			members.append(i)
			var y := i / w
			var x := i - y * w
			for j in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w if y > 0 else -1, i + w if y < h - 1 else -1]:
				if j < 0:
					continue
				if labels[j] == color:
					if comp[j] == -1:
						comp[j] = cid
						stack[top] = j
						top += 1
				else:
					border[labels[j]] = border.get(labels[j], 0) + 1
		if members.size() < min_area and not border.is_empty():
			var best := color
			var best_n := 0
			for v in border:
				if border[v] > best_n:
					best_n = border[v]
					best = v
			for i in members:
				labels[i] = best
	return labels

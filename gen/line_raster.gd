class_name LineRaster
extends RefCounted
## Line-art masks: one byte per pixel, 255 = line, 0 = empty.
## Every Collage picture source (mandala polylines, bundled line art, photos)
## ends up as one of these before region detection.


## Draws unit-space polylines (x, y in -1..1) into a mask of `size` pixels,
## each segment as a capsule `thickness` px wide.
static func rasterize(polylines: Array[PackedVector2Array], closed: PackedByteArray, size: Vector2i,
		thickness: float, margin: float = 0.04) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	var scale := minf(size.x, size.y) * (1.0 - 2.0 * margin) / 2.0
	var center := Vector2(size) / 2.0
	var hr := thickness / 2.0
	var hr2 := hr * hr
	for li in polylines.size():
		var src := polylines[li]
		var n := src.size()
		if n < 2:
			continue
		var segs: int = n if closed[li] else n - 1
		for i in segs:
			var a := center + src[i] * scale
			var b := center + src[(i + 1) % n] * scale
			var x0 := maxi(0, floori(minf(a.x, b.x) - hr))
			var x1 := mini(size.x - 1, ceili(maxf(a.x, b.x) + hr))
			var y0 := maxi(0, floori(minf(a.y, b.y) - hr))
			var y1 := mini(size.y - 1, ceili(maxf(a.y, b.y) + hr))
			var d := b - a
			var ll := d.length_squared()
			for y in range(y0, y1 + 1):
				var py := y + 0.5 - a.y
				var row := y * size.x
				for x in range(x0, x1 + 1):
					var px := x + 0.5 - a.x
					var t := 0.0
					if ll > 0.0:
						t = clampf((px * d.x + py * d.y) / ll, 0.0, 1.0)
					var ex := px - t * d.x
					var ey := py - t * d.y
					if ex * ex + ey * ey <= hr2:
						mask[row + x] = 255
	return mask


## Mask from a line-art image: dark, opaque pixels are lines.
static func from_image(img: Image, threshold: float = 0.5) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.get_luminance() < threshold:
				mask[y * w + x] = 255
	return mask


## Thickens lines by `radius` px (a square max filter, done separably). Used to
## close small gaps in hand-drawn line art before flood filling.
static func dilate(mask: PackedByteArray, w: int, h: int, radius: int) -> PackedByteArray:
	if radius <= 0:
		return mask
	var tmp := PackedByteArray()
	tmp.resize(w * h)
	for y in h:
		var row := y * w
		for x in w:
			if mask[row + x]:
				for xx in range(maxi(0, x - radius), mini(w, x + radius + 1)):
					tmp[row + xx] = 255
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			if tmp[y * w + x]:
				for yy in range(maxi(0, y - radius), mini(h, y + radius + 1)):
					out[yy * w + x] = 255
	return out


## Thickens lines by `radius` px in every direction (a round brush), using a
## two-pass 3-4 chamfer distance to the nearest line pixel.
static func dilate_round(mask: PackedByteArray, w: int, h: int, radius: float) -> PackedByteArray:
	if radius <= 0.0:
		return mask
	const BIG := 1 << 28
	var d := PackedInt32Array()
	d.resize(w * h)
	for i in w * h:
		d[i] = 0 if mask[i] else BIG
	for y in h:
		for x in w:
			var i := y * w + x
			if d[i] == 0:
				continue
			var best := d[i]
			if x > 0:
				best = mini(best, d[i - 1] + 3)
			if y > 0:
				best = mini(best, d[i - w] + 3)
				if x > 0:
					best = mini(best, d[i - w - 1] + 4)
				if x < w - 1:
					best = mini(best, d[i - w + 1] + 4)
			d[i] = best
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			if d[i] == 0:
				continue
			var best := d[i]
			if x < w - 1:
				best = mini(best, d[i + 1] + 3)
			if y < h - 1:
				best = mini(best, d[i + w] + 3)
				if x < w - 1:
					best = mini(best, d[i + w + 1] + 4)
				if x > 0:
					best = mini(best, d[i + w - 1] + 4)
			d[i] = best
	var limit := int(radius * 3.0)
	var out := PackedByteArray()
	out.resize(w * h)
	for i in w * h:
		if d[i] <= limit:
			out[i] = 255
	return out


## Marks every slot's capsule, grown by `pad` px, as line in a copy of `mask`.
## Gem lines use it to carve a channel that is exactly as wide as their stones.
static func stamp_slots(mask: PackedByteArray, w: int, h: int, slots: Array, pad: float) -> PackedByteArray:
	var out := mask.duplicate()
	for s: Dictionary in slots:
		var r: float = s["width"] / 2.0 + pad
		var hl: float = s["size"] / 2.0 - s["width"] / 2.0
		var c := Vector2(s["x"], s["y"])
		var dir := Vector2.from_angle(s["rotation"])
		var reach := r + hl
		for y in range(maxi(0, int(c.y - reach)), mini(h, int(c.y + reach) + 2)):
			for x in range(maxi(0, int(c.x - reach)), mini(w, int(c.x + reach) + 2)):
				var p := Vector2(x + 0.5, y + 0.5) - c
				var t := clampf(p.dot(dir), -hl, hl)
				if (p - dir * t).length_squared() <= r * r:
					out[y * w + x] = 255
	return out


## Adds a border so regions touching the picture's edge count as closed.
static func add_frame(source: PackedByteArray, w: int, h: int, thickness: int) -> PackedByteArray:
	var mask := source.duplicate()
	for y in h:
		for x in w:
			if x < thickness or y < thickness or x >= w - thickness or y >= h - thickness:
				mask[y * w + x] = 255
	return mask


static func to_image(mask: PackedByteArray, w: int, h: int) -> Image:
	return Image.create_from_data(w, h, false, Image.FORMAT_L8, mask)

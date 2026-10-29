class_name Thumbnail
extends RefCounted
## A small flat picture of a puzzle for the menu: placed stones in their
## colors, open slots as pale dots, on paper.

const PAPER := Color("#f4eee6")
const OPEN := Color("#d8d0c6")


## `placed`: one byte per slot (empty: none placed). `px`: the longer side.
static func render(picture: Dictionary, placed: PackedByteArray, px: int = 256) -> Image:
	var w: float = picture["width"]
	var h: float = picture["height"]
	var k := px / maxf(w, h)
	var iw := maxi(1, int(w * k))
	var ih := maxi(1, int(h * k))
	var img := Image.create(iw, ih, false, Image.FORMAT_RGB8)
	img.fill(PAPER)
	var slots: Array = picture["slots"]
	for i in slots.size():
		var s: Dictionary = slots[i]
		var on := i < placed.size() and placed[i] != 0
		_dot(img, s, k, s["target_color"] if on else OPEN)
	return img


## Paints a slot's footprint (an ellipse as long and wide as it) in `color`.
static func _dot(img: Image, s: Dictionary, k: float, color: Color) -> void:
	var c := Vector2(s["x"], s["y"]) * k
	var a := maxf(s["size"] * k / 2.0, 0.5)
	var b := maxf(s["width"] * k / 2.0, 0.5)
	var dir := Vector2.from_angle(s["rotation"])
	var reach := int(ceil(maxf(a, b)))
	for y in range(int(c.y) - reach, int(c.y) + reach + 1):
		if y < 0 or y >= img.get_height():
			continue
		for x in range(int(c.x) - reach, int(c.x) + reach + 1):
			if x < 0 or x >= img.get_width():
				continue
			var d := Vector2(x + 0.5, y + 0.5) - c
			var u := d.dot(dir) / a
			var v := d.dot(dir.orthogonal()) / b
			if u * u + v * v <= 1.0:
				img.set_pixel(x, y, color)

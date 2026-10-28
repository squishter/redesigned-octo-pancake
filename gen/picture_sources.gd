class_name PictureSources
extends RefCounted
## Every picture source works in both modes: Kit mode needs a color image,
## Collage mode needs line art. These helpers do the conversions.

const DEFAULT_SIZE := 768
const LINE_COLOR := Color("#3a2a4a")
const BACKGROUND := Color("#f4eee6")


## Mandala options: variant, wobble (see MandalaGenerator), size (raster px,
## default 768), line_width (px, default size / 170).
## Returns {"mask", "width", "height", "mandala"}.
static func mandala_lines(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var mandala := MandalaGenerator.generate(seed_value, options)
	var size: int = options.get("size", DEFAULT_SIZE)
	var line_width: float = options.get("line_width", size / 170.0)
	var mask := LineRaster.rasterize(mandala["polylines"], mandala["closed"], Vector2i(size, size), line_width)
	return {"mask": mask, "width": size, "height": size, "mandala": mandala}


## A Collage puzzle from a seeded mandala. Options as mandala_lines plus
## CollageGenerator's (theme, gems, coverage, ...).
static func mandala_collage(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var lines := mandala_lines(seed_value, options)
	var mandala: Dictionary = lines["mandala"]
	var opts := options.duplicate()
	opts["seed"] = seed_value
	opts["symmetry"] = mandala["symmetry"]
	opts["source"] = {
		"kind": "mandala",
		"seed": seed_value,
		"variant": mandala["variant"],
		"wobble": options.get("wobble", 0.0),
		"theme": options.get("theme", "sunset"),
	}
	return CollageGenerator.generate(lines["mask"], lines["width"], lines["height"], opts)


## The mandala filled with a theme palette, for Kit mode. Region colors are
## kept exact here; the kit generator snaps them to her gems afterwards.
static func mandala_image(seed_value: int, options: Dictionary = {}) -> Image:
	var lines := mandala_lines(seed_value, options)
	var w: int = lines["width"]
	var h: int = lines["height"]
	var map := RegionMap.build(lines["mask"], w, h, 0)
	var palette := Palettes.theme_colors(options.get("theme", "sunset"))
	var colors := RegionPaint.theme_colors(map, lines["mandala"]["symmetry"], palette, seed_value)
	return RegionPaint.render(map, colors, options.get("line_color", LINE_COLOR), options.get("background", BACKGROUND))


## A Collage puzzle from a photo: photo -> line art, region colors sampled
## from the photo. Options: detail (0..1), max_size, plus CollageGenerator's.
static func photo_collage(photo: Image, options: Dictionary = {}) -> Dictionary:
	var art := PhotoLineArt.generate(photo, options)
	var opts := options.duplicate()
	opts["colors_image"] = art["image"]
	opts["source"] = {"kind": "photo", "detail": options.get("detail", 0.5)}
	return CollageGenerator.generate(art["mask"], art["width"], art["height"], opts)


## A Collage puzzle from a bundled line-art image (dark lines on a light or
## transparent background). close_gaps dilates the lines by that many px first.
static func line_art_collage(img: Image, options: Dictionary = {}) -> Dictionary:
	var src := img.duplicate() as Image
	if src.is_compressed():
		src.decompress()
	var w := src.get_width()
	var h := src.get_height()
	var mask := LineRaster.from_image(src, options.get("threshold", 0.5))
	mask = LineRaster.dilate(mask, w, h, options.get("close_gaps", 1))
	var opts := options.duplicate()
	opts["source"] = options.get("source", {"kind": "line_art"})
	return CollageGenerator.generate(mask, w, h, opts)

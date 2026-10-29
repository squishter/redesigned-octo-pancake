class_name PictureSources
extends RefCounted
## Every picture source works in both modes: Kit mode needs a color image,
## Collage mode needs line art. These helpers do the conversions.

const DEFAULT_SIZE := 768
const LINE_COLOR := Color("#3a2a4a")
const BACKGROUND := Color("#f4eee6")


## Mandala options: variant, wobble (see MandalaGenerator), silhouette,
## extras, zoom and recent for mandalas (see MandalaDesign), template and recent
## for flowers (see FlowerGenerator), shape, collar, patterns and recent for
## hearts (see HeartGenerator), shape, border, body, antennae and recent for
## butterflies (see ButterflyGenerator), center, arm, tip, between, details
## and recent for snowflakes (see SnowflakeGenerator), size (raster px,
## default 768), line_width (px, default size / 170), and FrameDesign's
## framing options (frame, background, ...); most pictures get a frame.
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
	if mandala.has("flower"):
		opts["source"]["template"] = mandala["flower"]["template"]
	if mandala.has("heart"):
		opts["source"]["heart"] = mandala["heart"]
	if mandala.has("butterfly"):
		opts["source"]["butterfly"] = mandala["butterfly"]
	if mandala.has("snowflake"):
		opts["source"]["snowflake"] = mandala["snowflake"]
	if mandala.has("mandala"):
		opts["source"]["mandala"] = mandala["mandala"]
	if not mandala["frame"].is_empty():
		opts["source"]["frame"] = mandala["frame"]
	return CollageGenerator.generate(lines["mask"], lines["width"], lines["height"], opts)


## The mandala filled with a theme palette, for Kit mode. Region colors are
## kept exact here; the kit generator snaps them to her gems afterwards.
## The same design plan as the collage applies (sparsity, line_style options):
## bare regions take the background color, other sparse fills a pale tint of
## their color, and hidden lines take the color of the regions beside them.
static func mandala_image(seed_value: int, options: Dictionary = {}) -> Image:
	var lines := mandala_lines(seed_value, options)
	var w: int = lines["width"]
	var h: int = lines["height"]
	var symmetry: String = lines["mandala"]["symmetry"]
	var map := RegionMap.build(lines["mask"], w, h, 0)
	var palette := Palettes.theme_colors(options.get("theme", "sunset"))
	var colors := RegionPaint.theme_colors(map, symmetry, palette, seed_value)
	var background: Color = options.get("background", BACKGROUND)
	var plan := DesignPlan.make(map, RegionPaint.symmetry_groups(map, symmetry), options, seed_value)
	var fills: PackedStringArray = plan["fills"]
	for r in colors.size():
		if fills[r] == "bare":
			colors[r] = background
		elif fills[r] != "full":
			colors[r] = colors[r].lerp(background, 0.6)
	return RegionPaint.render(map, colors, options.get("line_color", LINE_COLOR), background,
			DesignPlan.visible_lines(map, plan))


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

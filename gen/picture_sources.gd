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
## Swirls (layout, shape, recent; see SwirlGenerator) aren't symmetric but
## come with families of lines and areas; those are returned as "motifs":
## {"lines": a family per pixel (-1 off the lines), "areas": [{"at": px,
## "family"}]}, for CollageGenerator.
## Returns {"mask", "width", "height", "mandala"} (and "motifs").
static func mandala_lines(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var mandala := MandalaGenerator.generate(seed_value, options)
	var size: int = options.get("size", DEFAULT_SIZE)
	var line_width: float = options.get("line_width", size / 170.0)
	var px := Vector2i(size, size)
	var mask := LineRaster.rasterize(mandala["polylines"], mandala["closed"], px, line_width)
	var out := {"mask": mask, "width": size, "height": size, "mandala": mandala}
	if mandala.has("families"):
		# A little wider than the lines, so their centerlines read it.
		var areas := []
		for m: Dictionary in mandala["marks"]:
			areas.append({"at": LineRaster.to_px(m["at"], px), "family": m["family"]})
		out["motifs"] = {
			"lines": LineRaster.rasterize_labels(mandala["polylines"], mandala["closed"], mandala["families"], px,
					line_width + 2.0),
			"areas": areas,
		}
	return out


## A Collage puzzle from a seeded mandala. Options as mandala_lines plus
## CollageGenerator's (theme, gems, setting, line_gems, ...); a swirl's
## families go in as `motifs`. The seed picks
## the lines; `pattern_seed` picks how they become gems, so one line art
## makes many collages. Pass `lines` (mandala_lines of the same seed and
## options) to reuse line art already made.
static func mandala_collage(seed_value: int, options: Dictionary = {}, lines: Dictionary = {}) -> Dictionary:
	if lines.is_empty():
		lines = mandala_lines(seed_value, options)
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
		opts["source"]["free_form"] = not mandala["flower"]["symmetric"]
	if mandala.has("heart"):
		opts["source"]["heart"] = mandala["heart"]
	if mandala.has("butterfly"):
		opts["source"]["butterfly"] = mandala["butterfly"]
	if mandala.has("snowflake"):
		opts["source"]["snowflake"] = mandala["snowflake"]
	if mandala.has("mandala"):
		opts["source"]["mandala"] = mandala["mandala"]
	if mandala.has("swirl"):
		opts["source"]["swirl"] = mandala["swirl"]
	if lines.has("motifs"):
		opts["motifs"] = lines["motifs"]
	if not mandala["frame"].is_empty():
		opts["source"]["frame"] = mandala["frame"]
	return CollageGenerator.generate(lines["mask"], lines["width"], lines["height"], opts)


## The mandala filled with a theme palette, for Kit mode. Region colors are
## kept exact here; the kit generator snaps them to her gems afterwards.
## The same design plan as the collage applies (sparsity, line_style options):
## bare regions take the background color, other sparse fills a pale tint of
## their color, and hidden lines take the color of the regions beside them.
## A swirl's motif areas (all its leaves, say) share colors.
## Pass `lines` (mandala_lines of the same seed and options) to reuse them.
static func mandala_image(seed_value: int, options: Dictionary = {}, lines: Dictionary = {}) -> Image:
	if lines.is_empty():
		lines = mandala_lines(seed_value, options)
	var w: int = lines["width"]
	var h: int = lines["height"]
	var symmetry: String = lines["mandala"]["symmetry"]
	var map := RegionMap.build(lines["mask"], w, h, 0)
	var palette: PackedColorArray = (options["theme_colors"] if options.has("theme_colors")
			else Palettes.theme_colors(options.get("theme", "sunset")))
	var groups := RegionPaint.symmetry_groups(map, symmetry)
	if lines.has("motifs"):
		groups = RegionPaint.motif_groups(map, groups, lines["motifs"]["areas"])
	var colors := RegionPaint.theme_colors(map, symmetry, palette, seed_value, groups)
	var background: Color = options.get("background", BACKGROUND)
	var plan := DesignPlan.make(map, groups, options, seed_value)
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
## Pass `art` (PhotoLineArt.generate of the same photo and options) to reuse it.
## `method`: "edges" (PhotoEdges: edge detection, then the subject alone
## when it has a clear one; see its `subject` option) or "areas"
## (PhotoLineArt: lines between color areas; the default, for the lab).
static func photo_collage(photo: Image, options: Dictionary = {}, art: Dictionary = {}) -> Dictionary:
	var method: String = options.get("method", "areas")
	if art.is_empty():
		art = PhotoEdges.line_art(photo, options) if method == "edges" else PhotoLineArt.generate(photo, options)
	var opts := options.duplicate()
	opts["colors_image"] = art["image"]
	opts["source"] = {"kind": "photo", "detail": options.get("detail", 0.5), "method": method,
			"subject": art.get("subject", false)}
	return CollageGenerator.generate(art["mask"], art["width"], art["height"], opts)


## A Collage puzzle from a bundled line-art image (dark lines on a light or
## transparent background). close_gaps dilates the lines by that many px first.
## Pass a different `pattern_seed` for another collage of the same art.
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

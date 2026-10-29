class_name MandalaGenerator
extends RefCounted
## Seeded symmetric line art: mandalas, flowers, snowflakes, hearts and
## butterflies. The same seed and options always give the same picture.
##
## Output is vector polylines in unit space (x and y in -1..1, y down), so it
## is crisp at any size. LineRaster turns it into a mask for the slot packer,
## and RegionPaint fills it with a theme for Kit mode.
##
## Each variant has its own generator: MandalaDesign, FlowerGenerator,
## SnowflakeGenerator, HeartGenerator and ButterflyGenerator. This class picks
## one, frames most pictures with FrameDesign, and holds the small shape
## helpers they share.

const VARIANTS := ["mandala", "flower", "snowflake", "heart", "butterfly"]


## options: variant (one of VARIANTS or "random", default "mandala"), wobble
## (0..1, the "semi-symmetric" strength, default 0), FrameDesign's options
## (frame, frame_shape, frame_band, frame_corner, background, frame_recent),
## plus the chosen generator's own options (see each generator). Returns
## {"seed", "variant", "symmetry": "radial" | "mirror" | "none", "polylines",
## "closed", "frame"} ("frame" is FrameDesign's choices, or empty), plus the
## design's choices under the variant's name: "mandala"
## (folds, silhouette, center, rings, extras, zoom), "flower" (template,
## symmetric, rings, center), "heart" (shape, collar, patterns, divider), "butterfly"
## (shape, border, body, antennae, fore, hind) or "snowflake" (center, arm,
## tip, between, details).
static func generate(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var variant: String = options.get("variant", "mandala")
	if variant == "random":
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		variant = VARIANTS[rng.randi_range(0, VARIANTS.size() - 1)]
	var design: Dictionary
	var symmetry := "radial"
	var keys: Array
	match variant:
		"flower":
			design = FlowerGenerator.generate(seed_value, options)
			keys = ["template", "symmetric", "rings", "center"]
		"snowflake":
			design = SnowflakeGenerator.generate(seed_value, options)
			keys = ["center", "arm", "tip", "between", "details"]
		"heart":
			design = HeartGenerator.generate(seed_value, options)
			symmetry = "mirror"
			keys = ["shape", "collar", "patterns", "divider"]
		"butterfly":
			design = ButterflyGenerator.generate(seed_value, options)
			symmetry = "mirror"
			keys = ["shape", "border", "body", "antennae", "fore", "hind"]
		_:
			variant = "mandala"
			design = MandalaDesign.generate(seed_value, options)
			keys = ["folds", "silhouette", "center", "rings", "extras", "zoom"]
			# A zoomed-in crop is no longer symmetric about the picture's center.
			if design["zoom"]:
				symmetry = "none"
	var info := {}
	for key in keys:
		info[key] = design[key]
	var framing := {"polylines": design["polylines"], "closed": design["closed"], "frame": {}}
	if _frameable(variant, design):
		framing = FrameDesign.apply(design["polylines"], design["closed"], seed_value, options)
	return {
		"seed": seed_value,
		"variant": variant,
		"symmetry": symmetry,
		"polylines": framing["polylines"],
		"closed": framing["closed"],
		"frame": framing["frame"],
		variant: info,
	}


## Mandalas that are zoomed in, or already have a frame or corner fans of
## their own, aren't framed again.
static func _frameable(variant: String, design: Dictionary) -> bool:
	if variant != "mandala":
		return true
	return not design["zoom"] and not ("frame" in design["extras"] or "corners" in design["extras"])


# --- shared helpers ---------------------------------------------------------------

## A circle as a closed polyline; segments default to more for bigger circles.
static func circle(center: Vector2, r: float, segments: int = 0) -> PackedVector2Array:
	if segments <= 0:
		segments = maxi(24, int(240.0 * minf(1.0, r * 2.0 + 0.1)))
	var pts := PackedVector2Array()
	for i in segments:
		pts.append(center + Vector2.from_angle(TAU * i / segments) * r)
	return pts


## A leaf-like lens between two points, bulging by `bulge` x its length.
static func _lens(a: Vector2, b: Vector2, bulge: float, n: int = 16) -> PackedVector2Array:
	var d := b - a
	var normal := Vector2(-d.y, d.x).normalized()
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		pts.append(a + d * t + normal * (bulge * d.length() * sin(PI * t) * 0.5))
	for i in range(n - 1, 0, -1):
		var t := float(i) / n
		pts.append(a + d * t - normal * (bulge * d.length() * sin(PI * t) * 0.5))
	return pts

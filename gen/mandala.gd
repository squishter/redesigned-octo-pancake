class_name MandalaGenerator
extends RefCounted
## Seeded line art: symmetric mandalas, flowers, snowflakes, hearts and
## butterflies, and free-form swirls. The same seed and options always give
## the same picture.
##
## Output is vector polylines in unit space (x and y in -1..1, y down), so it
## is crisp at any size. LineRaster turns it into a mask for the slot packer,
## and RegionPaint fills it with a theme for Kit mode.
##
## Each variant has its own generator: MandalaDesign, FlowerGenerator,
## SnowflakeGenerator, HeartGenerator, ButterflyGenerator and SwirlGenerator. This class picks
## one, frames most pictures with FrameDesign, and holds the small shape
## helpers they share.

const VARIANTS := ["mandala", "flower", "snowflake", "heart", "butterfly", "swirl"]
## Swirls are framed less often than the rest (unless `frame` says), so
## their own outlines show.
const SWIRL_FRAME_CHANCE := 0.25


## options: variant (one of VARIANTS or "random", default "mandala"), wobble
## (0..1, the "semi-symmetric" strength, default 0), FrameDesign's options
## (frame, frame_shape, frame_band, frame_corner, background, frame_recent),
## plus the chosen generator's own options (see each generator). Returns
## {"seed", "variant", "symmetry": "radial" | "mirror" | "none", "polylines",
## "closed", "frame"} ("frame" is FrameDesign's choices, or empty), plus the
## design's choices under the variant's name: "mandala"
## (folds, silhouette, center, rings, extras, zoom), "flower" (template,
## symmetric, rings, center), "heart" (shape, collar, patterns, divider), "butterfly"
## (shape, border, body, antennae, fore, hind), "snowflake" (center, arm,
## tip, between, details) or "swirl" (layout, shape, patch, strings, ribbon, motifs).
## Swirls aren't symmetric; instead they also return "families" (an id per
## polyline; a frame's lines get one more) and "marks" ([{"at", "family"}],
## points inside motif areas), see SwirlGenerator.
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
		"swirl":
			design = SwirlGenerator.generate(seed_value, options)
			symmetry = "none"
			keys = ["layout", "shape", "patch", "strings", "ribbon", "motifs"]
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
	var framing := {"polylines": design["polylines"], "closed": design["closed"], "frame": {}, "scale": 1.0}
	if _frameable(variant, design):
		var frame_options := options
		if variant == "swirl" and not options.has("frame"):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([seed_value, "swirl frame"])
			frame_options = options.duplicate()
			frame_options["frame"] = rng.randf() < SWIRL_FRAME_CHANCE
		framing = FrameDesign.apply(design["polylines"], design["closed"], seed_value, frame_options)
	var out := {
		"seed": seed_value,
		"variant": variant,
		"symmetry": symmetry,
		"polylines": framing["polylines"],
		"closed": framing["closed"],
		"frame": framing["frame"],
		variant: info,
	}
	if design.has("families"):
		# The frame's lines are one more family, and the marks move with the
		# picture inside it.
		var families: PackedInt32Array = design["families"].duplicate()
		var frame_family: int = design["family_names"].size()
		while families.size() < out["polylines"].size():
			families.append(frame_family)
		var marks := []
		for m: Dictionary in design["marks"]:
			marks.append({"at": m["at"] * framing["scale"], "family": m["family"]})
		out["families"] = families
		out["marks"] = marks
	return out


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

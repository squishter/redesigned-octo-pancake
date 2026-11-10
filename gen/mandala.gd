class_name MandalaGenerator
extends RefCounted
## Seeded line art: symmetric mandalas, flowers, snowflakes, hearts and
## butterflies, and free-form swirls and animals. The same
## seed and options always give the same picture.
##
## Output is vector polylines in unit space (x and y in -1..1, y down), so it
## is crisp at any size. LineRaster turns it into a mask for the slot packer,
## and RegionPaint fills it with a theme for Kit mode.
##
## Each variant has its own generator: MandalaDesign, FlowerGenerator,
## SnowflakeGenerator, HeartGenerator, ButterflyGenerator, SwirlGenerator,
## AnimalGenerator, AnimalMeshGenerator and PlantMeshGenerator. This class picks one, frames
## most pictures with FrameDesign, and holds the small shape helpers they
## share.

const VARIANTS := ["mandala", "flower", "snowflake", "heart", "butterfly", "swirl", "animal", "animal_mesh",
		"plant_mesh"]
## Swirls are framed less often than the rest (unless `frame` says), so
## their own outlines show.
const SWIRL_FRAME_CHANCE := 0.25
## Plants picked to read as pictures (see _plant_options): how many heads
## and branches, the views, and the ranges of PlantParameters' controls.
const PLANT_PICTURE := {
	"flowers": ["one", "few", "few"],
	"branching": ["none", "few"],
	"cameras": ["front", "three_quarter", "side", "high"],
	"few_heads": [2, 3],
	"few_branches": [1, 2],
	"controls": {"length": [1.4, 1.7], "radius": [0.032, 0.04], "flower_scale": [1.0, 1.15],
			"leaf_scale": [0.46, 0.55]},
}


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
## tip, between, details), "swirl" (layout, shape, patch, strings, ribbon, motifs),
## "animal" (species, blend, plan, coat, pose, facing, scene, feet, ears, horns,
## tail, mane, markings) or "animal_mesh" (species, model, plan, pose, camera,
## coat, pose_record, source_sha256, pose_data_sha256, projection, backend) or
## "plant_mesh" (flower, leaf, curve, branching, flowers, pose, camera,
## component_variant, stats, recipe, asset_revision, source_sha256,
## projection, backend; `recipe` makes the same plant again, see
## PlantMeshGenerator). A plant that can't be made (an unknown flower, say)
## comes back with no lines.
## Swirls, animals and plants aren't symmetric; instead they also return "families" (an id per
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
		"animal":
			design = AnimalGenerator.generate(seed_value, options)
			symmetry = "none"
			keys = ["species", "blend", "plan", "coat", "pose", "facing", "scene", "feet", "ears", "horns", "tail",
					"mane", "markings"]
		"animal_mesh":
			design = AnimalMeshGenerator.generate(seed_value, options)
			symmetry = "none"
			keys = ["species", "model", "plan", "pose", "camera", "coat", "pose_record",
					"source_sha256", "pose_data_sha256", "projection", "backend"]
		"plant_mesh":
			var plant_options := options.duplicate()
			plant_options["seed"] = seed_value
			design = PlantMeshGenerator.generate(seed_value, _plant_options(plant_options))
			symmetry = "none"
			keys = ["flower", "leaf", "curve", "branching", "flowers", "pose", "camera", "component_variant", "stats",
					"recipe", "asset_revision", "source_sha256", "projection", "backend"]
			if design.is_empty():
				keys = []
				design = {"polylines": [], "closed": PackedByteArray(), "families": PackedInt32Array(),
						"family_names": PackedStringArray(), "marks": []}
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
		if variant in ["animal_mesh", "plant_mesh"] and not options.has("frame"):
			frame_options = options.duplicate()
			frame_options["frame"] = false
		elif variant == "swirl" and not options.has("frame"):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([seed_value, "swirl frame"])
			frame_options = options.duplicate()
			frame_options["frame"] = rng.randf() < SWIRL_FRAME_CHANCE
		elif variant == "animal" and design["scene"] != "none" and not options.has("frame"):
			# An animal on a board of its own already has an edge; a frame
			# would shrink it to a stamp.
			frame_options = options.duplicate()
			frame_options["frame"] = false
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
		out["family_names"] = design["family_names"] + PackedStringArray(["frame"])
		out["marks"] = marks
	return out


## PlantMeshGenerator's options out of a picture's: its own keys only (a
## picture's `pose` or `camera` may be meant for an animal, and a choice the
## plants don't have would make no plant at all), with "random" and unknown
## choices left to the seed. `plant` holds them instead when given, so a
## saved source's "plant_mesh" (with its `recipe`) can be passed straight back.
##
## What isn't asked for is picked to suit a picture: the generator's own
## defaults grow tall thin stems with many small heads, which come out as
## specks in a gem collage. So few, big flowers and leaves on a short, thick
## stem with few branches (PLANT_PICTURE), unless `plant_natural` is true.
static func _plant_options(options: Dictionary) -> Dictionary:
	var given: Dictionary = options["plant"] if options.get("plant") is Dictionary else options
	var out := {}
	if given.get("recipe") is Dictionary:
		out["recipe"] = given["recipe"]
		return out
	var catalog := PlantMeshGenerator.catalog()
	var choices := {"flower": catalog["flowers"], "leaf": catalog["leaves"], "curve": catalog["curves"],
			"branching": catalog["branching"], "flowers": catalog["flowering"], "pose": catalog["poses"],
			"camera": catalog["cameras"], "component_variant": catalog["variants"]}
	for key: String in choices:
		var value: Variant = given.get(key, "")
		if value is String and value in choices[key]:
			out[key] = value
	for key: String in ["controls", "pose_controls", "projection_size"]:
		if given.has(key):
			out[key] = given[key]
	if options.get("recent") is Array:
		out["recent"] = (options["recent"] as Array).filter(func(r: Variant) -> bool:
			return r is Dictionary and r.has("flower") and r.has("leaf"))
	if options.get("plant_natural", false):
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(options.get("seed", 0)), out.get("flower", ""), "plant picture"])
	var controls: Dictionary = (out["controls"] as Dictionary).duplicate() if out.get("controls") is Dictionary else {}
	# Every choice draws from the stream whether or not it is used, so asking
	# for one thing leaves the others as they were.
	var flowers: String = PLANT_PICTURE["flowers"][rng.randi_range(0, PLANT_PICTURE["flowers"].size() - 1)]
	var branching: String = PLANT_PICTURE["branching"][rng.randi_range(0, PLANT_PICTURE["branching"].size() - 1)]
	var camera: String = PLANT_PICTURE["cameras"][rng.randi_range(0, PLANT_PICTURE["cameras"].size() - 1)]
	var heads := rng.randi_range(PLANT_PICTURE["few_heads"][0], PLANT_PICTURE["few_heads"][1])
	var branches := rng.randi_range(PLANT_PICTURE["few_branches"][0], PLANT_PICTURE["few_branches"][1])
	var picked := {}
	for key: String in PLANT_PICTURE["controls"]:
		var range: Array = PLANT_PICTURE["controls"][key]
		picked[key] = rng.randf_range(range[0], range[1])
	if not out.has("flowers"):
		out["flowers"] = flowers
		if flowers == "few" and not controls.has("flower_count"):
			controls["flower_count"] = heads
	if not out.has("branching"):
		out["branching"] = branching
		if branching == "few" and not controls.has("primary_count"):
			controls["primary_count"] = branches
	if not out.has("camera"):
		out["camera"] = camera
	if out["flowers"] != "many" and out["branching"] != "many":
		for key: String in picked:
			if not controls.has(key) and not given.has(key):
				controls[key] = picked[key]
	out["controls"] = controls
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

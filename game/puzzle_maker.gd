class_name PuzzleMaker
extends RefCounted
## Makes the game's puzzles: a picture of an unlocked type (a collage, or a
## kit of drills), colored with an unlocked theme, using only the gem colors,
## shapes, cuts and picture features she has unlocked. Touches no nodes, so
## it runs on a worker thread.

const SIZE := 768
## Mandalas' decorations outside the rings that aren't frames.
const UNFRAMED_EXTRAS := ["satellites", "sparkles", "rays"]
const EXTRAS_CHANCE := 0.4
## With hand-drawn lines unlocked, this share of pictures wobble.
const WOBBLE_CHANCE := 0.4
## Kits: px per cell and the drill's share of it, how often a kit uses
## square drills (when both are unlocked) and the bigger board.
const KIT_CELL := 10
const KIT_DRILL := 0.9
const SQUARE_DRILL_CHANCE := 0.4
const MEDIUM_KIT_CHANCE := 0.4
## Picture features make() knows (GemCatalog.FEATURES must be among them).
const FEATURES := ["frames", "backgrounds", "collars", "zoom", "wobble"]


## A new puzzle request with fresh seeds: {type, seed, pattern_seed, theme}.
static func new_request(type_id: String, theme_id: String) -> Dictionary:
	return {"type": type_id, "seed": randi_range(1, 999999), "pattern_seed": randi_range(1, 999999), "theme": theme_id}


## The puzzle for `request` (see new_request), made from `unlocks` only:
## its colors, shapes and cuts, and only the picture features unlocked.
static func make(request: Dictionary, unlocks: Dictionary) -> Dictionary:
	var seed_value: int = request["seed"]
	var theme_id: String = request["theme"]
	var info: Dictionary = GemCatalog.PUZZLES.get(request["type"], GemCatalog.PUZZLES["mandala"])
	var features: Array = unlocks.get("features", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "extras"])
	var extras := []
	if rng.randf() < EXTRAS_CHANCE:
		extras.append(UNFRAMED_EXTRAS[rng.randi_range(0, UNFRAMED_EXTRAS.size() - 1)])
	var opts := {
		"variant": info["variant"],
		"size": SIZE,
		"theme": theme_id,
		"theme_colors": GemCatalog.theme_colors(theme_id),
		"gems": GemCatalog.unlocked_gems(unlocks),
		"shapes": unlocks.get("shapes", {}),
		"pattern_seed": request["pattern_seed"],
	}
	# Picture features stay off until unlocked; unlocked, the generators pick
	# them as they usually would.
	if not "frames" in features:
		opts["frame"] = false
		opts["extras"] = extras
	elif not "backgrounds" in features:
		opts["background"] = "plain"
	if not "zoom" in features:
		opts["zoom"] = false
	if not "collars" in features:
		opts["collar"] = "none"
	if "wobble" in features and rng.randf() < WOBBLE_CHANCE:
		opts["wobble"] = rng.randf_range(0.2, 0.6)
	var picture := _kit(seed_value, opts, unlocks, rng) if info.get("kit", false) else \
			PictureSources.mandala_collage(seed_value, opts)
	picture["puzzle"] = request.duplicate()
	return picture


## A Diamond kit as a board of slots: the mandala painted with the theme,
## turned into a grid of round or square drills (whichever are unlocked), one
## per cell, KIT_CELL px apart.
static func _kit(seed_value: int, opts: Dictionary, unlocks: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var gems: Array = opts["gems"]
	var shapes: Dictionary = unlocks.get("shapes", {})
	var drill := "round"
	if shapes.has("square") and (not shapes.has("round") or rng.randf() < SQUARE_DRILL_CHANCE):
		drill = "square"
	var cut: String = shapes.get(drill, [GemCuts.for_shape(drill)[0]])[0]
	var size := "medium" if rng.randf() < MEDIUM_KIT_CHANCE else "small"
	var image := PictureSources.mandala_image(seed_value, opts)
	var kit := KitGenerator.generate(image, {"size": size, "colors": clampi(gems.size(), 6, 20), "gems": gems,
			"drill": drill, "seed": seed_value})
	var w: int = kit["width"]
	var h: int = kit["height"]
	var cells: PackedByteArray = kit["cells"]
	var palette: Array = kit["palette"]
	var d := KIT_CELL * KIT_DRILL
	var slots := []
	for y in h:
		for x in w:
			var entry: Dictionary = palette[cells[y * w + x]]
			slots.append({"id": slots.size(), "region": 0, "shape": drill, "cut": cut, "x": (x + 0.5) * KIT_CELL,
					"y": (y + 0.5) * KIT_CELL, "rotation": 0.0, "size": d, "width": d, "tone": 0, "part": 0,
					"target_color": entry["color"], "target_gem": entry["gem_color_id"]})
	return {
		"version": 2,
		"type": "collage",
		"kind": "kit",
		"width": w * KIT_CELL,
		"height": h * KIT_CELL,
		"unit": d / 2.0,
		"symmetry": "none",
		"drill": drill,
		"kit_size": size,
		"source": {"kind": "mandala", "seed": seed_value, "theme": opts["theme"]},
		"lines": PackedByteArray(),
		"lines_visible": PackedByteArray(),
		"regions": [],
		"slots": slots,
	}

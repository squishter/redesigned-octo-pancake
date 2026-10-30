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
## Photos are shrunk to at most this many px on their longest side first.
const PHOTO_MAX := 1024
## Photo kits: about this many drills, in the photo's own shape, each the
## gem nearest its color with this much of the difference carried on to its
## neighbors (see KitGenerator.map_direct): near 1 is most true to the photo
## (from a little way off), lower scatters fewer odd drills.
const PHOTO_KIT_CELLS := 6000
const PHOTO_DITHER := 0.85
## With the photo's own colors (request `kit_colors` > 0) the palette
## already fits the photo, so less carries on.
const PHOTO_OWN_DITHER := 0.5
## Picture features make() knows (GemCatalog.FEATURES must be among them).
const FEATURES := ["frames", "backgrounds", "collars", "zoom", "wobble"]


## A new puzzle request with fresh seeds: {type, seed, pattern_seed, theme}.
static func new_request(type_id: String, theme_id: String) -> Dictionary:
	return {"type": type_id, "seed": randi_range(1, 999999), "pattern_seed": randi_range(1, 999999), "theme": theme_id}


## The puzzle for `request` (see new_request), made from `unlocks` only:
## its colors, shapes and cuts, and only the picture features unlocked.
##
## Photo puzzles (GemCatalog.PHOTO_MODES) take `photo` (an Image) in the
## request instead of a theme (and photo collages `subject`, see
## PhotoEdges; photo kits `kit_colors`: 0 for her gem colors, else that
## many of the photo's own colors); the photo isn't kept in the request.
static func make(request: Dictionary, unlocks: Dictionary) -> Dictionary:
	if request.get("photo") is Image:
		return _photo(request, unlocks)
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


## A puzzle from her photo: traced into a collage, or a kit of drills.
static func _photo(request: Dictionary, unlocks: Dictionary) -> Dictionary:
	var photo: Image = request["photo"]
	var seed_value: int = request["seed"]
	var opts := {
		"gems": GemCatalog.unlocked_gems(unlocks),
		"shapes": unlocks.get("shapes", {}),
		"pattern_seed": request["pattern_seed"],
		"seed": seed_value,
		"detail": 0.5,
		# Edge detection, then the subject alone when the photo has a clear one
		# ("on": always the likeliest subject, "off": the whole photo).
		"method": "edges",
		"subject": request.get("subject", "auto"),
		# Every area filled: sparse designs make a photo hard to read.
		"sparsity": 0.0,
	}
	var picture: Dictionary
	if request["type"] == "photo_kit":
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "kit"])
		opts["kit_colors"] = int(request.get("kit_colors", 0))
		picture = _kit(seed_value, opts, unlocks, rng, photo)
		picture["source"] = {"kind": "photo", "kit_colors": opts["kit_colors"]}
	else:
		picture = PictureSources.photo_collage(photo, opts)
	var kept := request.duplicate()
	kept.erase("photo")
	picture["puzzle"] = kept
	return picture


## A Diamond kit as a board of slots: the mandala painted with the theme (or
## `image`, a photo), turned into a grid of round or square drills
## (whichever are unlocked), one per cell, KIT_CELL px apart.
static func _kit(seed_value: int, opts: Dictionary, unlocks: Dictionary, rng: RandomNumberGenerator,
		image: Image = null) -> Dictionary:
	var gems: Array = opts["gems"]
	var shapes: Dictionary = unlocks.get("shapes", {})
	var drill := "round"
	if shapes.has("square") and (not shapes.has("round") or rng.randf() < SQUARE_DRILL_CHANCE):
		drill = "square"
	var cut: String = shapes.get(drill, [GemCuts.for_shape(drill)[0]])[0]
	var size: Variant = "medium" if rng.randf() < MEDIUM_KIT_CHANCE else "small"
	var kit_options := {"size": size, "colors": clampi(gems.size(), 6, 20), "gems": gems, "drill": drill,
			"seed": seed_value}
	if image == null:
		image = PictureSources.mandala_image(seed_value, opts)
	else:
		# A photo: every gem she has (or the photo's own `kit_colors` colors),
		# straight from each cell's color, no crop.
		size = KitGenerator.board_for(image, PHOTO_KIT_CELLS)
		kit_options.merge({"size": size, "direct": true, "dither": PHOTO_DITHER, "cleanup": false}, true)
		var own: int = opts.get("kit_colors", 0)
		if own > 0:
			kit_options.merge({"exact": true, "colors": own, "dither": PHOTO_OWN_DITHER}, true)
	var kit := KitGenerator.generate(image, kit_options)
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
		"kit_size": size if size is String else "%dx%d" % [size.x, size.y],
		"source": {"kind": "mandala", "seed": seed_value, "theme": opts.get("theme", "")},
		"lines": PackedByteArray(),
		"lines_visible": PackedByteArray(),
		"regions": [],
		"slots": slots,
	}

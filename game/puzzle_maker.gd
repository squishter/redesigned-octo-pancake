class_name PuzzleMaker
extends RefCounted
## Makes the game's puzzles: a picture of an unlocked type, colored with an
## unlocked theme, using only the gem colors, shapes and cuts she has
## unlocked. Touches no nodes, so it runs on a worker thread.

const SIZE := 768
## Mandalas' decorations outside the rings that aren't frames.
const UNFRAMED_EXTRAS := ["satellites", "sparkles", "rays"]
const EXTRAS_CHANCE := 0.4


## A new puzzle request with fresh seeds: {type, seed, pattern_seed, theme}.
static func new_request(type_id: String, theme_id: String) -> Dictionary:
	return {"type": type_id, "seed": randi_range(1, 999999), "pattern_seed": randi_range(1, 999999), "theme": theme_id}


## The collage for `request` (see new_request), made from `unlocks` only.
static func make(request: Dictionary, unlocks: Dictionary) -> Dictionary:
	var seed_value: int = request["seed"]
	var theme_id: String = request["theme"]
	var info: Dictionary = GemCatalog.PUZZLES.get(request["type"], GemCatalog.PUZZLES["mandala"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "extras"])
	var extras := []
	if rng.randf() < EXTRAS_CHANCE:
		extras.append(UNFRAMED_EXTRAS[rng.randi_range(0, UNFRAMED_EXTRAS.size() - 1)])
	var opts := {
		"variant": info["variant"],
		"size": SIZE,
		# No frames or collars yet: they come later as unlocks.
		"frame": false,
		"zoom": false,
		"extras": extras,
		"collar": "none",
		"theme": theme_id,
		"theme_colors": GemCatalog.theme_colors(theme_id),
		"gems": GemCatalog.unlocked_gems(unlocks),
		"shapes": unlocks.get("shapes", {}),
		"pattern_seed": request["pattern_seed"],
	}
	var picture := PictureSources.mandala_collage(seed_value, opts)
	picture["puzzle"] = request.duplicate()
	return picture

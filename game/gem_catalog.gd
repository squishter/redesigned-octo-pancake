class_name GemCatalog
extends RefCounted
## Everything a player can unlock: gem colors, shapes and their cuts, color
## themes and puzzle types, and what she starts with. Unlocks are a
## Dictionary ({"colors", "shapes", "themes", "puzzles"}, see
## default_unlocks()) kept in her profile (SaveStore); puzzles are made only
## from what is in it (PuzzleMaker).

## Gem colors beyond the generators' starter set (Palettes.STARTER_GEMS).
const EXTRA_COLORS := [
	{"id": "indigo", "name": "Indigo", "color": "#3b2a8c"},
	{"id": "diamond", "name": "Clear", "color": "#e8eef3"},
]
## The primaries she starts with: the rainbow, black, white and clear.
const STARTING_COLORS := ["ruby", "tangerine", "sunflower", "leaf", "sapphire", "indigo", "amethyst", "onyx", "snow",
		"diamond"]
## About half the shapes, each in its classic cut (GemCuts.BY_SHAPE's first),
## covering every kind of slot: round ones, long ones and gem-line boxes.
const STARTING_SHAPES := ["round", "oval", "cushion", "square", "hexagon", "heart", "marquise", "teardrop", "baguette"]
const ALL_SHAPES := ["round", "square", "hexagon", "triangle", "cushion", "octagon", "pentagon", "heart", "trillion",
		"star", "flower", "oval", "teardrop", "marquise", "kite", "lozenge", "baguette", "emerald"]

## Color themes, as gem colors. Order matters as in Palettes.THEMES: rings
## and region groups walk the list, so neighbors should look good together.
const THEMES := {
	"rainbow": {"name": "Rainbow", "gems": ["ruby", "tangerine", "sunflower", "leaf", "sapphire", "amethyst"]},
	"sunset": {"name": "Sunset", "gems": ["sunflower", "tangerine", "ruby", "amethyst", "snow", "indigo"]},
	"ocean": {"name": "Ocean", "gems": ["sapphire", "diamond", "indigo", "leaf", "snow", "amethyst"]},
	"garden": {"name": "Garden", "gems": ["leaf", "ruby", "sunflower", "snow", "amethyst", "tangerine"]},
	"night": {"name": "Starry Night", "gems": ["indigo", "sunflower", "onyx", "diamond", "amethyst", "sapphire"]},
	"ember": {"name": "Ember", "gems": ["ruby", "tangerine", "onyx", "sunflower", "snow", "amethyst"]},
	"pastel": {"name": "Pastel", "gems": ["cherry_blossom", "lavender", "mint", "butter", "sky", "peach"]},
	"berry": {"name": "Berry", "gems": ["amethyst", "rose", "lavender", "ruby", "cherry_blossom", "midnight"]},
	"autumn": {"name": "Autumn", "gems": ["caramel", "tangerine", "ruby", "sunflower", "chocolate", "sand"]},
	"lagoon": {"name": "Lagoon", "gems": ["sea_glass", "sky", "mint", "sapphire", "snow", "forest"]},
}
const STARTING_THEMES := ["rainbow", "sunset", "ocean", "garden", "night", "ember"]

## Puzzle types: which picture generator makes them, and its options. None
## have frames or collars yet.
const PUZZLES := {
	"mandala": {"name": "Mandala collage", "variant": "mandala"},
	"flower": {"name": "Flower collage", "variant": "flower"},
	"snowflake": {"name": "Snowflake collage", "variant": "snowflake"},
	"heart": {"name": "Heart collage", "variant": "heart"},
	"butterfly": {"name": "Butterfly collage", "variant": "butterfly"},
}
const STARTING_PUZZLES := ["mandala"]


static func default_unlocks() -> Dictionary:
	var shapes := {}
	for shape: String in STARTING_SHAPES:
		shapes[shape] = [GemCuts.for_shape(shape)[0]]
	return {
		"colors": STARTING_COLORS.duplicate(),
		"shapes": shapes,
		"themes": STARTING_THEMES.duplicate(),
		"puzzles": STARTING_PUZZLES.duplicate(),
	}


## Every gem color, parsed: [{id, name, color}].
static func all_colors() -> Array:
	var out := Palettes.starter_gems()
	for g in EXTRA_COLORS:
		out.append({"id": g["id"], "name": g["name"], "color": Color(g["color"])})
	return out


## The unlocked gem colors, in the shape the generators expect.
static func unlocked_gems(unlocks: Dictionary) -> Array:
	var ids: Array = unlocks.get("colors", STARTING_COLORS)
	return all_colors().filter(func(g: Dictionary) -> bool: return g["id"] in ids)


static func color_of(gem_id: String) -> Color:
	for g in all_colors():
		if g["id"] == gem_id:
			return g["color"]
	return Color.WHITE


static func color_name(gem_id: String) -> String:
	for g in all_colors():
		if g["id"] == gem_id:
			return g["name"]
	return gem_id.capitalize()


static func theme_colors(theme_id: String) -> PackedColorArray:
	var out := PackedColorArray()
	for gem_id: String in THEMES.get(theme_id, THEMES["rainbow"])["gems"]:
		out.append(color_of(gem_id))
	return out


static func theme_name(theme_id: String) -> String:
	return THEMES.get(theme_id, {"name": theme_id.capitalize()})["name"]


static func puzzle_name(type_id: String) -> String:
	return PUZZLES.get(type_id, {"name": type_id.capitalize()})["name"]


## Unlocked themes and puzzle types, in catalog order.
static func unlocked_themes(unlocks: Dictionary) -> Array:
	var ids: Array = unlocks.get("themes", STARTING_THEMES)
	return THEMES.keys().filter(func(t: String) -> bool: return t in ids)


static func unlocked_puzzles(unlocks: Dictionary) -> Array:
	var ids: Array = unlocks.get("puzzles", STARTING_PUZZLES)
	return PUZZLES.keys().filter(func(t: String) -> bool: return t in ids)

class_name GemCatalog
extends RefCounted
## Everything a player can unlock: gem colors, shapes and their cuts, color
## themes, puzzle types, picture features (frames, collars, ...), placement
## animations and finales, plus the power-ups packs give charges of; and
## what she starts with. Unlocks are a Dictionary ({"colors", "shapes",
## "themes", "puzzles", "features", "animations", "finales"}, see
## default_unlocks()) kept in her profile (SaveStore); puzzles are made only
## from what is in it (PuzzleMaker). Packs (see Packs) unlock the rest.
## Ids here are kept in saves: add freely, never rename or reuse one (see
## Unlockables for how additions reach old profiles).

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

## Puzzle types: which picture generator makes them. Kits turn a mandala
## into a grid of round or square drills, one color per cell.
const PUZZLES := {
	"mandala": {"name": "Mandala collage", "variant": "mandala", "about": "Rings of patterned gems around a center."},
	"flower": {"name": "Flower collage", "variant": "flower", "about": "Layered petals, round and round."},
	"snowflake": {"name": "Snowflake collage", "variant": "snowflake", "about": "Six-fold frosty arms and plates."},
	"heart": {"name": "Heart collage", "variant": "heart", "about": "Hearts filled with patterns and motifs."},
	"butterfly": {"name": "Butterfly collage", "variant": "butterfly", "about": "Mirrored wings with spots and veins."},
	"kit": {"name": "Diamond kit", "variant": "mandala", "kit": true, "about": "A grid of drills, one color per cell."},
}
const STARTING_PUZZLES := ["mandala"]

## Picture features, off until unlocked.
const FEATURES := {
	"frames": {"name": "Frames", "about": "Pictures may come framed, in 280 styles."},
	"backgrounds": {"name": "Frame backgrounds", "about": "Patterns between a frame and its picture."},
	"collars": {"name": "Heart collars", "about": "Bands of rays, beads or petals inside hearts."},
	"zoom": {"name": "Close-ups", "about": "Now and then a mandala seen up close, cropped to a corner."},
	"wobble": {"name": "Hand-drawn lines", "about": "Some pictures wobble a little, as if drawn by hand."},
}

## How a placed gem goes in (see PlayScreen), and the finale's wave.
const ANIMATIONS := {
	"pop": {"name": "Pop", "about": "Grows in place with a little bounce."},
	"fly": {"name": "Fly", "about": "Swoops in from its card with a sparkle trail."},
	"drop": {"name": "Drop", "about": "Falls in from above and settles."},
	"spin": {"name": "Spin", "about": "Twirls into place as it grows."},
	"twinkle": {"name": "Twinkle", "about": "Appears in a burst of sparkles."},
}
const STARTING_ANIMATIONS := ["pop", "fly"]
const FINALES := {
	"ripple": {"name": "Ripple", "about": "A wave out from the middle."},
	"spiral": {"name": "Spiral", "about": "A wave sweeping round the center."},
	"sweep": {"name": "Sweep", "about": "A wave from one side to the other."},
	"shimmer": {"name": "Shimmer", "about": "Every gem twinkles in its own time."},
}
const STARTING_FINALES := ["ripple"]

## Power-ups: charges from packs, spent while playing. "puzzle" ones stay on
## for the whole puzzle once used; "now" ones act once per charge.
const POWERS := {
	"big_brush": {"name": "Big brush", "kind": "puzzle", "about": "Taps and drags fill every matching slot under a wide brush."},
	"auto_finish": {"name": "Tidy up", "kind": "puzzle", "about": "Any gem with fewer than 10 slots left finishes itself."},
	"free_hand": {"name": "Free hand", "kind": "puzzle",
			"about": "Tap any open slot to fill it with its own gem, whichever is picked."},
	"double_coins": {"name": "Double coins", "kind": "puzzle", "about": "Finishing this puzzle pays twice the coins."},
	"finish_gem": {"name": "Finish gem", "kind": "now", "about": "Fills every slot left for the picked gem."},
	"sweep": {"name": "Sweep", "kind": "now", "about": "Fills the picked gem's slots that are on screen."},
	"finder": {"name": "Finder", "kind": "now", "about": "Zooms to where the picked gem's last slots are."},
	"sprinkle": {"name": "Sprinkle", "kind": "now", "about": "Places 40 gems anywhere, of any kind."},
}
## Charges she starts with, to try them out.
const STARTING_POWERS := {"finish_gem": 1, "finder": 2}


## A new player's unlocks (see Unlockables).
static func default_unlocks() -> Dictionary:
	return Unlockables.default_unlocks()


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


## Every shape and cut pair, shape by shape in ALL_SHAPES order, classic cut first.
static func all_cuts() -> Array:
	var out := []
	for shape: String in ALL_SHAPES:
		for cut: String in GemCuts.for_shape(shape):
			out.append([shape, cut])
	return out


static func has_cut(unlocks: Dictionary, shape: String, cut: String) -> bool:
	return cut in unlocks.get("shapes", {}).get(shape, [])


## A shape's display name with its cut, e.g. "Oval, step cut".
static func cut_name(shape: String, cut: String) -> String:
	return "%s, %s cut" % [shape.capitalize(), cut]


static func unlocked_puzzles(unlocks: Dictionary) -> Array:
	var ids: Array = unlocks.get("puzzles", STARTING_PUZZLES)
	return PUZZLES.keys().filter(func(t: String) -> bool: return t in ids)

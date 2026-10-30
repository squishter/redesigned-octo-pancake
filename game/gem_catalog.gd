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

## Each gem color's hue, for grouping (the starter colors; extra ones say so themselves).
const HUES := {
	"snow": "neutral", "silver": "neutral", "slate": "neutral", "onyx": "neutral", "ruby": "red",
	"cherry_blossom": "pink", "rose": "pink", "coral": "orange", "tangerine": "orange", "peach": "orange",
	"sunflower": "yellow", "butter": "yellow", "leaf": "green", "mint": "green", "forest": "green", "sea_glass": "teal",
	"sky": "blue", "sapphire": "blue", "midnight": "blue", "lavender": "purple", "amethyst": "purple",
	"chocolate": "brown", "caramel": "brown", "sand": "brown", "indigo": "purple", "diamond": "neutral",
}
## Gem colors beyond the generators' starter set (Palettes.STARTER_GEMS),
## at least 10 of every hue in all. Add freely; never change an id.
const EXTRA_COLORS := [
	{"id": "indigo", "name": "Indigo", "color": "#3b2a8c", "hue": "purple"},
	{"id": "diamond", "name": "Clear", "color": "#e8eef3", "hue": "neutral"},
	{"id": "garnet", "name": "Garnet", "color": "#7a1022", "hue": "red"},
	{"id": "wine", "name": "Wine", "color": "#4e0c1c", "hue": "red"},
	{"id": "scarlet", "name": "Scarlet", "color": "#f2281e", "hue": "red"},
	{"id": "poppy", "name": "Poppy", "color": "#ff6150", "hue": "red"},
	{"id": "brick", "name": "Brick", "color": "#a8402c", "hue": "red"},
	{"id": "cherry", "name": "Cherry", "color": "#d6164f", "hue": "red"},
	{"id": "strawberry", "name": "Strawberry", "color": "#e8343e", "hue": "red"},
	{"id": "rosewood", "name": "Rosewood", "color": "#94303e", "hue": "red"},
	{"id": "blush", "name": "Blush", "color": "#f49a92", "hue": "red"},
	{"id": "amber", "name": "Amber", "color": "#ffa20a", "hue": "orange"},
	{"id": "pumpkin", "name": "Pumpkin", "color": "#e86a10", "hue": "orange"},
	{"id": "apricot", "name": "Apricot", "color": "#fcae6e", "hue": "orange"},
	{"id": "copper", "name": "Copper", "color": "#b85a26", "hue": "orange"},
	{"id": "persimmon", "name": "Persimmon", "color": "#ec5a2a", "hue": "orange"},
	{"id": "melon", "name": "Melon", "color": "#ff9f80", "hue": "orange"},
	{"id": "burnt_orange", "name": "Burnt Orange", "color": "#c2531a", "hue": "orange"},
	{"id": "papaya", "name": "Papaya", "color": "#ffe0a8", "hue": "orange"},
	{"id": "lemon", "name": "Lemon", "color": "#fff24a", "hue": "yellow"},
	{"id": "gold", "name": "Gold", "color": "#e0b020", "hue": "yellow"},
	{"id": "citrine", "name": "Citrine", "color": "#e6d040", "hue": "yellow"},
	{"id": "canary", "name": "Canary", "color": "#fff68a", "hue": "yellow"},
	{"id": "mustard", "name": "Mustard", "color": "#c49a1c", "hue": "yellow"},
	{"id": "honey", "name": "Honey", "color": "#f2b33d", "hue": "yellow"},
	{"id": "topaz", "name": "Topaz", "color": "#f0a800", "hue": "yellow"},
	{"id": "cream", "name": "Cream", "color": "#fff6cf", "hue": "yellow"},
	{"id": "olive_gold", "name": "Olive Gold", "color": "#9c8a1c", "hue": "yellow"},
	{"id": "emerald", "name": "Emerald", "color": "#10a060", "hue": "green"},
	{"id": "jade", "name": "Jade", "color": "#3aa57a", "hue": "green"},
	{"id": "lime", "name": "Lime", "color": "#a6e22e", "hue": "green"},
	{"id": "moss", "name": "Moss", "color": "#6b7d2a", "hue": "green"},
	{"id": "pine", "name": "Pine", "color": "#14452c", "hue": "green"},
	{"id": "peridot", "name": "Peridot", "color": "#b8d84a", "hue": "green"},
	{"id": "sage", "name": "Sage", "color": "#9cb89a", "hue": "green"},
	{"id": "clover", "name": "Clover", "color": "#2e8b3a", "hue": "green"},
	{"id": "turquoise", "name": "Turquoise", "color": "#20c6c0", "hue": "teal"},
	{"id": "teal", "name": "Teal", "color": "#0f8a8a", "hue": "teal"},
	{"id": "aquamarine", "name": "Aquamarine", "color": "#7fe0d0", "hue": "teal"},
	{"id": "lagoon", "name": "Lagoon", "color": "#0aa6b8", "hue": "teal"},
	{"id": "deep_sea", "name": "Deep Sea", "color": "#0a4f5a", "hue": "teal"},
	{"id": "seafoam", "name": "Seafoam", "color": "#b8efe0", "hue": "teal"},
	{"id": "peacock", "name": "Peacock", "color": "#0b6f80", "hue": "teal"},
	{"id": "mint_ice", "name": "Ice Mint", "color": "#d8f8f2", "hue": "teal"},
	{"id": "spruce", "name": "Spruce", "color": "#2a6f66", "hue": "teal"},
	{"id": "cobalt", "name": "Cobalt", "color": "#0a2f9a", "hue": "blue"},
	{"id": "azure", "name": "Azure", "color": "#2f8cf0", "hue": "blue"},
	{"id": "cornflower", "name": "Cornflower", "color": "#6a8ff0", "hue": "blue"},
	{"id": "navy", "name": "Navy", "color": "#10215c", "hue": "blue"},
	{"id": "powder", "name": "Powder Blue", "color": "#bcdcf8", "hue": "blue"},
	{"id": "denim", "name": "Denim", "color": "#3a5f9a", "hue": "blue"},
	{"id": "cerulean", "name": "Cerulean", "color": "#0a7fbf", "hue": "blue"},
	{"id": "steel", "name": "Steel Blue", "color": "#5a7896", "hue": "blue"},
	{"id": "arctic", "name": "Arctic", "color": "#8ad6ea", "hue": "blue"},
	{"id": "violet", "name": "Violet", "color": "#8a2be2", "hue": "purple"},
	{"id": "plum", "name": "Plum", "color": "#6a1f5c", "hue": "purple"},
	{"id": "orchid", "name": "Orchid", "color": "#b25ad0", "hue": "purple"},
	{"id": "lilac", "name": "Lilac", "color": "#dcc6f0", "hue": "purple"},
	{"id": "grape", "name": "Grape", "color": "#4b1c6e", "hue": "purple"},
	{"id": "mauve", "name": "Mauve", "color": "#a07ab0", "hue": "purple"},
	{"id": "tanzanite", "name": "Tanzanite", "color": "#5a4ad0", "hue": "purple"},
	{"id": "fuchsia", "name": "Fuchsia", "color": "#e0309a", "hue": "pink"},
	{"id": "magenta", "name": "Magenta", "color": "#c0187c", "hue": "pink"},
	{"id": "bubblegum", "name": "Bubblegum", "color": "#ff8ac8", "hue": "pink"},
	{"id": "flamingo", "name": "Flamingo", "color": "#f7708a", "hue": "pink"},
	{"id": "rose_quartz", "name": "Rose Quartz", "color": "#f5cfd8", "hue": "pink"},
	{"id": "hot_pink", "name": "Hot Pink", "color": "#ff4fa0", "hue": "pink"},
	{"id": "raspberry", "name": "Raspberry", "color": "#b81e5a", "hue": "pink"},
	{"id": "candy", "name": "Candy Pink", "color": "#ffb0d8", "hue": "pink"},
	{"id": "mocha", "name": "Mocha", "color": "#7a5040", "hue": "brown"},
	{"id": "cinnamon", "name": "Cinnamon", "color": "#9a4a30", "hue": "brown"},
	{"id": "tan", "name": "Tan", "color": "#c8a070", "hue": "brown"},
	{"id": "espresso", "name": "Espresso", "color": "#3a241a", "hue": "brown"},
	{"id": "hazel", "name": "Hazel", "color": "#8a6a3a", "hue": "brown"},
	{"id": "latte", "name": "Latte", "color": "#c4a088", "hue": "brown"},
	{"id": "umber", "name": "Umber", "color": "#6a4a2a", "hue": "brown"},
	{"id": "pearl", "name": "Pearl", "color": "#f2dcd6", "hue": "neutral"},
	{"id": "ivory", "name": "Ivory", "color": "#ece0c8", "hue": "neutral"},
	{"id": "smoke", "name": "Smoke", "color": "#8a8c94", "hue": "neutral"},
	{"id": "charcoal", "name": "Charcoal", "color": "#3a3a40", "hue": "neutral"},
	{"id": "pewter", "name": "Pewter", "color": "#9a9690", "hue": "neutral"},
	# True grays filling the gaps between the neutrals above.
	{"id": "platinum", "name": "Platinum", "color": "#d5d6d8", "hue": "neutral"},
	{"id": "ash", "name": "Ash", "color": "#77787b", "hue": "neutral"},
	{"id": "graphite", "name": "Graphite", "color": "#505154", "hue": "neutral"},
	{"id": "gunmetal", "name": "Gunmetal", "color": "#2c2d31", "hue": "neutral"},
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
## A theme is hers as soon as she has every one of its colors.
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
	# One for each hue.
	"reds": {"name": "Ruby Reds", "gems": ["ruby", "blush", "garnet", "scarlet", "rosewood", "poppy"]},
	"oranges": {"name": "Orange Grove", "gems": ["tangerine", "papaya", "copper", "apricot", "burnt_orange", "amber"]},
	"yellows": {"name": "Sunshine", "gems": ["sunflower", "cream", "mustard", "lemon", "honey", "canary"]},
	"greens": {"name": "Evergreen", "gems": ["emerald", "mint", "pine", "lime", "moss", "sage"]},
	"teals": {"name": "Tide Pool", "gems": ["teal", "seafoam", "deep_sea", "turquoise", "peacock", "aquamarine"]},
	"blues": {"name": "Deep Blue", "gems": ["sapphire", "powder", "navy", "azure", "denim", "arctic"]},
	"purples": {"name": "Twilight", "gems": ["amethyst", "lilac", "grape", "orchid", "plum", "lavender"]},
	"pinks": {"name": "Bubblegum", "gems": ["hot_pink", "rose_quartz", "raspberry", "bubblegum", "magenta", "candy"]},
	"browns": {"name": "Coffeehouse", "gems": ["espresso", "latte", "mocha", "tan", "cinnamon", "sand"]},
	"neutrals": {"name": "Moonlight", "gems": ["onyx", "pearl", "charcoal", "silver", "slate", "ivory"]},
	# Mixed.
	"tropical": {"name": "Tropical", "gems": ["turquoise", "flamingo", "lime", "papaya", "lagoon", "sunflower"]},
	"forest_floor": {"name": "Forest Floor", "gems": ["moss", "umber", "sage", "pine", "hazel", "peridot"]},
	"candy_shop": {"name": "Candy Shop", "gems": ["bubblegum", "lemon", "aquamarine", "lilac", "candy", "melon"]},
	"peacock": {"name": "Peacock", "gems": ["peacock", "emerald", "cobalt", "gold", "violet", "teal"]},
	"desert": {"name": "Desert", "gems": ["sand", "brick", "tan", "copper", "cream", "umber"]},
	"winter": {"name": "Winter", "gems": ["steel", "snow", "powder", "slate", "arctic", "diamond"]},
	"sorbet": {"name": "Sorbet", "gems": ["melon", "mint", "lemon", "rose_quartz", "apricot", "seafoam"]},
	"galaxy": {"name": "Galaxy", "gems": ["grape", "fuchsia", "navy", "tanzanite", "onyx", "diamond"]},
	"harvest": {"name": "Harvest", "gems": ["pumpkin", "mustard", "rosewood", "olive_gold", "cinnamon", "cream"]},
	"spring": {"name": "Spring", "gems": ["peridot", "cherry_blossom", "canary", "lilac", "mint", "cornflower"]},
	"royal": {"name": "Royal", "gems": ["gold", "wine", "navy", "pearl", "emerald", "amethyst"]},
	"fiesta": {"name": "Fiesta", "gems": ["hot_pink", "amber", "turquoise", "scarlet", "lime", "violet"]},
	"seaside": {"name": "Seaside", "gems": ["navy", "sand", "cerulean", "ivory", "coral", "seafoam"]},
}
const STARTING_THEMES := ["rainbow", "sunset", "ocean", "garden", "night", "ember"]

## Puzzle types: which picture generator makes them. Kits turn a mandala
## into a grid of round or square drills, one color per cell. `source` names
## the picture in the New puzzle panel, under its kind (collage or kit).
const PUZZLES := {
	"mandala": {"name": "Mandala collage", "source": "Mandala", "variant": "mandala",
			"about": "Rings of patterned gems around a center."},
	"flower": {"name": "Flower collage", "source": "Flower", "variant": "flower",
			"about": "Layered petals, round and round."},
	"snowflake": {"name": "Snowflake collage", "source": "Snowflake", "variant": "snowflake",
			"about": "Six-fold frosty arms and plates."},
	"heart": {"name": "Heart collage", "source": "Heart", "variant": "heart",
			"about": "Hearts filled with patterns and motifs."},
	"butterfly": {"name": "Butterfly collage", "source": "Butterfly", "variant": "butterfly",
			"about": "Mirrored wings with spots and veins."},
	"kit": {"name": "Diamond kit", "source": "Mandala", "variant": "mandala", "kit": true,
			"about": "A mandala as a grid of drills, one color per cell."},
}
const STARTING_PUZZLES := ["mandala"]
## Puzzles made from her own photos: always there, not unlocked.
const PHOTO_MODES := {
	"photo_collage": {"name": "Photo collage", "about": "Your photo traced into gem shapes."},
	"photo_kit": {"name": "Photo kit", "about": "Your photo as a grid of drills."},
}

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
	"bounce": {"name": "Bounce", "about": "Leaps from its card in a high arc."},
	"comet": {"name": "Comet", "about": "Streaks in from the sky with a long sparkling tail."},
	"firework": {"name": "Firework", "about": "A spark shoots up and bursts into the gem."},
	"beam": {"name": "Beam", "about": "A column of light shines down and leaves the gem."},
	"halo": {"name": "Halo", "about": "A ring of light closes in on the slot."},
}
const STARTING_ANIMATIONS := ["pop", "fly"]
const FINALES := {
	"ripple": {"name": "Ripple", "about": "A wave out from the middle."},
	"spiral": {"name": "Spiral", "about": "A wave sweeping round the center."},
	"sweep": {"name": "Sweep", "about": "A wave from one side to the other."},
	"shimmer": {"name": "Shimmer", "about": "Every gem twinkles in its own time."},
	"light_ripple": {"name": "Light ripple", "about": "A ring of light spreads from the middle, and every gem it passes flashes."},
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


## Hues in the order Collection shows them.
const HUE_ORDER := ["red", "orange", "yellow", "green", "teal", "blue", "purple", "pink", "brown", "neutral"]


## Every gem color, parsed: [{id, name, color, hue}].
static func all_colors() -> Array:
	var out := Palettes.starter_gems()
	for g in out:
		g["hue"] = HUES.get(g["id"], "neutral")
	for g in EXTRA_COLORS:
		out.append({"id": g["id"], "name": g["name"], "color": Color(g["color"]), "hue": g["hue"]})
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
	return PUZZLES.get(type_id, PHOTO_MODES.get(type_id, {"name": type_id.capitalize()}))["name"]


## Unlocked themes and puzzle types, in catalog order.
static func unlocked_themes(unlocks: Dictionary) -> Array:
	return THEMES.keys().filter(func(t: String) -> bool: return has_theme(unlocks, t))


## A theme is hers once she has all its colors (or if it was unlocked on
## its own before themes came from colors).
static func has_theme(unlocks: Dictionary, theme_id: String) -> bool:
	if theme_id in unlocks.get("themes", []):
		return true
	var colors: Array = unlocks.get("colors", [])
	for gem: String in THEMES.get(theme_id, {"gems": ["?"]})["gems"]:
		if not gem in colors:
			return false
	return true


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

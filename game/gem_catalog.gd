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
	# Shimmer: stones that aren't classic gems, each with a special finish
	# that plays with the light (see GemBoard3D.FINISH_ALPHA): opal's flashing
	# patches of color, moonstone's floating blue glow, labradorite's flash,
	# nacre's soft rainbows (mother of pearl, abalone) and aurora's
	# rainbow-coated crystal.
	{"id": "opal", "name": "Opal", "color": "#eef0f0", "hue": "shimmer", "finish": "opal"},
	{"id": "black_opal", "name": "Black Opal", "color": "#23263a", "hue": "shimmer", "finish": "opal"},
	{"id": "fire_opal", "name": "Fire Opal", "color": "#f2722e", "hue": "shimmer", "finish": "opal"},
	{"id": "pink_opal", "name": "Pink Opal", "color": "#f4c3cf", "hue": "shimmer", "finish": "opal"},
	{"id": "moonstone", "name": "Moonstone", "color": "#dfe5ec", "hue": "shimmer", "finish": "moonstone"},
	{"id": "peach_moonstone", "name": "Peach Moonstone", "color": "#f2cdb4", "hue": "shimmer", "finish": "moonstone"},
	{"id": "labradorite", "name": "Labradorite", "color": "#4c5862", "hue": "shimmer", "finish": "labradorite"},
	{"id": "mother_of_pearl", "name": "Mother of Pearl", "color": "#efe8e2", "hue": "shimmer", "finish": "nacre"},
	{"id": "abalone", "name": "Abalone", "color": "#2c5f6e", "hue": "shimmer", "finish": "nacre"},
	{"id": "aurora", "name": "Aurora", "color": "#eaf0f4", "hue": "shimmer", "finish": "aurora"},
]
## The primaries she starts with: the rainbow, black, white and clear.
const STARTING_COLORS := ["ruby", "tangerine", "sunflower", "leaf", "sapphire", "indigo", "amethyst", "onyx", "snow",
		"diamond"]
## About half the shapes, each in its classic cut (GemCuts.BY_SHAPE's first),
## covering every kind of slot: round ones, long ones and gem-line boxes.
const STARTING_SHAPES := ["round", "oval", "cushion", "square", "hexagon", "heart", "marquise", "teardrop", "baguette",
		"clover", "pebble"]
const ALL_SHAPES := ["round", "square", "hexagon", "triangle", "cushion", "octagon", "pentagon", "heart", "trillion",
		"star", "flower", "oval", "teardrop", "marquise", "kite", "lozenge", "baguette", "emerald", "clover", "pebble",
		"sunburst", "butterfly"]

## Color themes, as gem colors. Order matters as in Palettes.THEMES: rings
## and region groups walk the list, so neighbors should look good together.
## A theme is hers as soon as she has every one of its colors. Themes hold
## MIN_THEME_COLORS to MAX_THEME_COLORS colors; her own color stories
## (CustomThemes) as few as CustomThemes.MIN_COLORS.
const MIN_THEME_COLORS := 3
const MAX_THEME_COLORS := 8
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
	# Shimmer stones.
	"opaline": {"name": "Opaline", "gems": ["opal", "pink_opal", "moonstone", "mother_of_pearl", "aurora",
			"peach_moonstone"]},
	"northern_lights": {"name": "Northern Lights", "gems": ["black_opal", "labradorite", "abalone", "aurora",
			"fire_opal", "opal"]},
	"mermaid": {"name": "Mermaid", "gems": ["abalone", "seafoam", "mother_of_pearl", "lagoon", "opal", "lilac"]},
	# Small ones: three to five colors, for calmer pictures.
	"primary": {"name": "Primary", "gems": ["ruby", "sunflower", "sapphire"]},
	"bumblebee": {"name": "Bumblebee", "gems": ["sunflower", "onyx", "snow"]},
	"candy_cane": {"name": "Candy Cane", "gems": ["scarlet", "snow", "mint"]},
	"mint_chip": {"name": "Mint Chip", "gems": ["mint", "chocolate", "cream"]},
	"moonlit": {"name": "Moonlit", "gems": ["midnight", "silver", "moonstone"]},
	"coral_reef": {"name": "Coral Reef", "gems": ["coral", "turquoise", "sand", "sea_glass"]},
	"lavender_fields": {"name": "Lavender Fields", "gems": ["lavender", "sage", "lilac", "cream"]},
	"sakura": {"name": "Sakura", "gems": ["cherry_blossom", "blush", "snow", "moss"]},
	"meadow": {"name": "Wildflower Meadow", "gems": ["leaf", "poppy", "sunflower", "cornflower", "snow"]},
	"jewel_box": {"name": "Jewel Box", "gems": ["ruby", "emerald", "sapphire", "amethyst", "topaz"]},
	"rose_gold": {"name": "Rose Gold", "gems": ["rose_quartz", "gold", "blush", "ivory", "copper"]},
	# Big ones: seven or eight colors, for lively pictures.
	"full_spectrum": {"name": "Full Spectrum", "gems": ["ruby", "tangerine", "sunflower", "leaf", "sky", "sapphire",
			"amethyst"]},
	"festival": {"name": "Festival", "gems": ["hot_pink", "tangerine", "lemon", "lime", "turquoise", "violet", "snow"]},
	"aurora_sky": {"name": "Aurora Sky", "gems": ["navy", "teal", "emerald", "aurora", "violet", "lilac", "midnight"]},
	"kaleidoscope": {"name": "Kaleidoscope", "gems": ["ruby", "coral", "sunflower", "lime", "turquoise", "cobalt",
			"violet", "fuchsia"]},
	"opal_dreams": {"name": "Opal Dreams", "gems": ["opal", "pink_opal", "fire_opal", "black_opal", "moonstone",
			"aurora", "mother_of_pearl", "abalone"]},
	# More of every size but six. New ones go at the end: existing themes
	# never change, so puzzles made in them stay as they are.
	"tuxedo": {"name": "Tuxedo", "gems": ["onyx", "pearl", "garnet"]},
	"pink_lemonade": {"name": "Pink Lemonade", "gems": ["lemon", "strawberry", "mint"]},
	"blueberries": {"name": "Blueberries & Cream", "gems": ["navy", "cornflower", "cream"]},
	"matcha": {"name": "Matcha Latte", "gems": ["jade", "latte", "ivory"]},
	"golden_hour": {"name": "Golden Hour", "gems": ["honey", "persimmon", "plum"]},
	"cottage": {"name": "Cottage Garden", "gems": ["sage", "blush", "cream", "lavender"]},
	"hot_cocoa": {"name": "Hot Cocoa", "gems": ["espresso", "caramel", "latte", "cream"]},
	"deep_dive": {"name": "Deep Dive", "gems": ["deep_sea", "navy", "seafoam", "pearl"]},
	"citrus": {"name": "Citrus Twist", "gems": ["lemon", "tangerine", "lime", "persimmon"]},
	"nightshade": {"name": "Nightshade", "gems": ["plum", "tanzanite", "midnight", "silver"]},
	"peony": {"name": "Peony", "gems": ["rose", "flamingo", "cherry_blossom", "clover"]},
	"fallen_leaves": {"name": "Fallen Leaves", "gems": ["burnt_orange", "mustard", "brick", "moss"]},
	"beach_day": {"name": "Beach Day", "gems": ["sand", "turquoise", "coral", "sky", "snow"]},
	"orchard": {"name": "Orchard", "gems": ["cherry", "peach", "leaf", "apricot", "butter"]},
	"mountain": {"name": "Mountain Trail", "gems": ["pine", "slate", "snow", "sky", "umber"]},
	"vintage_rose": {"name": "Vintage Rose", "gems": ["mauve", "sage", "cream", "rosewood", "pewter"]},
	"neon": {"name": "Neon Lights", "gems": ["hot_pink", "lime", "lemon", "azure", "violet"]},
	"treasure": {"name": "Treasure Chest", "gems": ["gold", "garnet", "emerald", "sapphire", "pearl"]},
	"glacier": {"name": "Glacier", "gems": ["arctic", "mint_ice", "powder", "platinum", "cerulean"]},
	"rainforest": {"name": "Rainforest", "gems": ["spruce", "forest", "emerald", "lime", "scarlet", "sunflower",
			"cobalt"]},
	"dusk": {"name": "Dusk", "gems": ["midnight", "plum", "magenta", "coral", "tangerine", "amber", "sunflower"]},
	"fruit_bowl": {"name": "Fruit Bowl", "gems": ["strawberry", "tangerine", "lemon", "lime", "grape", "raspberry",
			"peach"]},
	"coastline": {"name": "Coastline", "gems": ["navy", "cerulean", "lagoon", "seafoam", "sand", "ivory", "hazel"]},
	"enchanted": {"name": "Enchanted", "gems": ["tanzanite", "violet", "orchid", "lilac", "moonstone", "aurora",
			"midnight"]},
	"bakery": {"name": "Bakery", "gems": ["cream", "butter", "caramel", "cinnamon", "chocolate", "strawberry",
			"rose_quartz"]},
	"mosaic": {"name": "Mosaic", "gems": ["brick", "amber", "turquoise", "cobalt", "ivory", "olive_gold", "deep_sea"]},
	"rainbow_bright": {"name": "Rainbow Bright", "gems": ["scarlet", "tangerine", "lemon", "lime", "teal", "azure",
			"violet", "hot_pink"]},
	"pastel_rainbow": {"name": "Pastel Rainbow", "gems": ["cherry_blossom", "peach", "butter", "mint", "mint_ice",
			"sky", "lavender", "lilac"]},
	"birthstones": {"name": "Birthstones", "gems": ["ruby", "topaz", "citrine", "peridot", "aquamarine", "sapphire",
			"amethyst", "diamond"]},
	"autumn_festival": {"name": "Autumn Festival", "gems": ["wine", "brick", "pumpkin", "amber", "mustard",
			"olive_gold", "moss", "chocolate"]},
	"ocean_depths": {"name": "Ocean Depths", "gems": ["arctic", "powder", "cerulean", "teal", "deep_sea", "navy",
			"midnight", "pearl"]},
	"flower_market": {"name": "Flower Market", "gems": ["poppy", "rose", "fuchsia", "orchid", "lilac", "canary",
			"peach", "leaf"]},
	"monochrome": {"name": "Monochrome", "gems": ["snow", "platinum", "silver", "ash", "pewter", "graphite",
			"charcoal", "onyx"]},
	"cosmic": {"name": "Cosmic", "gems": ["onyx", "midnight", "indigo", "tanzanite", "magenta", "aurora",
			"black_opal", "diamond"]},
	# Every hue at every size: light, dark, mid and the full range (ombré)
	# of its colors, lightest first, lighter and darker half taking turns.
	"red_light_3": {"name": "Poppy Petals", "gems": ["blush", "scarlet", "poppy"]},
	"red_dark_3": {"name": "Mulled Wine", "gems": ["rosewood", "wine", "garnet"]},
	"red_mid_3": {"name": "Fire Engine", "gems": ["cherry", "brick", "ruby"]},
	"red_full_3": {"name": "Rosé", "gems": ["blush", "wine", "ruby"]},
	"red_light_4": {"name": "Strawberry Fields", "gems": ["blush", "scarlet", "poppy", "strawberry"]},
	"red_dark_4": {"name": "Bordeaux", "gems": ["brick", "garnet", "rosewood", "wine"]},
	"red_mid_4": {"name": "Cherry Orchard", "gems": ["strawberry", "ruby", "cherry", "brick"]},
	"red_full_4": {"name": "Cranberry", "gems": ["blush", "brick", "strawberry", "wine"]},
	"red_light_5": {"name": "Lipstick", "gems": ["blush", "strawberry", "poppy", "cherry", "scarlet"]},
	"red_dark_5": {"name": "Garnet Ring", "gems": ["ruby", "garnet", "brick", "wine", "rosewood"]},
	"red_mid_5": {"name": "Brick & Berry", "gems": ["strawberry", "brick", "cherry", "rosewood", "ruby"]},
	"red_full_5": {"name": "Pomegranate", "gems": ["blush", "rosewood", "scarlet", "wine", "ruby"]},
	"red_light_6": {"name": "Light Reds", "gems": ["blush", "strawberry", "poppy", "cherry", "scarlet", "ruby"]},
	"red_dark_6": {"name": "Dark Reds", "gems": ["cherry", "rosewood", "ruby", "garnet", "brick", "wine"]},
	"red_mid_6": {"name": "Mid Reds", "gems": ["scarlet", "ruby", "strawberry", "brick", "cherry", "rosewood"]},
	"red_full_6": {"name": "Red Ombré", "gems": ["blush", "ruby", "scarlet", "rosewood", "cherry", "wine"]},
	"red_light_7": {"name": "Red Balloon", "gems": ["blush", "cherry", "poppy", "ruby", "scarlet", "brick",
			"strawberry"]},
	"red_dark_7": {"name": "Red Velvet", "gems": ["strawberry", "rosewood", "cherry", "garnet", "ruby", "wine",
			"brick"]},
	"red_mid_7": {"name": "Rooftops", "gems": ["scarlet", "brick", "strawberry", "rosewood", "cherry", "garnet",
			"ruby"]},
	"red_full_7": {"name": "Bouquet of Roses", "gems": ["blush", "brick", "poppy", "rosewood", "strawberry", "wine",
			"ruby"]},
	"red_light_8": {"name": "Scarlet Letter", "gems": ["blush", "cherry", "poppy", "ruby", "scarlet", "brick",
			"strawberry", "rosewood"]},
	"red_dark_8": {"name": "Opera House", "gems": ["scarlet", "brick", "strawberry", "rosewood", "cherry", "garnet",
			"ruby", "wine"]},
	"orange_light_3": {"name": "Apricot Jam", "gems": ["papaya", "apricot", "peach"]},
	"orange_dark_3": {"name": "Copper Kettle", "gems": ["persimmon", "copper", "burnt_orange"]},
	"orange_mid_3": {"name": "Clementine", "gems": ["amber", "coral", "tangerine"]},
	"orange_full_3": {"name": "Kumquat", "gems": ["papaya", "copper", "tangerine"]},
	"orange_light_4": {"name": "Peach Fuzz", "gems": ["papaya", "apricot", "peach", "melon"]},
	"orange_dark_4": {"name": "Bonfire", "gems": ["pumpkin", "burnt_orange", "persimmon", "copper"]},
	"orange_mid_4": {"name": "Tangerine Dream", "gems": ["amber", "coral", "tangerine", "pumpkin"]},
	"orange_full_4": {"name": "Fox Tail", "gems": ["papaya", "pumpkin", "melon", "copper"]},
	"orange_light_5": {"name": "Mango Lassi", "gems": ["papaya", "melon", "peach", "amber", "apricot"]},
	"orange_dark_5": {"name": "Rusty Gate", "gems": ["coral", "burnt_orange", "pumpkin", "copper", "persimmon"]},
	"orange_mid_5": {"name": "Marmalade", "gems": ["melon", "coral", "amber", "pumpkin", "tangerine"]},
	"orange_full_5": {"name": "Monarch Wings", "gems": ["papaya", "persimmon", "apricot", "copper", "tangerine"]},
	"orange_light_6": {"name": "Light Oranges", "gems": ["papaya", "melon", "peach", "amber", "apricot",
			"tangerine"]},
	"orange_dark_6": {"name": "Dark Oranges", "gems": ["tangerine", "persimmon", "coral", "burnt_orange", "pumpkin",
			"copper"]},
	"orange_mid_6": {"name": "Mid Oranges", "gems": ["melon", "coral", "amber", "pumpkin", "tangerine", "persimmon"]},
	"orange_full_6": {"name": "Orange Ombré", "gems": ["papaya", "coral", "apricot", "persimmon", "amber", "copper"]},
	"orange_light_7": {"name": "Orange Blossom", "gems": ["papaya", "amber", "peach", "tangerine", "apricot", "coral",
			"melon"]},
	"orange_dark_7": {"name": "Harvest Moon", "gems": ["amber", "persimmon", "tangerine", "burnt_orange", "coral",
			"copper", "pumpkin"]},
	"orange_mid_7": {"name": "Orange Soda", "gems": ["apricot", "coral", "melon", "pumpkin", "amber", "persimmon",
			"tangerine"]},
	"orange_full_7": {"name": "Tiger Stripes", "gems": ["papaya", "pumpkin", "apricot", "persimmon", "melon",
			"copper", "tangerine"]},
	"orange_light_8": {"name": "Creamsicle", "gems": ["papaya", "amber", "peach", "tangerine", "apricot", "coral",
			"melon", "pumpkin"]},
	"orange_dark_8": {"name": "Pumpkin Spice", "gems": ["melon", "pumpkin", "amber", "persimmon", "tangerine",
			"burnt_orange", "coral", "copper"]},
	"orange_mid_8": {"name": "Goldfish Bowl", "gems": ["apricot", "coral", "melon", "pumpkin", "amber", "persimmon",
			"tangerine", "burnt_orange"]},
	"orange_full_8": {"name": "Autumn Maple", "gems": ["papaya", "coral", "peach", "pumpkin", "melon",
			"burnt_orange", "amber", "copper"]},
	"yellow_light_3": {"name": "Lemon Meringue", "gems": ["cream", "lemon", "canary"]},
	"yellow_dark_3": {"name": "Old Gold", "gems": ["topaz", "olive_gold", "mustard"]},
	"yellow_mid_3": {"name": "Goldenrod", "gems": ["sunflower", "honey", "citrine"]},
	"yellow_full_3": {"name": "Lemon Tart", "gems": ["cream", "olive_gold", "citrine"]},
	"yellow_light_4": {"name": "Buttercup", "gems": ["cream", "lemon", "canary", "butter"]},
	"yellow_dark_4": {"name": "Mustard Seed", "gems": ["gold", "mustard", "topaz", "olive_gold"]},
	"yellow_mid_4": {"name": "Dandelion", "gems": ["sunflower", "honey", "citrine", "gold"]},
	"yellow_full_4": {"name": "Brass Band", "gems": ["cream", "gold", "butter", "olive_gold"]},
	"yellow_light_5": {"name": "Daffodil", "gems": ["cream", "butter", "canary", "sunflower", "lemon"]},
	"yellow_dark_5": {"name": "Antique Brass", "gems": ["honey", "mustard", "gold", "olive_gold", "topaz"]},
	"yellow_mid_5": {"name": "Honeybee", "gems": ["butter", "honey", "sunflower", "gold", "citrine"]},
	"yellow_full_5": {"name": "Saffron", "gems": ["cream", "topaz", "lemon", "olive_gold", "citrine"]},
	"yellow_light_6": {"name": "Light Yellows", "gems": ["cream", "butter", "canary", "sunflower", "lemon",
			"citrine"]},
	"yellow_dark_6": {"name": "Dark Yellows", "gems": ["citrine", "topaz", "honey", "mustard", "gold", "olive_gold"]},
	"yellow_mid_6": {"name": "Mid Yellows", "gems": ["butter", "honey", "sunflower", "gold", "citrine", "topaz"]},
	"yellow_full_6": {"name": "Yellow Ombré", "gems": ["cream", "honey", "lemon", "topaz", "sunflower",
			"olive_gold"]},
	"yellow_light_7": {"name": "Lemon Drops", "gems": ["cream", "sunflower", "canary", "citrine", "lemon", "honey",
			"butter"]},
	"yellow_dark_7": {"name": "Honeycomb", "gems": ["sunflower", "topaz", "citrine", "mustard", "honey",
			"olive_gold", "gold"]},
	"yellow_mid_7": {"name": "Summer Fields", "gems": ["lemon", "honey", "butter", "gold", "sunflower", "topaz",
			"citrine"]},
	"yellow_full_7": {"name": "Candlelight", "gems": ["cream", "gold", "lemon", "topaz", "butter", "olive_gold",
			"citrine"]},
	"yellow_light_8": {"name": "Sunbeam", "gems": ["cream", "sunflower", "canary", "citrine", "lemon", "honey",
			"butter", "gold"]},
	"yellow_dark_8": {"name": "Golden Wheat", "gems": ["butter", "gold", "sunflower", "topaz", "citrine", "mustard",
			"honey", "olive_gold"]},
	"yellow_mid_8": {"name": "Gilded", "gems": ["lemon", "honey", "butter", "gold", "sunflower", "topaz",
			"citrine", "mustard"]},
	"yellow_full_8": {"name": "Banana Bread", "gems": ["cream", "honey", "canary", "gold", "butter", "mustard",
			"sunflower", "olive_gold"]},
	"green_light_3": {"name": "Key Lime", "gems": ["mint", "peridot", "lime"]},
	"green_dark_3": {"name": "Deep Woods", "gems": ["moss", "pine", "forest"]},
	"green_mid_3": {"name": "Shamrock", "gems": ["leaf", "emerald", "jade"]},
	"green_full_3": {"name": "Juniper", "gems": ["mint", "pine", "jade"]},
	"green_light_4": {"name": "Spring Shoots", "gems": ["mint", "peridot", "lime", "sage"]},
	"green_dark_4": {"name": "Pine Needles", "gems": ["clover", "forest", "moss", "pine"]},
	"green_mid_4": {"name": "Four-Leaf Clover", "gems": ["leaf", "emerald", "jade", "clover"]},
	"green_full_4": {"name": "Ivy", "gems": ["mint", "clover", "sage", "pine"]},
	"green_light_5": {"name": "Fresh Herbs", "gems": ["mint", "sage", "lime", "leaf", "peridot"]},
	"green_dark_5": {"name": "Mossy Stones", "gems": ["emerald", "forest", "clover", "pine", "moss"]},
	"green_mid_5": {"name": "Emerald Isle", "gems": ["sage", "emerald", "leaf", "clover", "jade"]},
	"green_full_5": {"name": "Herb Garden", "gems": ["mint", "moss", "peridot", "pine", "jade"]},
	"green_light_6": {"name": "Light Greens", "gems": ["mint", "sage", "lime", "leaf", "peridot", "jade"]},
	"green_dark_6": {"name": "Dark Greens", "gems": ["jade", "moss", "emerald", "forest", "clover", "pine"]},
	"green_mid_6": {"name": "Mid Greens", "gems": ["sage", "emerald", "leaf", "clover", "jade", "moss"]},
	"green_full_6": {"name": "Green Ombré", "gems": ["mint", "emerald", "peridot", "moss", "leaf", "pine"]},
	"green_light_7": {"name": "Meadow Grass", "gems": ["mint", "leaf", "lime", "jade", "peridot", "emerald", "sage"]},
	"green_dark_7": {"name": "Fir Grove", "gems": ["leaf", "moss", "jade", "forest", "emerald", "pine", "clover"]},
	"green_mid_7": {"name": "Garden Hedge", "gems": ["peridot", "emerald", "sage", "clover", "leaf", "moss", "jade"]},
	"green_full_7": {"name": "Rolling Hills", "gems": ["mint", "clover", "peridot", "moss", "sage", "pine", "jade"]},
	"green_light_8": {"name": "Green Tea", "gems": ["mint", "leaf", "lime", "jade", "peridot", "emerald", "sage",
			"clover"]},
	"green_dark_8": {"name": "Jungle Canopy", "gems": ["sage", "clover", "leaf", "moss", "jade", "forest", "emerald",
			"pine"]},
	"green_mid_8": {"name": "Greenhouse", "gems": ["peridot", "emerald", "sage", "clover", "leaf", "moss", "jade",
			"forest"]},
	"green_full_8": {"name": "Botanical", "gems": ["mint", "emerald", "lime", "clover", "sage", "forest", "leaf",
			"pine"]},
	"teal_light_3": {"name": "Sea Breeze", "gems": ["mint_ice", "aquamarine", "seafoam"]},
	"teal_dark_3": {"name": "Kelp Forest", "gems": ["peacock", "deep_sea", "spruce"]},
	"teal_mid_3": {"name": "Turquoise Bay", "gems": ["turquoise", "teal", "lagoon"]},
	"teal_full_3": {"name": "Glacier Lake", "gems": ["mint_ice", "deep_sea", "lagoon"]},
	"teal_light_4": {"name": "Frosted Glass", "gems": ["mint_ice", "aquamarine", "seafoam", "sea_glass"]},
	"teal_dark_4": {"name": "Spruce Hollow", "gems": ["teal", "spruce", "peacock", "deep_sea"]},
	"teal_mid_4": {"name": "Beach Glass", "gems": ["sea_glass", "lagoon", "turquoise", "teal"]},
	"teal_full_4": {"name": "Paradise Cove", "gems": ["mint_ice", "teal", "sea_glass", "deep_sea"]},
	"teal_light_5": {"name": "Shallows", "gems": ["mint_ice", "sea_glass", "seafoam", "turquoise", "aquamarine"]},
	"teal_dark_5": {"name": "Peacock Feather", "gems": ["lagoon", "spruce", "teal", "deep_sea", "peacock"]},
	"teal_mid_5": {"name": "Teal Waters", "gems": ["sea_glass", "teal", "turquoise", "peacock", "lagoon"]},
	"teal_full_5": {"name": "Ocean Spray", "gems": ["mint_ice", "peacock", "aquamarine", "deep_sea", "lagoon"]},
	"teal_light_6": {"name": "Light Teals", "gems": ["mint_ice", "sea_glass", "seafoam", "turquoise", "aquamarine",
			"lagoon"]},
	"teal_dark_6": {"name": "Dark Teals", "gems": ["turquoise", "peacock", "lagoon", "spruce", "teal", "deep_sea"]},
	"teal_mid_6": {"name": "Mid Teals", "gems": ["aquamarine", "lagoon", "sea_glass", "teal", "turquoise",
			"peacock"]},
	"teal_full_6": {"name": "Teal Ombré", "gems": ["mint_ice", "lagoon", "aquamarine", "peacock", "turquoise",
			"deep_sea"]},
	"teal_light_7": {"name": "Caribbean", "gems": ["mint_ice", "turquoise", "seafoam", "lagoon", "aquamarine",
			"teal", "sea_glass"]},
	"teal_dark_7": {"name": "Undersea", "gems": ["sea_glass", "peacock", "turquoise", "spruce", "lagoon",
			"deep_sea", "teal"]},
	"teal_mid_7": {"name": "Tidewater", "gems": ["aquamarine", "teal", "sea_glass", "peacock", "turquoise", "spruce",
			"lagoon"]},
	"teal_full_7": {"name": "Northern Sea", "gems": ["mint_ice", "teal", "seafoam", "peacock", "sea_glass", "deep_sea",
			"lagoon"]},
	"teal_light_8": {"name": "Mermaid Tail", "gems": ["mint_ice", "turquoise", "seafoam", "lagoon", "aquamarine",
			"teal", "sea_glass", "peacock"]},
	"teal_dark_8": {"name": "Reef Shadows", "gems": ["aquamarine", "teal", "sea_glass", "peacock", "turquoise",
			"spruce", "lagoon", "deep_sea"]},
	"blue_light_3": {"name": "Baby Blue", "gems": ["powder", "sky", "arctic"]},
	"blue_dark_3": {"name": "Night Sky", "gems": ["cobalt", "navy", "midnight"]},
	"blue_mid_3": {"name": "Blue Jeans", "gems": ["cerulean", "denim", "steel"]},
	"blue_full_3": {"name": "Blueberry", "gems": ["powder", "navy", "cerulean"]},
	"blue_light_4": {"name": "Clear Skies", "gems": ["powder", "sky", "arctic", "cornflower"]},
	"blue_dark_4": {"name": "Admiral", "gems": ["sapphire", "midnight", "cobalt", "navy"]},
	"blue_mid_4": {"name": "Chambray", "gems": ["azure", "steel", "cerulean", "denim"]},
	"blue_full_4": {"name": "Delft", "gems": ["powder", "denim", "azure", "navy"]},
	"blue_light_5": {"name": "Forget-Me-Not", "gems": ["powder", "cornflower", "arctic", "azure", "sky"]},
	"blue_dark_5": {"name": "Night Watch", "gems": ["denim", "midnight", "sapphire", "navy", "cobalt"]},
	"blue_mid_5": {"name": "Bluebird", "gems": ["azure", "denim", "cerulean", "sapphire", "steel"]},
	"blue_full_5": {"name": "Morning Glory", "gems": ["powder", "sapphire", "cornflower", "navy", "cerulean"]},
	"blue_light_6": {"name": "Light Blues", "gems": ["powder", "cornflower", "arctic", "azure", "sky", "cerulean"]},
	"blue_dark_6": {"name": "Dark Blues", "gems": ["steel", "cobalt", "denim", "midnight", "sapphire", "navy"]},
	"blue_mid_6": {"name": "Mid Blues", "gems": ["cornflower", "steel", "azure", "denim", "cerulean", "sapphire"]},
	"blue_full_6": {"name": "Blue Ombré", "gems": ["powder", "denim", "sky", "cobalt", "azure", "navy"]},
	"blue_light_7": {"name": "Summer Sky", "gems": ["powder", "azure", "arctic", "cerulean", "sky", "steel",
			"cornflower"]},
	"blue_dark_7": {"name": "Starless Night", "gems": ["cerulean", "cobalt", "steel", "midnight", "denim", "navy",
			"sapphire"]},
	"blue_mid_7": {"name": "Lake House", "gems": ["cornflower", "denim", "azure", "sapphire", "cerulean", "cobalt",
			"steel"]},
	"blue_full_7": {"name": "Ocean Waves", "gems": ["powder", "denim", "sky", "cobalt", "azure", "navy", "cerulean"]},
	"blue_light_8": {"name": "Blue Hour", "gems": ["powder", "azure", "arctic", "cerulean", "sky", "steel",
			"cornflower", "denim"]},
	"blue_dark_8": {"name": "Moonless Sea", "gems": ["azure", "sapphire", "cerulean", "cobalt", "steel", "midnight",
			"denim", "navy"]},
	"blue_mid_8": {"name": "Blue Ribbon", "gems": ["sky", "steel", "cornflower", "denim", "azure", "sapphire",
			"cerulean", "cobalt"]},
	"blue_full_8": {"name": "Indigo Dye", "gems": ["powder", "steel", "sky", "sapphire", "cornflower", "cobalt",
			"cerulean", "navy"]},
	"purple_light_3": {"name": "Wisteria", "gems": ["lilac", "mauve", "lavender"]},
	"purple_dark_3": {"name": "Aubergine", "gems": ["plum", "grape", "indigo"]},
	"purple_mid_3": {"name": "Grape Soda", "gems": ["violet", "amethyst", "tanzanite"]},
	"purple_full_3": {"name": "Elderberry", "gems": ["lilac", "grape", "tanzanite"]},
	"purple_light_4": {"name": "Lavender Sachet", "gems": ["lilac", "mauve", "lavender", "orchid"]},
	"purple_dark_4": {"name": "Blackcurrant", "gems": ["amethyst", "indigo", "plum", "grape"]},
	"purple_mid_4": {"name": "Ultraviolet", "gems": ["orchid", "tanzanite", "violet", "amethyst"]},
	"purple_full_4": {"name": "Heather", "gems": ["lilac", "amethyst", "orchid", "grape"]},
	"purple_light_5": {"name": "Violets", "gems": ["lilac", "orchid", "lavender", "violet", "mauve"]},
	"purple_dark_5": {"name": "Royal Robe", "gems": ["tanzanite", "indigo", "amethyst", "grape", "plum"]},
	"purple_mid_5": {"name": "Violet Hour", "gems": ["orchid", "amethyst", "violet", "plum", "tanzanite"]},
	"purple_full_5": {"name": "Iris Garden", "gems": ["lilac", "plum", "mauve", "grape", "tanzanite"]},
	"purple_light_6": {"name": "Light Purples", "gems": ["lilac", "orchid", "lavender", "violet", "mauve",
			"tanzanite"]},
	"purple_dark_6": {"name": "Dark Purples", "gems": ["violet", "plum", "tanzanite", "indigo", "amethyst", "grape"]},
	"purple_mid_6": {"name": "Mid Purples", "gems": ["mauve", "tanzanite", "orchid", "amethyst", "violet", "plum"]},
	"purple_full_6": {"name": "Purple Ombré", "gems": ["lilac", "tanzanite", "mauve", "plum", "violet", "grape"]},
	"purple_light_7": {"name": "Sugarplum", "gems": ["lilac", "violet", "lavender", "tanzanite", "mauve",
			"amethyst", "orchid"]},
	"purple_dark_7": {"name": "Midnight Plum", "gems": ["orchid", "plum", "violet", "indigo", "tanzanite", "grape",
			"amethyst"]},
	"purple_mid_7": {"name": "Jam Jar", "gems": ["mauve", "amethyst", "orchid", "plum", "violet", "indigo",
			"tanzanite"]},
	"purple_full_7": {"name": "Thistle", "gems": ["lilac", "amethyst", "lavender", "plum", "orchid", "grape",
			"tanzanite"]},
	"purple_light_8": {"name": "Pansy Patch", "gems": ["lilac", "violet", "lavender", "tanzanite", "mauve",
			"amethyst", "orchid", "plum"]},
	"purple_dark_8": {"name": "Amethyst Geode", "gems": ["mauve", "amethyst", "orchid", "plum", "violet", "indigo",
			"tanzanite", "grape"]},
	"pink_light_3": {"name": "Cotton Candy", "gems": ["rose_quartz", "candy", "cherry_blossom"]},
	"pink_dark_3": {"name": "Raspberry Jam", "gems": ["fuchsia", "raspberry", "magenta"]},
	"pink_mid_3": {"name": "Flamingo Flock", "gems": ["flamingo", "rose", "hot_pink"]},
	"pink_full_3": {"name": "Bougainvillea", "gems": ["rose_quartz", "raspberry", "hot_pink"]},
	"pink_light_4": {"name": "Strawberry Milk", "gems": ["rose_quartz", "candy", "cherry_blossom", "bubblegum"]},
	"pink_dark_4": {"name": "Berry Bliss", "gems": ["rose", "magenta", "fuchsia", "raspberry"]},
	"pink_mid_4": {"name": "Hibiscus", "gems": ["bubblegum", "hot_pink", "flamingo", "rose"]},
	"pink_full_4": {"name": "Raspberry Ripple", "gems": ["rose_quartz", "rose", "bubblegum", "raspberry"]},
	"pink_light_5": {"name": "Peony Petals", "gems": ["rose_quartz", "bubblegum", "cherry_blossom", "flamingo",
			"candy"]},
	"pink_dark_5": {"name": "Fuchsia Bloom", "gems": ["hot_pink", "magenta", "rose", "raspberry", "fuchsia"]},
	"pink_mid_5": {"name": "Rosebud", "gems": ["bubblegum", "rose", "flamingo", "fuchsia", "hot_pink"]},
	"pink_full_5": {"name": "Camellia", "gems": ["rose_quartz", "fuchsia", "candy", "raspberry", "hot_pink"]},
	"pink_light_6": {"name": "Light Pinks", "gems": ["rose_quartz", "bubblegum", "cherry_blossom", "flamingo",
			"candy", "hot_pink"]},
	"pink_dark_6": {"name": "Dark Pinks", "gems": ["flamingo", "fuchsia", "hot_pink", "magenta", "rose",
			"raspberry"]},
	"pink_mid_6": {"name": "Mid Pinks", "gems": ["candy", "hot_pink", "bubblegum", "rose", "flamingo", "fuchsia"]},
	"pink_full_6": {"name": "Pink Ombré", "gems": ["rose_quartz", "hot_pink", "candy", "fuchsia", "flamingo",
			"raspberry"]},
	"pink_light_7": {"name": "Sweet Pea", "gems": ["rose_quartz", "flamingo", "cherry_blossom", "hot_pink",
			"candy", "rose", "bubblegum"]},
	"pink_dark_7": {"name": "Dragon Fruit", "gems": ["bubblegum", "fuchsia", "flamingo", "magenta", "hot_pink",
			"raspberry", "rose"]},
	"pink_mid_7": {"name": "Pink Party", "gems": ["candy", "rose", "bubblegum", "fuchsia", "flamingo", "magenta",
			"hot_pink"]},
	"pink_full_7": {"name": "Azalea", "gems": ["rose_quartz", "rose", "cherry_blossom", "fuchsia", "bubblegum",
			"raspberry", "hot_pink"]},
	"pink_light_8": {"name": "Blossom Parade", "gems": ["rose_quartz", "flamingo", "cherry_blossom", "hot_pink",
			"candy", "rose", "bubblegum", "fuchsia"]},
	"pink_dark_8": {"name": "Orchid House", "gems": ["candy", "rose", "bubblegum", "fuchsia", "flamingo", "magenta",
			"hot_pink", "raspberry"]},
	"brown_light_3": {"name": "Sandcastle", "gems": ["sand", "tan", "latte"]},
	"brown_dark_3": {"name": "Dark Roast", "gems": ["umber", "espresso", "chocolate"]},
	"brown_mid_3": {"name": "Chestnut", "gems": ["hazel", "mocha", "cinnamon"]},
	"brown_full_3": {"name": "Driftwood", "gems": ["sand", "espresso", "cinnamon"]},
	"brown_light_4": {"name": "Café au Lait", "gems": ["sand", "tan", "latte", "caramel"]},
	"brown_dark_4": {"name": "Cocoa Beans", "gems": ["mocha", "chocolate", "umber", "espresso"]},
	"brown_mid_4": {"name": "Hazelnut", "gems": ["caramel", "cinnamon", "hazel", "mocha"]},
	"brown_full_4": {"name": "Tiramisu", "gems": ["sand", "mocha", "caramel", "espresso"]},
	"brown_light_5": {"name": "Toffee", "gems": ["sand", "caramel", "latte", "hazel", "tan"]},
	"brown_dark_5": {"name": "Walnut", "gems": ["cinnamon", "chocolate", "mocha", "espresso", "umber"]},
	"brown_mid_5": {"name": "Cinnamon Roll", "gems": ["caramel", "mocha", "hazel", "umber", "cinnamon"]},
	"brown_full_5": {"name": "Saddle", "gems": ["sand", "umber", "tan", "espresso", "cinnamon"]},
	"brown_light_6": {"name": "Light Browns", "gems": ["sand", "caramel", "latte", "hazel", "tan", "cinnamon"]},
	"brown_dark_6": {"name": "Dark Browns", "gems": ["hazel", "umber", "cinnamon", "chocolate", "mocha", "espresso"]},
	"brown_mid_6": {"name": "Mid Browns", "gems": ["tan", "cinnamon", "caramel", "mocha", "hazel", "umber"]},
	"brown_full_6": {"name": "Brown Ombré", "gems": ["sand", "cinnamon", "tan", "umber", "hazel", "espresso"]},
	"brown_light_7": {"name": "Gingerbread", "gems": ["sand", "hazel", "latte", "cinnamon", "tan", "mocha",
			"caramel"]},
	"brown_dark_7": {"name": "Fudge Brownie", "gems": ["caramel", "umber", "hazel", "chocolate", "cinnamon",
			"espresso", "mocha"]},
	"brown_mid_7": {"name": "Acorns", "gems": ["tan", "mocha", "caramel", "umber", "hazel", "chocolate",
			"cinnamon"]},
	"brown_full_7": {"name": "Tree Bark", "gems": ["sand", "mocha", "latte", "umber", "caramel", "espresso",
			"cinnamon"]},
	"brown_light_8": {"name": "Wheat Field", "gems": ["sand", "hazel", "latte", "cinnamon", "tan", "mocha",
			"caramel", "umber"]},
	"brown_dark_8": {"name": "Leather Bound", "gems": ["tan", "mocha", "caramel", "umber", "hazel", "chocolate",
			"cinnamon", "espresso"]},
	"neutral_light_3": {"name": "First Snow", "gems": ["snow", "ivory", "diamond"]},
	"neutral_dark_3": {"name": "Raven", "gems": ["charcoal", "onyx", "gunmetal"]},
	"neutral_mid_3": {"name": "Pebbles", "gems": ["pewter", "ash", "smoke"]},
	"neutral_full_3": {"name": "Piano Keys", "gems": ["snow", "onyx", "smoke"]},
	"neutral_light_4": {"name": "Porcelain", "gems": ["snow", "ivory", "diamond", "pearl"]},
	"neutral_dark_4": {"name": "Cast Iron", "gems": ["graphite", "gunmetal", "charcoal", "onyx"]},
	"neutral_mid_4": {"name": "Dove Gray", "gems": ["silver", "smoke", "pewter", "ash"]},
	"neutral_full_4": {"name": "Chess Set", "gems": ["snow", "slate", "platinum", "onyx"]},
	"neutral_light_5": {"name": "Pearl Necklace", "gems": ["snow", "pearl", "diamond", "platinum", "ivory"]},
	"neutral_dark_5": {"name": "Storm Clouds", "gems": ["slate", "gunmetal", "graphite", "onyx", "charcoal"]},
	"neutral_mid_5": {"name": "River Stones", "gems": ["silver", "ash", "pewter", "slate", "smoke"]},
	"neutral_full_5": {"name": "Newsprint", "gems": ["snow", "graphite", "pearl", "onyx", "smoke"]},
	"neutral_light_6": {"name": "Light Neutrals", "gems": ["snow", "pearl", "diamond", "platinum", "ivory",
			"silver"]},
	"neutral_dark_6": {"name": "Dark Neutrals", "gems": ["ash", "charcoal", "slate", "gunmetal", "graphite", "onyx"]},
	"neutral_mid_6": {"name": "Mid Neutrals", "gems": ["platinum", "smoke", "silver", "ash", "pewter", "slate"]},
	"neutral_full_6": {"name": "Neutral Ombré", "gems": ["snow", "ash", "pearl", "graphite", "silver", "onyx"]},
	"neutral_light_7": {"name": "Silver Lining", "gems": ["snow", "platinum", "diamond", "silver", "ivory",
			"pewter", "pearl"]},
	"neutral_dark_7": {"name": "Wrought Iron", "gems": ["smoke", "charcoal", "ash", "gunmetal", "slate", "onyx",
			"graphite"]},
	"neutral_mid_7": {"name": "Morning Fog", "gems": ["platinum", "ash", "silver", "slate", "pewter", "graphite",
			"smoke"]},
	"neutral_full_7": {"name": "Charcoal Sketch", "gems": ["snow", "slate", "ivory", "charcoal", "platinum", "onyx",
			"smoke"]},
	"neutral_light_8": {"name": "Moonbeam", "gems": ["snow", "platinum", "diamond", "silver", "ivory",
			"pewter", "pearl", "smoke"]},
	"neutral_dark_8": {"name": "Smokestack", "gems": ["pewter", "graphite", "smoke", "charcoal", "ash",
			"gunmetal", "slate", "onyx"]},
	"neutral_mid_8": {"name": "City Streets", "gems": ["pearl", "smoke", "platinum", "ash", "silver", "slate",
			"pewter", "graphite"]},
	"neutral_full_8": {"name": "Silver Screen", "gems": ["snow", "smoke", "ivory", "slate", "platinum", "charcoal",
			"pewter", "onyx"]},
	"shimmer_light_3": {"name": "Soap Bubbles", "gems": ["opal", "mother_of_pearl", "aurora"]},
	"shimmer_dark_3": {"name": "Oil Slick", "gems": ["abalone", "black_opal", "labradorite"]},
	"shimmer_mid_3": {"name": "Sunset Opal", "gems": ["peach_moonstone", "fire_opal", "pink_opal"]},
	"shimmer_full_3": {"name": "Opal Trio", "gems": ["opal", "black_opal", "pink_opal"]},
	"shimmer_light_4": {"name": "Pearlescent", "gems": ["opal", "mother_of_pearl", "aurora", "moonstone"]},
	"shimmer_dark_4": {"name": "Dragon's Eye", "gems": ["fire_opal", "labradorite", "abalone", "black_opal"]},
	"shimmer_mid_4": {"name": "Blushing Moonstone", "gems": ["moonstone", "pink_opal", "peach_moonstone", "fire_opal"]},
	"shimmer_full_4": {"name": "Starfire", "gems": ["opal", "fire_opal", "moonstone", "black_opal"]},
	"shimmer_light_5": {"name": "Moonglow", "gems": ["opal", "moonstone", "aurora", "peach_moonstone",
			"mother_of_pearl"]},
	"shimmer_dark_5": {"name": "Opal Mine", "gems": ["pink_opal", "labradorite", "fire_opal", "black_opal",
			"abalone"]},
	"shimmer_mid_5": {"name": "Opal Fire", "gems": ["moonstone", "fire_opal", "peach_moonstone", "abalone",
			"pink_opal"]},
	"shimmer_full_5": {"name": "Moon & Stars", "gems": ["opal", "abalone", "mother_of_pearl", "black_opal",
			"pink_opal"]},
	"shimmer_dark_6": {"name": "Dark Shimmers", "gems": ["peach_moonstone", "abalone", "pink_opal", "labradorite",
			"fire_opal", "black_opal"]},
	"shimmer_mid_6": {"name": "Mid Shimmers", "gems": ["mother_of_pearl", "pink_opal", "moonstone", "fire_opal",
			"peach_moonstone", "abalone"]},
	"shimmer_full_6": {"name": "Shimmer Ombré", "gems": ["opal", "pink_opal", "mother_of_pearl", "abalone",
			"peach_moonstone", "black_opal"]},
	"shimmer_light_7": {"name": "Iridescence", "gems": ["opal", "peach_moonstone", "aurora", "pink_opal",
			"mother_of_pearl", "fire_opal", "moonstone"]},
	"shimmer_dark_7": {"name": "Deep Sea Pearl", "gems": ["moonstone", "abalone", "peach_moonstone", "labradorite",
			"pink_opal", "black_opal", "fire_opal"]},
	"shimmer_mid_7": {"name": "Treasure Trove", "gems": ["mother_of_pearl", "fire_opal", "moonstone", "abalone",
			"peach_moonstone", "labradorite", "pink_opal"]},
	"shimmer_full_7": {"name": "Shimmer Show", "gems": ["opal", "fire_opal", "aurora", "abalone", "moonstone",
			"black_opal", "pink_opal"]},
	"shimmer_light_8": {"name": "Fairy Wings", "gems": ["opal", "peach_moonstone", "aurora", "pink_opal",
			"mother_of_pearl", "fire_opal", "moonstone", "abalone"]},
	"shimmer_dark_8": {"name": "Night Opal", "gems": ["mother_of_pearl", "fire_opal", "moonstone", "abalone",
			"peach_moonstone", "labradorite", "pink_opal", "black_opal"]},
	# More mixes: complements, neighbors, seasons and places.
	"harbor_sunset": {"name": "Harbor Sunset", "gems": ["navy", "tangerine", "cerulean", "apricot", "denim",
			"pumpkin"]},
	"iris_daffodil": {"name": "Iris & Daffodil", "gems": ["violet", "lemon", "plum", "sunflower", "lilac", "honey"]},
	"holly_berry": {"name": "Holly Berry", "gems": ["garnet", "pine", "scarlet", "clover", "cream"]},
	"watermelon": {"name": "Watermelon", "gems": ["hot_pink", "lime", "flamingo", "clover", "candy", "forest"]},
	"coral_lagoon": {"name": "Coral Lagoon", "gems": ["teal", "coral", "aquamarine", "melon", "deep_sea", "peach"]},
	"denim_leather": {"name": "Denim & Leather", "gems": ["denim", "caramel", "navy", "tan", "steel", "espresso"]},
	"hearth": {"name": "Hearth", "gems": ["wine", "brick", "burnt_orange", "amber", "honey"]},
	"spring_rain": {"name": "Spring Rain", "gems": ["lime", "jade", "turquoise", "seafoam", "peridot"]},
	"hydrangea": {"name": "Hydrangea", "gems": ["cornflower", "lavender", "tanzanite", "powder", "lilac", "violet"]},
	"fairy_floss": {"name": "Fairy Floss", "gems": ["candy", "lilac", "bubblegum", "orchid", "rose_quartz",
			"lavender"]},
	"valentine": {"name": "Valentine", "gems": ["ruby", "rose_quartz", "hot_pink", "wine", "blush"]},
	"marigold": {"name": "Marigold", "gems": ["sunflower", "pumpkin", "amber", "butter", "burnt_orange"]},
	"woodland": {"name": "Woodland", "gems": ["moss", "mocha", "sage", "umber", "clover", "tan"]},
	"blue_lagoon": {"name": "Blue Lagoon", "gems": ["lagoon", "navy", "arctic", "peacock", "azure", "seafoam"]},
	"secondary": {"name": "Secondary Colors", "gems": ["tangerine", "leaf", "amethyst"]},
	"neapolitan": {"name": "Neapolitan", "gems": ["chocolate", "strawberry", "cream"]},
	"pumpkin_patch": {"name": "Pumpkin Patch", "gems": ["pumpkin", "moss", "cream", "umber"]},
	"lemon_blueberry": {"name": "Lemon Blueberry", "gems": ["lemon", "navy", "cornflower", "snow"]},
	"sea_salt_caramel": {"name": "Sea Salt Caramel", "gems": ["caramel", "seafoam", "ivory", "umber"]},
	"nautical": {"name": "Nautical", "gems": ["navy", "snow", "scarlet", "gold"]},
	"terracotta": {"name": "Terracotta", "gems": ["brick", "sand", "sage", "cream", "copper"]},
	"lilac_bloom": {"name": "Lilac Bloom", "gems": ["lilac", "sage", "rose_quartz", "cream"]},
	"cherry_pie": {"name": "Cherry Pie", "gems": ["cherry", "caramel", "cream", "garnet"]},
	"black_gold": {"name": "Black & Gold", "gems": ["onyx", "gold", "honey", "gunmetal"]},
	"silver_bells": {"name": "Silver Bells", "gems": ["platinum", "sapphire", "silver", "snow", "pewter"]},
	"emerald_city": {"name": "Emerald City", "gems": ["emerald", "jade", "gold", "pine", "peridot"]},
	"sunflower_field": {"name": "Sunflower Field", "gems": ["sunflower", "chocolate", "leaf", "sky", "honey"]},
	"flamingo_beach": {"name": "Flamingo Beach", "gems": ["flamingo", "sand", "turquoise", "snow"]},
	"plum_orchard": {"name": "Plum Orchard", "gems": ["plum", "mauve", "sage", "cream", "grape"]},
	"midnight_garden": {"name": "Midnight Garden", "gems": ["midnight", "rose", "forest", "lavender", "pine",
			"plum"]},
	"blue_willow": {"name": "Blue Willow", "gems": ["cobalt", "snow", "powder", "navy", "pearl"]},
	"spice_market": {"name": "Spice Market", "gems": ["cinnamon", "mustard", "brick", "persimmon", "olive_gold",
			"umber"]},
	"tea_party": {"name": "Tea Party", "gems": ["rose_quartz", "mint", "butter", "lavender", "pearl", "sage"]},
	"jelly_beans": {"name": "Jelly Beans", "gems": ["cherry", "tangerine", "lemon", "lime", "grape", "bubblegum",
			"snow"]},
	"gemstone_rainbow": {"name": "Gemstone Rainbow", "gems": ["garnet", "fire_opal", "citrine", "emerald",
			"aquamarine", "sapphire", "tanzanite", "rose_quartz"]},
	"sunrise": {"name": "Sunrise", "gems": ["indigo", "orchid", "flamingo", "melon", "apricot", "canary"]},
	"thunderstorm": {"name": "Thunderstorm", "gems": ["slate", "lemon", "graphite", "steel", "platinum", "navy"]},
	"zen_garden": {"name": "Zen Garden", "gems": ["sage", "ash", "sand", "moss", "ivory"]},
	"chocolate_box": {"name": "Chocolate Box", "gems": ["espresso", "raspberry", "chocolate", "caramel", "mocha",
			"cream"]},
	"dragon_scales": {"name": "Dragon Scales", "gems": ["emerald", "gold", "garnet", "teal", "onyx", "copper"]},
	"unicorn": {"name": "Unicorn", "gems": ["aurora", "lilac", "candy", "mint_ice", "butter", "powder", "opal"]},
	"seashell": {"name": "Seashell", "gems": ["pearl", "peach_moonstone", "sand", "blush", "mother_of_pearl"]},
	"toy_box": {"name": "Toy Box", "gems": ["scarlet", "cobalt", "lemon", "clover", "tangerine", "snow", "onyx",
			"violet"]},
	"retro_diner": {"name": "Retro Diner", "gems": ["cherry", "mint", "cream", "onyx", "turquoise"]},
	"campfire": {"name": "Campfire", "gems": ["espresso", "brick", "persimmon", "amber", "lemon", "charcoal"]},
	"lily_pond": {"name": "Lily Pond", "gems": ["jade", "pine", "rose_quartz", "lagoon", "cream"]},
	"bluebell_wood": {"name": "Bluebell Wood", "gems": ["cornflower", "tanzanite", "moss", "pine", "lilac"]},
	"rose_garden": {"name": "Rose Garden", "gems": ["rose", "forest", "blush", "raspberry", "sage",
			"cherry_blossom"]},
	"ballet": {"name": "Ballet Slippers", "gems": ["rose_quartz", "pearl", "blush", "platinum"]},
	"velvet": {"name": "Velvet", "gems": ["wine", "plum", "grape", "gold"]},
	"tiger_lily": {"name": "Tiger Lily", "gems": ["pumpkin", "onyx", "amber", "leaf"]},
	"koi_pond": {"name": "Koi Pond", "gems": ["persimmon", "snow", "teal", "onyx", "gold"]},
	"merry_bright": {"name": "Merry & Bright", "gems": ["scarlet", "pine", "gold", "snow", "clover", "garnet"]},
	"easter_eggs": {"name": "Easter Eggs", "gems": ["lilac", "butter", "mint", "candy", "powder"]},
	"spooky_night": {"name": "Spooky Night", "gems": ["pumpkin", "onyx", "grape", "lime", "amber"]},
	"lantern_festival": {"name": "Lantern Festival", "gems": ["scarlet", "gold", "garnet", "honey"]},
	"lemonade_stand": {"name": "Lemonade Stand", "gems": ["lemon", "sky", "snow", "strawberry"]},
	"fresh_mint": {"name": "Fresh Mint", "gems": ["mint", "pine", "snow", "jade"]},
	"blackberry": {"name": "Blackberry Bramble", "gems": ["grape", "forest", "raspberry", "plum", "moss"]},
	"tropical_punch": {"name": "Tropical Punch", "gems": ["fuchsia", "tangerine", "lagoon", "lemon", "lime",
			"coral"]},
	"starlight": {"name": "Starlight", "gems": ["navy", "canary", "midnight", "platinum", "cobalt", "snow"]},
	"copper_patina": {"name": "Copper Patina", "gems": ["copper", "aquamarine", "burnt_orange", "teal", "sand"]},
	"heather_moor": {"name": "Heather Moor", "gems": ["mauve", "moss", "lilac", "umber", "sage"]},
	"peaches_cream": {"name": "Peaches & Cream", "gems": ["peach", "cream", "apricot", "blush"]},
	"arctic_aurora": {"name": "Arctic Aurora", "gems": ["navy", "emerald", "aurora", "violet", "arctic", "teal",
			"midnight", "lime"]},
	"painted_desert": {"name": "Painted Desert", "gems": ["brick", "sand", "persimmon", "tan", "mauve", "umber",
			"cream"]},
	"berry_smoothie": {"name": "Berry Smoothie", "gems": ["raspberry", "lilac", "strawberry", "grape", "candy",
			"blush", "plum"]},
	"garden_party": {"name": "Garden Party", "gems": ["leaf", "bubblegum", "sunflower", "lavender", "sky", "peach",
			"snow"]},
	"autumn_woods": {"name": "Autumn Woods", "gems": ["pine", "amber", "brick", "olive_gold", "chocolate", "mustard",
			"moss"]},
	"coral_cove": {"name": "Coral Cove", "gems": ["coral", "navy", "sand", "turquoise", "peach", "teal", "ivory",
			"flamingo"]},
	"candy_store": {"name": "Sweet Shop", "gems": ["cherry", "bubblegum", "lemon", "mint", "lilac", "tangerine",
			"candy", "sky"]},
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
	"swirl": {"name": "Swirl collage", "source": "Swirl", "variant": "swirl",
			"about": "Free-flowing line art: waves, whirls, blooms, scales and more, no two alike."},
	"kit": {"name": "Diamond kit", "source": "Mandala", "variant": "mandala", "kit": true,
			"about": "Any of your pictures as a grid of drills, one color per cell."},
}
## The picture a kit request without `picture` is made from (see kit_picture).
const KIT_PICTURE := "mandala"
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
	"light_spiral": {"name": "Light spiral", "about": "A beam of light sweeps round the center, and every gem it passes flashes."},
	"light_sweep": {"name": "Light sweep", "about": "A band of light crosses from one side to the other, and every gem it passes flashes."},
	"light_shimmer": {"name": "Light shimmer", "about": "Light dances over the picture, flashing every gem in its own time."},
}
const STARTING_FINALES := ["light_shimmer"]
## How a picture's painted lines look (see LinePaint; GemBoard3D.LINE_FINISHES
## lists them in the paper shader's order).
const LINE_FINISHES := {
	"metal": {"name": "Metal", "about": "Brushed metal in the paint's color, with a bright sheen as the light moves."},
	"matte": {"name": "Matte", "about": "Soft, flat paint with no shine."},
	"glossy": {"name": "Glossy", "about": "Candy-bright paint, round as a tube, with a crisp white highlight."},
	"glitter": {"name": "Glitter", "about": "Sparkly paint whose flecks wink as you tilt the phone."},
	"chalk": {"name": "Chalk", "about": "Pale, dusty chalk with specks of paper showing through."},
	"rope": {"name": "Rope", "about": "A twisted cord, its strands running across the line."},
	"beads": {"name": "Beads", "about": "A string of tiny round, shiny beads."},
	"holographic": {"name": "Holographic", "about": "Rainbow bands slide over the paint as the light moves."},
}
const STARTING_LINE_FINISHES := ["metal"]

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
const HUE_ORDER := ["red", "orange", "yellow", "green", "teal", "blue", "purple", "pink", "brown", "neutral",
		"shimmer"]

static var _finishes := {}


## Every gem color, parsed: [{id, name, color, hue, finish}]; finish is ""
## for plain gems (see EXTRA_COLORS' shimmer stones).
static func all_colors() -> Array:
	var out := Palettes.starter_gems()
	for g in out:
		g["hue"] = HUES.get(g["id"], "neutral")
		g["finish"] = ""
	for g in EXTRA_COLORS:
		out.append({"id": g["id"], "name": g["name"], "color": Color(g["color"]), "hue": g["hue"],
				"finish": g.get("finish", "")})
	return out


## A gem color's special finish ("opal", "moonstone", "labradorite",
## "nacre" or "aurora"), or "" for a plain gem or an unknown id.
static func finish_of(gem_id: String) -> String:
	if _finishes.is_empty():
		for g in EXTRA_COLORS:
			if g.has("finish"):
				_finishes[g["id"]] = g["finish"]
	return _finishes.get(gem_id, "")


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
	return colors_of(THEMES.get(theme_id, THEMES["rainbow"])["gems"])


## Gem colors' colors, in order (for her own color stories too).
static func colors_of(gems: Array) -> PackedColorArray:
	var out := PackedColorArray()
	for gem_id: String in gems:
		out.append(color_of(gem_id))
	return out


static func theme_name(theme_id: String) -> String:
	return THEMES.get(theme_id, {"name": theme_id.capitalize()})["name"]


static func puzzle_name(type_id: String) -> String:
	return PUZZLES.get(type_id, PHOTO_MODES.get(type_id, {"name": type_id.capitalize()}))["name"]


## The collage picture a kit is made from (a request's or meta's `picture`):
## kits from before every picture could be a kit have none and are mandalas.
static func kit_picture(request: Dictionary) -> String:
	var picture: String = str(request.get("picture", KIT_PICTURE))
	return picture if PUZZLES.has(picture) and not PUZZLES[picture].get("kit", false) else KIT_PICTURE


## A puzzle's name from its request or meta: kits say which picture they are
## ("Butterfly diamond kit"), apart from the original mandala ones.
static func puzzle_title(request: Dictionary) -> String:
	var type_id: String = str(request.get("type", "mandala"))
	if PUZZLES.get(type_id, {}).get("kit", false):
		var picture := kit_picture(request)
		if picture != KIT_PICTURE:
			return "%s diamond kit" % PUZZLES[picture]["source"]
	return puzzle_name(type_id)


## Collage pictures she can make a kit from: every unlocked one, once kits
## are unlocked (none before).
static func kit_pictures(unlocks: Dictionary) -> Array:
	var unlocked := unlocked_puzzles(unlocks)
	if not unlocked.any(func(t: String) -> bool: return PUZZLES[t].get("kit", false)):
		return []
	return unlocked.filter(func(t: String) -> bool: return not PUZZLES[t].get("kit", false))


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

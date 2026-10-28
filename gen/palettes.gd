class_name Palettes
extends RefCounted
## Color data the generators need before the full gem database exists.
##
## STARTER_GEMS stands in for the ~24 basic gem colors she owns at the start;
## once GemDB loads GemColor resources, pass those to the generators instead
## (any Array of {"id", "color"} dictionaries works).

const STARTER_GEMS := [
	{"id": "snow", "name": "Snow", "color": "#f7f5f2"},
	{"id": "silver", "name": "Silver", "color": "#b9bcc4"},
	{"id": "slate", "name": "Slate", "color": "#5d6370"},
	{"id": "onyx", "name": "Onyx", "color": "#1f1d24"},
	{"id": "ruby", "name": "Ruby", "color": "#c3172f"},
	{"id": "cherry_blossom", "name": "Cherry Blossom", "color": "#f6b8c8"},
	{"id": "rose", "name": "Rose", "color": "#e8517d"},
	{"id": "coral", "name": "Coral", "color": "#f47a5b"},
	{"id": "tangerine", "name": "Tangerine", "color": "#f28b1c"},
	{"id": "peach", "name": "Peach", "color": "#fbc79a"},
	{"id": "sunflower", "name": "Sunflower", "color": "#f9cf2a"},
	{"id": "butter", "name": "Butter", "color": "#fbeaa0"},
	{"id": "leaf", "name": "Leaf", "color": "#5aa83c"},
	{"id": "mint", "name": "Mint", "color": "#a8e3c0"},
	{"id": "forest", "name": "Forest", "color": "#22603a"},
	{"id": "sea_glass", "name": "Sea Glass", "color": "#5cc3b5"},
	{"id": "sky", "name": "Sky", "color": "#7cc4f2"},
	{"id": "sapphire", "name": "Sapphire", "color": "#1f4fb8"},
	{"id": "midnight", "name": "Midnight", "color": "#1b2350"},
	{"id": "lavender", "name": "Lavender", "color": "#c3a8e8"},
	{"id": "amethyst", "name": "Amethyst", "color": "#7b3fb0"},
	{"id": "chocolate", "name": "Chocolate", "color": "#5a3422"},
	{"id": "caramel", "name": "Caramel", "color": "#b07a45"},
	{"id": "sand", "name": "Sand", "color": "#dcc49a"},
]

## Theme palettes for generated pictures. Order matters: rings and region
## groups walk the list, so neighbors in the list should look good together.
const THEMES := {
	"sunset": ["#f9cf2a", "#f28b1c", "#e8517d", "#7b3fb0", "#f6b8c8", "#c3172f"],
	"ocean": ["#1f4fb8", "#5cc3b5", "#7cc4f2", "#f7f5f2", "#1b2350", "#a8e3c0"],
	"garden": ["#5aa83c", "#f6b8c8", "#f9cf2a", "#22603a", "#e8517d", "#a8e3c0"],
	"berry": ["#7b3fb0", "#e8517d", "#c3a8e8", "#c3172f", "#f6b8c8", "#1b2350"],
	"pastel": ["#f6b8c8", "#c3a8e8", "#a8e3c0", "#fbeaa0", "#7cc4f2", "#fbc79a"],
	"celestial": ["#1b2350", "#f9cf2a", "#c3a8e8", "#1f4fb8", "#f7f5f2", "#7b3fb0"],
	"autumn": ["#b07a45", "#f28b1c", "#c3172f", "#f9cf2a", "#5a3422", "#dcc49a"],
}


static func theme_colors(theme_name: String) -> PackedColorArray:
	var out := PackedColorArray()
	for hex in THEMES.get(theme_name, THEMES["sunset"]):
		out.append(Color(hex))
	return out


static func theme_names() -> PackedStringArray:
	return PackedStringArray(THEMES.keys())


## STARTER_GEMS with their colors parsed, in the shape the generators expect.
static func starter_gems() -> Array:
	var out := []
	for g in STARTER_GEMS:
		out.append({"id": g["id"], "name": g["name"], "color": Color(g["color"])})
	return out

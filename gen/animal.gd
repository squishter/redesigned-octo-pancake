class_name AnimalGenerator
extends RefCounted
## Seeded animals seen from the side: four-legged silhouettes built from a
## few dozen "genes" (body height, chest, hips, back slope, hump, belly, leg
## length and thickness, hock bend, neck length and angle, head size, snout
## length, trunk, ear size, tail length, droop and curl...) plus parts (ears,
## horns, tail, mane, feet), wearing a coat (CoatPatterns: tiger stripes, cow
## patches, leopard rosettes, giraffe net, dapples...) and markings (socks,
## hooves, a blaze, a tail tip). Nothing is symmetric: the animal faces left
## or right, its legs stride, and its coat is its own.
##
## SPECIES are starting points: each is a set of genes and the coats and
## markings that suit it, jittered a little every time. "wild" blends two
## species gene by gene into an animal that never was, in any coat. Any gene
## can be set outright with the `genes` option.
##
## The picture is made of shapes in depth layers, back to front (LAYERS: far
## legs and far ear; horns and long hair; the body; near legs, mane and
## floppy ears; inner ears, blaze and tail tuft; the eye). Each shape is a
## signed distance field; a layer's shapes melt into each other (a smooth
## union), and a layer's outline is drawn wherever it lies over a layer
## behind it, so a near leg shows its thigh against the body, a mane its
## edge against the neck. The outermost outline is the silhouette. Coat
## markings are a field too, their outline clipped to the animal, and every
## line ends on another, so every region is closed (see FieldLines).
##
## Like a swirl, every line and the areas inside belong to a family (the
## coat, the markings, hair, horns, hooves, the eye...), so a collage gives
## all of the coat one pattern and colors, and all the markings another.
##
## Output matches MandalaGenerator: polylines in unit space (-1..1, y down),
## plus "families" (an id per polyline), "family_names" (by id) and "marks"
## ([{"at": unit-space point, "family": id}], points inside areas).

## Genes every animal has, with the range a wild animal may take. Lengths are
## in body lengths (the torso is 1 long), angles in degrees.
const GENE_RANGES := {
	"body_h": [0.26, 0.72],  # torso height
	"chest": [0.75, 1.3],  # chest end's thickness, x body_h
	"hips": [0.75, 1.3],  # rump end's thickness, x body_h
	"arch": [-0.08, 0.12],  # back rises in the middle (negative sags)
	"slope": [-0.15, 0.45],  # shoulders higher than hips, x body_h
	"hump": [0.0, 0.4],  # a hump on the back (camel, bison)
	"hump_at": [-0.4, 0.5],  # where along the back, -0.5 rump .. 0.5 chest
	"belly": [0.0, 0.14],  # belly hangs down
	"leg_len": [0.15, 1.25],
	"leg_w": [0.03, 0.12],  # leg radius at the knee
	"thigh": [0.6, 0.95],  # thigh and shoulder size, x the body's radius
	"taper": [0.55, 1.1],  # foot radius, x leg_w
	"hock": [0.0, 1.0],  # hind leg's zigzag (0 straight like an elephant's)
	"neck_len": [0.03, 1.2],
	"neck_angle": [-10.0, 75.0],  # above level
	"neck_w": [0.5, 1.0],  # neck thickness, x the chest's
	"head": [0.08, 0.24],  # skull radius
	"snout": [0.25, 2.6],  # snout length, x the skull radius
	"snout_w": [0.4, 0.95],  # snout tip thickness, x the skull's
	"head_tilt": [-10.0, 70.0],  # nose below level
	"trunk": [0.0, 0.9],
	"ear_size": [0.5, 1.8],
	"tail_len": [0.1, 1.0],
	"tail_droop": [-40.0, 90.0],  # below level, pointing back
	"tail_curl": [-1.0, 1.0],
	"tail_w": [0.02, 0.06],
}
const BASE_GENES := {
	"body_h": 0.42, "chest": 1.0, "hips": 1.0, "arch": 0.0, "slope": 0.0, "hump": 0.0, "hump_at": 0.0, "belly": 0.04,
	"leg_len": 0.55, "leg_w": 0.05, "thigh": 0.8, "taper": 0.75, "hock": 0.6, "neck_len": 0.3, "neck_angle": 40.0,
	"neck_w": 0.75, "head": 0.12, "snout": 1.2, "snout_w": 0.6, "head_tilt": 25.0, "trunk": 0.0, "ear_size": 1.0,
	"tail_len": 0.5, "tail_droop": 40.0, "tail_curl": 0.0, "tail_w": 0.035,
	"feet": "paw", "ears": "pointed", "horns": "none", "tail": "long", "mane": "none",
}
const FEET := ["paw", "hoof", "pad"]
const EARS := ["pointed", "round", "small", "long", "floppy", "fan", "none"]
const HORNS := ["none", "curved", "straight", "antlers", "ossicones", "ram", "nose"]
const TAILS := ["long", "tuft", "bushy", "hair", "short", "puff", "curly", "none"]
const MANES := ["none", "horse", "crest", "lion"]
const POSES := ["stand", "walk", "graze"]
## none: the animal alone; field: a square board with a horizon behind the
## animal (and sometimes a sun); round: the same in a circle.
const SCENES := ["none", "field", "round"]
const SCENE_WEIGHTS := {"none": 0.45, "field": 0.35, "round": 0.2}
const MARKINGS := ["socks", "blaze", "tail_tip"]

## Species: genes that differ from BASE_GENES, the coats that suit them, and
## how likely each marking is.
const SPECIES := {
	"cat": {"genes": {"body_h": 0.36, "chest": 0.95, "leg_len": 0.42, "leg_w": 0.04, "thigh": 0.85, "hock": 0.7,
			"neck_len": 0.1, "neck_angle": 30.0, "neck_w": 0.8, "head": 0.14, "snout": 0.45, "snout_w": 0.7,
			"head_tilt": 10.0, "ear_size": 0.95, "tail_len": 0.85, "tail_droop": -20.0, "tail_curl": 0.6,
			"tail_w": 0.03},
			"coats": ["tiger", "solid", "pinto", "cow", "countershade"], "socks": 0.3, "tail_tip": 0.15},
	"tiger": {"genes": {"body_h": 0.4, "leg_len": 0.45, "leg_w": 0.055, "thigh": 0.85, "hock": 0.65,
			"neck_len": 0.12, "neck_angle": 25.0, "neck_w": 0.85, "head": 0.13, "snout": 0.6, "snout_w": 0.75,
			"head_tilt": 15.0, "ears": "round", "ear_size": 0.6, "tail_len": 0.8, "tail_droop": 35.0, "tail_curl": 0.3,
			"tail_w": 0.035},
			"coats": ["tiger"]},
	"lion": {"genes": {"body_h": 0.42, "leg_len": 0.48, "leg_w": 0.058, "thigh": 0.85, "hock": 0.6,
			"neck_len": 0.14, "neck_angle": 30.0, "neck_w": 0.85, "head": 0.13, "snout": 0.7, "snout_w": 0.75,
			"head_tilt": 15.0, "ears": "round", "ear_size": 0.6, "tail": "tuft", "tail_len": 0.75, "tail_droop": 45.0,
			"tail_curl": 0.5, "tail_w": 0.032, "mane": "lion"},
			"coats": ["solid", "countershade"]},
	"cheetah": {"genes": {"body_h": 0.33, "chest": 1.1, "hips": 0.9, "arch": 0.05, "leg_len": 0.62, "leg_w": 0.036,
			"thigh": 0.8, "hock": 0.7, "neck_len": 0.16, "neck_angle": 30.0, "neck_w": 0.75, "head": 0.1,
			"snout": 0.6, "snout_w": 0.75, "head_tilt": 10.0, "ears": "small", "ear_size": 0.7, "tail_len": 0.85,
			"tail_droop": 55.0, "tail_curl": -0.5, "tail_w": 0.03},
			"coats": ["cheetah", "leopard", "dalmatian"], "tail_tip": 0.3},
	"leopard": {"genes": {"body_h": 0.38, "leg_len": 0.4, "leg_w": 0.048, "thigh": 0.85, "hock": 0.65,
			"neck_len": 0.12, "neck_angle": 25.0, "neck_w": 0.85, "head": 0.12, "snout": 0.55, "snout_w": 0.75,
			"head_tilt": 10.0, "ears": "round", "ear_size": 0.6, "tail_len": 0.9, "tail_droop": 40.0,
			"tail_curl": -0.6, "tail_w": 0.032},
			"coats": ["leopard", "cheetah"]},
	"horse": {"genes": {"body_h": 0.45, "chest": 1.05, "hips": 1.05, "arch": -0.03, "leg_len": 0.72, "leg_w": 0.042,
			"thigh": 0.8, "taper": 0.85, "hock": 0.8, "neck_len": 0.45, "neck_angle": 55.0, "neck_w": 0.75,
			"head": 0.1, "snout": 2.4, "snout_w": 0.62, "head_tilt": 60.0, "ear_size": 0.8, "tail": "hair",
			"tail_len": 0.6, "tail_droop": 70.0, "tail_curl": 0.1, "tail_w": 0.04, "feet": "hoof", "mane": "horse"},
			"coats": ["solid", "solid", "pinto", "dapple", "appaloosa"], "socks": 0.6, "blaze": 0.55},
	"zebra": {"genes": {"body_h": 0.46, "chest": 1.05, "hips": 1.05, "leg_len": 0.6, "leg_w": 0.045, "thigh": 0.8,
			"taper": 0.85, "hock": 0.75, "neck_len": 0.38, "neck_angle": 50.0, "neck_w": 0.8, "head": 0.105,
			"snout": 2.1, "snout_w": 0.65, "head_tilt": 55.0, "ear_size": 1.1, "tail": "tuft", "tail_len": 0.55,
			"tail_droop": 75.0, "tail_w": 0.03, "feet": "hoof", "mane": "crest"},
			"coats": ["zebra"]},
	"donkey": {"genes": {"body_h": 0.46, "leg_len": 0.52, "leg_w": 0.045, "thigh": 0.8, "taper": 0.85, "hock": 0.7,
			"neck_len": 0.3, "neck_angle": 45.0, "neck_w": 0.8, "head": 0.11, "snout": 1.9, "snout_w": 0.7,
			"head_tilt": 50.0, "ears": "long", "ear_size": 1.3, "tail": "tuft", "tail_len": 0.5, "tail_droop": 80.0,
			"tail_w": 0.03, "feet": "hoof", "mane": "crest"},
			"coats": ["solid", "countershade", "saddle"], "socks": 0.2},
	"cow": {"genes": {"body_h": 0.55, "hips": 0.95, "arch": -0.02, "belly": 0.08, "leg_len": 0.42, "leg_w": 0.055,
			"thigh": 0.75, "taper": 0.85, "hock": 0.5, "neck_len": 0.2, "neck_angle": 15.0, "neck_w": 0.85,
			"head": 0.12, "snout": 1.6, "snout_w": 0.78, "head_tilt": 50.0, "ear_size": 0.7, "horns": "curved",
			"tail": "tuft", "tail_len": 0.6, "tail_droop": 82.0, "tail_w": 0.03, "feet": "hoof"},
			"coats": ["cow", "cow", "pinto", "solid", "saddle"], "socks": 0.25, "blaze": 0.25},
	"pig": {"genes": {"body_h": 0.55, "chest": 0.95, "belly": 0.08, "leg_len": 0.25, "leg_w": 0.055, "thigh": 0.75,
			"taper": 0.8, "hock": 0.35, "neck_len": 0.05, "neck_angle": 10.0, "neck_w": 0.95, "head": 0.15,
			"snout": 1.1, "snout_w": 0.72, "head_tilt": 15.0, "ears": "floppy", "ear_size": 0.8, "tail": "curly",
			"tail_len": 0.22, "tail_droop": 0.0, "tail_curl": 1.0, "tail_w": 0.022, "feet": "hoof"},
			"coats": ["solid", "cow", "saddle", "dalmatian"]},
	"sheep": {"genes": {"body_h": 0.6, "chest": 1.05, "belly": 0.06, "leg_len": 0.36, "leg_w": 0.035, "thigh": 0.7,
			"taper": 0.85, "hock": 0.5, "neck_len": 0.15, "neck_angle": 35.0, "neck_w": 0.75, "head": 0.1,
			"snout": 1.3, "snout_w": 0.7, "head_tilt": 45.0, "ears": "floppy", "ear_size": 0.7, "tail": "short",
			"tail_len": 0.15, "tail_droop": 60.0, "feet": "hoof"},
			"coats": ["solid", "countershade", "pinto"]},
	"ram": {"genes": {"body_h": 0.56, "chest": 1.05, "belly": 0.05, "leg_len": 0.4, "leg_w": 0.038, "thigh": 0.7,
			"taper": 0.85, "hock": 0.5, "neck_len": 0.16, "neck_angle": 35.0, "neck_w": 0.8, "head": 0.11,
			"snout": 1.3, "snout_w": 0.7, "head_tilt": 40.0, "ears": "small", "ear_size": 0.7, "horns": "ram",
			"tail": "short", "tail_len": 0.15, "tail_droop": 60.0, "feet": "hoof"},
			"coats": ["solid", "countershade"]},
	"goat": {"genes": {"body_h": 0.44, "leg_len": 0.5, "leg_w": 0.035, "thigh": 0.75, "taper": 0.85, "hock": 0.7,
			"neck_len": 0.28, "neck_angle": 50.0, "neck_w": 0.7, "head": 0.1, "snout": 1.6, "snout_w": 0.6,
			"head_tilt": 45.0, "ears": "long", "ear_size": 0.8, "horns": "straight", "tail": "short", "tail_len": 0.14,
			"tail_droop": -30.0, "feet": "hoof"},
			"coats": ["solid", "pinto", "saddle", "countershade"], "socks": 0.2},
	"dog": {"genes": {"body_h": 0.38, "leg_len": 0.5, "leg_w": 0.045, "thigh": 0.8, "hock": 0.65, "neck_len": 0.22,
			"neck_angle": 45.0, "neck_w": 0.75, "head": 0.12, "snout": 1.3, "snout_w": 0.62, "head_tilt": 20.0,
			"ears": "floppy", "ear_size": 1.0, "tail_len": 0.45, "tail_droop": -10.0, "tail_curl": 0.3},
			"coats": ["dalmatian", "solid", "pinto", "countershade", "saddle"], "socks": 0.3, "blaze": 0.2,
			"tail_tip": 0.2},
	"dachshund": {"genes": {"body_h": 0.3, "chest": 1.1, "leg_len": 0.17, "leg_w": 0.04, "thigh": 0.8, "hock": 0.4,
			"neck_len": 0.16, "neck_angle": 40.0, "neck_w": 0.75, "head": 0.1, "snout": 1.6, "snout_w": 0.55,
			"head_tilt": 15.0, "ears": "floppy", "ear_size": 1.3, "tail_len": 0.45, "tail_droop": 20.0,
			"tail_curl": -0.2, "tail_w": 0.028},
			"coats": ["solid", "countershade", "dapple"]},
	"fox": {"genes": {"body_h": 0.32, "leg_len": 0.42, "leg_w": 0.033, "thigh": 0.8, "hock": 0.7, "neck_len": 0.16,
			"neck_angle": 35.0, "neck_w": 0.75, "head": 0.105, "snout": 1.6, "snout_w": 0.45, "head_tilt": 10.0,
			"ear_size": 1.3, "tail": "bushy", "tail_len": 0.75, "tail_droop": 30.0, "tail_curl": -0.3,
			"tail_w": 0.03},
			"coats": ["countershade", "solid"], "socks": 0.5, "tail_tip": 0.85},
	"wolf": {"genes": {"body_h": 0.38, "leg_len": 0.55, "leg_w": 0.04, "thigh": 0.8, "hock": 0.7, "neck_len": 0.2,
			"neck_angle": 30.0, "neck_w": 0.85, "head": 0.12, "snout": 1.45, "snout_w": 0.55, "head_tilt": 15.0,
			"ear_size": 1.0, "tail": "bushy", "tail_len": 0.55, "tail_droop": 65.0, "tail_w": 0.03},
			"coats": ["countershade", "saddle", "solid"], "tail_tip": 0.3},
	"deer": {"genes": {"body_h": 0.4, "arch": 0.02, "leg_len": 0.78, "leg_w": 0.03, "thigh": 0.8, "taper": 0.85,
			"hock": 0.8, "neck_len": 0.4, "neck_angle": 60.0, "neck_w": 0.7, "head": 0.1, "snout": 1.6,
			"snout_w": 0.5, "head_tilt": 45.0, "ear_size": 1.2, "horns": "antlers", "tail": "short",
			"tail_len": 0.12, "tail_droop": -20.0, "feet": "hoof"},
			"coats": ["countershade", "dalmatian", "solid"]},
	"giraffe": {"genes": {"body_h": 0.45, "slope": 0.35, "leg_len": 1.1, "leg_w": 0.036, "thigh": 0.8, "taper": 0.85,
			"hock": 0.7, "neck_len": 1.05, "neck_angle": 68.0, "neck_w": 0.55, "head": 0.09, "snout": 1.8,
			"snout_w": 0.55, "head_tilt": 55.0, "ear_size": 0.8, "horns": "ossicones", "tail": "tuft",
			"tail_len": 0.5, "tail_droop": 80.0, "tail_w": 0.022, "feet": "hoof", "mane": "crest"},
			"coats": ["giraffe"]},
	"elephant": {"genes": {"body_h": 0.68, "chest": 1.05, "arch": 0.04, "leg_len": 0.55, "leg_w": 0.11, "taper": 1.05,
			"thigh": 0.7, "hock": 0.08, "neck_len": 0.05, "neck_angle": 10.0, "neck_w": 0.9, "head": 0.17,
			"snout": 0.4, "snout_w": 0.8, "head_tilt": 65.0, "trunk": 0.75, "ears": "fan", "ear_size": 1.25,
			"tail": "tuft", "tail_len": 0.35, "tail_droop": 82.0, "tail_w": 0.02, "feet": "pad"},
			"coats": ["solid"]},
	"rhino": {"genes": {"body_h": 0.6, "belly": 0.06, "leg_len": 0.35, "leg_w": 0.09, "taper": 1.0, "thigh": 0.75,
			"hock": 0.2, "neck_len": 0.08, "neck_angle": 15.0, "neck_w": 0.95, "head": 0.16, "snout": 1.5,
			"snout_w": 0.8, "head_tilt": 30.0, "ear_size": 0.7, "horns": "nose", "tail": "tuft", "tail_len": 0.25,
			"tail_droop": 85.0, "tail_w": 0.02, "feet": "pad"},
			"coats": ["solid"]},
	"bear": {"genes": {"body_h": 0.55, "hump": 0.14, "hump_at": 0.3, "leg_len": 0.38, "leg_w": 0.07, "taper": 0.9,
			"thigh": 0.8, "hock": 0.25, "neck_len": 0.12, "neck_angle": 15.0, "neck_w": 0.9, "head": 0.14,
			"snout": 0.95, "snout_w": 0.6, "head_tilt": 15.0, "ears": "round", "ear_size": 0.6, "tail": "short",
			"tail_len": 0.1, "tail_droop": 40.0},
			"coats": ["solid", "countershade"]},
	"rabbit": {"genes": {"body_h": 0.6, "chest": 0.8, "hips": 1.2, "arch": 0.1, "leg_len": 0.2, "leg_w": 0.04,
			"thigh": 0.85, "hock": 0.5, "neck_len": 0.05, "neck_angle": 40.0, "neck_w": 0.8, "head": 0.16,
			"snout": 0.55, "snout_w": 0.7, "head_tilt": 20.0, "ears": "long", "ear_size": 1.5, "tail": "puff",
			"tail_len": 0.1},
			"coats": ["solid", "pinto", "countershade", "dapple"]},
	"camel": {"genes": {"body_h": 0.42, "hump": 0.36, "hump_at": -0.02, "leg_len": 0.85, "leg_w": 0.04,
			"thigh": 0.75, "hock": 0.6, "neck_len": 0.55, "neck_angle": 22.0, "neck_w": 0.6, "head": 0.1,
			"snout": 1.6, "snout_w": 0.7, "head_tilt": 15.0, "ears": "small", "ear_size": 0.6, "tail": "tuft",
			"tail_len": 0.35, "tail_droop": 80.0, "tail_w": 0.022, "feet": "pad"},
			"coats": ["solid", "countershade"]},
}
## Species used by this many previous animals in a row are skipped; coats
## skip fewer, since some species have only one.
const AVOID_RECENT := 4
const AVOID_RECENT_COATS := 2
## How far genes stray from their species (a fraction of their range), and
## how far a wild animal's do.
const JITTER := 0.06
const WILD_JITTER := 0.12
## Grid cells a side for the fields (see FieldLines).
const N := 320
## Smooth union radius within a layer, in body lengths.
const MELT := 0.05
## How far (body lengths) parts blend their stripe flow, and how near a part
## a cell must be to count.
const FLOW_SOFT := 0.025
const FLOW_REACH := 0.09
const BIG := 10.0
## How far (unit space) a mark in a thin area must be from its edge: past
## half a line's width.
const TIGHT := 0.0085

## Depth layers, back to front.
enum { FAR, BEHIND, BODY, FRONT, DETAIL, EYE }
const LAYERS := 6
const LAYER_FAMILIES := ["far", "behind", "body", "front", "detail", "eye"]
## Layers that never carry coat markings (FRONT carries them on legs only).
const PLAIN_LAYERS := [BEHIND, DETAIL, EYE]

var rng := RandomNumberGenerator.new()
var genes := {}
var polylines: Array[PackedVector2Array] = []
var closed := PackedByteArray()
var families := PackedInt32Array()
var family_names := PackedStringArray()
var marks := []

## Parts: {"layer", "pattern" (bool: takes coat markings), "family" (the
## area's family when it doesn't), "taper" (stripes thin toward v > 0),
## "prims"}. A prim is {"kind": "cap" | "ell", "a", "b", "ra", "rb", "u0",
## "phi0", "sign"} or {"kind": "ell", "c", "r" (Vector2), "rot", "phi0"}.
var _parts := []
## Bands across legs and tails: {"part", "layer", "c", "n" (toward the
## end), "family", "width"}.
var _bands := []
var _coat: CoatPatterns
var _coat_seed := 0
var _coat_bounds := Rect2()
var _coat_body := {}
## Animal space to unit space: unit = (animal * (fx, 1)) * s + off.
var _s := 1.0
var _off := Vector2.ZERO
var _fx := 1.0
## Fields on the grid: per layer, inside positive (unit space distance).
var _layer := []
var _total := PackedFloat32Array()
var _marking := PackedFloat32Array()
var _marking2 := PackedFloat32Array()
var _box := Rect2i()
## Scene: the board's outline, the horizon's height, the sun.
var _scene := "none"
var _horizon := []
var _sun := Vector3.ZERO  # x, y, radius (radius 0: none)
## Points the build keeps for later: the torso, ground, eye...
var _at := {}
## The markings that found a place (socks, blaze, tail_tip).
var _markings := []


## options:
##   species: one of SPECIES, "wild" (a blend of two) or "random" (default)
##   coat: one of CoatPatterns.COATS, or "random" (default: one that suits
##         the species; any for wild animals)
##   pose: one of POSES or "random"; facing: "left", "right" or "random"
##   scene: one of SCENES or "random"
##   markings: Array of MARKINGS to force, or omit for the species' chances
##   genes: Dictionary of genes to set outright (see GENE_RANGES, plus
##          "feet", "ears", "horns", "tail", "mane")
##   wildness: 0..1 (default 0), how far genes stray from the species
##   recent: Array of earlier results' {"species", "coat"}; recent choices
##           are skipped and the least used preferred
## Returns {"seed", "species", "blend" (the second species of a wild one, or
## ""), "coat", "pose", "facing", "scene", "feet", "ears", "horns", "tail",
## "mane", "markings", "polylines", "closed", "families", "family_names",
## "marks"}.
static func generate(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var g := AnimalGenerator.new()
	g.rng.seed = seed_value
	var recent: Array = options.get("recent", [])
	var species: String = options.get("species", "random")
	if species != "wild" and not SPECIES.has(species):
		species = g._least_used(SPECIES.keys(), _recent_of(recent, "species"), AVOID_RECENT)
	var blend := ""
	var suits := []
	var wildness: float = clampf(options.get("wildness", 0.0), 0.0, 1.0)
	if species == "wild":
		var names: Array = SPECIES.keys()
		var a: String = names[g.rng.randi_range(0, names.size() - 1)]
		names.erase(a)
		blend = names[g.rng.randi_range(0, names.size() - 1)]
		g._blend_genes(a, blend, g.rng.randf_range(0.3, 0.7))
		species = a
		suits = CoatPatterns.COATS
		wildness = maxf(wildness, 0.5)
	else:
		g.genes = BASE_GENES.duplicate()
		g.genes.merge(SPECIES[species]["genes"], true)
		suits = SPECIES[species]["coats"]
	g._jitter(lerpf(JITTER, WILD_JITTER * 2.0, wildness))
	var forced: Dictionary = options.get("genes", {})
	for key in forced:
		if g.genes.has(key):
			g.genes[key] = forced[key]

	var coat: String = options.get("coat", "random")
	if not coat in CoatPatterns.COATS:
		var pool := suits.duplicate()
		if wildness > 0.0 and g.rng.randf() < wildness * 0.5:
			pool = CoatPatterns.COATS
		coat = g._least_used(pool, _recent_of(recent, "coat"), AVOID_RECENT_COATS)
	var pose: String = options.get("pose", "random")
	if not pose in POSES:
		pose = "walk" if g.rng.randf() < 0.4 else "stand"
		if g.genes["neck_len"] >= 0.3 and g.rng.randf() < 0.15:
			pose = "graze"
	var facing: String = options.get("facing", "random")
	if not facing in ["left", "right"]:
		facing = "left" if g.rng.randf() < 0.5 else "right"
	var scene: String = options.get("scene", "random")
	if not scene in SCENES:
		scene = g._pick(SCENE_WEIGHTS)
	var markings := []
	if options.has("markings"):
		markings = options["markings"].filter(func(m: String) -> bool: return m in MARKINGS)
	else:
		var info: Dictionary = SPECIES.get(species, {})
		for m: String in MARKINGS:
			var chance: float = info.get(m, 0.0)
			if blend != "":
				chance = maxf(chance, SPECIES[blend].get(m, 0.0)) * 0.7
			if g.rng.randf() < chance:
				markings.append(m)
	if not g.genes["feet"] in FEET:
		g.genes["feet"] = "paw"

	g._build(pose, markings)
	g._fit(facing, scene)
	g._make_coat(coat, seed_value)
	g._fields()
	g._draw()
	g._mark()
	return {
		"seed": seed_value,
		"species": species,
		"blend": blend,
		"coat": coat,
		"pose": pose,
		"facing": facing,
		"scene": scene,
		"feet": g.genes["feet"],
		"ears": g.genes["ears"],
		"horns": g.genes["horns"],
		"tail": g.genes["tail"],
		"mane": g.genes["mane"],
		"markings": g._markings,
		"polylines": g.polylines,
		"closed": g.closed,
		"families": g.families,
		"family_names": g.family_names,
		"marks": g.marks,
	}


# --- choosing ------------------------------------------------------------------------

## Every value of `key` in the recent results, in order.
static func _recent_of(recent: Array, key: String) -> Array:
	var out := []
	for r in recent:
		if r is Dictionary and r.has(key):
			out.append(r[key])
	return out


## A name from `names`, skipping the last `avoid` of `recent` and preferring
## the least used.
func _least_used(names: Array, recent: Array, avoid: int) -> String:
	var skip := recent.slice(maxi(0, recent.size() - avoid))
	var choices := []
	var fewest := recent.size() + 1
	for n in names:
		if n in skip:
			continue
		var uses := recent.count(n)
		if uses < fewest:
			fewest = uses
			choices.clear()
		if uses == fewest:
			choices.append(n)
	if choices.is_empty():
		choices = names
	return choices[rng.randi_range(0, choices.size() - 1)]


func _pick(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var x := rng.randf() * total
	for k in weights:
		x -= weights[k]
		if x <= 0.0:
			return k
	return weights.keys()[0]


## Genes partway between two species (`t` toward b); each part (ears, tail,
## horns...) comes from one or the other.
func _blend_genes(a: String, b: String, t: float) -> void:
	var ga := BASE_GENES.duplicate()
	ga.merge(SPECIES[a]["genes"], true)
	var gb := BASE_GENES.duplicate()
	gb.merge(SPECIES[b]["genes"], true)
	genes = {}
	for key in ga:
		if GENE_RANGES.has(key):
			genes[key] = lerpf(ga[key], gb[key], t)
		else:
			genes[key] = ga[key] if rng.randf() < 0.5 else gb[key]


## Every gene strays by up to `amount` of its range, staying in range.
func _jitter(amount: float) -> void:
	for key: String in GENE_RANGES:
		var r: Array = GENE_RANGES[key]
		var v: float = genes[key] + rng.randf_range(-1.0, 1.0) * amount * (r[1] - r[0])
		genes[key] = clampf(v, r[0], r[1])
	# Trunks, humps and arches stay off unless the species has them.
	if genes["trunk"] < 0.1:
		genes["trunk"] = 0.0
	if genes["hump"] < 0.05:
		genes["hump"] = 0.0


# --- building -------------------------------------------------------------------------

func _part(layer: int, pattern: bool, family := "coat", taper := 0.0) -> Dictionary:
	var p := {"layer": layer, "pattern": pattern, "family": family, "taper": taper, "prims": []}
	_parts.append(p)
	return p


## A chain of tapered capsules through `pts` with `radii`; its stripe flow
## starts at phi0 and runs `sign` along it.
func _chain(part: Dictionary, pts: PackedVector2Array, radii: PackedFloat32Array, phi0: float, sign := 1.0) -> void:
	var u := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		part["prims"].append({"kind": "cap", "a": a, "b": b, "ra": maxf(0.02, radii[i]),
				"rb": maxf(0.02, radii[i + 1]), "u0": u, "phi0": phi0, "sign": sign})
		u += a.distance_to(b)


func _ellipse(part: Dictionary, c: Vector2, r: Vector2, rot := 0.0) -> void:
	part["prims"].append({"kind": "ell", "c": c, "r": Vector2(maxf(0.02, r.x), maxf(0.02, r.y)), "rot": rot,
			"phi0": c.x})


## A smooth curve through control points (Catmull-Rom), `per` points a span,
## with radii eased along it.
static func _smooth(ctrl: PackedVector2Array, radii: PackedFloat32Array, per: int) -> Array:
	var pts := PackedVector2Array()
	var rs := PackedFloat32Array()
	var n := ctrl.size()
	for i in n - 1:
		var p0 := ctrl[maxi(i - 1, 0)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(i + 2, n - 1)]
		for k in per:
			var t := float(k) / per
			pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
			rs.append(lerpf(radii[i], radii[i + 1], t))
	pts.append(ctrl[n - 1])
	rs.append(radii[n - 1])
	return [pts, rs]


func _build(pose: String, markings: Array) -> void:
	var g := genes
	var h: float = g["body_h"]
	var rh: float = h * 0.5 * g["hips"]
	var rc: float = h * 0.5 * g["chest"]
	var sag: float = h * 0.5 * g["belly"]
	var rm: float = h * 0.5 + sag
	var lift: float = g["slope"] * h
	var arch: float = g["arch"] * h
	var rump := Vector2(-0.5 + rh, lift * 0.5)
	var chest := Vector2(0.5 - rc, -lift * 0.5)
	var m1 := Vector2(-0.17, lerpf(rump.y, chest.y, 0.33) - arch + sag)
	var m2 := Vector2(0.17, lerpf(rump.y, chest.y, 0.67) - arch + sag)
	var torso := _part(BODY, true, "coat", 1.0)
	_chain(torso, PackedVector2Array([rump, m1, m2, chest]), PackedFloat32Array([rh, rm, rm, rc]), rump.x)
	_at["spine"] = [[rump.x, rump.y, rh], [m1.x, m1.y, rm], [m2.x, m2.y, rm], [chest.x, chest.y, rc]]
	_at["rump"] = rump + Vector2(0.0, -rh * 0.7)
	_at["rump_r"] = rh
	if g["hump"] > 0.0:
		var hx: float = g["hump_at"] * 0.8
		var top := lerpf(rump.y - rh, chest.y - rc, inverse_lerp(rump.x, chest.x, hx)) - arch
		var ry: float = g["hump"] * 0.6
		_ellipse(torso, Vector2(hx, top + ry * 0.2), Vector2(0.15 + g["hump"] * 0.35, ry))
	var ground: float = maxf(chest.y + rc, rump.y + rh) + g["leg_len"]
	# Legs stand near the ends of the body, however deep it is.
	_at["front_x"] = minf(chest.x, 0.5 - maxf(0.16, rc * 0.55)) + rng.randf_range(-0.03, 0.02)
	_at["hind_x"] = maxf(rump.x, -0.5 + maxf(0.17, rh * 0.6)) + rng.randf_range(-0.02, 0.03)
	_at["ground"] = ground
	_at["belly"] = maxf(chest.y + rc, m2.y + rm)

	# Legs: far ones first (behind), near ones in front. Walking legs swing
	# in opposite pairs; a far leg sits a little apart so it peeks out.
	var swing := 0.0
	if pose == "walk":
		swing = deg_to_rad(rng.randf_range(12.0, 22.0))
	var lifted := rng.randi_range(0, 3) if pose == "walk" and rng.randf() < 0.7 else -1
	var legs := [[true, false, 1.0], [false, false, -1.0], [true, true, -1.0], [false, true, 1.0]]
	for i in legs.size():
		var front: bool = legs[i][0]
		var near: bool = legs[i][1]
		var angle: float = swing * legs[i][2] * (1.0 if near else 0.7) + deg_to_rad(rng.randf_range(-4.0, 4.0))
		var fold := deg_to_rad(rng.randf_range(35.0, 60.0)) if i == lifted else 0.0
		_leg(front, near, chest, rc, rump, rh, ground, angle, fold, markings)

	var tilt: float = g["head_tilt"]
	var neck_angle: float = g["neck_angle"]
	if pose == "graze":
		neck_angle = -rng.randf_range(15.0, 35.0)
		tilt = rng.randf_range(75.0, 95.0)
	_head_and_neck(chest, rc, deg_to_rad(neck_angle), deg_to_rad(tilt), markings)
	_tail(rump, rh, "tail_tip" in markings)


func _leg(front: bool, near: bool, chest: Vector2, rc: float, rump: Vector2, rh: float, ground: float, angle: float,
		fold: float, markings: Array) -> void:
	var g := genes
	var lw: float = g["leg_w"]
	var foot_r: float = lw * g["taper"]
	var feet: String = g["feet"]
	var foot_h: float = lw * (1.2 if feet == "hoof" else 0.9 if feet == "paw" else 0.5)
	var thigh: float = minf((rc * 0.85 if front else rh) * g["thigh"], 0.17 if front else 0.2) * (1.0 if near else 0.8)
	var pts := PackedVector2Array()
	var radii := PackedFloat32Array()
	var top: Vector2
	if front:
		top = Vector2(_at["front_x"] - (0.0 if near else 0.07), chest.y + rc * 0.05)
		var elbow := Vector2(top.x - 0.03, chest.y + rc * 0.85)
		var knee := Vector2(top.x - 0.01, lerpf(elbow.y, ground, 0.5))
		pts = PackedVector2Array([top, elbow, knee, Vector2(top.x, ground - foot_h)])
		radii = PackedFloat32Array([thigh, lw * 1.3, lw * 0.95, foot_r])
	else:
		var k: float = g["hock"]
		top = Vector2(_at["hind_x"] + (0.0 if near else 0.06), rump.y - rh * 0.05)
		var stifle := Vector2(top.x + 0.1 * k + 0.02, rump.y + rh * 0.7)
		var hock := Vector2(top.x - 0.05 - 0.1 * k, lerpf(stifle.y, ground, 0.55 - 0.12 * k))
		pts = PackedVector2Array([top, stifle, hock, Vector2(hock.x + 0.04 * k, ground - foot_h)])
		radii = PackedFloat32Array([thigh, lw * 1.5, lw * 0.9, foot_r])
	# The foot, below the last joint.
	var fet := pts[3]
	var foot := PackedVector2Array()
	match feet:
		"hoof":
			foot = PackedVector2Array([fet, Vector2(fet.x + lw * 0.15, ground - foot_r * 1.1)])
		"pad":
			foot = PackedVector2Array([fet, Vector2(fet.x, ground - foot_r * 1.05)])
		_:
			foot = PackedVector2Array([fet, Vector2(fet.x + lw * 0.5, ground - lw * 0.5)])
	# Swing about the top; a lifted leg folds below the knee.
	for i in range(1, pts.size()):
		pts[i] = top + (pts[i] - top).rotated(angle)
	for i in foot.size():
		foot[i] = top + (foot[i] - top).rotated(angle)
	if fold != 0.0:
		var knee := pts[2]
		pts[3] = knee + (pts[3] - knee).rotated(fold)
		for i in foot.size():
			foot[i] = knee + (foot[i] - knee).rotated(fold)
	var part := _part(FRONT if near else FAR, true)
	_chain(part, pts, radii, top.x)
	var foot_radii := PackedFloat32Array([foot_r, foot_r * (1.15 if feet == "hoof" else 1.1)])
	if feet == "paw":
		_ellipse(part, foot[1], Vector2(lw * 1.05, lw * 0.55), (foot[1] - top).angle() - PI / 2.0)
	else:
		_chain(part, foot, foot_radii, top.x + pts[0].distance_to(fet))
	var down := (foot[1] - foot[0]).normalized()
	if feet == "hoof":
		_bands.append({"part": part, "layer": part["layer"], "c": foot[0], "n": down, "family": "hooves",
				"width": foot_r})
	if "socks" in markings and rng.randf() < 0.6:
		var t := rng.randf_range(0.15, 0.7)
		var c := pts[2].lerp(pts[3], t)
		_bands.append({"part": part, "layer": part["layer"], "c": c, "n": (pts[3] - pts[2]).normalized(),
				"family": "socks", "width": lw})
		if not "socks" in _markings:
			_markings.append("socks")


func _head_and_neck(chest: Vector2, rc: float, neck_angle: float, tilt: float, markings: Array) -> void:
	var g := genes
	var hr: float = g["head"]
	var dir := Vector2(cos(neck_angle), -sin(neck_angle))
	var base := chest + Vector2(rc * 0.35, -rc * 0.45)
	var neck_len: float = g["neck_len"]
	var rn0: float = rc * g["neck_w"]
	var rn1: float = maxf(hr * 0.8, rn0 * 0.55)
	var end := base + dir * neck_len
	var neck := _part(BODY, true, "coat", 1.0)
	var perp := Vector2(-dir.y, dir.x)
	var curve := rng.randf_range(-0.06, 0.06) * neck_len
	var ctrl := PackedVector2Array([base - dir * rc * 0.3, base + dir * neck_len * 0.5 + perp * curve, end])
	var sm := _smooth(ctrl, PackedFloat32Array([rn0, lerpf(rn0, rn1, 0.55), rn1]), 4)
	_chain(neck, sm[0], sm[1], base.x)
	var head_c := end + dir * hr * 0.3
	var hdir := Vector2(cos(tilt), sin(tilt))
	var up := Vector2(hdir.y, -hdir.x)
	var head := _part(BODY, true, "coat", 1.0)
	_ellipse(head, head_c, Vector2(hr * 1.05, hr * 0.95), tilt)
	var snout_len: float = g["snout"] * hr
	var tip := head_c + hdir * snout_len - up * hr * 0.1
	var tip_r: float = hr * g["snout_w"] * 0.8
	_chain(head, PackedVector2Array([head_c, tip]), PackedFloat32Array([hr * 0.85, tip_r]), head_c.x)
	if g["trunk"] > 0.0:
		# Down from the snout, curling forward at the end.
		var trunk := PackedVector2Array([tip])
		var tr := PackedFloat32Array([tip_r])
		var a := tilt
		var length: float = g["trunk"]
		var curl := rng.randf_range(0.6, 1.4)
		for k in 6:
			var t := (k + 1) / 6.0
			a = lerpf(tilt, PI / 2.0 + 0.15, minf(1.0, t * 1.6)) - (curl * (t - 0.7) * 3.0 if t > 0.7 else 0.0)
			trunk.append(trunk[k] + Vector2(cos(a), sin(a)) * length / 6.0)
			tr.append(tip_r * lerpf(1.0, 0.5, t))
		_chain(head, trunk, tr, tip.x)
	_at["head"] = head_c
	_at["tip"] = tip

	# Ears: the near one with the head, the far one behind it, its inside on
	# top.
	var ears: String = g["ears"]
	var es: float = g["ear_size"]
	var ear_base := head_c - hdir * hr * 0.3 + up * hr * 0.8
	var back := 0.35 if ears != "long" else 0.6
	var ed := (up * cos(back) - hdir * sin(back)).normalized()
	match ears:
		"pointed", "long":
			var long := ears == "long"
			var length := hr * es * (2.3 if long else 0.95)
			var r0 := hr * es * (0.3 if long else 0.36)
			for far in [true, false]:
				var shift := -hdir * hr * 0.28 if far else Vector2.ZERO
				var d := ed.rotated(-0.18) if far else ed
				var pts := PackedVector2Array([ear_base + shift - d * hr * 0.2, ear_base + shift + d * length * 0.45,
						ear_base + shift + d * length])
				var rr := PackedFloat32Array([r0, r0 * (1.1 if long else 0.6), hr * 0.07])
				_chain(_part(FAR if far else BODY, true, "coat", 0.0), pts, rr, ear_base.x)
			var inner := _part(DETAIL, false, "inner_ear")
			_chain(inner, PackedVector2Array([ear_base + ed * length * 0.2, ear_base + ed * length * 0.72]),
					PackedFloat32Array([r0 * 0.5, r0 * 0.18]), 0.0)
		"round", "small":
			var r := hr * es * (0.36 if ears == "round" else 0.24)
			var c := ear_base + ed * r * 0.9
			_ellipse(_part(FAR, true), c - hdir * hr * 0.3, Vector2(r, r))
			_ellipse(_part(BODY, true, "coat", 0.0), c, Vector2(r, r))
			if ears == "round":
				_ellipse(_part(DETAIL, false, "inner_ear"), c + ed * r * 0.15, Vector2(r * 0.52, r * 0.52))
		"floppy":
			var down := -up
			var pts := PackedVector2Array([ear_base - hdir * hr * 0.05, ear_base - hdir * hr * 0.45 + down * hr * 0.55 * es,
					ear_base - hdir * hr * 0.5 + down * hr * 1.1 * es])
			_chain(_part(FRONT, true), pts, PackedFloat32Array([hr * 0.26, hr * 0.36 * es, hr * 0.26 * es]),
					ear_base.x)
		"fan":
			_ellipse(_part(FRONT, true), head_c - hdir * hr * 0.55 - up * hr * 0.05 + Vector2(-hr * 0.35, 0.0),
					Vector2(hr * 0.62 * es, hr * 0.85 * es), tilt - 0.3)

	_horns(head_c, hr, hdir, up, tip, tip_r)
	_mane(head_c, hr, hdir, up, base, end, rn0, rn1, dir)

	# The eye, and a blaze down the face.
	var eye_r := clampf(hr * 0.2, 0.024, 0.042)
	_at["eye"] = head_c + hdir * hr * 0.25 + up * hr * 0.32
	_ellipse(_part(EYE, false, "eye"), _at["eye"], Vector2(eye_r, eye_r))
	if "blaze" in markings and snout_len > hr * 1.1:
		var from: Vector2 = head_c + up * hr * 0.62 - hdir * hr * 0.1
		var to: Vector2 = tip + up * tip_r * 0.25
		_chain(_part(DETAIL, false, "blaze"), PackedVector2Array([from, from.lerp(to, 0.5), to]),
				PackedFloat32Array([hr * 0.2, hr * 0.15, tip_r * 0.4]), 0.0)
		_markings.append("blaze")


func _horns(head_c: Vector2, hr: float, hdir: Vector2, up: Vector2, tip: Vector2, tip_r: float) -> void:
	var horns: String = genes["horns"]
	var base := head_c - hdir * hr * 0.05 + up * hr * 0.75
	var size := rng.randf_range(0.85, 1.2)
	match horns:
		"curved", "straight":
			var part := _part(BEHIND, false, "horns")
			for far in [true, false]:
				var b := base - hdir * (hr * 0.28 if far else 0.0)
				var pts: PackedVector2Array
				if horns == "curved":
					var out := rng.randf_range(-0.2, 0.4)
					pts = PackedVector2Array([b - up * hr * 0.2, b + up * hr * 0.55 * size + hdir * hr * out,
							b + up * hr * 0.9 * size + hdir * hr * (out + 0.5) * size])
				else:
					pts = PackedVector2Array([b - up * hr * 0.2, b + (up * 1.1 - hdir * 0.5) * hr * size,
							b + (up * 1.8 - hdir * 1.5) * hr * size])
				var sm := _smooth(pts, PackedFloat32Array([hr * 0.2, hr * 0.13, hr * 0.05]), 3)
				_chain(part, sm[0], sm[1], 0.0)
		"antlers":
			var part := _part(BEHIND, false, "horns")
			for far in [true, false]:
				var b := base - hdir * (hr * 0.3 if far else 0.0)
				var turn := -0.12 if far else 0.0
				var beam := PackedVector2Array([b - up * hr * 0.2])
				var a := 0.0
				for k in 4:
					a += rng.randf_range(0.15, 0.35)
					var d := (up * cos(a) - hdir * sin(a)).rotated(turn)
					beam.append(beam[k] + d * hr * 0.75 * size)
				_chain(part, beam, PackedFloat32Array([hr * 0.17, hr * 0.14, hr * 0.11, hr * 0.08, hr * 0.06]), 0.0)
				for k in range(1, 4):
					if rng.randf() < 0.85:
						var d := (up * 0.8 + hdir * rng.randf_range(0.3, 0.9)).normalized().rotated(turn)
						_chain(part, PackedVector2Array([beam[k], beam[k] + d * hr * rng.randf_range(0.5, 0.8) * size]),
								PackedFloat32Array([hr * 0.08, hr * 0.05]), 0.0)
		"ossicones":
			var part := _part(BEHIND, false, "horns")
			for far in [true, false]:
				var b := base - hdir * (hr * 0.35 if far else 0.0)
				var top := b + (up - hdir * 0.15) * hr * 0.75 * size
				_chain(part, PackedVector2Array([b - up * hr * 0.2, top]), PackedFloat32Array([hr * 0.13, hr * 0.1]), 0.0)
				_ellipse(part, top, Vector2(hr * 0.17, hr * 0.17))
		"ram":
			var part := _part(FRONT, false, "horns")
			var c := head_c - hdir * hr * 0.4 + up * hr * 0.15
			var pts := PackedVector2Array()
			var rs := PackedFloat32Array()
			# Up from the skull, back, down and forward round the ear.
			for k in 14:
				var t := k / 13.0
				var a := t * TAU * 0.95
				var r := hr * lerpf(0.95, 0.35, t) * size
				pts.append(c + (up * cos(a) - hdir * sin(a)) * r)
				rs.append(hr * lerpf(0.3, 0.13, t))
			_chain(part, pts, rs, 0.0)
		"nose":
			var part := _part(BEHIND, false, "horns")
			var b := tip - hdir * (tip - head_c).length() * 0.25 + up * tip_r * 0.6
			_chain(part, PackedVector2Array([b, b + (up * 1.2 + hdir * 0.4) * hr * 0.6 * size,
					b + (up * 1.9 - hdir * 0.1) * hr * 0.75 * size]), PackedFloat32Array([hr * 0.36, hr * 0.18, hr * 0.05]),
					0.0)
			var b2 := b - hdir * hr * 0.75
			_chain(part, PackedVector2Array([b2, b2 + up * hr * 0.75 * size]), PackedFloat32Array([hr * 0.24, hr * 0.05]),
					0.0)


func _mane(head_c: Vector2, hr: float, hdir: Vector2, up: Vector2, base: Vector2, end: Vector2, rn0: float,
		rn1: float, dir: Vector2) -> void:
	var mane: String = genes["mane"]
	var neck_up := Vector2(dir.y, -dir.x)  # the top of the neck
	var poll := head_c - hdir * hr * 0.35 + up * hr * 0.55
	var withers := base + neck_up * rn0 * 0.8 - dir * rn0 * 0.3
	match mane:
		"horse", "crest":
			var part := _part(FRONT, false, "hair")
			var r := (rn0 + rn1) * (0.22 if mane == "horse" else 0.17)
			var lift := r * (0.35 if mane == "horse" else 0.7)
			var top := PackedVector2Array()
			var rs := PackedFloat32Array()
			for k in 6:
				var t := k / 5.0
				var n_top: Vector2 = withers.lerp(poll, t)
				top.append(n_top + neck_up * lift)
				rs.append(r * lerpf(1.0, 0.75, t))
			_chain(part, top, rs, 0.0)
			if mane == "horse":
				# Locks hanging down the near side of the neck, and a forelock.
				var count := rng.randi_range(4, 7)
				for k in count:
					var t := (k + rng.randf_range(0.2, 0.8)) / count
					var at: Vector2 = withers.lerp(poll, t)
					var fall := (-neck_up * 0.8 - dir * 0.6).normalized()
					var length := lerpf(rn0, rn1, t) * rng.randf_range(0.9, 1.5)
					_chain(part, PackedVector2Array([at, at + fall * length]), PackedFloat32Array([r * 0.9, r * 0.35]), 0.0)
				_chain(part, PackedVector2Array([poll, poll + hdir * hr * 0.75 - up * hr * 0.05]),
						PackedFloat32Array([r * 0.8, r * 0.3]), 0.0)
		"lion":
			var part := _part(BEHIND, false, "hair")
			var c := head_c.lerp(end, 0.35) - hdir * hr * 0.2
			var big := hr * rng.randf_range(1.5, 1.8)
			_ellipse(part, c, Vector2(big, big * 1.05))
			var tufts := rng.randi_range(9, 13)
			var a0 := rng.randf() * TAU
			for k in tufts:
				var a := a0 + TAU * (k + rng.randf_range(-0.25, 0.25)) / tufts
				var d := Vector2.from_angle(a)
				_chain(part, PackedVector2Array([c + d * big * 0.7, c + d * big * rng.randf_range(1.2, 1.45)]),
						PackedFloat32Array([big * 0.32, big * 0.09]), 0.0)


func _tail(rump: Vector2, rh: float, tip_marking: bool) -> void:
	var g := genes
	var kind: String = g["tail"]
	if kind == "none":
		return
	var base := rump + Vector2(-rh * 0.85, -rh * 0.5)
	var droop := deg_to_rad(g["tail_droop"])
	var a := PI - droop
	var w: float = g["tail_w"]
	var length: float = g["tail_len"]
	var curl: float = g["tail_curl"]
	var segs := 6
	var radii := PackedFloat32Array()
	var layer := BODY
	var pattern := true
	var family := "coat"
	match kind:
		"long", "tuft":
			radii = PackedFloat32Array([w * 1.3, w, w * 0.95, w * 0.9, w * 0.85, w * 0.8, w * 0.75])
		"bushy":
			radii = PackedFloat32Array([w * 0.9, w * 1.7, w * 2.6, w * 3.0, w * 2.8, w * 2.1, w * 0.9])
		"hair":
			layer = BEHIND
			pattern = false
			family = "hair"
			radii = PackedFloat32Array([w * 1.2, w * 1.4, w * 1.8, w * 2.1, w * 2.2, w * 1.9, w * 1.0])
		"short":
			segs = 2
			length = minf(length, 0.16)
			radii = PackedFloat32Array([w * 1.3, w * 1.1, w * 0.8])
		"puff":
			var r := maxf(0.06, rh * 0.32)
			_ellipse(_part(FRONT, false, "hair"), base + Vector2(-r * 0.2, r * 0.3), Vector2(r, r))
			return
		"curly":
			segs = 10
			radii = PackedFloat32Array()
			for k in segs + 1:
				radii.append(w * lerpf(1.2, 0.9, k / float(segs)))
	var pts := PackedVector2Array([base])
	var bend: float = curl * (0.9 if kind == "curly" else 0.35)
	for k in segs:
		pts.append(pts[k] + Vector2(cos(a), sin(a)) * length / segs)
		a += bend
	var part := _part(layer, pattern, family, 0.0)
	var sm := _smooth(pts, radii, 3)
	_chain(part, sm[0], sm[1], base.x, -1.0)
	var last := pts[pts.size() - 1]
	var along := (last - pts[pts.size() - 2]).normalized()
	if kind == "tuft":
		_chain(_part(DETAIL, false, "hair"), PackedVector2Array([last - along * length * 0.12, last + along * length * 0.12,
				last + along * length * 0.3]), PackedFloat32Array([w * 0.9, w * 2.2, w * 0.7]), 0.0)
	elif kind == "hair":
		# The hair spreads into strands at the end.
		for k in 2:
			var d := along.rotated(rng.randf_range(0.2, 0.45) * (1.0 if k == 0 else -1.0))
			_chain(part, PackedVector2Array([pts[segs - 1], pts[segs - 1] + d * length * 0.4]),
					PackedFloat32Array([w * 1.6, w * 0.6]), 0.0)
	if tip_marking and kind in ["bushy", "long"]:
		var c := pts[segs - 1].lerp(last, rng.randf_range(0.0, 0.5))
		_bands.append({"part": part, "layer": layer, "c": c, "n": along, "family": "tail_tip", "width": w * 3.0})
		_markings.append("tail_tip")


# --- placing -----------------------------------------------------------------------------

func _prim_box(prim: Dictionary) -> Rect2:
	if prim["kind"] == "cap":
		var a: Vector2 = prim["a"]
		var b: Vector2 = prim["b"]
		var r: float = maxf(prim["ra"], prim["rb"])
		return Rect2(a, Vector2.ZERO).expand(b).grow(r)
	var rr: Vector2 = prim["r"]
	return Rect2(prim["c"], Vector2.ZERO).grow(maxf(rr.x, rr.y))


## Scales and places the animal on the board, facing its way, and sets up
## its scene.
func _fit(facing: String, scene: String) -> void:
	var box := Rect2()
	var first := true
	for part: Dictionary in _parts:
		for prim: Dictionary in part["prims"]:
			var b := _prim_box(prim)
			box = b if first else box.merge(b)
			first = false
	_fx = -1.0 if facing == "left" else 1.0
	_scene = scene
	var center := Vector2(box.get_center().x * _fx, box.get_center().y)
	match scene:
		"field":
			_s = minf(1.7 / box.size.x, 1.45 / box.size.y)
			_off = Vector2(-center.x * _s, 0.82 - box.end.y * _s)
		"round":
			_s = 1.72 / box.size.length()
			_off = -center * _s + Vector2(0.0, 0.03)
		_:
			_s = 1.8 / maxf(box.size.x, box.size.y)
			_off = -center * _s
	_box = _cells_of(box.grow(MELT + 0.08)).intersection(Rect2i(0, 0, N, N))
	if scene != "none":
		var belly: float = _at["belly"]
		var feet: float = _at["ground"]
		var y := lerpf(belly, feet, rng.randf_range(0.3, 0.65)) * _s + _off.y
		_horizon = [y, rng.randf_range(0.01, 0.05), rng.randf_range(1.0, 3.0), rng.randf() * TAU,
				rng.randf_range(0.0, 0.03)]
		_box = Rect2i(0, 0, N, N)


## The grid cells (end exclusive) covering an animal-space box.
func _cells_of(box: Rect2) -> Rect2i:
	var p0 := to_unit(box.position)
	var p1 := to_unit(box.end)
	var x0 := FieldLines.cell_of(minf(p0.x, p1.x), N)
	var y0 := FieldLines.cell_of(minf(p0.y, p1.y), N)
	return Rect2i(x0, y0, FieldLines.cell_of(maxf(p0.x, p1.x), N) + 1 - x0, FieldLines.cell_of(maxf(p0.y, p1.y), N) + 1 - y0)


func to_unit(a: Vector2) -> Vector2:
	return Vector2(a.x * _fx, a.y) * _s + _off


func to_animal(p: Vector2) -> Vector2:
	var q := (p - _off) / _s
	return Vector2(q.x * _fx, q.y)


func _make_coat(coat_name: String, seed_value: int) -> void:
	var box := Rect2()
	var first := true
	for part: Dictionary in _parts:
		for prim: Dictionary in part["prims"]:
			box = _prim_box(prim) if first else box.merge(_prim_box(prim))
			first = false
	_coat_seed = seed_value
	_coat_bounds = box
	_coat_body = {"spine": _at["spine"], "rump": _at["rump"], "rump_r": _at["rump_r"]}
	_coat = CoatPatterns.make(coat_name, seed_value, box, _coat_body)


# --- fields ------------------------------------------------------------------------------

## Distance (animal units) from `a` to a prim, and its flow coordinates:
## [distance, along (body lengths from the part's start), across (-1..1)].
static func _prim_at(prim: Dictionary, a: Vector2) -> Vector3:
	if prim["kind"] == "cap":
		var pa: Vector2 = a - prim["a"]
		var ba: Vector2 = prim["b"] - prim["a"]
		var l2 := ba.length_squared()
		var t := clampf(pa.dot(ba) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
		var r: float = lerpf(prim["ra"], prim["rb"], t)
		var q := pa - ba * t
		var across := 0.0
		if l2 > 0.0:
			across = (ba.x * q.y - ba.y * q.x) / sqrt(l2) / r
		return Vector3(q.length() - r, prim["u0"] + t * sqrt(l2), across)
	var rr: Vector2 = prim["r"]
	var local: Vector2 = (a - prim["c"]).rotated(-prim["rot"])
	var k0 := (local / rr).length()
	var k1 := (local / (rr * rr)).length()
	var d := k0 * (k0 - 1.0) / k1 if k1 > 0.0 else -minf(rr.x, rr.y)
	return Vector3(d, local.x, local.y / rr.y)


static func _smin(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


## The layer fields (smooth unions of their parts), the silhouette (all
## layers), and the coat's fields, on the grid.
func _fields() -> void:
	var cells := N * N
	_layer = []
	for _l in LAYERS:
		var f := PackedFloat32Array()
		f.resize(cells)
		f.fill(BIG)
		_layer.append(f)
	var wsum := PackedFloat32Array()
	var phis := PackedFloat32Array()
	var vs := PackedFloat32Array()
	wsum.resize(cells)
	phis.resize(cells)
	vs.resize(cells)
	var melt := MELT * _s
	var step := 2.0 / N
	# A part's prims join exactly (their nearest one counts, flow included);
	# parts in a layer melt into each other.
	for part: Dictionary in _parts:
		var sdf: PackedFloat32Array = _layer[part["layer"]]
		var pattern: bool = part["pattern"]
		var taper: float = part["taper"]
		var cells_of := []
		var span := Rect2i()
		for prim: Dictionary in part["prims"]:
			var r := _cells_of(_prim_box(prim).grow(maxf(MELT, FLOW_REACH)))
			cells_of.append(r)
			span = r if span.size == Vector2i.ZERO else span.merge(r)
		var bw := span.size.x
		var near := PackedFloat32Array()
		near.resize(bw * span.size.y)
		near.fill(BIG)
		var along := PackedFloat32Array()
		along.resize(near.size())
		var across := PackedFloat32Array()
		across.resize(near.size())
		for k in part["prims"].size():
			var prim: Dictionary = part["prims"][k]
			var r: Rect2i = cells_of[k]
			var phi0: float = prim["phi0"]
			var sign: float = prim.get("sign", 1.0)
			for cy in range(r.position.y, r.end.y):
				var py := -1.0 + (cy + 0.5) * step
				for cx in range(r.position.x, r.end.x):
					var at := _prim_at(prim, to_animal(Vector2(-1.0 + (cx + 0.5) * step, py)))
					var j := (cy - span.position.y) * bw + cx - span.position.x
					if at.x < near[j]:
						near[j] = at.x
						along[j] = phi0 + sign * at.y
						across[j] = at.z
		for cy in range(span.position.y, span.end.y):
			for cx in range(span.position.x, span.end.x):
				var j := (cy - span.position.y) * bw + cx - span.position.x
				var d := near[j]
				if d >= BIG:
					continue
				var i := cy * N + cx
				sdf[i] = _smin(sdf[i], d * _s, melt)
				if pattern and d < FLOW_REACH:
					var w := exp(-clampf(d, -0.15, FLOW_REACH) / FLOW_SOFT)
					wsum[i] += w
					phis[i] += w * along[j]
					vs[i] += w * across[j] * taper
	# Inside positive, and the silhouette is the outermost of them.
	_total.resize(cells)
	_total.fill(-BIG)
	for l in LAYERS:
		var f: PackedFloat32Array = _layer[l]
		for i in cells:
			f[i] = -f[i]
			_total[i] = maxf(_total[i], f[i])
	_marking.resize(cells)
	_marking.fill(-1.0)
	_marking2.resize(cells)
	_marking2.fill(-1.0)
	if _coat.coat == "solid":
		return
	# A coat whose markings miss the animal (or cover it) tries again.
	for attempt in 5:
		if attempt > 0:
			_coat = CoatPatterns.make(_coat.coat, _coat_seed + 7919 * attempt, _coat_bounds, _coat_body)
		var coverage := _coat_fields(wsum, phis, vs)
		if coverage > 0.04 and coverage < 0.85:
			break


## The coat's fields on the grid (from the blended flow); returns the share
## of the animal inside its markings.
func _coat_fields(wsum: PackedFloat32Array, phis: PackedFloat32Array, vs: PackedFloat32Array) -> float:
	var step := 2.0 / N
	var inside := 0
	var marked := 0
	var second := _coat.has_second()
	for cy in range(_box.position.y, _box.end.y):
		for cx in range(_box.position.x, _box.end.x):
			var i := cy * N + cx
			if _total[i] < -0.03:
				continue
			var a := to_animal(Vector2(-1.0 + (cx + 0.5) * step, -1.0 + (cy + 0.5) * step))
			var phi := a.x
			var v := 0.0
			if wsum[i] > 0.0:
				phi = phis[i] / wsum[i]
				v = vs[i] / wsum[i]
			_marking[i] = _coat.value(a, phi, v)
			if second:
				_marking2[i] = _coat.value2(a, phi, v)
			if _total[i] > 0.0:
				inside += 1
				if _marking[i] > 0.0:
					marked += 1
	return marked / float(maxi(1, inside))


## The front-most layer at unit point p, or -1 off the animal.
func _top(p: Vector2) -> int:
	for l in range(LAYERS - 1, -1, -1):
		if FieldLines.sample(_layer[l], N, p) > 0.0:
			return l
	return -1


## The part a point of `layer` belongs to: the nearest of that layer's parts.
func _part_at(p: Vector2, layer: int) -> Dictionary:
	var a := to_animal(p)
	var best := {}
	var best_d := INF
	for part: Dictionary in _parts:
		if part["layer"] != layer:
			continue
		for prim: Dictionary in part["prims"]:
			var d := _prim_at(prim, a).x
			if d < best_d:
				best_d = d
				best = part
	return best


## The band (hooves, socks, tail tip) p lies past, or {}.
func _band_at(p: Vector2, top: int) -> Dictionary:
	if _bands.is_empty():
		return {}
	var a := to_animal(p)
	var found := {}
	for band: Dictionary in _bands:
		if band["layer"] != top or (a - band["c"]).dot(band["n"]) <= 0.0:
			continue
		if not is_same(_part_at(p, top), band["part"]):
			continue
		# Hooves win over socks: the band furthest along.
		if found.is_empty() or (band["c"] - found["c"]).dot(band["n"]) > 0.0:
			found = band
	return found


## What area p is in: a family name, or "" off the picture.
func _area_at(p: Vector2) -> String:
	var top := _top(p)
	if top < 0:
		return _scene_at(p)
	if top in PLAIN_LAYERS:
		return _part_at(p, top)["family"]
	if top == FRONT:
		var part := _part_at(p, top)
		if not part["pattern"]:
			return part["family"]
	var band := _band_at(p, top)
	if not band.is_empty():
		return band["family"]
	if FieldLines.sample(_marking2, N, p) > 0.0:
		return "spots"
	if FieldLines.sample(_marking, N, p) > 0.0:
		return "markings"
	return "coat"


func _scene_at(p: Vector2) -> String:
	if _scene == "none" or not _on_board(p):
		return ""
	if _sun.z > 0.0 and p.distance_to(Vector2(_sun.x, _sun.y)) < _sun.z:
		return "sun"
	return "sky" if p.y < _horizon_y(p.x) else "ground"


func _on_board(p: Vector2) -> bool:
	if _scene == "round":
		return p.length() < 0.95
	return absf(p.x) < 0.95 and absf(p.y) < 0.95


func _horizon_y(x: float) -> float:
	return _horizon[0] + _horizon[1] * sin(x * _horizon[2] + _horizon[3]) + _horizon[4] * x


# --- lines --------------------------------------------------------------------------------

func _family(name: String) -> int:
	var id := family_names.find(name)
	if id < 0:
		id = family_names.size()
		family_names.append(name)
	return id


func _add(pts: PackedVector2Array, is_closed: bool, family: String) -> void:
	if pts.size() < 2:
		return
	polylines.append(pts)
	closed.append(1 if is_closed else 0)
	families.append(_family(family))


func _add_pieces(pieces: Array, family: String) -> void:
	for piece: Dictionary in pieces:
		_add(piece["points"], piece["closed"], family)


func _draw() -> void:
	if _scene != "none":
		_draw_scene()
	# The silhouette.
	for line: Dictionary in FieldLines.iso(_total, N, 0.0, _box, 0.05):
		_add(line["points"], line["closed"], "outline")
	# Each layer's outline where it lies over the layers behind it (and isn't
	# itself covered).
	for l in range(1, LAYERS):
		var layer := l
		var inside := func(p: Vector2) -> bool:
			var below := false
			for k in layer:
				if FieldLines.sample(_layer[k], N, p) > 0.0:
					below = true
					break
			if not below:
				return false
			for k in range(layer + 1, LAYERS):
				if FieldLines.sample(_layer[k], N, p) > 0.0:
					return false
			return true
		for line: Dictionary in FieldLines.iso(_layer[l], N, 0.0, _box, 0.02):
			_add_pieces(FieldLines.clip(line["points"], line["closed"], inside), LAYER_FAMILIES[l])
	# Bands across legs and tails, each ending on its leg's outline.
	for band: Dictionary in _bands:
		var c: Vector2 = band["c"]
		var n: Vector2 = band["n"]
		var across := Vector2(-n.y, n.x)
		var reach: float = band["width"] * 4.0
		var bow := 0.25 if band["family"] == "socks" else 0.1
		var pts := PackedVector2Array()
		for k in 17:
			var t := k / 16.0 * 2.0 - 1.0
			pts.append(to_unit(c + across * t * reach + n * (1.0 - t * t) * reach * bow * 0.5))
		var layer: int = band["layer"]
		var pieces := FieldLines.clip(pts, false, func(p: Vector2) -> bool: return _top(p) == layer)
		var piece := FieldLines.nearest_piece(pieces, to_unit(c))
		if not piece.is_empty():
			_add(piece["points"], false, "bands")
	# Coat markings, inside the animal and off its plain parts.
	var coated := func(p: Vector2) -> bool:
		var top := _top(p)
		if top < 0 or top in PLAIN_LAYERS:
			return false
		if top == FRONT and not _part_at(p, top)["pattern"]:
			return false
		return _band_at(p, top).is_empty()
	for line: Dictionary in FieldLines.iso(_marking, N, 0.0, _box, 0.03):
		_add_pieces(FieldLines.clip(line["points"], line["closed"], coated), "markings")
	if _coat.has_second():
		for line: Dictionary in FieldLines.iso(_marking2, N, 0.0, _box, 0.03):
			_add_pieces(FieldLines.clip(line["points"], line["closed"], coated), "spots")


func _draw_scene() -> void:
	var board := PackedVector2Array()
	if _scene == "round":
		board = MandalaGenerator.circle(Vector2.ZERO, 0.95, 240)
	else:
		for k in 4:
			var a := Vector2(-0.95, -0.95).rotated(PI / 2.0 * k)
			var b := Vector2(-0.95, -0.95).rotated(PI / 2.0 * (k + 1))
			for i in 60:
				board.append(a.lerp(b, i / 60.0))
	_add(board, true, "board")
	var off_animal := func(p: Vector2) -> bool:
		return FieldLines.sample(_total, N, p) < 0.0 and _on_board(p)
	var horizon := PackedVector2Array()
	for i in 121:
		var x := -1.0 + i / 60.0
		horizon.append(Vector2(x, _horizon_y(x)))
	_add_pieces(FieldLines.clip(horizon, false, off_animal), "horizon")
	# A sun in the sky, clear of the animal, the horizon and the edge.
	for _attempt in 30:
		var r := rng.randf_range(0.08, 0.14)
		var c := Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, _horizon[0] - 0.2))
		var ok := c.y + r < _horizon_y(c.x) - 0.08 and _on_board(c + c.normalized() * (r + 0.07))
		if ok:
			for k in 24:
				var q := c + Vector2.from_angle(TAU * k / 24.0) * (r + 0.07)
				if FieldLines.sample(_total, N, q) > -0.01 or not _on_board(q):
					ok = false
					break
		if ok:
			if rng.randf() < 0.6:
				_sun = Vector3(c.x, c.y, r)
				_add(MandalaGenerator.circle(c, r, 72), true, "sun")
			break


## Marks inside the areas, so a family's areas share colors: wherever a
## point of a fine lattice and its 8 neighbors are in the same area (so it's
## clear of every line), at most one per family in each block of the
## lattice.
func _mark() -> void:
	var stride := 2
	var cols := N / stride
	var area := PackedStringArray()
	area.resize(cols * cols)
	var lo := _box.position / stride
	var hi := _box.end / stride + Vector2i.ONE
	if _scene != "none":
		lo = Vector2i.ZERO
		hi = Vector2i(cols, cols)
	hi = hi.min(Vector2i(cols, cols))
	for ly in range(lo.y, hi.y):
		for lx in range(lo.x, hi.x):
			var p := Vector2(FieldLines.cell_center(lx * stride, N), FieldLines.cell_center(ly * stride, N))
			if _scene == "none" and FieldLines.sample(_total, N, p) < -0.02:
				continue
			area[ly * cols + lx] = _area_at(p)
	var block := 4
	var taken := {}
	for ly in range(maxi(lo.y, 1), mini(hi.y, cols - 1)):
		for lx in range(maxi(lo.x, 1), mini(hi.x, cols - 1)):
			var here := area[ly * cols + lx]
			if here == "" or here == "eye":
				continue
			var key := [lx / block, ly / block, here]
			if taken.has(key):
				continue
			var ok := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if area[(ly + dy) * cols + lx + dx] != here:
						ok = false
			if ok:
				taken[key] = true
				marks.append({"at": Vector2(FieldLines.cell_center(lx * stride, N), FieldLines.cell_center(ly * stride, N)),
						"family": _family(here)})
	# Thin areas (slivers along the outline, narrow stripes) the lattice
	# misses: a tighter look round points it turned down.
	for ly in range(maxi(lo.y, 1), mini(hi.y, cols - 1)):
		for lx in range(maxi(lo.x, 1), mini(hi.x, cols - 1)):
			var here := area[ly * cols + lx]
			if here == "" or here == "eye" or taken.has([lx / block, ly / block, here]):
				continue
			var key := [lx / 2, ly / 2, here, 1]
			if taken.has(key):
				continue
			var p := Vector2(FieldLines.cell_center(lx * stride, N), FieldLines.cell_center(ly * stride, N))
			var ok := true
			for k in 8:
				if _area_at(p + Vector2.from_angle(TAU * k / 8.0) * TIGHT) != here:
					ok = false
					break
			if ok:
				taken[key] = true
				marks.append({"at": p, "family": _family(here)})
	# Small markings the lattice missed.
	for second in [false, true]:
		var want := "spots" if second else "markings"
		for a in _coat.mark_points(second):
			var p := to_unit(a)
			if _area_at(p) == want:
				marks.append({"at": p, "family": _family(want)})

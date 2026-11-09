class_name AnimalGenerator
extends RefCounted
## Seeded animals seen from the side, posed: standing, walking, running,
## crouched to pounce, leaping, sitting, howling, lying down, resting the
## head on the paws, curled up asleep, stretching, grazing or swimming.
## Nothing is symmetric.
##
## Each animal is a rig. A spine runs from the rump through the body and
## neck; the body is swept along it with the species' own profile (the back
## close above the spine, a deep chest, a tucked waist, a round rump), so
## bending the spine bends the body: a sitting cat's body rises at 50
## degrees, a sleeping one curls into a ball. The head is swept the same way
## along its own axis (skull, forehead, stop, muzzle, jaw), and an elephant's
## carries on into its trunk. Legs are solved by inverse kinematics from
## shoulder and hip to where each paw should be (elbows bend back, knees
## forward, hocks back), with each body plan's segment lengths: digitigrade
## cats and dogs, hoofed horses and deer, pillar-legged elephants and hippos,
## flat-footed bears. A pose is where the paws go, how the spine bends, and
## where the neck, head and tail point.
##
## SPECIES set the proportions (GENE_RANGES), the parts (feet, ears, horns,
## tail, mane), the poses that suit them and the coats. Each animal is its
## species jittered a little; "wild" blends two species of one body plan
## gene by gene.
##
## Every part is drawn in depth order (far legs, far ear, tail, body, head,
## near legs, near ear, eye, as the pose has it), and its outline shows
## wherever it lies over a part behind it. Every part is also its own coat
## space: the distance along it and across it. Coat markings (CoatPatterns:
## tiger stripes, spots, rosettes, giraffe net...) and markings that follow
## the part's shape (a pale belly, a blanket over the rump, a belted middle,
## dark points, socks, hooves, a white tail tip, a blaze, a pale muzzle, the
## nose, inner ears) are fields over those coordinates, so stripes cross a
## leg and ring a tail, and follow the body round a curl. Every line ends on
## another, so every region is closed (see FieldLines).
##
## Like a swirl, every line and the areas inside belong to a family (the
## coat, the markings, the belly, socks, hair, horns, the eye...), so a
## collage gives all of the coat one pattern and colors, and all the stripes
## another.
##
## Output matches MandalaGenerator: polylines in unit space (-1..1, y down),
## plus "families" (an id per polyline), "family_names" (by id) and "marks"
## ([{"at": unit-space point, "family": id}], points inside areas).

## Proportions, in body lengths (the torso, rump to chest, is 1 long), and
## the range a wild blend may stray across.
const GENE_RANGES := {
	"back": [0.04, 0.16],  # how far the back rises above the spine
	"chest": [0.18, 0.62],  # chest depth below the spine
	"tuck": [0.5, 1.1],  # waist depth, x chest
	"rump": [0.13, 0.56],  # rump depth below the spine
	"haunch": [0.0, 1.0],  # how full, high and round the rump stays to the tail
	"barrel": [0.0, 1.0],  # how far back the chest keeps its depth
	"hip_at": [0.08, 0.2],  # where the hips sit, from the rump's end
	"arch": [-0.15, 0.3],  # how the back bows (up positive)
	"hump": [0.0, 0.1],  # extra height over the shoulders (a bear's)
	"neck": [0.05, 0.6],
	"neck_w": [0.6, 1.05],  # neck thickness where it meets the head, x skull
	"neck_angle": [5.0, 60.0],  # above level, standing
	"head": [0.24, 0.6],  # head length, back of skull to nose
	"skull": [0.1, 0.25],  # skull half-height
	"muzzle": [0.15, 0.62],  # muzzle length, x head
	"muzzle_w": [0.4, 1.1],  # muzzle tip half-height, x skull
	"jaw": [0.85, 1.4],  # cheek and jaw depth, x skull
	"head_angle": [0.0, 70.0],  # nose below level
	"trunk": [0.0, 0.8],
	"leg": [0.08, 0.6],  # elbow to ground, standing
	"leg_w": [0.03, 0.14],  # forearm half-width
	"shoulder": [0.07, 0.21],
	"thigh": [0.1, 0.26],
	"paw": [0.035, 0.14],
	"ear_size": [0.5, 1.5],
	"tail_len": [0.06, 0.85],
	"tail_w": [0.02, 0.06],
}
const FEET := ["paw", "hoof", "pillar", "plantigrade"]
const EARS := ["pointed", "round", "small", "floppy", "fan"]
const TAILS := ["thin", "tapered", "bushy", "tuft", "hair", "short", "whip"]
const MANES := ["none", "horse", "crest", "lion"]
const HORNS := ["none", "curved", "antlers"]
const POSES := ["stand", "walk", "run", "pounce", "leap", "sit", "howl", "lie", "rest", "curl", "stretch", "graze",
		"swim"]
## Poses each body plan can take.
const PLANS := {
	"feline": ["stand", "walk", "run", "pounce", "leap", "sit", "lie", "rest", "curl", "stretch", "swim"],
	"canine": ["stand", "walk", "run", "pounce", "leap", "sit", "howl", "lie", "rest", "curl", "stretch", "swim"],
	"ungulate": ["stand", "walk", "run", "lie", "graze"],
	"heavy": ["stand", "walk", "swim", "lie"],
	"bear": ["stand", "walk", "sit", "lie", "rest", "swim"],
}
## Plans that may blend into each other in a wild animal.
const KIN := {"feline": "carnivore", "canine": "carnivore", "bear": "carnivore", "ungulate": "hoofed",
		"heavy": "heavy"}
## Coats: CoatPatterns' markings, plus ones that follow the body's shape:
## a pale belly, a spotted blanket over the rump, a belted middle, dark
## points (face, ears, legs, tail).
const COATS := ["solid", "tiger", "zebra", "cow", "pinto", "dalmatian", "cheetah", "leopard", "giraffe", "dapple",
		"appaloosa", "saddle", "countershade", "points"]
## The area family each coat's markings make.
const COAT_FAMILY := {"appaloosa": "blanket", "saddle": "saddle", "countershade": "belly", "points": "points"}
const MARKINGS := ["socks", "blaze", "muzzle", "tip", "belly"]
## none: the animal alone; field: a square board with a horizon behind the
## animal (and sometimes a sun); round: the same in a circle. Swimmers are
## always in water.
const SCENES := ["none", "field", "round"]
const SCENE_WEIGHTS := {"none": 0.45, "field": 0.35, "round": 0.2}

const BASE_GENES := {
	"back": 0.06, "chest": 0.24, "tuck": 0.75, "rump": 0.17, "haunch": 0.0, "barrel": 0.0,
	"hip_at": 0.17, "arch": 0.05, "hump": 0.0,
	"neck": 0.17, "neck_w": 0.85, "neck_angle": 35.0,
	"head": 0.32, "skull": 0.134, "muzzle": 0.3, "muzzle_w": 0.6, "jaw": 0.95, "head_angle": 12.0, "trunk": 0.0,
	"leg": 0.27, "leg_w": 0.052, "shoulder": 0.1, "thigh": 0.15, "paw": 0.052,
	"ear_size": 1.0, "tail_len": 0.7, "tail_w": 0.042,
	"feet": "paw", "ears": "pointed", "tail": "thin", "mane": "none", "horns": "none",
}
## Species: body plan, genes that differ from BASE_GENES, the coats that suit
## them, and how likely each marking is.
const SPECIES := {
	"cat": {"plan": "feline", "genes": {"chest": 0.22, "tuck": 0.7, "rump": 0.16, "arch": 0.12, "neck": 0.15,
			"neck_angle": 40.0, "head": 0.324, "skull": 0.14, "muzzle": 0.26, "muzzle_w": 0.55, "jaw": 0.9,
			"head_angle": 8.0, "leg": 0.27, "leg_w": 0.05, "shoulder": 0.09, "thigh": 0.14, "paw": 0.05,
			"tail_len": 0.78, "tail_w": 0.04},
			"coats": ["tiger", "solid", "pinto", "cow", "countershade", "points"],
			"socks": 0.3, "muzzle": 0.3, "tip": 0.1, "belly": 0.3},
	"tiger": {"plan": "feline", "genes": {"back": 0.07, "chest": 0.26, "tuck": 0.8, "rump": 0.19, "arch": 0.05,
			"neck": 0.17, "neck_w": 0.9, "neck_angle": 22.0, "head": 0.324, "skull": 0.146, "muzzle": 0.32,
			"muzzle_w": 0.68, "jaw": 1.0, "head_angle": 14.0, "leg": 0.25, "leg_w": 0.066, "shoulder": 0.12,
			"thigh": 0.17, "paw": 0.066, "ears": "round", "ear_size": 0.7, "tail_len": 0.62, "tail_w": 0.045},
			"coats": ["tiger"], "muzzle": 0.8, "belly": 0.9},
	"lion": {"plan": "feline", "genes": {"back": 0.07, "chest": 0.27, "tuck": 0.8, "rump": 0.19, "arch": 0.04,
			"neck": 0.17, "neck_w": 0.9, "neck_angle": 28.0, "head": 0.335, "skull": 0.146, "muzzle": 0.33,
			"muzzle_w": 0.7, "jaw": 1.0, "head_angle": 14.0, "leg": 0.28, "leg_w": 0.066, "shoulder": 0.12,
			"thigh": 0.17, "paw": 0.066, "ears": "round", "ear_size": 0.6, "tail": "tuft", "tail_len": 0.65,
			"tail_w": 0.034, "mane": "lion"},
			"coats": ["solid", "countershade"], "muzzle": 0.6},
	"leopard": {"plan": "feline", "genes": {"chest": 0.24, "tuck": 0.78, "rump": 0.17, "arch": 0.06, "neck": 0.15,
			"neck_angle": 25.0, "head": 0.302, "skull": 0.134, "muzzle": 0.28, "muzzle_w": 0.65, "head_angle": 10.0,
			"leg": 0.23, "leg_w": 0.056, "shoulder": 0.1, "thigh": 0.155, "paw": 0.058, "ears": "round",
			"ear_size": 0.7, "tail_len": 0.82, "tail_w": 0.04},
			"coats": ["leopard", "cheetah"], "belly": 0.7, "muzzle": 0.4},
	"cheetah": {"plan": "feline", "genes": {"chest": 0.26, "tuck": 0.55, "rump": 0.15, "arch": 0.18, "neck": 0.2,
			"neck_w": 0.8, "neck_angle": 30.0, "head": 0.27, "skull": 0.118, "muzzle": 0.3, "muzzle_w": 0.65,
			"head_angle": 8.0, "leg": 0.37, "leg_w": 0.044, "shoulder": 0.09, "thigh": 0.13, "paw": 0.046,
			"ears": "small", "ear_size": 0.75, "tail_len": 0.75, "tail_w": 0.034},
			"coats": ["cheetah"], "tip": 0.6, "belly": 0.6},
	"dog": {"plan": "canine", "genes": {"back": 0.07, "chest": 0.3, "tuck": 0.72, "rump": 0.19, "arch": 0.03,
			"neck": 0.24, "neck_w": 0.85, "neck_angle": 40.0, "head": 0.41, "skull": 0.134, "muzzle": 0.46,
			"muzzle_w": 0.62, "jaw": 0.92, "head_angle": 12.0, "leg": 0.37, "leg_w": 0.055, "shoulder": 0.11,
			"thigh": 0.155, "paw": 0.056, "ears": "floppy", "tail": "tapered", "tail_len": 0.5, "tail_w": 0.045},
			"coats": ["solid", "dalmatian", "pinto", "saddle", "points"],
			"socks": 0.3, "blaze": 0.25, "muzzle": 0.25, "tip": 0.2},
	"wolf": {"plan": "canine", "genes": {"back": 0.07, "chest": 0.3, "tuck": 0.75, "rump": 0.18, "arch": 0.02,
			"neck": 0.24, "neck_w": 0.95, "neck_angle": 28.0, "head": 0.41, "skull": 0.14, "muzzle": 0.45,
			"muzzle_w": 0.56, "jaw": 0.95, "head_angle": 14.0, "leg": 0.4, "leg_w": 0.052, "shoulder": 0.11,
			"thigh": 0.15, "paw": 0.055, "ear_size": 0.9, "tail": "bushy", "tail_len": 0.55, "tail_w": 0.045},
			"coats": ["countershade", "saddle", "solid"], "muzzle": 0.5, "belly": 0.5},
	"fox": {"plan": "canine", "genes": {"back": 0.055, "chest": 0.22, "tuck": 0.72, "rump": 0.16, "arch": 0.05,
			"neck": 0.18, "neck_w": 0.85, "neck_angle": 35.0, "head": 0.356, "skull": 0.112, "muzzle": 0.5,
			"muzzle_w": 0.42, "jaw": 0.92, "head_angle": 8.0, "leg": 0.27, "leg_w": 0.04, "shoulder": 0.08,
			"thigh": 0.125, "paw": 0.045, "ear_size": 1.35, "tail": "bushy", "tail_len": 0.75, "tail_w": 0.05},
			"coats": ["countershade", "solid"], "socks": 0.85, "tip": 0.9, "muzzle": 0.6, "belly": 0.5},
	"dachshund": {"plan": "canine", "genes": {"chest": 0.24, "tuck": 0.85, "rump": 0.15, "arch": 0.02, "neck": 0.2,
			"neck_angle": 40.0, "head": 0.41, "skull": 0.123, "muzzle": 0.5, "muzzle_w": 0.5, "head_angle": 10.0,
			"leg": 0.1, "leg_w": 0.05, "shoulder": 0.1, "thigh": 0.12, "paw": 0.055, "ears": "floppy",
			"ear_size": 1.3, "tail": "tapered", "tail_len": 0.45, "tail_w": 0.04},
			"coats": ["solid", "dapple", "countershade"], "muzzle": 0.3},
	"horse": {"plan": "ungulate", "genes": {"hip_at": 0.1, "barrel": 1.0,
			"back": 0.07, "chest": 0.38, "tuck": 1.0, "rump": 0.22, "arch": -0.06,
			"neck": 0.48, "neck_w": 0.75, "neck_angle": 52.0, "head": 0.54, "skull": 0.123, "muzzle": 0.56,
			"muzzle_w": 0.62, "jaw": 1.35, "head_angle": 62.0, "leg": 0.55, "leg_w": 0.045, "shoulder": 0.13,
			"thigh": 0.22, "paw": 0.05, "feet": "hoof", "ear_size": 0.8, "tail": "hair", "tail_len": 0.6,
			"tail_w": 0.055, "mane": "horse"},
			"coats": ["solid", "solid", "pinto", "dapple", "appaloosa"], "socks": 0.6, "blaze": 0.55},
	"zebra": {"plan": "ungulate", "genes": {"hip_at": 0.1, "barrel": 1.0,
			"back": 0.07, "chest": 0.38, "tuck": 1.0, "rump": 0.22, "arch": -0.03,
			"neck": 0.42, "neck_w": 0.85, "neck_angle": 48.0, "head": 0.518, "skull": 0.129, "muzzle": 0.55,
			"muzzle_w": 0.65, "jaw": 1.3, "head_angle": 58.0, "leg": 0.47, "leg_w": 0.047, "shoulder": 0.13,
			"thigh": 0.22, "paw": 0.05, "feet": "hoof", "ear_size": 1.05, "tail": "tuft", "tail_len": 0.5,
			"tail_w": 0.03, "mane": "crest"},
			"coats": ["zebra"]},
	"cow": {"plan": "ungulate", "genes": {"hip_at": 0.12, "barrel": 0.8,
			"back": 0.08, "chest": 0.42, "tuck": 1.05, "rump": 0.29, "arch": -0.03,
			"neck": 0.22, "neck_w": 0.95, "neck_angle": 15.0, "head": 0.454, "skull": 0.146, "muzzle": 0.45,
			"muzzle_w": 0.78, "jaw": 1.2, "head_angle": 55.0, "leg": 0.37, "leg_w": 0.06, "shoulder": 0.14,
			"thigh": 0.2, "paw": 0.06, "feet": "hoof", "ear_size": 0.8, "horns": "curved", "tail": "tuft",
			"tail_len": 0.62, "tail_w": 0.03},
			"coats": ["cow", "cow", "pinto", "solid", "saddle"], "blaze": 0.25, "socks": 0.2},
	"deer": {"plan": "ungulate", "genes": {"hip_at": 0.11, "barrel": 0.8,
			"back": 0.06, "chest": 0.33, "tuck": 0.95, "rump": 0.19, "arch": 0.02,
			"neck": 0.38, "neck_w": 0.7, "neck_angle": 55.0, "head": 0.389, "skull": 0.112, "muzzle": 0.5,
			"muzzle_w": 0.5, "jaw": 1.0, "head_angle": 42.0, "leg": 0.55, "leg_w": 0.036, "shoulder": 0.1,
			"thigh": 0.18, "paw": 0.04, "feet": "hoof", "ear_size": 1.25, "horns": "antlers", "tail": "short",
			"tail_len": 0.13},
			"coats": ["countershade", "dalmatian", "solid"], "belly": 0.5},
	"elephant": {"plan": "heavy", "genes": {"back": 0.14, "chest": 0.54, "tuck": 1.0, "rump": 0.54, "haunch": 1.0,
			"arch": 0.0,
			"neck": 0.08, "neck_w": 1.0, "neck_angle": 10.0, "head": 0.389, "skull": 0.235, "muzzle": 0.25,
			"muzzle_w": 0.6, "jaw": 1.0, "head_angle": 72.0, "trunk": 0.7, "leg": 0.56, "leg_w": 0.125,
			"shoulder": 0.2, "thigh": 0.25, "paw": 0.13, "feet": "pillar", "ears": "fan", "ear_size": 1.2,
			"tail": "whip", "tail_len": 0.36, "tail_w": 0.025},
			"coats": ["solid"]},
	"hippo": {"plan": "heavy", "genes": {"back": 0.1, "chest": 0.4, "tuck": 1.08, "rump": 0.36, "haunch": 0.8, "arch": 0.03,
			"neck": 0.12, "neck_w": 1.05, "neck_angle": 8.0, "head": 0.54, "skull": 0.19, "muzzle": 0.42,
			"muzzle_w": 1.05, "jaw": 1.15, "head_angle": 14.0, "leg": 0.15, "leg_w": 0.095, "shoulder": 0.14,
			"thigh": 0.2, "paw": 0.1, "feet": "pillar", "ears": "small", "ear_size": 0.6, "tail": "whip",
			"tail_len": 0.18, "tail_w": 0.03},
			"coats": ["solid", "countershade"]},
	"bear": {"plan": "bear", "genes": {"back": 0.11, "chest": 0.33, "tuck": 0.9, "rump": 0.33, "haunch": 1.0, "arch": 0.0,
			"hump": 0.04, "neck": 0.16, "neck_w": 0.95, "neck_angle": 18.0, "head": 0.367, "skull": 0.157,
			"muzzle": 0.36, "muzzle_w": 0.55, "jaw": 0.95, "head_angle": 18.0, "leg": 0.3, "leg_w": 0.08,
			"shoulder": 0.15, "thigh": 0.24, "paw": 0.08, "feet": "plantigrade", "ears": "round", "ear_size": 0.55,
			"tail": "short", "tail_len": 0.08},
			"coats": ["solid", "countershade"], "muzzle": 0.5},
}
## Species, poses and coats used this recently are skipped.
const AVOID_RECENT := 4
const AVOID_RECENT_POSES := 3
const AVOID_RECENT_COATS := 2
## How far genes stray from their species (a fraction of their range), and
## how far a wild animal's do.
const JITTER := 0.035
const WILD_JITTER := 0.08
## Grid cells a side for the fields (see FieldLines).
const N := 320
const BIG := 10.0
## How far beyond a part (body lengths) its coordinates are kept, so its
## markings' lines run cleanly into its outline.
const REACH := 0.06
## How far (unit space) a mark in a thin area must be from its edge: past
## half a line's width.
const TIGHT := 0.0085
## Natural joint turns for each kind of foot (radians, from one bone's
## heading to the next's, y down): [front elbow, front wrist, hind knee, hind
## hock], resting and folded right up. A leg's pose blends between them.
const JOINTS := {
	"paw": {"rest": [-0.35, -0.25, 0.8, -0.95], "fold": [-1.4, 2.1, 2.1, -2.0]},
	"hoof": {"rest": [-0.2, 0.0, 0.55, -0.7], "fold": [-1.2, 2.3, 1.9, -2.1]},
	"pillar": {"rest": [-0.04, 0.02, 0.08, -0.08], "fold": [-0.6, 1.8, 1.4, -1.4]},
	"plantigrade": {"rest": [-0.12, -1.3, 0.25, -1.5], "fold": [-1.3, 0.6, 1.9, -1.6]},
}
## How far each of those joints may turn: [least, most]. Knees only fold
## forward and hocks back, so a leg never bends the wrong way.
const JOINT_LIMITS := [[-2.5, 0.25], [-1.7, 2.7], [-0.15, 2.7], [-2.75, 0.3]]
## The slant (from straight down, foot ahead positive) of the lowest bone
## of a leg standing on the ground, by kind of foot: [front, hind].
const PLANTED := {"paw": [[-0.1, 0.8], [-0.2, 0.6]], "hoof": [[-0.1, 0.45], [-0.1, 0.4]],
		"pillar": [[-0.12, 0.12], [-0.12, 0.12]], "plantigrade": [[1.15, 1.4], [1.45, 1.55]]}
## Where along the body (fraction of the torso) the shoulders sit; the hips
## sit at the gene "hip_at".
const SHOULDER_AT := 0.8

var rng := RandomNumberGenerator.new()
var genes := {}
var plan := "feline"
var polylines: Array[PackedVector2Array] = []
var closed := PackedByteArray()
var families := PackedInt32Array()
var family_names := PackedStringArray()
var marks := []

## Parts, back to front once sorted: {"name", "depth", "family" (its plain
## area), "line" (its outline's family), "pattern" (takes the coat),
## "taper" (stripes thin toward v > 0), "prims", "overlays", and on the
## grid "box" (Rect2i), "sdf" (unit space, inside negative), "u", "v", "r"}.
## A prim is a tapered capsule {"kind": "cap", "a", "b", "ra", "rb", "u0",
## "u1"} or an ellipse {"kind": "ell", "c", "r" (Vector2), "rot", "u0"}.
## Overlays are markings, lowest first: {"family", "fn": Callable(u, v, r,
## coat-space point) -> float, positive inside, "field"}.
var _parts := []
## The rig, built in `_rig`: segment lengths, and the spine and head as
## sampled sweeps {"pts", "n", "top", "bottom", "s"}.
var _legs := {}
var _body := {}
var _head := {}
var _ground := 0.0
var _depth := {}
## Animal space to unit space: unit = (animal * (fx, 1)) * s + off.
var _s := 1.0
var _off := Vector2.ZERO
var _fx := 1.0
var _box := Rect2i()
var _total := PackedFloat32Array()
## Scene: the board's outline, the horizon (or water) height, the sun.
var _scene := "none"
var _horizon := []
var _sun := Vector3.ZERO
var _water := false
var _markings := []


## options:
##   species: one of SPECIES, "wild" (a blend of two of one body plan) or
##            "random" (default)
##   pose: one of POSES the species can take, or "random"
##   coat: one of COATS, or "random" (default: one that suits the species)
##   facing: "left", "right" or "random"; scene: one of SCENES or "random"
##   markings: Array of MARKINGS to force, or omit for the species' chances
##   genes: Dictionary of genes to set outright (GENE_RANGES, plus "feet",
##          "ears", "tail", "mane", "horns")
##   wildness: 0..1 (default 0), how far genes stray from the species
##   recent: Array of earlier results' {"species", "pose", "coat"}; recent
##           choices are skipped and the least used preferred
## Returns {"seed", "species", "blend", "plan", "coat", "pose", "facing",
## "scene", "feet", "ears", "horns", "tail", "mane", "markings", "polylines",
## "closed", "families", "family_names", "marks"}.
static func generate(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var g := AnimalGenerator.new()
	g.rng.seed = seed_value
	var recent: Array = options.get("recent", [])
	var species: String = options.get("species", "random")
	if species != "wild" and not SPECIES.has(species):
		species = g._least_used(SPECIES.keys(), _recent_of(recent, "species"), AVOID_RECENT)
	var blend := ""
	var wildness: float = clampf(options.get("wildness", 0.0), 0.0, 1.0)
	var suits: Array
	if species == "wild":
		var names: Array = SPECIES.keys()
		species = names[g.rng.randi_range(0, names.size() - 1)]
		var kin: String = KIN[SPECIES[species]["plan"]]
		var first := species
		var mates := names.filter(func(n: String) -> bool:
			return n != first and KIN[SPECIES[n]["plan"]] == kin)
		if mates.is_empty():
			mates = names.filter(func(n: String) -> bool: return n != first)
		blend = mates[g.rng.randi_range(0, mates.size() - 1)]
		g._blend_genes(species, blend, g.rng.randf_range(0.3, 0.7))
		suits = COATS
		wildness = maxf(wildness, 0.5)
	else:
		g.genes = BASE_GENES.duplicate()
		g.genes.merge(SPECIES[species]["genes"], true)
		suits = SPECIES[species]["coats"]
	g.plan = SPECIES[species]["plan"]
	g._jitter(lerpf(JITTER, WILD_JITTER, wildness))
	var forced: Dictionary = options.get("genes", {})
	for key in forced:
		if g.genes.has(key):
			g.genes[key] = forced[key]

	var poses: Array = PLANS[g.plan]
	var pose: String = options.get("pose", "random")
	if not pose in POSES:
		pose = g._least_used(poses, _recent_of(recent, "pose"), AVOID_RECENT_POSES)
	var coat: String = options.get("coat", "random")
	if not coat in COATS:
		var pool := suits.duplicate()
		if wildness > 0.0 and g.rng.randf() < wildness * 0.5:
			pool = COATS
		coat = g._least_used(pool, _recent_of(recent, "coat"), AVOID_RECENT_COATS)
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
		for m: String in MARKINGS:
			var chance: float = SPECIES[species].get(m, 0.0)
			if blend != "":
				chance = maxf(chance, SPECIES[blend].get(m, 0.0)) * 0.7
			if g.rng.randf() < chance:
				markings.append(m)

	g._water = pose == "swim"
	if g._water and scene == "none":
		scene = "field"
	g._rig()
	g._pose(pose)
	g._coat(coat, markings, seed_value)
	g._fit(facing, scene)
	g._fields()
	g._draw()
	g._mark()
	return {
		"seed": seed_value,
		"species": species,
		"blend": blend,
		"plan": g.plan,
		"coat": coat,
		"pose": pose,
		"facing": facing,
		"scene": "water" if g._water else g._scene,
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
	# Feet go with the legs' plan.
	genes["feet"] = ga["feet"]


## Every gene strays by up to `amount` of its range, staying in range.
func _jitter(amount: float) -> void:
	for key: String in GENE_RANGES:
		var r: Array = GENE_RANGES[key]
		if key in ["trunk", "hump"] and genes[key] <= 0.0:
			continue
		genes[key] = clampf(genes[key] + rng.randf_range(-1.0, 1.0) * amount * (r[1] - r[0]), r[0], r[1])


# --- sweeps --------------------------------------------------------------------------

## Thickness along a sweep from stations [[fraction, top, bottom], ...],
## eased between them.
static func _station(stations: Array, f: float) -> Vector2:
	if f <= stations[0][0]:
		return Vector2(stations[0][1], stations[0][2])
	for i in range(1, stations.size()):
		var b: Array = stations[i]
		if f <= b[0]:
			var a: Array = stations[i - 1]
			var t := smoothstep(0.0, 1.0, (f - a[0]) / maxf(0.0001, b[0] - a[0]))
			return Vector2(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t))
	var last: Array = stations[stations.size() - 1]
	return Vector2(last[1], last[2])


## A path from `start` heading `angle` (radians, y down), turning by
## `turn.call(f)` (radians per body length at fraction f), `n` samples over
## `length`.
static func _path(start: Vector2, angle: float, length: float, turn: Callable, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array([start])
	var a := angle
	var ds := length / n
	for i in n:
		var f := (i + 0.5) / n
		var k: float = turn.call(f)
		a += k * ds * 0.5
		pts.append(pts[i] + Vector2.from_angle(a) * ds)
		a += k * ds * 0.5
	return pts


## A sweep along `pts`: thickness above (top) and below (bottom) the path
## from `stations`. Returns {"pts", "n" (normals toward the bottom), "top",
## "bottom", "s" (distance along)}. `flip`: the bottom is on the path's left
## (for a head facing back, so its top stays up).
static func _sweep(pts: PackedVector2Array, stations: Array, flip := false) -> Dictionary:
	var n := pts.size()
	var normals := PackedVector2Array()
	var tops := PackedFloat32Array()
	var bottoms := PackedFloat32Array()
	var along := PackedFloat32Array()
	var total := 0.0
	for i in n:
		if i > 0:
			total += pts[i].distance_to(pts[i - 1])
		along.append(total)
	for i in n:
		var d := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		normals.append(d.rotated(-PI / 2.0 if flip else PI / 2.0))
		var th := _station(stations, along[i] / maxf(total, 0.0001))
		tops.append(th.x)
		bottoms.append(th.y)
	return {"pts": pts, "n": normals, "top": tops, "bottom": bottoms, "s": along}


## The point of a sweep at fraction f along it, `v` across (-1 top .. 1
## bottom).
static func _sweep_at(sw: Dictionary, f: float, v := 0.0) -> Vector2:
	var s: PackedFloat32Array = sw["s"]
	var target := clampf(f, 0.0, 1.0) * s[s.size() - 1]
	var i := 0
	while i < s.size() - 2 and s[i + 1] < target:
		i += 1
	var t := clampf((target - s[i]) / maxf(0.0001, s[i + 1] - s[i]), 0.0, 1.0)
	var p: Vector2 = sw["pts"][i].lerp(sw["pts"][i + 1], t)
	var nrm: Vector2 = sw["n"][i].lerp(sw["n"][i + 1], t).normalized()
	var top := lerpf(sw["top"][i], sw["top"][i + 1], t)
	var bottom := lerpf(sw["bottom"][i], sw["bottom"][i + 1], t)
	return p + nrm * ((bottom - top) * 0.5 + v * (bottom + top) * 0.5)


## The direction of a sweep at fraction f.
static func _sweep_dir(sw: Dictionary, f: float) -> Vector2:
	var a := _sweep_at(sw, maxf(0.0, f - 0.02))
	var b := _sweep_at(sw, minf(1.0, f + 0.02))
	return (b - a).normalized()


func _part(name: String, family := "coat", line := "", pattern := true, taper := 0.0) -> Dictionary:
	var p := {"name": name, "depth": 0.0, "family": family, "line": line if line != "" else name, "pattern": pattern,
			"taper": taper, "prims": [], "overlays": [], "len": 0.0}
	_parts.append(p)
	return p


## Adds a sweep's capsules to a part, its distance along starting at u0.
func _add_sweep(part: Dictionary, sw: Dictionary, u0 := 0.0) -> void:
	var pts: PackedVector2Array = sw["pts"]
	for i in pts.size() - 1:
		var c0: Vector2 = pts[i] + sw["n"][i] * (sw["bottom"][i] - sw["top"][i]) * 0.5
		var c1: Vector2 = pts[i + 1] + sw["n"][i + 1] * (sw["bottom"][i + 1] - sw["top"][i + 1]) * 0.5
		part["prims"].append({"kind": "cap", "a": c0, "b": c1,
				"ra": maxf(0.012, (sw["top"][i] + sw["bottom"][i]) * 0.5),
				"rb": maxf(0.012, (sw["top"][i + 1] + sw["bottom"][i + 1]) * 0.5),
				"u0": u0 + sw["s"][i], "u1": u0 + sw["s"][i + 1]})
	part["len"] = maxf(part["len"], u0 + sw["s"][pts.size() - 1])


## A chain of joints with a radius at each (a limb), densely sampled so it
## tapers smoothly between joints.
func _add_chain(part: Dictionary, pts: PackedVector2Array, radii: Array, u0 := 0.0) -> void:
	var total := 0.0
	var lengths := [0.0]
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
		lengths.append(total)
	var dense := PackedVector2Array()
	for i in pts.size() - 1:
		var k := maxi(2, ceili(pts[i].distance_to(pts[i + 1]) / 0.03))
		for j in k:
			dense.append(pts[i].lerp(pts[i + 1], float(j) / k))
	dense.append(pts[pts.size() - 1])
	var stations := []
	for i in pts.size():
		stations.append([lengths[i] / maxf(total, 0.0001), radii[i], radii[i]])
	_add_sweep(part, _sweep(dense, stations), u0)


func _ellipse(part: Dictionary, c: Vector2, r: Vector2, rot: float, u0: float) -> void:
	part["prims"].append({"kind": "ell", "c": c, "r": r, "rot": rot, "u0": u0})
	part["len"] = maxf(part["len"], u0 + r.x * 2.0)


# --- the rig ---------------------------------------------------------------------------

## The body's profile and the legs' segment lengths, from the genes.
func _rig() -> void:
	var g := genes
	var back: float = g["back"]
	var chest: float = g["chest"]
	var rump: float = g["rump"]
	var hump: float = g["hump"]
	# The rump tapers to the tail (a cat's), or stays deep, high and round
	# behind the haunches (`haunch`: an elephant's, a bear's).
	var haunch: float = g["haunch"]
	var hip_at: float = g["hip_at"]
	var high := back * (1.15 + 0.7 * haunch)
	var stations := [
		[0.0, lerpf(back * 1.3, high, 0.8), rump * lerpf(0.72, 1.05, haunch)],
		[hip_at * 0.5, high, rump * lerpf(0.88, 1.08, haunch)],
		[hip_at, high, rump * lerpf(1.0, 1.08, haunch)],
		[0.45, back, chest * g["tuck"]],
		[0.68, back + hump * 0.6, chest],
		[0.86, back + hump, chest * 0.97],
		[1.0, back * 1.5 + hump, chest * 0.85],
	]
	# A full rump (a bear's) runs straight on into the shoulders: no dip in
	# the back, no waist under the belly.
	if haunch > 0.0:
		var t := (0.45 - hip_at) / (0.68 - hip_at)
		stations[3][1] = lerpf(back, lerpf(high, back + hump * 0.6, t), haunch)
		stations[3][2] = lerpf(chest * g["tuck"], lerpf(rump * 1.08, chest, t), haunch)
	# A barrel chest (a horse's) keeps the ribs' full depth back to the
	# flank, where the thigh meets the body, then tapers quickly.
	var barrel: float = g["barrel"]
	if barrel > 0.0:
		stations[3][2] = chest * lerpf(g["tuck"], 0.97, barrel)
		stations.insert(3, [lerpf(hip_at + 0.22, hip_at + 0.12, barrel), back,
				lerpf(chest * g["tuck"], chest * 0.9, barrel)])
	_body["stations"] = stations
	var skull: float = g["skull"]
	var neck_end: float = skull * g["neck_w"]
	_body["neck_stations"] = [
		[0.0, back * 1.5 + hump, chest * 0.85],
		[0.45, lerpf(back * 1.5, neck_end, 0.55), lerpf(chest * 0.85, neck_end, 0.6)],
		[1.0, neck_end, neck_end],
	]
	var muzzle: float = g["muzzle"]
	var mw: float = skull * g["muzzle_w"]
	var jaw: float = skull * g["jaw"]
	var stop: float = 1.0 - muzzle
	_head["stations"] = [
		[0.0, skull * 0.78, skull * 0.72],
		[0.22, skull, jaw * 0.95],
		[stop * 0.8, skull * 0.95, jaw],
		[stop, lerpf(skull * 0.9, mw, 0.5), lerpf(jaw, mw, 0.35)],
		[lerpf(stop, 1.0, 0.55), mw * 1.05, mw * 1.0],
		[1.0, mw * 0.95, mw * 0.95],
	]
	# Legs, standing on a level back: how far below the spine the shoulder
	# and hip joints sit (as _shoulder and _hip find them), and the ground
	# `leg` below the chest.
	var at_s: Vector2 = _station(_body["stations"], SHOULDER_AT)
	var at_h: Vector2 = _station(_body["stations"], g["hip_at"])
	var shoulder_depth := (at_s.y - at_s.x) * 0.5 + 0.1 * (at_s.y + at_s.x) * 0.5
	var hip_depth := (at_h.y - at_h.x) * 0.5 + 0.05 * (at_h.y + at_h.x) * 0.5
	var ground: float = at_s.y + g["leg"]
	var front_h := ground - shoulder_depth
	var hind_h := ground - hip_depth
	var paw_h := _paw_height()
	var upper := chest * 0.6 + 0.02
	var rest := maxf(0.05, front_h - upper * 0.92 - paw_h)
	match g["feet"]:
		"hoof":
			_legs["front"] = [upper, rest * 0.58, rest * 0.44]
			_legs["hind"] = [hind_h * 0.4, hind_h * 0.44, hind_h * 0.4]
		"pillar":
			# The elbow sits high at the belly; the joint halfway down an
			# elephant's foreleg is its wrist, which folds the foot back.
			_legs["front"] = [upper, rest * 0.55, rest * 0.45]
			_legs["hind"] = [hind_h * 0.5, hind_h * 0.46, hind_h * 0.06]
		"plantigrade":
			_legs["front"] = [upper, rest * 0.95, g["paw"] * 1.6]
			_legs["hind"] = [hind_h * 0.52, hind_h * 0.5, g["paw"] * 2.6]
		_:
			_legs["front"] = [upper, rest * 0.72, rest * 0.33]
			_legs["hind"] = [hind_h * 0.42, hind_h * 0.45, hind_h * 0.33]
	# Each pair, standing at ease, reaches just that ground: its upper bones
	# scaled to fit (the lowest keeps its length: a bear's foot, a hoof's
	# cannon).
	var heights := {"front": front_h - paw_h, "hind": hind_h - paw_h}
	for key: String in heights:
		for _i in 4:
			var reach := _rest_reach(key == "front").y
			if reach <= 0.01:
				break
			var lens: Array = _legs[key]
			var k: float = clampf(1.0 + (heights[key] - reach) / (lens[0] + lens[1]), 0.5, 1.5)
			lens[0] *= k
			lens[1] *= k


## How high above the ground the lowest bone ends when the foot stands on
## it.
func _paw_height() -> float:
	match genes["feet"]:
		"hoof":
			return genes["leg_w"] * 2.1
		"pillar":
			return genes["leg_w"] * 0.6
		"plantigrade":
			return genes["leg_w"] * 0.75
	return genes["paw"] * 0.62


## The body (torso and neck) along a spine from the rump: pitch (radians,
## negative raises the front), the back's bow, the neck's angle (above
## level) and bend, a curl through both, and how long the torso looks
## (`length`: a sitting animal folds the small of its back under, so its
## body stands shorter). Returns the sweep.
func _spine(pitch: float, bow: float, neck_angle: float, neck_bend := 0.0, curl := 0.0, length := 1.0) -> Dictionary:
	var g := genes
	var bend: float = (bow + curl) / length
	var torso := _path(Vector2.ZERO, pitch - bend * length * 0.5, length, func(_f: float) -> float: return bend, 40)
	var a_end := pitch + bend * length * 0.5
	var target := -neck_angle
	var neck_len: float = g["neck"]
	var need := angle_difference(a_end, target)
	var turn := func(f: float) -> float:
		# Swing from the body's heading to the neck's over its first half,
		# then bend (curled necks keep curling).
		if curl != 0.0:
			return curl
		return need * (2.0 if f < 0.5 else 0.0) / maxf(neck_len, 0.01) + neck_bend * smoothstep(0.4, 1.0, f)
	var neck := _path(torso[torso.size() - 1], a_end, neck_len, turn, maxi(6, ceili(neck_len / 0.025)))
	var pts := torso.duplicate()
	for i in range(1, neck.size()):
		pts.append(neck[i])
	var total := length + neck_len
	var stations := []
	for st: Array in _body["stations"]:
		stations.append([st[0] * length / total, st[1], st[2]])
	for st: Array in _body["neck_stations"]:
		stations.append([(length + st[0] * neck_len) / total, st[1], st[2]])
	var sw := _sweep(pts, stations)
	sw["total"] = total
	sw["torso"] = length
	return sw


## Where along the body sweep a torso fraction falls.
func _body_f(f: float) -> float:
	return f * _body["sweep"]["torso"] / _body["sweep"]["total"]


func _shoulder() -> Vector2:
	return _sweep_at(_body["sweep"], _body_f(SHOULDER_AT), 0.1)


func _hip() -> Vector2:
	return _sweep_at(_body["sweep"], _body_f(genes["hip_at"]), 0.05)


## The lowest point of the body's underside between two torso fractions.
func _low(f0: float, f1: float) -> float:
	var y := -INF
	for k in 41:
		var f := lerpf(f0, f1, k / 40.0)
		y = maxf(y, _sweep_at(_body["sweep"], _body_f(f), 1.0).y)
	return y


## Where a leg's foot rests when it stands at ease: its joints at their
## resting turns (JOINTS), the wrist or hock under the shoulder or hip.
## Returns the end of its lowest bone, relative to the joint it hangs from.
## `ease` scales the turns (0.3: nearly straight).
func _rest_reach(front: bool, ease := 1.0) -> Vector2:
	var lens: Array = _legs["front" if front else "hind"]
	var rest: Array = JOINTS[genes["feet"]]["rest"].map(func(t: float) -> float: return t * ease)
	var k := 0 if front else 2
	var best := Vector2.ZERO
	var nearest := INF
	for i in 121:
		var a := lerpf(PI / 2.0 - 1.2, PI / 2.0 + 1.2, i / 120.0)
		var mid: Vector2 = Vector2.from_angle(a) * lens[0]
		var joint: Vector2 = mid + Vector2.from_angle(a + rest[k]) * lens[1]
		var end: Vector2 = joint + Vector2.from_angle(a + rest[k] + rest[k + 1]) * lens[2]
		if absf(joint.x) < nearest:
			nearest = absf(joint.x)
			best = end
	return best


## The ground under standing legs: halfway between where each pair, at
## ease, puts its feet (one bends a little more, the other straightens), but
## no further than either can reach nearly straight.
func _standing_ground() -> float:
	var front := _shoulder().y + _rest_reach(true).y
	var hind := _hip().y + _rest_reach(false).y
	var most := minf(_shoulder().y + _rest_reach(true, 0.3).y, _hip().y + _rest_reach(false, 0.3).y)
	return minf((front + hind) * 0.5, most) + _paw_height()


## Solves a two-bone limb from `root` toward `target`: the middle joint,
## bending one way (+1 back, -1 forward). Returns [mid, end].
static func _ik(root: Vector2, target: Vector2, a: float, b: float, bend: float) -> Array:
	var d := clampf(root.distance_to(target), absf(a - b) + 0.002, a + b - 0.002)
	var dir := (target - root).normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var mid := root + dir.rotated(bend * acos(cos_a)) * a
	return [mid, mid + (target - mid).normalized() * b]


## The two joint turns of a limb bent at `mid` and `joint`, then pointing
## `low`: the elbow and wrist of a front leg, or knee and hock of a hind one.
static func _turns(root: Vector2, mid: Vector2, joint: Vector2, low: Vector2) -> Vector2:
	var upper := (mid - root).angle()
	var lower := (joint - mid).angle()
	return Vector2(angle_difference(upper, lower), angle_difference(lower, low.angle()))


## A leg from its joint to `paw` (where the lowest bone ends). The leg
## finds its own shape: the slant of its lowest bone and which way its
## joints bend, as near as it can to a resting leg blended toward a folded
## one by `fold` (0..1), never past what a joint can do. A `planted` foot
## stands flat on the ground, its lowest bone within the foot's range (or
## `slants`: a foot lying along the ground); otherwise the bone points near
## `hint` (radians from straight down, foot ahead positive).
func _leg(name: String, front: bool, near: bool, paw: Vector2, hint: float, fold: float, planted: bool,
		slants: Array = []) -> void:
	var g := genes
	var lw: float = g["leg_w"]
	var feet: String = g["feet"]
	var lens: Array = _legs["front" if front else "hind"]
	var root := _shoulder() if front else _hip()
	var at := _body_f(SHOULDER_AT if front else genes["hip_at"])
	var up := (_sweep_at(_body["sweep"], at, -1.0) - _sweep_at(_body["sweep"], at, 1.0)).normalized()
	var k := 0 if front else 2
	var rest: Array = JOINTS[feet]["rest"]
	var folded: Array = JOINTS[feet]["fold"]
	var want := Vector2(lerpf(rest[k], folded[k], fold), lerpf(rest[k + 1], folded[k + 1], fold))
	var lim0: Array = JOINT_LIMITS[k]
	var lim1: Array = JOINT_LIMITS[k + 1]
	var lo := hint - 1.3
	var hi := hint + 1.3
	var hint_weight := 0.35
	if planted:
		var range: Array = slants if not slants.is_empty() else PLANTED[feet][0 if front else 1]
		lo = range[0]
		hi = range[1]
		hint = clampf(hint, lo, hi)
		hint_weight = 0.15
	var best := INF
	var mid := root
	var joint := root
	var low := Vector2.DOWN
	for i in 41:
		var slant := lerpf(lo, hi, i / 40.0)
		var dir := Vector2(sin(slant), cos(slant))
		var target: Vector2 = paw - dir * lens[2]
		var d := root.distance_to(target)
		var short: float = maxf(0.0, d - (lens[0] + lens[1])) + maxf(0.0, absf(lens[0] - lens[1]) - d)
		for bend in [1.0, -1.0]:
			var limb := _ik(root, target, lens[0], lens[1], bend)
			var t: Vector2 = _turns(root, limb[0], limb[1], dir)
			var over := maxf(0.0, lim0[0] - t.x) + maxf(0.0, t.x - lim0[1]) + maxf(0.0, lim1[0] - t.y) \
					+ maxf(0.0, t.y - lim1[1])
			var cost := (t - want).length_squared() + 60.0 * over * over + 400.0 * short * short \
					+ hint_weight * (slant - hint) * (slant - hint)
			if cost < best:
				best = cost
				mid = limb[0]
				joint = limb[1]
				low = dir
	var end: Vector2 = joint + low * lens[2]
	var depth := _sweep_at(_body["sweep"], at, -1.0).distance_to(_sweep_at(_body["sweep"], at, 1.0))
	var fill := 0.4 if front else (0.56 if plan == "ungulate" else 0.46)
	var top_r: float = minf(g["shoulder"] if front else g["thigh"], depth * fill)
	if feet == "pillar":
		top_r = minf(top_r, lw * 1.5)
	if not near:
		top_r *= 0.85
	var top := root + up * top_r * 0.45
	var pts := PackedVector2Array([top, root, mid, joint, end])
	var radii: Array
	if feet == "pillar":
		radii = [top_r * 0.9, top_r * 0.85, lw * 1.12, lw * 1.0, lw * 1.0]
	elif front:
		radii = [top_r * 0.9, top_r * 0.8, lw * 1.25, lw * 0.82, lw * 0.78]
	else:
		radii = [top_r, top_r * 0.82, lw * 1.3, lw * 0.78, lw * 0.72]
	if not front:
		# The thigh starts as the rump itself: the body's rounded rear end,
		# so the rump flows into the back of the leg instead of sticking out
		# behind it, and the thigh tapers from there to the knee.
		var sw: Dictionary = _body["sweep"]
		var back_r: float = (sw["top"][0] + sw["bottom"][0]) * 0.5
		var heading: Vector2 = (sw["pts"][1] - sw["pts"][0]).normalized()
		pts[0] = _sweep_at(sw, 0.0) - heading * back_r * (0.015 if near else -0.1)
		radii[0] = back_r * (1.0 if near else 0.88)
		radii[1] = maxf(radii[1], lerpf(radii[0], radii[2], 0.35))
	var part := _part(name, "coat", "legs")
	_add_chain(part, pts, radii)
	var length: float = part["len"]
	# A foot standing on the ground is flat; one lying along it, or raised,
	# follows its bone.
	var toe := low.rotated(-PI / 2.0)
	var down := low
	if planted and slants.is_empty():
		toe = Vector2.RIGHT
		down = Vector2.DOWN
	elif planted:
		toe = low
		down = low
	var paw_r: float = g["paw"]
	match feet:
		"hoof":
			_add_chain(part, PackedVector2Array([end, end + down * lw * 1.15]), [lw * 0.78, lw * 0.98], length)
			part["hoof_at"] = length
		"pillar":
			_ellipse(part, end + down * lw * 0.1, Vector2(lw * 1.15, lw * 0.5), toe.angle(), length)
		"plantigrade":
			_ellipse(part, end + toe * paw_r * 0.45, Vector2(paw_r * 1.2, paw_r * 0.6), toe.angle(), length)
		_:
			_ellipse(part, end + toe * paw_r * 0.45, Vector2(paw_r * 1.15, paw_r * 0.62), toe.angle(), length)
	part["foot_at"] = length


## The head along its axis from near the neck's end, pointing `angle`
## radians (below level); an elephant's carries on into its trunk.
func _build_head(angle: float) -> void:
	var g := genes
	var neck_end := _sweep_at(_body["sweep"], 1.0)
	var skull: float = g["skull"]
	var hd := Vector2.from_angle(angle)
	var flip := hd.x < 0.0
	var up := hd.rotated(PI / 2.0 if flip else -PI / 2.0)
	var start := neck_end - hd * skull * 0.45 + up * skull * 0.25
	var length: float = g["head"]
	var pts := _path(start, angle, length, func(_f: float) -> float: return 0.0, maxi(10, ceili(length / 0.02)))
	var stations: Array = _head["stations"].duplicate(true)
	var trunk: float = g["trunk"]
	var total := length
	if trunk > 0.0:
		# Down from the face, curling forward at the end.
		var mw: float = skull * g["muzzle_w"]
		var down := angle_difference(angle, PI / 2.0 + 0.1)
		var t_pts := _path(pts[pts.size() - 1], angle, trunk, func(f: float) -> float:
			return down * 2.2 / trunk if f < 0.5 else -2.4, 24)
		for i in range(1, t_pts.size()):
			pts.append(t_pts[i])
		total = length + trunk
		for st: Array in stations:
			st[0] = st[0] * length / total
		stations.append([(length + trunk * 0.5) / total, mw * 0.62, mw * 0.62])
		stations.append([1.0, mw * 0.4, mw * 0.4])
	var head_sw := _sweep(pts, stations, flip)
	_head["sweep"] = head_sw
	_head["len"] = length
	_head["frac"] = length / total
	var part := _part("head", "coat", "head", true, 1.0)
	_add_sweep(part, head_sw)
	part["head_len"] = length


## The tail from the rump: heading `angle`, turning `bend` (radians per
## body length) over its first half and `bend2` after; it lies along the
## ground if it reaches it.
func _build_tail(angle: float, bend: float, bend2: float, ground := INF) -> void:
	var g := genes
	var kind: String = g["tail"]
	var length: float = g["tail_len"]
	var w: float = g["tail_w"]
	var base := _sweep_at(_body["sweep"], _body_f(0.02), -0.55)
	var n := maxi(8, ceili(length / 0.02))
	var pts := _path(base, angle, length, func(f: float) -> float: return bend if f < 0.5 else bend2, n)
	var stations: Array
	match kind:
		"bushy":
			stations = [[0.0, w * 0.8, w * 0.8], [0.25, w * 1.5, w * 1.5], [0.6, w * 2.0, w * 2.0], [1.0, w * 0.9, w * 0.9]]
		"tapered":
			stations = [[0.0, w, w], [0.5, w * 0.75, w * 0.75], [1.0, w * 0.42, w * 0.42]]
		"tuft", "whip":
			stations = [[0.0, w * 1.4, w * 1.4], [0.2, w, w], [0.82, w * 0.85, w * 0.85], [0.92, w * 1.8, w * 1.8],
					[1.0, w * 1.0, w * 1.0]]
		"hair":
			stations = [[0.0, w * 0.9, w * 0.9], [0.2, w * 1.0, w * 1.0], [0.65, w * 1.45, w * 1.45],
					[1.0, w * 0.75, w * 0.75]]
		"short":
			stations = [[0.0, w * 1.2, w * 1.2], [1.0, w * 0.9, w * 0.9]]
		_:
			stations = [[0.0, w * 1.15, w * 1.15], [0.3, w, w], [1.0, w * 0.82, w * 0.82]]
	# A tail that reaches the ground lies along it.
	for i in pts.size():
		var r: float = _station(stations, float(i) / (pts.size() - 1)).x
		pts[i].y = minf(pts[i].y, ground - r)
	var part := _part("tail", "coat" if kind != "hair" else "hair", "tail", kind != "hair")
	_add_sweep(part, _sweep(pts, stations))


## A sleeping animal's legs and belly, tucked under the arch of its back
## (`center`), with a front paw under its chin (`chin`).
func _build_tuck(center: Vector2, chin: Vector2) -> void:
	var g := genes
	var mass := _part("hind", "coat", "legs")
	var r := Vector2(0.0, 0.0)
	# As wide and deep as the hollow under the arch.
	var left := INF
	var right := -INF
	var top := INF
	for k in 41:
		var q := _sweep_at(_body["sweep"], _body_f(k / 40.0), 1.0)
		left = minf(left, q.x)
		right = maxf(right, q.x)
		top = minf(top, q.y)
	r = Vector2((right - left) * 0.5 + 0.02, (_ground - top) * 0.5 + 0.02)
	_ellipse(mass, Vector2((left + right) * 0.5, _ground - r.y), r, 0.0, 0.0)
	mass["foot_at"] = r.x * 2.0
	var paw_r: float = g["paw"]
	var paw := _part("front", "coat", "legs")
	_ellipse(paw, Vector2(chin.x - paw_r * 0.6, _ground - paw_r * 0.7), Vector2(paw_r * 1.5, paw_r * 0.75), 0.0, 0.0)
	paw["foot_at"] = paw_r * 3.0
	_depth["hind"] = 3.5
	_depth["front"] = 5.5
	if center == Vector2.INF:
		return


func _build_ears() -> void:
	var g := genes
	var kind: String = g["ears"]
	var hs: Dictionary = _head["sweep"]
	var frac: float = _head["frac"]
	var skull: float = g["skull"]
	var es: float = g["ear_size"]
	var hd := _sweep_dir(hs, 0.2 * frac)
	var up := _head_up(0.2 * frac)
	for far in [true, false]:
		var base := _sweep_at(hs, (0.24 - (0.07 if far else 0.0)) * frac, -0.8)
		var name: String = "far_ear" if far else "ear"
		var part := {}
		match kind:
			"pointed":
				var d := (up * cos(0.35) - hd * sin(0.35)).rotated(-0.15 if far else 0.0)
				var length := skull * 1.15 * es
				var w := skull * 0.42 * es
				part = _part(name, "coat", "ears", false)
				_add_sweep(part, _sweep(PackedVector2Array([base - d * w * 0.4, base + d * length * 0.5, base + d * length]),
						[[0.0, w, w], [0.55, w * 0.62, w * 0.62], [1.0, w * 0.1, w * 0.1]]))
			"round", "small":
				var r := skull * es * (0.42 if kind == "round" else 0.3)
				var d := (up * cos(0.5) - hd * sin(0.5)).rotated(-0.2 if far else 0.0)
				part = _part(name, "coat", "ears", false)
				_ellipse(part, base + d * r * 0.55, Vector2(r * 0.88, r), d.angle() - PI / 2.0, 0.0)
			"floppy":
				if far:
					continue
				var down := -up
				var root := base - hd * skull * 0.05
				part = _part(name, "coat", "ears", false)
				_add_sweep(part, _sweep(PackedVector2Array([root, root - hd * skull * 0.35 + down * skull * 0.5 * es,
						root - hd * skull * 0.3 + down * skull * 1.15 * es]),
						[[0.0, skull * 0.3, skull * 0.3], [0.6, skull * 0.42 * es, skull * 0.42 * es],
						[1.0, skull * 0.3 * es, skull * 0.3 * es]]))
			"fan":
				if far:
					continue
				# Behind the eye, hanging down the side of the head and neck.
				var c := _sweep_at(hs, 0.12 * frac, -0.1) + Vector2(-skull * 0.55, skull * 0.35)
				part = _part(name, "coat", "ears", false)
				_ellipse(part, c, Vector2(skull * 0.7 * es, skull * 0.95 * es), -0.25, 0.0)
		if not part.is_empty():
			part["ear"] = kind


## Toward the top of the head at fraction f along it.
func _head_up(f: float) -> Vector2:
	var hs: Dictionary = _head["sweep"]
	return (_sweep_at(hs, f, -1.0) - _sweep_at(hs, f, 1.0)).normalized()


func _build_eye() -> void:
	var hs: Dictionary = _head["sweep"]
	var muzzle: float = genes["muzzle"]
	var skull: float = genes["skull"]
	var at := _sweep_at(hs, (1.0 - muzzle) * 0.82 * _head["frac"], -0.35)
	var r := clampf(skull * 0.19, 0.022, 0.04)
	var part := _part("eye", "eye", "eye", false)
	_ellipse(part, at, Vector2(r, r * 0.92), 0.0, 0.0)


func _build_horns() -> void:
	var g := genes
	var kind: String = g["horns"]
	if kind == "none":
		return
	var hs: Dictionary = _head["sweep"]
	var frac: float = _head["frac"]
	var skull: float = g["skull"]
	var hd := _sweep_dir(hs, 0.2 * frac)
	var up := _head_up(0.2 * frac)
	for far in [true, false]:
		var part := _part("far_horn" if far else "horn", "horns", "horns", false)
		var base := _sweep_at(hs, (0.3 - (0.08 if far else 0.0)) * frac, -0.7)
		if kind == "curved":
			var side := -0.25 if far else 0.0
			var pts := _path(base - up * skull * 0.2, (up.rotated(side) + hd * 0.4).angle(), skull * 1.3,
					func(_f: float) -> float: return 2.8, 10)
			_add_sweep(part, _sweep(pts, [[0.0, skull * 0.2, skull * 0.2], [1.0, skull * 0.05, skull * 0.05]]))
		else:
			var turn := -0.15 if far else 0.0
			var beam := _path(base - up * skull * 0.2, (up * 0.85 - hd * 0.5).angle() + turn, skull * 3.0,
					func(f: float) -> float: return 0.9 if f < 0.6 else -0.6, 16)
			_add_sweep(part, _sweep(beam, [[0.0, skull * 0.16, skull * 0.16], [1.0, skull * 0.06, skull * 0.06]]))
			for k in 3:
				var at := beam[4 + k * 4]
				var d := (up * 0.8 + hd * rng.randf_range(0.2, 0.8)).normalized().rotated(turn)
				_add_sweep(part, _sweep(PackedVector2Array([at, at + d * skull * rng.randf_range(0.7, 1.0)]),
						[[0.0, skull * 0.08, skull * 0.08], [1.0, skull * 0.05, skull * 0.05]]))


func _build_mane() -> void:
	var g := genes
	var kind: String = g["mane"]
	if kind == "none":
		return
	var sw: Dictionary = _body["sweep"]
	var total: float = sw["total"]
	var skull: float = g["skull"]
	if kind == "lion":
		# A ruff round the head and down the neck, its edge in tufts.
		var hs: Dictionary = _head["sweep"]
		var c := _sweep_at(hs, 0.2 * _head["frac"], 0.1)
		var part := _part("mane", "hair", "hair", false)
		var big := skull * 1.75
		_ellipse(part, c - _sweep_dir(hs, 0.1) * skull * 0.4, Vector2(big * 1.05, big), 0.0, 0.0)
		var neck := _sweep_at(sw, (1.0 + 0.4 * g["neck"]) / total, 0.0)
		_ellipse(part, neck, Vector2(big * 0.9, big * 0.95), 0.0, 0.0)
		var tufts := 13
		for k in tufts:
			var a := TAU * (k + rng.randf_range(-0.25, 0.25)) / tufts
			var d := Vector2.from_angle(a)
			var from := c.lerp(neck, 0.4) + d * big * 0.75
			_add_sweep(part, _sweep(PackedVector2Array([from, from + d * big * rng.randf_range(0.5, 0.75)]),
					[[0.0, big * 0.3, big * 0.3], [1.0, big * 0.07, big * 0.07]]))
		return
	# Along the top of the neck, from the withers to the poll.
	var pts := PackedVector2Array()
	var count := 16
	for k in count + 1:
		var f: float = (0.92 + (total - 0.92) * k / count) / total
		pts.append(_sweep_at(sw, minf(f, 0.995), -1.0))
	var stations := []
	for k in count + 1:
		var f := float(k) / count
		var depth: float = skull * (0.45 if kind == "horse" else 0.12)
		if kind == "horse":
			depth *= 0.75 + 0.45 * absf(sin(f * PI * 5.5))
		stations.append([f, skull * (0.12 if kind == "horse" else 0.28), depth])
	var part := _part("mane", "hair", "hair", false)
	_add_sweep(part, _sweep(pts, stations))


# --- poses ---------------------------------------------------------------------------

## Builds the posed animal: spine, legs, head, tail, ears, eye, horns, mane,
## and their depth order.
func _pose(pose: String) -> void:
	var g := genes
	var neck_angle := deg_to_rad(g["neck_angle"])
	var head_angle := deg_to_rad(g["head_angle"])
	var bow: float = g["arch"]
	var paw := _paw_height()
	var f: Array = _legs["front"]
	var h: Array = _legs["hind"]
	var reach_f: float = f[0] + f[1] + f[2]
	var reach_h: float = h[0] + h[1] + h[2]
	var tail := [PI / 2.0 + deg_to_rad(rng.randf_range(30.0, 70.0)), rng.randf_range(-1.5, 1.5),
			rng.randf_range(-2.0, 2.0)]
	var tail_ground := false
	_depth = {"far_hind": 0.0, "far_front": 1.0, "far_ear": 2.0, "far_horn": 2.2, "horn": 2.4, "tail": 3.0,
			"body": 4.0, "mane": 4.5, "head": 5.0, "hind": 6.0, "front": 7.0, "ear": 8.0, "eye": 9.0}
	if g["mane"] == "lion":
		_depth["mane"] = 4.6
	if g["ears"] in ["floppy", "fan"]:
		_depth["ear"] = 5.5
	var feet: String = g["feet"]
	var legs := {}
	var front_slant := 0.22 if feet == "paw" else (0.12 if feet == "hoof" else 0.0)
	var hind_slant := 0.12 if feet in ["paw", "hoof"] else 0.0
	if feet == "plantigrade":
		hind_slant = PI / 2.0 - 0.05
		front_slant = PI / 2.0 - 0.3
	var stride := rng.randf_range(0.6, 1.0)
	var lw: float = g["leg_w"]
	var flat := [1.3, 1.62]
	# A leg standing on the ground with its foot at x, folded `fold` (0..1,
	# a little different each leg).
	var plant := func(front: bool, x: float, fold: float) -> Array:
		return [Vector2(x, _ground - paw), front_slant if front else hind_slant,
				clampf(fold + rng.randf_range(-0.06, 0.06), 0.0, 1.0), true]
	# A leg whose foot lies flat along the ground from its heel at x.
	var lay := func(front: bool, x: float, fold: float) -> Array:
		var foot: float = f[2] if front else h[2]
		return [Vector2(x + foot, _ground - lw * 0.8), PI / 2.0 - 0.05, fold, true, flat]
	match pose:
		"stand", "walk", "graze":
			if pose == "graze":
				neck_angle = -deg_to_rad(rng.randf_range(35.0, 55.0))
				head_angle = deg_to_rad(rng.randf_range(80.0, 95.0))
			_body["sweep"] = _spine(deg_to_rad(rng.randf_range(-2.0, 2.0)), bow, neck_angle)
			_ground = _standing_ground()
			var spread := 0.13 * stride if pose == "walk" else 0.0
			var lifted := rng.randi_range(0, 3) if pose == "walk" and rng.randf() < 0.75 else -1
			var spots := [[true, false, -spread * 0.6 - 0.05], [false, false, spread * 0.6 + 0.05],
					[false, true, -spread], [true, true, spread]]
			if pose != "walk":
				spots = [[true, false, -0.06], [false, false, 0.06], [false, true, -0.02], [true, true, 0.03]]
			var relax := 0.0 if pose != "walk" else 0.08
			var at_ease := {true: _shoulder().x + _rest_reach(true).x, false: _hip().x + _rest_reach(false).x}
			for i in spots.size():
				var front: bool = spots[i][0]
				var x: float = at_ease[front] + spots[i][2]
				var leg: Array = plant.call(front, x, relax * (0.6 if front else 1.0))
				if i == lifted:
					leg = [leg[0] + Vector2(-0.06, -(0.12 + 0.12 * stride) * reach_f), -1.1 if front else -0.5,
							rng.randf_range(0.6, 0.85), false]
				legs[_leg_name(front, spots[i][1])] = leg
			if pose == "stand":
				tail = [PI / 2.0 + deg_to_rad(rng.randf_range(20.0, 50.0)), rng.randf_range(-1.0, 0.5),
						rng.randf_range(-2.5, 1.0)]
		"run":
			_body["sweep"] = _spine(deg_to_rad(rng.randf_range(-6.0, 2.0)), bow - 0.15, neck_angle * 0.5)
			head_angle *= 0.6
			_ground = _standing_ground() + 0.1
			# Stretched out in flight, or gathered with the legs folded under.
			var gathered := rng.randf() < 0.4
			for front in [true, false]:
				for near in [false, true]:
					var root: Vector2 = _shoulder() if front else _hip()
					var reach: float = reach_f if front else reach_h
					var lean: float
					var leg: Array
					if gathered:
						lean = (-0.3 if front else 0.55) + (0.12 if near else -0.1)
						leg = [root + Vector2(sin(lean), cos(lean)) * reach * 0.6, -1.4 if front else 0.6,
								0.8 if front else 0.65, false]
					else:
						lean = (1.05 if front else -0.95) + (0.12 if near else -0.15) * (1.0 if front else -1.0)
						leg = [root + Vector2(sin(lean), cos(lean)) * reach * 0.88, lean + (0.9 if front else -0.4),
								0.15 if near else 0.3, false]
					legs[_leg_name(front, near)] = leg
			tail = [PI - 0.2, rng.randf_range(-0.5, 0.5), rng.randf_range(-1.0, 1.0)]
		"pounce":
			# Crouched low, about to spring: rump a touch high, head low.
			_body["sweep"] = _spine(deg_to_rad(rng.randf_range(2.0, 7.0)), bow * 0.5, deg_to_rad(rng.randf_range(-8.0, 8.0)))
			head_angle = deg_to_rad(rng.randf_range(0.0, 15.0))
			_ground = minf(_hip().y + reach_h * 0.5, _shoulder().y + reach_f * 0.62)
			legs["front"] = plant.call(true, _shoulder().x + 0.16, 0.45)
			legs["far_front"] = plant.call(true, _shoulder().x + 0.05, 0.4)
			legs["hind"] = plant.call(false, _hip().x + 0.12, 0.85)
			legs["far_hind"] = plant.call(false, _hip().x + 0.05, 0.8)
			tail = [PI + deg_to_rad(rng.randf_range(-5.0, 15.0)), rng.randf_range(-0.3, 0.3), rng.randf_range(-2.5, 2.5)]
		"leap":
			_body["sweep"] = _spine(-deg_to_rad(rng.randf_range(12.0, 25.0)), bow - 0.2, neck_angle * 0.4)
			head_angle *= 0.5
			_ground = _standing_ground() + 0.25
			# Forepaws reaching out, or tucked up under the chest.
			var tuck := rng.randf() < 0.4
			for near in [false, true]:
				if tuck:
					legs[_leg_name(true, near)] = [_shoulder() + Vector2(0.06 if near else 0.0, reach_f * 0.5), -1.6, 0.9,
							false]
				else:
					var lean_f := 1.35 + (0.15 if near else 0.0)
					legs[_leg_name(true, near)] = [_shoulder() + Vector2(sin(lean_f), cos(lean_f)) * reach_f * 0.85,
							lean_f + 0.5, 0.1, false]
				var lean_h := -0.8 - (0.15 if near else 0.0)
				legs[_leg_name(false, near)] = [_hip() + Vector2(sin(lean_h), cos(lean_h)) * reach_h * 0.92, lean_h - 0.2,
						0.05 if near else 0.25, false]
			tail = [PI - 0.15, rng.randf_range(-0.6, 0.2), rng.randf_range(-1.0, 1.0)]
		"sit", "howl":
			# The body rises until the front legs stand straight with the rump
			# on the ground.
			var neck := neck_angle + deg_to_rad(20.0)
			if pose == "howl":
				neck = deg_to_rad(rng.randf_range(65.0, 80.0))
				head_angle = -deg_to_rad(rng.randf_range(40.0, 60.0))
			else:
				head_angle = deg_to_rad(rng.randf_range(0.0, 25.0))
			var lumbar := rng.randf_range(0.68, 0.76)
			var lo := -deg_to_rad(65.0)
			var hi := -deg_to_rad(20.0)
			for _i in 14:
				var mid := (lo + hi) * 0.5
				_body["sweep"] = _spine(mid, bow + 0.6, neck, 0.0, 0.0, lumbar)
				_ground = _low(0.0, 0.35)
				if _ground - paw - _shoulder().y > (f[0] * 0.9 + f[1] + f[2] * 0.95) * 0.97:
					lo = mid
				else:
					hi = mid
			_body["sweep"] = _spine(hi, bow + 0.6, neck, 0.0, 0.0, lumbar)
			_ground = _low(0.0, 0.35)
			for near in [false, true]:
				legs[_leg_name(true, near)] = plant.call(true, _shoulder().x + (0.05 if near else -0.02), 0.0)
				legs[_leg_name(false, near)] = lay.call(false, _hip().x - (0.0 if near else 0.03), 1.0)
			tail = [PI * 0.62, 0.0, -3.5]
			tail_ground = true
			_depth["tail"] = 6.5
			_depth["front"] = 7.2
		"lie", "rest":
			if pose == "rest":
				_body["sweep"] = _spine(deg_to_rad(rng.randf_range(-1.0, 3.0)), bow * 0.5, -deg_to_rad(rng.randf_range(5.0, 15.0)))
				head_angle = deg_to_rad(rng.randf_range(0.0, 15.0))
				_depth["head"] = 7.5
				_depth["ear"] = maxf(_depth["ear"], 7.6)
			else:
				_body["sweep"] = _spine(deg_to_rad(rng.randf_range(-2.0, 2.0)), bow * 0.5, neck_angle)
			_ground = _low(0.0, 1.0)
			var tucked := plan in ["ungulate", "heavy"]
			for near in [false, true]:
				var x0: float = _shoulder().x
				if tucked:
					# Forelegs folded back under the chest.
					legs[_leg_name(true, near)] = [Vector2(x0 - f[1] * 0.35 + (0.05 if near else 0.0), _ground - lw),
							-PI / 2.0, 1.0, true, [-1.75, -1.35]]
				else:
					# Forearms along the ground.
					legs[_leg_name(true, near)] = lay.call(true, x0 + (f[0] + f[1]) * (0.72 if near else 0.62), 0.55)
				legs[_leg_name(false, near)] = lay.call(false, _hip().x + (0.0 if near else -0.03), 1.0)
			tail = [PI * 0.75, -0.5, 1.0]
			tail_ground = true
		"curl":
			# Asleep in a ball: the spine curls round, the head tucks in, the
			# tail wraps over the paws.
			var curl := rng.randf_range(2.6, 2.95)
			_body["sweep"] = _spine(-deg_to_rad(rng.randf_range(80.0, 95.0)) + curl * 0.5, 0.0, 0.0, 0.0, curl)
			var neck_end := _sweep_at(_body["sweep"], 1.0)
			# The head rests at the front, facing back toward the tail.
			head_angle = PI - deg_to_rad(rng.randf_range(0.0, 20.0))
			_ground = _low(0.0, 1.0)
			var center := Vector2.ZERO
			for k in 8:
				center += _sweep_at(_body["sweep"], k / 8.0)
			center /= 8.0
			_body["tuck"] = [center, neck_end]
			tail = [PI / 2.0 + 0.3, -5.0, -0.8]
			tail_ground = true
			# The legs tuck away under the body.
			_depth = {"far_hind": 0.0, "far_front": 0.5, "front": 1.0, "hind": 1.5, "far_ear": 2.0, "far_horn": 2.2,
					"horn": 2.4, "body": 4.0, "mane": 4.5, "head": 6.0, "ear": 6.5, "tail": 7.0, "eye": 9.0}
		"stretch":
			# A play bow: rump up, forelegs flat on the ground.
			var lo := deg_to_rad(5.0)
			var hi := deg_to_rad(45.0)
			for _i in 14:
				var mid := (lo + hi) * 0.5
				_body["sweep"] = _spine(mid, bow * 0.4, deg_to_rad(10.0))
				_ground = _hip().y + reach_h * 0.88
				if _ground - _shoulder().y > f[0] * 0.75 + lw:
					lo = mid
				else:
					hi = mid
			_body["sweep"] = _spine(hi, bow * 0.4, deg_to_rad(10.0))
			_ground = _hip().y + reach_h * 0.88
			head_angle = deg_to_rad(rng.randf_range(-5.0, 10.0))
			for near in [false, true]:
				legs[_leg_name(true, near)] = lay.call(true, _shoulder().x + (f[0] + f[1]) * (0.8 if near else 0.7), 0.35)
				legs[_leg_name(false, near)] = plant.call(false, _hip().x + (0.03 if near else -0.03), 0.05)
			tail = [-PI / 2.0 - deg_to_rad(rng.randf_range(10.0, 50.0)), rng.randf_range(-1.0, 1.0),
					rng.randf_range(-2.0, 2.0)]
		"swim":
			_body["sweep"] = _spine(-deg_to_rad(rng.randf_range(3.0, 8.0)), bow * 0.5, neck_angle * 0.8 + deg_to_rad(8.0))
			head_angle *= 0.6
			_ground = _standing_ground() + 0.2
			# Paddling: one pair reaching, the other drawn back and folded.
			for k: Array in [[true, true, 0.9, 0.2], [true, false, -0.2, 0.75], [false, true, -0.9, 0.1],
					[false, false, 0.3, 0.7]]:
				var root: Vector2 = _shoulder() if k[0] else _hip()
				var reach: float = reach_f if k[0] else reach_h
				var lean: float = k[2]
				var fold: float = k[3]
				legs[_leg_name(k[0], k[1])] = [root + Vector2(sin(lean), cos(lean)) * reach * lerpf(0.96, 0.62, fold),
						lean + (0.0 if feet == "pillar" else 0.4), fold, false]
			tail = [PI - 0.1, rng.randf_range(-0.4, 0.4), rng.randf_range(-0.8, 0.8)]
	for name: String in legs:
		var leg: Array = legs[name]
		_leg(name, name.ends_with("front"), not name.begins_with("far"), leg[0], leg[1], leg[2], leg[3],
				leg[4] if leg.size() > 4 else [])
	if _body.has("tuck"):
		_build_tuck(_body["tuck"][0], _body["tuck"][1])
	_build_head(head_angle)
	_build_tail(tail[0], tail[1], tail[2], _ground if tail_ground else INF)
	_build_ears()
	_build_eye()
	_build_horns()
	_build_mane()
	var body := _part("body", "coat", "body", true, 1.0)
	_add_sweep(body, _body["sweep"])
	for part: Dictionary in _parts:
		part["depth"] = _depth.get(part["name"], 4.0)
	_parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["depth"] < b["depth"])


static func _leg_name(front: bool, near: bool) -> String:
	return ("" if near else "far_") + ("front" if front else "hind")


# --- markings ------------------------------------------------------------------------

## The coat and markings on each part, as overlays in the part's own
## coordinates (u along it, v across, r its half-width there).
func _coat(coat: String, markings: Array, seed_value: int) -> void:
	_markings = []
	var pattern := coat in CoatPatterns.COATS
	for part: Dictionary in _parts:
		var name: String = part["name"]
		var length: float = part["len"]
		var is_leg: bool = part.has("foot_at")
		var shift := rng.randf_range(0.0, 10.0)
		var overlays: Array = part["overlays"]
		# The coat's own markings, from a coat of the part's own.
		if pattern and part["pattern"]:
			var c := CoatPatterns.make(coat, hash([seed_value, name]), Rect2(-0.2, -0.4, length + 0.4, 0.8))
			var taper: float = part["taper"]
			part["coat"] = c
			overlays.append({"family": "markings", "fn": func(u: float, v: float, _r: float, q: Vector2) -> float:
				return c.value(q, u, v * taper)})
		match coat:
			"countershade":
				if name in ["body", "head"]:
					var level := rng.randf_range(0.05, 0.35) if name == "body" else 0.25
					overlays.append({"family": "belly", "fn": func(u: float, v: float, _r: float, _q: Vector2) -> float:
						return v - level + 0.08 * sin(u * 9.0 + shift)})
			"saddle":
				if name == "body":
					var at := rng.randf_range(0.42, 0.6)
					var half := rng.randf_range(0.11, 0.17)
					overlays.append({"family": "saddle", "fn": func(u: float, v: float, _r: float, _q: Vector2) -> float:
						return half - absf(u - at + 0.03 * sin(v * 3.0 + shift))})
			"appaloosa":
				if name == "body":
					var reach := rng.randf_range(0.32, 0.45)
					var blanket := func(u: float, v: float) -> float:
						return minf(reach - u + 0.04 * sin(v * 5.0 + shift), (0.25 - v) * 0.3)
					overlays.append({"family": "blanket", "fn": func(u: float, v: float, _r: float, _q: Vector2) -> float:
						return blanket.call(u, v)})
					var spots := CoatPatterns.make("dalmatian", hash([seed_value, "blanket"]), Rect2(-0.2, -0.4, 1.0, 0.8),
							0.8)
					part["coat"] = spots
					overlays.append({"family": "spots", "fn": func(u: float, v: float, _r: float, q: Vector2) -> float:
						return minf(spots.value(q, u, v), blanket.call(u, v) - 0.03)})
			"points":
				var from := -1.0
				if name == "head":
					from = (1.0 - genes["muzzle"]) * part["head_len"] * 0.85
				elif is_leg:
					from = part["foot_at"] * 0.55
				elif name == "tail":
					from = length * 0.35
				if from >= 0.0:
					overlays.append({"family": "points", "fn": func(u: float, _v: float, _r: float, _q: Vector2) -> float:
						return u - from})
				elif name.ends_with("ear"):
					part["family"] = "points"
		if "belly" in markings and coat != "countershade" and name == "body":
			var level := rng.randf_range(0.35, 0.55)
			overlays.append({"family": "belly", "fn": func(u: float, v: float, _r: float, _q: Vector2) -> float:
				return v - level + 0.06 * sin(u * 11.0 + shift)})
			_note("belly")
		if "socks" in markings and is_leg and rng.randf() < 0.65 and coat != "points":
			var from: float = part["foot_at"] * rng.randf_range(0.6, 0.85)
			overlays.append({"family": "socks", "fn": func(u: float, _v: float, _r: float, _q: Vector2) -> float:
				return u - from})
			_note("socks")
		if part.has("hoof_at"):
			var from: float = part["hoof_at"]
			overlays.append({"family": "hooves", "fn": func(u: float, _v: float, _r: float, _q: Vector2) -> float:
				return u - from})
		if name == "tail" and "tip" in markings and genes["tail"] in ["thin", "tapered", "bushy"]:
			var from: float = length * rng.randf_range(0.72, 0.85)
			overlays.append({"family": "tip", "fn": func(u: float, _v: float, _r: float, _q: Vector2) -> float:
				return u - from})
			_note("tip")
		if name == "tail" and genes["tail"] in ["tuft", "whip"]:
			var from: float = length * 0.84
			overlays.append({"family": "hair", "fn": func(u: float, _v: float, _r: float, _q: Vector2) -> float:
				return u - from})
		if name == "head":
			var head_len: float = part["head_len"]
			var stop: float = (1.0 - genes["muzzle"]) * head_len
			if "muzzle" in markings:
				overlays.append({"family": "muzzle", "fn": func(u: float, v: float, _r: float, _q: Vector2) -> float:
					return minf(u - stop * 0.92, v + 0.05 + 0.25 * clampf((u - stop) / maxf(0.01, head_len - stop), 0.0, 1.0))})
				_note("muzzle")
			if "blaze" in markings and genes["muzzle"] > 0.35:
				overlays.append({"family": "blaze", "fn": func(u: float, v: float, _r: float, _q: Vector2) -> float:
					return minf(minf(0.2 - absf(v + 0.62), u - head_len * 0.25), head_len * 0.97 - u)})
				_note("blaze")
			if plan in ["feline", "canine", "bear"]:
				overlays.append({"family": "nose", "fn": func(u: float, v: float, _r: float, _q: Vector2) -> float:
					return minf(u - head_len * 0.92, 0.15 - v)})
		if part.get("ear", "") in ["pointed", "round"] and name == "ear":
			overlays.append({"family": "inner_ear", "fn": func(u: float, v: float, _r: float, _q: Vector2) -> float:
				return minf(minf(0.5 - absf(v), (u - length * 0.12) * 4.0), (length * 0.78 - u) * 4.0)})


func _note(marking: String) -> void:
	if not marking in _markings:
		_markings.append(marking)


# --- placing -----------------------------------------------------------------------------

func _prim_box(prim: Dictionary) -> Rect2:
	if prim["kind"] == "cap":
		var a: Vector2 = prim["a"]
		var b: Vector2 = prim["b"]
		var r: float = maxf(prim["ra"], prim["rb"])
		return Rect2(a, Vector2.ZERO).expand(b).grow(r)
	var rr: Vector2 = prim["r"]
	return Rect2(prim["c"], Vector2.ZERO).grow(maxf(rr.x, rr.y))


func _part_box(part: Dictionary) -> Rect2:
	var box := Rect2()
	var first := true
	for prim: Dictionary in part["prims"]:
		box = _prim_box(prim) if first else box.merge(_prim_box(prim))
		first = false
	return box


## Scales and places the animal on the board, facing its way, and sets up
## its scene.
func _fit(facing: String, scene: String) -> void:
	var box := Rect2()
	var first := true
	for part: Dictionary in _parts:
		var b := _part_box(part)
		box = b if first else box.merge(b)
		first = false
	_fx = -1.0 if facing == "left" else 1.0
	_scene = scene
	var center := Vector2(box.get_center().x * _fx, box.get_center().y)
	match scene:
		"field":
			_s = minf(1.7 / box.size.x, 1.4 / box.size.y)
			_off = Vector2(-center.x * _s, 0.82 - box.end.y * _s)
		"round":
			_s = 1.72 / box.size.length()
			_off = -center * _s + Vector2(0.0, 0.03)
		_:
			_s = 1.8 / maxf(box.size.x, box.size.y)
			_off = -center * _s
	_box = _cells_of(box.grow(REACH + 0.05)).intersection(Rect2i(0, 0, N, N))
	if scene != "none":
		var y: float
		if _water:
			y = _water_level()
		else:
			y = lerpf(box.get_center().y, minf(_ground, box.end.y), rng.randf_range(0.3, 0.7))
		_horizon = [y * _s + _off.y, rng.randf_range(0.01, 0.04), rng.randf_range(1.0, 3.0), rng.randf() * TAU,
				rng.randf_range(-0.02, 0.02)]
		if _water:
			_horizon[1] = rng.randf_range(0.012, 0.022)
			_horizon[2] = rng.randf_range(6.0, 10.0)
		_box = Rect2i(0, 0, N, N)


## Swimmers: the water comes up to the back, or (hippos) the eyes.
func _water_level() -> float:
	if plan == "heavy" and genes["trunk"] <= 0.0:
		return _sweep_at(_head["sweep"], 0.4 * _head["frac"], -0.1).y
	return _sweep_at(_body["sweep"], _body_f(0.55), -0.55).y


## The grid cells (end exclusive) covering an animal-space box.
func _cells_of(box: Rect2) -> Rect2i:
	var p0 := to_unit(box.position)
	var p1 := to_unit(box.end)
	var x0 := FieldLines.cell_of(minf(p0.x, p1.x), N)
	var y0 := FieldLines.cell_of(minf(p0.y, p1.y), N)
	return Rect2i(x0, y0, FieldLines.cell_of(maxf(p0.x, p1.x), N) + 1 - x0,
			FieldLines.cell_of(maxf(p0.y, p1.y), N) + 1 - y0)


func to_unit(a: Vector2) -> Vector2:
	return Vector2(a.x * _fx, a.y) * _s + _off


func to_animal(p: Vector2) -> Vector2:
	var q := (p - _off) / _s
	return Vector2(q.x * _fx, q.y)


# --- fields ------------------------------------------------------------------------------

## Distance (animal units) from `a` to a prim, and its coordinates:
## (distance, along, across -1..1, half-width there).
static func _prim_at(prim: Dictionary, a: Vector2) -> Vector4:
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
		return Vector4(q.length() - r, lerpf(prim["u0"], prim["u1"], t), across, r)
	var rr: Vector2 = prim["r"]
	var local: Vector2 = (a - prim["c"]).rotated(-prim["rot"])
	var k0 := (local / rr).length()
	var k1 := (local / (rr * rr)).length()
	var d := k0 * (k0 - 1.0) / k1 if k1 > 0.0 else -minf(rr.x, rr.y)
	return Vector4(d, prim["u0"] + local.x + rr.x, local.y / rr.y, rr.y)


## Each part's distance field and coordinates over its own box, the
## silhouette, and each part's overlays.
func _fields() -> void:
	var step := 2.0 / N
	_total.resize(N * N)
	_total.fill(-BIG)
	for part: Dictionary in _parts:
		var box := _cells_of(_part_box(part).grow(REACH)).intersection(Rect2i(0, 0, N, N))
		var cells := box.size.x * box.size.y
		var sdf := PackedFloat32Array()
		sdf.resize(cells)
		sdf.fill(BIG)
		var us := PackedFloat32Array()
		us.resize(cells)
		var vs := PackedFloat32Array()
		vs.resize(cells)
		var rs := PackedFloat32Array()
		rs.resize(cells)
		for prim: Dictionary in part["prims"]:
			var r := _cells_of(_prim_box(prim).grow(REACH)).intersection(box)
			for cy in range(r.position.y, r.end.y):
				var py := -1.0 + (cy + 0.5) * step
				for cx in range(r.position.x, r.end.x):
					var at := _prim_at(prim, to_animal(Vector2(-1.0 + (cx + 0.5) * step, py)))
					var j := (cy - box.position.y) * box.size.x + cx - box.position.x
					if at.x < sdf[j]:
						sdf[j] = at.x
						us[j] = at.y
						vs[j] = at.z
						rs[j] = at.w
		# Distances in unit space, inside negative.
		for j in cells:
			if sdf[j] < BIG:
				sdf[j] *= _s
		part["box"] = box
		part["sdf"] = sdf
		part["u"] = us
		part["v"] = vs
		for cy in range(box.position.y, box.end.y):
			for cx in range(box.position.x, box.end.x):
				var i := cy * N + cx
				_total[i] = maxf(_total[i], -sdf[(cy - box.position.y) * box.size.x + cx - box.position.x])
		for overlay: Dictionary in part["overlays"]:
			var field := PackedFloat32Array()
			field.resize(cells)
			var fn: Callable = overlay["fn"]
			for j in cells:
				if sdf[j] > REACH * _s:
					field[j] = -1.0
					continue
				field[j] = fn.call(us[j], vs[j], rs[j], Vector2(us[j], vs[j] * rs[j]))
			overlay["field"] = field


## A part's field at unit point p (bilinear on its box), or `outside` beyond
## its box. `key`: "sdf", or an overlay's index.
static func _part_sample(part: Dictionary, key: Variant, p: Vector2, outside: float) -> float:
	var box: Rect2i = part["box"]
	var gx := (p.x + 1.0) * N * 0.5 - 0.5 - box.position.x
	var gy := (p.y + 1.0) * N * 0.5 - 0.5 - box.position.y
	if gx < 0.0 or gy < 0.0 or gx > box.size.x - 1.001 or gy > box.size.y - 1.001:
		return outside
	var field: PackedFloat32Array = part["sdf"] if key is String else part["overlays"][key]["field"]
	var x0 := int(gx)
	var y0 := int(gy)
	var fx := gx - x0
	var fy := gy - y0
	var w: int = box.size.x
	var i := y0 * w + x0
	return lerpf(lerpf(field[i], field[i + 1], fx), lerpf(field[i + w], field[i + w + 1], fx), fy)


func _inside(part: Dictionary, p: Vector2) -> bool:
	return _part_sample(part, "sdf", p, BIG) < 0.0


## The front-most part at unit point p (its index in _parts), or -1.
func _top(p: Vector2) -> int:
	for k in range(_parts.size() - 1, -1, -1):
		if _inside(_parts[k], p):
			return k
	return -1


## The overlay of a part showing at p (its index), or -1 for the plain coat.
func _overlay_at(part: Dictionary, p: Vector2) -> int:
	var overlays: Array = part["overlays"]
	for i in range(overlays.size() - 1, -1, -1):
		if _part_sample(part, i, p, -1.0) > 0.0:
			return i
	return -1


## What area p is in: a family name, or "" off the picture.
func _area_at(p: Vector2) -> String:
	var k := _top(p)
	if k < 0:
		return _scene_at(p)
	var part: Dictionary = _parts[k]
	var o := _overlay_at(part, p)
	return part["family"] if o < 0 else part["overlays"][o]["family"]


func _scene_at(p: Vector2) -> String:
	if _scene == "none" or not _on_board(p):
		return ""
	if _sun.z > 0.0 and p.distance_to(Vector2(_sun.x, _sun.y)) < _sun.z:
		return "sun"
	if p.y < _horizon_y(p.x):
		return "sky"
	return "water" if _water else "ground"


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


## A part's box-local field copied onto the whole grid (`outside` beyond its
## box, values times `sign`), for iso-lines.
func _grid_of(part: Dictionary, field: PackedFloat32Array, outside: float, sign: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(N * N)
	out.fill(outside)
	var box: Rect2i = part["box"]
	for cy in range(box.position.y, box.end.y):
		for cx in range(box.position.x, box.end.x):
			out[cy * N + cx] = field[(cy - box.position.y) * box.size.x + cx - box.position.x] * sign
	return out


func _draw() -> void:
	if _scene != "none":
		_draw_scene()
	for line: Dictionary in FieldLines.iso(_total, N, 0.0, _box, 0.05):
		_add(line["points"], line["closed"], "outline")
	for k in _parts.size():
		var part: Dictionary = _parts[k]
		var index := k
		var box: Rect2i = part["box"]
		var grow := box.grow(1).intersection(Rect2i(0, 0, N, N))
		# The part's outline wherever it lies over a part behind it and isn't
		# covered.
		if k > 0:
			var inside := func(p: Vector2) -> bool:
				var below := false
				for j in index:
					if _inside(_parts[j], p):
						below = true
						break
				if not below:
					return false
				for j in range(index + 1, _parts.size()):
					if _inside(_parts[j], p):
						return false
				return true
			var grid := _grid_of(part, part["sdf"], -BIG, -1.0)
			for line: Dictionary in FieldLines.iso(grid, N, 0.0, grow, 0.02):
				_add_pieces(FieldLines.clip(line["points"], line["closed"], inside), part["line"])
		# Its markings, where it shows and no later marking covers them.
		var overlays: Array = part["overlays"]
		for o in overlays.size():
			var oi := o
			var shows := func(p: Vector2) -> bool:
				if _top(p) != index:
					return false
				for later in range(oi + 1, overlays.size()):
					if _part_sample(part, later, p, -1.0) > 0.0:
						return false
				return true
			var grid := _grid_of(part, overlays[o]["field"], -1.0, 1.0)
			for line: Dictionary in FieldLines.iso(grid, N, 0.0, grow, 0.03):
				_add_pieces(FieldLines.clip(line["points"], line["closed"], shows), overlays[o]["family"])


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
	for i in 241:
		var x := -1.0 + i / 120.0
		horizon.append(Vector2(x, _horizon_y(x)))
	_add_pieces(FieldLines.clip(horizon, false, off_animal), "water" if _water else "horizon")
	# A sun in the sky, clear of the animal, the horizon and the edge.
	for _attempt in 30:
		var r := rng.randf_range(0.08, 0.14)
		var c := Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, maxf(-0.79, _horizon[0] - 0.2)))
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
## clear of every line), at most one per family in each block; then a
## tighter look for thin areas.
func _mark() -> void:
	var stride := 2
	var cols := N / stride
	var area := PackedStringArray()
	area.resize(cols * cols)
	var lo := _box.position / stride
	var hi := (_box.end / stride + Vector2i.ONE).min(Vector2i(cols, cols))
	for ly in range(lo.y, hi.y):
		for lx in range(lo.x, hi.x):
			var p := Vector2(FieldLines.cell_center(lx * stride, N), FieldLines.cell_center(ly * stride, N))
			if _scene == "none" and FieldLines.sample(_total, N, p) < -0.02:
				continue
			area[ly * cols + lx] = _area_at(p)
	var block := 4
	var taken := {}
	for pass_i in 2:
		for ly in range(maxi(lo.y, 1), mini(hi.y, cols - 1)):
			for lx in range(maxi(lo.x, 1), mini(hi.x, cols - 1)):
				var here := area[ly * cols + lx]
				if here == "" or here == "eye" or taken.has([lx / block, ly / block, here]):
					continue
				var p := Vector2(FieldLines.cell_center(lx * stride, N), FieldLines.cell_center(ly * stride, N))
				var ok := true
				if pass_i == 0:
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							if area[(ly + dy) * cols + lx + dx] != here:
								ok = false
				else:
					var key := [lx / 2, ly / 2, here, 1]
					if taken.has(key):
						continue
					for k in 8:
						if _area_at(p + Vector2.from_angle(TAU * k / 8.0) * TIGHT) != here:
							ok = false
							break
					if ok:
						taken[key] = true
				if ok:
					taken[[lx / block, ly / block, here]] = true
					marks.append({"at": p, "family": _family(here)})

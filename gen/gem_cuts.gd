class_name GemCuts
extends RefCounted
## Facet styles a gem of each shape can be cut in. The 2D outline (see
## GemShapes) says where a stone sits; its cut says how its top is faceted
## in 3D (see GemMesh), so one outline makes several gem types.
##
## brilliant: a table ringed by kite and triangle facets (the classic sparkle)
## step: flat steps down from the table, like an emerald cut
## rose: no table, a dome of triangles rising to a point
## checker: a low dome of many small facets
## cabochon: a smooth polished dome, no facets

const ALL := ["brilliant", "step", "rose", "checker", "cabochon"]
## Each shape's cuts, its classic one first.
const BY_SHAPE := {
	"round": ["brilliant", "rose", "checker", "cabochon"],
	"oval": ["brilliant", "step", "checker", "cabochon"],
	"cushion": ["brilliant", "checker", "step"],
	"square": ["step", "brilliant", "checker"],
	"octagon": ["step", "brilliant", "checker"],
	"hexagon": ["brilliant", "step", "checker"],
	"pentagon": ["brilliant", "step", "checker"],
	"triangle": ["brilliant", "step"],
	"trillion": ["brilliant", "step"],
	"heart": ["brilliant", "checker", "cabochon"],
	"star": ["brilliant", "step"],
	"flower": ["rose", "brilliant", "cabochon"],
	"marquise": ["brilliant", "step"],
	"teardrop": ["brilliant", "rose", "cabochon"],
	"kite": ["brilliant", "step"],
	"lozenge": ["brilliant", "step"],
	"baguette": ["step", "brilliant"],
	"emerald": ["step", "brilliant"],
}
## Chance a gem type takes its shape's classic cut; the rest pick evenly
## among the others.
const CLASSIC_CHANCE := 0.5


static func for_shape(shape: String) -> Array:
	return BY_SHAPE.get(shape, ["brilliant"])


## The cut a gem type (shape in a color, keyed by `type_key`) gets in a
## picture: the same for every stone of that type. `cuts` narrows the
## choice (in for_shape's order, so its first is the classic one if allowed).
static func pick(shape: String, type_key: String, seed_value: int, cuts: Array = []) -> String:
	if cuts.is_empty():
		cuts = for_shape(shape)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, shape, type_key, "cut"])
	if cuts.size() == 1 or rng.randf() < CLASSIC_CHANCE:
		return cuts[0]
	return cuts[rng.randi_range(1, cuts.size() - 1)]

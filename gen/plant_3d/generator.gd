class_name PlantMeshGenerator
extends RefCounted
## Same entry/return contract as AnimalMeshGenerator, ready for a caller to
## register as a picture source. No game routing or scene setup happens here.


static func generate(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var built := surface(seed_value, options)
	if built.is_empty():
		return {}
	var recipe: Dictionary = built.recipe
	var result := PlantSurfaceProjection.project(built.data, recipe.camera, recipe.projection_size)
	if result.is_empty():
		return {}
	var design: Dictionary = result.design
	design.merge({"seed": seed_value, "symmetry": "none", "stem": recipe.curve + "_" + recipe.branching,
		"curve": recipe.curve, "branching": recipe.branching, "flowers": recipe.flowers,
		"flower": recipe.flower, "leaf": recipe.leaf, "pose": recipe.pose, "camera": recipe.camera,
		"component_variant": recipe.component_variant, "controls": recipe.controls.duplicate(),
		"stats": built.stats.duplicate(), "recipe": recipe.duplicate(true),
		"asset_revision": recipe.asset_revision, "source_sha256": PlantComponentData.CATALOG.data.source_sha256,
		"projection": "orthographic", "backend": "native modular plant"})
	return design


## Optional plain-array surface for previews/debugging. Does not project or
## create a Godot Mesh resource. A recipe is the only supported replay token.
static func surface(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var recipe := PlantParameters.resolve(seed_value, options)
	if recipe.is_empty():
		return {}
	var built := PlantGrowth.assemble(recipe)
	if built.is_empty():
		return {}
	built.recipe = recipe
	built.data.metadata = {"recipe": recipe.duplicate(true), "stats": built.stats.duplicate()}
	return built


static func catalog() -> Dictionary:
	return {"leaves": PlantComponentData.families("leaves"),
		"flowers": PlantComponentData.families("flowers"), "buds": PlantComponentData.families("buds"),
		"curves": PackedStringArray(PlantParameters.CURVES), "branching": PackedStringArray(PlantParameters.BRANCHING),
		"flowering": PackedStringArray(PlantParameters.FLOWERING),
		"poses": PackedStringArray(PlantParameters.POSES.keys()),
		"cameras": PackedStringArray(PlantSurfaceProjection.VIEWS.keys()),
		"variants": PackedStringArray(PlantComponentData.CATALOG.data.variants),
		"asset_revision": PlantComponentData.CATALOG.data.revision}

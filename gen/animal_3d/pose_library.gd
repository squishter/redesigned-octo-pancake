class_name AnimalPoseLibrary
extends RefCounted
## App-facing entry point for the sourced animal poses.

const CATALOG = preload("res://assets/animals/catalog.json")


static func model_ids() -> PackedStringArray:
	return PackedStringArray(CATALOG.data.models.keys())


static func model_info(id: String) -> Dictionary:
	return CATALOG.data.models.get(id, {}).duplicate(true)


static func spawn(parent: Node, id: String, height := 1.0) -> AnimalPoseModel:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	if not CATALOG.data.models.has(id) or not is_finite(height) or height <= 0:
		return null
	var info: Dictionary = CATALOG.data.models[id]
	var packed := load(info.scene) as PackedScene
	if packed == null:
		return null
	var animal := AnimalPoseModel.new()
	animal.name = id
	parent.add_child(animal)
	if not animal.configure(id, info, packed.instantiate(), height):
		animal.free()
		return null
	return animal

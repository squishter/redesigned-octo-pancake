class_name AnimalMeshGenerator
extends RefCounted
## Production animal source: frozen rig poses + seeded surface coats -> the
## app's ordinary polylines, motif families and closed paintable regions.

const CATALOG = preload("res://assets/animals/posed/catalog.json")
## Caricature "toy" meshes (Gobkit's big-eyed, blocky animals). A seeded pick
## draws from them only this often, so most pictures show lifelike animals.
const TOY_PREFIXES := ["gobkit_"]
const TOY_CHANCE := 0.1


static func is_toy(model_id: String) -> bool:
	return TOY_PREFIXES.any(func(prefix: String) -> bool: return model_id.begins_with(prefix))


## A seeded model, skipping the last 3 `recent` records ({"model": id}) and
## choosing a toy mesh with TOY_CHANCE (when one is left to choose).
static func pick_model(rng: RandomNumberGenerator, recent: Array = []) -> String:
	var used := []
	for row: Variant in recent.slice(maxi(0, recent.size() - 3)):
		if row is Dictionary:
			used.append(row.get("model", ""))
	var choices: Array = CATALOG.data.models.keys().filter(func(key): return key not in used)
	var toys := choices.filter(is_toy)
	var lifelike := choices.filter(func(key): return not is_toy(key))
	var pool := lifelike
	if lifelike.is_empty() or (not toys.is_empty() and rng.randf() < TOY_CHANCE):
		pool = toys
	return pool[rng.randi_range(0, pool.size() - 1)]


static func generate(seed_value: int, options: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var id: String = options.get("model", "")
	if id not in CATALOG.data.models:
		id = pick_model(rng, options.get("recent", []))
	var info: Dictionary = CATALOG.data.models[id]
	var file := FileAccess.open_compressed(info.file, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		push_error("Missing animal pose data: " + id)
		return {}
	var stored: Dictionary = file.get_var()
	file.close()
	var states: Array = stored.states
	var pose_name: String = options.get("pose", "")
	var candidates := states.filter(func(row): return row.pose.preset == pose_name)
	var saved_pose: Variant = options.get("pose_record", {})
	if saved_pose is Dictionary and not saved_pose.is_empty():
		candidates = states.filter(
			func(row):
				return (
					row.pose.preset == saved_pose.get("preset")
					and row.pose.seed == saved_pose.get("seed")
					and is_equal_approx(row.pose.phase, saved_pose.get("phase", -1))
				)
		)
	if candidates.is_empty():
		candidates = states
	var state: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	var views: Array = state.cameras.keys()
	var view: String = options.get("camera", "")
	if view not in views:
		var portraits := views.filter(func(key): return str(key).begins_with("head_"))
		var body := views.filter(func(key): return not str(key).begins_with("head_"))
		var pool: Array = portraits if not portraits.is_empty() and rng.randf() < 0.24 else body
		view = pool[rng.randi_range(0, pool.size() - 1)]
	var data: Dictionary = stored.attributes.duplicate()
	data.vertices = AnimalPoseData.vertices(stored, state)
	var whole := data
	if view.begins_with("head_"):
		data = AnimalSkinSampler.subset(data, stored.head_indices)
	var mode: String = options.get("coat_mode", "mixed")
	if mode == "mixed":
		mode = "natural" if rng.randf() < 0.65 else "decorative"
	var styles := AnimalSurfaceCoat.available(id, mode)
	var saved_coat: Variant = options.get("coat", "")
	var coat_record: Dictionary = saved_coat if saved_coat is Dictionary else {}
	var style: String = (
		coat_record.get("style", "") if saved_coat is Dictionary else str(saved_coat)
	)
	if style not in AnimalSurfaceCoat.available(id):
		style = styles[rng.randi_range(0, styles.size() - 1)]
	var coat := AnimalSurfaceCoat.make(
		id,
		style,
		options.get("coat_seed", coat_record.get("seed", seed_value)),
		options.get("coat_scale", coat_record.get("scale", 1.0))
	)
	if coat != null:
		coat.fit(whole)  # Head crops share the full body's motif layout.
	var result := AnimalSurfaceProjection.project(data, state.cameras[view], coat, 320)
	if result.is_empty():
		return {}
	var design: Dictionary = result.design
	var pose_record := {}
	for key in [
		"version", "preset", "seed", "amount", "overrides", "phase", "clip", "time", "grounding"
	]:
		pose_record[key] = state.pose[key]
	design.merge(
		{
			"seed": seed_value,
			"species": info.name,
			"blend": "",
			"plan": info.anatomy,
			"pose": state.pose.preset,
			"facing": "front" if view.begins_with("head_") or view == "front" else "side",
			"scene": "none",
			"feet": "",
			"ears": "",
			"horns": "",
			"tail": "",
			"mane": "",
			"markings": style,
			"model": id,
			"camera": view,
			"pose_record": pose_record,
			"pose_data_sha256": info.data_sha256,
			"source_sha256": info.source_sha256,
			"projection": "orthographic",
			"backend": "rigged surface"
		}
	)
	return design

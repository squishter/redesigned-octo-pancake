class_name PlantParameters
extends RefCounted
## The canonical, JSON-safe request used by the Godot backend. Its own version
## distinguishes native Godot seeds from the offline Python authoring recipes.

const VERSION := 1
const CURVES := ["straight", "gentle", "winding"]
const BRANCHING := ["none", "few", "many"]
const FLOWERING := ["one", "few", "many"]
const POSES := {
	"upright": {"bend_x": 0., "bend_z": 0., "spread": 1., "leaf_pitch": .18, "leaf_curl": .10, "opening": 1.},
	"reaching": {"bend_x": .18, "bend_z": -.10, "spread": 1.12, "leaf_pitch": .3, "leaf_curl": .24, "opening": .85},
	"nodding": {"bend_x": -.16, "bend_z": .12, "spread": .85, "leaf_pitch": -.1, "leaf_curl": .35, "opening": .72},
}
const LIMITS := {
	"length": [1.4, 3.2], "radius": [.012, .04], "curve_amount": [0., 1.],
	"bends": [.35, 2.8], "spread": [.55, 1.4], "primary_count": [0, 7],
	"secondary_count": [0, 3], "flower_count": [1, 24], "bud_count": [0, 6],
	"leaf_scale": [.16, .55], "flower_scale": [.32, 1.15], "leaf_density": [0., 1.5],
	"bend_angle_min": [0., 60.], "bend_angle_max": [0., 65.],
	"branch_spacing_min": [.025, .12], "branch_spacing_max": [.08, .3], "cluster_chance": [0., 1.],
	"flower_angle_jitter": [0., 10.], "flower_scale_jitter": [0., .15], "flower_shape_jitter": [0., .10],
	"bloom_min": [0., 1.], "bloom_max": [0., 1.],
}
const COUNTS := ["primary_count", "secondary_count", "flower_count", "bud_count"]
const POSE_LIMITS := {
	"bend_x": [-.35, .35], "bend_z": [-.35, .35], "spread": [.7, 1.3],
	"leaf_pitch": [-.4, .5], "leaf_curl": [0., .5], "opening": [.4, 1.],
}


static func resolve(seed_value: int, options: Dictionary) -> Dictionary:
	if seed_value < 0 or seed_value > 4294967295:
		return {}
	var opts := options.duplicate(true)
	var replay := false
	if opts.has("recipe"):
		if not opts.recipe is Dictionary:
			return {}
		opts = opts.recipe.duplicate(true)
		replay = true
	elif opts.has("recipe_version"):
		replay = true
	var catalog: Dictionary = PlantComponentData.CATALOG.data
	if replay:
		if opts.get("recipe_version") != VERSION or opts.get("asset_revision") != catalog.revision:
			return {}
		if opts.get("seed") != seed_value:
			return {}
		for key in ["curve", "branching", "flowers", "flower", "leaf", "component_variant", "pose", "camera",
				"controls", "pose_controls", "projection_size"]:
			if not opts.has(key):
				return {}
		for key in ["curve", "branching", "flowers", "flower", "leaf", "component_variant", "pose", "camera"]:
			if opts[key] in ["", "random"]:
				return {}
		if not opts.controls is Dictionary or not opts.pose_controls is Dictionary:
			return {}
		if opts.controls.size() != LIMITS.size() or opts.pose_controls.size() != POSE_LIMITS.size():
			return {}
	# Authoring growth records can supply matching controls, but the native
	# backend has its own deterministic random streams and replay namespace.
	if opts.has("growth"):
		if not opts.growth is Dictionary or opts.growth.get("seed", seed_value) != seed_value:
			return {}
		var authored: Dictionary = opts.growth
		for key in ["curve", "branching", "flowers", "controls"]:
			if not opts.has(key) and authored.has(key):
				opts[key] = authored[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var recent: Array = opts.get("recent", []) if opts.get("recent", []) is Array else []
	var curve := _choice(opts, "curve", CURVES, rng)
	var branching := _choice(opts, "branching", BRANCHING, rng)
	var flowers := _choice(opts, "flowers", FLOWERING, rng)
	var flower := _choice(opts, "flower", catalog.flowers.keys(), rng, recent)
	var leaf := _choice(opts, "leaf", catalog.leaves.keys(), rng, recent)
	var variant := _choice(opts, "component_variant", catalog.variants, rng)
	var pose := _choice(opts, "pose", POSES.keys(), rng)
	var camera := _choice(opts, "camera", PlantSurfaceProjection.VIEWS.keys(), rng)
	if "" in [curve, branching, flowers, flower, leaf, variant, pose, camera]:
		return {}
	var c := {
		"length": 2.25, "radius": .024, "curve_amount": 0. if curve == "straight" else 1.,
		"bends": {"straight": .5, "gentle": .55, "winding": 1.8}[curve], "spread": .95,
		"primary_count": {"none": 0, "few": 3, "many": 5}[branching],
		"secondary_count": 2 if branching == "many" else 0,
		"flower_count": {"one": 1, "few": 5, "many": 15}[flowers], "bud_count": 0,
		"leaf_scale": .42 if branching == "none" else .31,
		"flower_scale": {"one": 1., "few": .73, "many": .56}[flowers], "leaf_density": 1.,
		"bend_angle_min": {"straight": 0., "gentle": 8., "winding": 20.}[curve],
		"bend_angle_max": {"straight": 0., "gentle": 22., "winding": 55.}[curve],
		"branch_spacing_min": .035, "branch_spacing_max": .22, "cluster_chance": .55,
		"flower_angle_jitter": 6., "flower_scale_jitter": .10, "flower_shape_jitter": .045,
		"bloom_min": .35, "bloom_max": 1.,
	}
	if not opts.get("controls", {}) is Dictionary:
		return {}
	for key in opts.get("controls", {}):
		if not LIMITS.has(key):
			return {}
		c[key] = opts.controls[key]
	for key in LIMITS:
		if opts.has(key):
			c[key] = opts[key]
		if not _number(c[key], LIMITS[key]):
			return {}
		if key in COUNTS:
			if float(c[key]) != floor(float(c[key])):
				return {}
			c[key] = int(c[key])
		else:
			c[key] = float(c[key])
	if c.primary_count == 0 and c.secondary_count > 0:
		return {}
	if c.bend_angle_min > c.bend_angle_max or c.bloom_min > c.bloom_max or c.branch_spacing_min > c.branch_spacing_max:
		return {}
	if maxi(0, c.primary_count - 1) * c.branch_spacing_min > .60:
		return {}
	if c.flower_count == 1:
		c.bloom_min = maxf(.55, c.bloom_min)
		c.bloom_max = maxf(c.bloom_min, c.bloom_max)
	var p: Dictionary = POSES[pose].duplicate()
	if not opts.get("pose_controls", {}) is Dictionary:
		return {}
	for key in opts.get("pose_controls", {}):
		if not POSE_LIMITS.has(key):
			return {}
		p[key] = opts.pose_controls[key]
	for key in POSE_LIMITS:
		if not _number(p[key], POSE_LIMITS[key]):
			return {}
		p[key] = float(p[key])
	var size: Variant = opts.get("projection_size", 320)
	if not _number(size, [64, 512]) or float(size) != floor(float(size)):
		return {}
	return {"recipe_version": VERSION, "asset_revision": catalog.revision, "seed": seed_value,
		"curve": curve, "branching": branching, "flowers": flowers, "flower": flower, "leaf": leaf,
		"component_variant": variant, "pose": pose, "camera": camera, "controls": c,
		"pose_controls": p, "projection_size": int(size)}


static func _number(value: Variant, bounds: Array) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= bounds[0] and value <= bounds[1]


static func _choice(opts: Dictionary, key: String, values: Array, rng: RandomNumberGenerator, recent: Array = []) -> String:
	var requested: Variant = opts.get(key, "random")
	if not requested is String:
		return ""
	if requested != "random" and requested != "":
		return requested if requested in values else ""
	var used := []
	for row: Variant in recent.slice(maxi(0, recent.size() - 3)):
		if row is Dictionary:
			used.append(row.get(key, ""))
	var choices := values.filter(func(value): return value not in used)
	if choices.is_empty():
		choices = values
	return str(choices[rng.randi_range(0, choices.size() - 1)])

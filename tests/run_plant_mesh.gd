extends SceneTree
## Native entry-point contract, geometry, seed replay and downstream consumers.
## godot --headless --path . -s res://tests/run_plant_mesh.gd

var failures := 0
var checks := 0
var worker_result := {}
var out := "/tmp/plant-godot-checks"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("_run")


func _run() -> void:
	_components()
	if failures:
		quit(1)
		return
	_pack()
	_geometry()
	_invalid()
	var reference := {}
	var base := {"curve": "gentle", "branching": "few", "flowers": "few", "flower": "rose",
		"leaf": "serrated", "component_variant": "reference", "pose": "upright", "camera": "three_quarter"}
	for view: String in PlantSurfaceProjection.VIEWS:
		var options := base.duplicate()
		options.camera = view
		var start := Time.get_ticks_msec()
		var design := PlantMeshGenerator.generate(81, options)
		_check(not design.is_empty(), view + " native design")
		if design.is_empty():
			continue
		_projection(design, view)
		if view == "three_quarter":
			reference = design
			_pipeline(design)
		AnimalSurfaceProjection.line_image(design, 512).save_png(out.path_join(view + ".png"))
		print(view, ": ", design.polylines.size(), " paths, ", Time.get_ticks_msec() - start, "ms")
	if not reference.is_empty():
		# Same serialized recipe after other requests, then on a worker thread.
		var saved := PatternIO.from_json(PatternIO.to_json({"source": {"plant_mesh": reference.recipe}}))
		var replay := PlantMeshGenerator.generate(81, {"recipe": saved.source.plant_mesh})
		_check(_same_design(reference, replay), "JSON recipe replays exact contours and marks")
		var task := WorkerThreadPool.add_task(func() -> void:
			worker_result = PlantMeshGenerator.generate(81, {"recipe": saved.source.plant_mesh}))
		while not WorkerThreadPool.is_task_completed(task):
			await process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		_check(_same_design(reference, worker_result), "worker output matches main thread")
	print("%s: %d native plant checks, %d failures" % ["FAILED" if failures else "PASSED", checks, failures])
	quit(1 if failures else 0)


func _components() -> void:
	var catalog := PlantMeshGenerator.catalog()
	_check(catalog.leaves.size() == 24 and catalog.flowers.size() == 32 and catalog.buds.size() == 5, "component roster")
	for group in ["leaves", "flowers", "buds"]:
		for family in catalog[group]:
			var info: Dictionary = PlantComponentData.CATALOG.data[group][family]
			_check(FileAccess.get_sha256(info.file) == info.sha256, "asset checksum " + family)
			for variant in catalog.variants:
				var data := PlantComponentData.load_component(group, family, variant)
				_check(not data.is_empty(), family + " " + variant + " loads")
				if data.is_empty():
					continue
				_check(data.open.size() == int(info.vertices) and data.open.size() == data.closed.size(), family + " vertex attributes")
				var finite := true
				for i in data.open.size():
					finite = finite and data.open[i].is_finite() and data.closed[i].is_finite()
				_check(finite, family + " finite morph endpoints")
	print("Loaded all 244 component variants")


func _geometry() -> void:
	var by_load := {}
	var signatures := {}
	for curve in PlantParameters.CURVES:
		for branching in PlantParameters.BRANCHING:
			for flowering in PlantParameters.FLOWERING:
				var options := {"curve": curve, "branching": branching, "flowers": flowering,
					"flower": "rose", "leaf": "serrated", "pose": "upright", "component_variant": "reference"}
				var built := PlantMeshGenerator.surface(81, options)
				_check(not built.is_empty(), "native assembly " + str(options))
				if built.is_empty():
					continue
				_check(built.stats.structural_branches == {"none": 0, "few": 3, "many": 15}[branching], "independent branches")
				_check(built.stats.flower_count == {"one": 1, "few": 5, "many": 15}[flowering], "exact flower count")
				_check(absf(built.stats.main_length - 2.25) < .00002, "no stem stretching")
				var key: String = curve + branching
				var branch_hash := hash(built.branches)
				if by_load.has(key):
					_check(by_load[key] == branch_hash, "bloom load preserves structural graph")
				by_load[key] = branch_hash
				signatures[key] = branch_hash
				for branch: Dictionary in built.branches:
					_check(branch.max_curvature <= 1. / maxf(.18, 14. * branch.radius) + .005, "broad curvature bound")
					if curve == "straight":
						_check(branch.max_curvature < .005, "straight centerline")
				for site: Dictionary in built.data.attachments:
					var at := PlantGrowth.sample(built.branches[site.branch].points, site.at)
					_check(at.point.distance_to(site.attachment) < .000001, "exact organ attachment")
					_check(site.frame.y.distance_to(site.axis) < .000001, "orientation follows attachment axis")
					if site.kind == "flower":
						_check(rad_to_deg(site.axis.angle_to(site.support_axis)) <= 6.001, "bounded flower nudge")
						_check(site.bloom >= (.55 if flowering == "one" else .35) and site.bloom <= 1., "bloom range")
	var unique := {}
	for signature in signatures.values():
		unique[signature] = true
	_check(unique.size() == 9, "distinct curve/branch matrix generated")
	# Custom lower ranges still enforce single-bloom minimum; fully-open max is allowed.
	var single := PlantMeshGenerator.surface(12, {"flower": "rose", "flower_count": 1, "bloom_min": 0., "bloom_max": .1})
	_check(single.stats.bloom_min >= .55, "single bloom floor overrides requested closed range")
	var opened := PlantMeshGenerator.surface(12, {"flower": "rose", "flower_count": 1, "bloom_min": 1., "bloom_max": 1.})
	_check(opened.stats.bloom_min == 1., "single bloom may be fully open")
	var fixed := PlantMeshGenerator.surface(12, {"flower": "anthurium", "flower_count": 3, "bud_count": 2})
	_check(fixed.stats.bloom_min == 1. and fixed.stats.bud_count == 2, "fixed flowers and additional buds")
	var a := PlantMeshGenerator.surface(81, {"flower": "rose", "branching": "many", "flowers": "many"})
	var b := PlantMeshGenerator.surface(82, {"recipe": a.recipe})
	_check(b.is_empty(), "replay rejects seed mismatch")
	var again := PlantMeshGenerator.surface(81, {"recipe": a.recipe})
	_check(a.data.vertices == again.data.vertices, "exact mesh replay")
	var options: Dictionary = a.recipe.duplicate(true)
	options.erase("recipe_version")
	options.erase("asset_revision")
	options.erase("seed")
	b = PlantMeshGenerator.surface(82, options)
	_check(a.data.vertices != b.data.vertices, "seed changes geometry")
	var scales := {}
	var stages := {}
	for site: Dictionary in a.data.attachments:
		if site.kind == "flower":
			scales[site.scale] = true
			stages[site.bloom] = true
	_check(scales.size() == 15 and stages.size() == 15, "independent head scales and bloom stages")
	# Exercise maximum graph/load and close branch spacing without expensive projection.
	var dense := PlantMeshGenerator.surface(42, {"curve": "winding", "primary_count": 7,
		"secondary_count": 3, "flower_count": 24, "bud_count": 6, "leaf_density": 1.5,
		"branch_spacing_min": .025, "branch_spacing_max": .08, "cluster_chance": 1.})
	_check(not dense.is_empty(), "control endpoints accepted")
	if dense.is_empty():
		return
	_check(dense.stats.structural_branches == 28 and dense.stats.flower_count == 24, "maximum graph/load")
	var clustered := false
	var previous := -1.
	for branch: Dictionary in dense.branches:
		if branch.level == 1:
			if previous >= 0.:
				clustered = clustered or branch.at - previous < .05
			previous = branch.at
	_check(clustered, "branches can attach close together")
	print("Validated 27 growth combinations, custom counts, maturity and deterministic geometry")


func _invalid() -> void:
	for options in [{"curve": "spiral"}, {"flower": "missing"}, {"leaf": "missing"},
		{"bloom_min": .8, "bloom_max": .3}, {"length": NAN}, {"flower_count": 2.5},
		{"primary_count": 0, "secondary_count": 2}, {"projection_size": 12}, {"controls": {"typo": 1}},
		{"recipe": {"recipe_version": 1, "asset_revision": "different"}}]:
		_check(PlantMeshGenerator.surface(81, options).is_empty(), "invalid request rejected " + str(options))
	_check(PlantMeshGenerator.generate(-1).is_empty(), "invalid seed rejected")


func _lines(design: Dictionary, size := 384) -> Dictionary:
	var px := Vector2i(size, size)
	var areas := []
	for mark: Dictionary in design.marks:
		areas.append({"at": LineRaster.to_px(mark.at, px), "family": mark.family})
	return {"width": size, "height": size,
		"mask": LineRaster.rasterize(design.polylines, design.closed, px, size / 200.),
		"motifs": {"areas": areas, "lines": LineRaster.rasterize_labels(design.polylines,
			design.closed, design.families, px, size / 200. + 2.)},
		"mandala": {"seed": design.seed, "symmetry": "none", "frame": {}, "variant": "plant_mesh"}}


func _projection(design: Dictionary, view: String) -> void:
	_check(design.polylines.size() == design.closed.size() and design.closed.size() == design.families.size(),
		"aligned design arrays")
	_check(design.closed is PackedByteArray and design.families is PackedInt32Array
		and design.family_names is PackedStringArray, "animal-compatible typed arrays")
	var normalized := true
	for path: PackedVector2Array in design.polylines:
		for point in path:
			normalized = normalized and point.is_finite() and absf(point.x) <= 1. and absf(point.y) <= 1.
	_check(normalized, "normalized finite coordinates")
	var lines := _lines(design)
	var map := RegionMap.build(lines.mask, lines.width, lines.height, 0)
	var owners := {}
	var background: int = map.labels[0]
	for mark: Dictionary in lines.motifs.areas:
		var point: Vector2 = mark.at
		var region: int = map.labels[int(point.y) * map.width + int(point.x)]
		if region < 0:
			continue
		_check(region != background, view + " organ enclosed")
		if owners.has(region):
			_check(owners[region] == mark.family, view + " distinct families do not leak")
		owners[region] = mark.family
	_check(owners.size() >= 5, view + " paintable organs")


func _pipeline(design: Dictionary) -> void:
	var lines := _lines(design)
	var opts := {"theme": "garden", "setting": "metal", "sparsity": 0., "seed": 81}
	# Test-only injection; production registration belongs to the next session.
	var collage := PictureSources.mandala_collage(81, opts, lines)
	collage.source.plant_mesh = design.recipe
	_check(not collage.slots.is_empty(), "downstream playable collage")
	var image := PictureSources.mandala_image(81, opts, lines)
	var kit := KitGenerator.generate(image, {"size": "small", "colors": 10, "seed": 81})
	_check(kit.cells.size() == kit.width * kit.height, "downstream complete kit")
	var restored: Dictionary = PatternIO.from_json(PatternIO.to_json(collage)).source.plant_mesh
	_check(PlantParameters.resolve(81, {"recipe": restored}) == design.recipe, "puzzle persists recipe")
	image.save_png(out.path_join("game_colors.png"))


func _same_design(a: Dictionary, b: Dictionary) -> bool:
	return (not b.is_empty() and a.polylines == b.polylines and a.closed == b.closed
		and a.families == b.families and a.marks == b.marks and a.recipe == b.recipe)


func _pack() -> void:
	# Raw .dat files are not ResourceLoader imports. Verify their exact paths
	# in a mounted PCK, including loading variants after the pack is mounted.
	var pack := PCKPacker.new()
	var path := out.path_join("plants.pck")
	_check(pack.pck_start(path) == OK, "start asset pack")
	var catalog: Dictionary = PlantComponentData.CATALOG.data
	for group in ["leaves", "flowers", "buds"]:
		for family in catalog[group]:
			var file: String = catalog[group][family].file
			_check(pack.add_file(file, file) == OK, "pack component " + family)
	_check(pack.flush() == OK, "finish asset pack")
	_check(ProjectSettings.load_resource_pack(path), "mount raw component pack")
	_check(not PlantComponentData.load_component("flowers", "rose", "cupped").is_empty(), "load component from mounted pack")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

extends SceneTree
## Surface attachment, species eligibility, visibility, region topology,
## background generation and playable collage/kit integration.

var failures := 0
var out := "/tmp/animal-coats"
var cases := 0
var reports := []
var pipeline_only := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		if arg == "--pipeline-only":
			pipeline_only = true
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("_run")


func _run() -> void:
	if pipeline_only:
		_occlusion()
		await _studio()
		_pipeline()
		print(
			(
				"%s: worker, studio, saved metadata, collage and kit; %d failures"
				% ["FAILED" if failures else "PASSED", failures]
			)
		)
		quit(1 if failures else 0)
		return
	_check(
		AnimalSurfaceCoat.make("ultimate_husky", "zebra", 1) == null,
		"dog rejects natural zebra coat"
	)
	_check(
		AnimalSurfaceCoat.make("gobkit_shark", "tabby", 1) == null, "fish rejects feline markings"
	)
	_check(
		AnimalSurfaceCoat.make("ultimate_husky", "stripes", 1, NAN) == null,
		"invalid scale rejected"
	)
	_occlusion()
	_decorative_regularity()
	var styles := {}
	for id: String in AnimalPoseLibrary.model_ids():
		var animal := AnimalPoseLibrary.spawn(root, id)
		var rest := animal.snapshot()
		animal.pose("idle" if "idle" in animal.available_poses() else "rest", 81, 0.8)
		var posed := animal.snapshot()
		for key in [
			"rest", "coat_coordinates", "face_coordinates", "regions", "protected", "atlas", "flow"
		]:
			_check(rest[key] == posed[key], id + " immutable skin attribute " + key)
			_check(rest[key].size() == rest.vertices.size(), id + " complete " + key)
		for p: Vector3 in posed.rest:
			_check(p.is_finite(), id + " finite rest coordinates")
		for name_value: String in AnimalSurfaceCoat.available(id):
			styles[name_value] = true
		var style := "stripes" if id.begins_with("gobkit") else AnimalSurfaceCoat.available(id)[1]
		_project(animal, style, "three_quarter_left")
		if "head_front" in AnimalCameraPresets.available(animal):
			_project(animal, "petals", "head_front")
			if id in ["ultimate_husky", "toon_cat_toon_cat_free"]:
				for view in ["head_front", "head_front_close", "head_front_high"]:
					_project(animal, style, view)
		animal.free()
	_check(styles.size() >= 18, "natural and decorative pattern repertoire")
	for row in [
		["farm_zebra", "zebra"],
		["ultimate_horse", "dapple"],
		["vol2_cat", "rosettes"],
		["ultimate_husky", "spots"],
		["ultimate_husky", "tuxedo"],
		["vol2_cat", "points"],
		["ultimate_husky", "stars"],
		["ultimate_husky", "polka_dots"],
		["ultimate_husky", "checks"],
		["ultimate_husky", "gingham"],
		["ultimate_husky", "harlequin"],
		["ultimate_husky", "chevrons"],
		["ultimate_husky", "waves"],
		["ultimate_husky", "hearts"],
		["ultimate_husky", "scales"],
		["ultimate_horse", "pinto"],
		["ultimate_horse", "socks"]
	]:
		var animal := AnimalPoseLibrary.spawn(root, row[0])
		animal.pose("rest", 12, 0.7)
		_project(animal, row[1], "three_quarter_left")
		animal.free()
	await _studio()
	_pipeline()
	FileAccess.open(out.path_join("validation.json"), FileAccess.WRITE).store_string(
		JSON.stringify(
			{
				"failures": failures,
				"models": 37,
				"projection_cases": cases,
				"styles": styles.keys(),
				"cases": reports
			},
			"\t"
		)
	)
	print(
		(
			"%s: %d surface projections, %d styles, %d failures"
			% ["FAILED" if failures else "PASSED", cases, styles.size(), failures]
		)
	)
	quit(1 if failures else 0)


func _project(animal: AnimalPoseModel, style: String, view: String) -> void:
	var data := animal.portrait_snapshot() if view.begins_with("head_") else animal.snapshot()
	var camera := AnimalCameraPresets.frame(animal, view)
	var coat := AnimalSurfaceCoat.make(animal.model_id, style, 42 + posmod(hash(style), 1000000))
	coat.fit(animal.snapshot())
	var result := AnimalSurfaceProjection.project(data, camera, coat, 256)
	_check(not result.is_empty(), animal.model_id + " projects " + style)
	if result.is_empty():
		return
	_check_flat_lighting(result, coat, animal.model_id + " " + style + " " + view)
	var design: Dictionary = result.design
	var mask := LineRaster.rasterize(design.polylines, design.closed, Vector2i(512, 512), 1.8)
	var map := RegionMap.build(mask, 512, 512, 0)
	var owners := {}
	for mark: Dictionary in design.marks:
		var p := LineRaster.to_px(mark.at, Vector2i(512, 512))
		var label: int = map.labels[int(p.y) * 512 + int(p.x)]
		if label < 0:
			continue
		_check(label != map.labels[0], animal.model_id + " coat stays inside the animal")
		if owners.has(label):
			_check(
				owners[label] == mark.family,
				animal.model_id + " coat boundaries separate paint families"
			)
		owners[label] = mark.family
	_check(not design.marks.is_empty(), animal.model_id + " paintable surface regions")
	var name_value := animal.model_id + "_" + style + "_" + view
	result.image.save_png(out.path_join(name_value + "_model.png"))
	AnimalSurfaceProjection.line_image(design).save_png(out.path_join(name_value + "_lines.png"))
	reports.append(
		{
			"model": animal.model_id,
			"style": style,
			"view": view,
			"regions": map.regions.size(),
			"marked_regions": owners.size(),
			"paths": design.polylines.size()
		}
	)
	cases += 1
	print(name_value, ": ", owners.size(), " paint regions")


func _studio() -> void:
	var studio: Variant = load("res://tools/animal_pose_studio.tscn").instantiate()
	root.add_child(studio)
	studio._coats.select(studio._coats.item_count - 1)
	studio._render_mode.select(1)
	studio._frame_camera()
	while studio._preview_task >= 0:
		await process_frame
	_check(studio._preview.texture != null, "studio displays coated mesh projection")
	studio._render_mode.select(2)
	studio._frame_camera()
	while studio._preview_task >= 0:
		await process_frame
	_check(studio._preview.texture.get_width() == 640, "studio displays extracted line art")
	studio.free()


func _pipeline() -> void:
	var opts := {
		"variant": "animal_mesh",
		"model": "ultimate_husky",
		"pose": "sit",
		"camera": "three_quarter_left",
		"coat": "spots",
		"frame": false,
		"size": 512,
		"theme": "sunset",
		"setting": "metal",
		"sparsity": 0.0
	}
	var lines := {}
	var task := WorkerThreadPool.add_task(
		func(): lines.assign(PictureSources.mandala_lines(7721, opts))
	)
	WorkerThreadPool.wait_for_task_completion(task)
	var repeat_lines := PictureSources.mandala_lines(7721, opts)
	_check(lines.mask == repeat_lines.mask, "seeded worker source is reproducible")
	var replay: Dictionary = JSON.parse_string(JSON.stringify(lines.mandala.animal_mesh))
	replay.merge({"variant": "animal_mesh", "size": 512, "frame": false})
	var replayed := PictureSources.mandala_lines(7721, replay)
	_check(
		replayed.mask == lines.mask,
		"saved metadata reproduces the exact posed coat after JSON round trip"
	)
	var changed_opts := opts.duplicate()
	changed_opts.coat_seed = 351
	var changed := PictureSources.mandala_lines(7721, changed_opts)
	_check(
		changed.mandala.animal_mesh.pose_record == lines.mandala.animal_mesh.pose_record,
		"coat seed preserves anatomy"
	)
	_check(changed.mask != lines.mask, "coat seed changes marking boundaries")
	_check(lines.mandala.animal_mesh.model == "ultimate_husky", "mesh provenance in source")
	var toys := 0
	var recent := []
	for seed_value in 400:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var picked := AnimalMeshGenerator.pick_model(rng, recent)
		toys += int(AnimalMeshGenerator.is_toy(picked))
		recent.append({"model": picked})
	_check(toys >= 20 and toys <= 65, "toy meshes are about 1 in 10 seeded animals (%d/400)" % toys)
	var collage := PictureSources.mandala_collage(7721, opts, lines)
	_check(not collage.slots.is_empty(), "patterned animal produces playable collage slots")
	_check(collage.source.animal_mesh.coat.style == "spots", "coat provenance reaches saved puzzle")
	var image := PictureSources.mandala_image(7721, opts, lines)
	image.save_png(out.path_join("husky_game_colors.png"))
	var kit := KitGenerator.generate(image, {"seed": 7721, "size": "small", "colors": 8})
	_check(kit.cells.size() == kit.width * kit.height, "patterned animal produces complete kit")
	_check(
		GemCatalog.PUZZLES.animal.variant == "animal_mesh", "main animal source uses rigged meshes"
	)
	var request := {
		"type": "kit", "picture": "animal", "seed": 7721, "pattern_seed": 0, "theme": "sunset"
	}
	var game_kit := PuzzleMaker.make(request, GemCatalog.default_unlocks())
	_check(game_kit.source.has("animal_mesh"), "main app kit retains the animal and coat recipe")
	_check(
		game_kit.source.variant == "animal_mesh", "main app kit selects the rigged animal source"
	)
	print(
		"APP PIPELINE: ",
		collage.slots.size(),
		" collage slots, ",
		kit.width,
		"x",
		kit.height,
		" kit"
	)


## Constant lighting: every painted coat pixel is exactly its paint color, with
## no normal-dependent shading or shadow that could read as an edge.
func _check_flat_lighting(result: Dictionary, coat: AnimalSurfaceCoat, name_value: String) -> void:
	if coat.style == "source":
		return
	var image: Image = result.image
	var size := image.get_width()
	var flat := true
	for at in result.labels.size():
		var label: int = result.labels[at]
		if label < 1 or label > 3:
			continue
		var expected: Color = coat.palette[label]
		var actual := image.get_pixel(at % size, at / size)
		if (
			absf(actual.r - expected.r) > 0.006
			or absf(actual.g - expected.g) > 0.006
			or absf(actual.b - expected.b) > 0.006
		):
			flat = false
			break
	_check(flat, name_value + " coat colors are unshaded")


## Decorative coats are exact repeating lattices: no noise, no seed-dependent
## shapes, and seamless wrapping around every limb.
func _decorative_regularity() -> void:
	var periods := {
		"stripes": Vector2(1, 1),
		"checks": Vector2(2, 2),
		"gingham": Vector2(1, 1),
		"harlequin": Vector2(1, 1),
		"chevrons": Vector2(1, 1),
		"waves": Vector2(1, 1),
		"polka_dots": Vector2(2, 1),
		"stars": Vector2(2, 1),
		"petals": Vector2(2, 1),
		"hearts": Vector2(2, 1),
		"scales": Vector2(1.1, 3)
	}
	_check(
		periods.size() == AnimalSurfaceCoat.DECORATIVE.size(),
		"every decorative coat has a regularity check"
	)
	var animal := AnimalPoseLibrary.spawn(root, "ultimate_husky")
	var whole := animal.snapshot()
	animal.pose("sit" if "sit" in animal.available_poses() else "rest", 3, 1.0)
	var posed := animal.snapshot()
	animal.free()
	for style: String in AnimalSurfaceCoat.DECORATIVE:
		var coat := AnimalSurfaceCoat.make("ultimate_husky", style, 5)
		var other := AnimalSurfaceCoat.make("ultimate_husky", style, 991)
		var period: Vector2 = periods[style]
		var repeating := true
		var labels := {}
		for i in 400:
			var p := (
				Vector2(fposmod(i * 0.6180339 + 0.0123, 3.3), fposmod(i * 0.4142135 + 0.0271, 3.0))
				- Vector2(1.6, 1.5)
			)
			var label := coat._motif(p)
			labels[label] = true
			if (
				label != coat._motif(p + Vector2(period.x, 0))
				or label != coat._motif(p + Vector2(0, period.y))
				or label != coat._motif(p - Vector2(period.x * 3, period.y * 2))
				or label != other._motif(p)
			):
				repeating = false
		_check(repeating, style + " is an exact, noise-free repeating motif")
		_check(labels.size() >= 2, style + " has at least two paints")
		# Around a part the lattice wraps a whole number of times.
		coat.fit(whole)
		var chart: Dictionary = coat._charts[0]
		var probe: Vector3 = chart.center + chart.first * chart.radius + chart.axis * 0.137
		var turned: Vector3 = (
			chart.center
			+ (
				(chart.first * cos(TAU - 0.000001) + chart.second * sin(TAU - 0.000001))
				* chart.radius
			)
			+ chart.axis * 0.137
		)
		_check(
			absf(fposmod(coat._cell(probe, 0).y - coat._cell(turned, 0).y + 0.5, 1) - 0.5) < 0.001,
			style + " wraps seamlessly around the torso"
		)
		# The layout only reads pose-independent coordinates.
		var posed_coat := AnimalSurfaceCoat.make("ultimate_husky", style, 5)
		posed_coat.fit(posed)
		_check(posed_coat._charts == coat._charts, style + " layout is the same in every pose")


func _occlusion() -> void:
	var data := {
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"colors": PackedColorArray(),
		"rest": PackedVector3Array(),
		"coat_coordinates": PackedVector3Array(),
		"face_coordinates": PackedVector3Array(),
		"regions": PackedInt32Array(),
		"protected": PackedByteArray(),
		"triangles": PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	}
	var coat := AnimalSurfaceCoat.make("ultimate_husky", "patches", 42)
	var samples := {}
	for index in 100:
		var p := Vector3(index * 0.17, 0.31, 0.12)
		samples[coat.label_at(p, Vector3.ZERO, Vector3.ZERO, 0, Color.WHITE, 0)] = p
	_check(samples.has(1) and samples.has(2), "occlusion fixture has two different pigments")
	for layer in 2:
		for xy in [Vector2(-0.6, -0.6), Vector2(0.6, -0.6), Vector2(0.6, 0.6), Vector2(-0.6, 0.6)]:
			data.vertices.append(Vector3(xy.x, xy.y, layer * 0.5))
			data.normals.append(Vector3.BACK)
			data.colors.append(Color.WHITE)
			data.rest.append(samples[2 if layer == 0 else 1])
			data.coat_coordinates.append(Vector3.ZERO)
			data.face_coordinates.append(Vector3.ZERO)
			data.regions.append(layer)
			data.protected.append(0)
	var result := AnimalSurfaceProjection.project(
		data,
		{
			"transform": Transform3D(Basis.IDENTITY, Vector3(0, 0, 4)),
			"size": 2.0,
			"near": 0.1,
			"far": 10.0
		},
		coat,
		128
	)
	_check(result.labels[64 * 128 + 64] == 1, "occluded pigment never reaches the image")
	_check(
		result.design.polylines.size() == 1 and result.design.closed[0] == 1,
		"coplanar triangle edges are absent"
	)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

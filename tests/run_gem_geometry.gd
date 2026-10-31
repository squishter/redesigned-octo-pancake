extends SceneTree
## Rendering must follow the generator's existing outlines and footprints.
## godot --headless -s res://tests/run_gem_geometry.gd

var failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_outlines()
	_test_emerald_clearance()
	_test_atlas()
	await _test_board()
	_test_generated_slots()
	print("Gem geometry: %s (%d failures)" % ["FAILED" if failures else "PASSED", failures])
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)


func _slot(shape: String, ratio: float) -> Dictionary:
	return {"id": 0, "region": 0, "shape": shape, "cut": "step", "size": 20.0, "width": 20.0 * ratio,
			"x": 50.0, "y": 50.0, "rotation": 0.37, "target_color": Color.RED, "target_gem": "ruby"}


func _test_outlines() -> void:
	print("Full meshes, distant outlines and facet pictures match slots at different proportions")
	for shape: String in ["kite", "emerald"]:
		for ratio: float in [0.2, 0.4, 0.625, 0.9, 1.0]:
			var slot := _slot(shape, ratio)
			for cut: String in GemCuts.ALL:
				_check_footprint(slot, GemMesh.get_mesh(shape, cut, ratio), false)
			_check_footprint(slot, GemMesh.get_outline_mesh(shape, 0.25, ratio), true)
			_check_facets(slot, GemMesh.get_facets(shape, "step", ratio))
		_check((GemMesh.get_mesh(shape, "step", 0.4) != GemMesh.get_mesh(shape, "step", 0.625)) == (shape == "kite"),
				shape + " mesh sharing does not follow its outline proportions")
		_check(GemMesh.get_mesh(shape, "step", 0.625) == GemMesh.get_mesh(shape, "step", 0.625000001),
				shape + " shares a mesh across floating-point noise")
	for shape: String in GemCuts.BY_SHAPE:
		if shape != "kite":
			_check(GemMesh.get_mesh(shape, "brilliant", 0.4) == GemMesh.get_mesh(shape, "brilliant", 1.0),
					shape + " keeps sharing its existing mesh")
	_check(GemMesh.girdle_points("kite", -1, 4, 0.4) != GemMesh.girdle_points("lozenge"),
			"a long kite must retain its offset shoulders")


func _test_emerald_clearance() -> void:
	print("Emeralds preserve their placed silhouette and clearance beside neighboring stones")
	var emerald := GemShapes.outline("emerald", 20.0, 8.0)
	_check(emerald[0].is_equal_approx(Vector2(-6.5, -4.0)), "emerald corners expand beyond the existing 3D silhouette")
	var neighbor := GemShapes.outline("round", 4.0, 4.0)
	for i in neighbor.size():
		neighbor[i] += Vector2(9.0, 5.7)
	# These stones clear the packer's capsule test. Expanding the emerald's
	# upper-right corner to (8.6, 4.0) would make it intersect the round one.
	var overlap := 0.0
	for poly in Geometry2D.intersect_polygons(emerald, neighbor):
		overlap += _area(poly)
	_check(overlap < 0.0001, "emerald corners crowd a neighbor that cleared packing")
	for ratio: float in [0.2, 0.4, 0.625, 0.9, 1.0]:
		var existing := GemShapes.outline("emerald", 2.0, 2.0)
		var outline := GemShapes.outline("emerald", 20.0, 20.0 * ratio)
		for i in outline.size():
			_check(outline[i].distance_to(existing[i] * Vector2(10.0, 10.0 * ratio)) < 0.0001,
					"emerald outline differs from the existing stretched mesh")


func _check_footprint(slot: Dictionary, mesh: ArrayMesh, flat: bool) -> void:
	var poly := GemShapes.outline(slot["shape"], slot["size"], slot["width"], 96)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var scale := Vector2(slot["size"], slot["width"]) / 2.0
	var boundary := PackedVector2Array()
	var area := 0.0
	var outside := 0
	for i in range(0, verts.size(), 3):
		var a := Vector2(verts[i].x, verts[i].z) * scale
		var b := Vector2(verts[i + 1].x, verts[i + 1].z) * scale
		var c := Vector2(verts[i + 2].x, verts[i + 2].z) * scale
		area += absf((b - a).cross(c - a)) / 2.0
		for j in range(i, i + 3):
			var p := Vector2(verts[j].x, verts[j].z) * scale
			if flat or is_zero_approx(verts[j].y):
				boundary.append(p)
			if not Geometry2D.is_point_in_polygon(p, poly) and _edge_distance(p, poly) > 0.0001:
				outside += 1
	var label := "%s %.4f %s" % [slot["shape"], float(slot["width"]) / float(slot["size"]), "flat" if flat else "full"]
	_check(outside == 0, label + " extends outside its generated slot")
	_check(absf(area - _area(poly)) < 0.001, label + " does not cover its generated slot once")
	for corner in poly:
		var nearest := INF
		for p in boundary:
			nearest = minf(nearest, corner.distance_to(p))
		_check(nearest < 0.0001, label + " loses a slot corner")
	if slot["shape"] == "kite":
		# The packer stamps a capsule, independently of the rendered mesh.
		var r: float = slot["width"] / 2.0
		var h: float = slot["size"] / 2.0 - r
		for p in boundary:
			var axis := Vector2(clampf(p.x, -h, h), 0.0)
			_check(p.distance_to(axis) <= r + 0.0001, label + " exceeds the capsule reserved by the packer")
	else:
		for p in boundary:
			_check(absf(p.x) <= scale.x + 0.0001 and absf(p.y) <= scale.y + 0.0001,
					label + " exceeds its gem-line box")


func _check_facets(slot: Dictionary, facets: Image) -> void:
	var poly := GemShapes.outline(slot["shape"], slot["size"], slot["width"], 96)
	var scale := Vector2(slot["size"], slot["width"]) / 2.0
	var wrong := 0
	for y in GemMesh.FACET_PX:
		for x in GemMesh.FACET_PX:
			var p := ((Vector2(x, y) + Vector2.ONE * 0.5) / GemMesh.FACET_PX * 2.0 - Vector2.ONE) * scale
			var covered := facets.get_pixel(x + 1, y + 1).b > 0.5
			if covered != Geometry2D.is_point_in_polygon(p, poly) and _edge_distance(p, poly) > 0.0001:
				wrong += 1
	_check(wrong == 0, "%s facet picture differs from its slot at %d texels" % [slot["shape"], wrong])


func _test_atlas() -> void:
	print("Facet atlas keeps distinct proportions and reserves enough stable tiles")
	var atlas := FacetAtlas.new()
	atlas.prepare(60)
	var first := Vector4.ZERO
	for i in 60:
		var ratio := 0.2 + i * 0.01
		var tile := atlas.tile(GemMesh.mesh_key("kite", "step", ratio))
		if i == 0:
			first = tile
		_check(tile.x >= 0.0 and tile.y >= 0.0 and tile.x + tile.z <= 1.0 and tile.y + tile.w <= 1.0,
				"facet tile exceeds the texture")
		var image: Image = atlas._image
		var at := Vector2i(roundi(tile.x * image.get_width()), roundi(tile.y * image.get_height()))
		var actual := image.get_region(Rect2i(at, Vector2i(GemMesh.FACET_PX, GemMesh.FACET_PX)))
		var expected := GemMesh.get_facets("kite", "step", ratio).get_region(
				Rect2i(1, 1, GemMesh.FACET_PX, GemMesh.FACET_PX))
		_check(actual.get_data() == expected.get_data(), "facet atlas loses its mesh profile")
	_check(atlas.tile(GemMesh.mesh_key("kite", "step", 0.2)) == first, "adding tiles moved earlier UVs")
	atlas.prepare(1)
	_check(atlas._tiles.is_empty(), "a new board retains the old puzzle's profiles")
	atlas.tile(GemMesh.mesh_key("kite", "brilliant", 0.4))
	_check(atlas._image.get_width() == FacetAtlas.TILES * (GemMesh.FACET_PX + 2), "small boards keep an oversized atlas")


func _test_board() -> void:
	print("Board batching and zoom switches retain each slot's shape without changing the puzzle")
	var board := GemBoard3D.new()
	board.size = Vector2(400.0, 400.0)
	root.add_child(board)
	var slots := [_slot("kite", 0.4), _slot("kite", 0.625), _slot("emerald", 0.4), _slot("emerald", 0.625)]
	var picture := {"width": 100, "height": 100, "slots": slots}
	var before := var_to_bytes(picture)
	var shown := PackedByteArray([0, 0, 0, 0])
	board.show_collage(picture, shown)
	_check(board._gem_layers.size() == 3, "mesh batches do not follow outline proportions")
	for i in slots.size():
		board.set_slot_shown(i, true)
		var ref: Array = board._refs[i][0]
		var mesh: Mesh = (ref[0] as MultiMesh).mesh
		_check_footprint(slots[i], mesh, false)
	board._pick_meshes(0.01)
	for i in slots.size():
		_check_footprint(slots[i], (board._refs[i][0][0] as MultiMesh).mesh, true)
	board._pick_meshes(100.0)
	for i in slots.size():
		_check_footprint(slots[i], (board._refs[i][0][0] as MultiMesh).mesh, false)
	_check(before == var_to_bytes(picture), "rendering mutated generated slot data")
	board.queue_free()
	await process_frame


func _test_generated_slots() -> void:
	print("Corrected meshes stay inside real generated slots in classic and dense collages")
	var checked := 0
	for layout: String in ["classic", "dense"]:
		var picture := PictureSources.mandala_collage(1003, {"variant": "heart", "layout": layout, "size": 384,
				"setting": "gems", "line_gems": "emerald", "frame": false,
				"shapes": {"kite": ["brilliant"], "emerald": ["step"]}})
		var shapes := {}
		for slot: Dictionary in picture["slots"]:
			if slot["shape"] not in ["kite", "emerald"]:
				continue
			shapes[slot["shape"]] = true
			var ratio := float(slot["width"]) / float(slot["size"])
			_check_footprint(slot, GemMesh.get_mesh(slot["shape"], slot["cut"], ratio), false)
			checked += 1
		_check(shapes.size() == 2, layout + " fixture lacks kite or emerald stones")
	print("  %d generated stone footprints checked" % checked)


static func _edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var distance := INF
	for i in poly.size():
		distance = minf(distance, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
	return distance


static func _area(poly: PackedVector2Array) -> float:
	var area := 0.0
	for i in poly.size():
		area += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(area) / 2.0

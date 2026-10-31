extends SceneTree
## Reopen saved puzzles through PlayScreen, then check the actual picker,
## slot overlay and placed meshes. Use an isolated XDG_DATA_HOME.
## XDG_DATA_HOME=/tmp/gem-proportion-tests godot --headless -s res://tests/run_saved_gem_proportions.gd

const PlayScreen := preload("res://scenes/game/play_screen.gd")
const CollectionScreen := preload("res://scenes/game/collection_screen.gd")
var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.theme = PlayScreen.GameTheme.build()
	var profile := SaveStore.upgrade({})
	profile["settings"]["fill_animation"] = "pop"
	var slots := []
	var gems := ["ruby", "sapphire", "leaf"]
	for shape: String in GemCuts.BY_SHAPE:
		for k in 3:
			var ratio: float = [0.2, 0.4, 1.4][k]
			for copy in 2:
				var i := slots.size()
				var length := 20.0 if copy == 0 else 10.0
				slots.append({"id": i, "region": 0, "shape": shape, "cut": GemCuts.for_shape(shape)[0],
						"size": length, "width": length * ratio, "x": 25.0 + (i % 12) * 50.0,
						"y": 25.0 + (i / 12) * 50.0, "rotation": 0.37,
						"target_color": GemCatalog.color_of(gems[k]), "target_gem": gems[k]})
	var picture := {"type": "collage", "width": 600, "height": 450, "slots": slots}
	var meta := SaveStore.add_puzzle(profile, picture)
	var id: String = meta["id"]
	var placed := PackedByteArray()
	placed.resize(slots.size())
	for i in slots.size():
		placed[i] = 1 if i % 2 == 0 else 0
	SaveStore.save_progress(id, placed)
	var kept := var_to_bytes(SaveStore.load_picture(id))
	var play := await _open(profile, id)
	_check(play._filled == slots.size() / 2, "reopening loses saved placement progress")
	_check(play._overlay.placed == placed, "reopening changes which slots are placed")
	_check_view(play)
	play._fill(1)
	play._save(false)
	placed[1] = 1
	_check(SaveStore.load_progress(id, slots.size()) == placed, "placing a stone changes other saved progress")
	play.queue_free()
	await process_frame
	play = await _open(profile, id)
	_check(play._overlay.placed == placed, "new placement is lost on reopening")
	_check(var_to_bytes(SaveStore.load_picture(id)) == kept, "display changes rewrite the saved puzzle")
	_check_view(play)
	play.queue_free()
	await process_frame
	SaveStore.delete_puzzle(profile, id)
	print("Saved gem proportions: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _open(profile: Dictionary, id: String) -> Control:
	var play := PlayScreen.new()
	play.profile = profile
	play.puzzle_id = id
	root.add_child(play)
	for i in 3:
		await process_frame
	return play


func _check_view(play: Control) -> void:
	for i in play._picture["slots"].size():
		var slot: Dictionary = play._picture["slots"][i]
		var ratio := float(slot["width"]) / float(slot["size"])
		var type_id: int = play._type_of[i]
		var icon_ref: Array = play._icons._refs[type_id][0]
		var icon_transform: Transform3D = icon_ref[2]
		_check(absf(icon_transform.basis.z.length() / icon_transform.basis.x.length() - ratio) < 0.00001,
				"%s %.2f: picker proportions differ from saved stone" % [slot["shape"], ratio])
		var ref: Array = play._board._refs[i][0]
		var mesh: Mesh = (ref[0] as MultiMesh).mesh
		var transform: Transform3D = ref[2]
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var footprint := PackedVector2Array()
		var area := 0.0
		for j in range(0, vertices.size(), 3):
			var a: Vector3 = transform * vertices[j]
			var b: Vector3 = transform * vertices[j + 1]
			var c: Vector3 = transform * vertices[j + 2]
			var pa := Vector2(a.x, a.z)
			var pb := Vector2(b.x, b.z)
			var pc := Vector2(c.x, c.z)
			footprint.append_array([pa, pb, pc])
			area += absf((pb - pa).cross(pc - pa)) / 2.0
		var poly: PackedVector2Array = play._overlay._polys[i]
		_check(absf(_area(poly) / area - 1.0) < 0.06,
				"%s %.2f: empty slot area differs from placed mesh" % [slot["shape"], ratio])
		var bounds := _bounds(footprint)
		var outline := _bounds(poly)
		var tolerance := maxf(slot["size"], slot["width"]) * 0.05
		_check(bounds.position.distance_to(outline.position) < tolerance and bounds.end.distance_to(outline.end) < tolerance,
				"%s %.2f: empty slot bounds differ from placed mesh" % [slot["shape"], ratio])
		var icon := GemIcons.stone(slot["shape"], slot["cut"], slot["target_color"], slot["target_gem"],
				ratio, 100.0, Vector2(50.0, 50.0))
		for point in GemShapes.slot_polygon(icon, 96):
			_check(Rect2(0.0, 0.0, 100.0, 100.0).has_point(point), "picker stone bleeds into its neighbor")
	for shape: String in GemCuts.BY_SHAPE:
		var stone := CollectionScreen._stone(shape, GemCuts.for_shape(shape)[0], Color.RED, "ruby")
		var expected := 0.5 if shape in GemVariety.LONG_FAMILY or shape in GemVariety.BOX_FAMILY else 1.0
		_check(is_equal_approx(float(stone["width"]) / stone["size"], expected), "Collection loses native proportions")


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: ", message)


static func _bounds(points: PackedVector2Array) -> Rect2:
	var rect := Rect2(points[0], Vector2.ZERO)
	for p in points:
		rect = rect.expand(p)
	return rect


static func _area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in points.size():
		area += (points[i] - points[0]).cross(points[(i + 1) % points.size()] - points[0])
	return absf(area) / 2.0

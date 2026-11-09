extends Control
## Run this scene to inspect frozen poses and their seeded variations.

var _world: Node3D
var _camera: Camera3D
var _portrait: MeshInstance3D
var _floor: MeshInstance3D
var _coats: OptionButton
var _render_mode: OptionButton
var _coat_seed: SpinBox
var _preview: TextureRect
var _preview_task := -1
var _preview_serial := 0
var _pending_preview := {}
var _preview_result := {}
var _animal: AnimalPoseModel
## The whole animal's pose-independent coat coordinates, so head crops lay
## out decorative motifs exactly as the generator does.
var _coat_layout := {}
var _models: OptionButton
var _poses: OptionButton
var _views: OptionButton
var _phase: HSlider
var _seed: SpinBox
var _amount: HSlider
var _orbit: HSlider
var _status: Label
var _sliders := {}
var _overrides := {}


func _ready() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var title := Label.new()
	title.text = "Animal pose studio"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	_models = OptionButton.new()
	_models.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_models)
	var ids := Array(AnimalPoseLibrary.model_ids())
	ids.sort_custom(
		func(a: String, b: String):
			return (
				AnimalPoseLibrary.model_info(a).display_name
				< AnimalPoseLibrary.model_info(b).display_name
			)
	)
	for id: String in ids:
		_models.add_item(AnimalPoseLibrary.model_info(id).display_name)
		_models.set_item_metadata(_models.item_count - 1, id)
	_poses = OptionButton.new()
	toolbar.add_child(_poses)
	_seed = SpinBox.new()
	_seed.min_value = 0
	_seed.max_value = 2147483647
	_seed.value = 12
	_seed.prefix = "Seed "
	toolbar.add_child(_seed)
	var next := Button.new()
	next.text = "New variation"
	next.pressed.connect(func(): _seed.value += 1)
	toolbar.add_child(next)
	var view_row := HBoxContainer.new()
	column.add_child(view_row)
	var view_label := Label.new()
	view_label.text = "Camera / crop"
	view_row.add_child(view_label)
	_views = OptionButton.new()
	_views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_views.item_selected.connect(
		func(_index):
			_orbit.editable = _views.get_selected_metadata() == "manual"
			_frame_camera()
	)
	view_row.add_child(_views)
	var coat_row := HBoxContainer.new()
	column.add_child(coat_row)
	_coats = OptionButton.new()
	_coats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_coats.item_selected.connect(func(_index): _frame_camera())
	coat_row.add_child(_coats)
	_coat_seed = SpinBox.new()
	_coat_seed.max_value = 2147483647
	_coat_seed.value = 42
	_coat_seed.prefix = "Coat seed "
	_coat_seed.value_changed.connect(func(_value): _frame_camera())
	coat_row.add_child(_coat_seed)
	_render_mode = OptionButton.new()
	for label in ["Original model", "Coated model", "Line art"]:
		_render_mode.add_item(label)
	_render_mode.item_selected.connect(func(_index): _frame_camera())
	coat_row.add_child(_render_mode)
	var viewport_container := SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.custom_minimum_size = Vector2(0, 260)
	column.add_child(viewport_container)
	viewport_container.resized.connect(func(): _frame_camera.call_deferred())
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.own_world_3d = true
	viewport_container.add_child(viewport)
	_preview = TextureRect.new()
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.hide()
	viewport_container.add_child(_preview)
	_world = Node3D.new()
	viewport.add_child(_world)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_world.add_child(_camera)
	_portrait = MeshInstance3D.new()
	_portrait.hide()
	var portrait_material := StandardMaterial3D.new()
	portrait_material.vertex_color_use_as_albedo = true
	portrait_material.roughness = 0.9
	portrait_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_portrait.material_override = portrait_material
	_world.add_child(_portrait)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.3
	_world.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.87, 0.91, 0.94)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	_world.add_child(environment)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(20, 20)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.83, 0.87, 0.9)
	material.roughness = 1
	floor_mesh.material_override = material
	_world.add_child(floor_mesh)
	_floor = floor_mesh
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(controls)
	column = controls
	_amount = _slider(column, "Variation strength", 0, 1, 0.75)
	_amount.value_changed.connect(func(_value): _apply())
	_phase = _slider(column, "Pose phase", 0, 1, 0.25)
	_phase.value_changed.connect(
		func(value):
			_overrides.phase = value
			_apply()
	)
	_orbit = _slider(column, "View angle", -180, 180, 25)
	_orbit.value_changed.connect(func(_value): _frame_camera())
	for entry in [
		["Head turn", "look_yaw"],
		["Head lift", "look_pitch"],
		["Tail sweep", "tail_sweep"],
		["Body lean", "body_roll"],
		["Stance width", "stance_width"],
		["Foot stagger", "stance_stagger"],
		["Trunk curl", "trunk_curl"]
	]:
		var key: String = entry[1]
		var slider := _slider(column, entry[0], -1, 1, 0)
		_sliders[key] = slider
		slider.value_changed.connect(
			func(value):
				_overrides[key] = value
				_apply()
		)
	var reset := Button.new()
	reset.text = "Reset controls to seed"
	reset.pressed.connect(
		func():
			_overrides.clear()
			_apply()
	)
	column.add_child(reset)
	_status = Label.new()
	column.add_child(_status)
	_models.item_selected.connect(func(_index): _load_model())
	_poses.item_selected.connect(func(_index): _apply())
	_seed.value_changed.connect(func(_value): _apply())
	for i in _models.item_count:
		if _models.get_item_metadata(i) == "ultimate_fox":
			_models.select(i)
	_load_model()


func _load_model() -> void:
	if _animal != null:
		_animal.free()
	_animal = AnimalPoseLibrary.spawn(_world, _models.get_selected_metadata())
	_poses.clear()
	_overrides.clear()
	if _animal == null:
		_status.text = "Could not load this animal."
		return
	var whole := _animal.snapshot()
	_coat_layout = {"rest": whole.rest, "regions": whole.regions}
	var labels := {
		"rest": "Stand",
		"idle": "Idle",
		"walk": "Walking",
		"graze": "Grazing",
		"sit": "Sitting",
		"source": "Authored animation"
	}
	labels.merge(
		{
			"head_low": "Head low",
			"eat": "Eating",
			"alert": "Alert",
			"run": "Running",
			"gallop": "Galloping",
			"trot": "Trotting",
			"jump": "Jumping",
			"landing": "Landing",
			"kick": "Hind-leg kick",
			"headbutt": "Headbutt",
			"lie_down": "Lying down",
			"play_bow": "Play bow",
			"stretch": "Stretching",
			"look_back": "Looking back",
			"crouch": "Crouching",
			"swim": "Swimming",
			"fly": "Flying",
			"drift": "Drifting"
		},
		true
	)
	for preset: String in _animal.available_poses():
		_poses.add_item(labels.get(preset, preset))
		_poses.set_item_metadata(_poses.item_count - 1, preset)
		if preset == "idle":
			_poses.select(_poses.item_count - 1)
	var supported := _animal.supported_controls()
	_coats.clear()
	for style: String in AnimalSurfaceCoat.available(_animal.model_id):
		_coats.add_item(style.capitalize())
		_coats.set_item_metadata(_coats.item_count - 1, style)
	for key: String in _sliders:
		_sliders[key].editable = key in supported
	_apply()


func _apply() -> void:
	if _animal == null:
		return
	var preset: String = _poses.get_selected_metadata()
	var info := _animal.pose_info(preset)
	_phase.editable = info.end > info.start or info.get("custom", "") == "trot"
	var supported := _animal.supported_controls()
	for key: String in _sliders:
		var stance_control := key in ["body_roll", "stance_width", "stance_stagger"]
		_sliders[key].editable = key in supported and not (preset == "sit" and stance_control)
	var result := _animal.pose(preset, int(_seed.value), _amount.value, _overrides)
	if result.is_empty():
		_status.text = "This pose could not be applied."
		return
	for key: String in _sliders:
		_sliders[key].set_value_no_signal(
			result.controls[key] / maxf(0.0001, result.amount) if _sliders[key].editable else 0
		)
	_status.text = "Frozen pose · variation %d" % int(_seed.value)
	_phase.set_value_no_signal(result.phase)
	_status.text += " · " + ("custom pose" if result.origin == "procedural" else "authored pose")
	if result.body_factor > 0 and result.body_factor < 1:
		_status.text += " · stance softened to preserve foot contact"
	_sync_views()
	_frame_camera()


func _sync_views() -> void:
	var previous: String = (
		_views.get_selected_metadata() if _views.item_count > 0 else "three_quarter_left"
	)
	_views.clear()
	var labels := {
		"side_left": "Side · left",
		"side_right": "Side · right",
		"three_quarter_left": "Three-quarter · left",
		"three_quarter_right": "Three-quarter · right",
		"front": "Front · full animal",
		"head_front": "Front · head portrait",
		"head_front_close": "Front · tight head crop",
		"head_front_high": "Front · head from above"
	}
	for view: String in AnimalCameraPresets.available(_animal):
		_views.add_item(labels[view])
		_views.set_item_metadata(_views.item_count - 1, view)
	_views.add_item("Manual orbit")
	_views.set_item_metadata(_views.item_count - 1, "manual")
	_views.select(0)
	for i in _views.item_count:
		if _views.get_item_metadata(i) == previous:
			_views.select(i)
	_orbit.editable = _views.get_selected_metadata() == "manual"


func _frame_camera() -> void:
	if _animal == null:
		return
	var head: bool = (
		_views.item_count > 0 and str(_views.get_selected_metadata()).begins_with("head_")
	)
	_animal.visible = not head
	_floor.visible = not head
	_portrait.visible = head
	if head:
		var data := _animal.portrait_snapshot()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data.vertices
		arrays[Mesh.ARRAY_NORMAL] = data.normals
		arrays[Mesh.ARRAY_COLOR] = data.colors
		arrays[Mesh.ARRAY_INDEX] = data.triangles
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_portrait.mesh = mesh
		_portrait.transform = _animal.transform
	var viewport_size: Vector2 = _camera.get_viewport().get_visible_rect().size
	var aspect := maxf(0.1, float(viewport_size.x) / maxf(1, viewport_size.y))
	if _views.item_count > 0 and _views.get_selected_metadata() != "manual":
		AnimalCameraPresets.apply(_camera, _animal, _views.get_selected_metadata(), aspect)
		_queue_projection()
		return
	_camera.near = 0.01
	_camera.far = 100.0
	var points: PackedVector3Array = _animal.snapshot(false).vertices
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	var direction := _animal.forward_direction().rotated(Vector3.UP, deg_to_rad(_orbit.value))
	var center := bounds.get_center()
	_camera.position = center + direction * 4 + Vector3.UP * 1.1
	_camera.look_at(center)
	_camera.size = (
		maxf(bounds.size.y, Vector2(bounds.size.x, bounds.size.z).length() / aspect) * 1.35
	)
	_queue_projection()


func _queue_projection() -> void:
	_preview_serial += 1
	_preview.visible = _render_mode.selected != 0
	if not _preview.visible:
		_pending_preview = {}
		return
	var view: String = _views.get_selected_metadata()
	var data := _animal.portrait_snapshot() if view.begins_with("head_") else _animal.snapshot()
	var camera := AnimalCameraPresets.frame(_animal, view)
	if view == "manual":
		camera = {
			"transform": _animal.global_transform.affine_inverse() * _camera.global_transform,
			"size": _camera.size * maxf(1, _camera.get_viewport().get_visible_rect().size.aspect()),
			"near": 0.01,
			"far": 100.0
		}
	var coat := AnimalSurfaceCoat.make(
		_animal.model_id, _coats.get_selected_metadata(), int(_coat_seed.value)
	)
	if coat != null:
		coat.fit(_coat_layout)
	_pending_preview = {
		"serial": _preview_serial,
		"data": data,
		"camera": camera,
		"coat": coat,
		"lines": _render_mode.selected == 2
	}
	_start_preview()


func _start_preview() -> void:
	if _preview_task >= 0 or _pending_preview.is_empty():
		return
	var job := _pending_preview
	_pending_preview = {}
	_preview_task = WorkerThreadPool.add_task(
		_render_preview.bind(job), false, "animal coat projection"
	)


func _render_preview(job: Dictionary) -> void:
	var projection := AnimalSurfaceProjection.project(job.data, job.camera, job.coat, 384)
	var image: Image = (
		AnimalSurfaceProjection.line_image(projection.design) if job.lines else projection.image
	)
	_preview_result = {"serial": job.serial, "image": image}


func _process(_delta: float) -> void:
	if _preview_task < 0 or not WorkerThreadPool.is_task_completed(_preview_task):
		return
	WorkerThreadPool.wait_for_task_completion(_preview_task)
	_preview_task = -1
	if _preview_result.serial == _preview_serial:
		_preview.texture = ImageTexture.create_from_image(_preview_result.image)
	_start_preview()


func _exit_tree() -> void:
	if _preview_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_preview_task)


func _slider(parent: Node, caption: String, low: float, high: float, value: float) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 180
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.01
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	return slider

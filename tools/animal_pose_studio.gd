extends Control
## Run this scene to inspect frozen poses and their seeded variations.

var _world: Node3D
var _camera: Camera3D
var _animal: AnimalPoseModel
var _models: OptionButton
var _poses: OptionButton
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
	_world = Node3D.new()
	viewport.add_child(_world)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_world.add_child(_camera)
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
	_amount = _slider(column, "Variation strength", 0, 1, 0.75)
	_amount.value_changed.connect(func(_value): _apply())
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
	var labels := {
		"rest": "Stand",
		"idle": "Idle",
		"walk": "Walking",
		"graze": "Grazing",
		"sit": "Sitting",
		"source": "Authored animation"
	}
	for preset: String in _animal.available_poses():
		_poses.add_item(labels.get(preset, preset))
		_poses.set_item_metadata(_poses.item_count - 1, preset)
		if preset == "idle":
			_poses.select(_poses.item_count - 1)
	var supported := _animal.supported_controls()
	for key: String in _sliders:
		_sliders[key].editable = key in supported
	_apply()


func _apply() -> void:
	if _animal == null:
		return
	var preset: String = _poses.get_selected_metadata()
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
	if result.body_factor > 0 and result.body_factor < 1:
		_status.text += " · stance softened to preserve foot contact"
	_frame_camera()


func _frame_camera() -> void:
	if _animal == null:
		return
	var points: PackedVector3Array = _animal.snapshot(false).vertices
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	var direction := _animal.forward_direction().rotated(Vector3.UP, deg_to_rad(_orbit.value))
	var center := bounds.get_center()
	_camera.position = center + direction * 4 + Vector3.UP * 1.1
	_camera.look_at(center)
	var viewport_size: Vector2 = _camera.get_viewport().get_visible_rect().size
	var aspect := maxf(0.1, float(viewport_size.x) / viewport_size.y)
	_camera.size = (
		maxf(bounds.size.y, Vector2(bounds.size.x, bounds.size.z).length() / aspect) * 1.35
	)


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

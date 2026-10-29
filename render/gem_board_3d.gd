class_name GemBoard3D
extends SubViewportContainer
## The board in 3D: a gem collage (or a kit's drills) on white paper, under
## a fixed camera looking straight down. Every stone is a faceted gem
## (GemMesh, gem.gdshader) that glints as the light drifts over time and as
## the phone turns: the light hangs still in the room, so tilting, turning
## or rolling the phone (seen by its gravity sensor and compass, in any
## pose, upright too) moves it across the stones; the camera never moves.
## Each stone casts a soft shadow on the paper (`shadows` turns it off) with
## colored caustic light in it (gem_shadow.gdshader), and the brightest
## glints flare into star sparkles (gem_sparkle.gdshader). Caustics follow
## the light's direction only, so they hold still when it does.
##
## Stones of one shape and cut share a mesh and draw as one MultiMesh, so
## thousands stay cheap. Pinch to zoom, drag to pan, double-tap to fit (mouse
## wheel on desktop), like PreviewCanvas.

const GEM_SHADER := preload("res://render/gem.gdshader")
const SHADOW_SHADER := preload("res://render/gem_shadow.gdshader")
const SPARKLE_SHADER := preload("res://render/gem_sparkle.gdshader")
const PAPER_SHADER := preload("res://render/paper.gdshader")
const BACKGROUND := Color("#2a1f3d")
const MAX_ZOOM := 12.0
const DOUBLE_TAP_MS := 300
const DOUBLE_TAP_SLOP := 60.0
## Room around the picture when fitted, as a share of its size.
const MARGIN := 0.03
## A stone's girdle stands this high above the paper, and its crown rises
## about this much above that, in its half-widths.
const GIRDLE_HEIGHT := 0.45
const CROWN_HEIGHT := 0.3
## Shadow and sparkle planes, in stone half-sizes (shadows must cover the
## farthest the light can push them).
const SHADOW_SPAN := 2.2
const SPARKLE_SPAN := 1.7
## Kit drills: board units per cell, and the drill's share of it.
const KIT_CELL := 10.0
const KIT_DRILL := 0.9
## The key light: where it hangs when the picture appears (azimuth in the
## board's xz plane, toward the picture's top left; elevation above the
## paper) and how far it drifts. Radians.
const KEY_AZIMUTH := -2.3
const KEY_ELEVATION := 0.62
const DRIFT := 0.45
## However the phone turns, the lights stay at least this high above the
## paper (radians).
const MIN_ELEVATION := 0.2
## How quickly sensor readings settle (per second): higher follows the
## phone faster, lower smooths out compass jitter.
const SENSOR_SMOOTH := 6.0

## The light drifts with time (tests freeze it and set the time instead).
var animate := true
## Seconds of drift; the light's position over time.
var light_time := 0.0
## How the phone has turned since the picture appeared, as the rotation
## that carries a direction fixed in the room through the phone's own axes
## (x right, y up the screen, z out of it). Tests set it.
var turn := Basis.IDENTITY
var use_sensor := true
## Darken the paper under each stone (its caustic light shows either way).
var shadows := true:
	set(value):
		shadows = value
		_shadow_material.set_shader_parameter("shadow_strength", 1.0 if value else 0.0)

var _viewport := SubViewport.new()
var _camera := Camera3D.new()
var _paper := MeshInstance3D.new()
var _layers := Node3D.new()
var _gem_material := ShaderMaterial.new()
var _shadow_material := ShaderMaterial.new()
var _sparkle_material := ShaderMaterial.new()
var _paper_material := ShaderMaterial.new()
## Picture size in board units (picture pixels, or kit cells x KIT_CELL).
var _board := Vector2(1.0, 1.0)
var _zoom := 1.0
## The board point at the middle of the view.
var _center := Vector2(0.5, 0.5)
## Smoothed sensor readings, in the phone's axes, and the phone's frame
## (room east, north and up, in its axes) when the picture appeared.
var _gravity := Vector3.ZERO
var _magnet := Vector3.ZERO
var _start_up := Vector3.ZERO
var _start_frame := Basis.IDENTITY
var _touches := {}
var _last_tap_ms := -DOUBLE_TAP_MS
var _last_tap_pos := Vector2.ZERO


func _init() -> void:
	stretch = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.handle_input_locally = false
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.1
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_camera.near = 0.1
	_camera.far = 4000.0
	_viewport.add_child(_camera)
	_gem_material.shader = GEM_SHADER
	_shadow_material.shader = SHADOW_SHADER
	_shadow_material.render_priority = -1
	_sparkle_material.shader = SPARKLE_SHADER
	_sparkle_material.render_priority = 1
	_paper_material.shader = PAPER_SHADER
	_paper.material_override = _paper_material
	_viewport.add_child(_paper)
	_viewport.add_child(_layers)
	resized.connect(_apply_view)
	visibility_changed.connect(func() -> void:
		_viewport.render_target_update_mode = (SubViewport.UPDATE_WHEN_VISIBLE if is_visible_in_tree()
				else SubViewport.UPDATE_DISABLED))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if animate:
		light_time += delta
	if use_sensor:
		_read_sensors(delta)
	update_light()


## Follows the phone's orientation: gravity gives its tilt in every pose,
## the compass its heading (so turning it while upright counts too).
func _read_sensors(delta: float) -> void:
	var g := Input.get_gravity()
	if g.length() < 1.0:
		return  # no sensor (desktop, tests)
	var m := Input.get_magnetometer()
	var k := 1.0 - exp(-delta * SENSOR_SMOOTH)
	_gravity = g if _gravity == Vector3.ZERO else _gravity.lerp(g, k)
	if m.length() > 1.0:
		_magnet = m if _magnet == Vector3.ZERO else _magnet.lerp(m, k)
	var up := -_gravity.normalized()
	# The pose to measure from: the first reading, or the first with a
	# compass if that only came later.
	if _start_up == Vector3.ZERO or (_start_frame == Basis.IDENTITY and _magnet != Vector3.ZERO):
		_start_up = up
		_start_frame = room_frame(_gravity, _magnet)
	if _magnet == Vector3.ZERO or _start_frame == Basis.IDENTITY:
		# No compass: tilt only, the shortest turn from how the phone stood.
		turn = Basis(Quaternion(_start_up, up))
	else:
		turn = room_frame(_gravity, _magnet) * _start_frame.transposed()


## The room's east, north and up in the phone's axes (as a basis's columns),
## from gravity and the magnetic field read in those axes; IDENTITY without
## a usable field. Only how it changes matters, so the sensors' sign
## conventions don't.
static func room_frame(gravity: Vector3, magnet: Vector3) -> Basis:
	var up := -gravity.normalized()
	var east := magnet.cross(up)
	if east.length() < 1e-3:
		return Basis.IDENTITY
	east = east.normalized()
	return Basis(east, up.cross(east), up)


## Sets every shader's light for the current time and the phone's turn.
func update_light() -> void:
	var t := light_time
	var az := KEY_AZIMUTH + DRIFT * sin(t * 0.23) + 0.15 * sin(t * 0.61 + 1.3)
	var el := KEY_ELEVATION + 0.1 * sin(t * 0.17 + 0.4)
	var key := _turned(Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)))
	var faz := az + 2.6 + 0.3 * sin(t * 0.31 + 2.0)
	var fel := 0.45 + 0.08 * sin(t * 0.27)
	var fill := _turned(Vector3(cos(faz) * cos(fel), sin(fel), sin(faz) * cos(fel)))
	for m: ShaderMaterial in [_gem_material, _shadow_material, _sparkle_material, _paper_material]:
		m.set_shader_parameter("key_dir", key)
		m.set_shader_parameter("fill_dir", fill)


## A light direction (board space) after the phone's turn: into the phone's
## axes (board x right, y toward the viewer, z down the picture are its x,
## z and -y), turned, and back, kept above the paper.
func _turned(board_dir: Vector3) -> Vector3:
	var d := turn * Vector3(board_dir.x, -board_dir.z, board_dir.y)
	var b := Vector3(d.x, d.z, -d.y)
	var low := sin(MIN_ELEVATION)
	if b.y < low:
		var flat := Vector2(b.x, b.z).normalized() * cos(MIN_ELEVATION)
		b = Vector3(flat.x, low, flat.y)
	return b.normalized()


func show_collage(picture: Dictionary) -> void:
	var w: float = picture["width"]
	var h: float = picture["height"]
	var lines: PackedByteArray = picture.get("lines_visible", PackedByteArray())
	_build(picture["slots"], Vector2(w, h), lines, Vector2i(int(w), int(h)))


## A kit pattern's drills, round or square, one per cell.
func show_kit(pattern: Dictionary) -> void:
	var w: int = pattern["width"]
	var h: int = pattern["height"]
	var cells: PackedByteArray = pattern["cells"]
	var palette: Array = pattern["palette"]
	var shape := "round" if pattern["drill"] == "round" else "square"
	var d := KIT_CELL * KIT_DRILL
	var slots := []
	for y in h:
		for x in w:
			slots.append({"x": (x + 0.5) * KIT_CELL, "y": (y + 0.5) * KIT_CELL, "size": d, "width": d, "rotation": 0.0,
					"shape": shape, "cut": "brilliant", "target_color": palette[cells[y * w + x]]["color"]})
	_build(slots, Vector2(w, h) * KIT_CELL, PackedByteArray(), Vector2i.ZERO)


## Back to the whole picture.
func reset_view() -> void:
	_zoom = 1.0
	_center = _board / 2.0
	_apply_view()


func _build(slots: Array, board: Vector2, lines: PackedByteArray, lines_size: Vector2i) -> void:
	for child in _layers.get_children():
		child.queue_free()
	# The light starts where it should, however the phone is held now.
	_start_up = Vector3.ZERO
	turn = Basis.IDENTITY
	_board = board
	var plane := PlaneMesh.new()
	plane.size = board
	_paper.mesh = plane
	_paper.position = Vector3(board.x / 2.0, 0.0, board.y / 2.0)
	_paper_material.set_shader_parameter("board_px", board)
	_paper_material.set_shader_parameter("lines_tex", _mask_texture(lines, lines_size))

	var by_mesh := {}
	for i in slots.size():
		var s: Dictionary = slots[i]
		var cut: String = s.get("cut", "")
		if not cut in GemCuts.for_shape(s["shape"]):
			cut = GemCuts.for_shape(s["shape"])[0]
		by_mesh.get_or_add(s["shape"] + "|" + cut, []).append(i)
	for key: String in by_mesh:
		var parts := key.split("|")
		_add_layer(GemMesh.get_mesh(parts[0], parts[1]), _gem_material, slots, by_mesh[key], "gem",
				GemCuts.ALL.find(parts[1]))
	var all := range(slots.size())
	var shadow_plane := PlaneMesh.new()
	shadow_plane.size = Vector2(2.0, 2.0) * SHADOW_SPAN
	_add_layer(shadow_plane, _shadow_material, slots, all, "shadow")
	var sparkle_plane := PlaneMesh.new()
	sparkle_plane.size = Vector2(2.0, 2.0)
	_add_layer(sparkle_plane, _sparkle_material, slots, all, "sparkle")
	update_light()
	reset_view()


## One MultiMesh: `mesh` for the given slots, as gems, shadows or sparkles.
## For gems, `cut` is the cut's index in GemCuts.ALL.
func _add_layer(mesh: Mesh, material: ShaderMaterial, slots: Array, which: Array, kind: String, cut := 0) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = which.size()
	for k in which.size():
		var i: int = which[k]
		var s: Dictionary = slots[i]
		var half_len: float = s["size"] / 2.0
		var half_wid: float = s["width"] / 2.0
		var small := minf(half_len, half_wid)
		var turn := Basis(Vector3.UP, -float(s["rotation"]))
		var at := Vector3(s["x"], 0.0, s["y"])
		var color: Color = s["target_color"]
		var random := fposmod(sin(i * 12.9898 + 78.233) * 43758.5453, 1.0)
		match kind:
			"gem":
				at.y = GIRDLE_HEIGHT * small
				mm.set_instance_transform(k, Transform3D(turn * Basis.from_scale(Vector3(half_len, small, half_wid)), at))
				var optics := _optics(color)
				mm.set_instance_custom_data(k, Color(random, optics.x, optics.y, cut))
			"shadow":
				at.y = 0.02
				mm.set_instance_transform(k, Transform3D(turn * Basis.from_scale(Vector3(half_len, 1.0, half_wid)), at))
				mm.set_instance_custom_data(k, Color(random, (GIRDLE_HEIGHT + CROWN_HEIGHT) * small, 0.0, 0.0))
			_:
				at.y = (GIRDLE_HEIGHT + CROWN_HEIGHT) * small + 0.1
				var reach := maxf(half_len, half_wid) * SPARKLE_SPAN
				mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(reach, 1.0, reach)), at))
				mm.set_instance_custom_data(k, Color(random, 0.0, 0.0, 0.0))
		mm.set_instance_color(k, color)
	var layer := MultiMeshInstance3D.new()
	layer.multimesh = mm
	layer.material_override = material
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_layers.add_child(layer)


## Refractive index and dispersion for a gem color: pale, unsaturated
## stones read as diamonds (bright, with fire), the rest as colored gems.
static func _optics(color: Color) -> Vector2:
	if color.s < 0.18 and color.v > 0.7:
		return Vector2(2.42, 0.035)
	return Vector2(1.72, 0.012)


static func _mask_texture(mask: PackedByteArray, size: Vector2i) -> ImageTexture:
	if mask.is_empty() or size.x <= 0:
		var empty := Image.create(1, 1, false, Image.FORMAT_L8)
		return ImageTexture.create_from_image(empty)
	var data := PackedByteArray()
	data.resize(mask.size())
	for i in mask.size():
		data[i] = 255 if mask[i] != 0 else 0
	return ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, data))


## Points the camera at _center with the zoom, keeping the board covering
## the view (or centered when it's smaller).
func _apply_view() -> void:
	var view := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	var fit := minf(view.x / (_board.x * (1.0 + MARGIN * 2.0)), view.y / (_board.y * (1.0 + MARGIN * 2.0)))
	var scale_px := fit * _zoom  # screen px per board unit
	var seen := view / scale_px
	for axis in 2:
		if seen[axis] >= _board[axis]:
			_center[axis] = _board[axis] / 2.0
		else:
			_center[axis] = clampf(_center[axis], seen[axis] / 2.0, _board[axis] - seen[axis] / 2.0)
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.size = seen.y
	_camera.position = Vector3(_center.x, maxf(_board.x, _board.y), _center.y)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var p := _local(event.position)
		if event.pressed:
			if not Rect2(Vector2.ZERO, size).has_point(p):
				return
			_touches[event.index] = p
			if _touches.size() == 1:
				var now := Time.get_ticks_msec()
				if now - _last_tap_ms < DOUBLE_TAP_MS and p.distance_to(_last_tap_pos) < DOUBLE_TAP_SLOP:
					reset_view()
					now = -DOUBLE_TAP_MS
				_last_tap_ms = now
				_last_tap_pos = p
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var p := _local(event.position)
		var prev: Vector2 = _touches[event.index]
		if _touches.size() == 1:
			_pan(p - prev)
		else:
			# Pinch with the first other finger: follow the midpoint, scale by the spread.
			var other: Vector2 = _touches[_touches.keys().filter(func(k: int) -> bool: return k != event.index)[0]]
			_pan((p + other) / 2.0 - (prev + other) / 2.0)
			var old_spread := prev.distance_to(other)
			if old_spread > 1.0:
				_zoom_at((p + other) / 2.0, p.distance_to(other) / old_spread)
		_touches[event.index] = p
	elif event is InputEventMouseButton and event.pressed:
		var p := _local(event.position)
		if not Rect2(Vector2.ZERO, size).has_point(p):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(p, 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(p, 1.0 / 1.15)
	elif event is InputEventMagnifyGesture and _touches.is_empty():
		var p := _local(event.position)
		if Rect2(Vector2.ZERO, size).has_point(p):
			_zoom_at(p, event.factor)


func _local(viewport_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_pos


## Screen px per board unit.
func _scale_px() -> float:
	var view := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	return minf(view.x / (_board.x * (1.0 + MARGIN * 2.0)), view.y / (_board.y * (1.0 + MARGIN * 2.0))) * _zoom


func _pan(screen_delta: Vector2) -> void:
	_center -= screen_delta / _scale_px()
	_apply_view()


## Zooms by `factor` keeping the board point under screen point `p` still.
func _zoom_at(p: Vector2, factor: float) -> void:
	var before := _center + (p - size / 2.0) / _scale_px()
	_zoom = clampf(_zoom * factor, 1.0, MAX_ZOOM)
	_center = before - (p - size / 2.0) / _scale_px()
	_apply_view()

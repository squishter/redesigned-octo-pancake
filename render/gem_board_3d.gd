class_name GemBoard3D
extends SubViewportContainer
## The board in 3D: a gem collage (or a kit's drills) on white paper, under
## a fixed camera looking straight down. Every stone is a faceted gem
## (GemMesh, gem.gdshader) that glints as the light drifts over time and as
## the phone turns: the light hangs still in the room, so tilting, turning
## or rolling the phone (in any pose, upright too) moves it across the
## stones, always staying generally overhead; the camera never moves.
## Each stone casts a soft shadow on the paper (`shadows` turns it off) with
## colored caustic light in it (gem_shadow.gdshader), and the brightest
## glints flare into star sparkles (gem_sparkle.gdshader). Caustics follow
## the light's direction only, so they hold still when it does.
##
## Stones of one shape and cut share a mesh and draw as one MultiMesh, so
## thousands stay cheap. Pinch to zoom, drag to pan, double-tap to fit (mouse
## wheel on desktop), like PreviewCanvas.
##
## For play, stones can be hidden until they are placed (`shown` in
## show_collage, set_slot_shown), pop in when placed (fill_slot), and ripple
## out from a point when the picture is done (celebrate). A `stroke_filter`
## turns one-finger touches that start where it says into strokes
## (stroke_* signals, in board units) instead of pans, and view_transform()
## maps board units onto the control, for drawing over the board.

signal view_changed
signal stroke_started(at: Vector2)
signal stroke_moved(from: Vector2, to: Vector2)
signal stroke_ended

const GEM_SHADER := preload("res://render/gem.gdshader")
const SHADOW_SHADER := preload("res://render/gem_shadow.gdshader")
const SPARKLE_SHADER := preload("res://render/gem_sparkle.gdshader")
const PAPER_SHADER := preload("res://render/paper.gdshader")
const BACKGROUND := Color("#2a1f3d")
const MAX_ZOOM := 40.0
const DOUBLE_TAP_MS := 300
const DOUBLE_TAP_SLOP := 60.0
## Room around the picture when fitted, as a share of its size.
const MARGIN := 0.03
## A placed stone pops in over this long, overshooting a little; done
## pictures pulse each stone for PULSE_TIME, in a wave CELEBRATE_TIME long.
const POP_TIME := 0.32
const PULSE_TIME := 0.6
const CELEBRATE_TIME := 1.4
## A stone that flew in settles from a little too big over this long.
const LAND_TIME := 0.18
## How far a pop overshoots (the usual "back" easing constant).
const OVERSHOOT := 1.70158
## Gem colors cut as opaque polished stones rather than see-through ones,
## so white reads apart from clear diamond.
const OPAQUE_GEMS := ["snow"]
## A stone's girdle stands this high above the paper, and its crown rises
## about this much above that, in its half-widths.
const GIRDLE_HEIGHT := 0.45
const CROWN_HEIGHT := 0.3
## Shadow and sparkle planes, in stone half-sizes (shadows must cover the
## farthest the light can push them).
const SHADOW_SPAN := 2.6
const SPARKLE_SPAN := 1.7
## Kit drills: board units per cell, and the drill's share of it.
const KIT_CELL := 10.0
const KIT_DRILL := 0.9
## The key light: where it hangs when the picture appears (azimuth in the
## board's xz plane, toward the picture's top left; elevation above the
## paper) and how far it drifts. Radians.
const KEY_AZIMUTH := -2.3
const KEY_ELEVATION := 0.95
const DRIFT := 0.45
## The fill light's height, and the lowest the key and fill go (radians):
## however the phone turns, the light stays generally overhead.
const FILL_ELEVATION := 0.6
const MIN_KEY_ELEVATION := 0.7
const MIN_FILL_ELEVATION := 0.4
## The phone's turns count this many times over, so tilting it about 30
## degrees (flat, side to side) or turning it about 30 degrees (upright)
## swings the light over the stones from one side to the other.
const TURN_GAIN := 2.0
## How quickly gravity readings and the light settle (per second).
const SENSOR_SMOOTH := 6.0
const LIGHT_SMOOTH := 8.0

## The light drifts with time (tests freeze it and set the time instead).
var animate := true
## Seconds of drift; the light's position over time.
var light_time := 0.0
## How the phone has turned since the picture appeared, as the rotation
## that carries a direction fixed in the room through the phone's own axes
## (x right, y up the screen, z out of it). Tests set it.
var turn := Basis.IDENTITY
var use_sensor := true
## The lights' smoothed directions, in board space.
var key_dir := Vector3.UP
var fill_dir := Vector3.UP
## Darken the paper under each stone (its caustic light shows either way).
var shadows := true:
	set(value):
		shadows = value
		_shadow_material.set_shader_parameter("shadow_strength", 1.0 if value else 0.0)
## Room around the fitted picture, as a share of its size.
var margin := MARGIN
## Off: touches, drags and the wheel leave the board alone.
var input_enabled := true
## Called with the board point where a lone finger touches down: true makes
## that touch a stroke (stroke_started, stroke_moved, stroke_ended) instead
## of a pan. Unset, every touch pans.
var stroke_filter := Callable()

var _viewport := SubViewport.new()
var _camera := Camera3D.new()
var _paper := MeshInstance3D.new()
var _env := Environment.new()
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
## Smoothed gravity in the phone's axes, which way was up (in them) when
## the picture appeared, and how far the phone has spun about the vertical
## since (radians, from the gyroscope).
var _gravity := Vector3.ZERO
var _start_up := Vector3.ZERO
var _spin := 0.0
## Ease the lights toward their new directions (off for a new picture).
var _settle := false
var _touches := {}
var _last_tap_ms := -DOUBLE_TAP_MS
var _last_tap_pos := Vector2.ZERO
## The touch drawing a stroke, or -1.
var _stroke := -1
## Each slot's instances in every layer: [MultiMesh, index, full transform].
var _refs: Array = []
## Slots animating: slot -> [start (on _clock), 0 pop in, 1 pulse or 2 land].
var _anims := {}
var _clock := 0.0
## The light drifts faster until then (on _clock), sweeping glints over a
## finished picture.
var _sweep_until := 0.0


func _init() -> void:
	stretch = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.handle_input_locally = false
	add_child(_viewport)
	var env := _env
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
	_shadow_material.set_shader_parameter("span", SHADOW_SPAN)
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
	_clock += delta
	if animate:
		var sweep := clampf((_sweep_until - _clock) / CELEBRATE_TIME, 0.0, 1.0)
		light_time += delta * (1.0 + 5.0 * sin(PI * sweep))
	if not _anims.is_empty():
		_step_anims()
	if use_sensor:
		_read_sensors(delta)
	update_light(delta)


## Follows the phone's orientation, each sensor for one thing so they never
## pull against each other: gravity for tilting and rolling (in any pose),
## the gyroscope for spinning about the vertical (turning it while upright).
func _read_sensors(delta: float) -> void:
	var g := Input.get_gravity()
	if g.length() < 1.0:
		return  # no sensor (desktop, tests)
	_gravity = g if _gravity == Vector3.ZERO else _gravity.lerp(g, 1.0 - exp(-delta * SENSOR_SMOOTH))
	var up := -_gravity.normalized()
	if _start_up == Vector3.ZERO:
		_start_up = up
		_spin = 0.0
	_spin += Input.get_gyroscope().dot(up) * delta
	turn = phone_turn(_start_up, up, _spin)


## The phone's turn from how it stood (`start_up`: the room's up in its
## axes then) to now (`up`), having spun `spin` radians about the vertical
## on the way: a room-fixed direction tilts with the shortest turn from
## start_up to up, then spins back about up.
static func phone_turn(start_up: Vector3, up: Vector3, spin: float) -> Basis:
	return Basis(up, -spin) * Basis(Quaternion(start_up, up))


## Sets every shader's light for the current time and the phone's turn,
## easing toward it after `delta` seconds (0 jumps straight there).
func update_light(delta := 0.0) -> void:
	var t := light_time
	var az := KEY_AZIMUTH + DRIFT * sin(t * 0.23) + 0.15 * sin(t * 0.61 + 1.3)
	var el := KEY_ELEVATION + 0.1 * sin(t * 0.17 + 0.4)
	var key := _turned(Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)), MIN_KEY_ELEVATION)
	var faz := az + 2.6 + 0.3 * sin(t * 0.31 + 2.0)
	var fel := FILL_ELEVATION + 0.08 * sin(t * 0.27)
	var fill := _turned(Vector3(cos(faz) * cos(fel), sin(fel), sin(faz) * cos(fel)), MIN_FILL_ELEVATION)
	var k := 1.0 - exp(-delta * LIGHT_SMOOTH) if _settle and delta > 0.0 else 1.0
	key_dir = key_dir.slerp(key, k).normalized()
	fill_dir = fill_dir.slerp(fill, k).normalized()
	_settle = true
	for m: ShaderMaterial in [_gem_material, _shadow_material, _sparkle_material, _paper_material]:
		m.set_shader_parameter("key_dir", key_dir)
		m.set_shader_parameter("fill_dir", fill_dir)


## A light direction (board space) after the phone's turn (TURN_GAIN times
## over): into the phone's axes (board x right, y toward the viewer, z down
## the picture are its x, z and -y), turned, and back, staying at least
## `lowest` (radians) above the paper.
func _turned(board_dir: Vector3, lowest: float) -> Vector3:
	var d := Vector3(board_dir.x, -board_dir.z, board_dir.y)
	var q := turn.get_rotation_quaternion()
	if q.get_angle() > 1e-5:
		d = Basis(q.get_axis(), minf(q.get_angle() * TURN_GAIN, PI)) * d
	var b := Vector3(d.x, d.z, -d.y).normalized()
	if b.y < sin(lowest):
		var flat := Vector2(b.x, b.z)
		flat = (flat.normalized() if flat.length() > 1e-4 else Vector2(board_dir.x, board_dir.z).normalized())
		b = Vector3(flat.x * cos(lowest), sin(lowest), flat.y * cos(lowest))
	return b


## `shown` (one byte per slot, 0 hides it) leaves stones out until they are
## placed; empty shows them all.
func show_collage(picture: Dictionary, shown := PackedByteArray()) -> void:
	var w: float = picture["width"]
	var h: float = picture["height"]
	var lines: PackedByteArray = picture.get("lines_visible", PackedByteArray())
	_build(picture["slots"], Vector2(w, h), lines, Vector2i(int(w), int(h)))
	if not shown.is_empty():
		for i in mini(shown.size(), _refs.size()):
			if shown[i] == 0:
				_apply_scale(i, 0.0)


## Shows or hides one stone at once.
func set_slot_shown(i: int, on: bool) -> void:
	_anims.erase(i)
	_apply_scale(i, 1.0 if on else 0.0)


## Shows one stone, popping it in.
func fill_slot(i: int) -> void:
	_apply_scale(i, 0.0)
	_anims[i] = [_clock, 0]


## Shows one stone that has just flown in, settling into place.
func land_slot(i: int) -> void:
	_anims[i] = [_clock, 2]
	_step_anims()


## Draws only the stones, no paper, over a transparent background (for
## icons and stones flying over the screen).
func set_transparent() -> void:
	_viewport.transparent_bg = true
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.glow_enabled = false
	_paper.visible = false


## A wave of pulses through every stone, outward from board point `from`,
## while the light sweeps over them. Returns how long it lasts (seconds).
func celebrate(from: Vector2) -> float:
	var far := 1.0
	var at := []
	for refs: Array in _refs:
		if refs.is_empty():
			at.append(0.0)
			continue
		var o: Vector3 = refs[0][2].origin
		var d := Vector2(o.x, o.z).distance_to(from)
		at.append(d)
		far = maxf(far, d)
	for i in _refs.size():
		_anims[i] = [_clock + at[i] / far * CELEBRATE_TIME, 1]
	_sweep_until = _clock + CELEBRATE_TIME + PULSE_TIME
	return CELEBRATE_TIME + PULSE_TIME


## Moves animating stones along: pops ease out with an overshoot, pulses
## swell and settle.
func _step_anims() -> void:
	var done := []
	for i: int in _anims:
		var a: Array = _anims[i]
		var t: float = _clock - a[0]
		if t < 0.0:
			continue
		var u := minf(t / ([POP_TIME, PULSE_TIME, LAND_TIME][a[1]] as float), 1.0)
		var f := 1.0
		match a[1]:
			0:
				f = 1.0 + (OVERSHOOT + 1.0) * pow(u - 1.0, 3.0) + OVERSHOOT * pow(u - 1.0, 2.0)
			1:
				f = 1.0 + 0.3 * sin(PI * u)
			_:
				f = 1.0 + 0.15 * (1.0 - u) * (1.0 - u)
		_apply_scale(i, f)
		if u >= 1.0:
			done.append(i)
	for i: int in done:
		_anims.erase(i)


## Scales a stone (gem, shadow and sparkle) about its own place; 0 hides it.
func _apply_scale(i: int, f: float) -> void:
	if i < 0 or i >= _refs.size():
		return
	var k := maxf(f, 0.001)
	for ref: Array in _refs[i]:
		var xf: Transform3D = ref[2]
		var o := xf.origin
		(ref[0] as MultiMesh).set_instance_transform(ref[1],
				Transform3D(xf.basis.scaled(Vector3(k, k, k)), Vector3(o.x, o.y * k, o.z)))


## The board's picture as a texture (for icons cut from a board of single stones).
func get_view_texture() -> ViewportTexture:
	return _viewport.get_texture()


## Keeps rendering while off screen.
func set_always_render() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


## Board units to this control's px, as the view stands.
func view_transform() -> Transform2D:
	var s := _scale_px()
	return Transform2D(0.0, Vector2(s, s), 0.0, size / 2.0 - _center * s)


## This control's px to board units.
func screen_to_board(p: Vector2) -> Vector2:
	return _center + (p - size / 2.0) / _scale_px()


## Screen px per board unit.
func scale_px() -> float:
	return _scale_px()


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
	_settle = false
	_board = board
	_anims.clear()
	_refs = []
	_refs.resize(slots.size())
	for i in slots.size():
		_refs[i] = []
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
		var xf: Transform3D
		match kind:
			"gem":
				at.y = GIRDLE_HEIGHT * small
				xf = Transform3D(turn * Basis.from_scale(Vector3(half_len, small, half_wid)), at)
				# Opaque stones say so in their color's alpha.
				var opaque: bool = str(s.get("target_gem", "")) in OPAQUE_GEMS
				var optics := Vector2(1.55, 0.0) if opaque else _optics(color)
				mm.set_instance_custom_data(k, Color(random, optics.x, optics.y, cut))
				color = Color(color, 0.0 if opaque else 1.0)
			"shadow":
				at.y = 0.02
				xf = Transform3D(turn * Basis.from_scale(Vector3(half_len, 1.0, half_wid)), at)
				mm.set_instance_custom_data(k, Color(random, (GIRDLE_HEIGHT + CROWN_HEIGHT) * small, 0.0, 0.0))
			_:
				at.y = (GIRDLE_HEIGHT + CROWN_HEIGHT) * small + 0.1
				var reach := maxf(half_len, half_wid) * SPARKLE_SPAN
				xf = Transform3D(Basis.from_scale(Vector3(reach, 1.0, reach)), at)
				mm.set_instance_custom_data(k, Color(random, 0.0, 0.0, 0.0))
		mm.set_instance_transform(k, xf)
		mm.set_instance_color(k, color)
		if i < _refs.size():
			_refs[i].append([mm, k, xf])
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
	var fit := minf(view.x / (_board.x * (1.0 + margin * 2.0)), view.y / (_board.y * (1.0 + margin * 2.0)))
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
	view_changed.emit()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not input_enabled:
		return
	if event is InputEventScreenTouch:
		var p := _local(event.position)
		if event.pressed:
			if not Rect2(Vector2.ZERO, size).has_point(p):
				return
			_touches[event.index] = p
			if _touches.size() > 1 and _stroke >= 0:
				# A second finger: the stroke ends and the pair pinches.
				_stroke = -1
				stroke_ended.emit()
			if _touches.size() == 1:
				if stroke_filter.is_valid() and stroke_filter.call(screen_to_board(p)):
					_stroke = event.index
					stroke_started.emit(screen_to_board(p))
					return
				var now := Time.get_ticks_msec()
				if now - _last_tap_ms < DOUBLE_TAP_MS and p.distance_to(_last_tap_pos) < DOUBLE_TAP_SLOP:
					reset_view()
					now = -DOUBLE_TAP_MS
				_last_tap_ms = now
				_last_tap_pos = p
		else:
			_touches.erase(event.index)
			if event.index == _stroke:
				_stroke = -1
				stroke_ended.emit()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var p := _local(event.position)
		var prev: Vector2 = _touches[event.index]
		if event.index == _stroke:
			_touches[event.index] = p
			stroke_moved.emit(screen_to_board(prev), screen_to_board(p))
			return
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


func _scale_px() -> float:
	var view := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	return minf(view.x / (_board.x * (1.0 + margin * 2.0)), view.y / (_board.y * (1.0 + margin * 2.0))) * _zoom


func _pan(screen_delta: Vector2) -> void:
	_center -= screen_delta / _scale_px()
	_apply_view()


## Zooms by `factor` keeping the board point under screen point `p` still.
func _zoom_at(p: Vector2, factor: float) -> void:
	var before := _center + (p - size / 2.0) / _scale_px()
	_zoom = clampf(_zoom * factor, 1.0, MAX_ZOOM)
	_center = before - (p - size / 2.0) / _scale_px()
	_apply_view()

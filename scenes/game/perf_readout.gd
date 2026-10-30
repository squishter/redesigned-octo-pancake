class_name PerfReadout
extends Label
## A small performance readout over a GemBoard3D, for judging how the board
## runs on a phone: frames a second, frame time (real time) and the last
## frame's process time; how often the board renders and its GPU time per
## render (and the whole screen's); and the triangles and draw calls of the
## board's last render and of the whole last frame. Off by default; debug
## builds' Settings turn it on (with the frame cap, see apply_settings), the
## play screen toggles it with a long press on its progress line, the
## generator lab with a box in its Options.

## Seconds between updates.
const EVERY := 0.5
## Debug builds: her settings for the readout and the frame cap, and the
## caps Settings offers (0: none; unset, application/run/max_fps holds).
const SHOWN_KEY := "debug_perf_readout"
const CAP_KEY := "debug_max_fps"
const TEST_KEY := "debug_board_test"
const CAPS := [45, 60, 30, 0]

## Shown on every screen that has one, for the rest of the session.
static var shown := false

var board: GemBoard3D:
	set(value):
		board = value
		_restart()

## When the current count started (µs), and frames since.
var _since := 0
var _frames := 0
var _renders := 0
var _board_gpu := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 24)
	add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	bg.set_content_margin_all(10.0)
	bg.set_corner_radius_all(8)
	add_theme_stylebox_override("normal", bg)
	text = "…"


func _ready() -> void:
	visible = shown
	visibility_changed.connect(_restart)
	_restart()


## Shows or hides it (and every readout from now on).
func toggle() -> void:
	shown = not shown
	visible = shown


## Applies her saved readout and frame cap (debug builds only).
static func apply_settings(settings: Dictionary) -> void:
	if not OS.is_debug_build():
		return
	shown = bool(settings.get(SHOWN_KEY, false))
	GemBoard3D.debug_test = str(settings.get(TEST_KEY, "normal"))
	if settings.has(CAP_KEY):
		Engine.max_fps = int(settings[CAP_KEY])


func _restart() -> void:
	_since = Time.get_ticks_usec()
	_frames = 0
	_renders = board.render_count if board else 0
	_board_gpu = 0.0
	if board and is_inside_tree():
		RenderingServer.viewport_set_measure_render_time(board.render_viewport_rid(), visible)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), visible)


func _process(_delta: float) -> void:
	if not visible or board == null:
		return
	_frames += 1
	var rid := board.render_viewport_rid()
	# Only frames the board renders in measure it.
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	if gpu > 0.0:
		_board_gpu = gpu
	var seconds := (Time.get_ticks_usec() - _since) / 1000000.0
	if seconds < EVERY:
		return
	var renders := board.render_count - _renders
	var process := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var screen_gpu := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	var vis := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	text = "\n".join([
		"%.0f fps   %.1f ms/frame   process %.1f ms" % [_frames / seconds, seconds * 1000.0 / _frames, process],
		"board: %.0f renders/s   gpu %.1f ms/render   screen gpu %.1f ms" % [renders / seconds, _board_gpu, screen_gpu],
		"board render: %s tris   %d draws" % [_count(RenderingServer.viewport_get_render_info(rid, vis,
				RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)),
				RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)],
		"last frame: %s tris   %d draws" % [_count(RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)],
	])
	_since = Time.get_ticks_usec()
	_frames = 0
	_renders = board.render_count


static func _count(n: int) -> String:
	if n >= 1000000:
		return "%.2fM" % (n / 1000000.0)
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)

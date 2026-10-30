class_name CameraCapture
extends PanelContainer
## A full-screen overlay that takes a photo with the device camera through
## CameraServer, for photo puzzles (the menu) and the generator lab.
## The feed is drawn into a SubViewport through a shader that turns any feed
## type (RGB, YCbCr, or separate Y and CbCr planes) into RGB, so the snapshot
## is a plain image whatever the platform delivers.
##
## On Android the export preset needs the CAMERA permission; it is requested
## here when the panel opens.

signal captured(photo: Image)
signal closed

const LabTheme := preload("res://scenes/dev/lab_theme.gd")

## Largest feed width picked from the camera's formats; more is slow to
## generate from and adds nothing at kit or collage sizes.
const MAX_FEED_WIDTH := 1920
const CONVERT_SHADER := """
shader_type canvas_item;

// CameraFeed.FeedDataType: 1 RGB, 2 YCbCr in one image, 3 separate Y and CbCr.
uniform int data_type = 1;
uniform sampler2D cbcr_tex : filter_linear;

void fragment() {
	vec4 a = texture(TEXTURE, UV);
	if (data_type == 1) {
		COLOR = vec4(a.rgb, 1.0);
	} else {
		vec2 cbcr = (data_type == 3 ? texture(cbcr_tex, UV).rg : a.gb) - 0.5;
		float y = a.r;
		vec3 rgb = vec3(y + 1.402 * cbcr.y, y - 0.344136 * cbcr.x - 0.714136 * cbcr.y, y + 1.772 * cbcr.x);
		COLOR = vec4(clamp(rgb, 0.0, 1.0), 1.0);
	}
}
"""

var _feeds: Array[CameraFeed] = []
var _feed_index := 0
var _turns := 0  # quarter turns clockwise applied to the snapshot
var _viewport: SubViewport
var _feed_rect: TextureRect
var _material: ShaderMaterial
var _main_tex: CameraTexture
var _cbcr_tex: CameraTexture
var _preview: TextureRect
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	add_child(root)
	SafeArea.apply(root)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", LabTheme.SMALL_FONT_SIZE)
	_status.add_theme_color_override("font_color", LabTheme.TEXT_DIM)
	root.add_child(_status)

	_material = ShaderMaterial.new()
	_material.shader = Shader.new()
	_material.shader.code = CONVERT_SHADER
	_main_tex = CameraTexture.new()
	_main_tex.which_feed = CameraServer.FEED_RGBA_IMAGE
	_cbcr_tex = CameraTexture.new()
	_cbcr_tex.which_feed = CameraServer.FEED_CBCR_IMAGE
	_material.set_shader_parameter("cbcr_tex", _cbcr_tex)

	_viewport = SubViewport.new()
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_feed_rect = TextureRect.new()
	_feed_rect.texture = _main_tex
	_feed_rect.material = _material
	_feed_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_feed_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_viewport.add_child(_feed_rect)

	_preview = TextureRect.new()
	_preview.texture = _viewport.get_texture()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_preview)

	# The buttons, where thumbs reach.
	var bar := HBoxContainer.new()
	root.add_child(bar)
	_button(bar, "Cancel", close)
	_button(bar, "Switch", _switch_camera)
	_button(bar, "Turn", _rotate)
	var snap := _button(bar, "Take photo", _snap)
	snap.add_theme_color_override("font_color", LabTheme.GOLD)

	CameraServer.camera_feed_added.connect(func(_id: int) -> void: _refresh_feeds())
	CameraServer.camera_feed_removed.connect(func(_id: int) -> void: _refresh_feeds())
	get_tree().on_request_permissions_result.connect(_on_permission)
	hide()


## Shows the panel and starts the camera (asking for permission first on
## Android). `captured` follows if she takes a photo, `closed` either way.
func open() -> void:
	show()
	_turns = 1 if OS.get_name() == "Android" else 0  # Android sensors are landscape
	if OS.get_name() == "Android" and not "android.permission.CAMERA" in OS.get_granted_permissions():
		_status.text = "Asking for camera permission…"
		OS.request_permission("android.permission.CAMERA")
		return
	_start()


func close() -> void:
	_stop()
	hide()
	closed.emit()


func _exit_tree() -> void:
	if visible:
		_stop()


func _on_permission(permission: String, granted: bool) -> void:
	if not visible or not permission.ends_with("CAMERA"):
		return
	if granted:
		_start()
	else:
		_status.text = "No camera permission."


func _start() -> void:
	CameraServer.monitoring_feeds = true
	_refresh_feeds()


func _stop() -> void:
	for feed in _feeds:
		feed.feed_is_active = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	CameraServer.monitoring_feeds = false


func _refresh_feeds() -> void:
	if not visible:
		return
	_feeds.clear()
	for feed in CameraServer.feeds():
		# Back cameras first: that's what you point at a picture.
		if feed.get_position() == CameraFeed.FEED_BACK:
			_feeds.push_front(feed)
		else:
			_feeds.append(feed)
	if _feeds.is_empty():
		_status.text = "No camera found (waiting for one to connect)."
		return
	_feed_index = clampi(_feed_index, 0, _feeds.size() - 1)
	_activate(_feeds[_feed_index])


func _activate(feed: CameraFeed) -> void:
	for other in _feeds:
		if other != feed:
			other.feed_is_active = false
	var formats := feed.get_formats()
	if not formats.is_empty():
		feed.set_format(_best_format(formats), {})
	feed.feed_is_active = true
	_main_tex.camera_feed_id = feed.get_id()
	_cbcr_tex.camera_feed_id = feed.get_id()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_status.text = "%s (%d of %d)" % [feed.get_name(), _feed_index + 1, _feeds.size()]


## The biggest format no wider than MAX_FEED_WIDTH (or the narrowest).
static func _best_format(formats: Array) -> int:
	var best := -1
	var best_px := 0
	var narrowest := 0
	for i in formats.size():
		var f: Dictionary = formats[i]
		var w: int = f.get("width", 0)
		var px: int = w * int(f.get("height", 0))
		if w <= MAX_FEED_WIDTH and px > best_px:
			best = i
			best_px = px
		if w < int(formats[narrowest].get("width", 0)):
			narrowest = i
	return best if best >= 0 else narrowest


func _process(_delta: float) -> void:
	if not visible or _feeds.is_empty():
		return
	var feed := _feeds[_feed_index]
	_material.set_shader_parameter("data_type", feed.get_datatype())
	var tex_size := Vector2i(_main_tex.get_size())
	if tex_size.x > 0 and tex_size.y > 0 and _viewport.size != tex_size:
		_viewport.size = tex_size
		_feed_rect.size = tex_size


func _switch_camera() -> void:
	if _feeds.size() < 2:
		return
	_feed_index = (_feed_index + 1) % _feeds.size()
	_activate(_feeds[_feed_index])


## The preview shows the feed as the sensor sees it; the photo is turned
## this much more.
func _rotate() -> void:
	_turns = (_turns + 1) % 4
	_status.text = "The photo will be turned %d° clockwise." % (_turns * 90)


func _snap() -> void:
	if _feeds.is_empty() or _feeds[_feed_index].get_datatype() == CameraFeed.FEED_NOIMAGE:
		_status.text = "No camera image yet."
		return
	await RenderingServer.frame_post_draw
	var img := _viewport.get_texture().get_image()
	if img == null or img.is_empty():
		_status.text = "Couldn't read the camera image."
		return
	img.convert(Image.FORMAT_RGBA8)
	for _i in _turns:
		img.rotate_90(CLOCKWISE)
	close()
	captured.emit(img)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = LabTheme.TAP_HEIGHT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	parent.add_child(b)
	return b

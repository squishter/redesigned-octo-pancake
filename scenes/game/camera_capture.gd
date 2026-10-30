class_name CameraCapture
extends PanelContainer
## A full-screen overlay that takes a photo with the device camera through
## CameraServer, for photo puzzles (the menu) and the generator lab.
## The preview is drawn into a SubViewport through a shader that turns any
## feed type (RGB, YCbCr, or separate Y and CbCr planes, which is what Android
## sends) into RGB, turned upright. The photo itself is made on the CPU from
## the camera's own planes (photo_from_planes), not read back from the screen,
## so it doesn't depend on how the preview was drawn.
##
## Which way is up comes from the feed's transform (Godot works it out from
## the sensor's and the screen's orientation); Turn adds quarter turns on top.
##
## On Android the export preset needs the CAMERA permission; it is requested
## here when the panel opens.

signal captured(photo: Image)
signal closed

const LabTheme := preload("res://scenes/dev/lab_theme.gd")

## Largest feed width picked from the camera's formats; more is slow to
## convert and adds nothing at kit or collage sizes.
const MAX_FEED_WIDTH := 1920
## The photo's longest side (PuzzleMaker shrinks photos to this anyway).
const PHOTO_MAX := 1024
const CONVERT_SHADER := """
shader_type canvas_item;

// CameraFeed.FeedDataType: 1 RGB, 2 YCbCr in one image, 3 separate Y and CbCr.
uniform int data_type = 1;
uniform sampler2D cbcr_tex : filter_linear;
// The CbCr plane as one channel twice as wide (Cb, Cr, Cb, Cr...) instead of
// two channels; see chroma_layout.
uniform bool chroma_interleaved = false;

vec2 chroma(vec2 uv) {
	if (chroma_interleaved) {
		ivec2 size = textureSize(cbcr_tex, 0);
		ivec2 pairs = ivec2(max(size.x / 2, 1), size.y);
		ivec2 p = clamp(ivec2(uv * vec2(pairs)), ivec2(0), pairs - 1);
		return vec2(texelFetch(cbcr_tex, ivec2(p.x * 2, p.y), 0).r, texelFetch(cbcr_tex, ivec2(p.x * 2 + 1, p.y), 0).r);
	}
	return texture(cbcr_tex, uv).rg;
}

void fragment() {
	vec4 a = texture(TEXTURE, UV);
	if (data_type == 1) {
		COLOR = vec4(a.rgb, 1.0);
	} else {
		vec2 cbcr = (data_type == 3 ? chroma(UV) : a.gb) - 0.5;
		float y = a.r;
		vec3 rgb = vec3(y + 1.402 * cbcr.y, y - 0.344136 * cbcr.x - 0.714136 * cbcr.y, y + 1.772 * cbcr.x);
		COLOR = vec4(clamp(rgb, 0.0, 1.0), 1.0);
	}
}
"""

var _feeds: Array[CameraFeed] = []
var _feed_index := 0
var _extra_turns := 0  # quarter turns clockwise she added with Turn
## The CbCr plane's layout once looked at (see chroma_layout), "" before,
## and when to look (a moment after the feed starts, so frames have come).
var _chroma := ""
var _chroma_check_at := 0
var _feed_text := ""
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
	_extra_turns = 0
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
	var format := ""
	if not formats.is_empty():
		var best := _best_format(formats)
		feed.set_format(best, {})
		var f: Dictionary = formats[best]
		format = " · %s %d×%d" % [f.get("format", "?"), f.get("width", 0), f.get("height", 0)]
	feed.feed_is_active = true
	_main_tex.camera_feed_id = feed.get_id()
	_cbcr_tex.camera_feed_id = feed.get_id()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The format (and the CbCr layout, once seen) helps tell camera problems apart.
	_feed_text = "%s (%d of %d)%s" % [feed.get_name(), _feed_index + 1, _feeds.size(), format]
	_status.text = _feed_text
	_chroma = ""
	_chroma_check_at = Time.get_ticks_msec() + 600


## The biggest format no wider than MAX_FEED_WIDTH (or the narrowest),
## YUV_420_888 first on Android: Godot copies its rows carefully, while its
## RGBA path assumes rows without padding, which some cameras have.
static func _best_format(formats: Array) -> int:
	var best := -1
	var best_score := -1
	var narrowest := 0
	for i in formats.size():
		var f: Dictionary = formats[i]
		var w: int = f.get("width", 0)
		var score: int = w * int(f.get("height", 0))
		if str(f.get("format", "")) == "YUV_420_888":
			score += 1 << 40
		if w <= MAX_FEED_WIDTH and score > best_score:
			best = i
			best_score = score
		if w < int(formats[narrowest].get("width", 0)):
			narrowest = i
	return best if best >= 0 else narrowest


## Quarter turns clockwise that stand the feed upright: the feed's own
## rotation (set from the sensor and screen orientation) plus Turn's.
func _turns() -> int:
	var turns := _extra_turns
	if not _feeds.is_empty():
		var rotation := _feeds[_feed_index].feed_transform.get_rotation()
		turns += roundi(rotation / (PI / 2.0))
	return posmod(turns, 4)


func _process(_delta: float) -> void:
	if not visible or _feeds.is_empty():
		return
	var feed := _feeds[_feed_index]
	_material.set_shader_parameter("data_type", feed.get_datatype())
	if _chroma == "" and feed.get_datatype() == CameraFeed.FEED_YCBCR_SEP and Time.get_ticks_msec() >= _chroma_check_at:
		_check_chroma()
	var tex_size := Vector2i(_main_tex.get_size())
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	# The feed turned upright inside the viewport, so the preview stands
	# the way the photo will.
	lay_out_upright(_feed_rect, _viewport, tex_size, _turns())


## Looks at the CbCr plane once (reading a texture back is slow) and tells
## the shader how to read it.
func _check_chroma() -> void:
	var c := _cbcr_tex.get_image()
	if c == null or c.is_empty():
		_chroma_check_at = Time.get_ticks_msec() + 300
		return
	_chroma = chroma_layout(c)
	_material.set_shader_parameter("chroma_interleaved", _chroma == "interleaved")
	_status.text = "%s · CbCr %s %d×%d (%s)" % [_feed_text, _format_name(c.get_format()), c.get_width(),
			c.get_height(), _chroma]


## How a CbCr plane's bytes are laid out: "pairs" (two channels per pixel,
## Cb then Cr, as Godot's Android camera builds it) or "interleaved" (one
## channel, Cb and Cr side by side, so twice as wide).
static func chroma_layout(chroma: Image) -> String:
	var per_pixel := chroma.get_data().size() / maxi(1, chroma.get_width() * chroma.get_height())
	return "interleaved" if per_pixel == 1 else "pairs"


## A CbCr plane as RG8 (R: Cb, G: Cr), whichever layout it came in.
static func chroma_pairs(chroma: Image) -> Image:
	match chroma_layout(chroma):
		"interleaved":
			var w := maxi(1, chroma.get_width() / 2)
			var data := chroma.get_data()
			data.resize(w * 2 * chroma.get_height())
			return Image.create_from_data(w, chroma.get_height(), false, Image.FORMAT_RG8, data)
	var w := chroma.get_width()
	var h := chroma.get_height()
	if chroma.get_data().size() == w * h * 2:
		# RG8, or another two-byte format (LA8): the same bytes, as RG8.
		return Image.create_from_data(w, h, false, Image.FORMAT_RG8, chroma.get_data())
	var out := chroma.duplicate() as Image
	out.convert(Image.FORMAT_RG8)
	return out


static func _format_name(format: int) -> String:
	match format:
		Image.FORMAT_L8:
			return "L8"
		Image.FORMAT_LA8:
			return "LA8"
		Image.FORMAT_R8:
			return "R8"
		Image.FORMAT_RG8:
			return "RG8"
		Image.FORMAT_RGB8:
			return "RGB8"
		Image.FORMAT_RGBA8:
			return "RGBA8"
	return "format %d" % format


## Sizes `viewport` to the feed turned `turns` quarter turns clockwise, and
## turns `rect` (showing the feed, `tex_size` big) about its center to fill it.
static func lay_out_upright(rect: Control, viewport: SubViewport, tex_size: Vector2i, turns: int) -> void:
	var upright := tex_size if turns % 2 == 0 else Vector2i(tex_size.y, tex_size.x)
	if viewport.size != upright:
		viewport.size = upright
	rect.size = tex_size
	rect.pivot_offset = Vector2(tex_size) / 2.0
	rect.rotation = turns * PI / 2.0
	rect.position = (Vector2(upright) - Vector2(tex_size)) / 2.0


func _switch_camera() -> void:
	if _feeds.size() < 2:
		return
	_feed_index = (_feed_index + 1) % _feeds.size()
	_activate(_feeds[_feed_index])


## A quarter turn more, for when the camera's idea of up is wrong.
func _rotate() -> void:
	_extra_turns = (_extra_turns + 1) % 4


func _snap() -> void:
	if _feeds.is_empty() or _feeds[_feed_index].get_datatype() == CameraFeed.FEED_NOIMAGE:
		_status.text = "No camera image yet."
		return
	var img: Image
	if _feeds[_feed_index].get_datatype() == CameraFeed.FEED_YCBCR_SEP:
		img = photo_from_planes(_main_tex.get_image(), _cbcr_tex.get_image(), PHOTO_MAX)
	else:
		img = _main_tex.get_image()
	if img == null or img.is_empty():
		_status.text = "Couldn't read the camera image."
		return
	if img.get_format() != Image.FORMAT_RGB8 and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	for _i in _turns():
		img.rotate_90(CLOCKWISE)
	close()
	captured.emit(img)


## An RGB photo from a camera's separate planes: `luma` (Y, R8) and
## `chroma` (Cb and Cr, usually half as big, in either chroma_layout),
## full-range BT.601 as
## Android's YUV_420_888 is. Shrunk first so its longest side is at most
## `max_side`, which keeps the per-pixel loop short.
static func photo_from_planes(luma: Image, chroma: Image, max_side: int) -> Image:
	if luma == null or chroma == null or luma.is_empty() or chroma.is_empty():
		return null
	var w := luma.get_width()
	var h := luma.get_height()
	var k := minf(1.0, float(max_side) / maxi(w, h))
	w = maxi(1, int(w * k))
	h = maxi(1, int(h * k))
	var y_img := luma.duplicate() as Image
	y_img.convert(Image.FORMAT_R8)
	y_img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var c_img := chroma_pairs(chroma)
	c_img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var ys := y_img.get_data()
	var cs := c_img.get_data()
	var rgb := PackedByteArray()
	rgb.resize(w * h * 3)
	for i in w * h:
		var y := ys[i]
		var cb := cs[i * 2] - 128
		var cr := cs[i * 2 + 1] - 128
		rgb[i * 3] = clampi(roundi(y + 1.402 * cr), 0, 255)
		rgb[i * 3 + 1] = clampi(roundi(y - 0.344136 * cb - 0.714136 * cr), 0, 255)
		rgb[i * 3 + 2] = clampi(roundi(y + 1.772 * cb), 0, 255)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, rgb)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = LabTheme.TAP_HEIGHT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	parent.add_child(b)
	return b

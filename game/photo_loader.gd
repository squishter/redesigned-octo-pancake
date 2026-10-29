class_name PhotoLoader
extends RefCounted
## Loads a photo the right way up. Phone cameras save the pixels as the
## sensor saw them and record which way is up in the JPEG's EXIF
## Orientation tag; Godot's loaders ignore it, so portrait photos came in
## sideways. This reads the tag and turns or mirrors the image to match.

const ORIENTATION_TAG := 0x0112


## The photo at `path` (JPEG, PNG or WebP), upright; null if it can't be read.
static func open(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		var fallback := Image.load_from_file(path)
		return fallback if fallback != null and not fallback.is_empty() else null
	return from_bytes(bytes)


## A photo from its file's bytes, upright; null if it can't be decoded.
static func from_bytes(bytes: PackedByteArray) -> Image:
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes.size() > 3 and bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.size() > 8 and bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes.size() > 12 and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	upright(img, orientation(bytes))
	return img


## The EXIF Orientation (1-8, 1 = already upright) of a JPEG's bytes; 1 if
## there is none.
static func orientation(bytes: PackedByteArray) -> int:
	if bytes.size() < 4 or bytes[0] != 0xFF or bytes[1] != 0xD8:
		return 1
	var i := 2
	while i + 4 <= bytes.size():
		if bytes[i] != 0xFF:
			return 1
		var marker := bytes[i + 1]
		if marker == 0xDA or marker == 0xD9:  # image data starts: no EXIF before it
			return 1
		var length := (bytes[i + 2] << 8) | bytes[i + 3]
		if marker == 0xE1 and i + 10 <= bytes.size() and bytes.slice(i + 4, i + 8).get_string_from_ascii() == "Exif":
			return _tiff_orientation(bytes, i + 10, mini(i + 2 + length, bytes.size()))
		i += 2 + length
	return 1


## The Orientation tag in a TIFF block (EXIF's payload) from `start` to `end`.
static func _tiff_orientation(bytes: PackedByteArray, start: int, end: int) -> int:
	if start + 8 > end:
		return 1
	var little := bytes[start] == 0x49  # "II"; "MM" is big-endian
	var ifd := start + _u32(bytes, start + 4, little)
	if ifd + 2 > end:
		return 1
	var entries := _u16(bytes, ifd, little)
	for k in entries:
		var e := ifd + 2 + k * 12
		if e + 12 > end:
			break
		if _u16(bytes, e, little) == ORIENTATION_TAG:
			var value := _u16(bytes, e + 8, little)
			return value if value >= 1 and value <= 8 else 1
	return 1


## Turns and mirrors `img` so a photo with EXIF orientation `o` stands upright.
static func upright(img: Image, o: int) -> void:
	match o:
		2:
			img.flip_x()
		3:
			img.rotate_180()
		4:
			img.flip_y()
		5:
			img.rotate_90(CLOCKWISE)
			img.flip_x()
		6:
			img.rotate_90(CLOCKWISE)
		7:
			img.rotate_90(COUNTERCLOCKWISE)
			img.flip_x()
		8:
			img.rotate_90(COUNTERCLOCKWISE)


static func _u16(b: PackedByteArray, at: int, little: bool) -> int:
	return (b[at] | (b[at + 1] << 8)) if little else ((b[at] << 8) | b[at + 1])


static func _u32(b: PackedByteArray, at: int, little: bool) -> int:
	if little:
		return b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]

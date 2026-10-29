class_name PatternIO
extends RefCounted
## JSON save and load for generated pictures (kit patterns and collages).
##
## Colors are stored as "#rrggbb", byte grids (kit cells, collage line masks)
## as base64, and vectors as [x, y] arrays.

const BYTE_KEYS := ["cells", "lines", "lines_visible"]
const COLOR_KEYS := ["color", "target_color", "accent_color", "feature_color"]
## JSON numbers come back as floats; these keys hold ints.
const INT_KEYS := ["version", "width", "height", "id", "region", "group", "area", "count", "seed", "pattern_seed",
		"tone", "part", "gem_types"]
const VECTOR_KEYS := ["centroid"]


static func to_json(picture: Dictionary) -> String:
	return JSON.stringify(_encode(picture))


static func from_json(text: String) -> Dictionary:
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return {}
	return _decode(data)


static func save(picture: Dictionary, path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json(picture))
	return OK


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return from_json(FileAccess.get_file_as_string(path))


static func _encode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = _encode(v[k])
			return out
		TYPE_ARRAY:
			var out := []
			for item in v:
				out.append(_encode(item))
			return out
		TYPE_PACKED_BYTE_ARRAY:
			return Marshalls.raw_to_base64(v)
		TYPE_COLOR:
			return "#" + (v as Color).to_html(false)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [v.x, v.y]
		TYPE_FLOAT:
			# Two decimals is plenty for px coordinates and keeps files small.
			return snappedf(v, 0.01)
	return v


static func _decode(v: Variant, key: String = "") -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = _decode(v[k], k)
			# JSON numbers come back as floats; restore the ints we rely on.
			for int_key in INT_KEYS:
				if out.has(int_key) and out[int_key] is float:
					out[int_key] = int(out[int_key])
			return out
		TYPE_ARRAY:
			if key in VECTOR_KEYS:
				return Vector2(v[0], v[1])
			var out := []
			for item in v:
				out.append(_decode(item))
			return out
		TYPE_STRING:
			if key in BYTE_KEYS:
				return Marshalls.base64_to_raw(v)
			if key in COLOR_KEYS:
				return Color(v)
	return v

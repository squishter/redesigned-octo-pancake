class_name PlantComponentData
extends RefCounted
## Immutable authored surfaces. Each caller owns its arrays, so worker jobs
## share no mutable cache. Format: PLANT001 + raw-size u32 + zlib payload.

const CATALOG = preload("res://assets/plants/catalog.json")
const MAGIC := "PLANT001"
const MAX_RAW_BYTES := 32 * 1024 * 1024


static func families(group: String) -> PackedStringArray:
	if group not in ["leaves", "flowers", "buds"]:
		return PackedStringArray()
	return PackedStringArray(CATALOG.data[group].keys())


static func load_component(group: String, family: String, variant := "reference") -> Dictionary:
	if group not in ["leaves", "flowers", "buds"] or family not in CATALOG.data[group]:
		return {}
	var variant_index: int = CATALOG.data.variants.find(variant)
	if variant_index < 0:
		return {}
	var info: Dictionary = CATALOG.data[group][family]
	var packed := FileAccess.get_file_as_bytes(info.file)
	if packed.size() < 12 or packed.slice(0, 8).get_string_from_ascii() != MAGIC:
		return {}
	var length := packed.decode_u32(8)
	if length < 16 or length > MAX_RAW_BYTES:
		return {}
	var raw := packed.slice(12).decompress(length, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != length:
		return {}
	var count := raw.decode_u32(0)
	var index_count := raw.decode_u32(4)
	var variants := raw.decode_u32(8)
	var morph := raw.decode_u32(12)
	var state_bytes := count * 12
	var at := 16 + index_count * 4
	var state_start := at + count * 3
	if count != int(info.vertices) or index_count != int(info.triangles) * 3:
		return {}
	if variants != CATALOG.data.variants.size() or morph > 1:
		return {}
	if state_start + variants * state_bytes * (1 + morph) != raw.size():
		return {}
	var triangles := raw.slice(16, at).to_int32_array()
	var labels := PackedInt32Array()
	var parts := PackedInt32Array()
	labels.resize(count)
	parts.resize(count)
	for i in count:
		labels[i] = raw[at + i]
		parts[i] = raw.decode_u16(at + count + i * 2)
		if labels[i] < 1 or labels[i] > 6:
			return {}
	for index in triangles:
		if index < 0 or index >= count:
			return {}
	var offset := state_start + variant_index * state_bytes * (1 + morph)
	var opened := _points(raw.slice(offset, offset + state_bytes))
	var closed := _points(raw.slice(offset + state_bytes, offset + state_bytes * 2)) if morph else opened
	return {"open": opened, "closed": closed, "triangles": triangles, "labels": labels,
		"parts": parts, "bloom_profile": info.bloom_profile, "sha256": info.sha256}


static func _points(bytes: PackedByteArray) -> PackedVector3Array:
	var floats := bytes.to_float32_array()
	var points := PackedVector3Array()
	points.resize(floats.size() / 3)
	for i in points.size():
		points[i] = Vector3(floats[i * 3], floats[i * 3 + 1], floats[i * 3 + 2])
	return points

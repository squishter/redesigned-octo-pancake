class_name AnimalPoseData
extends RefCounted
## The frozen pose library's on-disk format: plain arrays, small enough to
## ship. Version 2 keeps only what the projector reads, and stores each
## pose's vertex positions once per distinct point:
##
## - Low-poly meshes split every corner per face (flat shading, UV seams), so
##   a point appears up to ~4 times. Vertices that coincide in every frozen
##   pose share one slot; `remap` gives each vertex its slot.
## - Slot positions are 16-bit fixed point inside that pose's bounding box
##   (under 1/65000 of the animal's size, far below a projected pixel).
## - Normals, authored atlas UVs and CoatFlow are left out: the unlit
##   projector never reads them. Live posing still provides them.

const VERSION := 2
## Static surface attributes the projector and generator read.
const ATTRIBUTES := [
	"triangles", "colors", "rest", "coat_coordinates", "face_coordinates", "regions", "protected"
]
const STEPS := 65535.0


## Packs a model's static attributes, portrait indices and states (each with
## "pose", "cameras" and full per-vertex "vertices") for storage.
static func pack(
	attributes: Dictionary, head_indices: PackedInt32Array, states: Array
) -> Dictionary:
	var kept := {}
	for key: String in ATTRIBUTES:
		kept[key] = attributes[key]
	var count: int = (
		(states[0].vertices as PackedVector3Array).size() if not states.is_empty() else 0
	)
	# Vertices share a slot only when they coincide in every pose.
	var slots := {}
	var remap := PackedInt32Array()
	remap.resize(count)
	var firsts := PackedInt32Array()
	for index in count:
		var key := []
		for state: Dictionary in states:
			key.append(state.vertices[index])
		if not slots.has(key):
			slots[key] = firsts.size()
			firsts.append(index)
		remap[index] = slots[key]
	var packed_states := []
	for state: Dictionary in states:
		var vertices: PackedVector3Array = state.vertices
		var low := Vector3(INF, INF, INF)
		var high := -low
		for index in firsts:
			low = low.min(vertices[index])
			high = high.max(vertices[index])
		var span := (high - low).max(Vector3.ONE * 1e-6)
		var bytes := PackedByteArray()
		bytes.resize(firsts.size() * 6)
		var at := 0
		for index in firsts:
			var q := (vertices[index] - low) / span * STEPS
			bytes.encode_u16(at, roundi(q.x))
			bytes.encode_u16(at + 2, roundi(q.y))
			bytes.encode_u16(at + 4, roundi(q.z))
			at += 6
		packed_states.append(
			{
				"pose": state.pose,
				"cameras": state.cameras,
				"origin": low,
				"span": span,
				"positions": bytes
			}
		)
	return {
		"version": VERSION,
		"attributes": kept,
		"head_indices": head_indices,
		"remap": remap,
		"states": packed_states
	}


## A packed state's full per-vertex positions (matching the attributes).
static func vertices(stored: Dictionary, state: Dictionary) -> PackedVector3Array:
	if not state.has("positions"):
		return state.vertices  # Version 1: stored as-is.
	var bytes: PackedByteArray = state.positions
	var scale: Vector3 = state.span / STEPS
	var origin: Vector3 = state.origin
	var slots := PackedVector3Array()
	slots.resize(bytes.size() / 6)
	for slot in slots.size():
		var at := slot * 6
		slots[slot] = (
			origin
			+ (
				Vector3(bytes.decode_u16(at), bytes.decode_u16(at + 2), bytes.decode_u16(at + 4))
				* scale
			)
		)
	var remap: PackedInt32Array = stored.remap
	var out := PackedVector3Array()
	out.resize(remap.size())
	for index in remap.size():
		out[index] = slots[remap[index]]
	return out


## Full-precision states back from a stored file (either version), for
## repacking without re-posing.
static func unpacked_states(stored: Dictionary) -> Array:
	var states := []
	for state: Dictionary in stored.states:
		states.append(
			{"pose": state.pose, "cameras": state.cameras, "vertices": vertices(stored, state)}
		)
	return states

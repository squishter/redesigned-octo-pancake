extends RefCounted
## Serialize actual runtime geometry/cameras for the reference CPU previews.


static func snapshot(animal: AnimalPoseModel, view := "", label: Variant = 0) -> Dictionary:
	var data := animal.portrait_snapshot() if view.begins_with("head_") else animal.snapshot()
	var result := {
		"vertices": [],
		"normals": [],
		"atlas": [],
		"flow": [],
		"colors": [],
		"triangles": [],
		"phase": label,
		"model": animal.model_id,
		"pose": animal.last_pose.get("preset", "rest")
	}
	for key in ["vertices", "normals"]:
		for v: Vector3 in data[key]:
			result[key].append(_vector(v))
	for key in ["atlas", "flow"]:
		for v: Vector2 in data[key]:
			result[key].append([v.x, v.y])
	for color: Color in data.colors:
		result.colors.append([color.r, color.g, color.b])
	for i in range(0, data.triangles.size(), 3):
		result.triangles.append([data.triangles[i], data.triangles[i + 1], data.triangles[i + 2]])
	if not view.is_empty():
		var camera := AnimalCameraPresets.frame(animal, view)
		if camera.is_empty():
			return {}
		result.camera = {
			"preset": view,
			"right": _vector(camera.transform.basis.x),
			"up": _vector(camera.transform.basis.y),
			"direction": _vector(camera.transform.basis.z),
			"target": _vector(camera.target),
			"size": camera.size
		}
		if camera.head:
			result.camera.clip_low = camera.clip_low
			result.camera.clip_high = camera.clip_high
	return result


static func _vector(v: Vector3) -> Array:
	return [v.x, -v.z, v.y]

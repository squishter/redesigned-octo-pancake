class_name AnimalCameraPresets
extends RefCounted
## Orthographic, geometry-framed silhouettes and front-facing head portraits.

const VIEWS := {
	"side_left": {"yaw": 80.0, "elevation": 8.0, "padding": 1.12},
	"side_right": {"yaw": -80.0, "elevation": 8.0, "padding": 1.12},
	"three_quarter_left": {"yaw": 45.0, "elevation": 8.0, "padding": 1.12},
	"three_quarter_right": {"yaw": -45.0, "elevation": 8.0, "padding": 1.12},
	"front": {"yaw": 0.0, "elevation": 5.0, "padding": 1.15},
	"head_front": {"yaw": 0.0, "elevation": 0.0, "padding": 1.13, "head": true},
	"head_front_close": {"yaw": 0.0, "elevation": 0.0, "padding": 1.04, "head": true},
	"head_front_high": {"yaw": 6.0, "elevation": 7.0, "padding": 1.12, "head": true}
}
const SIDE_ACTIONS := ["walk", "run", "gallop", "trot", "jump", "landing", "kick", "look_back"]


static func available(animal: AnimalPoseModel) -> PackedStringArray:
	var names := PackedStringArray()
	var portrait := _portrait_allowed(animal)
	for key: String in VIEWS:
		if key == "front" and animal.last_pose.get("preset", "rest") in SIDE_ACTIONS:
			continue
		if not VIEWS[key].get("head", false) or portrait:
			names.append(key)
	return names


static func frame(animal: AnimalPoseModel, preset: String, aspect := 1.0) -> Dictionary:
	if not VIEWS.has(preset) or not is_finite(aspect) or aspect <= 0:
		return {}
	if preset == "front" and animal.last_pose.get("preset", "rest") in SIDE_ACTIONS:
		return {}
	var view: Dictionary = VIEWS[preset]
	var head: bool = view.get("head", false)
	if head and not _portrait_allowed(animal):
		return {}
	var points: PackedVector3Array = (
		animal.head_vertices() if head else animal.snapshot(false).vertices
	)
	if points.is_empty():
		return {}
	var forward: Vector3 = animal.head_direction() if head else animal.forward_direction()
	var direction := forward.rotated(Vector3.UP, deg_to_rad(view.yaw))
	var right := direction.cross(Vector3.UP).normalized()
	if right.length() < 0.001:
		right = Vector3.RIGHT
	direction = direction.rotated(right, deg_to_rad(-view.elevation)).normalized()
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	var basis := Basis.looking_at(-direction, up)
	var inverse := basis.inverse()
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for point in points:
		var projected := inverse * point
		low = low.min(projected)
		high = high.max(projected)
	var center := basis * ((low + high) * 0.5)
	var size: float = maxf(high.y - low.y, (high.x - low.x) / aspect) * float(view.padding)
	var camera := Transform3D(
		basis, center + direction * maxf(animal._height * 4, high.z - low.z + 1)
	)
	var camera_depth: float = (inverse * camera.origin).z
	return {
		"preset": preset,
		"transform": camera,
		"size": maxf(size, 0.001),
		"aspect": aspect,
		"head": head,
		"target": center,
		"point_count": points.size(),
		"near": maxf(0.005, camera_depth - high.z - animal._height * 0.02) if head else 0.01,
		"far": camera_depth - low.z + animal._height * 0.03 if head else 100.0,
		"clip_low": low.z - animal._height * 0.03 if head else -INF,
		"clip_high": high.z + animal._height * 0.02 if head else INF
	}


static func apply(camera: Camera3D, animal: AnimalPoseModel, preset: String, aspect := 1.0) -> bool:
	var result := frame(animal, preset, aspect)
	if result.is_empty():
		return false
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.global_transform = animal.global_transform * result.transform
	camera.size = result.size * animal.global_basis.get_scale().y
	camera.near = result.near * animal.global_basis.get_scale().y
	camera.far = result.far * animal.global_basis.get_scale().y
	return true


static func _portrait_allowed(animal: AnimalPoseModel) -> bool:
	return (
		animal.source_info.locomotion in ["quadruped", "bird"]
		and animal.head_direction().dot(animal.forward_direction()) > 0.35
		and animal.head_vertices().size() >= 12
	)

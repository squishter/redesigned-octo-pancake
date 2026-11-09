class_name AnimalCoatSurface
extends RefCounted
## Immutable coordinates captured in the imported skin's neutral space. They
## travel with each vertex, including UV seams, detached parts and head crops.


static func capture(animal: AnimalPoseModel) -> Dictionary:
	var data := animal._sampler.sample()
	var points: PackedVector3Array = data.vertices
	var regions := PackedInt32Array()
	regions.resize(points.size())
	var groups := {1: [animal._profile.head], 6: animal._profile.tail, 7: animal._profile.ears}
	var legs := {}
	for leg: Dictionary in animal._legs:
		var region: int = 2 + ["front_left", "front_right", "hind_left", "hind_right"].find(leg.key)
		groups[region] = [leg.hip, leg.upper, leg.lower, leg.foot]
		legs[region] = leg
	for region: int in groups:
		var bones := PackedInt32Array()
		for bone in animal.skeleton.get_bone_count():
			var parent := bone
			while parent >= 0:
				if parent in groups[region]:
					bones.append(bone)
					break
				parent = animal.skeleton.get_bone_parent(parent)
		for index in animal._sampler.indices_for_bones(animal.skeleton, bones):
			regions[index] = region
	var forward := animal.forward_direction()
	var right: Vector3 = forward.cross(Vector3.UP)
	var body_low := INF
	var body_high := -INF
	for index in points.size():
		if regions[index] == 0:
			body_low = minf(body_low, points[index].dot(forward))
			body_high = maxf(body_high, points[index].dot(forward))
	var length := maxf(animal._height * 0.4, body_high - body_low)
	if not is_finite(length):
		length = animal._height
		body_low = 0.0
	var head_basis: Basis = (
		animal._bone(animal._profile.head).basis.orthonormalized()
		* animal._head_rest_basis.inverse()
	)
	var head_inverse := Basis(right, Vector3.UP, forward).inverse() * head_basis.inverse()
	var head_low := Vector3(INF, INF, INF)
	var head_high := Vector3(-INF, -INF, -INF)
	for index in points.size():
		if regions[index] == 1:
			var q := head_inverse * points[index]
			head_low = head_low.min(q)
			head_high = head_high.max(q)
	if not head_low.is_finite():
		head_low = Vector3.ZERO
		head_high = Vector3.ONE
	var head_extent := (head_high - head_low).max(Vector3.ONE * 0.001)
	var rest := PackedVector3Array()
	var coordinates := PackedVector3Array()
	var faces := PackedVector3Array()
	var protect := animal._sampler.protected_vertices()
	var kind := AnimalPoseCatalog.anatomy(animal.model_id)
	var feature_bones := PackedInt32Array()
	for bone in animal.skeleton.get_bone_count():
		var name_value := animal.skeleton.get_bone_name(bone).to_lower()
		for word in ["eye", "pupil", "tongue", "teeth", "tusk", "horn", "antler", "claw"]:
			if word in name_value:
				feature_bones.append(bone)
		if animal.source_info.rig == "gobkit" and "mouth" in name_value:
			feature_bones.append(bone)
	for index in animal._sampler.indices_for_bones(animal.skeleton, feature_bones):
		protect[index] = 1
	var hooves := (
		AnimalPoseCatalog.anatomy(animal.model_id)
		in ["equine", "bovine", "cervid", "camelid", "ovine", "porcine"]
	)
	for index in points.size():
		var point := points[index]
		var q := Vector3(point.dot(right), point.y, point.dot(forward) - body_low) / length
		var u := q.z
		var progress := 0.0
		if legs.has(regions[index]):
			var leg: Dictionary = legs[regions[index]]
			var a: Vector3 = animal._bone(leg.hip).origin
			var b: Vector3 = animal._bone(leg.foot).origin
			var axis := b - a
			progress = clampf((point - a).dot(axis) / maxf(0.00001, axis.length_squared()), 0, 1)
			u = (a.dot(forward) - body_low + progress * axis.length()) / length
		elif regions[index] == 6 and not animal._profile.tail.is_empty():
			var a: Vector3 = animal._bone(animal._profile.tail[0]).origin
			u = (a.dot(forward) - body_low + point.distance_to(a)) / length
		var face := (head_inverse * point - head_low) / head_extent
		face.x = face.x * 2 - 1
		var color: Color = data.colors[index]
		if regions[index] in [1, 7]:
			var dark := maxf(color.r, maxf(color.g, color.b)) < 0.20
			var nose := (
				face.z > 0.84
				and face.y < 0.72
				and absf(face.x) < 0.55
				and color.get_luminance() < 0.4
			)
			var eye_band := (
				face.y > 0.55 and face.y < 0.85 and absf(face.x) > 0.28 and face.z < 0.85
			)
			var pink := (
				color.r > color.g * 1.7 and color.r > color.b * 1.25 and color.b > color.g * 0.8
			)
			if nose or (dark and (eye_band or regions[index] == 7)) or pink:
				protect[index] = 1
		elif (
			legs.has(regions[index])
			and (
				(hooves and progress > 0.90) or (progress > 0.86 and color.get_luminance() < 0.045)
			)
		):
			protect[index] = 1
		if kind == "elephant" and color.get_luminance() > 0.45:
			protect[index] = 1
		rest.append(q)
		coordinates.append(Vector3(u, atan2(q.x, q.y) / TAU, progress))
		faces.append(face)
	return {
		"rest": rest,
		"coat_coordinates": coordinates,
		"face_coordinates": faces,
		"regions": regions,
		"protected": protect
	}

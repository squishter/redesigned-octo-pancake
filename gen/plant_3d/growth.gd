class_name PlantGrowth
extends RefCounted
## Native, deterministic plant assembly. Structural stems are independent of
## bloom load; every organ records its attachment to the same branch graph.

const STRIDE := 100000
const HANGING := ["bell", "fuchsia", "bleeding_heart"]


static func _rng(seed_value: int, part: int, stream: int) -> RandomNumberGenerator:
	var result := RandomNumberGenerator.new()
	# Versioned integer stream splitting, independent of Variant.hash().
	result.seed = (seed_value * 1664525 + part * 1013904223 + stream * 69069) & 0xffffffff
	return result


static func sample(path: PackedVector3Array, t: float) -> Dictionary:
	var f := clampf(t, 0., 1.) * (path.size() - 1)
	var index := mini(int(f), path.size() - 2)
	return {"point": path[index].lerp(path[index + 1], f - index),
		"tangent": (path[index + 1] - path[index]).normalized()}


static func _path(root: Vector3, axis: Vector3, length: float, radius: float,
		c: Dictionary, rng: RandomNumberGenerator, level: int) -> Dictionary:
	var segments := maxi(24, ceili(length * 40))
	var ds := length / segments
	var basis := PlantMeshSurface.frame(axis)
	var previous := axis.normalized()
	var points := PackedVector3Array([root])
	var max_turn := ds / maxf(.18, 14. * radius)
	var turns := maxi(1, roundi(c.bends * (2. if level == 0 else 1.4)))
	var knots := PackedFloat64Array([0.])
	var angles := PackedFloat64Array([0.])
	var planes := PackedFloat64Array([0.])
	for i in turns:
		knots.append(knots[-1] + rng.randf_range(.7, 1.3))
	var total := knots[-1]
	var sign_value := 1. if rng.randf() < .5 else -1.
	for i in turns:
		knots[i + 1] /= total
		angles.append(sign_value * (-1. if i % 2 else 1.) * rng.randf_range(c.bend_angle_min, c.bend_angle_max))
		planes.append(rng.randf_range(-.25, .25))
	for i in segments:
		var t := (i + .5) / segments
		var knot := 0
		while knot < turns - 1 and knots[knot + 1] < t:
			knot += 1
		var blend := smoothstep(knots[knot], knots[knot + 1], t)
		var theta := deg_to_rad(lerpf(angles[knot], angles[knot + 1], blend)) * float(c.curve_amount)
		var plane := lerpf(planes[knot], planes[knot + 1], blend)
		var desired := basis * Vector3(sin(theta) * cos(plane), cos(theta), sin(theta) * sin(plane))
		var angle := previous.angle_to(desired)
		if angle > max_turn:
			desired = previous.slerp(desired, max_turn / angle).normalized()
		points.append(points[-1] + (previous + desired).normalized() * ds)
		previous = desired
	var curvature := 0.
	var measured := 0.
	for i in range(1, points.size()):
		var delta := points[i] - points[i - 1]
		measured += delta.length()
		if i > 1:
			curvature = maxf(curvature, delta.angle_to(points[i - 1] - points[i - 2]) / ds)
	return {"points": points, "bend_angles": angles.slice(1), "bend_positions": knots.slice(1),
		"axis": axis, "length": measured, "max_curvature": curvature}


static func _positions(count: int, low: float, high: float, c: Dictionary,
		rng: RandomNumberGenerator) -> PackedFloat64Array:
	if count == 0:
		return PackedFloat64Array()
	var first := low + rng.randf_range(0., .035)
	var result := PackedFloat64Array([first])
	if count == 1:
		return result
	var gaps := PackedFloat64Array()
	for i in count - 1:
		gaps.append(rng.randf_range(c.branch_spacing_min, c.branch_spacing_max))
	if rng.randf() < c.cluster_chance:
		gaps[rng.randi_range(0, gaps.size() - 1)] = rng.randf_range(c.branch_spacing_min,
			c.branch_spacing_min + (c.branch_spacing_max - c.branch_spacing_min) * .1)
	var sum := 0.
	for gap in gaps:
		sum += gap
	var available := high - first
	for gap in gaps:
		if sum > available:
			gap = c.branch_spacing_min + (gap - c.branch_spacing_min) * (
				available - gaps.size() * c.branch_spacing_min) / (sum - gaps.size() * c.branch_spacing_min)
		result.append(result[-1] + gap)
	return result


static func _add(branches: Array, parent: int, at: float, axis: Vector3, length: float,
		radius: float, level: int, recipe: Dictionary, rotation: Basis) -> int:
	var root := Vector3.ZERO if parent < 0 else sample(branches[parent].points, at).point as Vector3
	var branch := _path(root, rotation * axis.normalized(), length, radius,
		recipe.controls, _rng(recipe.seed, branches.size(), 5317), level)
	branch.merge({"id": branches.size(), "parent": parent, "at": at, "level": level, "radius": radius})
	branches.append(branch)
	return branches.size() - 1


static func skeleton(recipe: Dictionary) -> Array:
	var c: Dictionary = recipe.controls
	var p: Dictionary = recipe.pose_controls
	var rng := _rng(recipe.seed, 0, 13)
	var rotation := Basis(Vector3.BACK, -p.bend_x) * Basis(Vector3.RIGHT, p.bend_z)
	var phase := rng.randf_range(-.3, .3)
	var branches := []
	_add(branches, -1, 0., Vector3.UP, c.length, c.radius, 0, recipe, rotation)
	var positions := _positions(c.primary_count, .16, .80, c, rng)
	for i in positions.size():
		var azimuth := phase + i * 2.3999632297 + rng.randf_range(-.18, .18)
		var axis := Vector3(cos(azimuth) * c.spread * p.spread, .85, sin(azimuth) * c.spread * p.spread)
		var length: float = c.length * (.61 - .18 * i / maxi(1, c.primary_count - 1))
		var parent := _add(branches, 0, positions[i], axis, length, c.radius * .68, 1, recipe, rotation)
		var secondary := _positions(c.secondary_count, .32, .80, c, rng)
		for j in secondary.size():
			var angle: float = azimuth + (-.9 if j % 2 else .9) * (1. + .2 * floor(j / 2.))
			axis = Vector3(cos(angle) * c.spread * p.spread, .95, sin(angle) * c.spread * p.spread)
			_add(branches, parent, secondary[j], axis, length * .54, maxf(.008, c.radius * .44), 2, recipe, rotation)
	return branches


static func _socket(branch: Dictionary, t: float, end: Vector3, kind: String) -> Dictionary:
	var at := sample(branch.points, t)
	return {"kind": kind, "branch": branch.id, "at": t, "root": end,
		"attachment": at.point, "tangent": at.tangent}


static func flower_sockets(branches: Array, wanted: int, flowers: int) -> Array:
	var candidates := []
	for branch: Dictionary in branches:
		var tip := sample(branch.points, 1.)
		candidates.append(_socket(branch, 1., tip.point + tip.tangent * .12, "flower"))
		var stations := 10 if branch.level == 0 else 3
		for i in stations:
			var t := lerpf(.30, .91, float(i) / (stations - 1))
			var at := sample(branch.points, t)
			for side in (3 if branch.level == 0 else 1):
				var angle: float = branch.id * 2.4 + i * 2.4 + side * TAU / 3.
				var radial := Vector3(cos(angle), .32, sin(angle)).normalized()
				var end: Vector3 = at.point + radial * (.20 + .035 * (i % 3)) + at.tangent * .06
				candidates.append(_socket(branch, t, end, "flower"))
	var selected := [candidates.pop_front()]
	while selected.size() < wanted:
		var best := -INF
		var index := -1
		for i in candidates.size():
			var nearest := INF
			for chosen: Dictionary in selected:
				nearest = minf(nearest, candidates[i].root.distance_to(chosen.root))
			var score: float = nearest + .04 * candidates[i].at
			if score > best:
				best = score
				index = i
		selected.append(candidates.pop_at(index))
	for i in selected.size():
		selected[i].kind = "flower" if i < flowers else "bud"
	return selected


static func assemble(recipe: Dictionary) -> Dictionary:
	var c: Dictionary = recipe.controls
	var p: Dictionary = recipe.pose_controls
	var leaf := PlantComponentData.load_component("leaves", recipe.leaf, recipe.component_variant)
	var flower := PlantComponentData.load_component("flowers", recipe.flower, recipe.component_variant)
	if leaf.is_empty() or flower.is_empty():
		return {}
	var buds := []
	if c.bud_count > 0:
		for family in PlantComponentData.families("buds"):
			var bud := PlantComponentData.load_component("buds", family, recipe.component_variant)
			if bud.is_empty():
				return {}
			buds.append(bud)
	var branches := skeleton(recipe)
	var mesh := PlantMeshSurface.new()
	for branch: Dictionary in branches:
		mesh.tube(branch.points, branch.radius, 10 + branch.id)
	var part := STRIDE
	for branch: Dictionary in branches:
		var count := roundi((4 if branch.level == 0 else 2 if branch.level == 1 else 1) * c.leaf_density)
		for i in count:
			var t := lerpf(.24, .77, float(i) / maxi(1, count - 1))
			var at := sample(branch.points, t)
			var angle: float = 2.4 * (i + branch.id)
			var axis: Vector3 = (Vector3(cos(angle), p.leaf_pitch, sin(angle)) + at.tangent * .15).normalized()
			var basis := PlantMeshSurface.frame(axis, at.tangent)
			var scale_value: float = c.leaf_scale * (1. - branch.level * .16)
			var rng := _rng(recipe.seed, part, 117)
			var changes := {"width": rng.randf_range(.95, 1.05), "length": rng.randf_range(.95, 1.05),
				"curl": p.leaf_curl - .1, "twist": rng.randf_range(-.08, .08)}
			mesh.component(leaf, Transform3D(basis, at.point), scale_value, part, 1., changes)
			var site := _socket(branch, t, at.point, "leaf")
			site.merge({"axis": axis, "frame": basis, "scale": scale_value, "part": part, "changes": changes})
			mesh.attachments.append(site)
			part += STRIDE
	var leaf_count := mesh.attachments.size()
	var sockets := flower_sockets(branches, c.flower_count + c.bud_count, c.flower_count)
	var bloom_low := 1.
	var bloom_high := 0.
	for i in sockets.size():
		var site: Dictionary = sockets[i]
		var mid: Vector3 = (site.attachment + site.root) * .5 + Vector3(0., .025, 0.)
		mesh.tube(PackedVector3Array([site.attachment, mid, site.root]), .009, part)
		var support_axis: Vector3 = (site.root - mid).normalized()
		var support := PlantMeshSurface.frame(support_axis, PlantMeshSurface.frame(site.tangent).z)
		var rng := _rng(recipe.seed, part, 769)
		var theta := deg_to_rad(rng.randf_range(0., c.flower_angle_jitter))
		var azimuth := rng.randf_range(0., TAU)
		var axis := (support_axis * cos(theta) + sin(theta) * (support.x * cos(azimuth) + support.z * sin(azimuth))).normalized()
		var is_bud: bool = site.kind == "bud"
		if not is_bud and recipe.flower in HANGING:
			axis = -axis
		var basis := PlantMeshSurface.frame(axis, support.z)
		var roll := deg_to_rad(rng.randf_range(-1., 1.) * c.flower_angle_jitter * 1.65)
		basis *= Basis(Vector3.UP, roll)
		var scale_value: float = c.flower_scale * (.55 if is_bud else 1.) * rng.randf_range(
			1. - c.flower_scale_jitter, 1. + c.flower_scale_jitter)
		var data: Dictionary = buds[i % buds.size()] if is_bud else flower
		var changes := {}
		for key in ["width", "length", "depth"]:
			changes[key] = rng.randf_range(1. - c.flower_shape_jitter, 1. + c.flower_shape_jitter)
		changes.width *= p.opening
		changes.depth *= p.opening
		var stage := 1.
		if data.bloom_profile != "fixed":
			stage = _rng(recipe.seed, part, 2759).randf_range(c.bloom_min, c.bloom_max)
		mesh.component(data, Transform3D(basis, site.root), scale_value, part + 1, stage, changes)
		site.merge({"axis": axis, "frame": basis, "scale": scale_value, "part": part + 1,
			"support_axis": support_axis, "angle_nudge": rad_to_deg(theta), "roll_nudge": rad_to_deg(roll),
			"changes": changes, "bloom": stage, "bloom_profile": data.bloom_profile})
		mesh.attachments.append(site)
		if not is_bud:
			bloom_low = minf(bloom_low, stage)
			bloom_high = maxf(bloom_high, stage)
		part += STRIDE
	var total_length := 0.
	var curvature := 0.
	for branch: Dictionary in branches:
		total_length += branch.length
		curvature = maxf(curvature, branch.max_curvature)
	return {"data": mesh.snapshot(), "branches": branches, "stats": {
		"structural_branches": branches.size() - 1, "flower_count": c.flower_count,
		"bud_count": c.bud_count, "leaf_count": leaf_count, "total_stem_length": total_length,
		"main_length": branches[0].length, "max_curvature": curvature,
		"bloom_min": bloom_low, "bloom_max": bloom_high}}

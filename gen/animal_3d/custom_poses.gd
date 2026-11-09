class_name AnimalCustomPoses
extends RefCounted
## Large pose recipes and an explicit body/foot-target solver. Uses the posing
## package's rig-space helpers; small seeded variations are applied afterwards.

const CANINES := [
	"ultimate_fox",
	"ultimate_wolf",
	"ultimate_husky",
	"ultimate_shibainu",
	"farm_pug",
	"vol2_dog",
	"daydaze_labrador",
	"shepherd_shepherd"
]
const FELINES := ["vol2_cat", "toon_cat_toon_cat_free", "tuxedo_cat_tuxedo_cat", "daydaze_lion"]
const EQUINES := [
	"ultimate_horse", "ultimate_horse_white", "farm_horse", "farm_zebra", "ultimate_donkey"
]


static func available(animal) -> PackedStringArray:
	var names := PackedStringArray()
	if animal._legs.size() != 4:
		return names
	if animal.model_id in CANINES:
		if animal.model_id != "vol2_dog":
			names.append("sit")
		names.append_array(["lie_down", "play_bow", "stretch", "look_back"])
	if animal.model_id in FELINES:
		names.append_array(["lie_down", "crouch", "stretch", "look_back"])
		if animal.model_id in ["daydaze_lion", "tuxedo_cat_tuxedo_cat"]:
			names.erase("lie_down")
	if animal.model_id in EQUINES:
		names.append("trot")
	return names


static func apply(animal, kind: String, phase: float, definition: Dictionary = {}) -> Dictionary:
	match kind:
		"sit":
			return _sit(animal)
		"trot":
			return _trot(animal, phase)
		"lie_down", "play_bow", "stretch", "crouch":
			return _low_pose(animal, kind)
		"look_back":
			var result := solve(animal, {"body": {"neck_yaw": 45.0, "head_yaw": 45.0}})
			if not result.is_empty():
				result.kind = "look_back"
			return result
		"targets":
			return solve(animal, definition)
	return {}


static func solve(animal, spec: Dictionary) -> Dictionary:
	if animal._legs.size() != 4:
		return {}
	if not spec.get("body", {}) is Dictionary or not spec.get("feet", {}) is Dictionary:
		return {}
	var body: Dictionary = spec.get("body", {})
	var targets: Dictionary = spec.get("feet", {})
	var valid_keys := PackedStringArray()
	for row: Dictionary in animal._capture_legs():
		valid_keys.append(row.leg.key)
	for key in targets:
		if key not in valid_keys or not targets[key] is Dictionary:
			return {}
		var point: Variant = targets[key].get("at")
		if not point is Vector3 or not point.is_finite():
			return {}
		if not targets[key].get("contact", true) is bool:
			return {}
		if (
			targets[key].has("pole")
			and (not targets[key].pole is Vector3 or not targets[key].pole.is_finite())
		):
			return {}
	for key in [
		"pitch",
		"roll",
		"yaw",
		"neck_pitch",
		"head_pitch",
		"tail_pitch",
		"hips_pitch",
		"shoulders_pitch",
		"neck_yaw",
		"head_yaw"
	]:
		var value: Variant = body.get(key, 0.0)
		if (
			not (value is float or value is int)
			or not is_finite(float(value))
			or absf(float(value)) > 85
		):
			return {}
	var pivot: Variant = body.get("pivot", animal._bone(animal._profile.body).origin)
	var translation: Variant = body.get("translation", Vector3.ZERO)
	if (
		not pivot is Vector3
		or not translation is Vector3
		or not pivot.is_finite()
		or not translation.is_finite()
	):
		return {}
	var original: Array[Dictionary] = animal._capture_state()
	var rows: Array[Dictionary] = animal._capture_legs()
	var origin: Vector3 = animal._bone(animal._profile.body).origin
	var rotation := Quaternion(animal._right, deg_to_rad(float(body.get("pitch", 0))))
	rotation = Quaternion(animal._forward, deg_to_rad(float(body.get("roll", 0)))) * rotation
	rotation = Quaternion(Vector3.UP, deg_to_rad(float(body.get("yaw", 0)))) * rotation
	animal._apply_rotation(animal._profile.body, rotation)
	animal._set_position(animal._profile.body, pivot + rotation * (origin - pivot) + translation)
	for row in rows:
		if not row.leg.front and row.leg.hip != row.leg.upper:
			animal._rotate(row.leg.hip, animal._right, float(body.get("hips_pitch", 0)))
		if row.leg.front and row.leg.shoulder != row.leg.upper:
			animal._rotate(row.leg.shoulder, animal._right, float(body.get("shoulders_pitch", 0)))
	animal._chain(animal._profile.neck, animal._right, float(body.get("neck_pitch", 0)))
	animal._chain(animal._profile.neck, Vector3.UP, float(body.get("neck_yaw", 0)))
	animal._rotate(animal._profile.head, animal._right, float(body.get("head_pitch", 0)))
	animal._rotate(animal._profile.head, Vector3.UP, float(body.get("head_yaw", 0)))
	if not animal._profile.tail.is_empty():
		animal._rotate(animal._profile.tail[0], animal._right, float(body.get("tail_pitch", 0)))
	var result := {"kind": "targets", "max_error": 0.0, "feet": [], "airborne": true}
	for row in rows:
		var entry: Dictionary = targets.get(row.leg.key, {"at": row.c, "contact": true})
		var target: Vector3 = entry.at
		var solving := row.duplicate()
		if entry.has("pole"):
			solving.a = animal._bone(row.leg.upper).origin
			solving.b = entry.pole
		animal._solve_leg(solving, target)
		var tip: Vector3 = (
			animal._bone(row.leg.foot).origin
			if row.leg.direct
			else animal._bone(row.leg.lower) * row.tip_offset
		)
		var error := tip.distance_to(target)
		result.max_error = maxf(result.max_error, error)
		var contact: bool = entry.get("contact", true)
		result.airborne = result.airborne and not contact
		result.feet.append(
			{"key": row.leg.key, "position": tip, "target": target, "contact": contact}
		)
	if result.max_error > animal._height * 0.002:
		animal._restore_bones(original)
		return {}
	animal._flush()
	return result


static func _sit(animal) -> Dictionary:
	var original: Array[Dictionary] = animal._capture_state()
	var rows: Array[Dictionary] = animal._capture_legs()
	var hips := Vector3.ZERO
	var reach := 0.0
	var floor_height := 0.0
	for row in rows:
		if row.leg.front:
			continue
		hips += animal._bone(row.leg.hip).origin * 0.5
		reach += (row.a.distance_to(row.b) + row.b.distance_to(row.c)) * 0.5
		floor_height += row.c.y * 0.5
	for pitch in [55.0, 50.0, 45.0, 40.0, 35.0, 30.0, 25.0]:
		for hip_fraction in [0.60, 0.55, 0.50, 0.44, 0.38, 0.32, 0.25]:
			animal._restore_bones(original)
			var hip_height: float = floor_height + reach * hip_fraction
			var shift := Vector3(0, hip_height - hips.y, 0)
			var turn := Quaternion(animal._right, deg_to_rad(pitch))
			var feet := {}
			for row in rows:
				var target: Vector3 = row.c
				if row.leg.front:
					var root: Vector3 = hips + turn * (row.a - hips) + shift
					if row.leg.shoulder != row.leg.upper:
						var shoulder: Vector3 = animal._bone(row.leg.shoulder).origin
						root = hips + turn * (shoulder - hips) + shift + row.a - shoulder
					target = root + animal._forward * (row.a.distance_to(row.c) * 0.05)
					target.y = row.c.y
				else:
					var hip: Vector3 = animal._bone(row.leg.hip).origin
					var length: float = row.a.distance_to(row.b) + row.b.distance_to(row.c)
					target = (
						hip
						+ (
							animal._forward
							* length
							* (0.04 if row.leg.hip != row.leg.upper else 0.38)
						)
					)
					target.y = row.c.y
				feet[row.leg.key] = {"at": target, "contact": true}
			var spec := {
				"body":
				{
					"pivot": hips,
					"translation": shift,
					"pitch": pitch,
					"neck_pitch": -pitch * 0.8,
					"head_pitch": -pitch * 0.2,
					"tail_pitch": -pitch - 20,
					"hips_pitch": 55.0 - pitch,
					"shoulders_pitch": -pitch
				},
				"feet": feet
			}
			var result := solve(animal, spec)
			if not result.is_empty() and _clear_floor(animal):
				result.kind = "sit"
				result.pitch = pitch
				result.spec = spec
				return result
	animal._restore_bones(original)
	return {}


static func _low_pose(animal, kind: String) -> Dictionary:
	var original: Array[Dictionary] = animal._capture_state()
	var rows: Array[Dictionary] = animal._capture_legs()
	var pivot := Vector3.ZERO
	for row in rows:
		if not row.leg.front:
			pivot += animal._bone(row.leg.hip).origin * 0.5
	var pitch := -20.0 if kind == "play_bow" else -12.0 if kind == "stretch" else 0.0
	var drop: float = (
		animal._height * (0.27 if kind == "lie_down" else 0.12 if kind == "crouch" else 0.0)
	)
	for strength in [1.0, 0.85, 0.7, 0.55]:
		animal._restore_bones(original)
		var shift := Vector3(0, -drop * strength, 0)
		var turn := Quaternion(animal._right, deg_to_rad(pitch * strength))
		var feet := {}
		var valid := true
		for row in rows:
			var target: Vector3 = row.c
			var length: float = row.a.distance_to(row.b) + row.b.distance_to(row.c)
			if row.leg.front:
				var root: Vector3 = pivot + turn * (row.a - pivot) + shift
				if kind == "lie_down" and root.y <= row.c.y + animal._height * 0.045:
					valid = false
					break
				var extension := (
					0.62
					if kind in ["lie_down", "stretch"]
					else 0.25 if kind == "play_bow" else 0.05
				)
				target = root + animal._forward * length * extension * strength
				if kind == "lie_down":
					# Put the elbow just above the floor, then extend the forearm.
					# A generic mid-range reach can push a deep-folded elbow below it.
					var first: float = row.a.distance_to(row.b)
					var second: float = row.b.distance_to(row.c)
					var elbow_y: float = maxf(
						row.c.y + animal._height * 0.02, root.y - first * 0.98
					)
					var upper_back := sqrt(maxf(0, first * first - pow(root.y - elbow_y, 2)))
					var fore_forward := sqrt(maxf(0, second * second - pow(elbow_y - row.c.y, 2)))
					target = root + animal._forward * (fore_forward - upper_back)
					var elbow: Vector3 = root - animal._forward * upper_back
					elbow.y = elbow_y
					feet[row.leg.key] = {"at": target, "contact": true, "pole": elbow}
				target.y = row.c.y
			elif kind == "lie_down" and row.leg.hip != row.leg.upper:
				target = animal._bone(row.leg.hip).origin
				target.y = row.c.y
			if feet.has(row.leg.key):
				feet[row.leg.key].at.y = row.c.y
			else:
				feet[row.leg.key] = {"at": target, "contact": true}
		if not valid:
			continue
		var spec := {
			"body":
			{
				"pivot": pivot,
				"translation": shift,
				"pitch": pitch * strength,
				"neck_pitch": -pitch * strength,
				"hips_pitch":
				(65 if kind == "lie_down" else 30 if kind == "crouch" else 0) * strength,
				"tail_pitch": -pitch * strength - (20.0 if kind == "lie_down" else 0.0)
			},
			"feet": feet
		}
		var result := solve(animal, spec)
		if not result.is_empty() and _clear_floor(animal):
			result.kind = kind
			result.strength = strength
			return result
	animal._restore_bones(original)
	return {}


static func _clear_floor(animal) -> bool:
	var minimum := INF
	for point: Vector3 in animal.snapshot(false).vertices:
		minimum = minf(minimum, point.y)
	return minimum >= -animal._height * 0.02


static func _trot(animal, phase: float) -> Dictionary:
	var rows: Array[Dictionary] = animal._capture_legs()
	var feet := {}
	var bob: float = animal._height * (0.025 + 0.005 * cos(phase * TAU * 2))
	for row in rows:
		var diagonal: bool = row.leg.key in ["front_left", "hind_right"]
		var cycle := fposmod(phase + (0.0 if diagonal else 0.5), 1.0)
		var contact := cycle < 0.5
		var progress: float = cycle * 2 if contact else (cycle - 0.5) * 2
		var stride: float = animal._height * 0.15
		var forward_offset := (
			lerpf(stride, -stride, progress) if contact else lerpf(-stride, stride, progress)
		)
		var target: Vector3 = row.c + animal._forward * forward_offset
		if not contact:
			target.y += sin(progress * PI) * animal._height * 0.11
		feet[row.leg.key] = {"at": target, "contact": contact}
		# A straight neutral leg cannot step horizontally at its full standing
		# height. Lower the body enough for every target to remain reachable,
		# using this rig's actual lengths rather than a species-wide guess.
		var length: float = row.a.distance_to(row.b) + row.b.distance_to(row.c)
		var horizontal: float = Vector2(row.a.x - target.x, row.a.z - target.z).length_squared()
		var vertical := sqrt(maxf(0, length * length * 0.99 - horizontal))
		bob = maxf(bob, row.a.y - target.y - vertical + animal._height * 0.005)
	var result := solve(animal, {"body": {"translation": Vector3(0, -bob, 0)}, "feet": feet})
	if not result.is_empty():
		result.kind = "trot"
	return result

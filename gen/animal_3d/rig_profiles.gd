class_name AnimalRigProfiles
extends RefCounted
## Semantic mappings for the sourced rigs. No guessed breed retargeting.


static func get_profile(kind: String) -> Dictionary:
	var p := {
		"body": "",
		"spine": [],
		"neck": [],
		"head": "",
		"tail": [],
		"ears": [],
		"trunk": [],
		"legs": [],
		"look_limit": 16.0
	}
	match kind:
		"quaternius", "labrador":
			p.merge(
				{
					"body": "Body",
					"spine": ["Torso", "Torso2", "Torso3"],
					"neck": ["Neck1", "Neck2", "Neck3"],
					"head": "Head",
					"tail": _numbered("Tail", 1, 8),
					"ears": ["Ear1.L", "Ear1.R"]
				},
				true
			)
			for side in ["L", "R"]:
				p.legs.append(
					_leg(
						"FrontUpperLeg." + side, "FrontLowerLeg." + side, "IKFrontLeg." + side, true
					)
				)
				p.legs.append(
					_leg("BackUpperLeg." + side, "BackLowerLeg." + side, "IKBackLeg." + side, false)
				)
		"farm":
			p.merge(
				{
					"body": "Body",
					"spine": ["Torso", "Shoulders"],
					"neck": ["Neck"],
					"head": "Head",
					"tail": _numbered("Tail", 1, 4)
				},
				true
			)
			for side in ["L", "R"]:
				p.legs.append(
					_leg("FrontUpLeg." + side, "FrontLowLeg." + side, "FrontFoot." + side, true)
				)
				p.legs.append(
					_leg("BackUpLeg." + side, "BackLowLeg." + side, "BackFoot." + side, false)
				)
		"legacy":
			p.merge(
				{
					"body": "Bone",
					"spine": ["Bone.001"],
					"neck": ["Bone.002"],
					"head": "Bone.003",
					"tail": ["Bone.004", "Bone.005", "Bone.006", "Bone.007"]
				},
				true
			)
			for start in [14, 17, 8, 11]:
				p.legs.append(
					_leg(
						"Bone.%03d" % start,
						"Bone.%03d" % (start + 1),
						"Bone.%03d" % (start + 2),
						start >= 14
					)
				)
		"gobkit":
			p.merge(
				{
					"body": "Hips",
					"spine": ["Spine"],
					"head": "Head",
					"tail": ["Tail"],
					"ears": ["LeftEar", "RightEar"],
					"look_limit": 10.0
				},
				true
			)
		"toon_cat":
			p.merge(
				{
					"body": "torso_02",
					"spine": ["spine.01_012", "spine.02_013"],
					"neck": ["neck_017"],
					"head": "head_018",
					"ears": ["ear.L_019", "ear.R_020"],
					"tail": ["tail_07", "tail.01_08", "tail.02_09", "tail.03_010"]
				},
				true
			)
			p.legs = [
				_leg("leg.upper.F.L_014", "leg.lower.FL_015", "foot.F.L_016", true),
				_leg("leg.upper.F.R_024", "leg.lower.F.R_00", "foot.F.R_025", true),
				_leg("leg.upper.B.L_04", "leg.lower.B.L_05", "foot.B.L_06", false),
				_leg("leg.upper.B.R_027", "leg.lower.B.R_028", "foot.B.R_029", false)
			]
		"tuxedo_cat":
			var suffix := "_metarig.004"
			p.merge(
				{
					"body": "Root" + suffix,
					"spine": ["spine.006" + suffix, "spine.007" + suffix, "spine.008" + suffix],
					"neck": ["spine.009" + suffix, "spine.010" + suffix],
					"head": "Head" + suffix,
					"ears": ["Ear.L" + suffix, "Ear.R" + suffix],
					"tail":
					["TailBase" + suffix, "Tail2" + suffix, "Tail3" + suffix, "TailTip" + suffix]
				},
				true
			)
			for side in ["L", "R"]:
				p.legs.append(
					_leg(
						"front_thigh." + side + suffix,
						"front_shin." + side + suffix,
						"front_foot." + side + suffix,
						true
					)
				)
				p.legs.append(
					_leg(
						"thigh." + side + suffix,
						"shin." + side + suffix,
						"foot." + side + suffix,
						false
					)
				)
		"elephant":
			p.merge(
				{
					"body": "spine1_hiResSpine1_01",
					"head": "head1_head_014",
					"neck": ["head1_neck_013"],
					"spine":
					[
						"spine1_hiResSpine2_02",
						"spine1_hiResSpine3_03",
						"spine1_hiResSpine4_04",
						"spine1_hiResSpine5_05"
					],
					"tail":
					[
						"tail1_Joint1_040",
						"tail1_Joint2_041",
						"tail1_Joint3_042",
						"tail1_Joint4_043"
					],
					"ears": ["LeftEar01_015", "RrightEar01_018"],
					"look_limit": 9.0
				},
				true
			)
			for i in range(1, 10):
				p.trunk.append("proboscis%02d_0%d" % [i, 21 + i])
			p.legs = [
				_leg(
					"leftLeg1_LoResUpperLeg_06",
					"leftLeg1_LoResLowerLeg_00",
					"leftLeg1_LoResFoot_07",
					true
				),
				_leg(
					"rightLeg1_LoResUpperLeg_09",
					"rightLeg1_LoResLowerLeg_010",
					"rightLeg1_LoResFoot_011",
					true
				),
				_leg(
					"leftLeg2_LoResUpperLeg_032",
					"leftLeg2_LoResLowerLeg_033",
					"leftLeg2_LoResFoot_034",
					false
				),
				_leg(
					"rightLeg2_LoResUpperLeg_036",
					"rightLeg2_LoResLowerLeg_037",
					"rightLeg2_LoResFoot_038",
					false
				)
			]
		"lion":
			p.merge(
				{
					"body": "Wolf_ROOTSHJnt_41",
					"head": "Wolf_Neck_TopSHJnt_17",
					"neck": ["Wolf_Neck_01SHJnt_19", "Wolf_Neck_02SHJnt_18"],
					"spine":
					[
						"Wolf_Spine_01SHJnt_24",
						"Wolf_Spine_02SHJnt_23",
						"Wolf_Spine_03SHJnt_22",
						"Wolf_Spine_04SHJnt_21"
					],
					"tail":
					[
						"Wolf_Tail_01_02SHJnt_40",
						"Wolf_Tail_01_03SHJnt_39",
						"Wolf_Tail_01_04SHJnt_38",
						"Wolf_Tail_01_05SHJnt_37"
					],
					"ears": ["Wolf_l_Ear_01_01SHJnt_14", "Wolf_r_Ear_01_01SHJnt_16"]
				},
				true
			)
			p.legs = [
				_leg(
					"Wolf_l_FrontLeg_HipSHJnt_4",
					"Wolf_l_FrontLeg_KneeSHJnt_3",
					"Wolf_l_FrontLeg_AnkleSHJnt_2",
					true
				),
				_leg(
					"Wolf_r_FrontLeg_HipSHJnt_10",
					"Wolf_r_FrontLeg_KneeSHJnt_9",
					"Wolf_r_FrontLeg_AnkleSHJnt_8",
					true
				),
				_leg(
					"Wolf_l_HindLeg_Knee1SHJnt_29",
					"Wolf_l_HindLeg_Knee2SHJnt_28",
					"Wolf_l_HindLeg_AnkleSHJnt_27",
					false
				),
				_leg(
					"Wolf_r_HindLeg_Knee1SHJnt_35",
					"Wolf_r_HindLeg_Knee2SHJnt_34",
					"Wolf_r_HindLeg_AnkleSHJnt_33",
					false
				)
			]
		_:
			return {}
	return p


static func _numbered(prefix: String, first: int, last: int) -> Array:
	var names := []
	for i in range(first, last + 1):
		names.append(prefix + str(i))
	return names


static func _leg(upper: String, lower: String, foot: String, front: bool) -> Dictionary:
	return {"upper": upper, "lower": lower, "foot": foot, "front": front}

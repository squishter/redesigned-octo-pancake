class_name AnimalPoseCatalog
extends RefCounted
## Pose names describe the animal and the actual source action, not merely
## whatever happens to share a rig. Death/hit-reaction clips are not offered.


static func anatomy(id: String) -> String:
	if id in AnimalCustomPoses.CANINES or id == "gobkit_corgi":
		return "canine"
	if id in AnimalCustomPoses.FELINES:
		return "feline"
	if id in AnimalCustomPoses.EQUINES:
		return "equine"
	if id in ["ultimate_cow", "ultimate_bull", "farm_cow"]:
		return "bovine"
	if id in ["ultimate_deer", "ultimate_stag"]:
		return "cervid"
	if id in ["ultimate_alpaca", "farm_llama"]:
		return "camelid"
	if id == "farm_sheep":
		return "ovine"
	if id == "farm_pig":
		return "porcine"
	if id == "daydaze_elephant":
		return "elephant"
	if id == "gobkit_bat":
		return "bat"
	if id in ["gobkit_anglerfish", "gobkit_shark"]:
		return "fish"
	if id == "gobkit_jellyfish":
		return "jellyfish"
	return "other"


static func build(animal, player: AnimationPlayer) -> Dictionary:
	var poses := {
		"rest": {"clip": "", "start": 0.0, "end": 0.0, "origin": "rest", "grounding": "surface"}
	}
	var kind := anatomy(animal.model_id)
	if player != null:
		var clips := player.get_animation_list()
		clips.sort()
		for clip in clips:
			var leaf := clip.get_slice("|", clip.get_slice_count("|") - 1).to_lower()
			var preset := ""
			if leaf in ["idle", "idlenorm"]:
				preset = "idle"
			elif leaf in ["idle_2", "idletailswoosh"]:
				preset = "alert"
			elif leaf in ["walk", "walking", "walkcycle", "walkslow"]:
				preset = "walk"
			elif leaf in ["eating", "eat", "graze"]:
				preset = (
					"eat"
					if kind in ["canine", "feline", "elephant"] and leaf != "graze"
					else "graze"
				)
			elif leaf in ["idle_headlow", "idle_2_headlow"]:
				preset = "head_low"
			elif leaf == "idlesit":
				preset = "sit"
			elif leaf in ["gallop", "run"] and animal.source_info.locomotion == "quadruped":
				preset = "gallop" if kind == "equine" and leaf == "gallop" else "run"
			elif (
				leaf in ["jump", "gallop_jump", "run_jump"]
				and animal.source_info.locomotion == "quadruped"
			):
				preset = "jump"
			elif leaf in ["jump_toidle"]:
				preset = "landing"
			elif leaf == "attack_kick" and kind in ["equine", "bovine", "cervid", "camelid"]:
				preset = "kick"
			elif leaf == "attack_headbutt" and kind in ["bovine", "cervid"]:
				preset = "headbutt"
			if preset.is_empty() or poses.has(preset):
				continue
			var action := preset in ["walk", "run", "gallop", "jump", "landing", "kick"]
			poses[preset] = {
				"clip": clip,
				"start": 0.0,
				"end": player.get_animation(clip).length,
				"origin": "authored",
				"grounding": "authored" if action else "surface"
			}
		if animal.source_info.rig == "gobkit":
			for clip in clips:
				if clip == "RESET" or player.get_animation(clip).length < 119.0 / 24:
					continue
				poses.idle = {
					"clip": clip,
					"start": 0.0,
					"end": 29.0 / 24,
					"origin": "authored",
					"grounding": "surface"
				}
				var motion := (
					"fly"
					if kind == "bat"
					else "swim" if kind == "fish" else "drift" if kind == "jellyfish" else "walk"
				)
				poses[motion] = {
					"clip": clip,
					"start": 90.0 / 24,
					"end": 119.0 / 24,
					"origin": "authored",
					"grounding": "authored"
				}
				break
		elif animal.source_info.rig == "toon_cat":
			for clip in clips:
				if clip != "RESET":
					poses.source = {
						"clip": clip,
						"start": 0.0,
						"end": player.get_animation(clip).length,
						"origin": "authored",
						"grounding": "authored"
					}
					break
	for custom: String in AnimalCustomPoses.available(animal):
		if not poses.has(custom):
			poses[custom] = {
				"clip": "",
				"start": 0.0,
				"end": 0.0,
				"custom": custom,
				"origin": "procedural",
				"grounding": "contacts"
			}
	if kind == "elephant" and poses.has("idle"):
		# This source's bind pose has a folded-back head. Use its authored
		# neutral frame for a meaningful standing preset and head portraits.
		var time: float = poses.idle.end * 0.25
		poses.rest = {
			"clip": poses.idle.clip,
			"start": time,
			"end": time,
			"origin": "authored",
			"grounding": "surface"
		}
	return poses

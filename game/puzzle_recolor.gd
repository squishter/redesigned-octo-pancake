class_name PuzzleRecolor
extends RefCounted
## Recolors a saved layout without rebuilding it or modifying the original.
## Includes photo puzzles: their original source image is not needed.


static func make(picture: Dictionary, request: Dictionary) -> Dictionary:
	var gems: Array = request.get("theme_gems", GemCatalog.THEMES.get(request.get("theme", ""), {}).get("gems", []))
	if picture.is_empty() or gems.is_empty():
		return {}
	var out := picture.duplicate(true)
	if out.has("kit_grid"):
		var palette: Array = out["kit_grid"]["palette"]
		for i in palette.size():
			palette[i]["gem"] = gems[i % gems.size()]
			palette[i]["color"] = GemCatalog.color_of(palette[i]["gem"])
		out["slots"] = PuzzleMaker.kit_slots(out)
	else:
		_recolor_regions(out, gems)
	out["gem_kinds"] = GemVariety.kinds(out["slots"])
	out["gem_types"] = out["gem_kinds"].size()
	out["puzzle"] = request.duplicate(true)
	if out.get("source", {}).has("theme"):
		out["source"]["theme"] = request.get("theme", "")
	return out


static func _recolor_regions(picture: Dictionary, gems: Array) -> void:
	var groups := {}
	var region_groups := {}
	for region: Dictionary in picture.get("regions", []):
		var group: int = int(region.get("group", region["id"]))
		if not groups.has(group):
			groups[group] = groups.size()
		region_groups[region["id"]] = group
		for tone in 3:
			var gem: String = gems[(int(groups[group]) + tone) % gems.size()]
			region[["gem_color_id", "accent_gem", "feature_gem"][tone]] = gem
			region[["color", "accent_color", "feature_color"][tone]] = GemCatalog.color_of(gem)
	for slot: Dictionary in picture["slots"]:
		var group: int = int(region_groups.get(slot["region"], slot["region"]))
		if not groups.has(group):
			groups[group] = groups.size()
		var gem: String = gems[(int(groups[group]) + int(slot.get("tone", 0))) % gems.size()]
		slot["target_gem"] = gem
		slot["target_color"] = GemCatalog.color_of(gem)

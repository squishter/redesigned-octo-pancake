class_name CustomThemes
extends RefCounted
## Her own color stories: named themes she makes from gem colors she has,
## MIN_COLORS to GemCatalog.MAX_THEME_COLORS of them, in the order she
## picked them (rings and region groups walk the list, as with GemCatalog's
## THEMES). Kept in her profile as `custom_themes`: [{id, name, gems}],
## oldest first. Ids start with ID_PREFIX, so they never meet a built-in
## theme's.
##
## A puzzle made with one carries the theme's name and colors in its
## request (theme_name, theme_gems; see PuzzleMaker.make), so it keeps
## them even if she changes or deletes the story later.

const ID_PREFIX := "mine_"
const MIN_COLORS := 2
const MAX_NAME := 24
## More than she could want to scroll through.
const MAX_THEMES := 60


## Her color stories, oldest first.
static func list(profile: Dictionary) -> Array:
	return profile.get("custom_themes", [])


static func is_custom(theme_id: String) -> bool:
	return theme_id.begins_with(ID_PREFIX)


## Her story with this id, or {}.
static func find(profile: Dictionary, theme_id: String) -> Dictionary:
	for t: Dictionary in list(profile):
		if t["id"] == theme_id:
			return t
	return {}


## Her stories she can use: every color still hers (a debug build can lend
## colors, then take them back).
static func usable(profile: Dictionary) -> Array:
	var colors: Array = profile.get("unlocks", {}).get("colors", [])
	return list(profile).filter(func(t: Dictionary) -> bool:
		return (t["gems"] as Array).all(func(g: String) -> bool: return g in colors))


## Whether `gems` make a story: enough colors, not too many, no repeats,
## all real gem colors.
static func valid_gems(gems: Array) -> bool:
	if gems.size() < MIN_COLORS or gems.size() > GemCatalog.MAX_THEME_COLORS:
		return false
	var known := {}
	for g in GemCatalog.all_colors():
		known[g["id"]] = true
	var seen := {}
	for gem in gems:
		if not gem is String or not known.has(gem) or seen.has(gem):
			return false
		seen[gem] = true
	return true


## A name for a story: trimmed and shortened, or "My colors N" if blank.
static func clean_name(profile: Dictionary, name: String) -> String:
	name = name.strip_edges().left(MAX_NAME)
	return name if name != "" else "My colors %d" % (list(profile).size() + 1)


## Adds a story (or, with `theme_id`, changes that one). Returns its id, or
## "" if the colors don't make one or there are already MAX_THEMES.
static func save(profile: Dictionary, name: String, gems: Array, theme_id := "") -> String:
	if not valid_gems(gems):
		return ""
	var themes := list(profile)
	profile["custom_themes"] = themes
	var existing := find(profile, theme_id)
	if not existing.is_empty():
		existing["name"] = clean_name(profile, name)
		existing["gems"] = gems.duplicate()
		return theme_id
	if themes.size() >= MAX_THEMES:
		return ""
	var id := "%s%d_%d" % [ID_PREFIX, int(Time.get_unix_time_from_system()), randi() % 100000]
	while not find(profile, id).is_empty():
		id += "x"
	themes.append({"id": id, "name": clean_name(profile, name), "gems": gems.duplicate()})
	return id


static func remove(profile: Dictionary, theme_id: String) -> void:
	var themes := list(profile)
	for i in themes.size():
		if themes[i]["id"] == theme_id:
			themes.remove_at(i)
			return


## A loaded profile's stories, tidied: anything malformed is dropped (as
## from a hand-edited file); names and colors are kept as they were.
static func upgrade(profile: Dictionary) -> void:
	var out := []
	var loaded: Variant = profile.get("custom_themes", [])
	if loaded is Array:
		for t: Variant in loaded:
			if not t is Dictionary:
				continue
			var gems: Variant = t.get("gems")
			if not t.get("id") is String or not is_custom(t["id"]) or not gems is Array:
				continue
			var names := []
			for g: Variant in gems:
				names.append(str(g))
			if not valid_gems(names):
				continue
			out.append({"id": t["id"], "name": str(t.get("name", "My colors")).left(MAX_NAME), "gems": names})
	profile["custom_themes"] = out

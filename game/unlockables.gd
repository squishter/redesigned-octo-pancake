class_name Unlockables
extends RefCounted
## Every kind of unlockable in one table, and the rules that keep adding
## more safe.
##
## Adding to the game:
## - A new item of a kind: add it to its catalog (GemCatalog, GemCuts.BY_SHAPE
##   for cuts). Packs offer it at once (a sold-out pack comes back in
##   stock), Collection shows it, and nothing she has changes.
## - A new starting item: add it to its STARTING_ list. Players who already
##   have a profile get it on their next start too (see normalize()).
## - A new kind: add a row to KINDS (its unlock list in the profile and the
##   pack that gives it) and its items to items(). Profiles grow the new list
##   on load.
## Never rename or reuse an id: saves keep ids, never positions or names. To
## rename one anyway, map the old id to the new in RENAMED.
##
## Saved puzzles don't depend on any of this: each keeps its whole picture
## (every stone's shape, cut and color), so they look and play the same
## whatever is added later.

## kind -> {key: the profile's unlock list ("" for power-ups, which are
## charges), pack: the pack that gives it ("" for kinds no pack gives:
## themes come with their colors), title, found: what a reveal says}.
const KINDS := {
	"color": {"key": "colors", "pack": "colors", "title": "Gem colors", "found": "New gem color!"},
	"shape": {"key": "shapes", "pack": "shapes", "title": "Shapes and cuts", "found": "New gem shape!"},
	"cut": {"key": "shapes", "pack": "cuts", "title": "Shapes and cuts", "found": "New cut!"},
	"theme": {"key": "themes", "pack": "", "title": "Color themes", "found": "New color theme!"},
	"puzzle": {"key": "puzzles", "pack": "puzzles", "title": "Picture types", "found": "New picture type!"},
	"feature": {"key": "features", "pack": "features", "title": "Flourishes", "found": "New flourish!"},
	"animation": {"key": "animations", "pack": "animations", "title": "Ways to place gems",
			"found": "New way to place gems!"},
	"finale": {"key": "finales", "pack": "animations", "title": "Finales", "found": "New finale!"},
	"power": {"key": "", "pack": "powers", "title": "Power-ups", "found": "Power-up!"},
}
## Old id -> new id, per kind ("kind:old": "new"), applied to profiles on load.
const RENAMED := {}
## Charges a power-up pack gives: on-demand ones come in pairs.
const NOW_CHARGES := 2
const PUZZLE_CHARGES := 1


## Every item of a kind, in catalog order: [{kind, id, name, about, ...}].
## Colors carry `color`; shapes and cuts `shape` and `cut` (a cut's id is
## "shape|cut"); power-ups `charges` (what a pack gives).
static func items(kind: String) -> Array:
	var out := []
	match kind:
		"color":
			for g in GemCatalog.all_colors():
				out.append({"id": g["id"], "name": g["name"], "color": g["color"], "about": "A new gem color."})
		"shape":
			for shape: String in GemCatalog.ALL_SHAPES:
				var cut: String = GemCuts.for_shape(shape)[0]
				out.append({"id": shape, "shape": shape, "cut": cut, "name": shape.capitalize(),
						"about": "A new gem shape, in its %s cut." % cut})
		"cut":
			for pair: Array in GemCatalog.all_cuts():
				out.append({"id": "%s|%s" % pair, "shape": pair[0], "cut": pair[1],
						"name": GemCatalog.cut_name(pair[0], pair[1]), "about": "A new cut for your %ss." % pair[0]})
		"theme":
			for t: String in GemCatalog.THEMES:
				out.append({"id": t, "name": GemCatalog.theme_name(t), "about": "A new color theme."})
		"power":
			for p: String in GemCatalog.POWERS:
				var info: Dictionary = GemCatalog.POWERS[p]
				out.append({"id": p, "name": info["name"], "about": info["about"],
						"charges": NOW_CHARGES if info["kind"] == "now" else PUZZLE_CHARGES})
		_:
			var catalog := _catalog(kind)
			for id: String in catalog:
				out.append({"id": id, "name": catalog[id]["name"], "about": catalog[id]["about"]})
	for item: Dictionary in out:
		item["kind"] = kind
	return out


## The catalog of a kind kept as {id: {name, about, ...}}.
static func _catalog(kind: String) -> Dictionary:
	match kind:
		"puzzle":
			return GemCatalog.PUZZLES
		"feature":
			return GemCatalog.FEATURES
		"animation":
			return GemCatalog.ANIMATIONS
		"finale":
			return GemCatalog.FINALES
	return {}


## What she starts with, per kind (ids; a cut's id is "shape|cut").
static func starting(kind: String) -> Array:
	match kind:
		"color":
			return GemCatalog.STARTING_COLORS
		"shape":
			return GemCatalog.STARTING_SHAPES
		"theme":
			return GemCatalog.STARTING_THEMES
		"puzzle":
			return GemCatalog.STARTING_PUZZLES
		"animation":
			return GemCatalog.STARTING_ANIMATIONS
		"finale":
			return GemCatalog.STARTING_FINALES
	return []


## A new player's unlocks: every kind's list, holding its starting items.
static func default_unlocks() -> Dictionary:
	var profile := {"unlocks": {}, "powers": {}}
	normalize(profile)
	return profile["unlocks"]


## Every item of every kind unlocked (for testing; see SaveStore.UNLOCK_ALL).
static func all_unlocks() -> Dictionary:
	var profile := {"unlocks": default_unlocks(), "powers": {}}
	for kind: String in KINDS:
		if KINDS[kind]["key"] != "":
			for item: Dictionary in items(kind):
				grant(profile, item)
	return profile["unlocks"]


## Whether she has an item (power-ups are charges, never "had").
static func has(unlocks: Dictionary, item: Dictionary) -> bool:
	match item["kind"]:
		"power":
			return false
		"shape":
			return unlocks.get("shapes", {}).has(item["id"])
		"cut":
			return GemCatalog.has_cut(unlocks, item["shape"], item["cut"])
		"theme":
			return GemCatalog.has_theme(unlocks, item["id"])
	return item["id"] in unlocks.get(KINDS[item["kind"]]["key"], [])


## Whether an item can come out of a pack yet: not had, of a kind packs
## give, and a cut only for a shape she has.
static func findable(unlocks: Dictionary, item: Dictionary) -> bool:
	if has(unlocks, item) or KINDS[item["kind"]]["pack"] == "":
		return false
	return item["kind"] != "cut" or unlocks.get("shapes", {}).has(item["shape"])


## Every theme she has with `after` unlocks but not with `before`.
static func themes_gained(before: Dictionary, after: Dictionary) -> Array:
	return GemCatalog.THEMES.keys().filter(func(t: String) -> bool:
		return GemCatalog.has_theme(after, t) and not GemCatalog.has_theme(before, t))


## Gives her an item: unlocks only ever grow, a power-up adds its charges.
static func grant(profile: Dictionary, item: Dictionary) -> void:
	var unlocks: Dictionary = profile["unlocks"]
	match item["kind"]:
		"power":
			var powers: Dictionary = profile["powers"]
			powers[item["id"]] = int(powers.get(item["id"], 0)) + int(item.get("charges", 1))
		"shape", "cut":
			var cuts: Array = unlocks["shapes"].get(item["shape"], [])
			if not item["cut"] in cuts:
				cuts.append(item["cut"])
			unlocks["shapes"][item["shape"]] = cuts
		_:
			var list: Array = unlocks[KINDS[item["kind"]]["key"]]
			if not item["id"] in list:
				list.append(item["id"])


## Brings a profile (new, or saved by any earlier version) up to date:
## every kind's list exists, renamed ids move to their new names, and every
## starting item is in, so starting items added later reach players who
## already have a profile. Starting power-up charges are given once, ever
## (the `granted` ledger). Nothing is taken away, and ids it doesn't know
## (from a newer version) are kept.
static func normalize(profile: Dictionary) -> void:
	var unlocks: Dictionary = profile.get("unlocks", {})
	profile["unlocks"] = unlocks
	for kind: String in KINDS:
		var key: String = KINDS[kind]["key"]
		if key == "" or unlocks.has(key):
			continue
		unlocks[key] = {} if key == "shapes" else []
	for key in RENAMED:
		var parts: PackedStringArray = str(key).split(":")
		var list_key: String = KINDS[parts[0]]["key"]
		var list: Variant = unlocks.get(list_key)
		if list is Array and parts[1] in list:
			list.erase(parts[1])
			if not RENAMED[key] in list:
				list.append(RENAMED[key])
		elif list is Dictionary and list.has(parts[1]):
			list[RENAMED[key]] = list[parts[1]]
			list.erase(parts[1])
	var shapes: Dictionary = unlocks["shapes"]
	for shape: String in shapes:
		var cuts: Array = []
		for cut in shapes[shape]:
			cuts.append(str(cut))
		shapes[shape] = cuts
	for kind: String in KINDS:
		for id: String in starting(kind):
			var item := {"kind": kind, "id": id}
			if kind == "shape":
				item["shape"] = id
				item["cut"] = GemCuts.for_shape(id)[0]
			grant(profile, item)
	if not profile.has("powers"):
		profile["powers"] = {}
	var granted: Array = profile.get("granted", [])
	# Profiles from before the ledger already got the starting charges.
	if not profile.has("granted") and not (profile["powers"] as Dictionary).is_empty():
		for p: String in GemCatalog.STARTING_POWERS:
			granted.append("power:" + p)
	for p: String in GemCatalog.STARTING_POWERS:
		if not ("power:" + p) in granted:
			granted.append("power:" + p)
			grant(profile, {"kind": "power", "id": p, "charges": GemCatalog.STARTING_POWERS[p]})
	profile["granted"] = granted

class_name Packs
extends RefCounted
## Gem packs and what pays for them.
##
## Each unlock pack gives one thing she doesn't have yet from its category
## (never a repeat), and is sold out once there's nothing left in it. The
## Everything pack picks a category that still has something (each as
## likely), then something from it. The power-up pack always gives charges.
##
## Packs are opened with a free pick or with coins. She gets a free pick the
## first time she opens the game each day and another for the first puzzle
## she finishes each day, and COINS_PER_PUZZLE coins for every puzzle she
## finishes (once per puzzle), so every 3 puzzles pay for a pack. Power-up
## packs cost about one puzzle's coins.
##
## Her balance lives in the profile (SaveStore): wallet {coins, picks},
## daily {opened, completed} (dates) and powers {power: charges}.

const COINS_PER_PUZZLE := 10
const PACK_PRICE := 30
const POWER_PACK_PRICE := 10
## Charges a power-up pack gives: on-demand ones come in pairs.
const NOW_CHARGES := 2
const PUZZLE_CHARGES := 1

const PACKS := {
	"colors": {"name": "Color pack", "about": "A new gem color."},
	"shapes": {"name": "Shape pack", "about": "A new gem shape, in its classic cut."},
	"cuts": {"name": "Facet pack", "about": "A new cut for a shape you have."},
	"puzzles": {"name": "Picture pack", "about": "A new kind of puzzle."},
	"themes": {"name": "Theme pack", "about": "A new color theme."},
	"features": {"name": "Flourish pack", "about": "Frames, collars and other picture touches."},
	"animations": {"name": "Sparkle pack", "about": "A new way for gems to go in, or a new finale."},
	"powers": {"name": "Power-up pack", "about": "Charges of a power-up."},
	"all": {"name": "Everything pack", "about": "Anything from any other pack."},
}


static func price(pack: String) -> int:
	return POWER_PACK_PRICE if pack == "powers" else PACK_PRICE


static func coins(profile: Dictionary) -> int:
	return int(profile["wallet"]["coins"])


static func picks(profile: Dictionary) -> int:
	return int(profile["wallet"]["picks"])


## What a pack could still give: [{kind, id, name, about, ...}]. Colors
## carry `color`, shapes and cuts `shape` and `cut`.
static func pool(pack: String, profile: Dictionary) -> Array:
	var unlocks: Dictionary = profile["unlocks"]
	var out := []
	match pack:
		"colors":
			for g in GemCatalog.all_colors():
				if not g["id"] in unlocks["colors"]:
					out.append({"kind": "color", "id": g["id"], "name": g["name"], "color": g["color"],
							"about": "A new gem color."})
		"shapes":
			for shape: String in GemCatalog.ALL_SHAPES:
				if not unlocks["shapes"].has(shape):
					var cut: String = GemCuts.for_shape(shape)[0]
					out.append({"kind": "shape", "id": shape, "shape": shape, "cut": cut, "name": shape.capitalize(),
							"about": "A new gem shape, in its %s cut." % cut})
		"cuts":
			for pair: Array in GemCatalog.all_cuts():
				if unlocks["shapes"].has(pair[0]) and not GemCatalog.has_cut(unlocks, pair[0], pair[1]):
					out.append({"kind": "cut", "id": "%s|%s" % pair, "shape": pair[0], "cut": pair[1],
							"name": GemCatalog.cut_name(pair[0], pair[1]), "about": "A new cut for your %ss." % pair[0]})
		"puzzles":
			out = _missing("puzzle", GemCatalog.PUZZLES, unlocks["puzzles"])
		"themes":
			for t: String in GemCatalog.THEMES:
				if not t in unlocks["themes"]:
					out.append({"kind": "theme", "id": t, "name": GemCatalog.theme_name(t), "about": "A new color theme."})
		"features":
			out = _missing("feature", GemCatalog.FEATURES, unlocks["features"])
		"animations":
			out = (_missing("animation", GemCatalog.ANIMATIONS, unlocks["animations"])
					+ _missing("finale", GemCatalog.FINALES, unlocks["finales"]))
		"powers":
			for p: String in GemCatalog.POWERS:
				var info: Dictionary = GemCatalog.POWERS[p]
				out.append({"kind": "power", "id": p, "name": info["name"], "about": info["about"],
						"charges": NOW_CHARGES if info["kind"] == "now" else PUZZLE_CHARGES})
		"all":
			for other: String in PACKS:
				if other != "all":
					out.append_array(pool(other, profile))
	return out


static func _missing(kind: String, catalog: Dictionary, have: Array) -> Array:
	var out := []
	for id: String in catalog:
		if not id in have:
			out.append({"kind": kind, "id": id, "name": catalog[id]["name"], "about": catalog[id]["about"]})
	return out


static func sold_out(pack: String, profile: Dictionary) -> bool:
	return pool(pack, profile).is_empty()


## Opens a pack, paying with a free pick (`with_pick`) or coins, and gives
## what's in it. Returns the item (see pool), or {} when it can't be opened
## (sold out, or nothing to pay with). Doesn't save the profile.
static func open(profile: Dictionary, pack: String, with_pick: bool, rng: RandomNumberGenerator) -> Dictionary:
	if sold_out(pack, profile):
		return {}
	var wallet: Dictionary = profile["wallet"]
	if with_pick:
		if picks(profile) <= 0:
			return {}
		wallet["picks"] = picks(profile) - 1
	else:
		if coins(profile) < price(pack):
			return {}
		wallet["coins"] = coins(profile) - price(pack)
	var item := draw(pack, profile, rng)
	give(profile, item)
	return item


## One thing from a pack: the Everything pack first picks a category with
## something left (each as likely), so power-ups don't crowd it out.
static func draw(pack: String, profile: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if pack == "all":
		var open_packs := []
		for other: String in PACKS:
			if other != "all" and not sold_out(other, profile):
				open_packs.append(other)
		pack = open_packs[rng.randi_range(0, open_packs.size() - 1)]
	var items := pool(pack, profile)
	var item: Dictionary = items[rng.randi_range(0, items.size() - 1)]
	item["pack"] = pack
	return item


static func give(profile: Dictionary, item: Dictionary) -> void:
	var unlocks: Dictionary = profile["unlocks"]
	match item["kind"]:
		"color":
			unlocks["colors"].append(item["id"])
		"shape", "cut":
			var cuts: Array = unlocks["shapes"].get(item["shape"], [])
			if not item["cut"] in cuts:
				cuts.append(item["cut"])
			unlocks["shapes"][item["shape"]] = cuts
		"puzzle":
			unlocks["puzzles"].append(item["id"])
		"theme":
			unlocks["themes"].append(item["id"])
		"feature":
			unlocks["features"].append(item["id"])
		"animation":
			unlocks["animations"].append(item["id"])
		"finale":
			unlocks["finales"].append(item["id"])
		"power":
			var powers: Dictionary = profile["powers"]
			powers[item["id"]] = int(powers.get(item["id"], 0)) + int(item["charges"])


static func today() -> String:
	return Time.get_date_string_from_system()


## The day's free pick for opening the game, once a day. True if given.
static func daily_open(profile: Dictionary) -> bool:
	var daily: Dictionary = profile["daily"]
	if daily.get("opened", "") == today():
		return false
	daily["opened"] = today()
	profile["wallet"]["picks"] = picks(profile) + 1
	return true


## Rewards for finishing a puzzle (once per puzzle): coins, doubled by the
## Double coins power-up, and the day's pick for a first finished puzzle.
## Returns {coins, pick} given (zeros if it was rewarded before).
static func puzzle_finished(profile: Dictionary, meta: Dictionary, doubled: bool) -> Dictionary:
	if meta.get("rewarded", false):
		return {"coins": 0, "pick": false}
	meta["rewarded"] = true
	var earned := COINS_PER_PUZZLE * (2 if doubled else 1)
	profile["wallet"]["coins"] = coins(profile) + earned
	var pick := false
	var daily: Dictionary = profile["daily"]
	if daily.get("completed", "") != today():
		daily["completed"] = today()
		profile["wallet"]["picks"] = picks(profile) + 1
		pick = true
	return {"coins": earned, "pick": pick}


static func charges(profile: Dictionary, power: String) -> int:
	return int(profile["powers"].get(power, 0))


## Spends a power-up charge; false if there's none.
static func spend(profile: Dictionary, power: String) -> bool:
	if charges(profile, power) <= 0:
		return false
	profile["powers"][power] = charges(profile, power) - 1
	return true

class_name Packs
extends RefCounted
## Gem packs and what pays for them.
##
## Each unlock pack gives new things from its category
## (never a repeat), and is sold out once there's nothing left in it. The
## Everything pack picks a category that still has something (each as
## likely) for each draw, then something from it. Power-up packs give two
## power-ups, each with its usual charges. Every pack has a 1-in-5 chance
## of an extra power-up. Everything gives two unlockables, or three 1 in 15
## times, and costs 50 coins (no free picks).
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
const POWER_BONUS_ODDS := 5
const ALL_EXTRA_ODDS := 15

const PACKS := {
	"colors": {"name": "Color pack", "about": "A new gem color."},
	"shapes": {"name": "Shape pack", "about": "A new gem shape, in its classic cut."},
	"cuts": {"name": "Facet pack", "about": "A new cut for a shape you have."},
	"puzzles": {"name": "Picture pack", "about": "A new kind of puzzle."},
	"features": {"name": "Flourish pack", "about": "Frames, collars and other picture touches."},
	"animations": {"name": "Sparkle pack", "about": "A new way for gems to go in, or a new finale."},
	"powers": {"name": "Power-up pack", "about": "Two power-ups, with charges for each.", "rewards": 2},
	"all": {"name": "Everything pack", "about": "Two new unlockables. 1 in 15 packs includes a third. Coins only.",
		"rewards": 2, "price": 50},
}
## A pack for a new kind of unlockable goes in PACKS, and the kind's row in
## Unlockables.KINDS names it.


## Definitions may set rewards (base draws, default 1), source (default
## the pack id), and price. Everything's base pool contains only unlockables.
static func price(pack: String, catalog: Dictionary = PACKS) -> int:
	var info: Dictionary = catalog.get(pack, {})
	var source: String = info.get("source", pack)
	return maxi(0, int(info.get("price", POWER_PACK_PRICE if source == "powers" else PACK_PRICE)))


static func reward_count(pack: String, catalog: Dictionary = PACKS) -> int:
	return maxi(1, int(catalog.get(pack, {}).get("rewards", 1)))


static func can_use_pick(pack: String, catalog: Dictionary = PACKS) -> bool:
	return catalog.has(pack) and catalog[pack].get("source", pack) != "all"


static func coins(profile: Dictionary) -> int:
	return int(profile["wallet"]["coins"])


static func picks(profile: Dictionary) -> int:
	return int(profile["wallet"]["picks"])


## What a pack could still give: every findable item of the kinds it
## offers (see Unlockables.KINDS; the Everything pack offers them all),
## [{kind, id, name, about, ...}].
static func pool(pack: String, profile: Dictionary, catalog: Dictionary = PACKS) -> Array:
	var source: String = catalog.get(pack, {}).get("source", pack)
	var out := []
	for kind: String in Unlockables.KINDS:
		var from: String = Unlockables.KINDS[kind]["pack"]
		if source != from and not (source == "all" and from != "" and kind != "power"):
			continue
		for item: Dictionary in Unlockables.items(kind):
			if kind == "power" or Unlockables.findable(profile["unlocks"], item):
				out.append(item)
	return out


static func sold_out(pack: String, profile: Dictionary, catalog: Dictionary = PACKS) -> bool:
	if not catalog.has(pack):
		return true
	var available := pool(pack, profile, catalog)
	if catalog[pack].get("source", pack) != "all" or available.size() != 1:
		return available.is_empty()
	# The last available shape may make a cut eligible for the second draw.
	var staged: Dictionary = profile.duplicate(true)
	give(staged, available[0])
	return pool(pack, staged, catalog).is_empty()


## One payment, one committed bundle. Plan on a copy first: later draws see
## earlier unlocks (including newly eligible cuts), and no reward repeats
## inside a bundle. When stock runs low, give the remaining distinct rewards.
## Returns [] without payment when unavailable. The caller saves the entire
## profile before presenting the returned rewards, including bonus themes.
static func open(profile: Dictionary, pack: String, with_pick: bool, rng: RandomNumberGenerator,
		catalog: Dictionary = PACKS) -> Array[Dictionary]:
	if sold_out(pack, profile, catalog):
		return []
	if (with_pick and (not can_use_pick(pack, catalog) or picks(profile) <= 0)
			or (not with_pick and coins(profile) < price(pack, catalog))):
		return []
	var staged: Dictionary = profile.duplicate(true)
	var rewards: Array[Dictionary] = []
	var seen: Array[String] = []
	var bonus_power := rng.randi_range(1, POWER_BONUS_ODDS) == 1
	var count := reward_count(pack, catalog)
	var everything: bool = catalog[pack].get("source", pack) == "all"
	if everything and rng.randi_range(1, ALL_EXTRA_ODDS) == 1:
		count += 1
	for _i in count:
		var item := draw(pack, staged, rng, catalog, seen)
		if item.is_empty():
			break
		seen.append(_reward_key(item))
		give(staged, item)
		rewards.append(item)
	if rewards.is_empty() or (everything and rewards.size() < 2):
		return []
	if bonus_power:
		var power := draw("powers", staged, rng, PACKS, seen)
		if not power.is_empty():
			power["bonus"] = true
			give(staged, power)
			rewards.append(power)
	# Completed themes are real bonus rewards, but never consume base draws.
	var themes := Unlockables.themes_gained(profile["unlocks"], staged["unlocks"])
	for theme: Dictionary in Unlockables.items("theme"):
		if theme["id"] in themes:
			theme["bonus"] = true
			theme["pack"] = pack
			rewards.append(theme)
	# No yields or fallible UI work between granting and the single payment.
	for item: Dictionary in rewards:
		give(profile, item)
	var wallet: Dictionary = profile["wallet"]
	if with_pick:
		wallet["picks"] = picks(profile) - 1
	else:
		wallet["coins"] = coins(profile) - price(pack, catalog)
	return rewards


## One draw without granting. Everything picks a category uniformly first,
## then an unlockable, so abundant colors do not crowd other categories out.
static func draw(pack: String, profile: Dictionary, rng: RandomNumberGenerator,
		catalog: Dictionary = PACKS, excluded: Array[String] = []) -> Dictionary:
	var items := pool(pack, profile, catalog).filter(func(item: Dictionary) -> bool:
		return not _reward_key(item) in excluded)
	if items.is_empty():
		return {}
	var source: String = catalog.get(pack, {}).get("source", pack)
	if source == "all":
		var categories: Array[String] = []
		for item: Dictionary in items:
			var category: String = Unlockables.KINDS[item["kind"]]["pack"]
			if not category in categories:
				categories.append(category)
		source = categories[rng.randi_range(0, categories.size() - 1)]
		items = items.filter(func(item: Dictionary) -> bool: return Unlockables.KINDS[item["kind"]]["pack"] == source)
	var item: Dictionary = items[rng.randi_range(0, items.size() - 1)]
	item["pack"] = source
	return item


static func _reward_key(item: Dictionary) -> String:
	return "%s|%s" % [item["kind"], item["id"]]


static func give(profile: Dictionary, item: Dictionary) -> void:
	Unlockables.grant(profile, item)


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

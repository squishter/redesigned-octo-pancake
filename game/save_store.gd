class_name SaveStore
extends RefCounted
## Her saved games, under user://saves:
##   profile.json: {version, unlocks (see GemCatalog), settings, wallet
##     {coins, picks}, daily {opened, completed}, powers {power: charges}
##     (see Packs), puzzles: [meta]}, where each meta is {id, type, seed,
##     pattern_seed, theme, created, updated, total, filled, done, rewarded,
##     powers (the whole-puzzle power-ups on for it)}, newest first;
##   <id>.json: the puzzle's picture (PatternIO), written once;
##   <id>.progress: which stones are placed, one bit per slot;
##   <id>.png: a small thumbnail for the menu.
## Every puzzle keeps its own files, so starting a new one never touches the
## others. Files are written to a temporary name and then moved into place,
## so a crash mid-write leaves the old file whole.

const DIR := "user://saves"
## Profile format: 2 added the `granted` ledger (see Unlockables.normalize).
## Loading brings any older profile up to date; fields it doesn't know (from
## a newer version) are kept as they are.
const VERSION := 2
## Her settings and their defaults: how a placed gem goes in and the
## finale's wave (unlocked ones of GemCatalog.ANIMATIONS and FINALES), and frame cap.
const DEFAULT_SETTINGS := {"fill_animation": "fly", "finale": "ripple", "fps_cap": 30}
## Player frame caps, with 0 leaving the rate uncapped by the engine.
const FPS_CAPS := [30, 60, 90, 120, 0]
## Debug builds only: the setting that lends her everything for testing.
## While it's on, the profile's `unlocks` hold every item and her own are
## kept aside under REAL_UNLOCKS, which is what save_profile writes. Turned
## off (or in a release build) she has exactly what she had.
const UNLOCK_ALL := "debug_unlock_all"
const REAL_UNLOCKS := "_real_unlocks"
## Debug purchases never spend the player's actual coins or free picks.
const FREE_PURCHASES := "debug_free_purchases"


static func load_profile() -> Dictionary:
	var profile := {}
	var path := DIR + "/profile.json"
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			profile = data
	upgrade(profile)
	set_unlock_all(profile, bool(profile["settings"].get(UNLOCK_ALL, false)))
	set_free_purchases(profile, bool(profile["settings"].get(FREE_PURCHASES, false)))
	return profile


## Turns UNLOCK_ALL on or off in memory (save_profile keeps it). Never on
## outside debug builds.
static func set_unlock_all(profile: Dictionary, on: bool) -> void:
	on = on and OS.is_debug_build()
	if on and not profile.has(REAL_UNLOCKS):
		profile[REAL_UNLOCKS] = profile["unlocks"]
		profile["unlocks"] = Unlockables.all_unlocks()
	elif not on and profile.has(REAL_UNLOCKS):
		profile["unlocks"] = profile[REAL_UNLOCKS]
		profile.erase(REAL_UNLOCKS)
	if on:
		profile["settings"][UNLOCK_ALL] = true
	else:
		profile["settings"].erase(UNLOCK_ALL)


static func is_unlock_all(profile: Dictionary) -> bool:
	return profile.has(REAL_UNLOCKS)


static func set_free_purchases(profile: Dictionary, on: bool) -> void:
	if on and OS.is_debug_build():
		profile["settings"][FREE_PURCHASES] = true
	else:
		profile["settings"].erase(FREE_PURCHASES)


## Also guard at purchase time so a copied debug profile cannot enable it in release.
static func free_purchases_enabled(profile: Dictionary) -> bool:
	return OS.is_debug_build() and profile.get("settings", {}).get(FREE_PURCHASES, false) == true


## A profile as loaded from JSON (any version, or {} for a new player),
## brought up to date: missing parts get their defaults, numbers come back
## as ints, unlocks get anything new they should have (see
## Unlockables.normalize). Nothing she has is lost.
static func upgrade(profile: Dictionary) -> Dictionary:
	profile["version"] = maxi(int(profile.get("version", 1)), VERSION)
	var powers: Dictionary = profile.get("powers", {})
	for key: String in powers:
		powers[key] = int(powers[key])
	profile["powers"] = powers
	Unlockables.normalize(profile)
	var settings: Dictionary = profile.get("settings", {})
	for key: String in DEFAULT_SETTINGS:
		if not settings.has(key):
			settings[key] = DEFAULT_SETTINGS[key]
	settings["fps_cap"] = fps_cap(settings)
	profile["settings"] = settings
	var wallet: Dictionary = profile.get("wallet", {})
	for key in ["coins", "picks"]:
		wallet[key] = int(wallet.get(key, 0))
	profile["wallet"] = wallet
	var daily: Dictionary = profile.get("daily", {})
	for key in ["opened", "completed"]:
		daily[key] = str(daily.get(key, ""))
	profile["daily"] = daily
	var puzzles: Array = profile.get("puzzles", [])
	for meta: Dictionary in puzzles:
		for key in ["seed", "pattern_seed", "created", "updated", "total", "filled"]:
			meta[key] = int(meta.get(key, 0))
		meta["done"] = bool(meta.get("done", false))
		meta["rewarded"] = bool(meta.get("rewarded", false))
		meta["powers"] = meta.get("powers", [])
		Hints.upgrade(meta)
	profile["puzzles"] = puzzles
	return profile


## JSON numbers may be floats; invalid or unsupported values use the default.
static func fps_cap(settings: Dictionary) -> int:
	var cap: Variant = settings.get("fps_cap", DEFAULT_SETTINGS["fps_cap"])
	if cap is int or cap is float:
		for allowed: int in FPS_CAPS:
			if cap == allowed:
				return allowed
	return DEFAULT_SETTINGS["fps_cap"]


static func apply_settings(profile: Dictionary) -> void:
	Engine.max_fps = fps_cap(profile.get("settings", {}))


static func save_profile(profile: Dictionary) -> Error:
	var saved := profile
	if profile.has(REAL_UNLOCKS):
		saved = profile.duplicate()
		saved["unlocks"] = saved[REAL_UNLOCKS]
		saved.erase(REAL_UNLOCKS)
	return _write(DIR + "/profile.json", JSON.stringify(saved, "\t").to_utf8_buffer())


## Adds a new puzzle (its picture made by PuzzleMaker) to the profile, newest
## first, and writes it. Returns its meta.
static func add_puzzle(profile: Dictionary, picture: Dictionary) -> Dictionary:
	var request: Dictionary = picture.get("puzzle", {})
	var now := int(Time.get_unix_time_from_system())
	var id := "p%d_%d" % [now, randi() % 100000]
	var meta := {
		"id": id,
		"type": request.get("type", "mandala"),
		"seed": int(request.get("seed", 0)),
		"pattern_seed": int(request.get("pattern_seed", 0)),
		"theme": request.get("theme", ""),
		"kit_size": request.get("kit_size", ""),
		"created": now,
		"updated": now,
		"total": picture["slots"].size(),
		"filled": 0,
		"done": false,
		"hints": Hints.START,
		"hint_ms": 0,
	}
	# Kits save as their grid, not their (many) slots.
	var kept := picture
	if picture.has("kit_grid"):
		kept = picture.duplicate()
		kept.erase("slots")
	_write(_path(id, "json"), PatternIO.to_json(kept).to_utf8_buffer())
	save_progress(id, PackedByteArray())
	(profile["puzzles"] as Array).push_front(meta)
	save_profile(profile)
	return meta


static func find(profile: Dictionary, id: String) -> Dictionary:
	for meta: Dictionary in profile["puzzles"]:
		if meta["id"] == id:
			return meta
	return {}


static func delete_puzzle(profile: Dictionary, id: String) -> void:
	var puzzles: Array = profile["puzzles"]
	for i in puzzles.size():
		if puzzles[i]["id"] == id:
			puzzles.remove_at(i)
			break
	for ext in ["json", "progress", "png"]:
		if FileAccess.file_exists(_path(id, ext)):
			DirAccess.remove_absolute(_path(id, ext))
	save_profile(profile)


static func load_picture(id: String) -> Dictionary:
	var picture := PatternIO.load_file(_path(id, "json"))
	if picture.has("kit_grid") and not picture.has("slots"):
		picture["slots"] = PuzzleMaker.kit_slots(picture)
	return picture


## Placed stones as one byte per slot (1 placed), `count` long.
static func load_progress(id: String, count: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(count)
	var path := _path(id, "progress")
	if not FileAccess.file_exists(path):
		return out
	var bits := FileAccess.get_file_as_bytes(path)
	for i in mini(count, bits.size() * 8):
		if bits[i >> 3] & (1 << (i & 7)):
			out[i] = 1
	return out


static func save_progress(id: String, placed: PackedByteArray) -> Error:
	var bits := PackedByteArray()
	bits.resize((placed.size() + 7) / 8)
	for i in placed.size():
		if placed[i] != 0:
			bits[i >> 3] = bits[i >> 3] | (1 << (i & 7))
	return _write(_path(id, "progress"), bits)


static func save_thumbnail(id: String, img: Image) -> Error:
	return _write(_path(id, "png"), img.save_png_to_buffer())


static func load_thumbnail(id: String) -> Texture2D:
	var path := _path(id, "png")
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(img)


static func _path(id: String, ext: String) -> String:
	return "%s/%s.%s" % [DIR, id, ext]


static func _write(path: String, bytes: PackedByteArray) -> Error:
	DirAccess.make_dir_recursive_absolute(DIR)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.close()
	if DirAccess.rename_absolute(tmp, path) == OK:
		return OK
	# Some platforms won't move over an existing file.
	DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)

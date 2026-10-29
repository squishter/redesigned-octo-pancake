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
## finale's wave (unlocked ones of GemCatalog.ANIMATIONS and FINALES).
const DEFAULT_SETTINGS := {"fill_animation": "fly", "finale": "ripple"}


static func load_profile() -> Dictionary:
	var profile := {}
	var path := DIR + "/profile.json"
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			profile = data
	return upgrade(profile)


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
	profile["puzzles"] = puzzles
	return profile


static func save_profile(profile: Dictionary) -> Error:
	return _write(DIR + "/profile.json", JSON.stringify(profile, "\t").to_utf8_buffer())


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
		"created": now,
		"updated": now,
		"total": picture["slots"].size(),
		"filled": 0,
		"done": false,
	}
	_write(_path(id, "json"), PatternIO.to_json(picture).to_utf8_buffer())
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
	return PatternIO.load_file(_path(id, "json"))


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

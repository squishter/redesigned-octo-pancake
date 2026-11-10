extends SceneTree
## Posed plants as pictures: the line-art variant, the game's Plant picture
## type (collage and kit), saved recipes, hanging heads and the aura.
##
##   godot --headless -s res://tests/run_plant_pictures.gd

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_line_art()
	_hanging()
	_aura()
	_game()
	print("%s: %d checks, %d failures" % ["FAILED" if failures else "PASSED", checks, failures])
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + what)
		print("FAIL: " + what)


func _line_art() -> void:
	_check("plant_mesh" in MandalaGenerator.VARIANTS, "plants are a line-art variant")
	var a := MandalaGenerator.generate(41, {"variant": "plant_mesh"})
	var b := MandalaGenerator.generate(41, {"variant": "plant_mesh"})
	_check(a["polylines"].size() > 4 and a["polylines"] == b["polylines"], "the same seed draws the same plant")
	_check(a["symmetry"] == "none" and a["frame"].is_empty(), "plants are free-form and unframed")
	_check(a["families"].size() == a["polylines"].size() and not a["marks"].is_empty(), "plants carry paint families")
	var info: Dictionary = a["plant_mesh"]
	_check(info["recipe"] is Dictionary and info["recipe"]["seed"] == 41, "the plant's recipe is in its choices")
	var picked: Dictionary = MandalaGenerator.PLANT_PICTURE
	_check(info["flowers"] in picked["flowers"] and info["branching"] in picked["branching"]
			and info["camera"] in picked["cameras"], "unasked choices suit a picture")
	_check(info["stats"]["flower_count"] <= picked["few_heads"][1], "a picture's plant has few heads")
	# A saved source makes the same plant again, through JSON.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(info, "", true, true))
	var replay := MandalaGenerator.generate(41, {"variant": "plant_mesh", "plant": saved})
	_check(replay["polylines"] == a["polylines"], "a saved recipe replays the plant")
	# Explicit choices win; choices the plants don't have are ignored.
	var asked := MandalaGenerator.generate(41, {"variant": "plant_mesh", "flower": "rose", "leaf": "fern",
			"flowers": "many", "camera": "back", "pose": "curl", "collar": "rays"})
	_check(asked["plant_mesh"].get("flower") == "rose" and asked["plant_mesh"]["leaf"] == "fern"
			and asked["plant_mesh"]["flowers"] == "many" and asked["plant_mesh"]["camera"] == "back",
			"explicit plant choices are kept")
	var natural := MandalaGenerator.generate(41, {"variant": "plant_mesh", "plant_natural": true})
	_check(not natural["plant_mesh"].is_empty() and natural["plant_mesh"]["recipe"]["controls"]["length"] == 2.25,
			"plant_natural leaves the generator's defaults")
	var recent := []
	var flowers := {}
	for i in 8:
		var m := MandalaGenerator.generate(500 + i, {"variant": "plant_mesh", "recent": recent, "projection_size": 96})
		recent.append(m["plant_mesh"])
		flowers[m["plant_mesh"]["flower"]] = true
	_check(flowers.size() >= 7, "recent flowers aren't repeated (%d of 8 differ)" % flowers.size())


## Hanging heads hang: mouth down, from the end of a pedicel that goes up
## and over, clear of the stem.
func _hanging() -> void:
	for flower: String in PlantGrowth.HANGING:
		for seed_value in [3, 4]:
			var built := PlantMeshGenerator.surface(seed_value, {"flower": flower, "flowers": "few", "curve": "straight"})
			var heads := 0
			for site: Dictionary in built.data.attachments:
				if site.kind != "flower":
					continue
				heads += 1
				_check(site.axis.y < -0.6, "%s head faces down (axis y %.2f)" % [flower, site.axis.y])
				_check(site.root.y < site.attachment.y + 0.2 and Vector2(site.root.x - site.attachment.x,
						site.root.z - site.attachment.z).length() > 0.08, "%s head hangs clear of its socket" % flower)
				_check(rad_to_deg(site.axis.angle_to(site.support_axis)) <= 6.001, "%s head follows its pedicel" % flower)
			_check(heads == 5, "%s plant has its heads" % flower)
	var upright := PlantMeshGenerator.surface(3, {"flower": "rose", "flowers": "one", "curve": "straight"})
	for site: Dictionary in upright.data.attachments:
		if site.kind == "flower":
			_check(site.axis.y > 0.6, "upright heads still face up")


func _aura() -> void:
	var with_stones := 0
	var styles := {}
	for i in 6:
		var seed_value := 60 + i
		var style: String = GemAura.STYLES[i % GemAura.STYLES.size()]
		var opts := {"variant": "plant_mesh", "layout": "cluster", "theme": "garden", "collar": style,
				"pattern_seed": i, "projection_size": 160}
		var lines := PictureSources.mandala_lines(seed_value, opts)
		var p := PictureSources.mandala_collage(seed_value, opts, lines)
		var aura: Dictionary = p["aura"]
		styles[aura["style"]] = true
		_check(aura["style"] == style, "the asked aura style is used")
		var same := PictureSources.mandala_collage(seed_value, opts, lines)
		_check(same["aura"] == aura and same["slots"].size() == p["slots"].size(), "auras are deterministic")
		var bare_opts := opts.duplicate()
		bare_opts["collar"] = "none"
		var bare := PictureSources.mandala_collage(seed_value, bare_opts, lines)
		_check(bare["aura"]["stones"] == 0 and bare["aura"]["region"] == -1, "collar none leaves the aura out")
		var own: int = p["slots"].size() - aura["stones"]
		_check(own == bare["slots"].size(), "the aura changes nothing else (%d vs %d stones)" % [own, bare["slots"].size()])
		if aura["stones"] == 0:
			continue
		with_stones += 1
		_check(aura["stones"] <= own * CollageGenerator.AURA_SHARE, "the aura stays a small share of the stones")
		var region: Dictionary = p["regions"][aura["region"]]
		_check(aura["region"] == p["regions"].size() - 1 and region["kind"] == "aura" and region["style"] == style,
				"the aura is the last region")
		var w: int = p["width"]
		var h: int = p["height"]
		var unit: float = p["unit"]
		var stones := []
		var others := []
		for s: Dictionary in p["slots"]:
			_check(s["id"] == stones.size() + others.size(), "slot ids run in order")
			if s["region"] == aura["region"]:
				stones.append(s)
			else:
				others.append(s)
		var lines_mask: PackedByteArray = p["lines"]
		var clear := true
		var inside := true
		var apart := true
		var small := true
		var typed := true
		for s: Dictionary in stones:
			var r: float = s["width"] / 2.0
			var c := Vector2(s["x"], s["y"])
			inside = inside and c.x >= r and c.y >= r and c.x <= w - r and c.y <= h - r
			small = small and r <= unit * GemAura.STONE + 0.01 and r >= unit * GemAura.MIN_STONE - 0.01
			typed = typed and s.has("cut") and s.has("target_color") and s["shape"] == "round"
			# Clear paper all around: no line within a stone and a half of it.
			for k in 12:
				var q := c + Vector2.from_angle(TAU * k / 12.0) * (r + unit)
				if lines_mask[clampi(int(q.y), 0, h - 1) * w + clampi(int(q.x), 0, w - 1)] != 0:
					clear = false
			for o: Dictionary in others + stones:
				if not is_same(o, s) and c.distance_to(Vector2(o["x"], o["y"])) < r + o["width"] / 2.0:
					apart = false
		_check(inside, "aura stones are inside the picture")
		_check(small, "aura stones are small")
		_check(typed, "aura stones are whole slots")
		_check(clear, "the aura keeps clear paper around the plant")
		_check(apart, "aura stones touch no other stone")
		# No outer edge: a veil's far stones are fewer than its near ones
		# (streams are checked stone by stone below).
		stones.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["fade"] < b["fade"])
		var third := stones.size() / 3
		if third >= 4 and style == "veil":
			var near := stones.slice(0, third)
			var far := stones.slice(stones.size() - third)
			var near_span: float = near[-1]["fade"] - near[0]["fade"]
			var far_span: float = far[-1]["fade"] - far[0]["fade"]
			_check(far_span > near_span * 1.3, "a veil thins outward (%.2f vs %.2f of the reach per third)" % [
					far_span, near_span])
		_check(stones[-1]["fade"] < 1.0, "every stone is inside the reach")
		_check(_reach_spread(stones, Vector2(w, h) / 2.0) > 1.4, "the aura's reach is uneven around the plant")
	_check(with_stones == 6, "every plant gets an aura (%d of 6)" % with_stones)
	_check(styles.size() == GemAura.STYLES.size(), "every aura style was made")
	# Every stream tapers: each stone smaller than the one before, down to
	# about the smallest stone there is, so none ends on a full-sized one.
	var o := {"variant": "plant_mesh", "layout": "cluster", "collar": "none", "projection_size": 160}
	var plant := PictureSources.mandala_collage(61, o)
	var placed := GemAura.place(plant["lines"], plant["width"], plant["height"], 9, {"style": "streams",
			"unit": plant["unit"], "keep_clear": plant["slots"]})
	var strands := {}
	for s: Dictionary in placed["slots"]:
		if not strands.has(s["strand"]):
			strands[s["strand"]] = []
		strands[s["strand"]].append(s)
	var smallest: float = plant["unit"] * GemAura.MIN_STONE * 2.0
	var tapering := true
	var long := 0
	var ends_small := 0
	for strand: int in strands:
		var run: Array = strands[strand]
		for k in range(1, run.size()):
			tapering = tapering and run[k]["width"] < run[k - 1]["width"] and run[k]["fade"] > run[k - 1]["fade"] - 0.05
		if run.size() >= 4:
			long += 1
			ends_small += int(run[-1]["width"] <= smallest * 1.25)
	_check(tapering, "every stream's stones shrink as it flows out")
	_check(long >= 5 and ends_small >= long * 0.8, "long streams end small (%d of %d)" % [ends_small, long])
	var thinned := GemAura.place(plant["lines"], plant["width"], plant["height"], 9, {"style": "streams",
			"unit": plant["unit"], "keep_clear": plant["slots"], "max_stones": placed["slots"].size() / 2})
	_check(thinned["slots"].size() <= placed["slots"].size() / 2 and thinned["slots"].size() > placed["slots"].size() / 4,
			"a capped aura is thinned, not dropped (%d of %d)" % [thinned["slots"].size(), placed["slots"].size()])
	# A framed plant, and pictures that aren't plants, get none.
	var heart := PictureSources.mandala_collage(7, {"variant": "heart", "layout": "cluster"})
	_check(heart["aura"]["stones"] == 0, "other pictures have no aura")
	# A picture with no background to speak of gets none either.
	var full := PackedByteArray()
	full.resize(64 * 64)
	_check(GemAura.place(full, 64, 64, 1)["slots"].is_empty(), "no subject, no aura")


func _mean_width(stones: Array) -> float:
	var sum := 0.0
	for s: Dictionary in stones:
		sum += s["width"]
	return sum / maxi(1, stones.size())


## How uneven the aura's outside is: the farthest stone in the widest of
## twelve sectors around `center` over that in the narrowest that has any,
## each measured from the nearest stone of its sector.
func _reach_spread(stones: Array, center: Vector2) -> float:
	var lo := {}
	var hi := {}
	for s: Dictionary in stones:
		var v := Vector2(s["x"], s["y"]) - center
		var k := int(fposmod(v.angle(), TAU) / TAU * 12.0)
		lo[k] = minf(lo.get(k, INF), v.length())
		hi[k] = maxf(hi.get(k, 0.0), v.length())
	var widest := 0.0
	var narrowest := INF
	for k: int in lo:
		var depth: float = hi[k] - lo[k] + 4.0
		widest = maxf(widest, depth)
		narrowest = minf(narrowest, depth)
	return widest / narrowest if lo.size() >= 3 else 0.0


func _game() -> void:
	var plant: Dictionary = GemCatalog.PUZZLES["plant"]
	_check(plant["variant"] == "plant_mesh" and not plant.get("kit", false), "the game has a Plant picture type")
	_check("plant" in Unlockables.items("puzzle").map(func(item: Dictionary) -> String: return item["id"]),
			"Plant can be found in packs")
	var unlocks := Unlockables.all_unlocks()
	var request := {"type": "plant", "seed": 4242, "pattern_seed": 17, "theme": "garden", "layout": "cluster"}
	var picture := PuzzleMaker.make(request, unlocks)
	_check(picture["slots"].size() >= CollageGenerator.CLUSTER_MIN_SLOTS / 2, "a game plant has stones (%d)"
			% picture["slots"].size())
	_check(picture["source"]["variant"] == "plant_mesh" and picture["source"]["plant_mesh"]["recipe"]["seed"] == 4242,
			"a game plant keeps its recipe")
	_check(picture["aura"]["style"] in GemAura.STYLES, "a game plant has an aura once collars are unlocked")
	# Saved and loaded, the recipe is exact and the aura's region survives.
	var loaded := PatternIO.from_json(PatternIO.to_json(picture))
	_check(loaded["regions"].size() == picture["regions"].size() and loaded["slots"].size() == picture["slots"].size(),
			"a saved plant keeps its aura")
	var first := MandalaGenerator.generate(4242, {"variant": "plant_mesh", "plant": picture["source"]["plant_mesh"]})
	var again := MandalaGenerator.generate(4242, {"variant": "plant_mesh", "plant": loaded["source"]["plant_mesh"]})
	_check(not again["polylines"].is_empty() and again["polylines"] == first["polylines"],
			"a saved and loaded recipe grows exactly the same plant")
	# Recoloring keeps every stone, aura and all.
	var recolored := PuzzleRecolor.make(picture, {"type": "plant", "theme": "berry"})
	_check(not recolored.is_empty() and recolored["slots"].size() == picture["slots"].size(), "a plant can be recolored")
	# Without the collars flourish there is no aura.
	var plain := PuzzleMaker.make(request, Unlockables.default_unlocks())
	_check(plain["aura"]["stones"] == 0 and plain["aura"]["style"] == "none", "no aura before collars are unlocked")
	var kit := PuzzleMaker.make({"type": "kit", "picture": "plant", "seed": 4242, "pattern_seed": 0, "theme": "garden"},
			unlocks)
	_check(kit["kind"] == "kit" and kit["source"]["variant"] == "plant_mesh"
			and kit["source"]["plant_mesh"]["recipe"]["seed"] == 4242, "a plant kit keeps the plant's recipe")
	_check(GemCatalog.puzzle_title({"type": "kit", "picture": "plant"}) == "Plant diamond kit", "plant kits are named")

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
	_colors()
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
	# An unframed plant's picture takes the plant's shape, and the plant fills it.
	var limits: Array = picked["aspect"]
	_check(a.has("aspect") and a["aspect"] >= limits[0] and a["aspect"] <= limits[1], "a plant's picture has its shape")
	var lines := PictureSources.mandala_lines(41, {"variant": "plant_mesh", "size": 400})
	_check(maxi(lines["width"], lines["height"]) == 400 and absf(float(lines["width"]) / lines["height"] - a["aspect"]) < 0.01,
			"the picture is rasterized in that shape (%dx%d)" % [lines["width"], lines["height"]])
	var half := Vector2(1.0, 1.0 / a["aspect"]) if a["aspect"] <= 1.0 else Vector2(a["aspect"], 1.0)
	var box := Rect2(a["polylines"][0][0], Vector2.ZERO)
	for line: PackedVector2Array in a["polylines"]:
		for v in line:
			box = box.expand(v)
	var pad: float = picked["pad"]
	_check(box.position.x >= -half.x + pad - 0.01 and box.end.x <= half.x - pad + 0.01
			and box.position.y >= -half.y + pad - 0.01 and box.end.y <= half.y - pad + 0.01, "the plant keeps room for its collar")
	_check(box.size.x >= (half.x - pad) * 2.0 - 0.02 or box.size.y >= (half.y - pad) * 2.0 - 0.02, "the plant fills its picture")
	var framed := MandalaGenerator.generate(41, {"variant": "plant_mesh", "frame": true})
	_check(not framed.has("aspect") and not framed["frame"].is_empty(), "a framed plant stays square")
	# Patches too small for gems are folded away: a hydrangea's florets
	# become a few areas, not hundreds of lines.
	var fine := MandalaGenerator.generate(32, {"variant": "plant_mesh", "flower": "hydrangea", "plant_min_region": 0.0})
	var folded := MandalaGenerator.generate(32, {"variant": "plant_mesh", "flower": "hydrangea"})
	_check(folded["polylines"].size() < fine["polylines"].size() * 0.6 and folded["polylines"].size() > 4,
			"small patches are folded into their neighbors (%d lines from %d)" % [folded["polylines"].size(),
			fine["polylines"].size()])
	var head_lines := PictureSources.mandala_lines(32, {"variant": "plant_mesh", "flower": "hydrangea"})
	var on_lines := 0
	for v in head_lines["mask"]:
		on_lines += int(v != 0)
	var raw_lines := PictureSources.mandala_lines(32, {"variant": "plant_mesh", "flower": "hydrangea", "plant_min_region": 0.0})
	var raw_on := 0
	for v in raw_lines["mask"]:
		raw_on += int(v != 0)
	_check(on_lines < raw_on * 0.8, "a folded plant is less line (%d px from %d)" % [on_lines, raw_on])
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
	for i in 9:
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
		_check(aura["stones"] <= own * CollageGenerator.AURA_SHARE or style == "halo",
				"the aura stays a small share of the stones")
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
		var radii := others.map(func(s: Dictionary) -> float: return s["width"] / 2.0)
		radii.sort()
		var typical: float = radii[int((radii.size() - 1) * CollageGenerator.AURA_STONE_RANK)]
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
			small = small and r <= minf(unit * GemAura.STONE, typical * CollageGenerator.AURA_STONE) + 0.01
			typed = typed and s.has("cut") and s.has("target_color") and s["shape"] == "round"
			# Clear paper all around: no line within a unit of it (a halo sits
			# closer in: half a unit).
			for k in 12:
				var q := c + Vector2.from_angle(TAU * k / 12.0) * (r + unit * (0.5 if style == "halo" else 1.0))
				if lines_mask[clampi(int(q.y), 0, h - 1) * w + clampi(int(q.x), 0, w - 1)] != 0:
					clear = false
			for o: Dictionary in others + stones:
				if not is_same(o, s) and c.distance_to(Vector2(o["x"], o["y"])) < r + o["width"] / 2.0:
					apart = false
		_check(inside, "aura stones are inside the picture")
		_check(small, "aura stones are smaller than the plant's bigger stones")
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
		if style == "halo":
			# Rows of even stones: one size in a row, at most two rows.
			var sizes := {}
			for s: Dictionary in stones:
				sizes[snappedf(s["width"], 0.01)] = true
			_check(sizes.size() <= 2, "a halo's rows are even (%d sizes)" % sizes.size())
		else:
			_check(_reach_spread(stones, Vector2(w, h) / 2.0) > 1.4, "the aura's reach is uneven around the plant")
	_check(with_stones == 9, "every plant gets an aura (%d of 9)" % with_stones)
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
	# Line stones on a plant's close lines never run into each other.
	for seed_value in [1008, 1017]:
		var classic := PictureSources.mandala_collage(seed_value, {"variant": "plant_mesh", "frame": false, "collar": "none"})
		var hits := 0
		var line_stones: Array = classic["slots"].filter(func(s: Dictionary) -> bool:
			return classic["regions"][s["region"]]["kind"] == "line")
		for i in line_stones.size():
			for j in range(i + 1, line_stones.size()):
				hits += int(CollageGenerator._capsule_gap(line_stones[i], line_stones[j]) < -1.0)
		_check(hits == 0, "seed %d: %d line stones overlap" % [seed_value, hits])
		_check(classic["bold_lines"] > 0 or seed_value != 1008, "plants keep their bold line stones")
	# A framed plant, and pictures that aren't plants, get none.
	var heart := PictureSources.mandala_collage(7, {"variant": "heart", "layout": "cluster"})
	_check(heart["aura"]["stones"] == 0, "other pictures have no aura")
	# A picture with no background to speak of gets none either.
	var full := PackedByteArray()
	full.resize(64 * 64)
	_check(GemAura.place(full, 64, 64, 1)["slots"].is_empty(), "no subject, no aura")


## Flowers in the colors that stand out from the paper, each head its own;
## stems, leaves and their outlines in the quiet ones.
func _colors() -> void:
	var paper := CollageGenerator.AURA_PAPER
	var palette := Palettes.theme_colors("garden")
	var split := RegionPaint.split_palette(palette, paper)
	var bold: PackedColorArray = split["bold"]
	var quiet: PackedColorArray = split["quiet"]
	_check(bold.size() + quiet.size() == palette.size() and quiet.size() == 2, "a palette of six has two quiet colors")
	var lab := LabColor.from_color(paper)
	var nearest_bold := INF
	var farthest_quiet := 0.0
	for c in bold:
		nearest_bold = minf(nearest_bold, LabColor.from_color(c).distance_to(lab))
	for c in quiet:
		farthest_quiet = maxf(farthest_quiet, LabColor.from_color(c).distance_to(lab))
	_check(nearest_bold >= farthest_quiet, "bold colors stand farther from the paper than quiet ones")
	_check(RegionPaint.split_palette(PackedColorArray([Color.RED]), paper)["bold"].size() == 1, "one color is bold and quiet")
	var head_colors_differ := 0
	var heads_seen := 0
	for seed_value in [1, 31, 33, 4, 22]:
		var opts := {"variant": "plant_mesh", "layout": "cluster", "theme": "garden", "collar": "none", "pattern_seed": 3}
		var lines := PictureSources.mandala_lines(seed_value, opts)
		var motifs: Dictionary = lines["motifs"]
		_check(motifs.has("bold") and not motifs["bold"].is_empty(), "seed %d: the plant's flowers are its bold areas" % seed_value)
		var p := PictureSources.mandala_collage(seed_value, opts, lines)
		var paint := CollageGenerator._snapped_palette(palette, Palettes.starter_gems())
		var roles := RegionPaint.split_palette(paint, paper)
		var is_bold := {}
		var is_quiet := {}
		for c: Color in roles["bold"]:
			is_bold[c.to_html(false)] = true
		for c: Color in roles["quiet"]:
			is_quiet[c.to_html(false)] = true
		# Every region is one or the other, and all its stones stay in its
		# palette whatever the variety pass recolored.
		var region_bold := {}
		var mixed := 0
		var bold_areas := 0
		var quiet_areas := 0
		for r: Dictionary in p["regions"]:
			var key: String = (r["color"] as Color).to_html(false)
			region_bold[r["id"]] = is_bold.has(key)
			if r["kind"] == "area":
				bold_areas += int(is_bold.has(key))
				quiet_areas += int(is_quiet.has(key))
		for s: Dictionary in p["slots"]:
			var key: String = (s["target_color"] as Color).to_html(false)
			if not (is_bold if region_bold[s["region"]] else is_quiet).has(key):
				mixed += 1
		_check(mixed == 0, "seed %d: %d stones left their region's palette" % [seed_value, mixed])
		# Stems and leaves: one quiet color each, through and through.
		var quiet_colors := {}
		var strayed := 0
		for r: Dictionary in p["regions"]:
			if r["kind"] == "area" and not region_bold[r["id"]]:
				quiet_colors[(r["color"] as Color).to_html(false)] = true
		for s: Dictionary in p["slots"]:
			var region: Dictionary = p["regions"][s["region"]]
			if region["kind"] == "area" and not region_bold[s["region"]] and s["target_color"] != region["color"]:
				strayed += 1
		_check(strayed == 0, "seed %d: %d stem or leaf stones aren't their area's color" % [seed_value, strayed])
		_check(quiet_colors.size() == 2, "seed %d: stems and leaves differ (%d quiet colors)" % [seed_value, quiet_colors.size()])
		_check(bold_areas > 0 and quiet_areas > 0, "seed %d: bold flowers (%d areas) and quiet greens (%d)" % [seed_value,
				bold_areas, quiet_areas])
		# The areas a head's marks fall in: heads may differ from each other.
		var map := RegionMap.build(p["lines"], p["width"], p["height"], 0)
		var by_head := {}
		for area: Dictionary in motifs["areas"]:
			if not motifs["bold"].has(area["family"]):
				continue
			var names: int = motifs["names"].size()
			if (area["family"] - PictureSources.PLANT_HEAD_FAMILY) % names != motifs["names"].find("petals"):
				continue
			var label := map.label_at(int(area["at"].x), int(area["at"].y))
			if label < 0:
				continue
			var head: int = (area["family"] - PictureSources.PLANT_HEAD_FAMILY) / names
			# The collage's own region there, by the nearest stone.
			var best := {}
			var best_d := INF
			for s: Dictionary in p["slots"]:
				var d: float = Vector2(s["x"], s["y"]).distance_squared_to(area["at"])
				if d < best_d and p["regions"][s["region"]]["kind"] == "area":
					best_d = d
					best = s
			if not best.is_empty():
				by_head[head] = (p["regions"][best["region"]]["color"] as Color).to_html(false)
		heads_seen += by_head.size()
		var distinct := {}
		for head: int in by_head:
			distinct[by_head[head]] = true
		head_colors_differ += int(distinct.size() > 1)
	_check(heads_seen >= 5, "flower heads were found (%d)" % heads_seen)
	_check(head_colors_differ >= 1, "heads of one plant can differ in color")
	# The painted picture (for kits) follows the same roles.
	var kit_lines := PictureSources.mandala_lines(1, {"variant": "plant_mesh", "theme": "garden"})
	var image := PictureSources.mandala_image(1, {"variant": "plant_mesh", "theme": "garden"}, kit_lines)
	var seen_bold := false
	var seen_quiet := false
	var others := 0
	var bold_keys := {}
	var quiet_keys := {}
	for c in bold:
		bold_keys[c.to_html(false)] = true
	for c in quiet:
		quiet_keys[c.to_html(false)] = true
	for area: Dictionary in kit_lines["motifs"]["areas"]:
		var key := image.get_pixel(int(area["at"].x), int(area["at"].y)).to_html(false)
		var flower: bool = kit_lines["motifs"]["bold"].has(area["family"])
		if flower and bold_keys.has(key):
			seen_bold = true
		elif not flower and quiet_keys.has(key):
			seen_quiet = true
		else:
			others += 1
	_check(seen_bold and seen_quiet and others <= kit_lines["motifs"]["areas"].size() / 4,
			"a painted plant has bold flowers and quiet greens (%d areas off)" % others)
	# Other pictures are colored as they always were.
	var heart := PictureSources.mandala_lines(7, {"variant": "swirl"})
	_check(not heart.get("motifs", {}).has("bold"), "only plants have bold areas")


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
	_check(picture["setting"] == "gems" and picture["sparsity"] == 0.0, "a plant has gem lines and no sparse areas")
	var bare := 0
	for r: Dictionary in picture["regions"]:
		bare += int(r["kind"] == "area" and r["fill"] in ["scatter", "outline", "accent"])
	_check(bare == 0, "no plant area is sparse")
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

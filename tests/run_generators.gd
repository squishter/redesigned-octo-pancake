extends SceneTree
## Headless checks for the puzzle generators, plus preview PNGs.
##
##   godot --headless --import            # once, registers class names
##   godot --headless -s res://tests/run_generators.gd -- --out=/tmp/previews --seeds=20
##
## Exits with code 1 if any check fails.

var failures := 0
var out_dir := "user://previews"
var seeds := 20


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--seeds="):
			seeds = int(arg.trim_prefix("--seeds="))
	DirAccess.make_dir_recursive_absolute(out_dir)

	test_lab_round_trip()
	test_mandala_determinism()
	test_mandalas()
	test_flowers()
	test_hearts()
	test_butterflies()
	test_snowflakes()
	test_frames()
	test_collages()
	test_design_plans()
	test_pattern_seeds()
	test_symmetry()
	test_gem_cuts()
	test_board_light()
	test_kits()
	test_photo_line_art()
	test_json_round_trip()
	test_game_puzzles()
	test_saves()

	print("\n%s (%d failures). Previews in %s" % ["FAILED" if failures else "PASSED", failures,
			ProjectSettings.globalize_path(out_dir)])
	quit(1 if failures else 0)


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("  FAIL: ", what)


func test_lab_round_trip() -> void:
	print("Lab round trip")
	for c in [Color("#e8517d"), Color("#1b2350"), Color.WHITE, Color.BLACK, Color("#5cc3b5")]:
		var back := LabColor.to_color(LabColor.from_color(c))
		check(absf(back.r - c.r) + absf(back.g - c.g) + absf(back.b - c.b) < 0.01, "Lab round trip of %s gave %s" % [c, back])


func test_mandala_determinism() -> void:
	print("Mandala determinism")
	for variant in MandalaGenerator.VARIANTS:
		var a := MandalaGenerator.generate(42, {"variant": variant, "wobble": 0.5})
		var b := MandalaGenerator.generate(42, {"variant": variant, "wobble": 0.5})
		var c := MandalaGenerator.generate(43, {"variant": variant, "wobble": 0.5})
		check(a["polylines"] == b["polylines"], "%s: same seed gave different lines" % variant)
		check(a["polylines"] != c["polylines"], "%s: different seeds gave the same lines" % variant)


## 24 mandalas in a row: every silhouette, center, extra and ring pattern
## shows up, many rings combine patterns, and each has plenty of closed
## regions. Two are forced to the zoomed-in crop. Writes a contact sheet.
func test_mandalas() -> void:
	print("Mandalas")
	var count := 24
	var cell := 256
	var sheet := Image.create(cell * 6, cell * 4, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	var recent := []
	var seen := {}
	var rings := 0
	var combined := 0
	for i in count:
		var seed_value := 7000 + i
		var opts := {"variant": "mandala", "recent": recent, "frame": false}
		if i == 5 or i == 17:
			opts["zoom"] = true
		var lines := PictureSources.mandala_lines(seed_value, opts)
		var md: Dictionary = lines["mandala"]["mandala"]
		recent.append(md)
		seen[md["silhouette"]] = true
		seen[md["center"]] = true
		for e in md["extras"]:
			seen[e] = true
		var names := PackedStringArray()
		for ring in md["rings"]:
			rings += 1
			if ring.size() >= 2:
				combined += 1
			for p in ring:
				seen[p] = true
			names.append("+".join(PackedStringArray(ring)))
		if md["zoom"]:
			check(lines["mandala"]["symmetry"] == "none", "seed %d: a zoomed crop should not be symmetric" % seed_value)
		var w: int = lines["width"]
		var h: int = lines["height"]
		var map := RegionMap.build(lines["mask"], w, h, int(w * h * 0.0005))
		print("  seed %d %2d-fold %-10s %-8s extras %-20s%s %3d regions  %s" % [seed_value, md["folds"],
				md["silhouette"], md["center"], " + ".join(PackedStringArray(md["extras"])),
				" zoom" if md["zoom"] else "     ", map.regions.size(), " | ".join(names)])
		check(map.regions.size() >= 10, "seed %d: only %d regions" % [seed_value, map.regions.size()])
		sheet_cell(sheet, lines, i, cell)
	var expected := (MandalaDesign.SILHOUETTES + MandalaDesign.CENTERS + MandalaDesign.EXTRAS + MandalaDesign.SINGULAR
			+ MandalaDesign.RISING + MandalaDesign.HANGING + MandalaDesign.FLOATING)
	for choice in expected:
		check(seen.has(choice), "%s never showed up in %d mandalas" % [choice, count])
	check(combined * 3 >= rings, "only %d of %d rings combine patterns" % [combined, rings])
	sheet.save_png(out_dir.path_join("mandalas_contact_sheet.png"))


## 24 flowers in a row, as a pack's picture choices would make them: every
## template shows up, none repeats within AVOID_RECENT flowers, petal counts
## vary, and each flower has plenty of closed regions. Writes a contact sheet.
func test_flowers() -> void:
	print("Flowers")
	var count := 24
	var cell := 256
	var sheet := Image.create(cell * 6, cell * 4, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	var recent := []
	var counts := {}
	for i in count:
		var seed_value := 3000 + i
		var lines := PictureSources.mandala_lines(seed_value, {"variant": "flower", "recent": recent, "wobble": 0.4,
				"frame": false})
		var flower: Dictionary = lines["mandala"]["flower"]
		var template: String = flower["template"]
		check(not template in recent.slice(maxi(0, recent.size() - FlowerGenerator.AVOID_RECENT)),
				"seed %d: %s repeats within %d flowers" % [seed_value, template, FlowerGenerator.AVOID_RECENT])
		recent.append(template)
		var petals: Array = []
		for ring in flower["rings"]:
			petals.append(ring["petals"])
		var allowed: Array = FlowerGenerator.TEMPLATES[template]["petals"]
		# Rings that would be too thin get fewer petals, never more.
		check(petals[0] >= 3 and petals[0] <= allowed[1], "seed %d: %s with %d petals" % [seed_value, template, petals[0]])
		counts[petals[0]] = true
		var w: int = lines["width"]
		var h: int = lines["height"]
		var map := RegionMap.build(lines["mask"], w, h, int(w * h * 0.0005))
		print("  seed %d %-8s petals %s center %-7s %d regions" % [seed_value, template, petals, flower["center"],
				map.regions.size()])
		check(map.regions.size() >= 5, "seed %d: only %d regions" % [seed_value, map.regions.size()])
		sheet_cell(sheet, lines, i, cell)
	var used := {}
	for t in recent:
		used[t] = true
	check(used.size() == FlowerGenerator.TEMPLATES.size(), "only %d of %d templates in %d flowers" % [
			used.size(), FlowerGenerator.TEMPLATES.size(), count])
	check(counts.size() >= 8, "only %d different outer petal counts" % counts.size())
	sheet.save_png(out_dir.path_join("flowers_contact_sheet.png"))


## 24 hearts in a row: every shape, collar and inner pattern shows up, most
## hearts combine 2-3 patterns, every heart is mirror-symmetric with plenty of
## closed regions. Writes a contact sheet.
func test_hearts() -> void:
	print("Hearts")
	var count := 24
	var cell := 256
	var sheet := Image.create(cell * 6, cell * 4, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	var recent := []
	var seen := {}
	var combined := 0
	for i in count:
		var seed_value := 4000 + i
		var lines := PictureSources.mandala_lines(seed_value, {"variant": "heart", "recent": recent, "frame": false})
		var heart: Dictionary = lines["mandala"]["heart"]
		recent.append(heart)
		seen[heart["shape"]] = true
		seen[heart["collar"]] = true
		for p in heart["patterns"]:
			seen[p] = true
		if heart["patterns"].size() >= 2:
			combined += 1
		var w: int = lines["width"]
		var h: int = lines["height"]
		var mask: PackedByteArray = lines["mask"]
		var map := RegionMap.build(mask, w, h, int(w * h * 0.0005))
		var mismatched := mirror_mismatch(mask, w, h)
		print("  seed %d %-10s %-8s %-32s %3d regions" % [seed_value, heart["shape"], heart["collar"],
				" + ".join(PackedStringArray(heart["patterns"])), map.regions.size()])
		check(map.regions.size() >= 3, "seed %d: only %d regions" % [seed_value, map.regions.size()])
		check(mismatched < w * h * 0.002, "seed %d: not mirror-symmetric (%d px differ)" % [seed_value, mismatched])
		sheet_cell(sheet, lines, i, cell)
	var expected := HeartGenerator.SHAPES.keys() + HeartGenerator.COLLARS + HeartGenerator.MOTIFS + HeartGenerator.FIELDS
	for choice in expected:
		check(seen.has(choice), "%s never showed up in %d hearts" % [choice, count])
	check(combined >= count / 2, "only %d of %d hearts combine patterns" % [combined, count])
	sheet.save_png(out_dir.path_join("hearts_contact_sheet.png"))


## 24 butterflies in a row: every wing shape, border, pattern, body and
## antenna style shows up, forewings and hindwings often differ, and every
## butterfly is mirror-symmetric with plenty of closed regions. Writes a
## contact sheet.
func test_butterflies() -> void:
	print("Butterflies")
	var count := 24
	var cell := 256
	var sheet := Image.create(cell * 6, cell * 4, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	var recent := []
	var seen := {}
	var differ := 0
	for i in count:
		var seed_value := 5000 + i
		var lines := PictureSources.mandala_lines(seed_value, {"variant": "butterfly", "recent": recent, "frame": false})
		var b: Dictionary = lines["mandala"]["butterfly"]
		recent.append(b)
		for key in ["shape", "border", "body", "antennae"]:
			seen[b[key]] = true
		for p in b["fore"] + b["hind"]:
			seen[p] = true
		if b["fore"] != b["hind"]:
			differ += 1
		var w: int = lines["width"]
		var h: int = lines["height"]
		var mask: PackedByteArray = lines["mask"]
		var map := RegionMap.build(mask, w, h, int(w * h * 0.0005))
		var mismatched := mirror_mismatch(mask, w, h)
		print("  seed %d %-11s %-9s %-9s %-9s fore %-28s hind %-28s %3d regions" % [seed_value, b["shape"],
				b["border"], b["body"], b["antennae"], " + ".join(PackedStringArray(b["fore"])),
				" + ".join(PackedStringArray(b["hind"])), map.regions.size()])
		check(map.regions.size() >= 6, "seed %d: only %d regions" % [seed_value, map.regions.size()])
		check(mismatched < w * h * 0.002, "seed %d: not mirror-symmetric (%d px differ)" % [seed_value, mismatched])
		sheet_cell(sheet, lines, i, cell)
	var expected := (ButterflyGenerator.SHAPES.keys() + ButterflyGenerator.BORDERS + ButterflyGenerator.PATTERNS
			+ ButterflyGenerator.BODIES + ButterflyGenerator.ANTENNAE)
	for choice in expected:
		check(seen.has(choice), "%s never showed up in %d butterflies" % [choice, count])
	check(differ >= count / 2, "forewing and hindwing patterns match in %d of %d" % [count - differ, count])
	sheet.save_png(out_dir.path_join("butterflies_contact_sheet.png"))


## 24 snowflakes in a row: every center, arm, tip, in-between content and
## detail shows up, nearly all have content between the arms, and each has
## plenty of closed regions. Writes a contact sheet.
func test_snowflakes() -> void:
	print("Snowflakes")
	var count := 24
	var cell := 256
	var sheet := Image.create(cell * 6, cell * 4, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	var recent := []
	var seen := {}
	var bare := 0
	for i in count:
		var seed_value := 6000 + i
		var lines := PictureSources.mandala_lines(seed_value, {"variant": "snowflake", "recent": recent, "frame": false})
		var f: Dictionary = lines["mandala"]["snowflake"]
		recent.append(f)
		for key in ["center", "arm", "tip"]:
			seen[f[key]] = true
		for b in f["between"] + f["details"]:
			seen[b] = true
		if f["between"].is_empty():
			bare += 1
		var w: int = lines["width"]
		var h: int = lines["height"]
		var map := RegionMap.build(lines["mask"], w, h, int(w * h * 0.0005))
		print("  seed %d %-8s %-9s %-8s between %-18s details %-12s %3d regions" % [seed_value, f["center"], f["arm"],
				f["tip"], " + ".join(PackedStringArray(f["between"])), " + ".join(PackedStringArray(f["details"])),
				map.regions.size()])
		check(map.regions.size() >= 6, "seed %d: only %d regions" % [seed_value, map.regions.size()])
		sheet_cell(sheet, lines, i, cell)
	var expected := (SnowflakeGenerator.CENTERS + SnowflakeGenerator.ARMS + SnowflakeGenerator.TIPS
			+ SnowflakeGenerator.BETWEEN + SnowflakeGenerator.DETAILS)
	for choice in expected:
		check(seen.has(choice), "%s never showed up in %d snowflakes" % [choice, count])
	check(bare <= count / 4, "%d of %d snowflakes have nothing between the arms" % [bare, count])
	sheet.save_png(out_dir.path_join("snowflakes_contact_sheet.png"))


## Frames: about three in four pictures are framed by default; 24 framed
## pictures in a row (across all variants) use every frame shape, band,
## corner and background. Writes a contact sheet.
func test_frames() -> void:
	print("Frames")
	var framed := 0
	for i in 40:
		var m := MandalaGenerator.generate(9000 + i, {"variant": MandalaGenerator.VARIANTS[i % 5], "zoom": false,
				"extras": []})
		if not m["frame"].is_empty():
			framed += 1
	print("  %d of 40 framed by default" % framed)
	check(framed >= 22 and framed <= 37, "%d of 40 framed, expected about 30" % framed)

	var count := 24
	var cell := 256
	var sheet := Image.create(cell * 6, cell * 4, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	var recent := []
	var seen := {}
	for i in count:
		var seed_value := 8000 + i
		var variant: String = MandalaGenerator.VARIANTS[i % MandalaGenerator.VARIANTS.size()]
		var lines := PictureSources.mandala_lines(seed_value, {"variant": variant, "frame": true, "frame_recent": recent,
				"zoom": false, "extras": []})
		var frame: Dictionary = lines["mandala"]["frame"]
		recent.append(frame)
		for key in frame:
			seen[frame[key]] = true
		var w: int = lines["width"]
		var h: int = lines["height"]
		var map := RegionMap.build(lines["mask"], w, h, int(w * h * 0.0005))
		print("  seed %d %-9s %-8s %-8s %-8s %-9s %3d regions" % [seed_value, variant, frame["shape"], frame["band"],
				frame["corner"], frame["background"], map.regions.size()])
		check(map.regions.size() >= 10, "seed %d: only %d regions" % [seed_value, map.regions.size()])
		sheet_cell(sheet, lines, i, cell)
	var expected := FrameDesign.SHAPES + FrameDesign.BANDS + FrameDesign.CORNERS + FrameDesign.BACKGROUNDS
	for choice in expected:
		check(seen.has(choice), "%s never showed up in %d frames" % [choice, count])
	sheet.save_png(out_dir.path_join("frames_contact_sheet.png"))


## Packs `seeds` mandalas across all variants and themes and checks the slots
## stay inside their regions, don't overlap, and cover the regions well.
func test_collages() -> void:
	print("Collages from %d seeds" % seeds)
	var themes := Palettes.theme_names()
	for i in seeds:
		var seed_value := 1000 + i
		var variant: String = MandalaGenerator.VARIANTS[i % MandalaGenerator.VARIANTS.size()]
		var t0 := Time.get_ticks_msec()
		var p := PictureSources.mandala_collage(seed_value, {
			"variant": variant,
			"wobble": 0.5 if i % 2 else 0.0,
			"theme": themes[i % themes.size()],
			"frame": false,
		})
		var ms := Time.get_ticks_msec() - t0
		var slots: Array = p["slots"]
		var regions: Array = p["regions"]
		var empty := 0
		var sparse := 0
		var areas := 0
		for r in regions:
			if r["kind"] != "area":
				continue
			areas += 1
			if r["empty"]:
				empty += 1
			if r["fill"] != "full":
				sparse += 1
		var coverage := CollageGenerator.mean_coverage(p)
		var img := render_collage(p)
		var overlaps := count_overlaps(slots, p["width"] * 0.002)
		print(("  seed %d %-9s %3d regions (%d empty, %d sparse) lines %-7s %4d slots  coverage %.0f%%"
				+ "  overlaps %d  stray px %.2f%%  %d ms") % [
			seed_value, variant, areas, empty, sparse, p["line_style"], slots.size(), coverage * 100.0,
			overlaps, img.get_meta("stray") * 100.0, ms])
		check(areas >= 5, "seed %d: only %d regions" % [seed_value, areas])
		check(float(empty) / areas < 0.25,
				"seed %d: %d of %d regions too thin for stones" % [seed_value, empty, areas])
		# Patterns leave the velvet showing between rows, so coverage runs lower than packing.
		check(coverage > 0.15, "seed %d: coverage %.2f" % [seed_value, coverage])
		check(overlaps == 0, "seed %d: %d overlapping slot pairs" % [seed_value, overlaps])
		check(img.get_meta("stray") < 0.02, "seed %d: slots spill onto lines" % seed_value)
		img.save_png(out_dir.path_join("collage_%d_%s.png" % [seed_value, variant]))


## Sparse fills and hidden lines: explicit settings are honored, sparse
## regions stay sparse, and every picture keeps something fully packed.
func test_design_plans() -> void:
	print("Design plans")
	var dense := PictureSources.mandala_collage(2001, {"sparsity": 0.0, "line_style": "full", "setting": "metal"})
	for r in dense["regions"]:
		check(r["fill"] == "full", "sparsity 0 gave a %s region" % r["fill"])
	check(dense["lines_visible"] == dense["lines"], "line_style full should draw every line")

	var bare := PictureSources.mandala_collage(2002, {"sparsity": 1.0, "line_style": "none", "setting": "metal"})
	var counts := {}
	var full_regions := 0
	var bare_area := 0.0
	var total_area := 0.0
	for r in bare["regions"]:
		counts[r["fill"]] = counts.get(r["fill"], 0) + 1
		total_area += r["area"]
		if r["fill"] == "full":
			full_regions += 1
		if r["fill"] == "bare":
			bare_area += r["area"]
	print("  sparsity 1: fills %s" % counts)
	check(full_regions > 0, "nothing left fully packed")
	check(counts.size() >= 3, "expected a mix of fills, got %s" % counts)
	check(bare_area <= DesignPlan.MAX_BARE_AREA * total_area + 1.0, "too much bare area")
	check(not 255 in bare["lines_visible"], "line_style none should hide every line")
	for s in bare["slots"]:
		check(bare["regions"][s["region"]]["fill"] != "bare", "slot in a bare region")
	var outlined := 0
	for r in bare["regions"]:
		if r["outlined"]:
			outlined += 1
	check(outlined == 0, "line_style none outlined %d regions" % outlined)
	render_collage(bare).save_png(out_dir.path_join("design_sparse_no_lines.png"))

	# Scatter regions are sparser than full ones.
	var mixed := PictureSources.mandala_collage(2003, {"sparsity": 0.6, "line_style": "partial", "setting": "metal"})
	var covered := {}
	for s in mixed["slots"]:
		var r: float = s["width"] / 2.0
		covered[s["region"]] = covered.get(s["region"], 0.0) + PI * r * r + 4.0 * r * (s["size"] / 2.0 - r)
	for r in mixed["regions"]:
		if r["fill"] == "scatter":
			check(covered.get(r["id"], 0.0) / r["area"] < 0.5, "scatter region %d too dense" % r["id"])
	var visible := 0
	var all_lines := 0
	for i in mixed["lines"].size():
		if mixed["lines"][i]:
			all_lines += 1
		if mixed["lines_visible"][i]:
			visible += 1
	print("  partial lines: %.0f%% of line pixels drawn" % (100.0 * visible / maxi(1, all_lines)))
	check(visible > 0 and visible < all_lines, "partial lines should draw some but not all")
	render_collage(mixed).save_png(out_dir.path_join("design_partial.png"))
	PictureSources.mandala_image(2003, {"sparsity": 0.6, "line_style": "partial"}).save_png(
			out_dir.path_join("design_partial_kit_source.png"))


## One line art, many collages: pattern seeds change the gems, not the lines;
## gem lines replace the metal; every line style and pattern shows up.
func test_pattern_seeds() -> void:
	print("Pattern seeds")
	var a := PictureSources.mandala_collage(2004, {"variant": "heart", "pattern_seed": 1})
	var b := PictureSources.mandala_collage(2004, {"variant": "heart", "pattern_seed": 1})
	var c := PictureSources.mandala_collage(2004, {"variant": "heart", "pattern_seed": 2})
	check(a["slots"].size() == b["slots"].size() and a["slots"][0]["x"] == b["slots"][0]["x"],
			"same pattern seed gave a different collage")
	check(a["slots"].size() != c["slots"].size() or a["slots"][0]["x"] != c["slots"][0]["x"],
			"another pattern seed gave the same collage")
	check(a["source"] == c["source"], "pattern seed changed the line art")

	var styles := {}
	var settings := {}
	for line_style in GemLines.STYLES:
		var p := PictureSources.mandala_collage(2005, {"variant": "snowflake", "setting": "gems", "line_gems": line_style})
		check(p["setting"] == "gems" and p["line_gems"] == line_style, "line_gems %s not honored" % line_style)
		check(not 255 in p["lines_visible"], "gem lines should draw no metal")
		var line_slots := 0
		var sizes := {}
		for s in p["slots"]:
			if p["regions"][s["region"]]["kind"] == "line":
				line_slots += 1
				sizes[snappedf(s["width"], 0.5)] = true
		check(line_slots > 50, "line_gems %s placed only %d line stones" % [line_style, line_slots])
		if line_style in ["taper", "pulse", "ramp", "radial", "hub", "pearls"]:
			check(sizes.size() >= 3, "line_gems %s should vary stone sizes" % line_style)
		var overlaps := count_overlaps(p["slots"], p["width"] * 0.002)
		check(overlaps == 0, "line_gems %s: %d overlapping slot pairs" % [line_style, overlaps])
		render_collage(p).save_png(out_dir.path_join("lines_%s.png" % line_style))
	var in_range := 0
	var sequences := 0
	for i in 12:
		var p := PictureSources.mandala_collage(2010 + i % 4, {"pattern_seed": i})
		settings[p["setting"]] = settings.get(p["setting"], 0) + 1
		var n: int = p["slots"].size()
		check(n >= CollageGenerator.MIN_SLOTS and n <= CollageGenerator.MAX_SLOTS,
				"pattern %d: %d stones, outside %d-%d" % [i, n, CollageGenerator.MIN_SLOTS, CollageGenerator.MAX_SLOTS])
		check(p["gem_types"] <= CollageGenerator.GEM_TYPES_MAX, "pattern %d: %d gem types" % [i, p["gem_types"]])
		check(p["gem_types"] == p["gem_kinds"].size(), "pattern %d: gem_types disagrees with gem_kinds" % i)
		if p["gem_types"] >= CollageGenerator.GEM_TYPES_MIN:
			in_range += 1
		# A line that repeats a sequence keeps one distinct gem type per step.
		var step_types := {}
		for sl in p["slots"]:
			if sl.get("seq", -1) >= 0:
				var line := "%d|%d" % [sl["region"], sl["part"]]
				if not step_types.has(line):
					step_types[line] = {}
				var t := "%s|%s" % [sl["shape"], sl["target_gem"]]
				var steps: Dictionary = step_types[line]
				if not steps.has(sl["seq"]):
					steps[sl["seq"]] = t
				check(steps[sl["seq"]] == t, "pattern %d: a sequence step changes type along its line" % i)
		for line in step_types:
			var types: Array = step_types[line].values()
			sequences += 1
			for x in types.size():
				for y in range(x + 1, types.size()):
					check(types[x] != types[y], "pattern %d: two steps of a line sequence share a gem type" % i)
		for r in p["regions"]:
			if r["kind"] == "area":
				styles[r["style"]] = true
	print("  settings %s, patterns %s, %d of 12 with %d-%d gem types, %d sequence lines" % [settings, styles.keys(),
			in_range, CollageGenerator.GEM_TYPES_MIN, CollageGenerator.GEM_TYPES_MAX, sequences])
	check(sequences > 0, "no line repeated a sequence of stones")
	# Busy radial pictures can run out of parts to vary; most reach the range.
	check(in_range >= 8, "only %d of 12 collages reached %d gem types" % [in_range, CollageGenerator.GEM_TYPES_MIN])
	check(settings.get("gems", 0) > settings.get("metal", 0), "gem lines should be the usual setting")
	for style in ["echo", "halo", "spine", "solitaire"]:
		check(styles.has(style), "pattern %s never used" % style)


## Symmetric pictures get symmetric stones: turned by one repeat, nearly
## every stone of an unframed mandala lands on a matching one. Junctions
## that thinning put a pixel or two apart keep gem lines a little lower.
## Most gem-line pictures get bold lines through the middle.
func test_symmetry() -> void:
	print("Symmetry")
	var bold := 0
	for i in 6:
		var seed_value := 3100 + i
		var p := PictureSources.mandala_collage(seed_value, {"variant": "mandala", "frame": false, "zoom": false,
				"setting": "metal" if i % 3 == 0 else "gems", "pattern_seed": i})
		var share := turn_match(p)
		print("  seed %d: %s, %d stones, %.0f%% match a turn later, %d bold lines" % [seed_value, p["setting"],
				p["slots"].size(), share * 100.0, p["bold_lines"]])
		check(share >= (0.9 if p["setting"] == "metal" else 0.7), "seed %d: only %.0f%% of stones symmetric" % [
				seed_value, share * 100.0])
		if p["bold_lines"] > 0:
			bold += 1
	check(bold >= 2, "only %d of 4 gem-line pictures got bold lines" % bold)

	# Lines in the styles of one size grow, shrink or swell along some strokes.
	var graded := 0
	for i in 3:
		var p := PictureSources.mandala_collage(3200 + i, {"variant": "mandala", "setting": "gems", "line_gems": "beads",
				"pattern_seed": i})
		var sizes := {}
		for sl in p["slots"]:
			if p["regions"][sl["region"]]["kind"] == "line" and sl["part"] < GemLines.NODE_PARTS:
				if not sizes.has(sl["part"]):
					sizes[sl["part"]] = []
				sizes[sl["part"]].append(sl["width"])
		for part in sizes:
			if sizes[part].size() >= 4 and sizes[part].max() >= sizes[part].min() * 1.5:
				graded += 1
	print("  %d classes of bead lines change size along their strokes" % graded)
	check(graded >= 3, "only %d classes of bead lines change size" % graded)

	# Over the stone limit, whole elements are left out instead of growing every stone.
	var capped := PictureSources.mandala_collage(3110, {"variant": "mandala", "setting": "gems", "pattern_seed": 1,
			"max_slots": 1200})
	print("  capped at 1200: %d stones, %d elements left out, unit %.1f" % [capped["slots"].size(), capped["dropped"],
			capped["unit"]])
	check(capped["dropped"] > 0, "nothing was left out over the stone limit")
	check(capped["slots"].size() <= 1200, "%d stones over a limit of 1200" % capped["slots"].size())


## Share of a mandala's stones (within its rings, short of the silhouette)
## that land on a stone of about the same size when the picture turns by
## one repeat (half the folds past 8, as centers repeat half as often).
static func turn_match(p: Dictionary) -> float:
	var folds: int = p["source"]["mandala"]["folds"]
	if folds > 8:
		folds /= 2
	var c := Vector2(p["width"], p["height"]) / 2.0
	var grid := {}
	for sl in p["slots"]:
		var k := Vector2i(int(sl["x"] / 8.0), int(sl["y"] / 8.0))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(sl)
	var hit := 0
	var counted := 0
	for sl in p["slots"]:
		var at := Vector2(sl["x"], sl["y"])
		if at.distance_to(c) > p["width"] * 0.38:
			continue
		counted += 1
		var q := c + (at - c).rotated(TAU / folds)
		var cell := Vector2i(int(q.x / 8.0), int(q.y / 8.0))
		var found := false
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				for o in grid.get(cell + Vector2i(dx, dy), []):
					if Vector2(o["x"], o["y"]).distance_to(q) < 2.5 and absf(o["width"] - sl["width"]) <= 0.15 * sl["width"] + 0.5:
						found = true
		if found:
			hit += 1
	return float(hit) / maxi(1, counted)


func test_gem_cuts() -> void:
	print("Gem cuts")
	# Every shape's mesh in every cut covers its outline once, facets facing up.
	var meshes := 0
	for shape: String in GemCuts.BY_SHAPE:
		var girdle := GemMesh.girdle_points(shape)
		var outline := 0.0
		for i in girdle.size():
			outline += (girdle[i][1] as Vector2).cross(girdle[(i + 1) % girdle.size()][1])
		outline = absf(outline) / 2.0
		for cut: String in GemCuts.ALL:
			var arrays := GemMesh.build(shape, cut).surface_get_arrays(0)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var covered := 0.0
			var down := 0
			for t in range(0, v.size(), 3):
				var a := Vector2(v[t].x, v[t].z)
				covered += absf((Vector2(v[t + 1].x, v[t + 1].z) - a).cross(Vector2(v[t + 2].x, v[t + 2].z) - a)) / 2.0
				if n[t].y <= 0.0:
					down += 1
			check(absf(covered / outline - 1.0) < 0.02 and down == 0, "%s %s mesh covers %.3f of its outline, %d facets down"
					% [shape, cut, covered / outline, down])
			meshes += 1
	# Every stone gets a cut its shape has; stones of one part share it.
	var cuts := {}
	for i in 3:
		var p := PictureSources.mandala_collage(3300 + i, {"variant": MandalaGenerator.VARIANTS[i], "pattern_seed": i})
		var by_part := {}
		for sl in p["slots"]:
			check(sl.get("cut", "") in GemCuts.for_shape(sl["shape"]), "a %s stone cut %s" % [sl["shape"], sl.get("cut")])
			cuts[sl["cut"]] = true
			var key := "%d|%d|%s|%s" % [p["regions"][sl["region"]]["group"], sl["part"], sl["shape"],
					(sl["target_color"] as Color).to_html()]
			if by_part.has(key):
				check(by_part[key] == sl["cut"], "seed %d: one part in two cuts" % (3300 + i))
			by_part[key] = sl["cut"]
	print("  %d meshes, cuts used %s" % [meshes, cuts.keys()])
	check(cuts.size() >= 3, "only %d cuts used in 3 pictures" % cuts.size())


func test_board_light() -> void:
	print("Board light")
	# Poses: which way is up in the phone's axes (x right, y up the screen,
	# z out of it) when the picture appeared and now, and how far it spun
	# about the vertical on the way.
	var upright := Vector3(0.0, 1.0, 0.0)
	var flat := Vector3(0.0, 0.0, 1.0)
	var tilt := func(up: Vector3, axis: Vector3, degrees: float) -> Vector3: return up.rotated(axis, deg_to_rad(degrees))
	var poses := {
		"held still": [upright, upright, 0.0],
		"upright, tilted back 20 degrees": [upright, tilt.call(upright, Vector3.RIGHT, 20.0), 0.0],
		"upright, turned 30 degrees left": [upright, upright, deg_to_rad(30.0)],
		"upright, turned 30 degrees right": [upright, upright, deg_to_rad(-30.0)],
		"flat, tilted 30 degrees left": [flat, tilt.call(flat, Vector3.UP, -30.0), 0.0],
		"flat, tilted 30 degrees right": [flat, tilt.call(flat, Vector3.UP, 30.0), 0.0],
		"upside down": [upright, -upright, 0.0],
		"lying face down": [upright, Vector3(0.0, 0.0, -1.0), 0.0],
		"spun half round": [upright, upright, PI],
	}
	var board := GemBoard3D.new()
	board.use_sensor = false
	board.update_light()
	var rest := board.key_dir
	var side := {}
	for what: String in poses:
		board.turn = GemBoard3D.phone_turn(poses[what][0], poses[what][1], poses[what][2])
		board.update_light()
		var key := board.key_dir
		var moved := rad_to_deg(key.angle_to(rest))
		var height := rad_to_deg(asin(key.y))
		side[what] = key.x
		print("  %s: light moves %.0f degrees, %.0f degrees above the paper, from x %.2f" % [what, moved, height, key.x])
		if what == "held still":
			check(moved < 0.5, "the light moved %.1f degrees with the phone held still" % moved)
		elif what == "upright, tilted back 20 degrees":
			check(moved > 15.0, "the light moved only %.1f degrees with the phone %s" % [moved, what])
		check(height >= rad_to_deg(GemBoard3D.MIN_KEY_ELEVATION) - 0.5, "the light fell to %.0f degrees, %s" % [height, what])
	# Side to side: the light crosses over the stones.
	for pair in [["flat, tilted 30 degrees left", "flat, tilted 30 degrees right"],
			["upright, turned 30 degrees left", "upright, turned 30 degrees right"]]:
		var a: float = side[pair[0]]
		var b: float = side[pair[1]]
		check(a * b < 0.0 and minf(absf(a), absf(b)) > 0.25, "%s and %s leave the light on one side (x %.2f, %.2f)"
				% [pair[0], pair[1], a, b])
	board.free()


func test_kits() -> void:
	print("Kits")
	var src := PictureSources.mandala_image(7, {"theme": "ocean"})
	src.save_png(out_dir.path_join("kit_source_7.png"))
	for size in KitGenerator.BOARD_SIZES:
		var t0 := Time.get_ticks_msec()
		var kit := KitGenerator.generate(src, {"size": size, "colors": 20, "seed": 7})
		var ms := Time.get_ticks_msec() - t0
		var w: int = kit["width"]
		var h: int = kit["height"]
		var cells: PackedByteArray = kit["cells"]
		var palette: Array = kit["palette"]
		check(cells.size() == w * h, "kit %s: cell count" % size)
		var max_index := 0
		for v in cells:
			max_index = maxi(max_index, v)
		check(max_index < palette.size(), "kit %s: cell refers to missing palette entry" % size)
		check(palette.size() <= 20, "kit %s: %d colors" % [size, palette.size()])
		var isolated := KitGenerator.count_isolated(PackedInt32Array(Array(cells)), w, h)
		print("  %s %dx%d  %d colors  %d isolated left  %d ms" % [size, w, h, palette.size(), isolated, ms])
		check(isolated < w * h * 0.01, "kit %s: %d isolated cells" % [size, isolated])
		render_kit(kit).save_png(out_dir.path_join("kit_7_%s.png" % size))
	# Pictures map only to colors she owns.
	var owned := Palettes.starter_gems().slice(0, 8)
	var owned_ids := []
	for g in owned:
		owned_ids.append(g["id"])
	var owned_kit := KitGenerator.generate(src, {"size": "small", "colors": 16, "gems": owned})
	for entry in owned_kit["palette"]:
		check(entry["gem_color_id"] in owned_ids, "kit used %s, which she doesn't own" % entry["gem_color_id"])


func test_photo_line_art() -> void:
	print("Photo to line art")
	var photo := synthetic_photo(400, 300)
	photo.save_png(out_dir.path_join("photo_source.png"))
	for detail in [0.0, 1.0]:
		var p := PictureSources.photo_collage(photo, {"detail": detail})
		print("  detail %.1f: %d regions, %d slots" % [detail, p["regions"].size(), p["slots"].size()])
		check(p["regions"].size() >= 4, "photo detail %.1f: %d regions" % [detail, p["regions"].size()])
		render_collage(p).save_png(out_dir.path_join("photo_collage_detail_%d.png" % int(detail * 10)))
	var kit := KitGenerator.generate(photo, {"size": "medium", "colors": 24})
	render_kit(kit).save_png(out_dir.path_join("photo_kit.png"))


func test_json_round_trip() -> void:
	print("JSON round trip")
	var p := PictureSources.mandala_collage(5, {"variant": "flower"})
	var back := PatternIO.from_json(PatternIO.to_json(p))
	check(back["lines"] == p["lines"], "collage lines changed")
	check(back["slots"].size() == p["slots"].size(), "collage slot count changed")
	check(back["slots"][0]["target_color"] is Color, "slot color not decoded")
	check(back["regions"][0]["centroid"] is Vector2, "centroid not decoded")
	var kit := KitGenerator.generate(PictureSources.mandala_image(5, {}), {})
	var kit_back := PatternIO.from_json(PatternIO.to_json(kit))
	check(kit_back["cells"] == kit["cells"], "kit cells changed")
	check(kit_back["width"] is int, "width not an int")


## Game puzzles use only what she has unlocked: the starting shapes in
## their one cut, the starting colors, no frame; recoloring keeps the slots.
func test_game_puzzles() -> void:
	print("Game puzzles")
	var unlocks := GemCatalog.default_unlocks()
	check(unlocks["shapes"].size() * 2 == GemCatalog.ALL_SHAPES.size(), "not half the shapes to start")
	var colors := {}
	for g in GemCatalog.unlocked_gems(unlocks):
		colors[g["id"]] = true
	check(colors.size() == 10, "expected 10 starting colors, got %d" % colors.size())
	for seed_value in [3, 11, 27]:
		var request := {"type": "mandala", "seed": seed_value, "pattern_seed": seed_value * 7, "theme": "rainbow"}
		var p := PuzzleMaker.make(request, unlocks)
		var n: int = p["slots"].size()
		check(n >= CollageGenerator.MIN_SLOTS, "seed %d: only %d slots" % [seed_value, n])
		check(not p["source"].has("frame"), "seed %d: framed" % seed_value)
		var bad := 0
		for s in p["slots"]:
			var cuts: Array = unlocks["shapes"].get(s["shape"], [])
			if not s.get("cut", "") in cuts or not colors.has(str(s["target_gem"])):
				bad += 1
		check(bad == 0, "seed %d: %d stones use locked shapes, cuts or colors" % [seed_value, bad])
		var again := PuzzleMaker.make({"type": "mandala", "seed": seed_value, "pattern_seed": seed_value * 7,
				"theme": "ocean"}, unlocks)
		check(again["lines"] == p["lines"], "seed %d: recoloring changed the lines" % seed_value)
	var restricted := [{"shape": "star", "size": 10.0, "width": 10.0}, {"shape": "kite", "size": 12.0, "width": 5.0},
			{"shape": "emerald", "size": 12.0, "width": 4.0}]
	GemVariety.restrict(restricted, {"round": ["brilliant"]})
	for s in restricted:
		check(s["shape"] == "round" and s["size"] == s["width"], "restrict gave %s %.1f x %.1f" % [s["shape"], s["size"],
				s["width"]])


## Progress saves bit by bit and comes back the same.
func test_saves() -> void:
	print("Saves")
	var placed := PackedByteArray()
	placed.resize(37)
	for i in [0, 5, 8, 36]:
		placed[i] = 1
	var id := "test_%d" % Time.get_ticks_usec()
	check(SaveStore.save_progress(id, placed) == OK, "progress didn't save")
	check(SaveStore.load_progress(id, placed.size()) == placed, "progress came back different")
	DirAccess.remove_absolute("%s/%s.progress" % [SaveStore.DIR, id])


# --- helpers -----------------------------------------------------------------

## Draws line art (as mandala_lines returns it) into cell i of a 6-wide sheet.
func sheet_cell(sheet: Image, lines: Dictionary, i: int, cell: int) -> void:
	var w: int = lines["width"]
	var h: int = lines["height"]
	var mask: PackedByteArray = lines["mask"]
	var art := Image.create(w, h, false, Image.FORMAT_RGBA8)
	art.fill(Color.WHITE)
	for y in h:
		for x in w:
			if mask[y * w + x]:
				art.set_pixel(x, y, PictureSources.LINE_COLOR)
	art.resize(cell, cell, Image.INTERPOLATE_BILINEAR)
	sheet.blit_rect(art, Rect2i(0, 0, cell, cell), Vector2i((i % 6) * cell, (i / 6) * cell))


## Pixels of a mask that differ from their mirror image across the vertical
## center line.
func mirror_mismatch(mask: PackedByteArray, w: int, h: int) -> int:
	var n := 0
	for y in h:
		for x in w / 2:
			if (mask[y * w + x] != 0) != (mask[y * w + w - 1 - x] != 0):
				n += 1
	return n


## A blobby test "photo": sky, sun, hills and a flower, with some noise.
func synthetic_photo(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in h:
		for x in w:
			var p := Vector2(x, y)
			var c := Color("#7cc4f2").lerp(Color("#fbeaa0"), float(y) / h * 0.6)
			if p.distance_to(Vector2(w * 0.78, h * 0.22)) < h * 0.12:
				c = Color("#f9cf2a")
			if y > h * 0.62 + sin(x * 0.02) * h * 0.06:
				c = Color("#5aa83c")
			if y > h * 0.8 + sin(x * 0.035 + 1.0) * h * 0.04:
				c = Color("#22603a")
			var f := Vector2(w * 0.3, h * 0.55)
			var a := (p - f).angle()
			if p.distance_to(f) < h * (0.1 + 0.05 * cos(a * 6.0)):
				c = Color("#e8517d")
			if p.distance_to(f) < h * 0.045:
				c = Color("#f28b1c")
			var n := rng.randf_range(-0.04, 0.04)
			img.set_pixel(x, y, Color(c.r + n, c.g + n, c.b + n))
	return img


## Software render of a collage; sets meta "stray" to the fraction of slot
## pixels that land on lines or outside the picture.
func render_collage(p: Dictionary) -> Image:
	var w: int = p["width"]
	var h: int = p["height"]
	var lines: PackedByteArray = p["lines"]
	var drawn: PackedByteArray = p.get("lines_visible", lines)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("#2a1f3d"))
	var total := 0
	var stray := 0
	for slot in p["slots"]:
		# Line gems sit in the line channel on purpose.
		var on_line: bool = p["regions"][slot["region"]].get("kind", "area") == "line"
		var poly := GemShapes.slot_polygon(slot, 16)
		var box := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			box = box.expand(v)
		var c: Color = slot["target_color"]
		for y in range(maxi(0, int(box.position.y)), mini(h, int(box.end.y) + 1)):
			for x in range(maxi(0, int(box.position.x)), mini(w, int(box.end.x) + 1)):
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
					if not on_line:
						total += 1
						if lines[y * w + x]:
							stray += 1
					img.set_pixel(x, y, c)
	var gold := Color("#d4af5a")
	for i in w * h:
		if drawn[i]:
			img.set_pixel(i % w, i / w, gold)
	img.set_meta("stray", float(stray) / maxi(1, total))
	return img


func render_kit(kit: Dictionary, cell: int = 8) -> Image:
	var w: int = kit["width"]
	var h: int = kit["height"]
	var cells: PackedByteArray = kit["cells"]
	var img := Image.create(w * cell, h * cell, false, Image.FORMAT_RGBA8)
	img.fill(Color("#f4eee6"))
	for y in h:
		for x in w:
			var c: Color = kit["palette"][cells[y * w + x]]["color"]
			img.fill_rect(Rect2i(x * cell + 1, y * cell + 1, cell - 2, cell - 2), c)
	return img


## Pairs of slots in the same region whose capsules come closer than
## `tolerance` px of touching.
func count_overlaps(slots: Array, tolerance: float) -> int:
	var cell := 32.0
	var grid := {}
	for s in slots:
		var key := Vector2i(floori(s["x"] / cell), floori(s["y"] / cell))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(s)
	var n := 0
	for a: Dictionary in slots:
		var ka := Vector2i(floori(a["x"] / cell), floori(a["y"] / cell))
		var ra: float = a["width"] / 2.0
		var ca := Vector2(a["x"], a["y"])
		var ha: Vector2 = Vector2.from_angle(a["rotation"]) * (a["size"] / 2.0 - ra)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for b: Dictionary in grid.get(ka + Vector2i(dx, dy), []):
					if b["id"] <= a["id"] or b["region"] != a["region"]:
						continue
					var rb: float = b["width"] / 2.0
					var cb := Vector2(b["x"], b["y"])
					if ca.distance_to(cb) > a["size"] / 2.0 + b["size"] / 2.0:
						continue
					var hb: Vector2 = Vector2.from_angle(b["rotation"]) * (b["size"] / 2.0 - rb)
					var pts := Geometry2D.get_closest_points_between_segments(ca - ha, ca + ha, cb - hb, cb + hb)
					if pts[0].distance_to(pts[1]) < ra + rb - tolerance:
						n += 1
	return n

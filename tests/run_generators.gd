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
	test_swirls()
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
	test_hints()
	test_game_puzzles()
	test_saves()
	test_packs()
	test_catalog_complete()
	test_old_profiles()
	test_photo_orientation()
	test_photo_edges()
	test_kit_puzzles()

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


## 30 swirls in a row: every layout and outline shows up, no outline repeats
## within 8 pictures, every line has a family, and each has closed regions.
## Families carry into the collage: a pebbles swirl's stones share groups,
## and its gem lines form far fewer classes than lines. Writes a contact
## sheet.
func test_swirls() -> void:
	print("Swirls")
	var count := 30
	var cell := 256
	var sheet := Image.create(cell * 6, cell * 5, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	var recent := []
	var seen := {}
	for i in count:
		var seed_value := 7000 + i
		var lines := PictureSources.mandala_lines(seed_value, {"variant": "swirl", "recent": recent, "frame": false})
		var m: Dictionary = lines["mandala"]
		var sw: Dictionary = m["swirl"]
		var shapes := recent.slice(maxi(0, recent.size() - 8)).map(func(r: Dictionary) -> String: return r["shape"])
		check(not sw["shape"] in shapes, "seed %d: %s outline again within 8" % [seed_value, sw["shape"]])
		recent.append(sw)
		seen[sw["layout"]] = true
		seen[sw["shape"]] = true
		var w: int = lines["width"]
		var h: int = lines["height"]
		var map := RegionMap.build(lines["mask"], w, h, int(w * h * 0.0005))
		print("  seed %d %-9s %-8s %-5s motifs %-26s %3d regions" % [seed_value, sw["layout"], sw["shape"],
				"patch" if sw["patch"] else "", " + ".join(PackedStringArray(sw["motifs"])), map.regions.size()])
		check(m["symmetry"] == "none", "seed %d: swirls aren't symmetric" % seed_value)
		check(m["families"].size() == m["polylines"].size(), "seed %d: lines without a family" % seed_value)
		check(map.regions.size() >= 5, "seed %d: only %d regions" % [seed_value, map.regions.size()])
		sheet_cell(sheet, lines, i, cell)
	for choice in SwirlGenerator.LAYOUTS + SwirlGenerator.SHAPES:
		check(seen.has(choice), "%s never showed up in %d swirls" % [choice, count])
	sheet.save_png(out_dir.path_join("swirls_contact_sheet.png"))

	var opts := {"variant": "swirl", "layout": "pebbles", "frame": false, "setting": "gems", "line_gems": "beads"}
	var pebbles := PictureSources.mandala_lines(7100, opts)
	var p := PictureSources.mandala_collage(7100, opts, pebbles)
	var areas := 0
	var groups := {}
	var classes := {}
	for r in p["regions"]:
		if r["kind"] == "area":
			areas += 1
			groups[r["group"]] = true
	for sl in p["slots"]:
		if p["regions"][sl["region"]]["kind"] == "line" and sl["part"] < GemLines.NODE_PARTS:
			classes[sl["part"]] = true
	var graph := Contours.centerlines(pebbles["mask"], p["width"], p["height"], p["unit"] * 1.5)
	print("  pebbles collage: %d areas in %d groups, %d lines in %d classes" % [areas, groups.size(),
			graph["paths"].size(), classes.size()])
	check(groups.size() * 2 < areas, "pebbles: %d areas in %d groups" % [areas, groups.size()])
	check(classes.size() * 3 < graph["paths"].size(), "pebbles: %d line classes for %d lines" % [classes.size(),
			graph["paths"].size()])


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
		# A gem type only changes size, never shape (see GemVariety.even_aspects).
		var ratios := {}
		for s: Dictionary in slots:
			var key := GemVariety.type_key(s)
			var r: float = float(s["width"]) / float(s["size"])
			var seen: Vector2 = ratios.get(key, Vector2(r, r))
			ratios[key] = Vector2(minf(seen.x, r), maxf(seen.y, r))
		for key: String in ratios:
			check(ratios[key].y <= ratios[key].x * 1.01, "seed %d: gem type %s has proportions %.2f to %.2f" % [
					seed_value, key, ratios[key].x, ratios[key].y])
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


## A mesh's area seen from above (its triangles' xz) and how many of them
## face down.
static func _covers(mesh: ArrayMesh) -> Array:
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var covered := 0.0
	var down := 0
	for t in range(0, v.size(), 3):
		var a := Vector2(v[t].x, v[t].z)
		covered += absf((Vector2(v[t + 1].x, v[t + 1].z) - a).cross(Vector2(v[t + 2].x, v[t + 2].z) - a)) / 2.0
		down += int(n[t].y <= 0.0)
	return [covered, down]


func test_gem_cuts() -> void:
	print("Gem cuts")
	# Every shape's mesh in every cut covers its outline once, facets facing up;
	# so does the flat outline tiny stones draw as (fewer girdle points, so
	# nearly as much), and their facet picture covers as much as the mesh.
	var meshes := 0
	for shape: String in GemCuts.BY_SHAPE:
		var girdle := GemMesh.girdle_points(shape)
		var outline := 0.0
		for i in girdle.size():
			outline += (girdle[i][1] as Vector2).cross(girdle[(i + 1) % girdle.size()][1])
		outline = absf(outline) / 2.0
		var flat := _covers(GemMesh.get_outline_mesh(shape, 0.25))
		check(flat[0] / outline > 0.85 and flat[0] / outline < 1.02 and flat[1] == 0,
				"%s flat outline covers %.3f of its outline, %d faces down" % [shape, flat[0] / outline, flat[1]])
		for cut: String in GemCuts.ALL:
			var full := _covers(GemMesh.build(shape, cut))
			check(absf(full[0] / outline - 1.0) < 0.02 and full[1] == 0, "%s %s mesh covers %.3f of its outline, %d facets down"
					% [shape, cut, full[0] / outline, full[1]])
			var facets := GemMesh.get_facets(shape, cut)
			var texels := 0
			for y in range(1, facets.get_height() - 1):
				for x in range(1, facets.get_width() - 1):
					texels += int(facets.get_pixel(x, y).b > 0.5)
			var pictured := texels * 4.0 / (GemMesh.FACET_PX * GemMesh.FACET_PX)
			check(absf(pictured / outline - 1.0) < 0.04, "%s %s facet picture covers %.3f of its outline"
					% [shape, cut, pictured / outline])
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


## Packs give only new things, sell out once empty, take a pick or coins;
## daily picks come once a day and puzzle coins once per puzzle.
func test_packs() -> void:
	print("Packs")
	var profile := {"unlocks": GemCatalog.default_unlocks(), "wallet": {"coins": 0, "picks": 0},
			"daily": {"opened": "", "completed": ""}, "powers": {}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	check(Packs.open(profile, "colors", true, rng).is_empty(), "opened a pack with no picks")
	# Themes come with their colors, never from a pack.
	check(not Packs.PACKS.has("themes"), "there's still a theme pack")
	var before: Dictionary = profile["unlocks"].duplicate(true)
	for gem: String in GemCatalog.THEMES["reds"]["gems"]:
		Unlockables.grant(profile, {"kind": "color", "id": gem})
	check(Unlockables.themes_gained(before, profile["unlocks"]).has("reds"), "the reds didn't bring Ruby Reds")
	check(Packs.daily_open(profile) and not Packs.daily_open(profile), "daily pick not exactly once a day")
	var got := Packs.open(profile, "colors", true, rng)
	check(not got.is_empty() and got[0].get("kind") == "color" and Packs.picks(profile) == 0, "free pick didn't open a color pack")
	var meta := {}
	var r1 := Packs.puzzle_finished(profile, meta, false)
	var r2 := Packs.puzzle_finished(profile, meta, false)
	check(r1["coins"] == Packs.COINS_PER_PUZZLE and r1["pick"] and r2["coins"] == 0, "puzzle rewards %s then %s" % [r1, r2])
	check(Packs.puzzle_finished(profile, {}, true)["coins"] == 2 * Packs.COINS_PER_PUZZLE, "double coins didn't double")
	# Every 3 puzzles pay for a pack.
	check(Packs.PACK_PRICE == 3 * Packs.COINS_PER_PUZZLE, "a pack isn't 3 puzzles' coins")
	# Open every category until it sells out: never a repeat, and it all ends up unlocked.
	for pack: String in Packs.PACKS:
		if pack in ["powers", "all"]:
			continue
		var seen := {}
		var guard := 0
		while not Packs.sold_out(pack, profile) and guard < 200:
			guard += 1
			profile["wallet"]["coins"] = 1000
			var item: Dictionary = Packs.open(profile, pack, false, rng)[0]
			check(not seen.has(item["id"]), "%s pack repeated %s" % [pack, item["id"]])
			seen[item["id"]] = true
		check(Packs.sold_out(pack, profile), "%s pack never sold out" % pack)
	var unlocks: Dictionary = profile["unlocks"]
	check(unlocks["colors"].size() == GemCatalog.all_colors().size(), "not every color unlocked")
	check(GemCatalog.unlocked_themes(unlocks).size() == GemCatalog.THEMES.size(), "all colors didn't bring every theme")
	check(unlocks["shapes"].size() == GemCatalog.ALL_SHAPES.size(), "not every shape unlocked")
	for pair: Array in GemCatalog.all_cuts():
		check(GemCatalog.has_cut(unlocks, pair[0], pair[1]), "cut %s not unlocked" % [pair])
	# Everything needs two unlockables; only power-up packs stay available when complete.
	profile["wallet"]["coins"] = 1000
	check(Packs.sold_out("all", profile) and Packs.open(profile, "all", false, rng).is_empty(),
		"Everything sold a pack without two unlockables")
	var power: Dictionary = Packs.open(profile, "powers", false, rng)[0]
	check(power.get("kind") == "power" and Packs.charges(profile, power["id"]) > 0, "power-up pack gave %s" % power)
	check(Packs.spend(profile, power["id"]), "couldn't spend a power-up charge")


## Everything a catalog lists is complete and handled, so adding an item
## (or a kind) halfway fails here instead of quietly never showing up.
func test_catalog_complete() -> void:
	print("Catalog complete")
	var families: Array = GemVariety.ROUND_FAMILY + GemVariety.LONG_FAMILY + GemVariety.BOX_FAMILY
	check(GemCuts.BY_SHAPE.keys().size() == GemCatalog.ALL_SHAPES.size(), "GemCuts.BY_SHAPE and ALL_SHAPES differ")
	for shape: String in GemCatalog.ALL_SHAPES:
		check(GemCuts.BY_SHAPE.has(shape), "shape %s has no cuts" % shape)
		check(shape in families, "shape %s is in no GemVariety family, so no puzzle would use it" % shape)
		for cut: String in GemCuts.for_shape(shape):
			check(GemCuts.SHADER_STYLE.has(cut), "cut %s has no shader style" % cut)
	for t: String in GemCatalog.THEMES:
		for gem: String in GemCatalog.THEMES[t]["gems"]:
			check(GemCatalog.all_colors().any(func(g: Dictionary) -> bool: return g["id"] == gem),
					"theme %s uses unknown gem %s" % [t, gem])
	for id: String in GemCatalog.PUZZLES:
		check(GemCatalog.PUZZLES[id]["variant"] in MandalaGenerator.VARIANTS, "puzzle %s has an unknown variant" % id)
	var handled := {
		"feature": PuzzleMaker.FEATURES,
		"animation": load("res://scenes/game/play_screen.gd").FILL_STYLES,
		"finale": GemBoard3D.FINALES,
		"power": load("res://scenes/game/play_screen.gd").POWER_EFFECTS,
	}
	for kind: String in Unlockables.KINDS:
		var info: Dictionary = Unlockables.KINDS[kind]
		check(info["pack"] == "" or Packs.PACKS.has(info["pack"]), "kind %s comes from unknown pack %s" % [kind,
				info["pack"]])
		var ids := {}
		for item: Dictionary in Unlockables.items(kind):
			check(not ids.has(item["id"]), "%s id %s is listed twice" % [kind, item["id"]])
			ids[item["id"]] = true
			check(str(item.get("name", "")) != "" and str(item.get("about", "")) != "", "%s %s lacks a name or about" % [
					kind, item["id"]])
			if handled.has(kind):
				check(item["id"] in handled[kind], "%s %s isn't handled by the game" % [kind, item["id"]])
		for id in Unlockables.starting(kind):
			check(ids.has(id), "starting %s %s isn't in its catalog" % [kind, id])
	# At least 10 colors of every hue, and a theme mostly of each.
	for hue: String in GemCatalog.HUE_ORDER:
		var n := GemCatalog.all_colors().filter(func(g: Dictionary) -> bool: return g["hue"] == hue).size()
		check(n >= 10, "only %d %s colors" % [n, hue])
	for g in GemCatalog.all_colors():
		check(g["hue"] in GemCatalog.HUE_ORDER, "color %s has unknown hue %s" % [g["id"], g["hue"]])
	# Starting themes must come with the starting colors.
	for t: String in GemCatalog.STARTING_THEMES:
		check(GemCatalog.has_theme({"colors": GemCatalog.STARTING_COLORS}, t), "starting theme %s needs locked colors" % t)
	for pack: String in Packs.PACKS:
		if pack != "all":
			check(Unlockables.KINDS.values().any(func(k: Dictionary) -> bool: return k["pack"] == pack),
					"pack %s offers no kind" % pack)


## Profiles saved by earlier versions load with nothing lost: unlocks only
## grow (new starting items arrive, ids from a newer version stay), starting
## power-ups aren't given twice, and loading again changes nothing.
func test_old_profiles() -> void:
	print("Old profiles")
	# As version 0.3 saved it (profile version 1, no ledger), after a few packs.
	var v1 := {"version": 1.0, "unlocks": {"colors": ["ruby", "snow", "future_gem"], "shapes": {"round": ["brilliant",
			"rose"], "kite": ["brilliant"]}, "themes": ["rainbow"], "puzzles": ["mandala", "kit"], "features": [],
			"animations": ["pop", "fly", "spin"], "finales": ["ripple"], "stickers": ["star"]},
			"settings": {"fill_animation": "spin"}, "wallet": {"coins": 40.0, "picks": 1.0},
			"daily": {"opened": "2026-10-28"}, "powers": {"finder": 0.0, "finish_gem": 3.0},
			"puzzles": [{"id": "p1", "type": "mandala", "seed": 5.0, "total": 900.0, "filled": 12.0, "done": false}]}
	var before: Dictionary = JSON.parse_string(JSON.stringify(v1))
	var p := SaveStore.upgrade(JSON.parse_string(JSON.stringify(v1)))
	var u: Dictionary = p["unlocks"]
	for key: String in before["unlocks"]:
		var old: Variant = before["unlocks"][key]
		if old is Array:
			for id in old:
				check(id in u[key], "lost %s %s" % [key, id])
		else:
			for shape: String in old:
				for cut in old[shape]:
					check(cut in u["shapes"][shape], "lost cut %s|%s" % [shape, cut])
	for id: String in GemCatalog.STARTING_COLORS:
		check(id in u["colors"], "starting color %s didn't reach an old profile" % id)
	check(u["shapes"].has("oval"), "starting shape didn't reach an old profile")
	check(p["powers"]["finder"] == 0 and p["powers"]["finish_gem"] == 3, "starting power-ups given again: %s" % p["powers"])
	check(p["wallet"]["coins"] == 40 and p["settings"]["fill_animation"] == "spin", "old wallet or settings changed")
	check(p["puzzles"][0]["seed"] is int and p["puzzles"][0]["rewarded"] == false, "old puzzle meta not upgraded")
	var again := SaveStore.upgrade(JSON.parse_string(JSON.stringify(p)))
	check(JSON.stringify(again) == JSON.stringify(p), "upgrading twice changed the profile")
	# A brand-new player gets the starting charges, once.
	var fresh := SaveStore.upgrade({})
	check(fresh["powers"] == GemCatalog.STARTING_POWERS, "new player's power-ups %s" % fresh["powers"])
	check(SaveStore.upgrade(fresh)["powers"] == GemCatalog.STARTING_POWERS, "starting power-ups given twice")
	# Shader styles of the original cuts never move.
	check(GemCuts.SHADER_STYLE == {"brilliant": 0, "step": 1, "rose": 2, "checker": 3, "cabochon": 4},
			"cut shader styles changed: old gems would light differently")


## Photos load the right way up: a JPEG carrying each EXIF orientation (in
## either byte order) comes back turned or mirrored to match.
func test_photo_orientation() -> void:
	print("Photo orientation")
	# A 4x2 picture, as it should look: red top-left, green top-right, blue bottom-left.
	var want := Image.create(40, 20, false, Image.FORMAT_RGB8)
	want.fill(Color.WHITE)
	want.fill_rect(Rect2i(0, 0, 10, 10), Color.RED)
	want.fill_rect(Rect2i(30, 0, 10, 10), Color.GREEN)
	want.fill_rect(Rect2i(0, 10, 10, 10), Color.BLUE)
	for o in range(1, 9):
		for little in [true, false]:
			# Store it as the camera would: the inverse of what orientation o fixes.
			var stored := want.duplicate() as Image
			match o:
				2:
					stored.flip_x()
				3:
					stored.rotate_180()
				4:
					stored.flip_y()
				5:
					stored.flip_x()
					stored.rotate_90(COUNTERCLOCKWISE)
				6:
					stored.rotate_90(COUNTERCLOCKWISE)
				7:
					stored.flip_x()
					stored.rotate_90(CLOCKWISE)
				8:
					stored.rotate_90(CLOCKWISE)
			var jpg := _with_exif(stored.save_jpg_to_buffer(0.95), o, little)
			check(PhotoLoader.orientation(jpg) == o, "orientation %d read as %d" % [o, PhotoLoader.orientation(jpg)])
			var got := PhotoLoader.from_bytes(jpg)
			var ok := got != null and got.get_size() == want.get_size()
			if ok:
				for spot: Vector2i in [Vector2i(5, 5), Vector2i(35, 5), Vector2i(5, 15), Vector2i(35, 15)]:
					var a := got.get_pixelv(spot)
					var b := want.get_pixelv(spot)
					if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.3:
						ok = false
			check(ok, "orientation %d (%s) not upright" % [o, "II" if little else "MM"])
	check(PhotoLoader.orientation(want.save_png_to_buffer()) == 1, "a PNG has an orientation")


## Photo collages from edges: a clear subject on a plain background is cut
## out alone (and every region is closed), a landscape keeps the whole
## picture, and asking for either always gets it.
func test_photo_edges() -> void:
	print("Photo edges")
	var subject := Image.create(480, 360, false, Image.FORMAT_RGB8)
	var scenery := Image.create(480, 360, false, Image.FORMAT_RGB8)
	for y in 360:
		for x in 480:
			var t := float(y) / 360.0
			# A pale wall and table, with a bright flower-ish thing in front.
			var c := Color(0.82 - 0.1 * t, 0.8 - 0.1 * t, 0.76 - 0.05 * t)
			var d := Vector2(x, y).distance_to(Vector2(240, 180))
			var a := Vector2(x - 240, y - 180).angle()
			if d < 95.0 + 18.0 * sin(a * 6.0):
				c = Color(0.85, 0.2, 0.3) if d > 40.0 else Color(0.98, 0.8, 0.15)
			subject.set_pixel(x, y, c)
			# Sky, hills and water, each running edge to edge.
			var hill := 200.0 - 50.0 * absf(sin(x / 70.0))
			var s := Color(0.55, 0.72, 0.95).lerp(Color(0.8, 0.88, 1.0), t)
			if y > hill:
				s = Color(0.3, 0.55, 0.3)
			if y > 290:
				s = Color(0.25, 0.45, 0.7)
			scenery.set_pixel(x, y, s)
	var art := PhotoEdges.line_art(subject)
	check(art["subject"], "no subject found on a plain background: %s" % art.get("scores"))
	check(art["width"] < 480 and art["height"] < 360, "the subject wasn't cropped around")
	var map := RegionMap.build(art["mask"], art["width"], art["height"], 0)
	check(map.regions.size() >= 2, "subject line art has %d closed regions" % map.regions.size())
	var land := PhotoEdges.line_art(scenery)
	check(not land["subject"], "a landscape was cut down to a subject: %s" % land.get("scores"))
	check(not PhotoEdges.line_art(subject, {"subject": "off"})["subject"], "subject off still cut one out")
	check(PhotoEdges.line_art(scenery, {"subject": "on"})["subject"], "subject on found none")


## A JPEG with an EXIF block holding just an Orientation tag, put after SOI.
func _with_exif(jpg: PackedByteArray, o: int, little: bool) -> PackedByteArray:
	var tiff := PackedByteArray()
	var u16 := func(v: int) -> PackedByteArray:
		return PackedByteArray([v & 0xFF, v >> 8]) if little else PackedByteArray([v >> 8, v & 0xFF])
	var u32 := func(v: int) -> PackedByteArray:
		var b := PackedByteArray([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24])
		if not little:
			b.reverse()
		return b
	tiff.append_array("II".to_ascii_buffer() if little else "MM".to_ascii_buffer())
	tiff.append_array(u16.call(42))
	tiff.append_array(u32.call(8))
	tiff.append_array(u16.call(1))
	tiff.append_array(u16.call(0x0112))
	tiff.append_array(u16.call(3))
	tiff.append_array(u32.call(1))
	tiff.append_array(u16.call(o))
	tiff.append_array(u16.call(0))
	tiff.append_array(u32.call(0))
	var payload := "Exif".to_ascii_buffer()
	payload.append_array(PackedByteArray([0, 0]))
	payload.append_array(tiff)
	var seg := PackedByteArray([0xFF, 0xE1, (payload.size() + 2) >> 8, (payload.size() + 2) & 0xFF])
	seg.append_array(payload)
	var out := jpg.slice(0, 2)
	out.append_array(seg)
	out.append_array(jpg.slice(2))
	return out


## Kits and unlocked picture features: a kit uses only unlocked colors and
## drills, and unlocked frames show up. Photos make collages and kits.
func test_kit_puzzles() -> void:
	print("Kit puzzles")
	var unlocks := GemCatalog.default_unlocks()
	var colors := {}
	for g in GemCatalog.unlocked_gems(unlocks):
		colors[g["id"]] = true
	var kit := PuzzleMaker.make({"type": "kit", "seed": 12, "pattern_seed": 3, "theme": "ocean"}, unlocks)
	check(kit.get("kind") == "kit" and kit["slots"].size() >= 2000, "kit has %d slots" % kit["slots"].size())
	var bad := 0
	for s in kit["slots"]:
		if not s["shape"] in ["round", "square"] or not colors.has(str(s["target_gem"])):
			bad += 1
	check(bad == 0, "kit: %d drills in locked shapes or colors" % bad)
	var framed := 0
	unlocks["features"] = ["frames", "backgrounds"]
	for seed_value in [1, 2, 3, 4]:
		var p := PuzzleMaker.make({"type": "flower", "seed": seed_value, "pattern_seed": 1, "theme": "garden"}, unlocks)
		if p["source"].has("frame"):
			framed += 1
	check(framed > 0, "no frames with frames unlocked")
	# Photo puzzles: a made-up photo becomes a collage and a kit, in unlocked colors only.
	var photo := Image.create(400, 300, false, Image.FORMAT_RGB8)
	for y in 300:
		for x in 400:
			var c := Color.from_hsv(fposmod(x / 400.0 + 0.3 * sin(y / 40.0), 1.0), 0.7, 0.4 + 0.5 * float(y) / 300.0)
			if Vector2(x, y).distance_to(Vector2(200, 150)) < 70:
				c = Color("#f7e04a")
			photo.set_pixel(x, y, c)
	for kind: String in GemCatalog.PHOTO_MODES:
		var req := PuzzleMaker.new_request(kind, "")
		req["photo"] = photo
		var p := PuzzleMaker.make(req, GemCatalog.default_unlocks())
		var off := 0
		for s in p["slots"]:
			if not colors.has(str(s["target_gem"])):
				off += 1
		check(p["slots"].size() >= 300 and off == 0, "%s: %d slots, %d in locked colors" % [kind, p["slots"].size(), off])
		check(not p["puzzle"].has("photo"), "%s keeps the photo in its request" % kind)
		check(PatternIO.from_json(PatternIO.to_json(p))["slots"].size() == p["slots"].size(), "%s didn't save" % kind)
	# A photo kit in the photo's own colors: that many at most, exact, no gem ids.
	var own := PuzzleMaker.new_request("photo_kit", "")
	own["photo"] = photo
	own["kit_colors"] = 12
	var kit_own := PuzzleMaker.make(own, GemCatalog.default_unlocks())
	var hexes := {}
	var with_gem := 0
	for s in kit_own["slots"]:
		hexes[(s["target_color"] as Color).to_html(false)] = true
		if s["target_gem"] != null:
			with_gem += 1
	check(hexes.size() <= 12 and hexes.size() >= 6 and with_gem == 0, "own-color kit: %d colors, %d with gems" % [
			hexes.size(), with_gem])
	# Kit sizes: the longer side is the size's drills, the other follows the picture.
	var wide := Image.create(300, 200, false, Image.FORMAT_RGB8)
	check(KitGenerator.board_long(wide, 250) == Vector2i(250, 167), "x-large board %s" % KitGenerator.board_long(wide, 250))
	var tall := Image.create(200, 300, false, Image.FORMAT_RGB8)
	check(KitGenerator.board_long(tall, 90) == Vector2i(60, 90), "medium tall board %s" % KitGenerator.board_long(tall, 90))
	var xl := PuzzleMaker.new_request("photo_kit", "")
	xl["photo"] = photo
	xl["kit_size"] = "xlarge"
	var big := PuzzleMaker.make(xl, GemCatalog.default_unlocks())
	var grid: Dictionary = big["kit_grid"]
	check(grid["cols"] == 250 and grid["rows"] == 188 and big["slots"].size() == 250 * 188, "x-large photo kit %dx%d" % [
			grid["cols"], grid["rows"]])
	# Kits save as their grid and come back slot for slot.
	var compact := big.duplicate()
	compact.erase("slots")
	var text := PatternIO.to_json(compact)
	check(text.length() < 200000, "x-large kit saves as %d KB" % (text.length() / 1024))
	var again := PatternIO.from_json(text)
	again["slots"] = PuzzleMaker.kit_slots(again)
	var same: bool = again["slots"].size() == big["slots"].size()
	for k in [0, 1234, big["slots"].size() - 1]:
		var a: Dictionary = again["slots"][k]
		var b: Dictionary = big["slots"][k]
		same = same and a["x"] == b["x"] and a["y"] == b["y"] and a["target_gem"] == b["target_gem"] and \
				(a["target_color"] as Color).to_html() == (b["target_color"] as Color).to_html()
	check(same, "kit grid didn't come back as the same slots")
	var mk := PuzzleMaker.make({"type": "kit", "seed": 9, "pattern_seed": 2, "theme": "rainbow", "kit_size": "small"},
			GemCatalog.default_unlocks())
	check(mk["kit_grid"]["cols"] == 50 and mk["kit_grid"]["rows"] == 50, "small diamond kit %dx%d" % [
			mk["kit_grid"]["cols"], mk["kit_grid"]["rows"]])
	var back := PatternIO.from_json(PatternIO.to_json(kit_own))
	check(back["slots"][0]["target_gem"] == null and back["slots"][0]["target_color"] is Color, "own-color kit didn't save")


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


func test_hints() -> void:
	print("Hints")
	var meta := {}
	Hints.upgrade(meta)
	check(meta["hints"] == Hints.START and meta["hint_ms"] == 0, "a puzzle starts with %d hint" % Hints.START)
	check(Hints.spend(meta) and not Hints.spend(meta), "spending: one, then none")
	check(not Hints.tick(meta, Hints.EVERY_MS - 1), "no hint a moment early")
	check(is_equal_approx(Hints.progress(meta), 1.0 - 1.0 / Hints.EVERY_MS), "progress just short of full")
	check(Hints.tick(meta, 1) and meta["hints"] == 1 and meta["hint_ms"] == 0, "a hint every %d ms" % Hints.EVERY_MS)
	Hints.tick(meta, Hints.EVERY_MS * 10)
	check(meta["hints"] == Hints.MAX and meta["hint_ms"] == 0, "at most %d banked" % Hints.MAX)
	check(Hints.progress(meta) == 0.0, "no fill while full")
	Hints.spend(meta)
	check(not Hints.tick(meta, 1000) and meta["hint_ms"] == 1000, "the clock starts again below the cap")

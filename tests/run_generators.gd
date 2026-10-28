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
	test_collages()
	test_design_plans()
	test_kits()
	test_photo_line_art()
	test_json_round_trip()

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
		})
		var ms := Time.get_ticks_msec() - t0
		var slots: Array = p["slots"]
		var regions: Array = p["regions"]
		var empty := 0
		var sparse := 0
		for r in regions:
			if r["empty"]:
				empty += 1
			if r["fill"] != "full":
				sparse += 1
		var coverage := CollageGenerator.mean_coverage(p)
		var img := render_collage(p)
		var overlaps := count_overlaps(slots, p["width"] * 0.002)
		print(("  seed %d %-9s %3d regions (%d empty, %d sparse) lines %-7s %4d slots  coverage %.0f%%"
				+ "  overlaps %d  stray px %.2f%%  %d ms") % [
			seed_value, variant, regions.size(), empty, sparse, p["line_style"], slots.size(), coverage * 100.0,
			overlaps, img.get_meta("stray") * 100.0, ms])
		check(regions.size() >= 5, "seed %d: only %d regions" % [seed_value, regions.size()])
		check(float(empty) / regions.size() < 0.25,
				"seed %d: %d of %d regions too thin for stones" % [seed_value, empty, regions.size()])
		check(coverage > 0.55, "seed %d: coverage %.2f" % [seed_value, coverage])
		check(overlaps == 0, "seed %d: %d overlapping slot pairs" % [seed_value, overlaps])
		check(img.get_meta("stray") < 0.02, "seed %d: slots spill onto lines" % seed_value)
		img.save_png(out_dir.path_join("collage_%d_%s.png" % [seed_value, variant]))


## Sparse fills and hidden lines: explicit settings are honored, sparse
## regions stay sparse, and every picture keeps something fully packed.
func test_design_plans() -> void:
	print("Design plans")
	var dense := PictureSources.mandala_collage(2001, {"sparsity": 0.0, "line_style": "full"})
	for r in dense["regions"]:
		check(r["fill"] == "full", "sparsity 0 gave a %s region" % r["fill"])
	check(dense["lines_visible"] == dense["lines"], "line_style full should draw every line")

	var bare := PictureSources.mandala_collage(2002, {"sparsity": 1.0, "line_style": "none"})
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
	var mixed := PictureSources.mandala_collage(2003, {"sparsity": 0.6, "line_style": "partial"})
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
	# "any color" keeps the quantized colors.
	var free_kit := KitGenerator.generate(src, {"size": "small", "colors": 16, "any_color": true})
	check(free_kit["palette"][0]["gem_color_id"] == null, "any_color kit should not snap to gems")


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


# --- helpers -----------------------------------------------------------------

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
		var poly := GemShapes.slot_polygon(slot, 16)
		var box := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			box = box.expand(v)
		var c: Color = slot["target_color"]
		for y in range(maxi(0, int(box.position.y)), mini(h, int(box.end.y) + 1)):
			for x in range(maxi(0, int(box.position.x)), mini(w, int(box.end.x) + 1)):
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
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
	var by_region := {}
	for s in slots:
		if not by_region.has(s["region"]):
			by_region[s["region"]] = []
		by_region[s["region"]].append(s)
	var n := 0
	for list in by_region.values():
		for i in list.size():
			for j in range(i + 1, list.size()):
				var a: Dictionary = list[i]
				var b: Dictionary = list[j]
				var ra: float = a["width"] / 2.0
				var rb: float = b["width"] / 2.0
				var reach: float = a["size"] / 2.0 + b["size"] / 2.0
				var ca := Vector2(a["x"], a["y"])
				var cb := Vector2(b["x"], b["y"])
				if ca.distance_to(cb) > reach:
					continue
				var ha := Vector2.from_angle(a["rotation"]) * (a["size"] / 2.0 - ra)
				var hb := Vector2.from_angle(b["rotation"]) * (b["size"] / 2.0 - rb)
				var pts := Geometry2D.get_closest_points_between_segments(ca - ha, ca + ha, cb - hb, cb + hb)
				if pts[0].distance_to(pts[1]) < ra + rb - tolerance:
					n += 1
	return n

class_name CollageGenerator
extends RefCounted
## Builds a Gem Collage puzzle from a line-art mask: regions, packed gem slots
## and a target color per region.
##
## Result format (saved as JSON through PatternIO):
## {
##   version, type: "collage", width, height, symmetry, source: {...},
##   lines: PackedByteArray mask (255 = line); every line separates regions,
##   lines_visible: the part of `lines` to draw as the metal setting,
##   line_style, sparsity: the design choices (see DesignPlan),
##   regions: [{id, group, color, gem_color_id, fill, outlined, style, area, centroid, empty}],
##   slots: [{id, region, shape, x, y, rotation, size, width, target_color, target_gem}],
## }
## Coordinates and sizes are in px of width x height. Regions in the same
## `group` are symmetric copies, which free-color mode can paint together.


## options:
##   symmetry: "radial" | "mirror" | "none"   (default "none")
##   theme: theme name for region colors        (default "sunset")
##   colors_image: Image to sample region colors from instead of a theme
##   gems: Array of {"id", "color"} to snap target colors to (default starter gems;
##         pass [] to keep exact colors)
##   min_area: px; smaller regions merge into the lines (default 0.05% of the picture)
##   sparsity, line_style: see DesignPlan (default: picked per seed)
##   seed, unit, gap, coverage, outline: passed to SlotPacker
##   source: Dictionary describing where the lines came from, stored as is
static func generate(mask: PackedByteArray, w: int, h: int, options: Dictionary = {}) -> Dictionary:
	var seed_value: int = options.get("seed", 1)
	var symmetry: String = options.get("symmetry", "none")
	var min_area: int = options.get("min_area", int(w * h * 0.0005))
	var map := RegionMap.build(mask, w, h, min_area)
	var groups := RegionPaint.symmetry_groups(map, symmetry)
	var plan := DesignPlan.make(map, groups, options, seed_value)
	var pack_options := options.duplicate()
	var styles := DesignPlan.packer_styles(plan)
	styles.merge(options.get("styles", {}), true)
	pack_options["styles"] = styles
	var slots := SlotPacker.pack(map, pack_options)

	var colors: PackedColorArray
	if options.get("colors_image") is Image:
		colors = RegionPaint.image_colors(map, options["colors_image"])
	else:
		colors = RegionPaint.theme_colors(map, symmetry, Palettes.theme_colors(options.get("theme", "sunset")), seed_value)
	var gems: Array = options.get("gems", Palettes.starter_gems())
	var gem_ids := []
	if not gems.is_empty():
		var snapped := RegionPaint.snap_to_gems(colors, gems)
		for r in colors.size():
			colors[r] = gems[snapped[r]]["color"]
			gem_ids.append(gems[snapped[r]]["id"])

	var fills: PackedStringArray = plan["fills"]
	var outlined: PackedByteArray = plan["outlined"]
	var slot_count := PackedInt32Array()
	slot_count.resize(map.regions.size())
	for s in slots:
		var r: int = s["region"]
		s["target_color"] = colors[r]
		s["target_gem"] = gem_ids[r] if not gem_ids.is_empty() else null
		slot_count[r] += 1

	var regions := []
	for r in map.regions:
		var id: int = r["id"]
		regions.append({
			"id": id,
			"group": groups[id],
			"color": colors[id],
			"gem_color_id": gem_ids[id] if not gem_ids.is_empty() else null,
			"fill": fills[id],
			"outlined": outlined[id] == 1,
			"style": r.get("style", ""),
			"area": r["area"],
			"centroid": r["centroid"],
			# Too thin for any stone, though it was meant to have some.
			"empty": slot_count[id] == 0 and fills[id] != "bare",
		})

	return {
		"version": 1,
		"type": "collage",
		"width": w,
		"height": h,
		"symmetry": symmetry,
		"line_style": plan["line_style"],
		"sparsity": plan["sparsity"],
		"source": options.get("source", {}),
		"lines": map.line_mask(),
		"lines_visible": DesignPlan.visible_lines(map, plan),
		"regions": regions,
		"slots": slots,
	}


## Fraction of each region's area covered by its slots (capsule footprints),
## averaged over fully packed regions that have slots. Used by tests and tuning.
static func mean_coverage(picture: Dictionary) -> float:
	var covered := {}
	for s in picture["slots"]:
		var r: float = s["width"] / 2.0
		var h: float = s["size"] / 2.0 - r
		covered[s["region"]] = covered.get(s["region"], 0.0) + PI * r * r + 4.0 * r * h
	var total := 0.0
	var n := 0
	for region in picture["regions"]:
		if covered.has(region["id"]) and region.get("fill", "full") == "full":
			total += covered[region["id"]] / float(region["area"])
			n += 1
	return total / maxi(1, n)

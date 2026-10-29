class_name CollageGenerator
extends RefCounted
## Builds a Gem Collage puzzle from a line-art mask: regions, gem slots laid
## out in patterns, and target colors.
##
## Each picture picks a setting:
##   gems (about 3 in 4): the lines themselves become rows of gems slotted
##     along them (see GemLines), and no metal is drawn;
##   metal: the lines stay as the metal setting (all or some of them, see
##     DesignPlan) and only the areas get gems.
## Either way every area is filled with a pattern (see SlotPacker).
##
## The same line art makes many different collages: `pattern_seed` changes
## the setting, patterns, sparse fills and colors while the lines stay put.
##
## Result format (saved as JSON through PatternIO):
## {
##   version, type: "collage", width, height, symmetry, source: {...},
##   setting: "gems" | "metal", pattern_seed, line_gems: GemLines style or "",
##   lines: PackedByteArray mask (255 = line); every line separates regions
##     (in the gems setting, the widened channel the line gems sit in),
##   lines_visible: the part of `lines` to draw as the metal setting,
##   line_style, sparsity: the design choices (see DesignPlan),
##   regions: [{id, group, kind, color, gem_color_id, accent_color, accent_gem, fill,
##              outlined, style, area, centroid, empty}],
##   slots: [{id, region, shape, x, y, rotation, size, width, tone, part, target_color, target_gem}],
##   spacers: bool, thin rows of small stones between every pattern's main rows
##            (default: some groups; all when the picture is short of gem types)
##   gem_types: how many gem types it uses; gem_kinds: [{shape, gem, color, count}],
##   unit, tiers, radial_size: the stone size and design choices used,
## }
## Coordinates and sizes are in px of width x height. Regions in the same
## `group` are symmetric copies, which free-color mode can paint together.
## kind is "area" for a closed area or "line" for the gems along the lines
## (one region for the inner lines and one for the silhouette). Slots with
## tone 1 take their region's accent color.

const SETTINGS := ["gems", "metal"]
const GEMS_SETTING_CHANCE := 0.75
## Stones per collage: pictures outside this range are rebuilt with bigger or
## smaller stones, aiming a little inside it.
const MIN_SLOTS := 300
const MAX_SLOTS := 1500
const SLOTS_LOW_AIM := 450.0
const SLOTS_HIGH_AIM := 1250.0
## Gem types (shape + color, any size) a collage aims for.
const GEM_TYPES_MIN := 25
const GEM_TYPES_MAX := 30


## options:
##   symmetry: "radial" | "mirror" | "none"   (default "none")
##   theme: theme name for region colors        (default "sunset")
##   colors_image: Image to sample region colors from instead of a theme
##   gems: Array of {"id", "color"} to snap target colors to (default starter gems;
##         pass [] to keep exact colors)
##   min_area: px; smaller regions merge into the lines (default 0.05% of the picture)
##   setting: "gems" | "metal" | "auto" (default "auto": picked per seed)
##   line_gems: one of GemLines.STYLES (default: picked per seed)
##   pattern_seed: int (default 0); another value makes another collage from
##                 the same lines
##   sparsity, line_style: see DesignPlan (default: picked per seed)
##   radial_size: bool, area stones shrink toward the center (default: picked per seed)
##   tiers: bool, some groups get a few large then medium stones before their
##          pattern (default: picked per seed)
##   spacers: bool, thin rows of small stones between every pattern's main rows
##            (default: some groups; all when the picture is short of gem types)
##   gem_types: how many gem types (shape + color, any size) to aim for
##              (default: 25-30, picked per seed)
##   seed, gap: passed to SlotPacker
##   unit: base stone radius in px; by default 1% of the picture, then scaled
##         so the collage has MIN_SLOTS..MAX_SLOTS stones
##   source: Dictionary describing where the lines came from, stored as is
static func generate(mask: PackedByteArray, w: int, h: int, options: Dictionary = {}) -> Dictionary:
	var unit: float = options.get("unit", minf(w, h) * 0.010)
	var picture := _build(mask, w, h, options, unit)
	if options.has("unit") and options.has("spacers"):
		return picture
	# Stone count goes roughly as 1 / unit^2 (line stones change less): rescale
	# toward the range and rebuild, a few times for the busiest pictures.
	for _attempt in (0 if options.has("unit") else 4):
		var n: int = picture["slots"].size()
		if n >= MIN_SLOTS and n <= MAX_SLOTS:
			break
		var aim := SLOTS_HIGH_AIM if n > MAX_SLOTS else SLOTS_LOW_AIM
		unit *= clampf(sqrt(float(n) / aim), 0.5, 2.5)
		picture = _build(mask, w, h, options, unit)
	# Short of gem types: thin spacer rows between the main rows give the
	# variety pass more rows to vary, without breaking up any row.
	if picture["gem_types"] < GEM_TYPES_MIN and not options.has("spacers"):
		var opts := options.duplicate()
		opts["spacers"] = true
		var spaced := _build(mask, w, h, opts, unit)
		var n: int = spaced["slots"].size()
		if spaced["gem_types"] > picture["gem_types"] and n >= MIN_SLOTS and n <= MAX_SLOTS:
			picture = spaced
	return picture


static func _build(mask: PackedByteArray, w: int, h: int, options: Dictionary, unit: float) -> Dictionary:
	var pattern_seed: int = options.get("pattern_seed", 0)
	var seed_value: int = options.get("seed", 1)
	if pattern_seed != 0:
		seed_value = hash([seed_value, pattern_seed]) & 0x7fffffff
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "setting"])
	var symmetry: String = options.get("symmetry", "none")
	var min_area: int = options.get("min_area", int(w * h * 0.0005))
	var side := float(mini(w, h))
	var gap: float = options.get("gap", side * 0.003)

	var setting: String = options.get("setting", "auto")
	if not setting in SETTINGS:
		setting = "gems" if rng.randf() < GEMS_SETTING_CHANCE else "metal"
	var line_gems: String = options.get("line_gems", "")
	var line_r := 0.0
	var graph := {}
	var line_slots: Array[Dictionary] = []
	var area_mask := mask
	if setting == "gems":
		if not line_gems in GemLines.STYLES:
			line_gems = GemLines.STYLES[rng.randi_range(0, GemLines.STYLES.size() - 1)]
		# Stones go along the lines' centerlines; the lines then become a channel
		# shaped to those stones, so the areas shrink exactly where the stones are big.
		graph = Contours.centerlines(mask, w, h, unit * 1.5)
		var outline_map := RegionMap.build(mask, w, h, min_area)
		# Line stones scale with how roomy the areas are, so busy pictures keep
		# room for their area patterns.
		var depths := []
		for r in outline_map.regions:
			depths.append(r["max_dist"])
		depths.sort()
		var typical: float = depths[depths.size() / 2] if not depths.is_empty() else unit * 3.0
		line_r = clampf(typical * 0.3, unit * 0.45, unit * 0.7) * [0.85, 1.0, 1.15][rng.randi_range(0, 2)]
		line_slots = GemLines.place(graph, outline_map, line_r, gap, line_gems, symmetry, seed_value)
		area_mask = LineRaster.stamp_slots(mask, w, h, line_slots, gap * 1.2)
	else:
		line_gems = ""

	var map := RegionMap.build(area_mask, w, h, min_area)
	var groups := RegionPaint.symmetry_groups(map, symmetry)
	var plan_options := options.duplicate()
	if setting == "gems":
		plan_options["line_style"] = "none"
	var plan := DesignPlan.make(map, groups, plan_options, seed_value)
	var pack_options := options.duplicate()
	pack_options["seed"] = seed_value
	pack_options["groups"] = groups
	if not pack_options.has("radial_size"):
		pack_options["radial_size"] = rng.randf() < (0.35 if symmetry == "radial" else 0.15)
	if not pack_options.has("tiers"):
		pack_options["tiers"] = rng.randf() < 0.3
	pack_options["unit"] = unit
	var styles := DesignPlan.packer_styles(plan)
	styles.merge(options.get("styles", {}), true)
	pack_options["styles"] = styles
	var slots := SlotPacker.pack(map, pack_options)

	var n := map.regions.size()
	var theme := Palettes.theme_colors(options.get("theme", "sunset"))
	var colors: PackedColorArray
	var accents := PackedColorArray()
	var features := PackedColorArray()
	var from_image: bool = options.get("colors_image") is Image
	if from_image:
		colors = RegionPaint.image_colors(map, options["colors_image"])
		for c in colors:
			accents.append(c.lightened(0.35) if c.get_luminance() < 0.6 else c.darkened(0.3))
			features.append(c.darkened(0.45) if c.get_luminance() > 0.3 else c.lightened(0.6))
	else:
		colors = RegionPaint.theme_colors(map, symmetry, theme, seed_value)
		accents = RegionPaint.accent_colors(map, groups, colors, theme, seed_value)
		features = RegionPaint.accent_colors(map, groups, accents, theme, seed_value + 1)

	var n_groups := 0
	for g in groups:
		n_groups = maxi(n_groups, g + 1)
	# Line stones form their own regions: "inner"/"outer" in one or two line
	# colors, or (matched) one per area group, each line in the accent color of
	# the area it borders (the one nearer the center), plus the silhouette.
	var line_keys := []
	var line_matched := false
	if setting == "gems":
		var neutral := _line_colors(theme, from_image, rng)
		line_matched = not from_image and rng.randf() < 0.5
		for sl in line_slots:
			var key: Variant = "outer" if sl["region"] == 1 else "inner"
			if line_matched and key == "inner":
				key = _bordered_group(sl, map, groups, gap)
			var k := line_keys.find(key)
			if k < 0:
				k = line_keys.size()
				line_keys.append(key)
				if key is int:
					var c: Color = accents[groups.find(key)]
					colors.append(c)
				else:
					colors.append(neutral[1] if key == "outer" else neutral[0])
				# Second and third colors for lines that repeat a sequence.
				var base: Color = colors[colors.size() - 1]
				var seq_colors := _distinct_colors(base, theme + PackedColorArray(neutral), 2, hash([seed_value, str(key)]))
				accents.append(seq_colors[0])
				features.append(seq_colors[1])
			sl["region"] = n + k

	var gems: Array = options.get("gems", Palettes.starter_gems())
	var gem_ids := []
	var accent_ids := []
	var feature_ids := []
	if not gems.is_empty():
		var snapped := RegionPaint.snap_to_gems(colors, gems)
		var snapped_accents := RegionPaint.snap_to_gems(accents, gems)
		var snapped_features := RegionPaint.snap_to_gems(features, gems)
		for r in colors.size():
			colors[r] = gems[snapped[r]]["color"]
			gem_ids.append(gems[snapped[r]]["id"])
			accents[r] = gems[snapped_accents[r]]["color"]
			accent_ids.append(gems[snapped_accents[r]]["id"])
			features[r] = gems[snapped_features[r]]["color"]
			feature_ids.append(gems[snapped_features[r]]["id"])

	for sl in line_slots:
		sl["id"] = slots.size()
		slots.append(sl)

	var fills: PackedStringArray = plan["fills"]
	var outlined: PackedByteArray = plan["outlined"]
	var slot_count := PackedInt32Array()
	slot_count.resize(colors.size())
	for s in slots:
		var r: int = s["region"]
		match s.get("tone", 0):
			1:
				s["target_color"] = accents[r]
				s["target_gem"] = accent_ids[r] if not accent_ids.is_empty() else null
			2:
				s["target_color"] = features[r]
				s["target_gem"] = feature_ids[r] if not feature_ids.is_empty() else null
			_:
				s["target_color"] = colors[r]
				s["target_gem"] = gem_ids[r] if not gem_ids.is_empty() else null
		slot_count[r] += 1

	# Steer the number of gem types (shape + color, any size) into range by
	# recoloring or reshaping whole pattern parts across symmetric copies.
	var group_of := PackedInt32Array()
	for r in colors.size():
		group_of.append(groups[r] if r < n else n_groups + r - n)
	var type_rng := RandomNumberGenerator.new()
	type_rng.seed = hash([seed_value, "gem types"])
	var type_target: int = options.get("gem_types", type_rng.randi_range(GEM_TYPES_MIN, GEM_TYPES_MAX))
	var gem_types := GemVariety.balance(slots, group_of,
			[] if from_image else _variety_colors(slots, theme, gems), type_target, seed_value)

	var regions := []
	for r in map.regions:
		var id: int = r["id"]
		regions.append({
			"id": id,
			"group": groups[id],
			"kind": "area",
			"color": colors[id],
			"gem_color_id": gem_ids[id] if not gem_ids.is_empty() else null,
			"accent_color": accents[id],
			"accent_gem": accent_ids[id] if not accent_ids.is_empty() else null,
			"feature_color": features[id],
			"feature_gem": feature_ids[id] if not feature_ids.is_empty() else null,
			"fill": fills[id],
			"outlined": outlined[id] == 1,
			"style": r.get("style", ""),
			"area": r["area"],
			"centroid": r["centroid"],
			# Too thin for any stone, though it was meant to have some.
			"empty": slot_count[id] == 0 and fills[id] != "bare",
		})
	for k in colors.size() - n:
		var id := n + k
		var sum := Vector2.ZERO
		for s in line_slots:
			if s["region"] == id:
				sum += Vector2(s["x"], s["y"])
		regions.append({
			"id": id,
			"group": n_groups + k,
			"kind": "line",
			"color": colors[id],
			"gem_color_id": gem_ids[id] if not gem_ids.is_empty() else null,
			"accent_color": accents[id],
			"accent_gem": accent_ids[id] if not accent_ids.is_empty() else null,
			"fill": "line",
			"outlined": false,
			"style": line_gems,
			"line": str(line_keys[k]) if line_keys[k] is String else "group",
			"area": 0,
			"centroid": sum / maxi(1, slot_count[id]),
			"empty": false,
		})

	return {
		"version": 2,
		"type": "collage",
		"width": w,
		"height": h,
		"symmetry": symmetry,
		"setting": setting,
		"pattern_seed": pattern_seed,
		"line_gems": line_gems,
		"line_colors": ("matched" if line_matched else "neutral") if setting == "gems" else "",
		"radial_size": pack_options["radial_size"],
		"tiers": pack_options["tiers"],
		"spacers": pack_options.get("spacers", false),
		"unit": unit,
		"gem_types": gem_types,
		"gem_kinds": GemVariety.kinds(slots),
		"line_style": "gems" if setting == "gems" else plan["line_style"],
		"sparsity": plan["sparsity"],
		"source": options.get("source", {}),
		"lines": map.line_mask(),
		"lines_visible": DesignPlan.visible_lines(map, plan),
		"regions": regions,
		"slots": slots,
	}


## `count` colors from `choices`, each clearly different from `base` and
## from each other (picked in a seeded order), for the steps of a line
## sequence. Falls back to lighter and darker shades of `base`.
static func _distinct_colors(base: Color, choices: PackedColorArray, count: int, seed_value: int) -> PackedColorArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pool := Array(choices)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Color = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var out := PackedColorArray()
	var taken := [LabColor.from_color(base)]
	for c: Color in pool:
		if out.size() >= count:
			break
		var lab := LabColor.from_color(c)
		var far := true
		for t: Vector3 in taken:
			if lab.distance_to(t) < 25.0:
				far = false
				break
		if far:
			out.append(c)
			taken.append(lab)
	while out.size() < count:
		out.append(base.lightened(0.5) if out.size() == 0 else base.darkened(0.5))
	return out


## Colors GemVariety may recolor parts with, best first: the gem colors the
## picture already uses (most used first), then the theme's, then the other
## gems by how close they sit to a theme color, so new types stay in harmony.
static func _variety_colors(slots: Array, theme: PackedColorArray, gems: Array) -> Array:
	var out := []
	var seen := {}
	var used := {}
	for s in slots:
		var key: String = str(s["target_gem"]) if s["target_gem"] != null else (s["target_color"] as Color).to_html(false)
		if not used.has(key):
			used[key] = {"color": s["target_color"], "gem": s["target_gem"], "n": 0}
		used[key]["n"] += 1
	var by_use := used.values()
	by_use.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["n"] > b["n"])
	for u in by_use:
		var key: String = str(u["gem"]) if u["gem"] != null else (u["color"] as Color).to_html(false)
		seen[key] = true
		out.append({"color": u["color"], "gem": u["gem"]})
	if gems.is_empty():
		for c in theme:
			if not seen.has(c.to_html(false)):
				seen[c.to_html(false)] = true
				out.append({"color": c, "gem": null})
		return out
	var theme_lab := PackedVector3Array()
	for c in theme:
		theme_lab.append(LabColor.from_color(c))
	var rest := []
	for g in gems:
		if seen.has(str(g["id"])):
			continue
		var lab := LabColor.from_color(g["color"])
		var d := INF
		for t in theme_lab:
			d = minf(d, lab.distance_to(t))
		rest.append({"color": g["color"], "gem": g["id"], "d": d})
	rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])
	for r in rest:
		out.append({"color": r["color"], "gem": r["gem"]})
	return out


## Symmetry group of the area a line stone borders: of the areas on its two
## sides, the one with the lower group (nearer the center or the top); "inner"
## if neither side is an area.
static func _bordered_group(slot: Dictionary, map: RegionMap, groups: PackedInt32Array, gap: float) -> Variant:
	var c := Vector2(slot["x"], slot["y"])
	var nrm := Vector2.from_angle(slot["rotation"]).orthogonal()
	var best := -1
	for reach in [slot["width"] / 2.0 + gap * 1.2 + 2.0, slot["width"] / 2.0 + gap * 1.2 + 5.0]:
		for side in [-1.0, 1.0]:
			var q: Vector2 = c + nrm * reach * side
			var l := map.label_at(int(q.x), int(q.y))
			if l >= 0 and (best < 0 or groups[l] < best):
				best = groups[l]
	return best if best >= 0 else "inner"


## Colors for the inner lines and the silhouette: a sparkly neutral (snow,
## silver, sand) or a theme color; the silhouette sometimes differs.
static func _line_colors(theme: PackedColorArray, from_image: bool, rng: RandomNumberGenerator) -> PackedColorArray:
	var neutrals := [Color("#f7f5f2"), Color("#b9bcc4"), Color("#dcc49a")]
	if from_image:
		neutrals = [Color("#1f1d24"), Color("#f7f5f2"), Color("#b9bcc4")]
	var inner: Color
	if from_image or rng.randf() < 0.55:
		inner = neutrals[rng.randi_range(0, neutrals.size() - 1)]
	else:
		inner = theme[rng.randi_range(0, theme.size() - 1)]
	var outer := inner
	if rng.randf() < 0.4:
		var choices := neutrals + Array(theme)
		while outer == inner:
			outer = choices[rng.randi_range(0, choices.size() - 1)]
	return PackedColorArray([inner, outer])


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

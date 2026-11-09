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
## Layouts (how closely the stones sit):
##   classic: every pattern and gem line spaced as SlotPacker.GAP says;
##   dense: 2/3 to 3/4 of the groups of areas and of the classes of gem
##     lines (DENSE_SHARE_MIN..MAX, picked per seed) are dense: lines' stones
##     sit closer together (GemLines.DENSE_GAP), areas get smaller stones in
##     more rows, closer together and more often with spacer rows
##     (SlotPacker.DENSE_GAP), and dense areas are never sparse, so more
##     areas are filled. Pictures may have more stones (DENSE_MAX_SLOTS);
##   cluster: fewer, bigger stones (about CLUSTER_AIM, CLUSTER_MIN_SLOTS..
##     CLUSTER_MAX_SLOTS) in fewer gem types (CLUSTER_TYPES_MIN..MAX), every
##     group and line packed tight (SlotPacker.DENSE_GAP of the gap, stones
##     their usual size), and no filler: no spacer rows, no scatter or
##     outline fills, no free-form pave, no stones shrinking toward the
##     center or (lattices) the rim while their spacing stays, rows and
##     chains spaced to their stones (see SlotPacker.tight), and pattern
##     parts whose stones sit loose (farther from their neighbors than
##     LOOSE_GAP of their own radius) are left out, so the stones that
##     remain sit in close groups. Nor tiny runs of one or two stones of a
##     part (TINY_FILLER), nor gem types of fewer than MIN_TYPE_STONES
##     stones but accents. Gem lines over fine line art take stones small
##     enough to fit along it (CLUSTER_LINE_MIN), and such pictures may go
##     over the stone range rather than lose lines. Groups can still spread
##     over the picture, with bare areas and the background between them.
## A picture is made the same again only in its own layout: a puzzle
## request without one (from before dense) stays classic.
##
## Result format (saved as JSON through PatternIO):
## {
##   version, type: "collage", width, height, symmetry, source: {...},
##   layout: one of LAYOUTS, dense: the share of groups and line classes made dense,
##   setting: "gems" | "metal", pattern_seed, line_gems: GemLines style or "",
##   bold_lines: how many classes of lines got medium or large stones,
##   loose_dropped: how many loose area stones the cluster layout left out,
##   dropped: how many elements (classes of gem lines, groups of areas) were
##     left out to stay under max_slots stones,
##   lines: PackedByteArray mask (255 = line); every line separates regions
##     (in the gems setting, the widened channel the line gems sit in),
##   lines_visible: the part of `lines` to draw as the metal setting,
##   line_style, sparsity: the design choices (see DesignPlan),
##   regions: [{id, group, kind, color, gem_color_id, accent_color, accent_gem, fill,
##              outlined, dense (areas only), style, area, centroid, empty}],
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
const MAX_SLOTS := 6000
const SLOTS_LOW_AIM := 450.0
const SLOTS_HIGH_AIM := 5000.0
## Pictures over MAX_SLOTS leave out up to this many elements (a class of
## gem lines, or a group of areas, with all their symmetric copies; the
## busiest first) before their stones are made bigger.
const MAX_DROPPED := 6
## The channel around gem-line stones is this many stone gaps wider than
## them. Area stones keep a gap from the channel's edge as well, so this
## only needs to cover rasterizing.
const LINE_PAD := 0.5
## Gem types (shape + color, any size) a collage aims for.
const GEM_TYPES_MIN := 25
const GEM_TYPES_MAX := 30
const LAYOUTS := ["classic", "dense", "cluster"]
## Dense layout: the share of groups of areas and of classes of gem lines
## made dense (picked per seed in this range), and its most stones.
const DENSE_SHARE_MIN := 0.67
const DENSE_SHARE_MAX := 0.75
const DENSE_MAX_SLOTS := 7500
## Cluster layout: its stone range and aim, the stone unit it starts from
## (a share of SlotPacker.UNIT's; then rescaled into range), its gem types,
## and when a stone sits loose: its second-nearest neighbor is farther away
## (edge to edge) than this share of its own radius. A pattern part with at
## least LOOSE_SHARE of its stones loose is left out (its group keeps its
## biggest part, unless LOOSE_GROUP_SHARE of the group's stones are loose:
## then the whole group is left bare), up to LOOSE_PASSES times, as leaving
## stones out can leave their neighbors loose.
const CLUSTER_MIN_SLOTS := 420
const CLUSTER_MAX_SLOTS := 580
const CLUSTER_AIM := 500.0
const CLUSTER_UNIT := 2.0
const CLUSTER_MAX_UNIT := 3.0
const CLUSTER_METAL_MAX_UNIT := 4.0
const CLUSTER_TRIES := 10
## No gem type keeps fewer stones than this (accents excepted: stones at
## least ACCENT_SIZE times their area's typical stone, or an area's only one
## or two, and accent stones along lines).
const MIN_TYPE_STONES := 3
## Cluster layout: the smallest line stone (in units) where the areas beside
## the lines are shallow (otherwise 0.45).
const CLUSTER_LINE_MIN := 0.2
const ACCENT_SIZE := 1.5
## Tiny fillers left out: a run of one or two stones of a pattern part (not
## touching more of its part) under this share of their area's typical stone.
const TINY_FILLER := 0.6
const CLUSTER_TYPES_MIN := 10
const CLUSTER_TYPES_MAX := 15
const LOOSE_GAP := 1.0
const LOOSE_SHARE := 0.5
const LOOSE_GROUP_SHARE := 0.6
const LOOSE_PASSES := 3
## Whole groups are left bare only while this share of the packed area
## stones stays.
const LOOSE_KEEP := 0.6


## options:
##   symmetry: "radial" | "mirror" | "none"   (default "none")
##   theme: theme name for region colors        (default "sunset")
##   theme_colors: PackedColorArray to use instead of a named theme
##   colors_image: Image to sample region colors from instead of a theme
##   gems: Array of {"id", "color"} to snap target colors to (default starter gems;
##         pass [] to keep exact colors)
##   min_area: px; smaller regions merge into the lines (default 0.05% of the picture),
##             except a symmetric picture's center
##   setting: "gems" | "metal" | "auto" (default "auto": picked per seed)
##   line_gems: one of GemLines.STYLES (default: picked per seed)
##   bold_lines: how many classes of lines through the middle get medium or
##               large stones (default: 2 or 3, picked per seed; 0 for none)
##   pattern_seed: int (default 0); another value makes another collage from
##                 the same lines
##   sparsity, line_style: see DesignPlan (default: picked per seed)
##   radial_size: bool, area stones shrink toward the center (default: picked per seed)
##   tiers: bool, some groups get a few large then medium stones before their
##          pattern (default: picked per seed)
##   spacers: bool, thin rows of small stones between every pattern's main rows
##            (default: some groups; all when the picture is short of gem types)
##   gem_types: how many gem types (shape + color, any size) to aim for
##              (default: 25-30, or 10-15 in the cluster layout, picked per seed)
##   shapes: the only shapes and cuts to use, {shape: [cuts]} (default {}: all);
##           other stones take a stand-in shape (see GemVariety.restrict)
##   seed, gap: passed to SlotPacker
##   unit: base stone radius in px; by default SlotPacker.UNIT of the picture, then scaled
##         so the collage has MIN_SLOTS..MAX_SLOTS stones (gem-line pictures
##         first leave out their busiest classes of lines, see MAX_DROPPED;
##         cluster pictures start from CLUSTER_UNIT of it and only rescale,
##         toward CLUSTER_AIM)
##   max_slots: the most stones (default MAX_SLOTS, DENSE_MAX_SLOTS or CLUSTER_MAX_SLOTS)
##   drop_lines, bare_at: classes of gem lines and centroids of areas to leave
##     out (set when over max_slots)
##   layout: one of LAYOUTS (default "classic")
##   motifs: a free-form picture's families of lines and areas (see
##     PictureSources.mandala_lines): {"lines": a family per pixel, "areas":
##     [{"at", "family"}]}. A family stands in for symmetric copies: its gem
##     lines are one class (see GemLines) and its areas one group.
##   source: Dictionary describing where the lines came from, stored as is
static func generate(mask: PackedByteArray, w: int, h: int, options: Dictionary = {}) -> Dictionary:
	var layout: String = options.get("layout", "")
	var cluster := layout == "cluster"
	var unit: float = options.get("unit", minf(w, h) * SlotPacker.UNIT * (CLUSTER_UNIT if cluster else 1.0))
	if cluster and not options.has("unit"):
		return _fit_cluster(mask, w, h, options, unit, options.get("max_slots", CLUSTER_MAX_SLOTS))
	var picture := _build(mask, w, h, options, unit)
	if (options.has("unit") and options.has("spacers")) or cluster:
		return picture
	var max_slots: int = options.get("max_slots", DENSE_MAX_SLOTS if layout == "dense" else MAX_SLOTS)
	# Too many stones: leave out the element with the most stones (a class of
	# gem lines, or a group of areas), all its symmetric copies at once, as a
	# symmetric gap, rather than making every stone bigger.
	var drop := []
	var bare := []
	for _attempt in MAX_DROPPED:
		if picture["slots"].size() <= max_slots:
			break
		var busiest := _busiest_element(picture)
		if busiest.is_empty():
			break
		if busiest.has("lines"):
			drop.append(busiest["lines"])
		else:
			bare.append_array(busiest["areas"])
		options = options.duplicate()
		options["drop_lines"] = drop.duplicate()
		options["bare_at"] = bare.duplicate()
		picture = _build(mask, w, h, options, unit)
	# Stone count goes roughly as 1 / unit^2 (line stones change less): rescale
	# toward the range and rebuild, a few times for the busiest pictures.
	for _attempt in (0 if options.has("unit") else 4):
		var n: int = picture["slots"].size()
		if n >= MIN_SLOTS and n <= max_slots:
			break
		var aim := SLOTS_HIGH_AIM * max_slots / MAX_SLOTS if n > max_slots else SLOTS_LOW_AIM
		unit *= clampf(sqrt(float(n) / aim), 0.5, 2.5)
		picture = _build(mask, w, h, options, unit)
	# Short of gem types: thin spacer rows between the main rows give the
	# variety pass more rows to vary, without breaking up any row.
	if picture["gem_types"] < GEM_TYPES_MIN and not options.has("spacers"):
		var opts := options.duplicate()
		opts["spacers"] = true
		var spaced := _build(mask, w, h, opts, unit)
		var n: int = spaced["slots"].size()
		if spaced["gem_types"] > picture["gem_types"] and n >= MIN_SLOTS and n <= max_slots:
			picture = spaced
	return picture


## A cluster picture in CLUSTER_MIN_SLOTS..max_slots stones. The unit is
## rescaled toward CLUSTER_AIM, up to CLUSTER_MAX_UNIT of SlotPacker.UNIT's
## with gem lines (fine line art keeps their stones small however big the
## unit gets, while its areas lose theirs) and CLUSTER_METAL_MAX_UNIT
## without. With stones that big and still too many, a picture whose gem
## lines take most of its stones keeps them all, with more stones than the
## range (line art that fine would break up without them); otherwise the
## busiest elements (a class of gem lines, or a group of areas, with their
## symmetric copies) are left out as symmetric gaps, as other
## layouts do. Keeps the try closest to the aim (by ratio) if none lands in
## range.
static func _fit_cluster(mask: PackedByteArray, w: int, h: int, options: Dictionary, unit: float,
		max_slots: int) -> Dictionary:
	var base := minf(w, h) * SlotPacker.UNIT
	var picture := _build(mask, w, h, options, unit)
	var best := picture
	var drop := []
	var bare := []
	# The count jumps as the unit crosses the sizes that pick each area's
	# pattern, so once one unit gave too many stones and a bigger one too
	# few, the next try is halfway between them (on a log scale).
	var too_many := 0.0
	var too_few := INF
	for _attempt in CLUSTER_TRIES:
		var n: int = picture["slots"].size()
		if n >= CLUSTER_MIN_SLOTS and n <= max_slots:
			return picture
		if n > max_slots:
			too_many = unit
		else:
			too_few = unit
		# Line stones go about as 1 / unit (they fill the lines' length),
		# area stones as 1 / unit^2.
		var on_lines := 0
		for s in picture["slots"]:
			if picture["regions"][s["region"]]["kind"] == "line":
				on_lines += 1
		var on_areas := n - on_lines
		var top := base * (CLUSTER_MAX_UNIT if picture["setting"] == "gems" else CLUSTER_METAL_MAX_UNIT)
		if n > max_slots and unit >= top * 0.99 and on_lines > on_areas:
			# Gem lines take most of the stones even at the biggest unit: the
			# line art is too fine for the aim, and leaving lines out would
			# break it up. It keeps them all, with more stones.
			break
		if n > max_slots and unit >= top * 0.99:
			# The busiest elements, as many as it takes to come down to the aim
			# (at least one), in one rebuild.
			var excess := n - int(CLUSTER_AIM)
			var gone := 0
			for e: Dictionary in _elements_by_size(picture):
				if gone >= excess and gone > 0:
					break
				# Leaving out an element bigger than the excess twice over
				# would overshoot; take a smaller one instead, unless none is.
				if gone > 0 and gone + e["stones"] > excess * 2:
					continue
				var el: Dictionary = e["element"]
				if el.has("lines"):
					drop.append(el["lines"])
				else:
					bare.append_array(el["areas"])
				gone += e["stones"]
			if gone == 0:
				break
			options = options.duplicate()
			options["drop_lines"] = drop.duplicate()
			options["bare_at"] = bare.duplicate()
			too_many = 0.0
			too_few = INF
		elif too_many > 0.0 and too_few < INF:
			# Units this close make the same picture: the count jumps here.
			if absf(too_few / too_many - 1.0) < 0.02:
				break
			unit = sqrt(too_many * too_few)
		else:
			# The scale that brings on_lines / s + on_areas / s^2 to the aim.
			var s := (on_lines + sqrt(on_lines * on_lines + 4.0 * CLUSTER_AIM * on_areas)) / (2.0 * CLUSTER_AIM)
			unit = minf(unit * clampf(s, 0.5, 2.5), top)
		picture = _build(mask, w, h, options, unit)
		if _off_aim(picture) < _off_aim(best):
			best = picture
	return best


## How far a picture's stone count is from CLUSTER_AIM, as a ratio (so 250
## and 1000 stones are as far off).
static func _off_aim(picture: Dictionary) -> float:
	return absf(log(maxf(1.0, picture["slots"].size()) / CLUSTER_AIM))


static func _build(mask: PackedByteArray, w: int, h: int, options: Dictionary, unit: float) -> Dictionary:
	var pattern_seed: int = options.get("pattern_seed", 0)
	var seed_value: int = options.get("seed", 1)
	if pattern_seed != 0:
		seed_value = hash([seed_value, pattern_seed]) & 0x7fffffff
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "setting"])
	var symmetry: String = options.get("symmetry", "none")
	var min_area: int = options.get("min_area", int(w * h * 0.0005))
	# A symmetric picture's center region stays, however small: it is the focus.
	var center := Vector2i(w / 2, h / 2) if symmetry != "none" else Vector2i(-1, -1)
	var side := float(mini(w, h))
	# The share of groups and line classes made dense, from a stream of its
	# own so classic pictures come out as they always have.
	var layout: String = options.get("layout", "classic")
	if not layout in LAYOUTS:
		layout = "classic"
	var cluster := layout == "cluster"
	# Cluster pictures sit tight everywhere, as dense groups do.
	var gap: float = options.get("gap", unit * SlotPacker.GAP * (SlotPacker.DENSE_GAP if cluster else 1.0))
	var dense := 0.0
	if layout == "dense":
		var dense_rng := RandomNumberGenerator.new()
		dense_rng.seed = hash([seed_value, "dense"])
		dense = dense_rng.randf_range(DENSE_SHARE_MIN, DENSE_SHARE_MAX)

	var setting: String = options.get("setting", "auto")
	if not setting in SETTINGS:
		setting = "gems" if rng.randf() < GEMS_SETTING_CHANCE else "metal"
	var line_gems: String = options.get("line_gems", "")
	var line_r := 0.0
	var graph := {}
	var line_slots: Array[Dictionary] = []
	var bold_lines := {}
	var area_mask := mask
	if setting == "gems":
		if not line_gems in GemLines.STYLES:
			line_gems = GemLines.STYLES[rng.randi_range(0, GemLines.STYLES.size() - 1)]
		# Stones go along the lines' centerlines; the lines then become a channel
		# shaped to those stones, so the areas shrink exactly where the stones are big.
		graph = Contours.centerlines(mask, w, h, unit * 1.5)
		var outline_map := RegionMap.build(mask, w, h, min_area, center)
		# Line stones scale with how roomy the areas are, so busy pictures keep
		# room for their area patterns.
		var depths := []
		for r in outline_map.regions:
			depths.append(r["max_dist"])
		depths.sort()
		var typical: float = depths[depths.size() / 2] if not depths.is_empty() else unit * 3.0
		# Cluster pictures' stones are big, so fine line art keeps line stones
		# that fit beside it (rather than ones shrunk into gaps along it).
		line_r = clampf(typical * 0.3, unit * (CLUSTER_LINE_MIN if cluster else 0.45), unit * 0.7) \
				* [0.85, 1.0, 1.15][rng.randi_range(0, 2)]
		var bold: int = options.get("bold_lines", rng.randi_range(2, 3))
		line_slots = GemLines.place(graph, outline_map, line_r, gap, line_gems, symmetry, seed_value, bold, mask,
				options.get("drop_lines", []), dense,
				options.get("motifs", {}).get("lines", PackedInt32Array()))
		for sl in line_slots:
			if sl["seq"] < 0 and sl["tone"] == 1:
				bold_lines[sl["part"]] = true
		# Area stones keep their own gap from this edge, so a small pad is enough.
		area_mask = LineRaster.stamp_slots(mask, w, h, line_slots, gap * LINE_PAD)
	else:
		line_gems = ""

	var map := RegionMap.build(area_mask, w, h, min_area, center)
	var groups := RegionPaint.symmetry_groups(map, symmetry)
	if options.has("motifs"):
		groups = RegionPaint.motif_groups(map, groups, options["motifs"]["areas"])
	var plan_options := options.duplicate()
	plan_options["unit"] = unit
	if setting == "gems":
		plan_options["line_style"] = "none"
	plan_options["dense"] = dense
	if cluster:
		plan_options["tight"] = true
	var plan := DesignPlan.make(map, groups, plan_options, seed_value)
	# Areas left out to stay under max_slots (by where they are, as region
	# numbers can shift between builds).
	for at: Vector2 in options.get("bare_at", []):
		for r in map.regions:
			if (r["centroid"] as Vector2).distance_to(at) < 3.0:
				plan["fills"][r["id"]] = "bare"
	var pack_options := options.duplicate()
	pack_options["seed"] = seed_value
	pack_options["groups"] = groups
	if not pack_options.has("radial_size"):
		pack_options["radial_size"] = rng.randf() < (0.35 if symmetry == "radial" else 0.15)
	if not pack_options.has("tiers"):
		pack_options["tiers"] = rng.randf() < 0.5
	pack_options["unit"] = unit
	pack_options["line_mask"] = mask
	var dense_groups := {}
	var dense_regions: PackedByteArray = plan["dense"]
	for r in dense_regions.size():
		if dense_regions[r] == 1:
			dense_groups[groups[r]] = true
	pack_options["dense_groups"] = dense_groups
	if cluster:
		pack_options["allow_spacers"] = false
		pack_options["tight"] = true
		pack_options["radial_size"] = false
	var styles := DesignPlan.packer_styles(plan)
	styles.merge(options.get("styles", {}), true)
	pack_options["styles"] = styles
	var slots := SlotPacker.pack(map, pack_options)
	var packed := slots.size()
	var loose_bare := {}
	if cluster:
		slots = _drop_tiny_fillers(slots)
		# Leaving stones out can leave their neighbors loose: a few passes.
		for _pass in LOOSE_PASSES:
			var kept := _drop_loose(slots, line_slots, groups, ceili(packed * LOOSE_KEEP))
			var before := slots.size()
			slots = kept["slots"]
			loose_bare.merge(kept["bare"])
			if slots.size() == before:
				break

	var n := map.regions.size()
	var theme: PackedColorArray = (options["theme_colors"] if options.has("theme_colors")
			else Palettes.theme_colors(options.get("theme", "sunset")))
	var colors: PackedColorArray
	var accents := PackedColorArray()
	var features := PackedColorArray()
	var from_image: bool = options.get("colors_image") is Image
	var gems: Array = options.get("gems", Palettes.starter_gems())
	# Which groups of areas touch, so neighbors get colors that read apart.
	var neighbors := RegionPaint.group_neighbors(
			map.adjacency(_neighbor_reach(line_slots, unit, gap), maxi(4, int(unit))), groups)
	if from_image:
		colors = RegionPaint.image_colors(map, options["colors_image"])
		for c in colors:
			accents.append(c.lightened(0.35) if c.get_luminance() < 0.6 else c.darkened(0.3))
			features.append(c.darkened(0.45) if c.get_luminance() > 0.3 else c.lightened(0.6))
	else:
		# Choose among the gems the theme snaps to, so two theme colors that
		# land on one gem don't count as different.
		var paint := _snapped_palette(theme, gems)
		colors = RegionPaint.theme_colors(map, symmetry, paint, seed_value, groups, neighbors)
		accents = RegionPaint.accent_colors(map, groups, colors, paint, seed_value, neighbors)
		features = RegionPaint.accent_colors(map, groups, accents, paint, seed_value + 1, neighbors, colors)

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
	for r in fills.size():
		if loose_bare.has(groups[r]):
			fills[r] = "bare"
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
	# A matched line wears its area group's accent and borders that group's
	# neighbors on its other side, so it keeps apart from those.
	for k in line_keys.size():
		neighbors.append([])
	for k in line_keys.size():
		var key: Variant = line_keys[k]
		if not (key is int):
			continue
		var g: int = key
		for o: int in neighbors[g].duplicate():
			if o < n_groups:
				neighbors[n_groups + k].append(o)
				neighbors[o].append(n_groups + k)
	var type_rng := RandomNumberGenerator.new()
	type_rng.seed = hash([seed_value, "gem types"])
	var type_target: int = options.get("gem_types", type_rng.randi_range(CLUSTER_TYPES_MIN, CLUSTER_TYPES_MAX) if cluster
			else type_rng.randi_range(GEM_TYPES_MIN, GEM_TYPES_MAX))
	var allowed: Dictionary = options.get("shapes", {})
	GemVariety.restrict(slots, allowed)
	if cluster:
		_mark_accents(slots, n)
	var gem_types := GemVariety.balance(slots, group_of,
			[] if from_image else _variety_colors(slots, theme, gems), type_target, seed_value, allowed, neighbors,
			MIN_TYPE_STONES if cluster else 0)
	for s in slots:
		s.erase("keep_type")
	# The centerpiece may have changed shape: stand it upright again.
	for s in slots:
		if s.get("centerpiece", false):
			s["rotation"] = SlotPacker.upright(s["shape"])
			s.erase("centerpiece")
	# Every stone of a gem type in the same proportions; only sizes vary.
	GemVariety.even_aspects(slots)

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
			"dense": dense_regions[id] == 1,
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
		"layout": layout,
		"dense": dense,
		"setting": setting,
		"pattern_seed": pattern_seed,
		"line_gems": line_gems,
		"line_colors": ("matched" if line_matched else "neutral") if setting == "gems" else "",
		"bold_lines": bold_lines.size(),
		"loose_dropped": packed - slots.size() + line_slots.size(),
		"dropped": options.get("drop_lines", []).size() + _bare_groups(options.get("bare_at", []), groups, map),
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


## Area stones without tiny fillers: a run of one or two stones of a pattern
## part (stones of one area and part touching, edge to edge, within the
## bigger one's radius) that are all under TINY_FILLER of the area's median
## stone. Areas with only one or two stones keep them. Renumbers ids.
static func _drop_tiny_fillers(slots: Array[Dictionary]) -> Array[Dictionary]:
	var by_region := {}
	for s in slots:
		if not by_region.has(s["region"]):
			by_region[s["region"]] = []
		by_region[s["region"]].append(s)
	var drop := {}
	for region: int in by_region:
		var list: Array = by_region[region]
		if list.size() < 3:
			continue
		var radii := []
		for s: Dictionary in list:
			radii.append(float(s["width"]) / 2.0)
		radii.sort()
		var typical: float = radii[radii.size() / 2]
		var by_part := {}
		for s: Dictionary in list:
			if not by_part.has(s["part"]):
				by_part[s["part"]] = []
			by_part[s["part"]].append(s)
		for part: int in by_part:
			var members: Array = by_part[part]
			# Runs of touching stones, by flood fill.
			var seen := {}
			for i in members.size():
				if seen.has(i):
					continue
				var run := [i]
				seen[i] = true
				var k := 0
				while k < run.size() and run.size() <= 2:
					var a: Dictionary = members[run[k]]
					for j in members.size():
						if seen.has(j):
							continue
						var b: Dictionary = members[j]
						if _capsule_gap(a, b) <= maxf(a["width"], b["width"]) / 2.0:
							seen[j] = true
							run.append(j)
					k += 1
				if run.size() > 2:
					continue
				var tiny := true
				for j: int in run:
					if members[j]["width"] / 2.0 >= typical * TINY_FILLER:
						tiny = false
				if tiny:
					for j: int in run:
						drop[members[j]] = true
	var out: Array[Dictionary] = []
	for s in slots:
		if drop.has(s):
			continue
		s["id"] = out.size()
		out.append(s)
	return out


## Marks the stones that may keep a gem type of their own however few
## ("keep_type"): an area's only one or two stones, area stones at least
## ACCENT_SIZE times their area's median, and accent stones along lines.
## `line_from`: the first region id of the line regions.
static func _mark_accents(slots: Array, line_from: int) -> void:
	var by_region := {}
	for s: Dictionary in slots:
		if not by_region.has(s["region"]):
			by_region[s["region"]] = []
		by_region[s["region"]].append(s)
	for region: int in by_region:
		var list: Array = by_region[region]
		if region >= line_from:
			for s: Dictionary in list:
				if s.get("tone", 0) != 0 or s.get("seq", -1) >= 0:
					s["keep_type"] = true
			continue
		if list.size() <= 2:
			for s: Dictionary in list:
				s["keep_type"] = true
			continue
		var radii := []
		for s: Dictionary in list:
			radii.append(float(s["width"]) / 2.0)
		radii.sort()
		var typical: float = radii[radii.size() / 2]
		for s: Dictionary in list:
			if s["width"] / 2.0 >= typical * ACCENT_SIZE:
				s["keep_type"] = true


## Leaves out the area stones that sit loose: farther from their
## second-nearest neighbor (area or line stone, edge to edge) than LOOSE_GAP
## of their own radius. Whole pattern parts go (a row, a ring, a tier...
## with all their symmetric copies) when at least LOOSE_SHARE of their
## stones sit loose; a group keeps its biggest part (by stone area) unless
## LOOSE_GROUP_SHARE of the group's stones sit loose (a few stones adrift in
## small cells), and then it is left bare, loosest groups first, while at
## least `keep_at_least` stones and one group stay. Renumbers ids.
## Returns {slots, bare: the groups left bare}.
static func _drop_loose(slots: Array[Dictionary], line_slots: Array[Dictionary], groups: PackedInt32Array,
		keep_at_least: int) -> Dictionary:
	var loose := _loose(slots, slots + line_slots)
	var parts := {}  # "group|part" -> {loose, n, area, group}
	var group_n := {}  # group -> [stones, loose stones]
	for i in slots.size():
		var s := slots[i]
		var g: int = groups[s["region"]]
		var pk := "%d|%d" % [g, s.get("part", 0)]
		if not parts.has(pk):
			parts[pk] = {"loose": 0, "n": 0, "area": 0.0, "group": g}
		parts[pk]["n"] += 1
		parts[pk]["area"] += float(s["width"]) * float(s["size"])
		parts[pk]["loose"] += loose[i]
		if not group_n.has(g):
			group_n[g] = [0, 0]
		group_n[g][0] += 1
		group_n[g][1] += loose[i]
	var biggest := {}  # group -> its part with the most stone area
	for pk: String in parts:
		var g: int = parts[pk]["group"]
		if not biggest.has(g) or parts[pk]["area"] > parts[biggest[g]]["area"]:
			biggest[g] = pk
	# Loosest groups first, while keep_at_least stones stay.
	var candidates := []
	for g: int in group_n:
		if group_n[g][1] >= group_n[g][0] * LOOSE_GROUP_SHARE:
			candidates.append(g)
	candidates.sort_custom(func(a: int, b: int) -> bool:
		var la: float = float(group_n[a][1]) / group_n[a][0]
		var lb: float = float(group_n[b][1]) / group_n[b][0]
		return la > lb or (la == lb and a < b))
	var bare := {}
	var left := slots.size()
	for g: int in candidates:
		if left - group_n[g][0] < keep_at_least or bare.size() + 1 >= group_n.size():
			continue
		bare[g] = true
		left -= group_n[g][0]
	var out: Array[Dictionary] = []
	for s in slots:
		var g: int = groups[s["region"]]
		var pk := "%d|%d" % [g, s.get("part", 0)]
		var p: Dictionary = parts[pk]
		if bare.has(g) or (p["loose"] >= p["n"] * LOOSE_SHARE and biggest[g] != pk):
			continue
		s["id"] = out.size()
		out.append(s)
	return {"slots": out, "bare": bare}


## 1 for each of `slots` that sits loose: its second-nearest stone among
## `all` (which holds `slots`) is farther, edge to edge, than LOOSE_GAP of
## its own radius; else 0. Stones of an area with only one or two are
## whole elements (a solitaire filling its cell), never loose.
static func _loose(slots: Array, all: Array) -> PackedByteArray:
	var per_region := {}
	for s: Dictionary in slots:
		per_region[s["region"]] = per_region.get(s["region"], 0) + 1
	var reach := 1.0
	for s: Dictionary in all:
		reach = maxf(reach, float(s["size"]))
	# A grid of cells as wide as the biggest stone: any stone close enough to
	# count has its center within two cells.
	var grid := {}
	for j in all.size():
		var key := Vector2i(floori(all[j]["x"] / reach), floori(all[j]["y"] / reach))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(j)
	var out := PackedByteArray()
	out.resize(slots.size())
	for i in slots.size():
		var s: Dictionary = slots[i]
		if per_region[s["region"]] < 3:
			continue
		var key := Vector2i(floori(s["x"] / reach), floori(s["y"] / reach))
		var near := [INF, INF]
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				for j: int in grid.get(key + Vector2i(dx, dy), []):
					if is_same(all[j], s):
						continue
					var d := _capsule_gap(s, all[j])
					if d < near[0]:
						near[1] = near[0]
						near[0] = d
					elif d < near[1]:
						near[1] = d
		if near[1] > s["width"] / 2.0 * LOOSE_GAP:
			out[i] = 1
	return out


## Share of a picture's area stones that sit loose (see _loose; line stones
## count as neighbors). Used by tests and tuning.
static func loose_share(picture: Dictionary) -> float:
	var slots: Array = picture["slots"]
	var areas := slots.filter(func(s: Dictionary) -> bool: return picture["regions"][s["region"]]["kind"] == "area")
	var n := 0
	for v in _loose(areas, slots):
		n += v
	return float(n) / maxi(1, areas.size())


## Edge-to-edge distance between two stones, each taken as a capsule along
## its rotation (as SlotPacker does).
static func _capsule_gap(a: Dictionary, b: Dictionary) -> float:
	var ra: float = a["width"] / 2.0
	var rb: float = b["width"] / 2.0
	var ha := Vector2.from_angle(a["rotation"]) * maxf(0.0, a["size"] / 2.0 - ra)
	var hb := Vector2.from_angle(b["rotation"]) * maxf(0.0, b["size"] / 2.0 - rb)
	var ca := Vector2(a["x"], a["y"])
	var cb := Vector2(b["x"], b["y"])
	var pts := Geometry2D.get_closest_points_between_segments(ca - ha, ca + ha, cb - hb, cb + hb)
	return pts[0].distance_to(pts[1]) - ra - rb


## The element with the most stones: a class of inner gem lines (not the
## silhouette's, nor bold lines) as {"lines": class}, or a symmetry group of
## areas as {"areas": [their centroids]}; {} if none.
static func _busiest_element(picture: Dictionary) -> Dictionary:
	var list := _elements_by_size(picture)
	return list[0]["element"] if not list.is_empty() else {}


## The elements _busiest_element picks from, busiest first: [{element, stones}].
static func _elements_by_size(picture: Dictionary) -> Array:
	var lines := {}
	var areas := {}
	for s in picture["slots"]:
		var region: Dictionary = picture["regions"][s["region"]]
		if region["kind"] == "area":
			areas[region["group"]] = areas.get(region["group"], 0) + 1
		elif region.get("line", "") != "outer" and s["part"] < GemLines.NODE_PARTS and not (s["seq"] < 0 and s["tone"] == 1):
			lines[s["part"]] = lines.get(s["part"], 0) + 1
	var out := []
	for part: int in lines:
		out.append({"element": {"lines": part}, "stones": lines[part]})
	for g: int in areas:
		var at := []
		for r in picture["regions"]:
			if r["kind"] == "area" and r["group"] == g:
				at.append(r["centroid"])
		out.append({"element": {"areas": at}, "stones": areas[g]})
	# Busiest first; lines before areas on a tie, as before.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["stones"] > b["stones"])
	return out


## How many symmetry groups the areas left out (by centroid) belong to.
static func _bare_groups(bare_at: Array, groups: PackedInt32Array, map: RegionMap) -> int:
	var seen := {}
	for at: Vector2 in bare_at:
		for r in map.regions:
			if (r["centroid"] as Vector2).distance_to(at) < 3.0:
				seen[groups[r["id"]]] = true
	return seen.size()


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


## How wide a line two areas may face each other across, in px: the widest
## gem-line stone with its channel, or a few stones' width for metal lines.
static func _neighbor_reach(line_slots: Array, unit: float, gap: float) -> float:
	var widest := unit * 2.0
	for sl: Dictionary in line_slots:
		widest = maxf(widest, float(sl["width"]) + gap * (1.0 + 2.0 * LINE_PAD))
	return widest + 3.0


## The theme's colors snapped to `gems`, each gem once, in theme order (the
## theme itself when there are no gems to snap to).
static func _snapped_palette(theme: PackedColorArray, gems: Array) -> PackedColorArray:
	if gems.is_empty():
		return theme
	var out := PackedColorArray()
	var seen := {}
	var snapped := RegionPaint.snap_to_gems(theme, gems)
	for i in snapped.size():
		var g: Dictionary = gems[snapped[i]]
		if not seen.has(str(g["id"])):
			seen[str(g["id"])] = true
			out.append(g["color"])
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
	for reach in [slot["width"] / 2.0 + gap * LINE_PAD + 2.0, slot["width"] / 2.0 + gap * LINE_PAD + 5.0]:
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

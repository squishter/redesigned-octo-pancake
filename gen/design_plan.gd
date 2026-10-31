class_name DesignPlan
extends RefCounted
## Per-design choices that keep pictures from all looking alike: how full each
## region gets and which of the lines are shown.
##
## Choices are made per symmetry group, so symmetric copies always match.
##
## Fills:
##   full: packed by the region's own style (about 80% covered)
##   scatter: a few small stones spread out with breathing room
##   accent: a single stone at the region's heart, nearly filling it (only
##           compact regions, so it doesn't sit alone in a long empty one)
##   outline: only a rhinestone border along the region's edge
##   bare: no stones; the background shows through as negative space (only
##         regions roomy enough for it to look deliberate)
##
## Line styles:
##   full: every line is drawn
##   partial: only the lines around some groups are drawn
##   outer: only the picture's silhouette is drawn
##   none: no lines; the stones alone make the picture
## Hidden lines still separate the regions for slot packing; they just aren't
## drawn.
##
## Dense groups (the "dense" option, a share of the groups): packed with
## smaller stones closer together (see SlotPacker.DENSE_GAP), and always
## full, so only the other groups can go sparse.

const FILLS := ["full", "scatter", "accent", "outline", "bare"]
const LINE_STYLES := ["full", "partial", "outer", "none"]
## Sparsity values a seed picks from when none is given. Half the designs stay
## fully packed.
const AUTO_SPARSITY := [0.0, 0.0, 0.0, 0.2, 0.35, 0.5]
## Line style weights for "auto".
const AUTO_LINE_WEIGHTS := {"full": 0.5, "partial": 0.25, "outer": 0.15, "none": 0.1}
## Caps on how much of the picture's area may go sparse, and how much bare.
const MAX_SPARSE_AREA := 0.6
const MAX_BARE_AREA := 0.3
## Bare regions are at least this deep (in stone units), so they read as
## negative space rather than gaps.
const BARE_MIN_DEPTH := 2.0
## Accent regions are at most this deep (in stone units) and this spread out
## (area over the deepest circle's), so their one stone nearly fills them.
const ACCENT_MAX_DEPTH := 3.0
const ACCENT_MAX_SPREAD := 2.5


## options:
##   sparsity: 0..1, the chance each group gets a sparse fill (default -1:
##             picked from AUTO_SPARSITY by the seed)
##   line_style: one of LINE_STYLES or "auto" (default "auto")
##   unit: base stone radius in px, as for SlotPacker (default SlotPacker.UNIT of the picture)
##   dense: 0..1, the share of groups packed dense (default 0)
## Returns {sparsity, line_style, fills: PackedStringArray per region,
##          outlined: PackedByteArray per region, dense: PackedByteArray per
##          region, keep_outer: bool}.
static func make(map: RegionMap, groups: PackedInt32Array, options: Dictionary, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	# Its own stream, so the plan doesn't shift the packer's or colors' choices.
	rng.seed = seed_value * 7919 + 13
	var sparsity: float = options.get("sparsity", -1.0)
	if sparsity < 0.0:
		sparsity = AUTO_SPARSITY[rng.randi_range(0, AUTO_SPARSITY.size() - 1)]
	var line_style: String = options.get("line_style", "auto")
	if not line_style in LINE_STYLES:
		line_style = _weighted_pick(AUTO_LINE_WEIGHTS, rng)
	var unit: float = options.get("unit", minf(map.width, map.height) * SlotPacker.UNIT)

	var n_groups := 0
	for g in groups:
		n_groups = maxi(n_groups, g + 1)
	var group_area := PackedFloat32Array()
	group_area.resize(n_groups)
	var group_depth := PackedFloat32Array()  # smallest max_dist among members
	group_depth.resize(n_groups)
	group_depth.fill(INF)
	# Area over the deepest circle's: 1 for a disc, more the longer or
	# lumpier the region (largest among members).
	var group_spread := PackedFloat32Array()
	group_spread.resize(n_groups)
	var total_area := 0.0
	for r in map.regions:
		var g := groups[r["id"]]
		group_area[g] += r["area"]
		group_depth[g] = minf(group_depth[g], r["max_dist"])
		group_spread[g] = maxf(group_spread[g], r["area"] / (PI * r["max_dist"] * r["max_dist"]))
		total_area += r["area"]

	# Dense groups: that share of them, picked in an order of their own so the
	# other choices stay as they were.
	var group_dense := PackedByteArray()
	group_dense.resize(n_groups)
	var dense: float = options.get("dense", 0.0)
	if dense > 0.0:
		var dense_rng := RandomNumberGenerator.new()
		dense_rng.seed = hash([seed_value, "dense"])
		var order := _shuffled(n_groups, dense_rng)
		for i in mini(n_groups, roundi(n_groups * dense)):
			group_dense[order[i]] = 1

	var group_fill := PackedStringArray()
	group_fill.resize(n_groups)
	group_fill.fill("full")
	var sparse_area := 0.0
	var bare_area := 0.0
	for g in _shuffled(n_groups, rng):
		if group_dense[g] == 1:
			continue
		if rng.randf() >= sparsity or sparse_area + group_area[g] > MAX_SPARSE_AREA * total_area:
			continue
		var depth := group_depth[g]
		var choices := []
		# One stone that fills most of the region, not one adrift in it.
		if depth >= unit * 1.6 and depth <= unit * ACCENT_MAX_DEPTH and group_spread[g] <= ACCENT_MAX_SPREAD:
			choices.append("accent")
		if depth >= unit * 3.0:
			choices.append_array(["scatter", "scatter", "outline"])
		# Small bare regions read as holes, not negative space.
		if depth >= unit * BARE_MIN_DEPTH and bare_area + group_area[g] <= MAX_BARE_AREA * total_area:
			choices.append("bare")
		if choices.is_empty():
			continue
		var fill: String = choices[rng.randi_range(0, choices.size() - 1)]
		group_fill[g] = fill
		sparse_area += group_area[g]
		if fill == "bare":
			bare_area += group_area[g]
	# Something always stays fully packed: the biggest group if nothing else.
	if n_groups > 0 and not "full" in group_fill:
		var biggest := 0
		for g in n_groups:
			if group_area[g] > group_area[biggest]:
				biggest = g
		group_fill[biggest] = "full"

	var group_outlined := PackedByteArray()
	group_outlined.resize(n_groups)
	match line_style:
		"full":
			group_outlined.fill(1)
		"partial":
			for g in n_groups:
				group_outlined[g] = 1 if rng.randf() < 0.5 else 0
			# Make sure it really is partial.
			if n_groups >= 2 and not 0 in group_outlined:
				group_outlined[rng.randi_range(0, n_groups - 1)] = 0
			if n_groups >= 2 and not 1 in group_outlined:
				group_outlined[rng.randi_range(0, n_groups - 1)] = 1

	var fills := PackedStringArray()
	var outlined := PackedByteArray()
	var dense_regions := PackedByteArray()
	for r in map.regions.size():
		fills.append(group_fill[groups[r]])
		outlined.append(group_outlined[groups[r]])
		dense_regions.append(group_dense[groups[r]])
	return {
		"sparsity": sparsity,
		"line_style": line_style,
		"fills": fills,
		"outlined": outlined,
		"dense": dense_regions,
		"keep_outer": line_style != "none",
	}


## The lines to draw for a plan: each line pixel belongs to the region (or the
## background) nearest to it, and is drawn if that region is outlined. A line
## between an outlined region and a hidden one shows only its outlined half.
static func visible_lines(map: RegionMap, plan: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(map.width * map.height)
	if plan["line_style"] == "none":
		return out
	var outlined: PackedByteArray = plan["outlined"]
	var keep_outer: bool = plan["keep_outer"]
	var owners := map.line_owners()
	for i in out.size():
		if map.labels[i] != RegionMap.LINE:
			continue
		var o := owners[i]
		if (o >= 0 and outlined[o]) or (o < 0 and keep_outer):
			out[i] = 255
	return out


## Packer style per region for the sparse fills ("full" leaves the packer to
## choose), as SlotPacker's `styles` option.
static func packer_styles(plan: Dictionary) -> Dictionary:
	var styles := {}
	var fills: PackedStringArray = plan["fills"]
	for r in fills.size():
		if fills[r] != "full":
			styles[r] = fills[r]
	return styles


static func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var pick := rng.randf() * total
	for k in weights:
		pick -= weights[k]
		if pick <= 0.0:
			return k
	return weights.keys()[0]


## 0..n-1 in a seeded random order (Array.shuffle uses the global RNG).
static func _shuffled(n: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var out := PackedInt32Array(range(n))
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := out[i]
		out[i] = out[j]
		out[j] = t
	return out

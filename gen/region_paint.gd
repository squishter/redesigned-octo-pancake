class_name RegionPaint
extends RefCounted
## Region colors: theme colors that respect a picture's symmetry, colors
## sampled from a source image, snapping to gem colors, and flat renders of a
## colored RegionMap (the Kit-mode source for line art).


## Groups regions that are symmetric copies of each other, so they can share a
## color. Regions match when their centroids sit at the same distance from the
## center (radial) or mirror across the vertical axis (mirror) and their areas
## are close. symmetry "none" puts every region in its own group.
## Returns a group id per region, numbered from the center outward (radial)
## or top to bottom (mirror).
static func symmetry_groups(map: RegionMap, symmetry: String) -> PackedInt32Array:
	var n := map.regions.size()
	var center := Vector2(map.width, map.height) / 2.0
	var tol := minf(map.width, map.height) * 0.015
	var keys := []  # [primary, secondary, area, region id]
	for r in map.regions:
		var c: Vector2 = r["centroid"]
		match symmetry:
			"radial":
				keys.append([c.distance_to(center), 0.0, float(r["area"]), r["id"]])
			"mirror":
				keys.append([c.y, absf(c.x - center.x), float(r["area"]), r["id"]])
			_:
				keys.append([c.y, c.x, float(r["area"]), r["id"]])
	keys.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var group_of := PackedInt32Array()
	group_of.resize(n)
	var groups := []  # [primary, secondary, area] of each group's first member
	for k in keys:
		var found := -1
		if symmetry != "none":
			for g in range(groups.size() - 1, -1, -1):
				var gk: Array = groups[g]
				if k[0] - gk[0] > tol:
					break
				var ratio: float = k[2] / gk[2]
				if absf(k[1] - gk[1]) <= tol and ratio < 1.35 and ratio > 1.0 / 1.35:
					found = g
					break
		if found < 0:
			found = groups.size()
			groups.append([k[0], k[1], k[2]])
		group_of[k[3]] = found
	return group_of


## Joins the groups of regions that hold a mark of the same motif family
## (`marks`: [{"at": px, "family"}], see PictureSources.mandala_lines), so
## all of a free-form picture's leaves, say, share colors and a pattern
## though they aren't copies of each other. Marks on lines are skipped.
## Groups are renumbered in the order of their first regions.
static func motif_groups(map: RegionMap, groups: PackedInt32Array, marks: Array) -> PackedInt32Array:
	var n_groups := 0
	for g in groups:
		n_groups = maxi(n_groups, g + 1)
	var parent := range(n_groups)
	var find := func(g: int) -> int:
		while parent[g] != g:
			g = parent[g]
		return g
	var family_group := {}
	for m: Dictionary in marks:
		var at: Vector2 = m["at"]
		var x := int(at.x)
		var y := int(at.y)
		if x < 0 or y < 0 or x >= map.width or y >= map.height:
			continue
		var label := map.labels[y * map.width + x]
		if label < 0:
			continue
		var g: int = find.call(groups[label])
		var f: int = m["family"]
		if not family_group.has(f):
			family_group[f] = g
			continue
		var other: int = find.call(family_group[f])
		if other != g:
			parent[maxi(g, other)] = mini(g, other)
	var renumber := {}
	var out := PackedInt32Array()
	out.resize(groups.size())
	for r in groups.size():
		var root: int = find.call(groups[r])
		if not renumber.has(root):
			renumber[root] = renumber.size()
		out[r] = renumber[root]
	return out


## Colors at least this far apart (CIE76 delta E in Lab) read as different
## next to each other; closer ones (ruby by garnet, say) blur together.
const MIN_CONTRAST := 18.0
## The chance that two neighboring groups may show the same accent or
## feature color anyway (see may_match), so pictures aren't too strict.
const SAME_COLOR_CHANCE := 0.05
## The share of a palette that counts as quiet (see split_palette).
const QUIET_SHARE := 0.34


## Neighboring groups: per group, the other groups (sorted) holding a region
## next to one of its regions (`adjacency` from RegionMap.adjacency).
static func group_neighbors(adjacency: Array, groups: PackedInt32Array) -> Array:
	var n_groups := 0
	for g in groups:
		n_groups = maxi(n_groups, g + 1)
	var sets := []
	for g in n_groups:
		sets.append({})
	for r in mini(adjacency.size(), groups.size()):
		for other: int in adjacency[r]:
			if other < groups.size() and groups[other] != groups[r]:
				sets[groups[r]][groups[other]] = true
	var out := []
	for g in n_groups:
		var list: Array = sets[g].keys()
		list.sort()
		out.append(list)
	return out


## Whether neighboring groups `a` and `b` may share an accent or feature
## color: a seeded SAME_COLOR_CHANCE per pair, the same either way round.
static func may_match(seed_value: int, a: int, b: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, mini(a, b), maxi(a, b), "same color"])
	return rng.randf() < SAME_COLOR_CHANCE


## Whether two colors read as different side by side.
static func contrasts(a: Color, b: Color) -> bool:
	return LabColor.from_color(a).distance_to(LabColor.from_color(b)) >= MIN_CONTRAST


## Index of a palette color for one group: a random one of those that
## contrast with every color in `avoid` (a list of tiers, most important
## first); when none does, the last tiers are dropped one by one. With none
## left even for the first tier, the color farthest from it.
static func _pick(palette: PackedColorArray, avoid: Array, rng: RandomNumberGenerator) -> int:
	var labs := PackedVector3Array()
	for c in palette:
		labs.append(LabColor.from_color(c))
	for keep in range(avoid.size(), 0, -1):
		var choices := []
		for i in palette.size():
			var ok := true
			for t in keep:
				for c: Color in avoid[t]:
					if labs[i].distance_to(LabColor.from_color(c)) < MIN_CONTRAST:
						ok = false
						break
				if not ok:
					break
			if ok:
				choices.append(i)
		if not choices.is_empty():
			return choices[rng.randi_range(0, choices.size() - 1)]
	if avoid.is_empty() or (avoid[0] as Array).is_empty():
		return rng.randi_range(0, palette.size() - 1)
	var best := 0
	var best_d := -1.0
	for i in palette.size():
		var d := INF
		for c: Color in avoid[0]:
			d = minf(d, labs[i].distance_to(LabColor.from_color(c)))
		if d > best_d:
			best_d = d
			best = i
	return best


## A theme color per region. Symmetric copies share a color. Given
## `neighbors` (group_neighbors), groups that touch get colors that read as
## different (MIN_CONTRAST), the most hemmed-in groups choosing first; when
## the palette runs short, a group takes the color farthest from its
## neighbors'. Without it, each group avoids the colors of the two groups
## before it, so neighboring rings differ.
## `groups` (default: symmetry_groups) says which regions share one.
static func theme_colors(map: RegionMap, symmetry: String, palette: PackedColorArray, seed_value: int,
		groups := PackedInt32Array(), neighbors: Array = []) -> PackedColorArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if groups.is_empty():
		groups = symmetry_groups(map, symmetry)
	var n_groups := 0
	for g in groups:
		n_groups = maxi(n_groups, g + 1)
	var group_color := PackedInt32Array()
	group_color.resize(n_groups)
	if neighbors.size() >= n_groups and n_groups > 0:
		group_color.fill(-1)
		# DSatur: the group whose neighbors already show the most colors goes
		# next, then the one with most neighbors, then the one nearest the center.
		for _step in n_groups:
			var pick := -1
			var pick_sat := -1
			for g in n_groups:
				if group_color[g] >= 0:
					continue
				var seen := {}
				for o: int in neighbors[g]:
					if group_color[o] >= 0:
						seen[group_color[o]] = true
				var sat := seen.size()
				if sat > pick_sat or (sat == pick_sat and neighbors[g].size() > neighbors[pick].size()):
					pick = g
					pick_sat = sat
			var near := []
			for o: int in neighbors[pick]:
				if group_color[o] >= 0:
					near.append(palette[group_color[o]])
			group_color[pick] = _pick(palette, [near], rng)
	else:
		for g in n_groups:
			var choices := []
			for c in palette.size():
				if (g < 1 or group_color[g - 1] != c) and (g < 2 or group_color[g - 2] != c):
					choices.append(c)
			if choices.is_empty():
				choices = range(palette.size())
			group_color[g] = choices[rng.randi_range(0, choices.size() - 1)]
	var out := PackedColorArray()
	out.resize(map.regions.size())
	for r in map.regions.size():
		out[r] = palette[group_color[groups[r]]]
	return out


## A palette split by how far its colors stand from `paper` (in Lab): {"bold":
## the ones that stand out, "quiet": the QUIET_SHARE nearest it (at least
## one, and two of a palette of four or more)}, each in the palette's order.
## A palette of one color is both.
static func split_palette(palette: PackedColorArray, paper: Color) -> Dictionary:
	var lab := LabColor.from_color(paper)
	var order := range(palette.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var da := LabColor.from_color(palette[a]).distance_to(lab)
		var db := LabColor.from_color(palette[b]).distance_to(lab)
		return da < db or (da == db and a < b))
	var n_quiet := clampi(roundi(palette.size() * QUIET_SHARE), 2 if palette.size() >= 4 else 1, maxi(1, palette.size() - 1))
	var is_quiet := {}
	for i in mini(n_quiet, order.size()):
		is_quiet[order[i]] = true
	var bold := PackedColorArray()
	var quiet := PackedColorArray()
	for i in palette.size():
		if is_quiet.has(i):
			quiet.append(palette[i])
		else:
			bold.append(palette[i])
	if bold.is_empty():
		bold = quiet
	return {"bold": bold, "quiet": quiet}


## The groups that hold a mark of a bold family (`marks` as for
## motif_groups, `bold`: family -> true): group -> true.
static func bold_groups(map: RegionMap, groups: PackedInt32Array, marks: Array, bold: Dictionary) -> Dictionary:
	var out := {}
	for m: Dictionary in marks:
		if not bold.has(m["family"]):
			continue
		var at: Vector2 = m["at"]
		var label := map.label_at(int(at.x), int(at.y))
		if label >= 0:
			out[groups[label]] = true
	return out


## A color per region by its group's role: groups in `bold` (group -> true)
## take any of the palette's bold colors, the others its quiet ones
## (`split`: split_palette's). Groups that touch get colors that read apart
## where their palette allows, the groups with most neighbors choosing
## first, and quiet groups each a quiet color of their own while they last.
static func role_colors(map: RegionMap, groups: PackedInt32Array, split: Dictionary, seed_value: int,
		neighbors: Array, bold: Dictionary) -> PackedColorArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "roles"])
	var n_groups := 0
	for g in groups:
		n_groups = maxi(n_groups, g + 1)
	var order := range(n_groups)
	order.sort_custom(func(a: int, b: int) -> bool:
		var na: int = neighbors[a].size() if a < neighbors.size() else 0
		var nb: int = neighbors[b].size() if b < neighbors.size() else 0
		return na > nb or (na == nb and a < b))
	var group_color := {}
	# Quiet colors in use, so quiet groups differ from each other (a plant's
	# stems from its leaves) even where they don't touch, while colors last.
	var quiet_used := []
	for g: int in order:
		var palette: PackedColorArray = split["bold"] if bold.has(g) else split["quiet"]
		var near := []
		if g < neighbors.size():
			for o: int in neighbors[g]:
				if group_color.has(o):
					near.append(group_color[o])
		if bold.has(g):
			group_color[g] = palette[_pick(palette, [near], rng)]
			continue
		var fresh := PackedColorArray()
		for c in palette:
			if not c in quiet_used:
				fresh.append(c)
		if fresh.is_empty():
			fresh = palette
		group_color[g] = fresh[_pick(fresh, [near], rng)]
		quiet_used.append(group_color[g])
	var out := PackedColorArray()
	out.resize(map.regions.size())
	for r in map.regions.size():
		out[r] = group_color[groups[r]]
	return out


## A second color per region for its pattern's accent stones: a palette
## color that contrasts with the region's own colors (`colors`, plus `also`
## when given, as for a third color that should differ from both the region's
## color and its accent), shared by symmetric copies. Given `neighbors`
## (group_neighbors), it also contrasts with the neighboring groups' colors
## and with the accents already chosen next door, except for the odd pair
## that may_match lets share one. When the palette runs short, the accents
## next door give way first, then the neighbors' colors, then `also`.
static func accent_colors(map: RegionMap, groups: PackedInt32Array, colors: PackedColorArray,
		palette: PackedColorArray, seed_value: int, neighbors: Array = [],
		also := PackedColorArray()) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(map.regions.size())
	var by_group := {}
	# Each group's colors, and its neighbors' (all regions of a group share them).
	var group_color := {}
	var group_also := {}
	for r in map.regions.size():
		group_color[groups[r]] = colors[r]
		if not also.is_empty():
			group_also[groups[r]] = also[r]
	for r in map.regions.size():
		var g := groups[r]
		if not by_group.has(g):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([seed_value, g, "accent"])
			var own := [colors[r]]
			var second := [group_also[g]] if group_also.has(g) else []
			var next_door := []
			var next_accents := []
			if g < neighbors.size():
				for o: int in neighbors[g]:
					if may_match(seed_value, g, o):
						continue
					if group_color.has(o):
						next_door.append(group_color[o])
					if group_also.has(o):
						next_door.append(group_also[o])
					if by_group.has(o):
						next_accents.append(by_group[o])
			# Strictly unlike its own color, then unlike its other color, its
			# neighbors' colors and the accents already chosen next door.
			var choices := []
			for c in palette:
				if not c.is_equal_approx(colors[r]):
					choices.append(c)
			if choices.is_empty():
				by_group[g] = colors[r]
			else:
				var pal := PackedColorArray(choices)
				by_group[g] = pal[_pick(pal, [own, second, next_door, next_accents], rng)]
		out[r] = by_group[g]
	return out


## The mean color of `img` over each region. The image is scaled to the map.
static func image_colors(map: RegionMap, img: Image) -> PackedColorArray:
	var src := img.duplicate() as Image
	if src.is_compressed():
		src.decompress()
	if src.get_width() != map.width or src.get_height() != map.height:
		src.resize(map.width, map.height, Image.INTERPOLATE_BILINEAR)
	var sums := PackedVector3Array()
	sums.resize(map.regions.size())
	var counts := PackedInt32Array()
	counts.resize(map.regions.size())
	for y in map.height:
		for x in map.width:
			var l := map.labels[y * map.width + x]
			if l >= 0:
				var c := src.get_pixel(x, y)
				sums[l] += Vector3(c.r, c.g, c.b)
				counts[l] += 1
	var out := PackedColorArray()
	out.resize(map.regions.size())
	for r in map.regions.size():
		var m := sums[r] / maxf(1.0, counts[r])
		out[r] = Color(m.x, m.y, m.z)
	return out


## Index into `gems` (Array of {"id", "color"}) of the closest gem per color.
static func snap_to_gems(colors: PackedColorArray, gems: Array) -> PackedInt32Array:
	var gem_lab := PackedVector3Array()
	for g in gems:
		gem_lab.append(LabColor.from_color(g["color"]))
	var out := PackedInt32Array()
	out.resize(colors.size())
	for i in colors.size():
		out[i] = LabColor.nearest(LabColor.from_color(colors[i]), gem_lab)
	return out


## Flat render: regions in their colors, lines (and merged tiny regions) in
## line_color, everything outside the picture in background. If `visible` is
## given, line pixels it leaves out take the color of the nearest region
## instead, so hidden lines disappear.
static func render(map: RegionMap, colors: PackedColorArray, line_color: Color, background: Color,
		visible: PackedByteArray = PackedByteArray()) -> Image:
	var img := Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)
	var owners: PackedInt32Array = PackedInt32Array() if visible.is_empty() else map.line_owners()
	for y in map.height:
		for x in map.width:
			var i := y * map.width + x
			var l := map.labels[i]
			var c: Color
			if l >= 0:
				c = colors[l]
			elif l == RegionMap.LINE:
				if visible.is_empty() or visible[i]:
					c = line_color
				else:
					c = colors[owners[i]] if owners[i] >= 0 else background
			else:
				c = background
			img.set_pixel(x, y, c)
	return img

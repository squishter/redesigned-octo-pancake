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


## A theme color per region. Symmetric copies share a color, and each group
## avoids the colors of the two groups before it so neighboring rings differ.
## `groups` (default: symmetry_groups) says which regions share one.
static func theme_colors(map: RegionMap, symmetry: String, palette: PackedColorArray, seed_value: int,
		groups := PackedInt32Array()) -> PackedColorArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if groups.is_empty():
		groups = symmetry_groups(map, symmetry)
	var n_groups := 0
	for g in groups:
		n_groups = maxi(n_groups, g + 1)
	var group_color := PackedInt32Array()
	for g in n_groups:
		var choices := []
		for c in palette.size():
			if (g < 1 or group_color[g - 1] != c) and (g < 2 or group_color[g - 2] != c):
				choices.append(c)
		if choices.is_empty():
			choices = range(palette.size())
		group_color.append(choices[rng.randi_range(0, choices.size() - 1)])
	var out := PackedColorArray()
	out.resize(map.regions.size())
	for r in map.regions.size():
		out[r] = palette[group_color[groups[r]]]
	return out


## A second color per region for its pattern's accent stones: a palette
## color other than the region's own, shared by symmetric copies.
static func accent_colors(map: RegionMap, groups: PackedInt32Array, colors: PackedColorArray,
		palette: PackedColorArray, seed_value: int) -> PackedColorArray:
	var out := PackedColorArray()
	var by_group := {}
	for r in map.regions.size():
		var g := groups[r]
		if not by_group.has(g):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([seed_value, g, "accent"])
			var choices := []
			for c in palette:
				if not c.is_equal_approx(colors[r]):
					choices.append(c)
			by_group[g] = choices[rng.randi_range(0, choices.size() - 1)] if not choices.is_empty() else colors[r]
		out.append(by_group[g])
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

class_name LinePaint
extends RefCounted
## The lines a picture keeps as drawn outlines (its `lines_visible`, the
## "metal" setting; see CollageGenerator), split into groups the player
## paints like gems: each group is one "slot" that fills all at once.
##
## Nothing here changes how pictures are made: groups are worked out from the
## saved picture when it's played, so every puzzle with kept lines, old or
## new, gets them, and the same picture always gives the same groups.
##
## A thin line pixel's group is the pair of symmetry groups (CollageGenerator's
## region `group`) on its two sides, so symmetric copies of a line share a
## group: every petal's outline, every ring between two bands. Thick parts
## (bands and blobs much wider than the lines) are each one group, keyed by
## every symmetry group around them, so a wide band touching many areas
## stays whole and its symmetric copies share it. Groups too small to find
## with a finger join the group next to them. Each group takes
## a color from the board: the accent color of the smaller area it borders
## (its own color when it has no accent), so groups of one color share a
## paint.

## Labels: the group of each pixel, or NONE.
const NONE := 255
## Groups smaller than this share of all kept line pixels (and at least
## MIN_PX) join a neighbor.
const MIN_SHARE := 1.0 / 300.0
const MIN_PX := 30
## At most this many groups (labels are bytes); the smallest beyond it join
## a neighbor.
const MAX_GROUPS := 200
## Bumped whenever build() would group a picture differently, so groups
## cached by an older version (see SaveStore.load_line_groups) are rebuilt.
const FORMAT := 2
## A line pixel at least this many px (4-connected) from the nearest area,
## and this share of the picture's shorter side (about 1.6 times as deep as
## the middle of a line drawn PictureSources' usual width, side / 170), is
## in a thick part.
const THICK_MIN_DEPTH := 4
const THICK_SHARE := 1.6 / 170.0

## Pixel offsets, 4- and 8-connected.
const _N4 := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
const _N8 := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]


## Whether `picture` keeps any lines as drawn outlines.
static func has_lines(picture: Dictionary) -> bool:
	var vis: PackedByteArray = picture.get("lines_visible", PackedByteArray())
	var w := int(picture.get("width", 0))
	var h := int(picture.get("height", 0))
	return w > 0 and h > 0 and vis.size() == w * h and vis.count(0) < vis.size()


## The picture's line groups: {width, height, labels: PackedByteArray (a
## group per pixel, NONE off the kept lines), groups: [{color: Color,
## count: pixels, at: Vector2 (a pixel of it near its middle), rect: Rect2}]}.
## Empty when it keeps no lines.
static func build(picture: Dictionary) -> Dictionary:
	if not has_lines(picture):
		return {}
	var w := int(picture["width"])
	var h := int(picture["height"])
	var n := w * h
	var vis: PackedByteArray = picture["lines_visible"]
	var full: PackedByteArray = picture.get("lines", PackedByteArray())
	if full.size() != n:
		full = vis

	# Areas between the lines (4-connected), and which touch the edge.
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	for i in n:
		if full[i] != 0 or vis[i] != 0:
			comp[i] = -2
	var queue := PackedInt32Array()
	queue.resize(n)
	var edge_comps := {}
	var comps := 0
	for start in n:
		if comp[start] != -1:
			continue
		var c := comps
		comps += 1
		comp[start] = c
		var head := 0
		var tail := 1
		queue[0] = start
		var on_edge := false
		while head < tail:
			var i := queue[head]
			head += 1
			var y := i / w
			var x := i - y * w
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				on_edge = true
			if x > 0 and comp[i - 1] == -1:
				comp[i - 1] = c
				queue[tail] = i - 1
				tail += 1
			if x < w - 1 and comp[i + 1] == -1:
				comp[i + 1] = c
				queue[tail] = i + 1
				tail += 1
			if y > 0 and comp[i - w] == -1:
				comp[i - w] = c
				queue[tail] = i - w
				tail += 1
			if y < h - 1 and comp[i + w] == -1:
				comp[i + w] = c
				queue[tail] = i + w
				tail += 1
		if on_edge:
			edge_comps[c] = true

	# Each area's symmetry group, from the stones in it (-1 the background,
	# and areas with no stones a group of their own).
	var regions: Array = picture.get("regions", [])
	var comp_region := PackedInt32Array()
	comp_region.resize(comps)
	comp_region.fill(-1)
	for s: Dictionary in picture.get("slots", []):
		var x := clampi(int(s["x"]), 0, w - 1)
		var y := clampi(int(s["y"]), 0, h - 1)
		var c := comp[y * w + x]
		var r := int(s.get("region", -1))
		if c >= 0 and comp_region[c] < 0 and r >= 0 and r < regions.size() and regions[r].get("kind", "area") == "area":
			comp_region[c] = r
	var comp_group := PackedInt32Array()
	comp_group.resize(comps)
	for c in comps:
		if edge_comps.has(c) and comp_region[c] < 0:
			comp_group[c] = -1
		elif comp_region[c] >= 0:
			comp_group[c] = int(regions[comp_region[c]].get("group", comp_region[c]))
		else:
			comp_group[c] = 1000000 + c

	# Every line pixel takes the area nearest it (a breadth-first sweep in
	# from both sides, so a line splits down its middle).
	var near := comp.duplicate()
	var depth := PackedInt32Array()
	depth.resize(n)
	var tail := 0
	for i in n:
		if near[i] != -2:
			continue
		var y := i / w
		var x := i - y * w
		var o := -2
		if x > 0 and comp[i - 1] >= 0:
			o = comp[i - 1]
		elif x < w - 1 and comp[i + 1] >= 0:
			o = comp[i + 1]
		elif y > 0 and comp[i - w] >= 0:
			o = comp[i - w]
		elif y < h - 1 and comp[i + w] >= 0:
			o = comp[i + w]
		if o >= 0:
			near[i] = o
			depth[i] = 1
			queue[tail] = i
			tail += 1
	var head := 0
	while head < tail:
		var i := queue[head]
		head += 1
		var y := i / w
		var x := i - y * w
		for d: Vector2i in _N4:
			var xx := x + d.x
			var yy := y + d.y
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			var j := yy * w + xx
			if near[j] == -2:
				near[j] = near[i]
				depth[j] = depth[i] + 1
				queue[tail] = j
				tail += 1

	var key_of := {}
	var keys: Array = []
	var label := PackedInt32Array()
	label.resize(n)
	label.fill(-1)
	_label_thick(vis, comp, comp_group, depth, label, key_of, keys, queue, w, h)

	# The pair of groups on the two sides: read where the two halves of a
	# line meet, then spread across its width.
	tail = 0
	for i in n:
		if vis[i] == 0 or near[i] < 0 or label[i] >= 0:
			continue
		var y := i / w
		var x := i - y * w
		var a := comp_group[near[i]]
		for d: Vector2i in _N4:
			var xx := x + d.x
			var yy := y + d.y
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			var j := yy * w + xx
			if near[j] >= 0 and near[j] != near[i] and comp[j] == -2 and label[j] < 0:
				var b := comp_group[near[j]]
				var k := [mini(a, b), maxi(a, b)]
				if not key_of.has(k):
					key_of[k] = keys.size()
					keys.append(k)
				label[i] = key_of[k]
				queue[tail] = i
				tail += 1
				break
	_spread(label, vis, queue, tail, w, h, _N4)
	# Lines with the same area on both sides (loose ends, spurs).
	for i in n:
		if vis[i] != 0 and label[i] < 0 and near[i] >= 0:
			var a := comp_group[near[i]]
			var k := [a, a]
			if not key_of.has(k):
				key_of[k] = keys.size()
				keys.append(k)
			label[i] = key_of[k]

	# Small groups join a neighbor (the biggest groups are kept first).
	var counts := PackedInt32Array()
	counts.resize(keys.size())
	var total := 0
	for i in n:
		if label[i] >= 0:
			counts[label[i]] += 1
			total += 1
	var order := range(keys.size())
	order.sort_custom(func(p: int, q: int) -> bool: return counts[p] > counts[q] or (counts[p] == counts[q] and p < q))
	var least := maxi(MIN_PX, int(total * MIN_SHARE))
	var keep := {}
	for k: int in order:
		if keep.size() < MAX_GROUPS and (counts[k] >= least or keep.is_empty()):
			keep[k] = true
	tail = 0
	for i in n:
		if label[i] < 0:
			continue
		if keep.has(label[i]):
			queue[tail] = i
			tail += 1
		else:
			label[i] = -1
	_spread(label, vis, queue, tail, w, h, _N8)
	# Pieces cut off from every kept group (rare): the biggest group.
	var biggest: int = order[0]
	for i in n:
		if vis[i] != 0 and label[i] < 0:
			label[i] = biggest

	# Kept groups, numbered by size, with their colors and where they are.
	var index := {}
	var groups: Array[Dictionary] = []
	for k: int in order:
		if keep.has(k):
			index[k] = groups.size()
			groups.append({"key": keys[k], "count": 0, "sum": Vector2.ZERO, "min": Vector2i(w, h), "max": Vector2i(-1, -1)})
	var labels := PackedByteArray()
	labels.resize(n)
	labels.fill(NONE)
	for i in n:
		if label[i] < 0:
			continue
		var g: int = index[label[i]]
		labels[i] = g
		var y := i / w
		var x := i - y * w
		var gr: Dictionary = groups[g]
		gr["count"] += 1
		gr["sum"] += Vector2(x, y)
		gr["min"] = Vector2i(mini(gr["min"].x, x), mini(gr["min"].y, y))
		gr["max"] = Vector2i(maxi(gr["max"].x, x), maxi(gr["max"].y, y))
	var group_area := _group_areas(regions)
	var fallback := _main_color(picture)
	var out_groups := []
	for g in groups.size():
		var gr: Dictionary = groups[g]
		var mean: Vector2 = gr["sum"] / maxi(1, gr["count"])
		out_groups.append({
			"key": gr["key"],
			"color": _color_for(gr["key"], regions, group_area, fallback),
			"count": gr["count"],
			"at": _nearest_pixel(labels, w, h, g, mean),
			"rect": Rect2(Vector2(gr["min"]), Vector2(gr["max"] - gr["min"] + Vector2i.ONE)),
		})
	return {"format": FORMAT, "width": w, "height": h, "labels": labels, "groups": out_groups}


## Gives `lines`' groups their colors from `picture` again (a cached grouping
## keeps the groups' sides, not their colors, which a recolor may change).
static func recolor(lines: Dictionary, picture: Dictionary) -> void:
	var regions: Array = picture.get("regions", [])
	var group_area := _group_areas(regions)
	var fallback := _main_color(picture)
	for g: Dictionary in lines.get("groups", []):
		g["color"] = _color_for(g["key"], regions, group_area, fallback)


## Labels the thick parts of the kept lines (see THICK_MIN_DEPTH): each
## connected core deeper than the threshold, grown out to its rim (down the
## depth, so thin lines leaving it aren't taken), is keyed by "thick" and
## every symmetry group it touches.
static func _label_thick(vis: PackedByteArray, comp: PackedInt32Array, comp_group: PackedInt32Array,
		depth: PackedInt32Array, label: PackedInt32Array, key_of: Dictionary, keys: Array, queue: PackedInt32Array,
		w: int, h: int) -> void:
	var n := w * h
	var thick := maxi(THICK_MIN_DEPTH, roundi(mini(w, h) * THICK_SHARE))
	var part := PackedInt32Array()
	part.resize(n)
	part.fill(-1)
	var parts := 0
	for start in n:
		if vis[start] == 0 or depth[start] < thick or part[start] >= 0:
			continue
		# One core (8-connected), then down to its rim.
		var b := parts
		parts += 1
		part[start] = b
		var head := 0
		var tail := 1
		queue[0] = start
		while head < tail:
			var i := queue[head]
			head += 1
			var y := i / w
			var x := i - y * w
			for d: Vector2i in _N8:
				var xx := x + d.x
				var yy := y + d.y
				if xx < 0 or yy < 0 or xx >= w or yy >= h:
					continue
				var j := yy * w + xx
				if vis[j] != 0 and part[j] < 0 and depth[j] > 0 \
						and (depth[j] >= thick or depth[j] < depth[i]):
					part[j] = b
					queue[tail] = j
					tail += 1
		var around := {}
		for k in tail:
			var i := queue[k]
			var y := i / w
			var x := i - y * w
			for d: Vector2i in _N4:
				var xx := x + d.x
				var yy := y + d.y
				if xx < 0 or yy < 0 or xx >= w or yy >= h:
					continue
				var c := comp[yy * w + xx]
				if c >= 0:
					around[comp_group[c]] = true
		var groups := around.keys()
		groups.sort()
		var key := ["thick"] + groups
		if not key_of.has(key):
			key_of[key] = keys.size()
			keys.append(key)
		for k in tail:
			label[queue[k]] = key_of[key]


## Spreads labels from the first `tail` pixels in `queue` over the kept line
## pixels still unlabeled.
static func _spread(label: PackedInt32Array, vis: PackedByteArray, queue: PackedInt32Array, tail: int, w: int, h: int,
		steps: Array) -> void:
	var head := 0
	while head < tail:
		var i := queue[head]
		head += 1
		var y := i / w
		var x := i - y * w
		for d: Vector2i in steps:
			var xx := x + d.x
			var yy := y + d.y
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			var j := yy * w + xx
			if vis[j] != 0 and label[j] < 0:
				label[j] = label[i]
				queue[tail] = j
				tail += 1


## Each symmetry group's area and the first region of it: {group: [area, region]}.
static func _group_areas(regions: Array) -> Dictionary:
	var out := {}
	for r in regions.size():
		var region: Dictionary = regions[r]
		if region.get("kind", "area") != "area":
			continue
		var g := int(region.get("group", r))
		if not out.has(g):
			out[g] = [0, r]
		out[g][0] += int(region.get("area", 0))
	return out


## The color of a line between the symmetry groups in `key`: the smallest
## side's accent (or own) color.
static func _color_for(key: Array, regions: Array, group_area: Dictionary, fallback: Color) -> Color:
	var best := -1
	var best_area := 0
	for g: Variant in key:
		if g is int and group_area.has(g) and (best < 0 or group_area[g][0] < best_area):
			best = group_area[g][1]
			best_area = group_area[g][0]
	if best < 0:
		return fallback
	var region: Dictionary = regions[best]
	var accent: Variant = region.get("accent_color")
	if accent is Color:
		return accent
	return region.get("color", fallback)


## The picture's most used stone color.
static func _main_color(picture: Dictionary) -> Color:
	var counts := {}
	for s: Dictionary in picture.get("slots", []):
		var c: Color = s.get("target_color", Color.WHITE)
		counts[c] = counts.get(c, 0) + 1
	var best := Color("#c9a24a")
	var most := 0
	for c: Color in counts:
		if counts[c] > most:
			most = counts[c]
			best = c
	return best


## The pixel of group g nearest `p`, searching outward in rings.
static func _nearest_pixel(labels: PackedByteArray, w: int, h: int, g: int, p: Vector2) -> Vector2:
	var cx := clampi(int(p.x), 0, w - 1)
	var cy := clampi(int(p.y), 0, h - 1)
	for r in maxi(w, h):
		var best := -1.0
		var at := Vector2.ZERO
		for y in range(maxi(0, cy - r), mini(h, cy + r + 1)):
			var ring := absi(y - cy) == r
			var x := maxi(0, cx - r)
			while x < mini(w, cx + r + 1):
				if labels[y * w + x] == g:
					var d := Vector2(x, y).distance_squared_to(p)
					if best < 0.0 or d < best:
						best = d
						at = Vector2(x, y)
				if ring or x == cx + r:
					x += 1
				else:
					x = cx + r
		if best >= 0.0:
			return at + Vector2(0.5, 0.5)
	return p


## The group under board point `at` (picture px) that `wanted` accepts
## (a Callable taking a group, or always when not valid), within `radius`
## px: the nearest such pixel's group, or -1.
static func group_at(lines: Dictionary, at: Vector2, radius: float, wanted := Callable()) -> int:
	if lines.is_empty():
		return -1
	var w: int = lines["width"]
	var h: int = lines["height"]
	var labels: PackedByteArray = lines["labels"]
	var r := ceili(maxf(radius, 1.0))
	var best := -1
	var best_d := INF
	var ok := {}
	for y in range(maxi(0, int(at.y) - r), mini(h, int(at.y) + r + 1)):
		for x in range(maxi(0, int(at.x) - r), mini(w, int(at.x) + r + 1)):
			var g := labels[y * w + x]
			if g == NONE:
				continue
			if not ok.has(g):
				ok[g] = not wanted.is_valid() or wanted.call(g)
			if not ok[g]:
				continue
			var d := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_squared_to(at)
			if d < best_d and d <= radius * radius + 1.0:
				best_d = d
				best = g
	return best

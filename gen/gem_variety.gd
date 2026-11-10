class_name GemVariety
extends RefCounted
## Steers how many gem types a collage uses. A gem type is a shape, cut in
## one of its facet styles (see GemCuts), in a gem color (a small and a big
## brilliant round ruby are the same type), so a picture's variety comes
## from its shapes, cuts and colors, while sizes vary freely. Each shape in
## a color starts with its own seeded cut, so all its stones look alike.
##
## Stones are changed a whole pattern part at a time (a row, a ring, the
## center stones, a line's stones), across every symmetric copy at once, so
## every row and line keeps a single type and symmetry survives: a part is
## the stones of one symmetry group, pattern step and shape. When parts run
## out, the caller rebuilds with spacer rows (SlotPacker's `spacers`), which
## adds thin rows to vary.
##
## Shapes only swap within a family whose outlines fit the same slot:
## round, cushion, octagon, hexagon, flower, square, pentagon, heart,
## trillion, triangle, star, pebble, clover, sunburst and butterfly fit a circle; oval, marquise, lozenge, kite and
## teardrop fit a capsule (baguette and emerald corners don't, so nothing
## becomes one).
##
## A game passes the shapes and cuts she has unlocked (`allowed`, shape ->
## its cuts): restrict() first gives every other stone a stand-in shape
## resized to fit its slot, and balance() only swaps among allowed ones.

const ROUND_FAMILY := ["round", "cushion", "octagon", "hexagon", "flower", "square", "pentagon", "heart", "trillion",
		"triangle", "star", "pebble", "clover", "sunburst", "butterfly"]  # most fitting first
const LONG_FAMILY := ["oval", "marquise", "lozenge", "kite", "teardrop"]
const BOX_FAMILY := ["baguette", "emerald"]
## Shapes that only stand in for a locked shape when nothing else of its
## family is unlocked: a locked star should become a heart, say, rather
## than a soft pebble, and stand-ins stay as they were before these came.
const STAND_IN_LAST := ["pebble", "clover", "sunburst", "butterfly"]


## slots: the collage's slots, each with shape, part, target_color and
##   target_gem; `group_of` gives each slot's region a group id.
## colors: Array of {"color", "gem"} to recolor with, best first (gem may be
##   null when colors aren't snapped to gems); empty to only swap shapes.
## allowed: shape -> Array of cuts it may take (empty: every shape and cut);
##   run restrict() with it first.
## neighbors: per group id, the groups beside it (see RegionPaint.group_neighbors).
##   A part only takes a new color that reads as different from every color
##   its neighbors show (RegionPaint.contrasts), except next to the odd
##   neighbor RegionPaint.may_match lets share one; a part whose color
##   already blurs into a neighbor's tries a new color before a new shape.
## min_stones: when above 0, no type is left with fewer stones than this:
##   parts that small never take a new type, and a type still that small
##   afterwards takes the type of the nearest stone its shape can become
##   (in its own group first), so it sits beside stones like it. Slots marked
##   "keep_type" (accents that fill a feature on their own) are exempt.
## Sets every slot's "cut". Returns the number of gem types afterwards.
static func balance(slots: Array, group_of: PackedInt32Array, colors: Array, target: int, seed_value: int,
		allowed: Dictionary = {}, neighbors: Array = [], min_stones: int = 0) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "variety"])
	# Colors each group shows (gem key -> parts), to keep neighbors apart.
	var ctx := {"neighbors": neighbors, "seed": seed_value, "group_colors": {}, "labs": {}, "may_match": {}}
	var units := {}  # key -> {slots, shape, color, gem, combo}
	var unit_keys := []
	for s in slots:
		var key := "%d|%d|%d|%s|%s" % [group_of[s["region"]], s.get("part", 0), s.get("seq", -1), s["shape"],
				_gem_key(s["target_gem"], s["target_color"])]
		if not units.has(key):
			units[key] = {"slots": [], "shape": s["shape"], "color": s["target_color"], "gem": s["target_gem"],
					"group": group_of[s["region"]], "locked": s.get("seq", -1) >= 0, "keep": false,
					"cut": GemCuts.pick(s["shape"], _gem_key(s["target_gem"], s["target_color"]), seed_value,
							_cuts(s["shape"], allowed))}
			unit_keys.append(key)
		units[key]["slots"].append(s)
		if s.get("keep_type", false):
			units[key]["keep"] = true
	unit_keys.sort()
	for i in range(unit_keys.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = unit_keys[i]
		unit_keys[i] = unit_keys[j]
		unit_keys[j] = t
	var holders := {}  # combo -> number of units with it
	var stones := {}  # combo -> number of stones with it
	for key in unit_keys:
		var u: Dictionary = units[key]
		_count(holders, stones, ctx, u, 1)

	# Too few types: give a part a combination nobody has yet, taking parts
	# whose current type other parts share, so nothing is lost.
	var guard := 0
	while holders.size() < target and guard < 500:
		guard += 1
		var changed := false
		for key in unit_keys:
			var u: Dictionary = units[key]
			if holders[_combo(u)] < 2 or u["slots"].size() < min_stones:
				continue
			# A new shape in the part's own color first, so the palette stays calm,
			# then a new cut of it, then a new color (colors are ordered best first).
			var shape: String = u["shape"]
			var gem_key := _gem_key(u["gem"], u["color"])
			# A part that blurs into its neighbors gets a new color first instead.
			var recolor_first := _clashes(ctx, u, u["gem"], u["color"])
			if recolor_first and _recolor(ctx, holders, stones, u, colors):
				changed = true
				break
			for alt in _family(shape, allowed):
				var alt_cut := GemCuts.pick(alt, gem_key, seed_value, _cuts(alt, allowed))
				if alt != shape and not holders.has(_combo_of(alt, alt_cut, u["gem"], u["color"])):
					_count(holders, stones, ctx, u, -1)
					u["shape"] = alt
					u["cut"] = alt_cut
					_count(holders, stones, ctx, u, 1)
					changed = true
					break
			if changed:
				break
			for cut: String in _cuts(shape, allowed):
				if not holders.has(_combo_of(shape, cut, u["gem"], u["color"])):
					_count(holders, stones, ctx, u, -1)
					u["cut"] = cut
					_count(holders, stones, ctx, u, 1)
					changed = true
					break
			if changed:
				break
			if not recolor_first and _recolor(ctx, holders, stones, u, colors):
				changed = true
				break
		if not changed:
			break

	# Too many: fold the rarest type into a common one of the same family
	# (a type nothing can fold into without blurring into a neighbor stays).
	guard = 0
	var stuck := {}
	while holders.size() > target and guard < 500:
		guard += 1
		# Steps of a line sequence never fold, or the sequence would vanish.
		var locked := {}
		for key in unit_keys:
			if units[key]["locked"]:
				locked[_combo(units[key])] = true
		var rare := ""
		for combo in stones:
			if locked.has(combo) or stuck.has(combo):
				continue
			if rare == "" or stones[combo] < stones[rare] or (stones[combo] == stones[rare] and combo < rare):
				rare = combo
		if rare == "":
			break
		var into: Variant = null
		var rare_units := []
		for key in unit_keys:
			if _combo(units[key]) == rare:
				rare_units.append(units[key])
		for key in unit_keys:
			var u: Dictionary = units[key]
			if _combo(u) != rare:
				continue
			# The most common existing type this part could become.
			var best := ""
			var best_u: Dictionary = {}
			for key2 in unit_keys:
				var v: Dictionary = units[key2]
				var cv := _combo(v)
				if cv == rare or not v["shape"] in _family(u["shape"], allowed):
					continue
				if colors.is_empty() and v["shape"] == u["shape"]:
					continue
				if not colors.is_empty() or _same_color(u, v):
					if _folds_into_neighbor(ctx, rare_units, v):
						continue
					if best == "" or stones[cv] > stones[best]:
						best = cv
						best_u = v
			if best != "":
				into = best_u
			break
		if into == null:
			stuck[rare] = true
			continue
		for key in unit_keys:
			var u: Dictionary = units[key]
			if _combo(u) == rare:
				_count(holders, stones, ctx, u, -1)
				u["shape"] = into["shape"]
				u["cut"] = into["cut"]
				u["color"] = into["color"]
				u["gem"] = into["gem"]
				_count(holders, stones, ctx, u, 1)

	# Types of only a stone or two: each takes the type of the stone nearest it.
	if min_stones > 0:
		for _pass in 2:
			for key in unit_keys:
				var u: Dictionary = units[key]
				if u["locked"] or u["keep"] or stones.get(_combo(u), 0) >= min_stones:
					continue
				var v := _nearest_unit(ctx, u, units, unit_keys, allowed)
				if v.is_empty():
					continue
				_count(holders, stones, ctx, u, -1)
				u["shape"] = v["shape"]
				u["cut"] = v["cut"]
				u["color"] = v["color"]
				u["gem"] = v["gem"]
				_count(holders, stones, ctx, u, 1)

	for key in unit_keys:
		var u: Dictionary = units[key]
		for s in u["slots"]:
			s["shape"] = u["shape"]
			s["cut"] = u["cut"]
			s["target_color"] = u["color"]
			s["target_gem"] = u["gem"]
	return holders.size()


## Every gem type in a list of slots: [{shape, cut, gem, color, count}], most used first.
static func kinds(slots: Array) -> Array:
	var by := {}
	for s in slots:
		var cut: String = s.get("cut", "")
		var combo := _combo_of(s["shape"], cut, s["target_gem"], s["target_color"])
		if not by.has(combo):
			by[combo] = {"shape": s["shape"], "cut": cut, "gem": s["target_gem"], "color": s["target_color"], "count": 0}
		by[combo]["count"] += 1
	var out := by.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["count"] > b["count"])
	return out


## Gives every slot whose shape isn't in `allowed` (shape -> cuts) the
## nearest allowed shape: one of its own family if any (round, long or box),
## else one from another family, resized to fit inside the slot.
static func restrict(slots: Array, allowed: Dictionary) -> void:
	if allowed.is_empty():
		return
	var stand_ins := {}
	for s in slots:
		var shape: String = s["shape"]
		if allowed.has(shape):
			continue
		if not stand_ins.has(shape):
			stand_ins[shape] = _stand_in(shape, allowed)
		var alt: String = stand_ins[shape]
		if alt != "":
			_reshape(s, alt)


## The allowed shape nearest `shape`: its family's neighbors first (the
## families list their shapes most alike next to each other; STAND_IN_LAST
## shapes after the rest of their family), then the other families; "" if
## nothing is allowed.
static func _stand_in(shape: String, allowed: Dictionary) -> String:
	var order := []
	for whole: Array in [_whole_family(shape), LONG_FAMILY, ROUND_FAMILY, BOX_FAMILY]:
		var fam := whole.filter(func(f: String) -> bool: return not f in STAND_IN_LAST or f == shape)
		var at := fam.find(shape)
		var by_near := fam.duplicate()
		if at >= 0:
			by_near.sort_custom(func(a: String, b: String) -> bool:
				return absi(fam.find(a) - at) < absi(fam.find(b) - at))
		by_near.append_array(whole.filter(func(f: String) -> bool: return f in STAND_IN_LAST))
		for f: String in by_near:
			if not f in order:
				order.append(f)
	for f: String in order:
		if allowed.has(f):
			return f
	for f: String in allowed:
		return f
	return ""


## Gives every stone of a gem type (shape, cut and color, as the game counts
## them) the same proportions, the type's median width / length, so a type
## only ever changes size. A stone shrinks to them inside its own slot
## (narrower if it was rounder, shorter if it was thinner), keeping its
## center and turn, so nothing comes to overlap. Circle shapes are already
## even; capsules come out of packing stretched to their space.
static func even_aspects(slots: Array) -> void:
	var ratios := {}
	for s: Dictionary in slots:
		var key := type_key(s)
		if not ratios.has(key):
			ratios[key] = []
		ratios[key].append(float(s["width"]) / maxf(float(s["size"]), 0.001))
	var target := {}
	for key: String in ratios:
		var list: Array = ratios[key]
		list.sort()
		target[key] = list[list.size() / 2]
	for s: Dictionary in slots:
		var want: float = target[type_key(s)]
		var size: float = s["size"]
		var width: float = s["width"]
		var ratio := width / maxf(size, 0.001)
		if ratio > want * 1.001:
			s["width"] = size * want
		elif ratio < want / 1.001:
			s["size"] = width / want


## A gem type's key: shape, cut and gem (or color, when not snapped to gems).
static func type_key(s: Dictionary) -> String:
	var gem: Variant = s.get("target_gem")
	var color := str(gem) if gem != null else (s["target_color"] as Color).to_html(false)
	return "%s|%s|%s" % [s["shape"], s.get("cut", ""), color]


## Turns a slot into `to`, keeping it inside the slot it had: a circle's
## stone fits a capsule as wide as it, a capsule's fits the circle it spans,
## and a box's corners are pulled in.
static func _reshape(s: Dictionary, to: String) -> void:
	var from: Array = _whole_family(s["shape"])
	var into: Array = _whole_family(to)
	var size: float = s["size"]
	var width: float = s["width"]
	if from != into:
		if into == ROUND_FAMILY:
			s["size"] = minf(size, width)
			s["width"] = s["size"]
		elif into == LONG_FAMILY:
			if from == ROUND_FAMILY:
				s["width"] = size * 0.7
		elif from == ROUND_FAMILY:
			s["size"] = size * 0.8
			s["width"] = size * 0.55
		else:
			s["size"] = size - width * 0.3
			s["width"] = width * 0.75
	s["shape"] = to


static func _whole_family(shape: String) -> Array:
	if shape in ROUND_FAMILY:
		return ROUND_FAMILY
	if shape in LONG_FAMILY:
		return LONG_FAMILY
	if shape in BOX_FAMILY:
		return BOX_FAMILY
	return [shape]


## The shapes `shape` may swap with: its family (only round and long ones
## swap), narrowed to the allowed shapes.
static func _family(shape: String, allowed: Dictionary = {}) -> Array:
	var fam: Array = [shape]
	if shape in ROUND_FAMILY:
		fam = ROUND_FAMILY
	elif shape in LONG_FAMILY:
		fam = LONG_FAMILY
	if allowed.is_empty():
		return fam
	return fam.filter(func(f: String) -> bool: return allowed.has(f) or f == shape)


## The cuts `shape` may take, classic first: every one of them, or those allowed.
static func _cuts(shape: String, allowed: Dictionary) -> Array:
	var cuts := GemCuts.for_shape(shape)
	if not allowed.has(shape):
		return cuts
	var ok: Array = allowed[shape]
	var out := cuts.filter(func(c: String) -> bool: return c in ok)
	return out if not out.is_empty() else [cuts[0]]


static func _same_color(u: Dictionary, v: Dictionary) -> bool:
	return _gem_key(u["gem"], u["color"]) == _gem_key(v["gem"], v["color"])


static func _gem_key(gem: Variant, color: Color) -> String:
	return str(gem) if gem != null else color.to_html(false)


static func _combo_of(shape: String, cut: String, gem: Variant, color: Color) -> String:
	return shape + "|" + cut + "|" + _gem_key(gem, color)


static func _combo(u: Dictionary) -> String:
	return _combo_of(u["shape"], u["cut"], u["gem"], u["color"])


static func _count(holders: Dictionary, stones: Dictionary, ctx: Dictionary, u: Dictionary, delta: int) -> void:
	var c := _combo(u)
	holders[c] = holders.get(c, 0) + delta
	stones[c] = stones.get(c, 0) + delta * u["slots"].size()
	if holders[c] <= 0:
		holders.erase(c)
		stones.erase(c)
	var by_group: Dictionary = ctx["group_colors"]
	var g: int = u["group"]
	if not by_group.has(g):
		by_group[g] = {}
	var shown: Dictionary = by_group[g]
	var k := _gem_key(u["gem"], u["color"])
	shown[k] = shown.get(k, 0) + delta
	if shown[k] <= 0:
		shown.erase(k)
	elif not ctx["labs"].has(k):
		ctx["labs"][k] = LabColor.from_color(u["color"])


## Gives part `u` the first of `colors` (best first) that makes a type nobody
## has yet and doesn't blur into its neighbors' colors. Returns whether it did.
static func _recolor(ctx: Dictionary, holders: Dictionary, stones: Dictionary, u: Dictionary, colors: Array) -> bool:
	for c: Dictionary in colors:
		if holders.has(_combo_of(u["shape"], u["cut"], c["gem"], c["color"])):
			continue
		if _clashes(ctx, u, c["gem"], c["color"]):
			continue
		_count(holders, stones, ctx, u, -1)
		u["color"] = c["color"]
		u["gem"] = c["gem"]
		_count(holders, stones, ctx, u, 1)
		return true
	return false


## Whether part `u` in this color would blur into a color a neighboring group
## shows (one RegionPaint.may_match doesn't excuse).
static func _clashes(ctx: Dictionary, u: Dictionary, gem: Variant, color: Color) -> bool:
	var neighbors: Array = ctx["neighbors"]
	var g: int = u["group"]
	if g < 0 or g >= neighbors.size():
		return false
	var key := _gem_key(gem, color)
	var lab := LabColor.from_color(color)
	var by_group: Dictionary = ctx["group_colors"]
	for o: int in neighbors[g]:
		if not by_group.has(o) or _may_match(ctx, g, o):
			continue
		for k: String in by_group[o]:
			if k == key or (ctx["labs"][k] as Vector3).distance_to(lab) < RegionPaint.MIN_CONTRAST:
				return true
	return false


## RegionPaint.may_match, remembered per pair.
static func _may_match(ctx: Dictionary, a: int, b: int) -> bool:
	var pair := Vector2i(mini(a, b), maxi(a, b))
	var known: Dictionary = ctx["may_match"]
	if not known.has(pair):
		known[pair] = RegionPaint.may_match(ctx["seed"], a, b)
	return known[pair]


## The part of another type with the stone nearest to any of part `u`'s,
## whose shape `u`'s stones can take: in `u`'s own group if it has one,
## else anywhere it doesn't blur into a neighbor's color; {} if none.
static func _nearest_unit(ctx: Dictionary, u: Dictionary, units: Dictionary, unit_keys: Array,
		allowed: Dictionary) -> Dictionary:
	var own := _combo(u)
	var fam := _family(u["shape"], allowed)
	var best := {}
	var best_d := INF
	var best_own := {}
	var best_own_d := INF
	for key in unit_keys:
		var v: Dictionary = units[key]
		if _combo(v) == own or not v["shape"] in fam:
			continue
		var d := INF
		for a: Dictionary in u["slots"]:
			var pa := Vector2(a["x"], a["y"])
			for b: Dictionary in v["slots"]:
				d = minf(d, pa.distance_squared_to(Vector2(b["x"], b["y"])))
		if v["group"] == u["group"]:
			if d < best_own_d:
				best_own_d = d
				best_own = v
		elif d < best_d and not _folds_into_neighbor(ctx, [u], v):
			best_d = d
			best = v
	return best_own if not best_own.is_empty() else best


## Whether folding `parts` into part `v`'s type would give any of them a new
## color that blurs into a neighbor's.
static func _folds_into_neighbor(ctx: Dictionary, parts: Array, v: Dictionary) -> bool:
	for u: Dictionary in parts:
		if not _same_color(u, v) and _clashes(ctx, u, v["gem"], v["color"]):
			return true
	return false

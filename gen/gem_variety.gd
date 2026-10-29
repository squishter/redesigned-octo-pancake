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
## trillion, triangle and star fit a circle; oval, marquise, lozenge, kite and
## teardrop fit a capsule (baguette and emerald corners don't, so nothing
## becomes one).
##
## A game passes the shapes and cuts she has unlocked (`allowed`, shape ->
## its cuts): restrict() first gives every other stone a stand-in shape
## resized to fit its slot, and balance() only swaps among allowed ones.

const ROUND_FAMILY := ["round", "cushion", "octagon", "hexagon", "flower", "square", "pentagon", "heart", "trillion",
		"triangle", "star"]  # most fitting first
const LONG_FAMILY := ["oval", "marquise", "lozenge", "kite", "teardrop"]
const BOX_FAMILY := ["baguette", "emerald"]


## slots: the collage's slots, each with shape, part, target_color and
##   target_gem; `group_of` gives each slot's region a group id.
## colors: Array of {"color", "gem"} to recolor with, best first (gem may be
##   null when colors aren't snapped to gems); empty to only swap shapes.
## allowed: shape -> Array of cuts it may take (empty: every shape and cut);
##   run restrict() with it first.
## Sets every slot's "cut". Returns the number of gem types afterwards.
static func balance(slots: Array, group_of: PackedInt32Array, colors: Array, target: int, seed_value: int,
		allowed: Dictionary = {}) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "variety"])
	var units := {}  # key -> {slots, shape, color, gem, combo}
	var unit_keys := []
	for s in slots:
		var key := "%d|%d|%d|%s|%s" % [group_of[s["region"]], s.get("part", 0), s.get("seq", -1), s["shape"],
				_gem_key(s["target_gem"], s["target_color"])]
		if not units.has(key):
			units[key] = {"slots": [], "shape": s["shape"], "color": s["target_color"], "gem": s["target_gem"],
					"locked": s.get("seq", -1) >= 0,
					"cut": GemCuts.pick(s["shape"], _gem_key(s["target_gem"], s["target_color"]), seed_value,
							_cuts(s["shape"], allowed))}
			unit_keys.append(key)
		units[key]["slots"].append(s)
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
		_count(holders, stones, u, 1)

	# Too few types: give a part a combination nobody has yet, taking parts
	# whose current type other parts share, so nothing is lost.
	var guard := 0
	while holders.size() < target and guard < 500:
		guard += 1
		var changed := false
		for key in unit_keys:
			var u: Dictionary = units[key]
			if holders[_combo(u)] < 2:
				continue
			# A new shape in the part's own color first, so the palette stays calm,
			# then a new cut of it, then a new color (colors are ordered best first).
			var shape: String = u["shape"]
			var gem_key := _gem_key(u["gem"], u["color"])
			for alt in _family(shape, allowed):
				var alt_cut := GemCuts.pick(alt, gem_key, seed_value, _cuts(alt, allowed))
				if alt != shape and not holders.has(_combo_of(alt, alt_cut, u["gem"], u["color"])):
					_count(holders, stones, u, -1)
					u["shape"] = alt
					u["cut"] = alt_cut
					_count(holders, stones, u, 1)
					changed = true
					break
			if changed:
				break
			for cut: String in _cuts(shape, allowed):
				if not holders.has(_combo_of(shape, cut, u["gem"], u["color"])):
					_count(holders, stones, u, -1)
					u["cut"] = cut
					_count(holders, stones, u, 1)
					changed = true
					break
			if changed:
				break
			for c: Dictionary in colors:
				if not holders.has(_combo_of(shape, u["cut"], c["gem"], c["color"])):
					_count(holders, stones, u, -1)
					u["color"] = c["color"]
					u["gem"] = c["gem"]
					_count(holders, stones, u, 1)
					changed = true
					break
			if changed:
				break
		if not changed:
			break

	# Too many: fold the rarest type into a common one of the same family.
	guard = 0
	while holders.size() > target and guard < 500:
		guard += 1
		# Steps of a line sequence never fold, or the sequence would vanish.
		var locked := {}
		for key in unit_keys:
			if units[key]["locked"]:
				locked[_combo(units[key])] = true
		var rare := ""
		for combo in stones:
			if locked.has(combo):
				continue
			if rare == "" or stones[combo] < stones[rare] or (stones[combo] == stones[rare] and combo < rare):
				rare = combo
		if rare == "":
			break
		var into: Variant = null
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
					if best == "" or stones[cv] > stones[best]:
						best = cv
						best_u = v
			if best != "":
				into = best_u
			break
		if into == null:
			break
		for key in unit_keys:
			var u: Dictionary = units[key]
			if _combo(u) == rare:
				_count(holders, stones, u, -1)
				u["shape"] = into["shape"]
				u["cut"] = into["cut"]
				u["color"] = into["color"]
				u["gem"] = into["gem"]
				_count(holders, stones, u, 1)

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
## families list their shapes most alike next to each other), then the
## other families; "" if nothing is allowed.
static func _stand_in(shape: String, allowed: Dictionary) -> String:
	var order := []
	for fam: Array in [_whole_family(shape), LONG_FAMILY, ROUND_FAMILY, BOX_FAMILY]:
		var at := fam.find(shape)
		var by_near := fam.duplicate()
		if at >= 0:
			by_near.sort_custom(func(a: String, b: String) -> bool:
				return absi(fam.find(a) - at) < absi(fam.find(b) - at))
		for f: String in by_near:
			if not f in order:
				order.append(f)
	for f: String in order:
		if allowed.has(f):
			return f
	for f: String in allowed:
		return f
	return ""


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


static func _count(holders: Dictionary, stones: Dictionary, u: Dictionary, delta: int) -> void:
	var c := _combo(u)
	holders[c] = holders.get(c, 0) + delta
	stones[c] = stones.get(c, 0) + delta * u["slots"].size()
	if holders[c] <= 0:
		holders.erase(c)
		stones.erase(c)

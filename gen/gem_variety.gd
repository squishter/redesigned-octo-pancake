class_name GemVariety
extends RefCounted
## Steers how many gem types a collage uses. A gem type is a shape in a gem
## color (a small and a big round ruby are the same type), so a picture's
## variety comes from its shapes and colors, while sizes vary freely.
##
## Stones are changed a whole pattern part at a time (a row, a ring, the
## center stones, a line's stones), across every symmetric copy at once, so
## every row and line keeps a single type and symmetry survives: a part is
## the stones of one symmetry group, pattern step and shape. When parts run
## out, the caller rebuilds with spacer rows (SlotPacker's `spacers`), which
## adds thin rows to vary.
##
## Shapes only swap within a family whose outlines fit the same slot:
## round, square, hexagon and triangle fit a circle; oval, marquise and
## teardrop fit a capsule (a baguette's corners don't, so nothing becomes one).

const ROUND_FAMILY := ["round", "hexagon", "square", "triangle"]  # most fitting first
const LONG_FAMILY := ["oval", "marquise", "teardrop"]


## slots: the collage's slots, each with shape, part, target_color and
##   target_gem; `group_of` gives each slot's region a group id.
## colors: Array of {"color", "gem"} to recolor with, best first (gem may be
##   null when colors aren't snapped to gems); empty to only swap shapes.
## Returns the number of gem types afterwards.
static func balance(slots: Array, group_of: PackedInt32Array, colors: Array, target: int, seed_value: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "variety"])
	var units := {}  # key -> {slots, shape, color, gem, combo}
	var unit_keys := []
	for s in slots:
		var key := "%d|%d|%d|%s|%s" % [group_of[s["region"]], s.get("part", 0), s.get("seq", -1), s["shape"],
				_gem_key(s["target_gem"], s["target_color"])]
		if not units.has(key):
			units[key] = {"slots": [], "shape": s["shape"], "color": s["target_color"], "gem": s["target_gem"],
					"locked": s.get("seq", -1) >= 0}
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
			# then a new color (colors are ordered best first).
			var shape: String = u["shape"]
			for alt in _family(shape):
				if alt != shape and not holders.has(_combo_of(alt, u["gem"], u["color"])):
					_count(holders, stones, u, -1)
					u["shape"] = alt
					_count(holders, stones, u, 1)
					changed = true
					break
			if changed:
				break
			for c: Dictionary in colors:
				if not holders.has(_combo_of(shape, c["gem"], c["color"])):
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
				if cv == rare or not v["shape"] in _family(u["shape"]):
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
				u["color"] = into["color"]
				u["gem"] = into["gem"]
				_count(holders, stones, u, 1)

	for key in unit_keys:
		var u: Dictionary = units[key]
		for s in u["slots"]:
			s["shape"] = u["shape"]
			s["target_color"] = u["color"]
			s["target_gem"] = u["gem"]
	return holders.size()


## Every gem type in a list of slots: [{shape, gem, color, count}], most used first.
static func kinds(slots: Array) -> Array:
	var by := {}
	for s in slots:
		var combo := _combo_of(s["shape"], s["target_gem"], s["target_color"])
		if not by.has(combo):
			by[combo] = {"shape": s["shape"], "gem": s["target_gem"], "color": s["target_color"], "count": 0}
		by[combo]["count"] += 1
	var out := by.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["count"] > b["count"])
	return out


static func _family(shape: String) -> Array:
	if shape in ROUND_FAMILY:
		return ROUND_FAMILY
	if shape in LONG_FAMILY:
		return LONG_FAMILY
	return [shape]


static func _same_color(u: Dictionary, v: Dictionary) -> bool:
	return _gem_key(u["gem"], u["color"]) == _gem_key(v["gem"], v["color"])


static func _gem_key(gem: Variant, color: Color) -> String:
	return str(gem) if gem != null else color.to_html(false)


static func _combo_of(shape: String, gem: Variant, color: Color) -> String:
	return shape + "|" + _gem_key(gem, color)


static func _combo(u: Dictionary) -> String:
	return _combo_of(u["shape"], u["gem"], u["color"])


static func _count(holders: Dictionary, stones: Dictionary, u: Dictionary, delta: int) -> void:
	var c := _combo(u)
	holders[c] = holders.get(c, 0) + delta
	stones[c] = stones.get(c, 0) + delta * u["slots"].size()
	if holders[c] <= 0:
		holders.erase(c)
		stones.erase(c)

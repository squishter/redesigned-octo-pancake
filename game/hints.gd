class_name Hints
extends RefCounted
## Hints, kept per puzzle in its meta: `hints` banked (a new puzzle starts
## with START, at most MAX) and `hint_ms`, the play time toward the next.
## One more comes every EVERY_MS of play in that puzzle while fewer than MAX
## are banked; with MAX banked the clock waits. A hint glides the board to
## the selected gem's nearest open slot (see PlayScreen).

const START := 1
const MAX := 3
const EVERY_MS := 3 * 60 * 1000


## Fills in hint fields a puzzle's meta doesn't have yet (older saves).
static func upgrade(meta: Dictionary) -> void:
	meta["hints"] = clampi(int(meta.get("hints", START)), 0, MAX)
	meta["hint_ms"] = clampi(int(meta.get("hint_ms", 0)), 0, EVERY_MS)


## Adds `ms` of play. Returns true if that earned a hint.
static func tick(meta: Dictionary, ms: int) -> bool:
	if int(meta["hints"]) >= MAX:
		meta["hint_ms"] = 0
		return false
	var total := int(meta["hint_ms"]) + ms
	var earned := false
	while total >= EVERY_MS and int(meta["hints"]) < MAX:
		total -= EVERY_MS
		meta["hints"] = int(meta["hints"]) + 1
		earned = true
	meta["hint_ms"] = total if int(meta["hints"]) < MAX else 0
	return earned


## Spends a hint if there is one.
static func spend(meta: Dictionary) -> bool:
	if int(meta["hints"]) <= 0:
		return false
	meta["hints"] = int(meta["hints"]) - 1
	return true


## How far along the next hint is, 0..1 (0 with MAX banked).
static func progress(meta: Dictionary) -> float:
	if int(meta["hints"]) >= MAX:
		return 0.0
	return clampf(float(meta["hint_ms"]) / EVERY_MS, 0.0, 1.0)

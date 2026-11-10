extends SceneTree
## Source parameters retain precision while puzzle pixel coordinates stay compact.


func _initialize() -> void:
	var source := {
		"seed": 81, "growth": {"version": 3, "seed": 81,
			"controls": {"radius": 0.024, "length": 2.123456789012345, "bends": 1.827345689}},
		"stats": {"total_stem_length": 7.123456789012345},
	}
	var puzzle := {"source": source, "slots": [{"x": 12.3456, "y": 45.6789}],
		"lines": PackedByteArray([0, 255]), "palette": [{"color": Color("#eabb73")}],
		"title": 'A "quoted" picture'}
	var text := PatternIO.to_json(puzzle)
	var restored := PatternIO.from_json(text)
	var checks := [
		restored.source == source,
		is_equal_approx(restored.slots[0].x, 12.35),
		is_equal_approx(restored.slots[0].y, 45.68),
		restored.lines == puzzle.lines,
		restored.palette[0].color == puzzle.palette[0].color,
		restored.title == puzzle.title,
		PatternIO.from_json(PatternIO.to_json({"source": source})).source == source,
		PatternIO.from_json(PatternIO.to_json({"x": 1.2345})).x == 1.23,
		PatternIO.from_json(PatternIO.to_json({})).is_empty(),
	]
	for index in checks.size():
		if not checks[index]:
			printerr("FAIL source recipe serialization check ", index)
			quit(1)
			return
	print("PASSED: exact nested source parameters, compact coordinates and existing puzzle encodings.")
	quit(0)

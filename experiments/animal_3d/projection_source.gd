extends RefCounted
## Adapter for the investigation's 3D projections. It uses the same source
## contract as AnimalGenerator, without changing the production catalog.


static func load_lines(path: String, size := 384) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	var design: Dictionary = parsed
	var polylines: Array[PackedVector2Array] = []
	for line: Array in design["polylines"]:
		var points := PackedVector2Array()
		for point: Array in line:
			points.append(Vector2(point[0], point[1]))
		polylines.append(points)
	var closed := PackedByteArray(design["closed"])
	var families := PackedInt32Array(design["families"])
	var px := Vector2i(size, size)
	var thickness := size / 170.0
	var marks := []
	for mark: Dictionary in design["marks"]:
		marks.append({"at": LineRaster.to_px(Vector2(mark["at"][0], mark["at"][1]), px),
				"family": int(mark["family"])})
	var species: String = design["species"]
	return {
		"width": size, "height": size,
		"mask": LineRaster.rasterize(polylines, closed, px, thickness),
		"motifs": {"lines": LineRaster.rasterize_labels(polylines, closed, families, px, thickness + 2.0),
				"areas": marks},
		"mandala": {"seed": 0, "variant": "animal", "symmetry": "none", "frame": {},
				"polylines": polylines, "closed": closed, "families": families,
				"family_names": PackedStringArray(design["family_names"]),
				"animal": {"species": species, "pose": design["pose"], "yaw": design["yaw"],
						"plan": AnimalGenerator.SPECIES[species]["plan"], "blend": "", "coat": "3d surface",
						"facing": "right", "scene": "none", "projection": "orthographic"}},
	}

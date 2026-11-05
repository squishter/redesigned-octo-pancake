extends SceneTree
## Second step of tools/web_art/build_catalog.py: turns each cutout in
## <work>/cutouts (RGBA PNG + JSON metadata) into line art with the game's own
## PhotoEdges (the subject from the cutout's alpha), keeps the ones the
## collage generator turns into a playable collage, and writes the catalog to
## <out>:
##
##   art/<id>.png     line art: black lines on white, exactly PhotoEdges' mask
##   color/<id>.jpg   the picture cropped like the line art (a collage's colors)
##   thumbs/<id>.png  the line art at THUMB px, for the list
##   index.json       {version, built, items: [{id, title, artist, date, medium,
##                    classification, source, license, url, tags, art, color,
##                    thumb, width, height, subject, cut_out, areas, stones}]}
##
## Rejected pictures' line art goes to <work>/rejected/, with the reasons in
## <work>/rejected.json, for review.
##
##   godot --headless --path . -s res://tools/web_art/trace_catalog.gd -- <work> <out> [detail] [strict]

const THUMB := 192
## A trial collage (the game's dense layout) must have at least this many
## areas and stones, or there's too little picture to fill.
const MIN_AREAS := 4
const MIN_STONES := 300


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <work dir> <out dir> [detail 0..1] [strict]")
		quit(2)
		return
	var work: String = args[0]
	var out: String = args[1]
	var detail := float(args[2]) if args.size() > 2 else 0.5
	var strict := args.size() > 3 and args[3] == "strict"
	var cut_dir := work.path_join("cutouts")
	for sub in ["art", "color", "thumbs"]:
		DirAccess.make_dir_recursive_absolute(out.path_join(sub))
	DirAccess.make_dir_recursive_absolute(work.path_join("rejected"))
	var names := Array(DirAccess.get_files_at(cut_dir)).filter(func(f: String) -> bool: return f.ends_with(".json"))
	names.sort()
	var items := []
	var rejected := []
	for f: String in names:
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(cut_dir.path_join(f)))
		if not meta is Dictionary:
			continue
		var id: String = meta["id"]
		var img := Image.load_from_file(cut_dir.path_join(id + ".png"))
		if img == null or img.is_empty():
			rejected.append({"id": id, "why": "no cutout"})
			continue
		var t0 := Time.get_ticks_msec()
		var art := PhotoEdges.line_art(img, {"detail": detail, "subject": "alpha", "strict_inside": strict})
		var w: int = art["width"]
		var h: int = art["height"]
		var color: Image = art["image"]
		color.convert(Image.FORMAT_RGB8)
		art["image"] = color
		var trial := PictureSources.photo_collage(color, {"method": "edges", "layout": PuzzleMaker.LAYOUT,
				"pattern_seed": 1}, art)
		var areas := 0
		for r in trial["regions"]:
			if r["kind"] == "area" and not r["empty"]:
				areas += 1
		var stones: int = trial["slots"].size()
		var why := ""
		if areas < MIN_AREAS:
			why = "too few areas (%d)" % areas
		elif stones < MIN_STONES:
			why = "too few stones (%d)" % stones
		print("%s: %dx%d, %s, %d areas, %d stones — %s (%d ms)" % [id, w, h,
				"cut out" if art["scores"].get("alpha") else ("subject found" if art["subject"] else "whole picture"),
				areas, stones, why if why else "kept", Time.get_ticks_msec() - t0])
		var lines := Image.create_from_data(w, h, false, Image.FORMAT_L8, _inverted(art["mask"]))
		if why:
			lines.save_png(work.path_join("rejected/%s.png" % id))
			rejected.append({"id": id, "title": meta.get("title", ""), "why": why})
			continue
		lines.save_png(out.path_join("art/%s.png" % id))
		color.save_jpg(out.path_join("color/%s.jpg" % id), 0.85)
		var thumb := lines.duplicate() as Image
		var s := float(THUMB) / maxi(w, h)
		thumb.resize(maxi(1, roundi(w * s)), maxi(1, roundi(h * s)), Image.INTERPOLATE_LANCZOS)
		thumb.save_png(out.path_join("thumbs/%s.png" % id))
		var entry := {}
		for k in ["id", "title", "artist", "date", "medium", "classification", "source", "license", "url", "tags"]:
			entry[k] = meta.get(k, "")
		entry.merge({"art": "art/%s.png" % id, "color": "color/%s.jpg" % id, "thumb": "thumbs/%s.png" % id,
				"width": w, "height": h, "subject": art["subject"], "cut_out": art["scores"].get("alpha", false),
				"areas": areas, "stones": stones})
		items.append(entry)
	_write_json(out.path_join("index.json"), {"version": 1, "built": Time.get_datetime_string_from_system(true),
			"items": items})
	_write_json(work.path_join("rejected.json"), rejected)
	print("%d kept, %d rejected → %s" % [items.size(), rejected.size(), out.path_join("index.json")])
	quit(0)


static func _write_json(path: String, data: Variant) -> void:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify(data, " ", false))
	fa.close()


static func _inverted(mask: PackedByteArray) -> PackedByteArray:
	var out := mask.duplicate()
	for i in out.size():
		out[i] = 255 - out[i]
	return out

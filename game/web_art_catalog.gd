class_name WebArtCatalog
extends RefCounted
## The web line-art catalog built by tools/web_art/build_catalog.py: line art
## traced from open-access museum pictures (the subject cut out when there is
## one), with titles, tags and credits, searchable by words.
##
## A catalog is a folder holding index.json plus the art/, color/ and thumbs/
## files it names (see tools/web_art/trace_catalog.gd).

const DEFAULT_DIR := "res://assets/web_art"

var dir := ""
var items: Array = []


## The catalog in `folder`; empty (no items) if it has no index.json.
static func open(folder: String = DEFAULT_DIR) -> WebArtCatalog:
	var c := WebArtCatalog.new()
	c.dir = folder
	var path := folder.path_join("index.json")
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			c.items = data.get("items", [])
	return c


## Items where every word of `query` starts a word of the title, tags,
## artist, classification or source ("bird" finds "Birds", not "Ladybird"),
## title matches first. An empty query lists them all.
func search(query: String) -> Array:
	var words := _words(query).split(" ", false)
	if words.is_empty():
		return items.duplicate()
	var in_title := []
	var elsewhere := []
	for item: Dictionary in items:
		var title := " " + _words(item.get("title", ""))
		var hay := title + " " + _words(" ".join(PackedStringArray([" ".join(PackedStringArray(item.get("tags", []))),
				item.get("artist", ""), item.get("classification", ""), item.get("source", "")])))
		if Array(words).all(func(w: String) -> bool: return hay.contains(" " + w)):
			(in_title if Array(words).any(func(w: String) -> bool: return title.contains(" " + w)) else elsewhere).append(item)
	return in_title + elsewhere


## Lowercase, with everything but letters and digits as spaces.
static func _words(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch.unicode_at(0) > 127 else " "
	return out


## An item's file (its "art", "color" or "thumb"); null if missing.
func image(item: Dictionary, key: String) -> Image:
	var rel: String = item.get(key, "")
	return load_image(dir.path_join(rel)) if rel else null


## Line art ready for PictureSources.photo_collage(art["image"], options, art):
## {mask, width, height, image (the picture's colors), subject}. Empty if the
## item's files are missing.
func line_art(item: Dictionary) -> Dictionary:
	var lines := image(item, "art")
	if lines == null:
		return {}
	var w := lines.get_width()
	var h := lines.get_height()
	var color := image(item, "color")
	if color == null or color.get_size() != lines.get_size():
		color = Image.create(w, h, false, Image.FORMAT_RGB8)
		color.fill(Color.WHITE)
	return {"mask": LineRaster.from_image(lines), "width": w, "height": h, "image": color,
			"subject": item.get("subject", false)}


## A credit line: "Title, Artist, Date. Source (License)".
static func credit(item: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in ["title", "artist", "date"]:
		if str(item.get(k, "")) != "":
			parts.append(str(item[k]))
	return "%s. %s (%s)" % [", ".join(parts), item.get("source", ""), item.get("license", "")]


## An image from a file: the file itself when it's there (the editor, or
## user://), else the imported texture (res:// in an exported build, where
## only the import is packed).
static func load_image(path: String) -> Image:
	if FileAccess.file_exists(path):
		var img := PhotoLoader.from_bytes(FileAccess.get_file_as_bytes(path))
		if img != null:
			return img
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			var img := tex.get_image()
			if img.is_compressed():
				img.decompress()
			return img
	return null

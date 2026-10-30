class_name FacetAtlas
extends RefCounted
## A board's facet pictures (GemMesh.get_facets) gathered into one texture,
## for its tiny stones drawn as flat outlines (gem_impostor.gdshader): a
## shape and cut gets its tile the first time a layer of them is that small.

## Tiles a side: enough for every shape and cut.
const TILES := 7

var texture := ImageTexture.new()
var _image: Image
var _tiles := {}


## Where a shape and cut ("shape|cut") sits: the UV of its -1..1 square's
## corner, and its size. Adds its picture the first time.
func tile(key: String) -> Vector4:
	var px := GemMesh.FACET_PX + 2
	if not _tiles.has(key):
		if _image == null:
			_image = Image.create(px * TILES, px * TILES, false, Image.FORMAT_RGBA8)
		var k := _tiles.size()
		var parts := key.split("|")
		_image.blit_rect(GemMesh.get_facets(parts[0], parts[1]), Rect2i(0, 0, px, px), Vector2i(k % TILES, k / TILES) * px)
		if texture.get_width() == 0:
			texture.set_image(_image)
		else:
			texture.update(_image)
		_tiles[key] = k
	var at: int = _tiles[key]
	var size := float(px * TILES)
	# Inside its one-texel border (see GemMesh.get_facets).
	return Vector4((at % TILES * px + 1) / size, (at / TILES * px + 1) / size, GemMesh.FACET_PX / size,
			GemMesh.FACET_PX / size)

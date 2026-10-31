class_name FacetAtlas
extends RefCounted
## A board's facet pictures (GemMesh.get_facets) gathered into one texture,
## for its tiny stones drawn as flat outlines (gem_impostor.gdshader): a
## shape and cut gets its tile the first time a layer of them is that small.

## Minimum tiles a side; prepare() allows for outline aspect variants too.
const TILES := 7

var texture := ImageTexture.new()
var _image: Image
var _tiles := {}
var _side := TILES


## Reserve the whole board before any tile UVs are handed out, keeping
## them stable while pictures are added. A new puzzle drops old profiles.
func prepare(profiles: int) -> void:
	_side = maxi(TILES, ceili(sqrt(profiles)))
	_tiles.clear()
	_image = null


## Where a mesh profile ("shape|cut|ratio") sits: the UV of its -1..1 square's
## corner, and its size. Adds its picture the first time.
func tile(key: String) -> Vector4:
	var px := GemMesh.FACET_PX + 2
	if not _tiles.has(key):
		if _image == null:
			_image = Image.create(px * _side, px * _side, false, Image.FORMAT_RGBA8)
		var k := _tiles.size()
		var parts := key.split("|")
		var ratio := float(parts[2]) if parts.size() > 2 else 1.0
		_image.blit_rect(GemMesh.get_facets(parts[0], parts[1], ratio), Rect2i(0, 0, px, px),
				Vector2i(k % _side, k / _side) * px)
		if texture.get_width() != _image.get_width():
			texture.set_image(_image)
		else:
			texture.update(_image)
		_tiles[key] = k
	var at: int = _tiles[key]
	var size := float(px * _side)
	# Inside its one-texel border (see GemMesh.get_facets).
	return Vector4((at % _side * px + 1) / size, (at / _side * px + 1) / size, GemMesh.FACET_PX / size,
			GemMesh.FACET_PX / size)

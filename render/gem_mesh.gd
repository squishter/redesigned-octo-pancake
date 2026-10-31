class_name GemMesh
extends RefCounted
## Faceted 3D gems for the board: the top of a stone (its crown), built from
## its 2D outline (GemShapes) in one of its cuts (GemCuts).
##
## A mesh is unit sized: the outline is 2 long (x, the shape's long axis) and
## 2 wide (z), with y up toward the viewer and the girdle (the outline) at
## y = 0. The board stretches each mesh to a stone's length and width. Every
## facet is flat with its own normal, so light glints off one facet at a
## time; cabochons are smooth instead.
## Kites need the stone's width / length when building that unit mesh:
## their shoulders depend on its proportions. Build the GemShapes outline
## first, then normalize it, so stretching it back preserves the generator's
## slot and packing footprint.
##
## A cut is a stack of rings from the girdle up: every k-th girdle point
## (starting at an offset), pulled toward the center and raised. Neighboring
## rings are zipped into triangles in the order their points go around, so
## rings with fewer points (offset by half a step) make the kite and star
## facets of a brilliant, and aligned rings make the flat steps of a step
## cut. The last ring is the table (a flat top), or a single apex point.
##
## Tiny stones (a few px across on screen) draw as a flat outline instead
## (get_outline_mesh), their facets from a picture (get_facets).

## Girdle points per shape, before rounding: a multiple of its corners.
const GIRDLE := {"star": 40, "pentagon": 40, "triangle": 48, "trillion": 48, "hexagon": 48}
const GIRDLE_DEFAULT := 32
## Girdle points come in multiples of this between corners, so rings that
## take every 2nd or 4th point keep the corners.
const QUANTUM := 4
## Turns sharper than this (radians) keep a girdle point on the corner.
const CORNER := 0.45
## Rings per cut: [every, offset, scale, height]. A ring takes every
## `every`-th girdle point from `offset`, pulled to `scale` of the way from
## the center and raised to `height` (outline radius 1); every 0 is the apex.
const RINGS := {
	"brilliant": [[1, 0, 1.0, 0.0], [4, 0, 0.8, 0.15], [4, 2, 0.55, 0.27]],
	"step": [[1, 0, 1.0, 0.0], [1, 0, 0.87, 0.13], [1, 0, 0.74, 0.17], [1, 0, 0.6, 0.27]],
	"rose": [[1, 0, 1.0, 0.0], [4, 2, 0.62, 0.2], [0, 0, 0.0, 0.34]],
	"checker": [[1, 0, 1.0, 0.0], [2, 1, 0.8, 0.12], [4, 0, 0.58, 0.21], [4, 2, 0.34, 0.27], [0, 0, 0.0, 0.3]],
}
## Cabochon: a smooth dome this high, in this many rings.
const DOME_HEIGHT := 0.4
const DOME_RINGS := 6
## Outlines for tiny stones have this share of the girdle points.
const LOW_SHARE := 0.25
## Facet pictures (get_facets) are this many texels a side, plus a texel of
## border all round (repeating the edge, so filtering never reads past it).
const FACET_PX := 64
const ASPECT_SHAPES := ["kite"]

static var _cache := {}


## Other outlines stretch affinely and can share a mesh at every aspect.
## Six decimals coalesce floating-point noise between sizes of one type.
static func profile_ratio(shape: String, ratio: float) -> float:
	return snappedf(maxf(ratio, 0.000001), 0.000001) if shape in ASPECT_SHAPES else 1.0


static func mesh_key(shape: String, cut: String, ratio := 1.0) -> String:
	return "%s|%s|%.6f" % [shape, cut, profile_ratio(shape, ratio)]


## The mesh for a shape, cut and outline proportions, built once and shared.
static func get_mesh(shape: String, cut: String, ratio := 1.0) -> ArrayMesh:
	var key := mesh_key(shape, cut, ratio)
	if not _cache.has(key):
		_cache[key] = build(shape, cut, ratio)
	return _cache[key]


## A stone's outline as a flat polygon (a quarter of its girdle points,
## keeping the corners) at height `y`, facing up, for drawing tiny stones
## (gem_impostor.gdshader): their facets come from get_facets. An octagon
## for a round stone: 6 triangles. Built once a shape.
static func get_outline_mesh(shape: String, y: float, ratio := 1.0) -> ArrayMesh:
	var key := mesh_key(shape, "outline", ratio) + "|%f" % y
	if not _cache.has(key):
		var girdle := girdle_points(shape, roundi(GIRDLE.get(shape, GIRDLE_DEFAULT) * LOW_SHARE), 1, ratio)
		var flat := PackedVector2Array()
		for g: Array in girdle:
			flat.append(g[1])
		var tris := PackedVector3Array()
		var order := Geometry2D.triangulate_polygon(flat)
		for k in range(0, order.size(), 3):
			var a := flat[order[k]]
			var b := flat[order[k + 1]]
			var c := flat[order[k + 2]]
			_tri(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), tris)
		_cache[key] = _mesh(tris, false)
	return _cache[key]


## A stone seen from above as a picture, for drawing tiny stones as a flat
## outline each (gem_impostor.gdshader): FACET_PX texels a side over the
## mesh's -1..1 in x and z (plus a border texel), each holding the normal of
## the facet there (its x and z, as 0..1 in red and green; y is the rest, as
## every facet faces up) and in blue whether the stone covers it. Built once
## a shape and cut, from the full mesh.
static func get_facets(shape: String, cut: String, ratio := 1.0) -> Image:
	var key := mesh_key(shape, cut, ratio) + "|facets"
	if not _cache.has(key):
		_cache[key] = _facets(get_mesh(shape, cut, ratio))
	return _cache[key]


static func _facets(mesh: ArrayMesh) -> Image:
	var n := FACET_PX
	var data := PackedByteArray()
	data.resize(n * n * 4)
	for i in n * n:
		data[i * 4] = 128
		data[i * 4 + 1] = 128
		data[i * 4 + 3] = 255
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	# Texel (i, j)'s center is at x, z = (i + 0.5) / n * 2 - 1: in texels, a
	# point sits at (x + 1) / 2 * n - 0.5.
	var to_px := func(p: Vector3) -> Vector2: return Vector2((p.x + 1.0) * 0.5 * n - 0.5, (p.z + 1.0) * 0.5 * n - 0.5)
	for t in range(0, v.size(), 3):
		var a: Vector2 = to_px.call(v[t])
		var b: Vector2 = to_px.call(v[t + 1])
		var c: Vector2 = to_px.call(v[t + 2])
		var area := (b - a).cross(c - a)
		if absf(area) < 1e-9:
			continue
		for j in range(maxi(0, ceili(minf(a.y, minf(b.y, c.y)))), mini(n - 1, floori(maxf(a.y, maxf(b.y, c.y)))) + 1):
			for i in range(maxi(0, ceili(minf(a.x, minf(b.x, c.x)))), mini(n - 1, floori(maxf(a.x, maxf(b.x, c.x)))) + 1):
				var p := Vector2(i, j)
				var wa := (c - b).cross(p - b) / area
				var wb := (a - c).cross(p - c) / area
				var wc := 1.0 - wa - wb
				if wa < -1e-4 or wb < -1e-4 or wc < -1e-4:
					continue
				var normal := (nm[t] * wa + nm[t + 1] * wb + nm[t + 2] * wc).normalized()
				var at := (j * n + i) * 4
				data[at] = clampi(roundi((normal.x * 0.5 + 0.5) * 255.0), 0, 255)
				data[at + 1] = clampi(roundi((normal.z * 0.5 + 0.5) * 255.0), 0, 255)
				data[at + 2] = 255
	var inner := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
	# The border: each edge texel once more outside it.
	var out := Image.create(n + 2, n + 2, false, Image.FORMAT_RGBA8)
	out.blit_rect(inner, Rect2i(0, 0, n, n), Vector2i(1, 1))
	for k in n + 2:
		var e := clampi(k - 1, 0, n - 1)
		out.set_pixel(k, 0, inner.get_pixel(e, 0))
		out.set_pixel(k, n + 1, inner.get_pixel(e, n - 1))
		out.set_pixel(0, k, inner.get_pixel(0, e))
		out.set_pixel(n + 1, k, inner.get_pixel(n - 1, e))
	return out


## Builds the mesh for a shape in a cut (unknown cuts make a brilliant).
static func build(shape: String, cut: String, ratio := 1.0) -> ArrayMesh:
	var girdle := girdle_points(shape, -1, QUANTUM, ratio)
	var rings := []
	if cut == "cabochon":
		for k in DOME_RINGS + 1:
			var t := float(k) / DOME_RINGS
			rings.append([1, 0, cos(t * PI / 2.0), DOME_HEIGHT * sin(t * PI / 2.0)] if k < DOME_RINGS
					else [0, 0, 0.0, DOME_HEIGHT])
	else:
		rings = RINGS.get(cut, RINGS["brilliant"])
	var tris := PackedVector3Array()
	var built := []
	for spec: Array in rings:
		built.append(_ring(girdle, spec))
	for k in range(1, built.size()):
		var outer: Array = built[k - 1]
		var inner: Array = built[k]
		if inner.size() == 1:
			_fan(outer, inner[0][1], tris)
		else:
			_zip(outer, inner, tris)
	var top: Array = built[built.size() - 1]
	if top.size() > 2:
		var c := Vector3.ZERO
		for p: Array in top:
			c += p[1]
		_fan(top, c / top.size(), tris)
	return _mesh(tris, cut == "cabochon")


## The outline as [u, Vector2] points (u: 0..1 around), about `want` of
## them (the shape's GIRDLE count when -1), resampled so every corner keeps
## a point and the points between corners come in `quantum` steps, evenly
## spaced along each side.
static func girdle_points(shape: String, want := -1, quantum := QUANTUM, ratio := 1.0) -> Array:
	ratio = profile_ratio(shape, ratio)
	var outline := GemShapes.outline(shape, 2.0, 2.0 * ratio, 96)
	for i in outline.size():
		outline[i].y /= ratio
	var n := outline.size()
	var corners := []
	for i in n:
		var a := outline[(i - 1 + n) % n]
		var b := outline[i]
		var c := outline[(i + 1) % n]
		if shape in ASPECT_SHAPES or absf((b - a).angle_to(c - b)) > CORNER:
			corners.append(i)
	if corners.is_empty():
		corners.append(0)
	# The sides between corners, as polylines.
	var sides := []
	var total := 0.0
	for k in corners.size():
		var i0: int = corners[k]
		var i1: int = corners[(k + 1) % corners.size()]
		var side := PackedVector2Array([outline[i0]])
		var i := i0
		while true:
			i = (i + 1) % n
			side.append(outline[i])
			if i == i1:
				break
		sides.append(side)
		total += _length(side)
	if want < 0:
		want = GIRDLE.get(shape, GIRDLE_DEFAULT)
	var out := []
	var count := 0
	var counts := []
	for side: PackedVector2Array in sides:
		var m := maxi(1, roundi(want * _length(side) / total / quantum)) * quantum
		counts.append(m)
		count += m
	var done := 0
	for k in sides.size():
		var side: PackedVector2Array = sides[k]
		var m: int = counts[k]
		var length := _length(side)
		for j in m:
			out.append([float(done + j) / count, _at(side, length * j / m)])
		done += m
	return out


## A ring from a spec, as [u, Vector3] points.
static func _ring(girdle: Array, spec: Array) -> Array:
	var every: int = spec[0]
	var scale: float = spec[2]
	var height: float = spec[3]
	if every == 0:
		return [[0.0, Vector3(0.0, height, 0.0)]]
	var out := []
	var offset: int = spec[1]
	for i in range(offset, girdle.size(), every):
		var p: Vector2 = girdle[i][1] * scale
		out.append([girdle[i][0], Vector3(p.x, height, p.y)])
	return out


## Triangles between two rings, taking their points in the order they go
## around (by u), so each triangle joins neighbors.
static func _zip(outer: Array, inner: Array, tris: PackedVector3Array) -> void:
	# Each point's turn comes at its u (a point at u = 0 at 1, closing the
	# loop); each ring starts from the point whose turn comes last.
	var events := []
	var last := [0, 0]
	var latest := [-1.0, -1.0]
	for r in 2:
		var ring: Array = outer if r == 0 else inner
		for k in ring.size():
			var u: float = ring[k][0]
			var turn := u if u > 0.0 else u + 1.0
			events.append([turn, r, k])
			if turn > latest[r]:
				latest[r] = turn
				last[r] = k
	events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var cur_o: Vector3 = outer[last[0]][1]
	var cur_i: Vector3 = inner[last[1]][1]
	for e: Array in events:
		if e[1] == 0:
			var next: Vector3 = outer[e[2]][1]
			_tri(cur_o, next, cur_i, tris)
			cur_o = next
		else:
			var next: Vector3 = inner[e[2]][1]
			_tri(cur_o, next, cur_i, tris)
			cur_i = next


## Triangles from a ring to one point.
static func _fan(ring: Array, apex: Vector3, tris: PackedVector3Array) -> void:
	for k in ring.size():
		_tri(ring[k][1], ring[(k + 1) % ring.size()][1], apex, tris)


## Adds a triangle, wound so its face points up.
static func _tri(a: Vector3, b: Vector3, c: Vector3, tris: PackedVector3Array) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	if n.y > 0.0:
		tris.append_array([a, c, b])  # Godot's front faces wind clockwise
	else:
		tris.append_array([a, b, c])


static func _mesh(tris: PackedVector3Array, smooth: bool) -> ArrayMesh:
	var normals := PackedVector3Array()
	normals.resize(tris.size())
	var smoothed := {}
	for t in range(0, tris.size(), 3):
		var n := (tris[t + 2] - tris[t]).cross(tris[t + 1] - tris[t]).normalized()
		for k in 3:
			normals[t + k] = n
			if smooth:
				var key := Vector3i(roundi(tris[t + k].x * 1e4), roundi(tris[t + k].y * 1e4), roundi(tris[t + k].z * 1e4))
				smoothed[key] = smoothed.get(key, Vector3.ZERO) + n
	if smooth:
		for i in tris.size():
			var key := Vector3i(roundi(tris[i].x * 1e4), roundi(tris[i].y * 1e4), roundi(tris[i].z * 1e4))
			normals[i] = (smoothed[key] as Vector3).normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tris
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


## The point `s` along a polyline.
static func _at(pts: PackedVector2Array, s: float) -> Vector2:
	for i in range(1, pts.size()):
		var d := pts[i - 1].distance_to(pts[i])
		if s <= d or i == pts.size() - 1:
			return pts[i - 1].lerp(pts[i], clampf(s / maxf(d, 1e-9), 0.0, 1.0))
		s -= d
	return pts[pts.size() - 1]

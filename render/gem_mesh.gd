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
##
## A cut is a stack of rings from the girdle up: every k-th girdle point
## (starting at an offset), pulled toward the center and raised. Neighboring
## rings are zipped into triangles in the order their points go around, so
## rings with fewer points (offset by half a step) make the kite and star
## facets of a brilliant, and aligned rings make the flat steps of a step
## cut. The last ring is the table (a flat top), or a single apex point.

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

static var _cache := {}


## The mesh for a shape in a cut, built once and shared.
static func get_mesh(shape: String, cut: String) -> ArrayMesh:
	var key := shape + "|" + cut
	if not _cache.has(key):
		_cache[key] = build(shape, cut)
	return _cache[key]


## Builds the mesh for a shape in a cut (unknown cuts make a brilliant).
static func build(shape: String, cut: String) -> ArrayMesh:
	var girdle := girdle_points(shape)
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


## The outline as [u, Vector2] points (u: 0..1 around), resampled so every
## corner keeps a point and the points between corners come in QUANTUM
## steps, evenly spaced along each side.
static func girdle_points(shape: String) -> Array:
	var outline := GemShapes.outline(shape, 2.0, 2.0, 96)
	var n := outline.size()
	var corners := []
	for i in n:
		var a := outline[(i - 1 + n) % n]
		var b := outline[i]
		var c := outline[(i + 1) % n]
		if absf((b - a).angle_to(c - b)) > CORNER:
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
	var want: int = GIRDLE.get(shape, GIRDLE_DEFAULT)
	var out := []
	var count := 0
	var counts := []
	for side: PackedVector2Array in sides:
		var m := maxi(1, roundi(want * _length(side) / total / QUANTUM)) * QUANTUM
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

class_name LabColor
extends RefCounted
## sRGB <-> CIE Lab (D65) conversion. Lab distance matches how people see
## color differences far better than RGB distance, so the quantizer and the
## gem-color snapping both work in Lab.


static func _to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func _to_srgb(c: float) -> float:
	var v: float = c * 12.92 if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055
	return clampf(v, 0.0, 1.0)


static func _f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0


static func _f_inv(t: float) -> float:
	var t3 := t * t * t
	return t3 if t3 > 0.008856 else (t - 16.0 / 116.0) / 7.787


## Returns Lab as Vector3(L, a, b). L is 0..100.
static func from_color(c: Color) -> Vector3:
	var r := _to_linear(c.r)
	var g := _to_linear(c.g)
	var b := _to_linear(c.b)
	var x := (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
	var y := (r * 0.2126 + g * 0.7152 + b * 0.0722)
	var z := (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
	var fx := _f(x)
	var fy := _f(y)
	var fz := _f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func to_color(lab: Vector3) -> Color:
	var fy := (lab.x + 16.0) / 116.0
	var fx := fy + lab.y / 500.0
	var fz := fy - lab.z / 200.0
	var x := _f_inv(fx) * 0.95047
	var y := _f_inv(fy)
	var z := _f_inv(fz) * 1.08883
	var r := x * 3.2406 + y * -1.5372 + z * -0.4986
	var g := x * -0.9689 + y * 1.8758 + z * 0.0415
	var b := x * 0.0557 + y * -0.2040 + z * 1.0570
	return Color(_to_srgb(r), _to_srgb(g), _to_srgb(b))


## Index of the Lab color in `palette` closest to `lab`.
static func nearest(lab: Vector3, palette: PackedVector3Array) -> int:
	var best := 0
	var best_d := INF
	for i in palette.size():
		var d := lab.distance_squared_to(palette[i])
		if d < best_d:
			best_d = d
			best = i
	return best

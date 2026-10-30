class_name GemIcons
extends RefCounted
## Single gems laid out on an icon sheet (an off-screen GemBoard3D that the
## gem row, Collection and flying gems cut their pictures from), one per
## square cell. Each stone is sized to stay well inside its own cell even
## when tilted, so no part of it ever shows in a neighbor's picture.

## Round stones span this much of their cell; long ones (tilted 45°) at
## most LONG, and less when wide, so their tilted outline (half-extent
## (length + width) / 2√2) stays within FIT of the cell's half.
const ROUND := 0.62
const LONG := 0.8
const FIT := 0.85
## Icon sheets render this many times a second: their glints only change
## with the light's slow drift (and the phone's turn).
const FPS := 10.0


## A stone for an icon cell `cell` units wide, centered at `at`: `ratio` is
## its width over its length (long shapes only).
static func stone(shape: String, cut: String, color: Color, gem: Variant, ratio: float, cell: float,
		at: Vector2) -> Dictionary:
	var long := shape in GemVariety.LONG_FAMILY or shape in GemVariety.BOX_FAMILY
	var length := cell * ROUND
	var width := length
	if long:
		ratio = clampf(ratio, 0.2, 1.0)
		length = cell * minf(LONG, FIT * sqrt(2.0) / (1.0 + ratio))
		width = length * ratio
	return {"x": at.x, "y": at.y, "size": length, "width": width,
			"rotation": -PI / 4.0 if long else SlotPacker.upright(shape), "shape": shape, "cut": cut,
			"target_color": color, "target_gem": gem}

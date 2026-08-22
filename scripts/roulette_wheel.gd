class_name RouletteWheel
extends Control
## Draws a European roulette wheel. The whole control is rotated (around its
## pivot) to animate the spin; set result_index to draw the ball in a pocket.

## Pocket order around a European wheel, clockwise from the zero.
const WHEEL_ORDER := [
	0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
	5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
]
const RED_NUMBERS := [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]

const COLOR_RED := Color(0.72, 0.11, 0.15)
const COLOR_BLACK := Color(0.09, 0.09, 0.11)
const COLOR_GREEN := Color(0.05, 0.42, 0.2)
const COLOR_GOLD := Color(0.85, 0.7, 0.35)

## Index into WHEEL_ORDER of the pocket holding the ball, or -1 for no ball.
var result_index := -1


## Angle (in this control's local space) of the center of pocket i.
## Pocket 0 sits at the top when rotation is 0.
static func pocket_angle(i: int) -> float:
	return -PI / 2.0 + i * (TAU / 37.0)


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0
	var step := TAU / 37.0

	# Outer rim.
	draw_circle(center, radius, Color(0.3, 0.19, 0.09))
	draw_circle(center, radius * 0.96, Color(0.5, 0.33, 0.16))

	# Pockets.
	for i in WHEEL_ORDER.size():
		var number: int = WHEEL_ORDER[i]
		var a0 := pocket_angle(i) - step / 2.0
		var color := COLOR_GREEN
		if number != 0:
			color = COLOR_RED if number in RED_NUMBERS else COLOR_BLACK
		_draw_wedge(center, radius * 0.45, radius * 0.92, a0, a0 + step, color)

	# Pocket separators.
	for i in WHEEL_ORDER.size():
		var a := pocket_angle(i) - step / 2.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(center + dir * radius * 0.45, center + dir * radius * 0.92, COLOR_GOLD, 1.5, true)

	# Numbers.
	var font := get_theme_default_font()
	for i in WHEEL_ORDER.size():
		var a := pocket_angle(i)
		var pos := center + Vector2(cos(a), sin(a)) * radius * 0.8
		draw_set_transform(pos, a + PI / 2.0, Vector2.ONE)
		draw_string(font, Vector2(-18, 5), str(WHEEL_ORDER[i]), HORIZONTAL_ALIGNMENT_CENTER, 36, 13, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Hub.
	draw_circle(center, radius * 0.45, Color(0.24, 0.15, 0.08))
	draw_circle(center, radius * 0.41, Color(0.1, 0.28, 0.15))
	draw_circle(center, radius * 0.06, COLOR_GOLD)

	# Ball.
	if result_index >= 0:
		var a := pocket_angle(result_index)
		var pos := center + Vector2(cos(a), sin(a)) * radius * 0.56
		draw_circle(pos, 7.0, Color(0.96, 0.96, 0.9))


func _draw_wedge(center: Vector2, r0: float, r1: float, a0: float, a1: float, color: Color) -> void:
	var points := PackedVector2Array()
	var segments := 4
	for s in segments + 1:
		var t := a0 + (a1 - a0) * s / float(segments)
		points.append(center + Vector2(cos(t), sin(t)) * r1)
	for s in segments + 1:
		var t := a1 - (a1 - a0) * s / float(segments)
		points.append(center + Vector2(cos(t), sin(t)) * r0)
	draw_colored_polygon(points, color)

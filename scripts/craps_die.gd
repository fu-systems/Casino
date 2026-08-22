class_name CrapsDie
extends Control
## A die face drawn from pips, so the dice read at a glance rather than
## being two numbers in boxes.
##
## The face is drawn by a static, so the proposition box can print the same
## pips on the 2, 3, 11 and 12 that the rolling dice show.

const PIPS := {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.29, 0.29), Vector2(0.71, 0.71)],
	3: [Vector2(0.27, 0.27), Vector2(0.5, 0.5), Vector2(0.73, 0.73)],
	4: [Vector2(0.29, 0.29), Vector2(0.71, 0.29), Vector2(0.29, 0.71), Vector2(0.71, 0.71)],
	5: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.5, 0.5),
		Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
	6: [Vector2(0.29, 0.24), Vector2(0.71, 0.24), Vector2(0.29, 0.5),
		Vector2(0.71, 0.5), Vector2(0.29, 0.76), Vector2(0.71, 0.76)],
}

const FACE := Color(0.97, 0.96, 0.93)
const EDGE := Color(0.52, 0.52, 0.49)
const PIP := Color(0.12, 0.1, 0.1)

var value := 1:
	set(v):
		value = clampi(v, 1, 6)
		queue_redraw()


func _draw() -> void:
	draw_face(self, Rect2(Vector2.ZERO, size), value)


## Paints one die face into `rect` on any canvas.
static func draw_face(canvas: CanvasItem, rect: Rect2, face: int) -> void:
	face = clampi(face, 1, 6)
	var box := StyleBoxFlat.new()
	box.bg_color = FACE
	box.set_corner_radius_all(int(rect.size.x * 0.16))
	box.border_color = EDGE
	box.set_border_width_all(maxi(1, int(rect.size.x * 0.03)))
	canvas.draw_style_box(box, rect)
	for pip in PIPS[face]:
		canvas.draw_circle(rect.position + Vector2(pip.x * rect.size.x, pip.y * rect.size.y),
			rect.size.x * 0.085, PIP)

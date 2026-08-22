class_name PolyButton
extends Button
## A button whose clickable area is a polygon, not its rectangle.
##
## The craps felt is painted as one picture with curved and angled betting
## areas, so rectangles are the wrong hit-boxes for it. Godot routes all
## control hit-testing through `_has_point`, and consults it before the
## rect rather than after, so overriding it is enough: every area can be a
## full-rect node carrying its own polygon, and a click falls through to the
## next area whose polygon actually contains it.
##
## Staying a Button means `BetBoard` keeps working unchanged — chip badges,
## `disabled`, and `pressed` all behave as they do everywhere else.

const HOVER := Color(1, 1, 1, 0.15)
const PRESSED := Color(0, 0, 0, 0.3)
const DISABLED := Color(0, 0, 0, 0.28)

## Whether being disabled should dim the area. Come and don't come points
## are never directly bettable, so an empty one is not a bet turned off —
## it is a place chips have not reached yet, and greying it out would read
## as half the table being closed.
var dim_when_disabled := true

## The clickable area, in this control's local coordinates.
var polygon := PackedVector2Array():
	set(value):
		polygon = value
		queue_redraw()


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	# The felt paints the area itself; the button only paints its state.
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _has_point(point: Vector2) -> bool:
	return polygon.size() >= 3 and Geometry2D.is_point_in_polygon(point, polygon)


func _draw() -> void:
	if polygon.size() < 3:
		return
	var tint := Color(0, 0, 0, 0)
	match get_draw_mode():
		DRAW_DISABLED:
			if not dim_when_disabled:
				return
			tint = DISABLED
		DRAW_PRESSED, DRAW_HOVER_PRESSED:
			tint = PRESSED
		DRAW_HOVER:
			tint = HOVER
	if tint.a > 0.0:
		draw_colored_polygon(polygon, tint)

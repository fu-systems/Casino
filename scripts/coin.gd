class_name Coin
extends Control
## The coin baccarat's Coin Flip mode shows instead of cards: heads for the
## banker, tails for the player, and — about one hand in eleven — on its edge
## for a tie. It only shows the outcome; the hand is still dealt and settled
## by the real tableau.

const COLOR_FACE := Color(0.94, 0.78, 0.29)
const COLOR_RIM := Color(0.62, 0.47, 0.12)
const COLOR_TEXT := Color(0.25, 0.17, 0.02)
const FLIP_TIME := 0.9
const FLIPS := 6

## "", "heads", "tails" or "edge".
var face := "":
	set(value):
		face = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(150, 150)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Spins the coin through a few half-turns and lands it on `result`.
func flip(result: String) -> void:
	pivot_offset = size / 2.0
	var half := FLIP_TIME / (FLIPS * 2)
	for i in FLIPS:
		var tween := create_tween()
		tween.tween_property(self, "scale:x", 0.05, half)
		await tween.finished
		face = "heads" if i % 2 == 0 else "tails"
		tween = create_tween()
		tween.tween_property(self, "scale:x", 1.0, half)
		await tween.finished
	face = result
	scale = Vector2.ONE


func _draw() -> void:
	var centre := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - 4.0
	var font := ThemeDB.fallback_font
	if face == "edge":
		# Seen side-on: a thin milled rim standing upright.
		var rim := Rect2(centre.x - 9, centre.y - radius, 18, radius * 2)
		draw_rect(rim, COLOR_RIM)
		for y in range(int(rim.position.y) + 4, int(rim.end.y) - 2, 6):
			draw_line(Vector2(rim.position.x, y), Vector2(rim.end.x, y), COLOR_FACE, 2.0)
		return
	draw_circle(centre, radius, COLOR_RIM)
	draw_circle(centre, radius - 7, COLOR_FACE)
	draw_arc(centre, radius - 16, 0, TAU, 64, COLOR_RIM, 2.0)
	var text: String = {"heads": "B", "tails": "P"}.get(face, "?")
	var font_size := int(radius * 1.05)
	var width := radius * 2
	var baseline := centre.y + font.get_ascent(font_size) / 2.0 - font.get_descent(font_size) / 2.0
	draw_string(font, Vector2(centre.x - radius, baseline), text,
		HORIZONTAL_ALIGNMENT_CENTER, width, font_size, COLOR_TEXT)

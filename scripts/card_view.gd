class_name CardView
extends RefCounted
## Draws a playing card as a Control, at any size. Shared by the blackjack
## table and the trainers so a card looks the same everywhere.

## The size every other size is scaled from.
const BASE_SIZE := Vector2(96, 134)
const COLOR_RED := Color(0.75, 0.1, 0.14)
const COLOR_BLACK := Color(0.1, 0.1, 0.12)
const COLOR_BACK := Color(0.13, 0.2, 0.45)
const COLOR_BACK_EDGE := Color(0.72, 0.76, 0.94)


static func make(card: Dictionary, face_down: bool, size: Vector2 = BASE_SIZE) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scale := size.y / BASE_SIZE.y
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(10 * scale))

	if face_down:
		sb.bg_color = COLOR_BACK
		sb.border_color = COLOR_BACK_EDGE
		sb.set_border_width_all(maxi(2, int(4 * scale)))
		panel.add_theme_stylebox_override("panel", sb)
		var back := Label.new()
		back.text = "❖"
		back.set_anchors_preset(Control.PRESET_FULL_RECT)
		back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		back.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		back.add_theme_font_size_override("font_size", int(40 * scale))
		back.add_theme_color_override("font_color", COLOR_BACK_EDGE)
		panel.add_child(back)
		return panel

	sb.bg_color = Color(0.98, 0.97, 0.94)
	sb.border_color = Color(0.78, 0.78, 0.78)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)

	var color := COLOR_RED if card.suit in ["♥", "♦"] else COLOR_BLACK

	var corner := Label.new()
	corner.text = "%s\n%s" % [card.rank, card.suit]
	corner.position = Vector2(int(8 * scale), int(4 * scale))
	corner.add_theme_font_size_override("font_size", maxi(11, int(20 * scale)))
	corner.add_theme_color_override("font_color", color)
	panel.add_child(corner)

	var center := Label.new()
	center.text = card.suit
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center.add_theme_font_size_override("font_size", int(46 * scale))
	center.add_theme_color_override("font_color", color)
	panel.add_child(center)
	return panel

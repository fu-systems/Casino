class_name CasinoUI
extends RefCounted
## Shared look-and-feel for the casino's hand-built UI.
##
## Every game builds its interface in code, so the button styling used to be
## copy-pasted per game and had drifted apart (blackjack lightened hover by
## 0.12, roulette by 0.15). This is the single definition; 0.12 won.

const HOVER_LIGHTEN := 0.12
const PRESSED_DARKEN := 0.18
const DISABLED_DARKEN := 0.4
const STATES := ["normal", "hover", "pressed", "disabled"]


## Paints a button in the house style: a flat rounded box per state, white
## label, dimmed when disabled. Pass `border` to outline it — the lobby
## buttons are gold-edged, the in-game ones are not.
static func style_button(button: Button, bg: Color, font_size: int,
		pad_h: int, pad_v: int, radius: int = 8,
		border: Color = Color(0, 0, 0, 0)) -> void:
	for state in STATES:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		if state == "hover":
			sb.bg_color = bg.lightened(HOVER_LIGHTEN)
		elif state == "pressed":
			sb.bg_color = bg.darkened(PRESSED_DARKEN)
		elif state == "disabled":
			sb.bg_color = bg.darkened(DISABLED_DARKEN)
		sb.set_corner_radius_all(radius)
		if border.a > 0.0:
			sb.border_color = border
			sb.set_border_width_all(2)
		sb.content_margin_left = pad_h
		sb.content_margin_right = pad_h
		sb.content_margin_top = pad_v
		sb.content_margin_bottom = pad_v
		button.add_theme_stylebox_override(state, sb)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))


## A bordered felt panel, as used for the roulette board and the blackjack
## trainer.
static func panel_style(bg: Color, border: Color, radius: int = 12, margin: int = 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(2)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

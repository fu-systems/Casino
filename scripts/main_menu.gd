extends Control
## Casino lobby: pick a game, see your bankroll, reset it, or quit.

const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_FELT := Color(0.05, 0.22, 0.11)
const COLOR_MUTED := Color(0.78, 0.85, 0.78)
## Two game buttons plus the gap match the width of the full-width pair.
const GAME_SIZE := Vector2(233, 58)
const WIDE_SIZE := Vector2(480, 58)
## Three utility buttons and their two gaps make the same 480.
const SMALL_SIZE := Vector2(150, 58)

## Bump to show the play-money notice again after its wording changes.
const NOTICE_VERSION := 1

## Problem-gambling help, offered from the About box. Free chips are not real
## gambling, but someone who opens a casino game may want these anyway.
const HELP_LINKS := [
	["US: 1-800-GAMBLER", "https://www.ncpgambling.org/"],
	["UK: GamCare", "https://www.gamcare.org.uk/"],
	["AU: Gambling Help Online", "https://www.gamblinghelponline.org.au/"],
]

const FOOTER := "Play money only. No real-money gambling, and no prizes."

var balance_label: Label
var utility_row: HBoxContainer


func _ready() -> void:
	_build_ui()
	Bank.balance_changed.connect(_on_balance_changed)
	_on_balance_changed(Bank.balance)
	if int(SaveData.get_value("notice", "accepted", 0)) < NOTICE_VERSION:
		_show_notice()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_FELT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := SafeArea.create(20)
	add_child(margin)

	var center := CenterContainer.new()
	margin.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "CASINO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Blackjack  •  Roulette  •  Craps  •  Baccarat"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	vbox.add_child(subtitle)

	balance_label = Label.new()
	balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	balance_label.add_theme_font_size_override("font_size", 26)
	balance_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(balance_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	# Four games stacked one per row would run the lobby to ~710px of the
	# 720px design height. Two columns keeps it comfortable and leaves room
	# for a fifth game later.
	var games := GridContainer.new()
	games.columns = 2
	games.add_theme_constant_override("h_separation", 14)
	games.add_theme_constant_override("v_separation", 14)
	vbox.add_child(games)

	_add_menu_button(games, "Blackjack", Color(0.13, 0.13, 0.16), _on_blackjack_pressed, GAME_SIZE)
	_add_menu_button(games, "Roulette", Color(0.55, 0.1, 0.13), _on_roulette_pressed, GAME_SIZE)
	_add_menu_button(games, "Craps", Color(0.16, 0.24, 0.45), _on_craps_pressed, GAME_SIZE)
	_add_menu_button(games, "Baccarat", Color(0.35, 0.16, 0.4), _on_baccarat_pressed, GAME_SIZE)

	_add_menu_button(vbox, "Reset Balance ($%s)" % Bank.fmt(Bank.START_BALANCE),
		Color(0.16, 0.3, 0.2), _on_reset_pressed, WIDE_SIZE)

	utility_row = HBoxContainer.new()
	utility_row.alignment = BoxContainer.ALIGNMENT_CENTER
	utility_row.add_theme_constant_override("separation", 15)
	vbox.add_child(utility_row)
	_add_menu_button(utility_row, "About", Color(0.18, 0.24, 0.3), _on_about_pressed, SMALL_SIZE)
	_add_menu_button(utility_row, "Quit", Color(0.25, 0.22, 0.2), _on_quit_pressed, SMALL_SIZE)

	var footer := Label.new()
	footer.text = FOOTER
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 15)
	footer.add_theme_color_override("font_color", COLOR_MUTED)
	vbox.add_child(footer)


func _add_menu_button(parent: Control, text: String, bg: Color, handler: Callable,
		size: Vector2) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(button, bg, 24, 16, 10, 10, COLOR_GOLD)
	button.add_theme_color_override("font_pressed_color", COLOR_GOLD)
	button.pressed.connect(handler)
	parent.add_child(button)


func _on_balance_changed(new_balance: int) -> void:
	balance_label.text = "Balance: $%s" % Bank.fmt(new_balance)


func _on_blackjack_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/blackjack.tscn")


func _on_roulette_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/roulette.tscn")


func _on_craps_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/craps.tscn")


func _on_baccarat_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/baccarat.tscn")


func _on_reset_pressed() -> void:
	Bank.reset()


func _on_quit_pressed() -> void:
	get_tree().quit()


# --- Notice and About ----------------------------------------------------------

## Shown until accepted, then never again unless NOTICE_VERSION moves. It says
## plainly what the chips are, because a casino game that looks real ought to.
func _show_notice() -> Modal:
	var modal := Modal.open(self, "Before you play", 620)
	modal.name = "Notice"
	modal.add_text("Casino is a casino simulation for adults (18+).")
	modal.add_text("It is played with play money only. Chips are free, unlimited and "
		+ "worth nothing: they can't be bought, won, or cashed out, and there are no prizes.")
	modal.add_text("Reset your balance from this screen whenever you like.", 16, COLOR_MUTED)
	modal.add_button("I'm 18 or over, continue", Color(0.16, 0.35, 0.22), _accept_notice)
	return modal


func _accept_notice() -> void:
	SaveData.set_value("notice", "accepted", NOTICE_VERSION)


func _on_about_pressed() -> void:
	_show_about()


func _show_about() -> Modal:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var modal := Modal.open(self, "Casino %s" % version, 620)
	modal.name = "About"
	modal.add_text("Blackjack, roulette, craps and baccarat, played for free chips "
		+ "that are worth nothing.")
	modal.add_text("Privacy: Casino collects no personal data and contains no ads or "
		+ "analytics. Purchases are handled entirely by Google Play.", 16, COLOR_MUTED)
	modal.add_text("If gambling has stopped being fun for you or someone you know, "
		+ "free and confidential help is available:", 16, COLOR_MUTED)
	for link in HELP_LINKS:
		var button := Button.new()
		button.text = link[0]
		button.focus_mode = Control.FOCUS_NONE
		CasinoUI.style_button(button, Color(0.12, 0.22, 0.32), 17, 12, 8)
		button.pressed.connect(OS.shell_open.bind(link[1]))
		modal.content.add_child(button)
	modal.add_button("Close", Color(0.25, 0.22, 0.2))
	return modal

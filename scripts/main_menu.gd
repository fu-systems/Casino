extends Control
## Casino lobby: pick a game, see your bankroll, reset it, or quit.

const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_FELT := Color(0.05, 0.22, 0.11)
## Two game buttons plus the gap match the width of the full-width pair.
const GAME_SIZE := Vector2(233, 58)
const WIDE_SIZE := Vector2(480, 58)

var balance_label: Label


func _ready() -> void:
	_build_ui()
	Bank.balance_changed.connect(_on_balance_changed)
	_on_balance_changed(Bank.balance)


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
	_add_menu_button(vbox, "Quit", Color(0.25, 0.22, 0.2), _on_quit_pressed, WIDE_SIZE)


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

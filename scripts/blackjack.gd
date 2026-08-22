extends Control
## Blackjack table: betting, hit/stand/double, dealer AI, and payouts.
## House rules: dealer stands on all 17s, blackjack pays 3:2, double down
## on any first two cards, no splits or insurance.

const CHIP_VALUES := [5, 25, 100, 500]
const CARD_SIZE := Vector2(96, 134)
const SUITS := ["♠", "♥", "♦", "♣"]
const RANKS := {
	"A": 11, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
	"8": 8, "9": 9, "10": 10, "J": 10, "Q": 10, "K": 10,
}

const COLOR_FELT := Color(0.05, 0.32, 0.15)
const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_WIN := Color(0.5, 0.92, 0.55)
const COLOR_LOSE := Color(0.96, 0.5, 0.45)

enum Phase { BETTING, PLAYER_TURN, DEALER_TURN, ROUND_OVER }

var deck: Array = []
var player_hand: Array = []
var dealer_hand: Array = []
var bet := 0
var phase: int = Phase.BETTING
var hole_hidden := true

var balance_label: Label
var bet_label: Label
var message_label: Label
var dealer_score_label: Label
var player_score_label: Label
var dealer_cards_box: HBoxContainer
var player_cards_box: HBoxContainer
var chip_holder: Control
var back_button: Button
var clear_button: Button
var deal_button: Button
var hit_button: Button
var stand_button: Button
var double_button: Button
var new_round_button: Button


func _ready() -> void:
	_build_ui()
	Bank.balance_changed.connect(_on_balance_changed)
	_on_balance_changed(Bank.balance)
	_update_bet_label()
	_set_message("Place your bet.", Color.WHITE)
	_update_controls()


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_FELT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Top bar: back button, title, balance.
	var top_bar := HBoxContainer.new()
	vbox.add_child(top_bar)

	back_button = Button.new()
	back_button.text = "< Back"
	back_button.focus_mode = Control.FOCUS_NONE
	_style_button(back_button, Color(0.1, 0.18, 0.12), 18, 14, 8)
	back_button.pressed.connect(_on_back_pressed)
	top_bar.add_child(back_button)

	var title := Label.new()
	title.text = "BLACKJACK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	top_bar.add_child(title)

	balance_label = Label.new()
	balance_label.add_theme_font_size_override("font_size", 22)
	balance_label.add_theme_color_override("font_color", Color.WHITE)
	top_bar.add_child(balance_label)

	# Dealer area.
	dealer_score_label = Label.new()
	dealer_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dealer_score_label.add_theme_font_size_override("font_size", 20)
	dealer_score_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
	vbox.add_child(dealer_score_label)

	dealer_cards_box = _add_card_row(vbox)

	# Center message.
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.custom_minimum_size = Vector2(0, 44)
	message_label.add_theme_font_size_override("font_size", 26)
	vbox.add_child(message_label)

	# Player area.
	player_cards_box = _add_card_row(vbox)

	player_score_label = Label.new()
	player_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_score_label.add_theme_font_size_override("font_size", 20)
	player_score_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
	vbox.add_child(player_score_label)

	var stretch := Control.new()
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(stretch)

	# Bet display.
	bet_label = Label.new()
	bet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bet_label.add_theme_font_size_override("font_size", 24)
	bet_label.add_theme_color_override("font_color", COLOR_GOLD)
	vbox.add_child(bet_label)

	# Chip row (betting phase only).
	var chip_center := CenterContainer.new()
	vbox.add_child(chip_center)
	chip_holder = chip_center

	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 10)
	chip_center.add_child(chip_row)

	for value in CHIP_VALUES:
		var chip := Button.new()
		chip.text = "$%d" % value
		chip.custom_minimum_size = Vector2(84, 50)
		chip.focus_mode = Control.FOCUS_NONE
		_style_button(chip, _chip_color(value), 20, 8, 8, 25)
		chip.pressed.connect(_on_chip_pressed.bind(value))
		chip_row.add_child(chip)

	clear_button = Button.new()
	clear_button.text = "Clear"
	clear_button.custom_minimum_size = Vector2(84, 50)
	clear_button.focus_mode = Control.FOCUS_NONE
	_style_button(clear_button, Color(0.35, 0.3, 0.25), 18, 8, 8, 25)
	clear_button.pressed.connect(_on_clear_pressed)
	chip_row.add_child(clear_button)

	# Action row.
	var action_center := CenterContainer.new()
	vbox.add_child(action_center)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	action_center.add_child(action_row)

	deal_button = _make_action_button(action_row, "Deal", Color(0.72, 0.55, 0.1), _on_deal_pressed)
	hit_button = _make_action_button(action_row, "Hit", Color(0.15, 0.45, 0.25), _on_hit_pressed)
	stand_button = _make_action_button(action_row, "Stand", Color(0.6, 0.16, 0.16), _on_stand_pressed)
	double_button = _make_action_button(action_row, "Double", Color(0.2, 0.3, 0.55), _on_double_pressed)
	new_round_button = _make_action_button(action_row, "New Round", Color(0.72, 0.55, 0.1), _on_new_round_pressed)


func _add_card_row(parent: Control) -> HBoxContainer:
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(0, CARD_SIZE.y + 8)
	parent.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	center.add_child(row)
	return row


func _make_action_button(parent: Control, text: String, bg: Color, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(130, 52)
	button.focus_mode = Control.FOCUS_NONE
	_style_button(button, bg, 22, 18, 10)
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _style_button(button: Button, bg: Color, font_size: int, pad_h: int, pad_v: int, radius: int = 8) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		if state == "hover":
			sb.bg_color = bg.lightened(0.12)
		elif state == "pressed":
			sb.bg_color = bg.darkened(0.18)
		elif state == "disabled":
			sb.bg_color = bg.darkened(0.4)
		sb.set_corner_radius_all(radius)
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


func _chip_color(value: int) -> Color:
	match value:
		5: return Color(0.65, 0.15, 0.15)
		25: return Color(0.13, 0.4, 0.2)
		100: return Color(0.12, 0.12, 0.14)
		500: return Color(0.4, 0.2, 0.5)
	return Color(0.3, 0.3, 0.3)


# --- Cards -------------------------------------------------------------------

func _build_deck() -> void:
	deck.clear()
	for suit in SUITS:
		for rank in RANKS:
			deck.append({"rank": rank, "suit": suit, "value": RANKS[rank]})
	deck.shuffle()


func _draw_card() -> Dictionary:
	return deck.pop_back()


func _hand_value(hand: Array) -> int:
	var total := 0
	var aces := 0
	for card in hand:
		total += card.value
		if card.rank == "A":
			aces += 1
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total


func _is_blackjack(hand: Array) -> bool:
	return hand.size() == 2 and _hand_value(hand) == 21


func _make_card_node(card: Dictionary, face_down: bool) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = CARD_SIZE
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)

	if face_down:
		sb.bg_color = Color(0.13, 0.2, 0.45)
		sb.border_color = Color(0.72, 0.76, 0.94)
		sb.set_border_width_all(4)
		panel.add_theme_stylebox_override("panel", sb)
		var back := Label.new()
		back.text = "❖"
		back.set_anchors_preset(Control.PRESET_FULL_RECT)
		back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		back.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		back.add_theme_font_size_override("font_size", 40)
		back.add_theme_color_override("font_color", Color(0.72, 0.76, 0.94))
		panel.add_child(back)
		return panel

	sb.bg_color = Color(0.98, 0.97, 0.94)
	sb.border_color = Color(0.78, 0.78, 0.78)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)

	var color := Color(0.75, 0.1, 0.14) if card.suit in ["♥", "♦"] else Color(0.1, 0.1, 0.12)

	var corner := Label.new()
	corner.text = "%s\n%s" % [card.rank, card.suit]
	corner.position = Vector2(8, 4)
	corner.add_theme_font_size_override("font_size", 20)
	corner.add_theme_color_override("font_color", color)
	panel.add_child(corner)

	var center := Label.new()
	center.text = card.suit
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center.add_theme_font_size_override("font_size", 46)
	center.add_theme_color_override("font_color", color)
	panel.add_child(center)
	return panel


func _refresh_table() -> void:
	_fill_cards(dealer_cards_box, dealer_hand, hole_hidden)
	_fill_cards(player_cards_box, player_hand, false)

	if dealer_hand.is_empty():
		dealer_score_label.text = "Dealer"
	elif hole_hidden:
		dealer_score_label.text = "Dealer — %d + ?" % dealer_hand[0].value
	else:
		dealer_score_label.text = "Dealer — %d" % _hand_value(dealer_hand)

	if player_hand.is_empty():
		player_score_label.text = "Player"
	else:
		player_score_label.text = "Player — %d" % _hand_value(player_hand)


func _fill_cards(box: HBoxContainer, hand: Array, hide_hole: bool) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for i in hand.size():
		var face_down: bool = hide_hole and i == 1
		box.add_child(_make_card_node(hand[i], face_down))


# --- Betting -----------------------------------------------------------------

func _on_chip_pressed(value: int) -> void:
	if phase != Phase.BETTING:
		return
	if bet + value > Bank.balance:
		_set_message("Not enough chips for that bet.", COLOR_LOSE)
		return
	bet += value
	_update_bet_label()
	_set_message("Press Deal when ready.", Color.WHITE)


func _on_clear_pressed() -> void:
	if phase != Phase.BETTING:
		return
	bet = 0
	_update_bet_label()
	_set_message("Place your bet.", Color.WHITE)


func _update_bet_label() -> void:
	bet_label.text = "Bet: $%s" % Bank.fmt(bet)


# --- Round flow --------------------------------------------------------------

func _on_deal_pressed() -> void:
	if phase != Phase.BETTING:
		return
	if bet <= 0:
		_set_message("Place a bet first.", COLOR_GOLD)
		return
	if not Bank.withdraw(bet):
		_set_message("Not enough chips for that bet.", COLOR_LOSE)
		return

	_build_deck()
	player_hand.clear()
	dealer_hand.clear()
	hole_hidden = true
	player_hand.append(_draw_card())
	dealer_hand.append(_draw_card())
	player_hand.append(_draw_card())
	dealer_hand.append(_draw_card())

	phase = Phase.PLAYER_TURN
	_refresh_table()

	if _is_blackjack(player_hand):
		hole_hidden = false
		phase = Phase.ROUND_OVER
		_refresh_table()
		if _is_blackjack(dealer_hand):
			Bank.deposit(bet)
			_set_message("Both have blackjack — push.", COLOR_GOLD)
		else:
			var winnings := bet * 3 / 2
			Bank.deposit(bet + winnings)
			_set_message("Blackjack! You win $%s." % Bank.fmt(winnings), COLOR_WIN)
	else:
		_set_message("Hit or stand?", Color.WHITE)
	_update_controls()


func _on_hit_pressed() -> void:
	if phase != Phase.PLAYER_TURN:
		return
	player_hand.append(_draw_card())
	_refresh_table()
	var value := _hand_value(player_hand)
	if value > 21:
		phase = Phase.ROUND_OVER
		hole_hidden = false
		_refresh_table()
		_set_message("Bust with %d — you lose $%s." % [value, Bank.fmt(bet)], COLOR_LOSE)
		_update_controls()
	elif value == 21:
		_on_stand_pressed()
	else:
		_update_controls()


func _on_stand_pressed() -> void:
	if phase != Phase.PLAYER_TURN:
		return
	phase = Phase.DEALER_TURN
	_update_controls()
	hole_hidden = false
	_refresh_table()
	_set_message("Dealer's turn…", Color.WHITE)
	while _hand_value(dealer_hand) < 17:
		await get_tree().create_timer(0.55).timeout
		dealer_hand.append(_draw_card())
		_refresh_table()
	_resolve_round()


func _on_double_pressed() -> void:
	if phase != Phase.PLAYER_TURN or player_hand.size() != 2:
		return
	if not Bank.withdraw(bet):
		_set_message("Not enough chips to double.", COLOR_LOSE)
		return
	bet *= 2
	_update_bet_label()
	player_hand.append(_draw_card())
	_refresh_table()
	if _hand_value(player_hand) > 21:
		phase = Phase.ROUND_OVER
		hole_hidden = false
		_refresh_table()
		_set_message("Bust — you lose $%s." % Bank.fmt(bet), COLOR_LOSE)
		_update_controls()
	else:
		_on_stand_pressed()


func _resolve_round() -> void:
	phase = Phase.ROUND_OVER
	var player_value := _hand_value(player_hand)
	var dealer_value := _hand_value(dealer_hand)
	if dealer_value > 21:
		Bank.deposit(bet * 2)
		_set_message("Dealer busts with %d — you win $%s!" % [dealer_value, Bank.fmt(bet)], COLOR_WIN)
	elif player_value > dealer_value:
		Bank.deposit(bet * 2)
		_set_message("%d beats %d — you win $%s!" % [player_value, dealer_value, Bank.fmt(bet)], COLOR_WIN)
	elif player_value < dealer_value:
		_set_message("Dealer's %d beats %d — you lose $%s." % [dealer_value, player_value, Bank.fmt(bet)], COLOR_LOSE)
	else:
		Bank.deposit(bet)
		_set_message("Push at %d — bet returned." % player_value, COLOR_GOLD)
	_update_controls()


func _on_new_round_pressed() -> void:
	if phase != Phase.ROUND_OVER:
		return
	phase = Phase.BETTING
	player_hand.clear()
	dealer_hand.clear()
	hole_hidden = true
	if bet > Bank.balance:
		bet = 0
	_update_bet_label()
	_refresh_table()
	if Bank.balance <= 0:
		_set_message("Out of chips! Reset your balance from the menu.", COLOR_LOSE)
	else:
		_set_message("Place your bet.", Color.WHITE)
	_update_controls()


# --- Helpers -----------------------------------------------------------------

func _update_controls() -> void:
	var betting := phase == Phase.BETTING
	var playing := phase == Phase.PLAYER_TURN
	chip_holder.visible = betting
	deal_button.visible = betting
	hit_button.visible = playing
	stand_button.visible = playing
	double_button.visible = playing and player_hand.size() == 2 and Bank.balance >= bet
	new_round_button.visible = phase == Phase.ROUND_OVER
	back_button.disabled = phase == Phase.DEALER_TURN


func _set_message(text: String, color: Color) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", color)


func _on_balance_changed(new_balance: int) -> void:
	balance_label.text = "Balance: $%s" % Bank.fmt(new_balance)


func _on_back_pressed() -> void:
	if phase == Phase.DEALER_TURN:
		return
	if phase == Phase.PLAYER_TURN:
		# Abandoning a hand mid-round returns the stake.
		Bank.deposit(bet)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

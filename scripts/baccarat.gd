extends Control
## Punto Banco baccarat.
##
## There are no decisions to make: both hands are drawn by a fixed tableau,
## so the whole game is that tableau plus what you backed before the deal.
## Banker pays even money less 5% commission, tie pays 8:1, and the pair side
## bets pay 11:1.

const CHIP_VALUES := [5, 25, 100, 500]
const CARD_SIZE := Vector2(84, 118)
const SUITS := ["♠", "♥", "♦", "♣"]
const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

const DECKS := 8
## Fraction of the shoe still undealt when the dealer reshuffles.
const RESHUFFLE_AT := 0.25
## Taken out of a winning banker bet. Rounded to the nearest dollar, and
## always shown in the result so the arithmetic is visible.
const COMMISSION := 0.05
const TIE_PAYS := 8
const PAIR_PAYS := 11

const COLOR_FELT := Color(0.05, 0.24, 0.28)
const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_WIN := Color(0.5, 0.92, 0.55)
const COLOR_LOSE := Color(0.96, 0.5, 0.45)
const COLOR_MUTED := Color(0.82, 0.88, 0.88)
const COLOR_PLAYER := Color(0.16, 0.34, 0.6)
const COLOR_BANKER := Color(0.6, 0.16, 0.18)
const COLOR_TIE := Color(0.15, 0.45, 0.25)

enum Phase { BETTING, DEALING, ROUND_OVER }

var shoe: Array = []
var shoe_start_size := 0
var shoe_note := ""

var player_cards: Array = []
var banker_cards: Array = []
var phase: int = Phase.BETTING
var selected_chip := 25
var board := BetBoard.new()
var history: Array = []
## Set by tests to force a known deal; consumed before the shoe.
var scripted_cards: Array = []

var balance_label: Label
var message_label: Label
var total_bet_label: Label
var shoe_label: Label
var player_box: HBoxContainer
var banker_box: HBoxContainer
var player_score: Label
var banker_score: Label
var history_box: HBoxContainer
var back_button: Button
var deal_button: Button
var clear_button: Button
var new_round_button: Button


func _ready() -> void:
	_build_ui()
	_reshuffle_shoe()
	shoe_note = ""
	Bank.balance_changed.connect(_on_balance_changed)
	_on_balance_changed(Bank.balance)
	_refresh_table()
	_set_message("Back the player, the banker, or a tie.", Color.WHITE)
	_update_controls()


# --- cards -------------------------------------------------------------------

## Baccarat counts aces as one, pips at face value, and every ten and court
## card as nothing.
static func card_value(rank: String) -> int:
	if rank == "A":
		return 1
	if rank in ["10", "J", "Q", "K"]:
		return 0
	return int(rank)


## A hand's total is its cards modulo ten, so 7 + 8 is 5, not 15.
static func hand_total(cards: Array) -> int:
	var total := 0
	for card in cards:
		total += card_value(card.rank)
	return total % 10


static func is_pair(cards: Array) -> bool:
	return cards.size() >= 2 and cards[0].rank == cards[1].rank


## The banker's tableau: whether the banker draws a third card, given its
## two-card total and the pip value of the player's third card (-1 when the
## player stood). This is the whole game, so it is stated as data.
static func banker_draws(banker_total: int, player_third: int) -> bool:
	if banker_total >= 7:
		return false
	if player_third < 0:
		# Player stood, so the banker plays its own hand like the player.
		return banker_total <= 5
	match banker_total:
		0, 1, 2:
			return true
		3:
			return player_third != 8
		4:
			return player_third >= 2 and player_third <= 7
		5:
			return player_third >= 4 and player_third <= 7
		6:
			return player_third >= 6 and player_third <= 7
	return false


func _reshuffle_shoe() -> void:
	shoe.clear()
	for _d in DECKS:
		for suit in SUITS:
			for rank in RANKS:
				shoe.append({"rank": rank, "suit": suit})
	shoe.shuffle()
	shoe_start_size = shoe.size()
	shoe_note = "Freshly shuffled."


func _reshuffle_threshold() -> int:
	return int(shoe_start_size * RESHUFFLE_AT)


func _reshuffle_if_spent() -> void:
	if shoe.size() > _reshuffle_threshold():
		shoe_note = ""
		return
	_reshuffle_shoe()
	shoe_note = "Cut card reached — shoe reshuffled."


func _draw_card() -> Dictionary:
	if not scripted_cards.is_empty():
		return scripted_cards.pop_front()
	if shoe.is_empty():
		_reshuffle_shoe()
		shoe_note = "Shoe ran out mid-hand — reshuffled."
	return shoe.pop_back()


# --- round flow --------------------------------------------------------------

func _on_deal_pressed() -> void:
	if phase != Phase.BETTING or board.total() <= 0:
		if board.total() <= 0:
			_set_message("Place a bet before dealing.", COLOR_GOLD)
		return

	_reshuffle_if_spent()
	player_cards.clear()
	banker_cards.clear()
	phase = Phase.DEALING
	_update_controls()

	# Two cards each, dealt alternately as at the table.
	for i in 2:
		player_cards.append(_draw_card())
		banker_cards.append(_draw_card())
		_refresh_table()
		await _pause()

	var player_total := hand_total(player_cards)
	var banker_total := hand_total(banker_cards)

	# A natural eight or nine on either side ends the hand at once.
	if player_total < 8 and banker_total < 8:
		var player_third := -1
		if player_total <= 5:
			player_cards.append(_draw_card())
			player_third = card_value(player_cards[2].rank)
			_refresh_table()
			await _pause()
		if banker_draws(banker_total, player_third):
			banker_cards.append(_draw_card())
			_refresh_table()
			await _pause()

	_settle()


func _pause() -> void:
	await get_tree().create_timer(0.4).timeout


## Pays every backed bet and clears the board.
func _settle() -> void:
	phase = Phase.ROUND_OVER
	var player_total := hand_total(player_cards)
	var banker_total := hand_total(banker_cards)
	var staked := board.total()
	var returned := 0
	var commission := 0

	var outcome := "tie"
	if player_total > banker_total:
		outcome = "player"
	elif banker_total > player_total:
		outcome = "banker"

	# Player and banker bets push on a tie rather than losing.
	if outcome == "player":
		returned += board.amount("player") * 2
	elif outcome == "banker":
		var stake := board.amount("banker")
		if stake > 0:
			commission = roundi(stake * COMMISSION)
			returned += stake * 2 - commission
	else:
		returned += board.amount("player") + board.amount("banker")
		returned += board.amount("tie") * (TIE_PAYS + 1)

	if is_pair(player_cards):
		returned += board.amount("player_pair") * (PAIR_PAYS + 1)
	if is_pair(banker_cards):
		returned += board.amount("banker_pair") * (PAIR_PAYS + 1)

	if returned > 0:
		Bank.deposit(returned)
	board.clear_all()

	_add_history(outcome)
	_refresh_table()

	var net := returned - staked
	var headline := "Tie at %d" % player_total
	if outcome == "player":
		headline = "Player %d beats %d" % [player_total, banker_total]
	elif outcome == "banker":
		headline = "Banker %d beats %d" % [banker_total, player_total]
	var tail := " — you break even."
	var colour := COLOR_GOLD
	if net > 0:
		tail = " — you win $%s." % Bank.fmt(net)
		colour = COLOR_WIN
	elif net < 0:
		tail = " — you lose $%s." % Bank.fmt(-net)
		colour = COLOR_LOSE
	if commission > 0:
		tail += " Commission $%s." % Bank.fmt(commission)
	_set_message(headline + tail, colour)
	_update_controls()


func _on_new_round_pressed() -> void:
	if phase != Phase.ROUND_OVER:
		return
	phase = Phase.BETTING
	player_cards.clear()
	banker_cards.clear()
	_refresh_table()
	if Bank.balance <= 0:
		_set_message("Out of chips! Reset your balance from the menu.", COLOR_LOSE)
	else:
		_set_message("Back the player, the banker, or a tie.", Color.WHITE)
	_update_controls()


# --- betting -----------------------------------------------------------------

func _on_bet_pressed(key: String) -> void:
	if phase != Phase.BETTING:
		return
	if not board.place(key, selected_chip):
		_set_message("Not enough balance for a $%d chip." % selected_chip, COLOR_LOSE)
		return
	_update_totals()
	_set_message("Bet placed. Deal when ready.", Color.WHITE)


func _on_clear_pressed() -> void:
	if phase != Phase.BETTING:
		return
	if board.refund_all() > 0:
		_set_message("Bets cleared and refunded.", Color.WHITE)
	_update_totals()


func _on_back_pressed() -> void:
	if phase == Phase.DEALING:
		return
	board.refund_all()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	# The betting areas are labelled with their odds, so chips sit in the
	# corner rather than covering them.
	board.badge_position = BetBoard.Badge.CORNER

	var bg := ColorRect.new()
	bg.color = COLOR_FELT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := SafeArea.create(20)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	# Top bar.
	var top := HBoxContainer.new()
	column.add_child(top)

	back_button = Button.new()
	back_button.text = "< Back"
	back_button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(back_button, Color(0.09, 0.17, 0.2), 18, 14, 8)
	back_button.pressed.connect(_on_back_pressed)
	top.add_child(back_button)

	var title := Label.new()
	title.text = "BACCARAT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	top.add_child(title)

	balance_label = Label.new()
	balance_label.add_theme_font_size_override("font_size", 22)
	balance_label.add_theme_color_override("font_color", Color.WHITE)
	top.add_child(balance_label)

	# The two hands, side by side.
	var hands := HBoxContainer.new()
	hands.add_theme_constant_override("separation", 40)
	hands.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(hands)
	var player_side := _build_hand_side("PLAYER", COLOR_PLAYER)
	hands.add_child(player_side)
	var banker_side := _build_hand_side("BANKER", COLOR_BANKER)
	hands.add_child(banker_side)
	player_box = player_side.get_meta("cards")
	player_score = player_side.get_meta("score")
	banker_box = banker_side.get_meta("cards")
	banker_score = banker_side.get_meta("score")

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(0, 46)
	message_label.add_theme_font_size_override("font_size", 22)
	column.add_child(message_label)

	# Betting areas.
	var bet_row := HBoxContainer.new()
	bet_row.add_theme_constant_override("separation", 12)
	bet_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(bet_row)
	_add_bet_area(bet_row, "player", "PLAYER\n1 : 1", COLOR_PLAYER, Vector2(190, 78))
	_add_bet_area(bet_row, "tie", "TIE\n%d : 1" % TIE_PAYS, COLOR_TIE, Vector2(150, 78))
	_add_bet_area(bet_row, "banker", "BANKER\n1 : 1 less %d%%" % int(COMMISSION * 100),
		COLOR_BANKER, Vector2(190, 78))

	var pair_row := HBoxContainer.new()
	pair_row.add_theme_constant_override("separation", 12)
	pair_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(pair_row)
	_add_bet_area(pair_row, "player_pair", "PLAYER PAIR  %d : 1" % PAIR_PAYS,
		COLOR_PLAYER.darkened(0.25), Vector2(240, 46))
	_add_bet_area(pair_row, "banker_pair", "BANKER PAIR  %d : 1" % PAIR_PAYS,
		COLOR_BANKER.darkened(0.25), Vector2(240, 46))

	var stretch := Control.new()
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stretch)

	# Shoe and recent results.
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 16)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(info)
	shoe_label = Label.new()
	shoe_label.add_theme_font_size_override("font_size", 14)
	shoe_label.add_theme_color_override("font_color", COLOR_MUTED)
	info.add_child(shoe_label)
	history_box = HBoxContainer.new()
	history_box.add_theme_constant_override("separation", 5)
	info.add_child(history_box)

	# Chips and actions.
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(chip_row)

	var chip_label := Label.new()
	chip_label.text = "Chip:"
	chip_label.add_theme_font_size_override("font_size", 20)
	chip_label.add_theme_color_override("font_color", Color.WHITE)
	chip_row.add_child(chip_label)

	var group := ButtonGroup.new()
	for value in CHIP_VALUES:
		var chip := Button.new()
		chip.text = "$%d" % value
		chip.toggle_mode = true
		chip.button_group = group
		chip.custom_minimum_size = Vector2(82, 46)
		chip.focus_mode = Control.FOCUS_NONE
		CasinoUI.style_button(chip, Color(0.11, 0.14, 0.16), 18, 6, 6, 23)
		var chosen := StyleBoxFlat.new()
		chosen.bg_color = COLOR_GOLD
		chosen.set_corner_radius_all(23)
		chip.add_theme_stylebox_override("pressed", chosen)
		chip.add_theme_color_override("font_pressed_color", Color(0.15, 0.1, 0.0))
		chip.pressed.connect(func() -> void: selected_chip = value)
		if value == selected_chip:
			chip.button_pressed = true
		chip_row.add_child(chip)

	total_bet_label = Label.new()
	total_bet_label.add_theme_font_size_override("font_size", 20)
	total_bet_label.add_theme_color_override("font_color", COLOR_GOLD)
	total_bet_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_row.add_child(total_bet_label)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(action_row)
	deal_button = _make_action(action_row, "Deal", Color(0.72, 0.55, 0.1), _on_deal_pressed)
	clear_button = _make_action(action_row, "Clear Bets", Color(0.35, 0.3, 0.25), _on_clear_pressed)
	new_round_button = _make_action(action_row, "New Round", Color(0.72, 0.55, 0.1), _on_new_round_pressed)


func _build_hand_side(title: String, accent: Color) -> Control:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)

	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", accent.lightened(0.45))
	side.add_child(heading)

	var centre := CenterContainer.new()
	centre.custom_minimum_size = Vector2(3 * CARD_SIZE.x + 20, CARD_SIZE.y + 4)
	side.add_child(centre)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	centre.add_child(cards)

	var score := Label.new()
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_theme_font_size_override("font_size", 24)
	score.add_theme_color_override("font_color", COLOR_GOLD)
	side.add_child(score)

	side.set_meta("cards", cards)
	side.set_meta("score", score)
	return side


func _add_bet_area(parent: Control, key: String, text: String, colour: Color, size: Vector2) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(button, colour, 16, 6, 4, 8)
	button.pressed.connect(_on_bet_pressed.bind(key))
	parent.add_child(button)
	board.add(key, button)


func _make_action(parent: Control, text: String, colour: Color, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 50)
	button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(button, colour, 21, 14, 10)
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _make_card_node(card: Dictionary) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = CARD_SIZE
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(9)
	sb.bg_color = Color(0.98, 0.97, 0.94)
	sb.border_color = Color(0.78, 0.78, 0.78)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)

	var colour := Color(0.75, 0.1, 0.14) if card.suit in ["♥", "♦"] else Color(0.1, 0.1, 0.12)

	var corner := Label.new()
	corner.text = "%s\n%s" % [card.rank, card.suit]
	corner.position = Vector2(7, 3)
	corner.add_theme_font_size_override("font_size", 18)
	corner.add_theme_color_override("font_color", colour)
	panel.add_child(corner)

	var pip := Label.new()
	pip.text = str(card_value(card.rank))
	pip.set_anchors_preset(Control.PRESET_FULL_RECT)
	pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pip.add_theme_font_size_override("font_size", 38)
	pip.add_theme_color_override("font_color", colour)
	panel.add_child(pip)
	return panel


func _fill(box: HBoxContainer, cards: Array) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for card in cards:
		box.add_child(_make_card_node(card))


func _refresh_table() -> void:
	_fill(player_box, player_cards)
	_fill(banker_box, banker_cards)
	player_score.text = "—" if player_cards.is_empty() else str(hand_total(player_cards))
	banker_score.text = "—" if banker_cards.is_empty() else str(hand_total(banker_cards))
	_update_totals()
	board.refresh_all_badges()


func _update_totals() -> void:
	total_bet_label.text = "Total: $%s" % Bank.fmt(board.total())
	var text := "%d of %d cards left" % [shoe.size(), shoe_start_size]
	if shoe_note != "":
		text += " · " + shoe_note
	shoe_label.text = text


func _add_history(outcome: String) -> void:
	history.push_front(outcome)
	if history.size() > 12:
		history.resize(12)
	for child in history_box.get_children():
		history_box.remove_child(child)
		child.queue_free()
	for entry in history:
		var dot := Label.new()
		dot.text = {"player": "P", "banker": "B", "tie": "T"}[entry]
		dot.custom_minimum_size = Vector2(26, 26)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"player": COLOR_PLAYER, "banker": COLOR_BANKER, "tie": COLOR_TIE}[entry]
		sb.set_corner_radius_all(13)
		dot.add_theme_stylebox_override("normal", sb)
		dot.add_theme_color_override("font_color", Color.WHITE)
		dot.add_theme_font_size_override("font_size", 13)
		history_box.add_child(dot)


func _update_controls() -> void:
	var betting := phase == Phase.BETTING
	deal_button.visible = betting
	clear_button.visible = betting
	new_round_button.visible = phase == Phase.ROUND_OVER
	back_button.disabled = phase == Phase.DEALING


func _set_message(text: String, colour: Color) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", colour)


func _on_balance_changed(new_balance: int) -> void:
	balance_label.text = "Balance: $%s" % Bank.fmt(new_balance)

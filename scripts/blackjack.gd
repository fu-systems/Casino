extends Control
## Blackjack table: betting, hit/stand/double, dealer AI, and payouts, plus a
## card-counting and strategy trainer.
##
## House rules: dealer stands on all 17s, blackjack pays 3:2, double down on
## any first two cards, no splits or insurance. Cards come from a persistent
## 1-8 deck shoe that reshuffles once penetration passes 75%.

const CHIP_VALUES := [5, 25, 100, 500]
const CARD_SIZE := Vector2(96, 134)
const SUITS := ["♠", "♥", "♦", "♣"]
const RANKS := {
	"A": 11, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
	"8": 8, "9": 9, "10": 10, "J": 10, "Q": 10, "K": 10,
}

const MIN_DECKS := 1
const MAX_DECKS := 8
const DEFAULT_DECKS := 6
## Fraction of the shoe still undealt when the dealer reshuffles.
const RESHUFFLE_AT := 0.25
const TRAINER_WIDTH := 348

const COLOR_FELT := Color(0.05, 0.32, 0.15)
const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_WIN := Color(0.5, 0.92, 0.55)
const COLOR_LOSE := Color(0.96, 0.5, 0.45)
const COLOR_MUTED := Color(0.82, 0.88, 0.82)

enum Phase { BETTING, PLAYER_TURN, DEALER_TURN, ROUND_OVER }

var shoe: Array = []
var shoe_start_size := 0
var deck_count := DEFAULT_DECKS
var shoe_note := ""

var player_hand: Array = []
var dealer_hand: Array = []
var bet := 0
## The stake chosen before any double-down, carried over as the next
## round's opening bet so doubling doesn't silently escalate it.
var base_bet := 0
var phase: int = Phase.BETTING
var hole_hidden := true

## Hi-Lo running count over every card the player has actually seen. The
## hole card is excluded until it is turned over.
var running_count := 0
var hole_counted := false

var show_count := false
var show_basic := false
var show_deviation := false

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

var deck_buttons: Array[Button] = []
## Disabled deck buttons draw their "disabled" box rather than "pressed", so
## the chosen size needs its own dimmed-gold box to stay visible mid-hand.
var deck_locked_on: StyleBoxFlat
var deck_locked_off: StyleBoxFlat
var shuffle_button: Button
var shoe_label: Label
var count_toggle: Button
var count_label: Label
var clear_count_button: Button
var basic_toggle: Button
var basic_label: Label
var deviation_toggle: Button
var deviation_label: Label


func _ready() -> void:
	_build_ui()
	_reshuffle_shoe()
	shoe_note = ""
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
		margin.add_theme_constant_override(side, 20)
	add_child(margin)

	var root_column := VBoxContainer.new()
	root_column.add_theme_constant_override("separation", 8)
	margin.add_child(root_column)

	# Top bar: back button, title, balance.
	var top_bar := HBoxContainer.new()
	root_column.add_child(top_bar)

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

	# Body: the table on the left, the trainer panel down the right.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_column.add_child(body)

	body.add_child(_build_table_column())
	body.add_child(_build_trainer_panel())


func _build_table_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	dealer_score_label = Label.new()
	dealer_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dealer_score_label.add_theme_font_size_override("font_size", 20)
	dealer_score_label.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(dealer_score_label)

	dealer_cards_box = _add_card_row(column)

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(0, 44)
	message_label.add_theme_font_size_override("font_size", 24)
	column.add_child(message_label)

	player_cards_box = _add_card_row(column)

	player_score_label = Label.new()
	player_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_score_label.add_theme_font_size_override("font_size", 20)
	player_score_label.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(player_score_label)

	var stretch := Control.new()
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stretch)

	bet_label = Label.new()
	bet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bet_label.add_theme_font_size_override("font_size", 24)
	bet_label.add_theme_color_override("font_color", COLOR_GOLD)
	column.add_child(bet_label)

	# Chip row (betting phase only).
	var chip_center := CenterContainer.new()
	column.add_child(chip_center)
	chip_holder = chip_center

	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 10)
	chip_center.add_child(chip_row)

	for value in CHIP_VALUES:
		var chip := Button.new()
		chip.text = "$%d" % value
		chip.custom_minimum_size = Vector2(80, 48)
		chip.focus_mode = Control.FOCUS_NONE
		_style_button(chip, _chip_color(value), 20, 8, 8, 24)
		chip.pressed.connect(_on_chip_pressed.bind(value))
		chip_row.add_child(chip)

	clear_button = Button.new()
	clear_button.text = "Clear"
	clear_button.custom_minimum_size = Vector2(80, 48)
	clear_button.focus_mode = Control.FOCUS_NONE
	_style_button(clear_button, Color(0.35, 0.3, 0.25), 18, 8, 8, 24)
	clear_button.pressed.connect(_on_clear_pressed)
	chip_row.add_child(clear_button)

	# Action row.
	var action_center := CenterContainer.new()
	column.add_child(action_center)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	action_center.add_child(action_row)

	deal_button = _make_action_button(action_row, "Deal", Color(0.72, 0.55, 0.1), _on_deal_pressed)
	hit_button = _make_action_button(action_row, "Hit", Color(0.15, 0.45, 0.25), _on_hit_pressed)
	stand_button = _make_action_button(action_row, "Stand", Color(0.6, 0.16, 0.16), _on_stand_pressed)
	double_button = _make_action_button(action_row, "Double", Color(0.2, 0.3, 0.55), _on_double_pressed)
	new_round_button = _make_action_button(action_row, "New Round", Color(0.72, 0.55, 0.1), _on_new_round_pressed)

	return column


func _build_trainer_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(TRAINER_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.24, 0.12)
	style.set_corner_radius_all(12)
	style.border_color = COLOR_GOLD
	style.set_border_width_all(2)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	# --- Shoe ---
	_add_section_header(column, "SHOE")

	var deck_row := HBoxContainer.new()
	deck_row.add_theme_constant_override("separation", 3)
	column.add_child(deck_row)

	var deck_caption := Label.new()
	deck_caption.text = "Decks"
	deck_caption.add_theme_font_size_override("font_size", 15)
	deck_caption.add_theme_color_override("font_color", COLOR_MUTED)
	deck_row.add_child(deck_caption)

	deck_locked_on = StyleBoxFlat.new()
	deck_locked_on.bg_color = Color(0.58, 0.48, 0.19)
	deck_locked_on.set_corner_radius_all(6)
	deck_locked_off = StyleBoxFlat.new()
	deck_locked_off.bg_color = Color(0.08, 0.12, 0.09)
	deck_locked_off.set_corner_radius_all(6)

	var deck_group := ButtonGroup.new()
	for n in range(MIN_DECKS, MAX_DECKS + 1):
		var button := Button.new()
		button.text = str(n)
		button.toggle_mode = true
		button.button_group = deck_group
		button.custom_minimum_size = Vector2(31, 32)
		button.focus_mode = Control.FOCUS_NONE
		_style_button(button, Color(0.11, 0.16, 0.12), 15, 2, 2, 6)
		var chosen := StyleBoxFlat.new()
		chosen.bg_color = COLOR_GOLD
		chosen.set_corner_radius_all(6)
		button.add_theme_stylebox_override("pressed", chosen)
		button.add_theme_color_override("font_pressed_color", Color(0.14, 0.1, 0.0))
		# `pressed` only fires on real clicks, so syncing the toggle state in
		# code below can't feed back into this handler.
		button.pressed.connect(_on_deck_count_pressed.bind(n))
		deck_row.add_child(button)
		deck_buttons.append(button)

	shuffle_button = Button.new()
	shuffle_button.text = "Shuffle the Shoe"
	shuffle_button.focus_mode = Control.FOCUS_NONE
	_style_button(shuffle_button, Color(0.2, 0.3, 0.55), 17, 10, 7)
	shuffle_button.pressed.connect(_on_shuffle_pressed)
	column.add_child(shuffle_button)

	shoe_label = Label.new()
	shoe_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shoe_label.add_theme_font_size_override("font_size", 14)
	shoe_label.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(shoe_label)

	# --- Card counting ---
	_add_section_header(column, "CARD COUNTING (HI-LO)")

	count_toggle = Button.new()
	count_toggle.focus_mode = Control.FOCUS_NONE
	_style_button(count_toggle, Color(0.15, 0.45, 0.25), 17, 10, 7)
	count_toggle.pressed.connect(_on_count_toggle_pressed)
	column.add_child(count_toggle)

	count_label = Label.new()
	count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	count_label.add_theme_font_size_override("font_size", 17)
	count_label.add_theme_color_override("font_color", COLOR_GOLD)
	column.add_child(count_label)

	clear_count_button = Button.new()
	clear_count_button.text = "Clear Count"
	clear_count_button.focus_mode = Control.FOCUS_NONE
	_style_button(clear_count_button, Color(0.35, 0.3, 0.25), 16, 10, 6)
	clear_count_button.pressed.connect(_on_clear_count_pressed)
	column.add_child(clear_count_button)

	# --- Strategy ---
	_add_section_header(column, "STRATEGY TRAINER")

	basic_toggle = Button.new()
	basic_toggle.focus_mode = Control.FOCUS_NONE
	_style_button(basic_toggle, Color(0.15, 0.45, 0.25), 17, 10, 7)
	basic_toggle.pressed.connect(_on_basic_toggle_pressed)
	column.add_child(basic_toggle)

	basic_label = _make_advice_label(column)

	deviation_toggle = Button.new()
	deviation_toggle.focus_mode = Control.FOCUS_NONE
	_style_button(deviation_toggle, Color(0.5, 0.32, 0.1), 17, 10, 7)
	deviation_toggle.pressed.connect(_on_deviation_toggle_pressed)
	column.add_child(deviation_toggle)

	deviation_label = _make_advice_label(column)

	return panel


func _add_section_header(parent: Control, text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	parent.add_child(spacer)

	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", COLOR_GOLD)
	parent.add_child(header)

	var rule := ColorRect.new()
	rule.color = Color(0.94, 0.78, 0.29, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	parent.add_child(rule)


func _make_advice_label(parent: Control) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", COLOR_MUTED)
	parent.add_child(label)
	return label


func _add_card_row(parent: Control) -> HBoxContainer:
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(0, CARD_SIZE.y + 6)
	parent.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	center.add_child(row)
	return row


func _make_action_button(parent: Control, text: String, bg: Color, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(126, 50)
	button.focus_mode = Control.FOCUS_NONE
	_style_button(button, bg, 22, 16, 10)
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


# --- Shoe and counting -------------------------------------------------------

## Builds a fresh shuffled shoe and resets the count, exactly as a real
## reshuffle does.
func _reshuffle_shoe() -> void:
	shoe.clear()
	for _d in deck_count:
		for suit in SUITS:
			for rank in RANKS:
				shoe.append({"rank": rank, "suit": suit, "value": RANKS[rank]})
	shoe.shuffle()
	shoe_start_size = shoe.size()
	running_count = 0
	hole_counted = false
	shoe_note = "Freshly shuffled — count reset to 0."


func _reshuffle_threshold() -> int:
	return int(shoe_start_size * RESHUFFLE_AT)


## Reshuffles between rounds once the shoe is down to its last quarter.
func _reshuffle_if_spent() -> void:
	if shoe.size() > _reshuffle_threshold():
		shoe_note = ""
		return
	_reshuffle_shoe()
	shoe_note = "Cut card reached — shoe reshuffled, count reset."


func _draw_card(count_it: bool = true) -> Dictionary:
	if shoe.is_empty():
		# Only reachable if a single hand outruns the whole remaining shoe.
		_reshuffle_shoe()
		shoe_note = "Shoe ran out mid-hand — reshuffled, count reset."
	var card: Dictionary = shoe.pop_back()
	if count_it:
		running_count += BlackjackStrategy.hi_lo(card)
	return card


## Turns the hole card up, counting it at the moment it becomes visible.
func _reveal_hole() -> void:
	if not hole_counted and dealer_hand.size() >= 2:
		running_count += BlackjackStrategy.hi_lo(dealer_hand[1])
		hole_counted = true
	hole_hidden = false


func _decks_left() -> float:
	return shoe.size() / 52.0


func _true_count() -> float:
	# Guarded so a nearly empty shoe can't divide the count by zero.
	return running_count / maxf(_decks_left(), 0.25)


# --- Cards -------------------------------------------------------------------

func _hand_value(hand: Array) -> int:
	return int(BlackjackStrategy.evaluate(hand).total)


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

	_update_trainer()


func _fill_cards(box: HBoxContainer, hand: Array, hide_hole: bool) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for i in hand.size():
		var face_down: bool = hide_hole and i == 1
		box.add_child(_make_card_node(hand[i], face_down))


# --- Trainer panel -----------------------------------------------------------

func _update_trainer() -> void:
	_update_shoe_label()
	_update_count_display()
	_update_strategy_display()


func _update_shoe_label() -> void:
	var text := "%d of %d cards left (%.1f decks)\nReshuffles at %d cards" % [
		shoe.size(), shoe_start_size, _decks_left(), _reshuffle_threshold()]
	if shoe_note != "":
		text += "\n" + shoe_note
	shoe_label.text = text


func _update_count_display() -> void:
	count_toggle.text = "Hide Count" if show_count else "Show Count"
	count_label.visible = show_count
	if show_count:
		count_label.text = "Running %+d      True %+.1f" % [running_count, _true_count()]


func _update_strategy_display() -> void:
	basic_toggle.text = "Hide Basic Strategy" if show_basic else "Show Basic Strategy"
	deviation_toggle.text = "Hide Count Strategy" if show_deviation else "Show Count Strategy"
	basic_label.visible = show_basic
	deviation_label.visible = show_deviation

	if not show_basic and not show_deviation:
		return

	if phase != Phase.PLAYER_TURN or player_hand.is_empty() or dealer_hand.is_empty():
		var idle := "Deal a hand to see the play for it."
		basic_label.text = idle
		deviation_label.text = idle
		deviation_label.add_theme_color_override("font_color", COLOR_MUTED)
		return

	var dealer_up := int(dealer_hand[0].value)
	var can_double: bool = player_hand.size() == 2 and Bank.balance >= bet

	if show_basic:
		var basic_play := BlackjackStrategy.basic(player_hand, dealer_up, can_double)
		basic_label.text = "%s — %s" % [String(basic_play.action).to_upper(), basic_play.reason]

	if show_deviation:
		var count_play := BlackjackStrategy.with_count(
			player_hand, dealer_up, can_double, _true_count())
		deviation_label.text = "%s — %s" % [String(count_play.action).to_upper(), count_play.reason]
		# Gold whenever the count actually moves the play off basic strategy.
		deviation_label.add_theme_color_override(
			"font_color", COLOR_GOLD if count_play.deviates else COLOR_MUTED)


func _on_count_toggle_pressed() -> void:
	show_count = not show_count
	_update_trainer()


func _on_clear_count_pressed() -> void:
	running_count = 0
	hole_counted = dealer_hand.size() >= 2 and not hole_hidden
	_update_trainer()
	_set_message("Running count cleared to 0.", COLOR_GOLD)


func _on_basic_toggle_pressed() -> void:
	show_basic = not show_basic
	_update_trainer()


func _on_deviation_toggle_pressed() -> void:
	show_deviation = not show_deviation
	_update_trainer()


func _on_deck_count_pressed(n: int) -> void:
	if _mid_hand():
		return
	if n == deck_count:
		# Re-clicking the current size shouldn't silently wipe the count;
		# that's what the shuffle button is for.
		return
	deck_count = n
	_reshuffle_shoe()
	_sync_deck_buttons()
	_update_trainer()
	_set_message("Shoe rebuilt with %d deck%s — count reset." % [n, "" if n == 1 else "s"], COLOR_GOLD)


func _on_shuffle_pressed() -> void:
	if _mid_hand():
		return
	_reshuffle_shoe()
	_update_trainer()
	_set_message("Shoe shuffled — running count reset to 0.", COLOR_GOLD)


func _sync_deck_buttons() -> void:
	for i in deck_buttons.size():
		var button := deck_buttons[i]
		var selected := (i + MIN_DECKS) == deck_count
		button.button_pressed = selected
		button.add_theme_stylebox_override(
			"disabled", deck_locked_on if selected else deck_locked_off)
		button.add_theme_color_override("font_disabled_color",
			Color(0.16, 0.12, 0.02) if selected else Color(1, 1, 1, 0.4))


func _mid_hand() -> bool:
	return phase == Phase.PLAYER_TURN or phase == Phase.DEALER_TURN


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
	base_bet = bet

	_reshuffle_if_spent()
	player_hand.clear()
	dealer_hand.clear()
	hole_hidden = true
	hole_counted = false
	player_hand.append(_draw_card())
	dealer_hand.append(_draw_card())
	player_hand.append(_draw_card())
	# The hole card is dealt face down, so it stays out of the count.
	dealer_hand.append(_draw_card(false))

	phase = Phase.PLAYER_TURN
	_refresh_table()

	# The dealer peeks: a natural on either side ends the round before the
	# player can act, so a dealer natural can never be pushed by a 21 the
	# player builds from three or more cards.
	if _is_blackjack(player_hand) or _is_blackjack(dealer_hand):
		_reveal_hole()
		phase = Phase.ROUND_OVER
		_refresh_table()
		if _is_blackjack(player_hand) and _is_blackjack(dealer_hand):
			Bank.deposit(bet)
			_set_message("Both have blackjack — push.", COLOR_GOLD)
		elif _is_blackjack(player_hand):
			# 3:2 rounded up, so a $5 blackjack pays $8 rather than $7.
			var winnings := roundi(bet * 1.5)
			Bank.deposit(bet + winnings)
			_set_message("Blackjack! You win $%s." % Bank.fmt(winnings), COLOR_WIN)
		else:
			_set_message("Dealer has blackjack — you lose $%s." % Bank.fmt(bet), COLOR_LOSE)
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
		_reveal_hole()
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
	_reveal_hole()
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
		_reveal_hole()
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
	hole_counted = false
	bet = base_bet
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

	# The shoe can only be rebuilt between hands.
	var locked := _mid_hand()
	shuffle_button.disabled = locked
	for button in deck_buttons:
		button.disabled = locked
	_sync_deck_buttons()
	_update_trainer()


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

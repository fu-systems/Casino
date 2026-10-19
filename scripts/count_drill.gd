extends Control
## The Card Counting Trainer pack.
##
## A dealer and a table of auto-players who play basic strategy. Every tap
## lays the next card, so you set the pace — and each round has to be dealt
## inside the difficulty's time limit. When the round is over you enter the
## running count (and, if you like, the true count). Get it right and the
## next round deals; get it wrong, or run out of time, and the run ends.
##
## Scores: most cards counted in one run, and the fastest pace (cards per
## second over at least MIN_PACE_CARDS correctly counted cards), per
## difficulty.

const PACK_ID := "count_trainer"

const DIFFICULTIES := {
	"relaxed": {"name": "Relaxed", "limit": 0.0},
	"casino": {"name": "Casino", "limit": 20.0},
	"pro": {"name": "Pro", "limit": 10.0},
	"shark": {"name": "Shark", "limit": 6.0},
}
const DIFFICULTY_ORDER := ["relaxed", "casino", "pro", "shark"]
const DECK_CHOICES := [2, 4, 6, 8]
const MIN_SEATS := 1
const MAX_SEATS := 7
## A pace only counts as a record over at least this many cards.
const MIN_PACE_CARDS := 50

const DEALER_CARD := Vector2(66, 92)
const SEAT_CARD := Vector2(58, 81)
## Cards in a hand overlap, leaving each one's corner showing.
const FAN_OVERLAP := -32

const COLOR_FELT := Color(0.05, 0.3, 0.15)
const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_WIN := Color(0.5, 0.92, 0.55)
const COLOR_LOSE := Color(0.96, 0.5, 0.45)
const COLOR_MUTED := Color(0.82, 0.88, 0.82)

enum Phase { SETUP, DEALING, ANSWER, OVER }

var difficulty := "casino"
var seat_count := 5
var decks := 6
var ask_true := false

var phase: int = Phase.SETUP
var shoe: BlackjackShoe
var events: Array = []
var event_index := 0
## Cards in the discard tray as the player sees it: the round is dealt out
## of the shoe up front, so the tray only catches up as each card is laid.
var tray := 0
var round_time := 0.0
var timing := false
## The run so far: correctly counted cards and rounds, and the time spent
## dealing them (answering isn't timed).
var run_cards := 0
var run_rounds := 0
var run_time := 0.0
## The value the pad is building.
var entry := 0
var entry_negative := false
var entry_display: Label

var dealer_box: HBoxContainer
var seat_boxes: Array = []
var stats_label: Label
var hint_label: Label
var timer_bar: ProgressBar
var shoe_label: Label
var table: Control


func _ready() -> void:
	difficulty = str(SaveData.get_value("count_trainer", "difficulty", difficulty))
	seat_count = int(SaveData.get_value("count_trainer", "seats", seat_count))
	decks = int(SaveData.get_value("count_trainer", "decks", decks))
	ask_true = bool(SaveData.get_value("count_trainer", "ask_true", ask_true))
	_build_ui()
	_update_stats()
	if Store.owns(PACK_ID):
		_show_setup()
	else:
		LockedPack.cover(self, PACK_ID, "res://scenes/blackjack.tscn")


func _process(delta: float) -> void:
	if not timing:
		return
	round_time += delta
	var limit: float = DIFFICULTIES[difficulty].limit
	if limit > 0.0:
		timer_bar.value = maxf(0.0, 1.0 - round_time / limit) * 100.0
		if round_time > limit:
			timing = false
			_end_run("Too slow — the round took longer than %d seconds." % int(limit))


func _unhandled_input(event: InputEvent) -> void:
	# Space or Enter deals too, for anyone practising at a keyboard.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_SPACE, KEY_ENTER]:
		advance()


# --- Run flow -----------------------------------------------------------------------

func start_run() -> void:
	SaveData.set_value("count_trainer", "difficulty", difficulty)
	SaveData.set_value("count_trainer", "seats", seat_count)
	SaveData.set_value("count_trainer", "decks", decks)
	SaveData.set_value("count_trainer", "ask_true", ask_true)
	shoe = BlackjackShoe.new(decks)
	shoe.reshuffle()
	run_cards = 0
	run_rounds = 0
	run_time = 0.0
	_new_round("Fresh shoe — the count starts at 0.")


func _new_round(note: String = "") -> void:
	if shoe.is_spent():
		shoe.reshuffle()
		note = "Cut card — the dealer shuffles. The count starts again at 0."
	tray = shoe.start_size - shoe.cards.size()
	events = BlackjackRoundSim.deal_round(shoe, seat_count).events
	event_index = 0
	round_time = 0.0
	timing = false
	timer_bar.value = 100.0
	timer_bar.visible = DIFFICULTIES[difficulty].limit > 0.0
	_apply_seat_visibility()
	_clear_table()
	phase = Phase.DEALING
	hint_label.text = (note + "  " if note != "" else "") + "Tap anywhere to deal the next card."
	_update_shoe_label()
	_update_stats()


## Lays the next card. The round's clock starts with its first card.
func advance() -> void:
	if phase != Phase.DEALING or event_index >= events.size():
		return
	timing = true
	_show_event(events[event_index])
	if events[event_index].type == "card":
		tray += 1
	event_index += 1
	# A split brings no new card, so it happens without waiting for a tap.
	while event_index < events.size() and events[event_index].type == "split":
		_show_event(events[event_index])
		event_index += 1
	_update_shoe_label()
	if event_index == events.size():
		timing = false
		phase = Phase.ANSWER
		_ask("What's the running count?", _on_running_count)


func _on_running_count(value: int) -> void:
	var expected := int(events[-1].count)
	if value != expected:
		_end_run("The running count was %+d — you said %+d." % [expected, value])
		return
	if ask_true:
		_ask("And the true count? (%s)" % _decks_text(), _on_true_count)
		return
	_round_counted()


func _on_true_count(value: int) -> void:
	var exact := true_count_shown()
	# Any whole number within half a point of the exact figure is fair: that
	# is what rounding a true count in your head gives.
	if absf(value - exact) > 0.5 + 0.0001:
		_end_run("The true count was %+.1f (%+d over %s) — you said %+d." % [
			exact, int(events[-1].count), _decks_text(), value])
		return
	_round_counted()


func _round_counted() -> void:
	run_cards += cards_in_round()
	run_rounds += 1
	run_time += round_time
	_new_round()


## The true count from what the player can see: the running count over the
## decks left, judged to the nearest half deck from the discard tray.
func true_count_shown() -> float:
	return int(events[-1].count) / maxf(_decks_left_shown(), 0.5)


func _decks_left_shown() -> float:
	return roundf(shoe.decks_left() * 2.0) / 2.0


func _decks_text() -> String:
	var left := _decks_left_shown()
	return "about %s decks left" % ("%d" % int(left) if is_equal_approx(left, roundf(left)) else "%.1f" % left)


## Cards the player actually saw this round: the face-down hole card counts
## once, when it turns over, and a split is no card at all.
func cards_in_round() -> int:
	var seen := 0
	for e in events:
		if e.type == "reveal" or (e.type == "card" and e.face_up):
			seen += 1
	return seen


func pace() -> float:
	return run_cards / run_time if run_time > 0.0 else 0.0


func _end_run(reason: String) -> void:
	phase = Phase.OVER
	timing = false
	var cards_key := "most_cards_" + difficulty
	var pace_key := "best_pace_" + difficulty
	var records: PackedStringArray = []
	if run_cards > int(SaveData.get_value("count_trainer", cards_key, 0)):
		SaveData.set_value("count_trainer", cards_key, run_cards)
		records.append("most cards")
	if run_cards >= MIN_PACE_CARDS and pace() > float(SaveData.get_value("count_trainer", pace_key, 0.0)):
		SaveData.set_value("count_trainer", pace_key, pace())
		records.append("fastest pace")

	var modal := Modal.open(self, "Run over", 860)
	modal.name = "RunOver"
	modal.add_text(reason, 20, COLOR_LOSE)
	modal.add_text("%d cards counted over %d rounds, at %.2f cards a second." % [
		run_cards, run_rounds, pace()], 20, Color.WHITE)
	if not records.is_empty():
		modal.add_text("New best for %s: %s!" % [DIFFICULTIES[difficulty].name, " and ".join(records)], 18, COLOR_GOLD)
	modal.add_text("The last round, card by card:", 16, COLOR_MUTED)
	modal.content.add_child(_review_row())
	modal.add_button("Again", Color(0.16, 0.38, 0.24), start_run)
	modal.add_button("Settings", Color(0.18, 0.24, 0.3), _show_setup)
	_update_stats()


## Every card of the round just played with its Hi-Lo value under it, in the
## order the player saw them — the hole card where it was turned over.
func _review_row() -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for e in events:
		if not e.face_up:
			continue
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.add_child(CardView.make(e.card, false, Vector2(40, 56)))
		var value := Label.new()
		value.text = "%+d" % BlackjackStrategy.hi_lo(e.card)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.add_theme_font_size_override("font_size", 14)
		value.add_theme_color_override("font_color", COLOR_GOLD)
		cell.add_child(value)
		flow.add_child(cell)
	return flow


# --- The table ------------------------------------------------------------------------

func _show_event(e: Dictionary) -> void:
	if e.type == "split":
		var split_seat: VBoxContainer = seat_boxes[int(e.seat)]
		var split_hands: VBoxContainer = split_seat.get_child(1)
		var from: HBoxContainer = split_hands.get_child(0)
		var to := _make_fan()
		split_hands.add_child(to)
		var moved := from.get_child(from.get_child_count() - 1)
		from.remove_child(moved)
		to.add_child(moved)
		return
	if e.type == "reveal":
		# Turn the face-down hole card over in place.
		var hole: Control = dealer_box.get_child(1)
		var face := CardView.make(e.card, false, DEALER_CARD)
		dealer_box.add_child(face)
		dealer_box.move_child(face, 1)
		dealer_box.remove_child(hole)
		hole.queue_free()
		return
	if int(e.seat) == BlackjackRoundSim.DEALER:
		dealer_box.add_child(CardView.make(e.card, not e.face_up, DEALER_CARD))
		return
	var seat: VBoxContainer = seat_boxes[int(e.seat)]
	var hands: VBoxContainer = seat.get_child(1)
	while hands.get_child_count() <= int(e.hand):
		hands.add_child(_make_fan())
	var fan: HBoxContainer = hands.get_child(int(e.hand))
	fan.add_child(CardView.make(e.card, false, SEAT_CARD))


func _make_fan() -> HBoxContainer:
	var fan := HBoxContainer.new()
	fan.alignment = BoxContainer.ALIGNMENT_CENTER
	fan.add_theme_constant_override("separation", FAN_OVERLAP)
	fan.custom_minimum_size = Vector2(0, SEAT_CARD.y)
	return fan


func _clear_table() -> void:
	_clear(dealer_box)
	for seat in seat_boxes:
		_clear(seat.get_child(1))


func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _update_shoe_label() -> void:
	shoe_label.text = "Discard tray: %d of %d cards dealt" % [tray, shoe.start_size]


func _update_stats() -> void:
	var best_cards := int(SaveData.get_value("count_trainer", "most_cards_" + difficulty, 0))
	var best_pace := float(SaveData.get_value("count_trainer", "best_pace_" + difficulty, 0.0))
	stats_label.text = "%s   ·   This run: %d cards, %d rounds, %.2f cards/s   ·   Best: %d cards, %.2f cards/s" % [
		DIFFICULTIES[difficulty].name, run_cards, run_rounds, pace(), best_cards, best_pace]


# --- The number pad -----------------------------------------------------------------

## Asks for a signed whole number on a pad. A pad rather than a choice of
## answers, so the right one can't be picked out from the options.
func _ask(title: String, on_answer: Callable) -> Modal:
	entry = 0
	entry_negative = false
	var modal := Modal.open(self, title, 460)
	modal.name = "Pad"
	entry_display = Label.new()
	entry_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry_display.add_theme_font_size_override("font_size", 44)
	entry_display.add_theme_color_override("font_color", COLOR_GOLD)
	modal.content.add_child(entry_display)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var centre := CenterContainer.new()
	centre.add_child(grid)
	modal.content.add_child(centre)
	for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "±", "0", "⌫"]:
		var button := Button.new()
		button.text = key
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(96, 54)
		CasinoUI.style_button(button, Color(0.1, 0.2, 0.14), 24, 8, 6)
		button.pressed.connect(press_key.bind(key))
		grid.add_child(button)
	modal.add_button("OK", Color(0.16, 0.38, 0.24), func() -> void: on_answer.call(entered()))
	_refresh_entry()
	return modal


func press_key(key: String) -> void:
	match key:
		"±":
			entry_negative = not entry_negative
		"⌫":
			entry /= 10
		_:
			if entry < 100:
				entry = entry * 10 + int(key)
	_refresh_entry()


func entered() -> int:
	return -entry if entry_negative else entry


func _refresh_entry() -> void:
	entry_display.text = "%+d" % entered() if entered() != 0 else ("-0" if entry_negative else "0")


# --- Settings -----------------------------------------------------------------------

func _show_setup() -> Modal:
	phase = Phase.SETUP
	var modal := Modal.open(self, "Counting Trainer", 760)
	modal.name = "Setup"
	modal.add_text("A table of players who all play basic strategy. Tap to deal each card, keep the Hi-Lo count (2-6 are +1, 7-9 are 0, tens and aces are -1), and enter it when the round ends. A wrong count, or a round dealt slower than the time limit, ends the run.", 16, COLOR_MUTED)

	var diff_row := _setting_row(modal, "Time per round")
	for key in DIFFICULTY_ORDER:
		var limit: float = DIFFICULTIES[key].limit
		var label := "%s%s" % [DIFFICULTIES[key].name, "" if limit == 0.0 else " %ds" % int(limit)]
		_choice(diff_row, label, key == difficulty, func() -> void:
			difficulty = key
			_refresh_setup(modal))

	var seat_row := _setting_row(modal, "Players")
	_choice(seat_row, "−", false, func() -> void:
		seat_count = maxi(MIN_SEATS, seat_count - 1)
		_refresh_setup(modal))
	var seats_label := Label.new()
	seats_label.text = str(seat_count)
	seats_label.custom_minimum_size = Vector2(50, 0)
	seats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seats_label.add_theme_font_size_override("font_size", 24)
	seat_row.add_child(seats_label)
	_choice(seat_row, "+", false, func() -> void:
		seat_count = mini(MAX_SEATS, seat_count + 1)
		_refresh_setup(modal))

	var deck_row := _setting_row(modal, "Decks")
	for n in DECK_CHOICES:
		_choice(deck_row, str(n), n == decks, func() -> void:
			decks = n
			_refresh_setup(modal))

	var true_row := _setting_row(modal, "True count too")
	_choice(true_row, "Yes" if ask_true else "No", ask_true, func() -> void:
		ask_true = not ask_true
		_refresh_setup(modal))

	modal.add_button("Start", Color(0.16, 0.38, 0.24), start_run)
	modal.add_button("Back", Color(0.25, 0.22, 0.2), _on_back_pressed, false)
	return modal


func _refresh_setup(modal: Modal) -> void:
	modal.close()
	_update_stats()
	_show_setup()


func _setting_row(modal: Modal, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(170, 0)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(label)
	modal.content.add_child(row)
	return row


func _choice(row: HBoxContainer, text: String, active: bool, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(64, 44)
	CasinoUI.style_button(button, Color(0.45, 0.36, 0.1) if active else Color(0.1, 0.2, 0.14),
		17, 10, 6, 8, COLOR_GOLD if active else Color(0, 0, 0, 0))
	button.pressed.connect(handler)
	row.add_child(button)
	return button


# --- Building -----------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_FELT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := SafeArea.create(18)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var top := HBoxContainer.new()
	column.add_child(top)
	var back := Button.new()
	back.text = "< Back"
	back.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(back, Color(0.09, 0.2, 0.13), 18, 14, 8)
	back.pressed.connect(_on_back_pressed)
	top.add_child(back)
	var title := Label.new()
	title.text = "COUNTING TRAINER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	top.add_child(title)
	var settings := Button.new()
	settings.text = "Settings"
	settings.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(settings, Color(0.18, 0.24, 0.3), 18, 14, 8)
	settings.pressed.connect(func() -> void:
		if phase != Phase.ANSWER:
			timing = false
			_show_setup())
	top.add_child(settings)

	stats_label = Label.new()
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 16)
	stats_label.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(stats_label)

	# The table: the dealer across the top, the seats along the bottom, and
	# a transparent layer over it all that turns any tap into the next card.
	table = Control.new()
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.custom_minimum_size = Vector2(0, 380)
	column.add_child(table)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 10)
	table.add_child(layout)
	var dealer_label := Label.new()
	dealer_label.text = "DEALER"
	dealer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dealer_label.add_theme_font_size_override("font_size", 15)
	dealer_label.add_theme_color_override("font_color", COLOR_MUTED)
	layout.add_child(dealer_label)
	dealer_box = HBoxContainer.new()
	dealer_box.alignment = BoxContainer.ALIGNMENT_CENTER
	dealer_box.add_theme_constant_override("separation", 8)
	dealer_box.custom_minimum_size = Vector2(0, DEALER_CARD.y)
	layout.add_child(dealer_box)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(gap)
	var seats_row := HBoxContainer.new()
	seats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seats_row.add_theme_constant_override("separation", 12)
	layout.add_child(seats_row)
	for s in MAX_SEATS:
		var seat := VBoxContainer.new()
		seat.custom_minimum_size = Vector2(150, 0)
		seat.add_theme_constant_override("separation", 6)
		var name_label := Label.new()
		name_label.text = "Player %d" % (s + 1)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", COLOR_MUTED)
		seat.add_child(name_label)
		var hands := VBoxContainer.new()
		hands.add_theme_constant_override("separation", 6)
		hands.custom_minimum_size = Vector2(0, SEAT_CARD.y * 2 + 6)
		seat.add_child(hands)
		seats_row.add_child(seat)
		seat_boxes.append(seat)

	var catcher := Control.new()
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(_on_table_input)
	table.add_child(catcher)

	hint_label = Label.new()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 18)
	hint_label.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(hint_label)

	timer_bar = ProgressBar.new()
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size = Vector2(0, 10)
	timer_bar.value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = COLOR_GOLD
	fill.set_corner_radius_all(5)
	timer_bar.add_theme_stylebox_override("fill", fill)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.03, 0.16, 0.08)
	track.set_corner_radius_all(5)
	timer_bar.add_theme_stylebox_override("background", track)
	column.add_child(timer_bar)

	shoe_label = Label.new()
	shoe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shoe_label.add_theme_font_size_override("font_size", 15)
	shoe_label.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(shoe_label)
	_apply_seat_visibility()


func _apply_seat_visibility() -> void:
	for s in seat_boxes.size():
		seat_boxes[s].visible = s < seat_count


func _on_table_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if tapped:
		advance()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/blackjack.tscn")

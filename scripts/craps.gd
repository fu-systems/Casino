extends Control
## Craps, with the whole table: line and odds, come and don't come, place
## bets, the field, Big 6/8, the hardways, and the proposition box.
##
## House rules, stated on the board because they change what a bet does:
##   * Place bets and every odds bet are OFF on the come-out roll — they
##     neither win nor lose, and sit there waiting for a point.
##   * Odds are capped 3-4-5x, so the most you can win behind the line is
##     six times it whichever number the point is.
##   * Winners are paid and come down, except place bets and Big 6/8, which
##     stay working until they lose — that is the real table rule and it is
##     what makes those bets worth making.
##   * Place and odds payouts round down to the dollar, as a dealer does.

const CHIP_VALUES := [5, 25, 100, 500]
const POINTS := [4, 5, 6, 8, 9, 10]

## What the point number pays behind the line. The right bettor wins
## num/den; the wrong bettor lays it the other way up.
const TRUE_ODDS := {4: [2, 1], 5: [3, 2], 6: [6, 5], 8: [6, 5], 9: [3, 2], 10: [2, 1]}
## Place bets pay worse than true odds — that is the whole house edge.
const PLACE_ODDS := {4: [9, 5], 5: [7, 5], 6: [7, 6], 8: [7, 6], 9: [7, 5], 10: [9, 5]}
## 3-4-5x: the multiple of the flat bet you may take in odds. Every one of
## them tops out at a win of six times the flat bet.
const ODDS_MULTIPLE := {4: 3, 5: 4, 6: 5, 8: 5, 9: 4, 10: 3}
## The most you may win behind any line bet, as a multiple of it.
const MAX_ODDS_WIN := 6

const HARD_PAYS := {4: 7, 6: 9, 8: 9, 10: 7}
const FIELD_NUMBERS := [2, 3, 4, 9, 10, 11, 12]
## Field numbers that pay more than even money.
const FIELD_BONUS := {2: 2, 12: 3}
const ANY_CRAPS_PAYS := 7
const ELEVEN_PAYS := 15

## The one-roll proposition box. `numbers` is what wins, `pays` the odds,
## `edge` the house's cut — the whole point of printing it is that these are
## the worst bets on the table and it should be possible to see that.
const PROPS := {
	"any_7": {"numbers": [7], "pays": 4, "label": "ANY 7", "edge": "16.7%"},
	"any_craps": {"numbers": [2, 3, 12], "pays": 7, "label": "ANY CRAPS", "edge": "11.1%"},
	"prop_2": {"numbers": [2], "pays": 30, "label": "2  SNAKE EYES", "edge": "13.9%"},
	"prop_3": {"numbers": [3], "pays": 15, "label": "3  ACE DEUCE", "edge": "11.1%"},
	"prop_11": {"numbers": [11], "pays": 15, "label": "11  YO", "edge": "11.1%"},
	"prop_12": {"numbers": [12], "pays": 30, "label": "12  BOXCARS", "edge": "13.9%"},
}

const COLOR_FELT := Color(0.05, 0.22, 0.13)
const COLOR_PANEL := Color(0.04, 0.17, 0.1)
const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_WIN := Color(0.5, 0.92, 0.55)
const COLOR_LOSE := Color(0.96, 0.5, 0.45)
const COLOR_MUTED := Color(0.78, 0.85, 0.78)
const COLOR_PASS := Color(0.13, 0.35, 0.6)
const COLOR_DONT := Color(0.5, 0.14, 0.16)
const COLOR_ODDS := Color(0.1, 0.28, 0.22)
const COLOR_PLACE := Color(0.09, 0.3, 0.18)
const COLOR_FIELD := Color(0.2, 0.28, 0.42)
const COLOR_HARD := Color(0.36, 0.2, 0.45)
const COLOR_PROP := Color(0.42, 0.22, 0.14)

const ROLL_TIME := 0.75
const TUMBLE_STEPS := 8

## 0 when the point is off and the next roll is a come-out.
var point := 0
var rolling := false
var selected_chip := 25
var board := BetBoard.new()
var history: Array = []
## Set by tests to force known dice; consumed before the generator.
var scripted_rolls: Array = []

var die_a: Die
var die_b: Die
var balance_label: Label
var total_bet_label: Label
var message_label: Label
var detail_label: Label
var point_label: Label
var roll_label: Label
var history_box: HBoxContainer
var back_button: Button
var roll_button: Button
var clear_button: Button
var max_odds_button: Button


func _ready() -> void:
	_build_ui()
	Bank.balance_changed.connect(_on_balance_changed)
	_on_balance_changed(Bank.balance)
	_refresh()
	_set_message("Come-out roll. Back the pass line, or fade it.", Color.WHITE)


# --- dice --------------------------------------------------------------------

## Two independent dice, so the totals come out 6-heavy the way they should.
## Rolling `randi() % 11 + 2` would be uniform across 2-12 and would quietly
## turn craps into a different game; the rule suite histograms this.
func _roll_dice() -> Array:
	if not scripted_rolls.is_empty():
		return scripted_rolls.pop_front()
	return [randi() % 6 + 1, randi() % 6 + 1]


# --- odds --------------------------------------------------------------------

## The number an odds bet is riding on: the point for the line, or the come
## point it sits behind. Zero when there is nothing to ride.
func _odds_number(key: String) -> int:
	if key == "pass_odds" or key == "dont_pass_odds":
		return point
	return int(board.meta(key).get("number", 0))


## The 3-4-5x cap. On the right side that is a multiple of the flat bet; on
## the wrong side you lay more than you win, so the cap is whatever lays up
## to the same six-times win.
func _max_odds(key: String) -> int:
	var number := _odds_number(key)
	if number == 0:
		return 0
	var flat := board.amount(String(board.meta(key).get("flat", "")))
	if flat <= 0:
		return 0
	if bool(board.meta(key).get("lay", false)):
		var o: Array = TRUE_ODDS[number]
		return MAX_ODDS_WIN * flat * int(o[0]) / int(o[1])
	return flat * int(ODDS_MULTIPLE[number])


# --- betting -----------------------------------------------------------------

## Why a bet can't be made right now, or "" when it can.
func _refusal(key: String) -> String:
	if rolling:
		return "The dice are out."
	var meta := board.meta(key)
	var kind := String(meta.get("kind", ""))
	match kind:
		"line":
			if point != 0:
				return "The point is %d — back a come bet instead." % point
		"come":
			if point == 0:
				return "Come bets go up once a point is established."
		"odds":
			if _odds_number(key) == 0:
				return "Nothing to take odds on yet."
			if board.amount(String(meta.get("flat", ""))) <= 0:
				return "Take odds behind a bet you already have."
			if board.amount(key) + selected_chip > _max_odds(key):
				return "Odds are capped at $%s behind that bet." % Bank.fmt(_max_odds(key))
		"point":
			# Chips never go straight onto a come point; they get there by
			# winning their way over from the come bar.
			if board.amount(key) <= 0:
				return "Come bets travel to their number — they can't be placed on one."
	return ""


func _on_bet_pressed(key: String) -> void:
	# Tapping a come point that already carries a bet takes odds behind it,
	# since that is the only thing you can actually do to one.
	if String(board.meta(key).get("kind", "")) == "point" and board.amount(key) > 0:
		key = _odds_key_for(key)
	var refusal := _refusal(key)
	if refusal != "":
		_set_message(refusal, COLOR_GOLD)
		return
	if not board.place(key, selected_chip):
		_set_message("Not enough balance for a $%d chip." % selected_chip, COLOR_LOSE)
		return
	_refresh()


## The odds bet riding behind a come or don't come point.
func _odds_key_for(point_key: String) -> String:
	var number := int(board.meta(point_key).get("number", 0))
	if point_key.begins_with("dont"):
		return "dont_come_odds_%d" % number
	return "come_odds_%d" % number


## Tops every odds bet up to its 3-4-5x maximum, as far as the bank allows.
func _on_max_odds_pressed() -> void:
	if rolling:
		return
	var taken := 0
	for key in board.bets:
		if String(board.meta(key).get("kind", "")) != "odds":
			continue
		var want := _max_odds(key) - board.amount(key)
		if want <= 0:
			continue
		want = mini(want, Bank.balance)
		if want > 0 and board.place(key, want):
			taken += want
	if taken > 0:
		_set_message("Took $%s in odds behind the line." % Bank.fmt(taken), Color.WHITE)
	else:
		_set_message("Nothing to take odds on, or nothing left to take them with.", COLOR_GOLD)
	_refresh()


func _on_clear_pressed() -> void:
	if rolling:
		return
	if board.refund_all() > 0:
		_set_message("Bets cleared and refunded.", Color.WHITE)
	_refresh()


func _on_back_pressed() -> void:
	if rolling:
		return
	board.refund_all()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# --- settling ----------------------------------------------------------------

## Pays a bet at num:den and returns the stake with it. Payouts round down
## to the dollar, which is what a dealer does with an odd-money bet.
func _pay(key: String, num: int, den: int) -> int:
	var stake := board.take(key)
	if stake <= 0:
		return 0
	var winnings := stake * num / den
	Bank.deposit(stake + winnings)
	return winnings


## Pays the winnings but leaves the stake working, for place and Big 6/8.
func _pay_and_leave(key: String, num: int, den: int) -> int:
	var stake := board.amount(key)
	if stake <= 0:
		return 0
	var winnings := stake * num / den
	Bank.deposit(winnings)
	return winnings


func _lose(key: String) -> int:
	return board.take(key)


func _push(key: String) -> int:
	return board.refund(key)


func _on_roll_pressed() -> void:
	if rolling:
		return
	if board.total() <= 0:
		_set_message("Get a bet down first.", COLOR_GOLD)
		return
	rolling = true
	_refresh()

	var dice := _roll_dice()
	# Tumble through faces before landing, so the result reads as a roll.
	for i in TUMBLE_STEPS:
		die_a.value = randi() % 6 + 1
		die_b.value = randi() % 6 + 1
		await get_tree().create_timer(ROLL_TIME / TUMBLE_STEPS).timeout
	die_a.value = int(dice[0])
	die_b.value = int(dice[1])

	var before := Bank.balance
	var notes: Array = []
	var headline := _resolve_roll(int(dice[0]), int(dice[1]), notes)

	rolling = false
	_add_history(int(dice[0]) + int(dice[1]))
	_refresh()

	var net := Bank.balance - before
	var colour := COLOR_GOLD
	var tail := ""
	if net > 0:
		colour = COLOR_WIN
		tail = " You're up $%s on the roll." % Bank.fmt(net)
	elif net < 0:
		colour = COLOR_LOSE
		tail = " That cost you $%s." % Bank.fmt(-net)
	_set_message(headline + tail, colour)
	detail_label.text = " · ".join(notes)


## Settles every bet on the table against one roll and returns the headline.
func _resolve_roll(d1: int, d2: int, notes: Array) -> String:
	var total := d1 + d2
	var hard := d1 == d2
	var came_out := point == 0

	# One-roll bets go first: they care only about this roll.
	_resolve_field(total, notes)
	_resolve_props(total, notes)
	_resolve_horn(total, notes)
	_resolve_c_and_e(total, notes)
	_resolve_hardways(total, hard, notes)

	# Come points settle before the come bar, so a bet arriving on a number
	# this roll isn't also paid for the roll that put it there.
	_resolve_come_points(total, came_out, notes)
	_resolve_come_bar(total, notes)

	# Place bets sleep through the come-out. Big 6/8 never do.
	if not came_out:
		_resolve_place(total, notes)
	_resolve_big(total, notes)

	if came_out:
		return _resolve_come_out(total, notes)
	return _resolve_point_roll(total, notes)


func _resolve_field(total: int, notes: Array) -> void:
	var stake := board.amount("field")
	if stake <= 0:
		return
	if total in FIELD_NUMBERS:
		var won := _pay("field", int(FIELD_BONUS.get(total, 1)), 1)
		notes.append("Field %d pays $%s" % [total, Bank.fmt(won)])
	else:
		_lose("field")
		notes.append("Field loses $%s" % Bank.fmt(stake))


func _resolve_props(total: int, notes: Array) -> void:
	for key in PROPS:
		var stake := board.amount(key)
		if stake <= 0:
			continue
		var prop: Dictionary = PROPS[key]
		if total in prop.numbers:
			var won := _pay(key, int(prop.pays), 1)
			notes.append("%s pays $%s" % [prop.label, Bank.fmt(won)])
		else:
			_lose(key)
			notes.append("%s loses $%s" % [prop.label, Bank.fmt(stake)])


## The horn is four bets in one. The winning quarter pays its own odds and
## the other three quarters are simply lost.
func _resolve_horn(total: int, notes: Array) -> void:
	var stake := board.take("horn")
	if stake <= 0:
		return
	if not (total in [2, 3, 11, 12]):
		notes.append("Horn loses $%s" % Bank.fmt(stake))
		return
	var pays: int = 30 if total in [2, 12] else ELEVEN_PAYS
	var back := roundi(stake / 4.0 * (pays + 1))
	Bank.deposit(back)
	notes.append("Horn %d returns $%s of $%s" % [total, Bank.fmt(back), Bank.fmt(stake)])


## Craps and Eleven: half on any craps, half on the yo.
func _resolve_c_and_e(total: int, notes: Array) -> void:
	var stake := board.take("c_and_e")
	if stake <= 0:
		return
	var back := 0
	if total in [2, 3, 12]:
		back = roundi(stake / 2.0 * (ANY_CRAPS_PAYS + 1))
	elif total == 11:
		back = roundi(stake / 2.0 * (ELEVEN_PAYS + 1))
	if back > 0:
		Bank.deposit(back)
		notes.append("C & E %d returns $%s of $%s" % [total, Bank.fmt(back), Bank.fmt(stake)])
	else:
		notes.append("C & E loses $%s" % Bank.fmt(stake))


## A hardway wants its number rolled as a pair. The same number rolled any
## other way kills it, and so does a seven.
func _resolve_hardways(total: int, hard: bool, notes: Array) -> void:
	for number in HARD_PAYS:
		var key := "hard_%d" % number
		var stake := board.amount(key)
		if stake <= 0:
			continue
		if total == number and hard:
			var won := _pay(key, int(HARD_PAYS[number]), 1)
			notes.append("Hard %d pays $%s" % [number, Bank.fmt(won)])
		elif total == number or total == 7:
			_lose(key)
			notes.append("Hard %d loses $%s" % [number, Bank.fmt(stake)])


## A come bet sitting on the bar wins on 7 or 11, loses on craps, and
## otherwise travels to the number rolled and waits there. The don't come
## bet is its mirror, barring the twelve.
func _resolve_come_bar(total: int, notes: Array) -> void:
	var come := board.amount("come")
	if come > 0:
		if total == 7 or total == 11:
			var won := _pay("come", 1, 1)
			notes.append("Come wins $%s" % Bank.fmt(won))
		elif total in [2, 3, 12]:
			_lose("come")
			notes.append("Come loses $%s to craps" % Bank.fmt(come))
		else:
			board.take("come")
			board.move_in("come_%d" % total, come)
			notes.append("Come travels to the %d" % total)

	var dont := board.amount("dont_come")
	if dont > 0:
		if total in [2, 3]:
			var won := _pay("dont_come", 1, 1)
			notes.append("Don't come wins $%s" % Bank.fmt(won))
		elif total == 12:
			_push("dont_come")
			notes.append("Don't come pushes on the bar twelve")
		elif total == 7 or total == 11:
			_lose("dont_come")
			notes.append("Don't come loses $%s" % Bank.fmt(dont))
		else:
			board.take("dont_come")
			board.move_in("dont_come_%d" % total, dont)
			notes.append("Don't come travels to the %d" % total)


## Come points win on their number and die to a seven; don't come points do
## the reverse. Their odds sleep through the come-out, so a come-out seven
## takes the flat bet but hands the odds back.
func _resolve_come_points(total: int, came_out: bool, notes: Array) -> void:
	for number in POINTS:
		var flat_key := "come_%d" % number
		var odds_key := "come_odds_%d" % number
		var flat := board.amount(flat_key)
		if flat > 0:
			if total == number:
				var won := _pay(flat_key, 1, 1)
				var odds := board.amount(odds_key)
				if odds > 0:
					if came_out:
						_push(odds_key)
					else:
						var o: Array = TRUE_ODDS[number]
						won += _pay(odds_key, int(o[0]), int(o[1]))
				notes.append("Come %d pays $%s" % [number, Bank.fmt(won)])
			elif total == 7:
				_lose(flat_key)
				if board.amount(odds_key) > 0:
					if came_out:
						_push(odds_key)
					else:
						_lose(odds_key)
				notes.append("Come %d down $%s" % [number, Bank.fmt(flat)])

		var dont_key := "dont_come_%d" % number
		var lay_key := "dont_come_odds_%d" % number
		var dont := board.amount(dont_key)
		if dont > 0:
			if total == 7:
				var won := _pay(dont_key, 1, 1)
				if board.amount(lay_key) > 0:
					if came_out:
						_push(lay_key)
					else:
						var o: Array = TRUE_ODDS[number]
						won += _pay(lay_key, int(o[1]), int(o[0]))
				notes.append("Don't come %d pays $%s" % [number, Bank.fmt(won)])
			elif total == number:
				_lose(dont_key)
				if board.amount(lay_key) > 0:
					if came_out:
						_push(lay_key)
					else:
						_lose(lay_key)
				notes.append("Don't come %d down $%s" % [number, Bank.fmt(dont)])


## Place bets pay and stay up. A seven takes the lot.
func _resolve_place(total: int, notes: Array) -> void:
	if total == 7:
		var lost := 0
		for number in POINTS:
			lost += _lose("place_%d" % number)
		if lost > 0:
			notes.append("Place bets down $%s" % Bank.fmt(lost))
		return
	if not (total in POINTS):
		return
	var key := "place_%d" % total
	if board.amount(key) <= 0:
		return
	var o: Array = PLACE_ODDS[total]
	var won := _pay_and_leave(key, int(o[0]), int(o[1]))
	notes.append("Place %d pays $%s and stays up" % [total, Bank.fmt(won)])


## Big 6 and Big 8 are always working, which is exactly why they are a worse
## way to bet the same numbers than placing them.
func _resolve_big(total: int, notes: Array) -> void:
	if total == 7:
		var lost := _lose("big_6") + _lose("big_8")
		if lost > 0:
			notes.append("Big 6 and 8 down $%s" % Bank.fmt(lost))
		return
	for number in [6, 8]:
		if total != number:
			continue
		var key := "big_%d" % number
		if board.amount(key) > 0:
			var won := _pay_and_leave(key, 1, 1)
			notes.append("Big %d pays $%s and stays up" % [number, Bank.fmt(won)])


func _resolve_come_out(total: int, notes: Array) -> String:
	if total == 7 or total == 11:
		var won := _pay("pass", 1, 1)
		var lost := _lose("dont_pass")
		if lost > 0:
			notes.append("Don't pass down $%s" % Bank.fmt(lost))
		return "%d — a natural. Pass line wins $%s." % [total, Bank.fmt(won)]
	if total in [2, 3, 12]:
		var lost := _lose("pass")
		if lost > 0:
			notes.append("Pass line down $%s" % Bank.fmt(lost))
		if total == 12:
			# Barring the twelve is where the don't side's edge goes.
			var pushed := _push("dont_pass")
			if pushed > 0:
				notes.append("Don't pass pushes on the bar twelve")
			return "12 — craps, but the twelve is barred, so the don't side pushes."
		var won := _pay("dont_pass", 1, 1)
		return "%d — craps. Don't pass wins $%s." % [total, Bank.fmt(won)]
	point = total
	return "Point is %d. Roll it again before a seven." % total


func _resolve_point_roll(total: int, notes: Array) -> String:
	if total == point:
		var made := point
		var won := _pay("pass", 1, 1)
		var o: Array = TRUE_ODDS[made]
		won += _pay("pass_odds", int(o[0]), int(o[1]))
		var lost := _lose("dont_pass") + _lose("dont_pass_odds")
		if lost > 0:
			notes.append("Don't pass down $%s" % Bank.fmt(lost))
		point = 0
		return "%d — point made! Pass line pays $%s." % [made, Bank.fmt(won)]
	if total == 7:
		var lost := _lose("pass") + _lose("pass_odds")
		var won := _pay("dont_pass", 1, 1)
		var o: Array = TRUE_ODDS[point]
		won += _pay("dont_pass_odds", int(o[1]), int(o[0]))
		if won > 0:
			notes.append("Don't pass pays $%s" % Bank.fmt(won))
		point = 0
		return "Seven out. The line loses $%s and the dice pass on." % Bank.fmt(lost)
	return "%d. Point is still %d." % [total, point]


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	# Every area here carries its name and its price, so chips go in the
	# corner rather than over the words.
	board.badge_position = BetBoard.Badge.CORNER

	var bg := ColorRect.new()
	bg.color = COLOR_FELT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := SafeArea.create(18)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	column.add_child(_build_top_bar())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	body.add_child(_build_side_panel())
	body.add_child(_build_board())


func _build_top_bar() -> Control:
	var top := HBoxContainer.new()

	back_button = Button.new()
	back_button.text = "< Back"
	back_button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(back_button, Color(0.08, 0.16, 0.1), 18, 14, 8)
	back_button.pressed.connect(_on_back_pressed)
	top.add_child(back_button)

	var title := Label.new()
	title.text = "CRAPS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	top.add_child(title)

	balance_label = Label.new()
	balance_label.add_theme_font_size_override("font_size", 22)
	balance_label.add_theme_color_override("font_color", Color.WHITE)
	top.add_child(balance_label)
	return top


func _build_side_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CasinoUI.panel_style(COLOR_PANEL, COLOR_GOLD, 12, 14))
	panel.custom_minimum_size = Vector2(300, 0)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	panel.add_child(side)

	point_label = Label.new()
	point_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	point_label.add_theme_font_size_override("font_size", 24)
	point_label.add_theme_color_override("font_color", COLOR_GOLD)
	side.add_child(point_label)

	var dice_row := HBoxContainer.new()
	dice_row.add_theme_constant_override("separation", 16)
	dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_child(dice_row)
	die_a = Die.new()
	die_a.custom_minimum_size = Vector2(76, 76)
	dice_row.add_child(die_a)
	die_b = Die.new()
	die_b.custom_minimum_size = Vector2(76, 76)
	dice_row.add_child(die_b)

	roll_label = Label.new()
	roll_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roll_label.add_theme_font_size_override("font_size", 18)
	roll_label.add_theme_color_override("font_color", Color.WHITE)
	side.add_child(roll_label)

	roll_button = Button.new()
	roll_button.text = "ROLL"
	roll_button.custom_minimum_size = Vector2(0, 58)
	roll_button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(roll_button, Color(0.72, 0.55, 0.1), 26, 14, 10)
	roll_button.pressed.connect(_on_roll_pressed)
	side.add_child(roll_button)

	var chip_grid := GridContainer.new()
	chip_grid.columns = 4
	chip_grid.add_theme_constant_override("h_separation", 6)
	side.add_child(chip_grid)
	var group := ButtonGroup.new()
	for value in CHIP_VALUES:
		var chip := Button.new()
		chip.text = "$%d" % value
		chip.toggle_mode = true
		chip.button_group = group
		chip.custom_minimum_size = Vector2(61, 42)
		chip.focus_mode = Control.FOCUS_NONE
		CasinoUI.style_button(chip, Color(0.1, 0.14, 0.11), 16, 4, 4, 21)
		var chosen := StyleBoxFlat.new()
		chosen.bg_color = COLOR_GOLD
		chosen.set_corner_radius_all(21)
		chip.add_theme_stylebox_override("pressed", chosen)
		chip.add_theme_color_override("font_pressed_color", Color(0.15, 0.1, 0.0))
		chip.pressed.connect(func() -> void: selected_chip = value)
		if value == selected_chip:
			chip.button_pressed = true
		chip_grid.add_child(chip)

	total_bet_label = Label.new()
	total_bet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_bet_label.add_theme_font_size_override("font_size", 18)
	total_bet_label.add_theme_color_override("font_color", COLOR_GOLD)
	side.add_child(total_bet_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	side.add_child(actions)
	max_odds_button = Button.new()
	max_odds_button.text = "Max Odds"
	max_odds_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	max_odds_button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(max_odds_button, COLOR_ODDS.lightened(0.1), 16, 8, 8)
	max_odds_button.pressed.connect(_on_max_odds_pressed)
	actions.add_child(max_odds_button)
	clear_button = Button.new()
	clear_button.text = "Clear Bets"
	clear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(clear_button, Color(0.32, 0.28, 0.23), 16, 8, 8)
	clear_button.pressed.connect(_on_clear_pressed)
	actions.add_child(clear_button)

	var history_title := Label.new()
	history_title.text = "Recent rolls"
	history_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	history_title.add_theme_font_size_override("font_size", 13)
	history_title.add_theme_color_override("font_color", COLOR_MUTED)
	side.add_child(history_title)

	history_box = HBoxContainer.new()
	history_box.add_theme_constant_override("separation", 4)
	history_box.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_child(history_box)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(filler)

	var rules := Label.new()
	rules.text = "Place bets and odds are off on the come-out. Odds capped 3-4-5x. Place and Big 6/8 stay working after a win."
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_font_size_override("font_size", 12)
	rules.add_theme_color_override("font_color", COLOR_MUTED)
	side.add_child(rules)
	return panel


func _build_board() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CasinoUI.panel_style(COLOR_PANEL, COLOR_GOLD, 12, 12))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var board_column := VBoxContainer.new()
	board_column.add_theme_constant_override("separation", 6)
	panel.add_child(board_column)

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(0, 28)
	message_label.add_theme_font_size_override("font_size", 20)
	board_column.add_child(message_label)

	detail_label = Label.new()
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size = Vector2(0, 30)
	detail_label.add_theme_font_size_override("font_size", 13)
	detail_label.add_theme_color_override("font_color", COLOR_MUTED)
	board_column.add_child(detail_label)

	# Line bets and the odds behind them.
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_column.add_child(line)
	_add_bet(line, "pass", "PASS LINE\n1:1 · edge 1.41%", COLOR_PASS, Vector2(0, 50), 14,
		{"kind": "line"})
	_add_bet(line, "pass_odds", "ODDS\ntrue price · no edge", COLOR_ODDS, Vector2(0, 50), 13,
		{"kind": "odds", "flat": "pass", "lay": false})
	_add_bet(line, "dont_pass", "DON'T PASS\nbar 12 · 1:1 · edge 1.36%", COLOR_DONT, Vector2(0, 50), 13,
		{"kind": "line"})
	_add_bet(line, "dont_pass_odds", "LAY ODDS\ntrue price · no edge", COLOR_ODDS, Vector2(0, 50), 13,
		{"kind": "odds", "flat": "dont_pass", "lay": true})

	var come := HBoxContainer.new()
	come.add_theme_constant_override("separation", 6)
	come.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_column.add_child(come)
	_add_bet(come, "come", "COME  1:1 · edge 1.41%", COLOR_PASS.darkened(0.15), Vector2(0, 40), 14,
		{"kind": "come"})
	_add_bet(come, "dont_come", "DON'T COME  bar 12 · 1:1 · edge 1.36%", COLOR_DONT.darkened(0.15),
		Vector2(0, 40), 14, {"kind": "come"})

	board_column.add_child(_build_numbers())

	_add_bet(board_column, "field",
		"FIELD  2 3 4 9 10 11 12   ·   pays 1:1, the 2 pays 2:1 and the 12 pays 3:1   ·   edge 2.78%",
		COLOR_FIELD, Vector2(0, 42), 14, {"kind": "one_roll"})

	var hard_row := HBoxContainer.new()
	hard_row.add_theme_constant_override("separation", 6)
	hard_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_column.add_child(hard_row)
	_add_bet(hard_row, "big_6", "BIG 6\n1:1 · 9.09%", COLOR_PLACE.lightened(0.1), Vector2(0, 44), 13,
		{"kind": "contract"})
	_add_bet(hard_row, "big_8", "BIG 8\n1:1 · 9.09%", COLOR_PLACE.lightened(0.1), Vector2(0, 44), 13,
		{"kind": "contract"})
	for number in [4, 6, 8, 10]:
		var edge := "11.1%" if number in [4, 10] else "9.09%"
		_add_bet(hard_row, "hard_%d" % number,
			"HARD %d\n%d:1 · %s" % [number, HARD_PAYS[number], edge],
			COLOR_HARD, Vector2(0, 44), 13, {"kind": "contract"})

	board_column.add_child(_build_props())
	return panel


## Six number columns, each stacking everything that can ride on that number:
## the place bet, a come point with its odds, and a don't come point with its
## lay. Come chips arrive on their own; tapping one takes odds behind it.
func _build_numbers() -> Control:
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL

	grid.add_child(_row_label(""))
	for number in POINTS:
		var head := Label.new()
		head.text = str(number)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.custom_minimum_size = Vector2(106, 0)
		head.add_theme_font_size_override("font_size", 20)
		head.add_theme_color_override("font_color", COLOR_GOLD)
		grid.add_child(head)

	var rows := [
		{"label": "PLACE", "prefix": "place_", "colour": COLOR_PLACE, "kind": "place"},
		{"label": "COME", "prefix": "come_", "colour": COLOR_PASS.darkened(0.2), "kind": "point"},
		{"label": "ODDS", "prefix": "come_odds_", "colour": COLOR_ODDS, "kind": "odds"},
		{"label": "DON'T", "prefix": "dont_come_", "colour": COLOR_DONT.darkened(0.2), "kind": "point"},
		{"label": "LAY", "prefix": "dont_come_odds_", "colour": COLOR_ODDS, "kind": "odds"},
	]
	for row in rows:
		grid.add_child(_row_label(String(row.label)))
		for number in POINTS:
			var key: String = String(row.prefix) + str(number)
			var text := ""
			var meta := {"kind": String(row.kind), "number": number}
			match String(row.kind):
				"place":
					var o: Array = PLACE_ODDS[number]
					text = "%d:%d" % [int(o[0]), int(o[1])]
				"odds":
					var lay := String(row.prefix).begins_with("dont")
					meta["lay"] = lay
					meta["flat"] = ("dont_come_" if lay else "come_") + str(number)
			_add_bet(grid, key, text, Color(row.colour), Vector2(106, 30), 12, meta)
	return grid


func _row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(56, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", COLOR_MUTED)
	return label


func _build_props() -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL

	for key in PROPS:
		var prop: Dictionary = PROPS[key]
		_add_bet(grid, key, "%s\n%d:1 · %s" % [prop.label, int(prop.pays), prop.edge],
			COLOR_PROP, Vector2(0, 40), 12, {"kind": "one_roll"})
	_add_bet(grid, "horn", "HORN  2 3 11 12\nquartered · 12.5%", COLOR_PROP.darkened(0.15),
		Vector2(0, 40), 12, {"kind": "one_roll"})
	_add_bet(grid, "c_and_e", "C & E  craps or yo\nhalved · 11.1%", COLOR_PROP.darkened(0.15),
		Vector2(0, 40), 12, {"kind": "one_roll"})
	return grid


func _add_bet(parent: Control, key: String, text: String, colour: Color,
		size: Vector2, font_size: int, meta: Dictionary) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	CasinoUI.style_button(button, colour, font_size, 4, 2, 6)
	button.pressed.connect(_on_bet_pressed.bind(key))
	parent.add_child(button)
	board.add(key, button, meta)


func _add_history(total: int) -> void:
	history.push_front(total)
	if history.size() > 12:
		history.resize(12)
	for child in history_box.get_children():
		history_box.remove_child(child)
		child.queue_free()
	for entry in history:
		var dot := Label.new()
		dot.text = str(entry)
		dot.custom_minimum_size = Vector2(21, 21)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = COLOR_DONT if entry == 7 else Color(0.1, 0.28, 0.16)
		sb.set_corner_radius_all(11)
		dot.add_theme_stylebox_override("normal", sb)
		dot.add_theme_color_override("font_color", Color.WHITE)
		dot.add_theme_font_size_override("font_size", 12)
		history_box.add_child(dot)


func _refresh() -> void:
	point_label.text = "Come-out roll" if point == 0 else "Point:  %d" % point
	roll_label.text = "Rolling…" if rolling else "Last roll: %d" % (die_a.value + die_b.value)
	if history.is_empty() and not rolling:
		roll_label.text = "The dice are yours."
	total_bet_label.text = "On the table: $%s" % Bank.fmt(board.total())
	roll_button.disabled = rolling
	clear_button.disabled = rolling
	max_odds_button.disabled = rolling
	back_button.disabled = rolling
	for key in board.bets:
		var kind := String(board.meta(key).get("kind", ""))
		var button: Button = board.bets[key].button
		match kind:
			"line":
				button.disabled = point != 0
			"come":
				button.disabled = point == 0
			"odds":
				button.disabled = _max_odds(key) <= 0
			"point":
				button.disabled = board.amount(key) <= 0
	board.refresh_all_badges()


func _set_message(text: String, colour: Color) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", colour)


func _on_balance_changed(new_balance: int) -> void:
	balance_label.text = "Balance: $%s" % Bank.fmt(new_balance)


## A die face drawn from pips, so the dice read at a glance rather than
## being two numbers in boxes.
class Die:
	extends Control

	const PIPS := {
		1: [Vector2(0.5, 0.5)],
		2: [Vector2(0.29, 0.29), Vector2(0.71, 0.71)],
		3: [Vector2(0.27, 0.27), Vector2(0.5, 0.5), Vector2(0.73, 0.73)],
		4: [Vector2(0.29, 0.29), Vector2(0.71, 0.29), Vector2(0.29, 0.71), Vector2(0.71, 0.71)],
		5: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.5, 0.5),
			Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
		6: [Vector2(0.29, 0.24), Vector2(0.71, 0.24), Vector2(0.29, 0.5),
			Vector2(0.71, 0.5), Vector2(0.29, 0.76), Vector2(0.71, 0.76)],
	}

	var value := 1:
		set(v):
			value = clampi(v, 1, 6)
			queue_redraw()

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.97, 0.96, 0.93)
		box.set_corner_radius_all(int(size.x * 0.16))
		box.border_color = Color(0.52, 0.52, 0.49)
		box.set_border_width_all(2)
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		for pip in PIPS[value]:
			draw_circle(Vector2(pip.x * size.x, pip.y * size.y), size.x * 0.085,
				Color(0.12, 0.1, 0.1))

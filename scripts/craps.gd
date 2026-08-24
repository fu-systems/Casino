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
## ...and here is exactly how much worse, for the edge toggle.
const PLACE_EDGE := {4: "6.67%", 5: "4.00%", 6: "1.52%", 8: "1.52%", 9: "4.00%", 10: "6.67%"}
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

var felt: CrapsTable
var die_a: CrapsDie
var die_b: CrapsDie
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
var edges_button: Button

## Built once, then handed to both `BetBoard` and the felt.
var _meta_cache := {}


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


## Whether the player may take a bet down right now. Two bets are contracts
## once the dice have made them one: the pass line after a point is
## established, and a come bet that has travelled to its number. They ride
## until they win or lose. Everything else — odds, place bets, the props,
## and the whole don't side — is the player's to pick up between rolls.
func _is_contract(key: String) -> bool:
	if key == "pass":
		return point != 0
	return key.begins_with("come_") and not key.begins_with("come_odds")


func _on_clear_pressed() -> void:
	if rolling:
		return
	var kept := 0
	var refunded := 0
	for key in board.staked_keys():
		if _is_contract(key):
			kept += board.amount(key)
		else:
			refunded += board.refund(key)
	if refunded > 0 and kept > 0:
		_set_message("Removable bets refunded. $%s of contract bets ride until they win or lose." % Bank.fmt(kept), COLOR_GOLD)
	elif refunded > 0:
		_set_message("Bets cleared and refunded.", Color.WHITE)
	elif kept > 0:
		_set_message("The pass line and travelled come bets are contracts — they ride until they win or lose.", COLOR_GOLD)
	_refresh()


## Settles the table for a player walking away: every removable bet is
## handed back, and the contracts are forfeited to the house — a contract
## bet cannot come down, and the table doesn't pause for someone who left.
## Returns what the walk cost.
func _settle_walk_away() -> int:
	var forfeited := 0
	for key in board.staked_keys():
		if _is_contract(key):
			forfeited += board.take(key)
		else:
			board.refund(key)
	return forfeited


func _on_back_pressed() -> void:
	if rolling:
		return
	_settle_walk_away()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# --- settling ----------------------------------------------------------------

## Pays a bet at num:den and returns the stake with it — for the bets that
## genuinely come down with their pay: travelled come bets, and odds once
## their point resolves. Payouts round down to the dollar, which is what a
## dealer does with an odd-money bet.
func _pay(key: String, num: int, den: int) -> int:
	var stake := board.take(key)
	if stake <= 0:
		return 0
	var winnings := stake * num / den
	Bank.deposit(stake + winnings)
	return winnings


## Pays the winnings and leaves the stake standing — the default on a live
## table, where a paid bet keeps working until it loses or the player takes
## it down.
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
		var won := _pay_and_leave("field", int(FIELD_BONUS.get(total, 1)), 1)
		notes.append("Field %d pays $%s and stays up" % [total, Bank.fmt(won)])
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
			var won := _pay_and_leave(key, int(prop.pays), 1)
			notes.append("%s pays $%s and stays up" % [prop.label, Bank.fmt(won)])
		else:
			_lose(key)
			notes.append("%s loses $%s" % [prop.label, Bank.fmt(stake)])


## The horn is four bets in one. On a win the winning quarter pays its own
## odds, the three losing quarters are bought back out of the winnings, and
## the whole horn stays working — which is exactly how a stickman keeps it.
func _resolve_horn(total: int, notes: Array) -> void:
	var stake := board.amount("horn")
	if stake <= 0:
		return
	if not (total in [2, 3, 11, 12]):
		_lose("horn")
		notes.append("Horn loses $%s" % Bank.fmt(stake))
		return
	var pays: int = 30 if total in [2, 12] else ELEVEN_PAYS
	var won := roundi(stake / 4.0 * (pays - 3))
	Bank.deposit(won)
	notes.append("Horn %d pays $%s and stays up" % [total, Bank.fmt(won)])


## Craps and Eleven: half on any craps, half on the yo. As with the horn, a
## win pays the winning half, re-buys the losing half, and stays working.
func _resolve_c_and_e(total: int, notes: Array) -> void:
	var stake := board.amount("c_and_e")
	if stake <= 0:
		return
	var won := 0
	if total in [2, 3, 12]:
		won = roundi(stake / 2.0 * (ANY_CRAPS_PAYS - 1))
	elif total == 11:
		won = roundi(stake / 2.0 * (ELEVEN_PAYS - 1))
	if won > 0:
		Bank.deposit(won)
		notes.append("C & E %d pays $%s and stays up" % [total, Bank.fmt(won)])
	else:
		_lose("c_and_e")
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
			var won := _pay_and_leave(key, int(HARD_PAYS[number]), 1)
			notes.append("Hard %d pays $%s and stays up" % [number, Bank.fmt(won)])
		elif total == number or total == 7:
			_lose(key)
			notes.append("Hard %d loses $%s" % [number, Bank.fmt(stake)])


## A come bet sitting on the bar wins on 7 or 11, loses on craps, and
## otherwise travels to the number rolled and waits there. A winner is paid
## where it lies and stays on the bar as a fresh come bet — a dealer pays
## next to the chips and leaves them unless asked. The don't come bet is its
## mirror, barring the twelve; on the bar twelve it simply stands off.
func _resolve_come_bar(total: int, notes: Array) -> void:
	var come := board.amount("come")
	if come > 0:
		if total == 7 or total == 11:
			var won := _pay_and_leave("come", 1, 1)
			notes.append("Come pays $%s and stays on the bar" % Bank.fmt(won))
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
			var won := _pay_and_leave("dont_come", 1, 1)
			notes.append("Don't come pays $%s and stays on the bar" % Bank.fmt(won))
		elif total == 12:
			notes.append("Bar twelve — the don't come stands off")
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
		var won := _pay_and_leave("pass", 1, 1)
		var lost := _lose("dont_pass")
		if lost > 0:
			notes.append("Don't pass down $%s" % Bank.fmt(lost))
		if won > 0:
			return "%d — a natural. Pass line pays $%s and stays up." % [total, Bank.fmt(won)]
		return "%d — a natural." % total
	if total in [2, 3, 12]:
		var lost := _lose("pass")
		if lost > 0:
			notes.append("Pass line down $%s" % Bank.fmt(lost))
		if total == 12:
			# Barring the twelve is where the don't side's edge goes: the
			# bet neither wins nor loses, it just stands where it is.
			return "12 — craps, but the twelve is barred, so the don't side stands off."
		var won := _pay_and_leave("dont_pass", 1, 1)
		if won > 0:
			return "%d — craps. Don't pass pays $%s and stays up." % [total, Bank.fmt(won)]
		return "%d — craps." % total
	point = total
	return "Point is %d. Roll it again before a seven." % total


func _resolve_point_roll(total: int, notes: Array) -> String:
	if total == point:
		var made := point
		# The flat bet stays for the next come-out; only the odds come down,
		# there being no point left for them to ride.
		var won := _pay_and_leave("pass", 1, 1)
		var o: Array = TRUE_ODDS[made]
		won += _pay("pass_odds", int(o[0]), int(o[1]))
		var lost := _lose("dont_pass") + _lose("dont_pass_odds")
		if lost > 0:
			notes.append("Don't pass down $%s" % Bank.fmt(lost))
		point = 0
		return "%d — point made! Pass line pays $%s and stays up." % [made, Bank.fmt(won)]
	if total == 7:
		var lost := _lose("pass") + _lose("pass_odds")
		var won := _pay_and_leave("dont_pass", 1, 1)
		var o: Array = TRUE_ODDS[point]
		won += _pay("dont_pass_odds", int(o[1]), int(o[0]))
		if won > 0:
			notes.append("Don't pass pays $%s and stays up" % Bank.fmt(won))
		point = 0
		return "Seven out. The line loses $%s and the dice pass on." % Bank.fmt(lost)
	return "%d. Point is still %d." % [total, point]


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_FELT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := SafeArea.create(16)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	column.add_child(_build_top_bar())
	column.add_child(_build_messages())

	# The felt paints itself and owns every area's geometry; the buttons are
	# transparent polygons layered over it.
	felt = CrapsTable.new()
	felt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	felt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	felt.geometry_changed.connect(_fit_areas)
	column.add_child(felt)
	_describe_bets()
	_build_areas()

	column.add_child(_build_rail())


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
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	top.add_child(title)

	balance_label = Label.new()
	balance_label.add_theme_font_size_override("font_size", 22)
	balance_label.add_theme_color_override("font_color", Color.WHITE)
	top.add_child(balance_label)
	return top


func _build_messages() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(0, 26)
	message_label.add_theme_font_size_override("font_size", 19)
	box.add_child(message_label)

	detail_label = Label.new()
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size = Vector2(0, 28)
	detail_label.add_theme_font_size_override("font_size", 13)
	detail_label.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(detail_label)
	return box


## What each area prints. The price comes from the same constant that pays
## it, so the felt can't drift from the payout.
func _describe_bets() -> void:
	felt.set_text("pass", "PASS LINE", "1 TO 1", "edge 1.41%")
	felt.set_text("dont_pass", "DON'T PASS", "1 TO 1", "edge 1.36%")
	felt.set_text("pass_odds", "ODDS", "true price", "no edge")
	felt.set_text("dont_pass_odds", "LAY ODDS", "true price", "no edge")
	felt.set_text("come", "COME", "1 TO 1", "edge 1.41%")
	felt.set_text("dont_come", "DON'T COME", "1 TO 1", "edge 1.36%")
	felt.set_text("field", "FIELD", "1 TO 1", "edge 2.78%")
	felt.set_text("big_6", "BIG 6", "1 TO 1", "9.09%")
	felt.set_text("big_8", "BIG 8", "1 TO 1", "9.09%")

	for number in POINTS:
		var o: Array = PLACE_ODDS[number]
		felt.set_text("place_%d" % number, "PLACE %d" % number,
			"%d TO %d" % [int(o[0]), int(o[1])], String(PLACE_EDGE[number]))
		var t: Array = TRUE_ODDS[number]
		var price := "%d TO %d" % [int(t[0]), int(t[1])]
		felt.set_text("come_%d" % number, "COME %d" % number, "1 TO 1", "edge 1.41%")
		felt.set_text("dont_come_%d" % number, "DON'T COME %d" % number, "1 TO 1", "edge 1.36%")
		# The 3-4-5x multiple is printed on the take-odds spot; the lay pays
		# the same odds the other way up, so its price is inverted.
		felt.set_text("come_odds_%d" % number,
			"ODDS %dx" % int(ODDS_MULTIPLE[number]), price, "no edge")
		felt.set_text("dont_come_odds_%d" % number, "LAY ODDS",
			"%d TO %d" % [int(t[1]), int(t[0])], "no edge")

	for number in HARD_PAYS:
		felt.set_text("hard_%d" % number, "HARD %d" % number,
			"%d TO 1" % int(HARD_PAYS[number]),
			"11.1%" if number in [4, 10] else "9.09%")

	for key in PROPS:
		var prop: Dictionary = PROPS[key]
		felt.set_text(key, String(prop.label), "%d TO 1" % int(prop.pays), String(prop.edge))
	felt.set_text("horn", "HORN", "quartered", "12.5%")
	felt.set_text("c_and_e", "C & E", "halved", "11.1%")


## One transparent polygon button per area, stacked over the felt. Each
## covers the whole felt and hit-tests its own polygon, so a click lands on
## the area whose shape actually contains it rather than whichever bounding
## box happens to be on top.
func _build_areas() -> void:
	for key in _bet_meta():
		var button := PolyButton.new()
		button.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Come points and odds spots never dim. Neither is a bet turned off:
		# one is a place chips have not reached yet, the other a spot with
		# nothing behind it. Greying either reads as a rendering fault, and
		# a dark patch in the middle of the pass line especially so — the
		# refusal message explains why a tap did nothing.
		var kind := String(_bet_meta()[key].get("kind", ""))
		button.dim_when_disabled = not (kind in ["point", "odds"])
		button.pressed.connect(_on_bet_pressed.bind(key))
		felt.add_child(button)
		board.add(key, button, _bet_meta()[key])


## The kinds the game reasons about, keyed the same as the felt's areas.
func _bet_meta() -> Dictionary:
	if not _meta_cache.is_empty():
		return _meta_cache
	_meta_cache = {
		"pass": {"kind": "line"},
		"dont_pass": {"kind": "line"},
		"pass_odds": {"kind": "odds", "flat": "pass", "lay": false},
		"dont_pass_odds": {"kind": "odds", "flat": "dont_pass", "lay": true},
		"come": {"kind": "come"},
		"dont_come": {"kind": "come"},
		"field": {"kind": "one_roll"},
		"big_6": {"kind": "contract"},
		"big_8": {"kind": "contract"},
		"horn": {"kind": "one_roll"},
		"c_and_e": {"kind": "one_roll"},
	}
	for number in POINTS:
		_meta_cache["place_%d" % number] = {"kind": "place", "number": number}
		_meta_cache["come_%d" % number] = {"kind": "point", "number": number}
		_meta_cache["dont_come_%d" % number] = {"kind": "point", "number": number}
		_meta_cache["come_odds_%d" % number] = {
			"kind": "odds", "number": number, "flat": "come_%d" % number, "lay": false}
		_meta_cache["dont_come_odds_%d" % number] = {
			"kind": "odds", "number": number, "flat": "dont_come_%d" % number, "lay": true}
	for number in HARD_PAYS:
		_meta_cache["hard_%d" % number] = {"kind": "contract"}
	for key in PROPS:
		_meta_cache[key] = {"kind": "one_roll"}
	return _meta_cache


## Copies the felt's freshly computed geometry onto the buttons: the hit
## polygon, and the chip spot the badge sits on.
func _fit_areas() -> void:
	for key in board.bets:
		if not felt.areas.has(key):
			continue
		var area: Dictionary = felt.areas[key]
		var button: PolyButton = board.bets[key].button
		button.polygon = area.poly
		board.bets[key].meta["badge_at"] = area.chip
	board.refresh_all_badges()


func _build_rail() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CasinoUI.panel_style(COLOR_PANEL, COLOR_GOLD, 10, 8))

	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 5)
	panel.add_child(rail)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	rail.add_child(top)

	die_a = CrapsDie.new()
	die_a.custom_minimum_size = Vector2(46, 46)
	top.add_child(die_a)
	die_b = CrapsDie.new()
	die_b.custom_minimum_size = Vector2(46, 46)
	top.add_child(die_b)

	point_label = Label.new()
	point_label.custom_minimum_size = Vector2(150, 0)
	point_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	point_label.add_theme_font_size_override("font_size", 19)
	point_label.add_theme_color_override("font_color", COLOR_GOLD)
	top.add_child(point_label)

	var group := ButtonGroup.new()
	for value in CHIP_VALUES:
		var chip := Button.new()
		chip.text = "$%d" % value
		chip.toggle_mode = true
		chip.button_group = group
		chip.custom_minimum_size = Vector2(66, 40)
		chip.focus_mode = Control.FOCUS_NONE
		CasinoUI.style_button(chip, Color(0.1, 0.14, 0.11), 16, 4, 4, 20)
		var chosen := StyleBoxFlat.new()
		chosen.bg_color = COLOR_GOLD
		chosen.set_corner_radius_all(20)
		chip.add_theme_stylebox_override("pressed", chosen)
		chip.add_theme_color_override("font_pressed_color", Color(0.15, 0.1, 0.0))
		chip.pressed.connect(func() -> void: selected_chip = value)
		if value == selected_chip:
			chip.button_pressed = true
		top.add_child(chip)

	roll_button = _rail_button(top, "ROLL", Color(0.72, 0.55, 0.1), _on_roll_pressed, 132)
	roll_button.add_theme_font_size_override("font_size", 22)
	max_odds_button = _rail_button(top, "Max Odds", COLOR_ODDS.lightened(0.12), _on_max_odds_pressed, 100)
	clear_button = _rail_button(top, "Clear", Color(0.32, 0.28, 0.23), _on_clear_pressed, 82)
	edges_button = _rail_button(top, "Show Edges", Color(0.24, 0.2, 0.34), _on_edges_pressed, 116)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	rail.add_child(bottom)

	total_bet_label = Label.new()
	total_bet_label.add_theme_font_size_override("font_size", 15)
	total_bet_label.add_theme_color_override("font_color", COLOR_GOLD)
	bottom.add_child(total_bet_label)

	roll_label = Label.new()
	roll_label.add_theme_font_size_override("font_size", 13)
	roll_label.add_theme_color_override("font_color", COLOR_MUTED)
	bottom.add_child(roll_label)

	history_box = HBoxContainer.new()
	history_box.add_theme_constant_override("separation", 4)
	bottom.add_child(history_box)

	var rules := Label.new()
	rules.text = "Winners stay up, as at a live table — travelled come bets and odds come down with pay. Place bets and odds sit out the come-out; odds capped 3-4-5x."
	# Wraps when squeezed, so the sentence can't widen the scene's minimum.
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules.custom_minimum_size = Vector2(300, 0)
	rules.add_theme_font_size_override("font_size", 12)
	rules.add_theme_color_override("font_color", COLOR_MUTED)
	bottom.add_child(rules)
	return panel


func _rail_button(parent: Control, text: String, colour: Color, handler: Callable,
		width: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 40)
	button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(button, colour, 16, 8, 6)
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _on_edges_pressed() -> void:
	felt.edges_shown = not felt.edges_shown
	edges_button.text = "Hide Edges" if felt.edges_shown else "Show Edges"


func _add_history(total: int) -> void:
	history.push_front(total)
	if history.size() > 10:
		history.resize(10)
	for child in history_box.get_children():
		history_box.remove_child(child)
		child.queue_free()
	for entry in history:
		var dot := Label.new()
		dot.text = str(entry)
		dot.custom_minimum_size = Vector2(20, 20)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = COLOR_DONT if entry == 7 else Color(0.1, 0.28, 0.16)
		sb.set_corner_radius_all(10)
		dot.add_theme_stylebox_override("normal", sb)
		dot.add_theme_color_override("font_color", Color.WHITE)
		dot.add_theme_font_size_override("font_size", 12)
		history_box.add_child(dot)


func _refresh() -> void:
	felt.point = point
	# A number carrying a come or don't come bet grows its odds box.
	var come_open: Array = []
	var dont_open: Array = []
	for number in POINTS:
		if board.amount("come_%d" % number) > 0:
			come_open.append(number)
		if board.amount("dont_come_%d" % number) > 0:
			dont_open.append(number)
	felt.set_odds_open(come_open, dont_open)
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

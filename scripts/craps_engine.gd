class_name CrapsEngine
extends RefCounted
## The rules of the craps table: what every bet covers, what it pays, and
## what it does when the dice land — shared by the table and the Craps
## Systems Lab, so a simulated system plays exactly the game on the felt.
##
## The engine settles a BetBoard. Money moves through the board, which uses
## the player's Bank unless it has been given a wallet of its own (the lab's
## sessions each play from one). After each roll, `results` says what each
## settled bet did ("won", "lost" or "push") and `resolved` how much stake
## was settled, which is what the house edge applies to.

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

## Bet keys by number, spelled out once: building "come_%d" for every number
## on every roll is most of what a roll costs when the lab plays thousands.
const COME_KEYS := {4: "come_4", 5: "come_5", 6: "come_6", 8: "come_8", 9: "come_9", 10: "come_10"}
const COME_ODDS_KEYS := {4: "come_odds_4", 5: "come_odds_5", 6: "come_odds_6",
	8: "come_odds_8", 9: "come_odds_9", 10: "come_odds_10"}
const DONT_COME_KEYS := {4: "dont_come_4", 5: "dont_come_5", 6: "dont_come_6",
	8: "dont_come_8", 9: "dont_come_9", 10: "dont_come_10"}
const DONT_COME_ODDS_KEYS := {4: "dont_come_odds_4", 5: "dont_come_odds_5", 6: "dont_come_odds_6",
	8: "dont_come_odds_8", 9: "dont_come_odds_9", 10: "dont_come_odds_10"}
const PLACE_KEYS := {4: "place_4", 5: "place_5", 6: "place_6", 8: "place_8", 9: "place_9", 10: "place_10"}
const HARD_KEYS := {4: "hard_4", 6: "hard_6", 8: "hard_8", 10: "hard_10"}

## The house edge on each bet per decision, as a fraction of the stake that
## settles — what the lab's "expected" figure is built from. Odds have none.
const EDGES := {
	"pass": 0.0141, "come": 0.0141, "dont_pass": 0.0136, "dont_come": 0.0136,
	"field": 0.0278, "big_6": 0.0909, "big_8": 0.0909,
	"place_4": 0.0667, "place_10": 0.0667, "place_5": 0.04, "place_9": 0.04,
	"place_6": 0.0152, "place_8": 0.0152,
	"hard_4": 0.1111, "hard_10": 0.1111, "hard_6": 0.0909, "hard_8": 0.0909,
	"any_7": 0.1667, "any_craps": 0.1111, "prop_2": 0.1389, "prop_12": 0.1389,
	"prop_3": 0.1111, "prop_11": 0.1111, "horn": 0.125, "c_and_e": 0.1111,
}

## 0 when the point is off and the next roll is a come-out.
var point := 0
var board: BetBoard
## What each bet settled this roll did, and the stake that settled.
var results := {}
var resolved := {}
## Skips writing the roll's notes — the lab plays thousands of rolls nobody
## reads, and the formatting is most of their cost.
var quiet := false

static var _meta_cache := {}


func _init(new_board: BetBoard = null) -> void:
	board = new_board if new_board != null else BetBoard.new()


## The house edge on a bet, come and don't come points included.
static func edge(key: String) -> float:
	if key.begins_with("come_odds") or key.begins_with("dont_come_odds") or key.ends_with("_odds"):
		return 0.0
	if key.begins_with("dont_come_"):
		return EDGES.dont_come
	if key.begins_with("come_"):
		return EDGES.come
	return float(EDGES.get(key, 0.0))


## The kinds the game reasons about, keyed the same as the felt's areas.
static func bet_meta() -> Dictionary:
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



## Why a bet can't be made right now, or "" when it can.
func refusal(key: String, chips: int) -> String:
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
			if odds_number(key) == 0:
				return "Nothing to take odds on yet."
			if board.amount(String(meta.get("flat", ""))) <= 0:
				return "Take odds behind a bet you already have."
			if board.amount(key) + chips > max_odds(key):
				return "Odds are capped at $%s behind that bet." % Bank.fmt(max_odds(key))
		"point":
			# Chips never go straight onto a come point; they get there by
			# winning their way over from the come bar.
			if board.amount(key) <= 0:
				return "Come bets travel to their number — they can't be placed on one."
	return ""


## The number an odds bet is riding on: the point for the line, or the come
## point it sits behind. Zero when there is nothing to ride.
func odds_number(key: String) -> int:
	if key == "pass_odds" or key == "dont_pass_odds":
		return point
	return int(board.meta(key).get("number", 0))


## The 3-4-5x cap. On the right side that is a multiple of the flat bet; on
## the wrong side you lay more than you win, so the cap is whatever lays up
## to the same six-times win.
func max_odds(key: String) -> int:
	var number := odds_number(key)
	if number == 0:
		return 0
	var flat := board.amount(String(board.meta(key).get("flat", "")))
	if flat <= 0:
		return 0
	if bool(board.meta(key).get("lay", false)):
		var o: Array = TRUE_ODDS[number]
		return MAX_ODDS_WIN * flat * int(o[0]) / int(o[1])
	return flat * int(ODDS_MULTIPLE[number])


## Whether the player may take a bet down right now. Two bets are contracts
## once the dice have made them one: the pass line after a point is
## established, and a come bet that has travelled to its number. They ride
## until they win or lose. Everything else — odds, place bets, the props,
## and the whole don't side — is the player's to pick up between rolls.
func is_contract(key: String) -> bool:
	if key == "pass":
		return point != 0
	return key.begins_with("come_") and not key.begins_with("come_odds")


## The odds bet riding behind a come or don't come point.
func odds_key_for(point_key: String) -> String:
	var number := int(board.meta(point_key).get("number", 0))
	if point_key.begins_with("dont"):
		return "dont_come_odds_%d" % number
	return "come_odds_%d" % number


## Pays a bet at num:den and returns the stake with it — for the bets that
## genuinely come down with their pay: travelled come bets, and odds once
## their point resolves. Payouts round down to the dollar, which is what a
## dealer does with an odd-money bet.
func _pay(key: String, num: int, den: int) -> int:
	var stake := board.take(key)
	if stake <= 0:
		return 0
	var winnings := stake * num / den
	board.deposit(stake + winnings)
	_record(key, "won", stake)
	return winnings


## Pays the winnings and leaves the stake standing — the default on a live
## table, where a paid bet keeps working until it loses or the player takes
## it down.
func _pay_and_leave(key: String, num: int, den: int) -> int:
	var stake := board.amount(key)
	if stake <= 0:
		return 0
	var winnings := stake * num / den
	board.deposit(winnings)
	_record(key, "won", stake)
	return winnings


func _lose(key: String) -> int:
	var stake := board.take(key)
	if stake > 0:
		_record(key, "lost", stake)
	return stake


func _push(key: String) -> int:
	var stake := board.refund(key)
	if stake > 0:
		_record(key, "push", stake)
	return stake


## Notes what a bet did on this roll, and the stake that settled.
func _record(key: String, result: String, stake: int) -> void:
	results[key] = result
	if result != "push":
		resolved[key] = stake


## Settles every bet on the table against one roll and returns the headline.
func resolve_roll(d1: int, d2: int, notes: Array) -> String:
	results.clear()
	resolved.clear()
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
		if not quiet:
			notes.append("Field %d pays $%s and stays up" % [total, Bank.fmt(won)])
	else:
		_lose("field")
		if not quiet:
			notes.append("Field loses $%s" % Bank.fmt(stake))


func _resolve_props(total: int, notes: Array) -> void:
	for key in PROPS:
		var stake := board.amount(key)
		if stake <= 0:
			continue
		var prop: Dictionary = PROPS[key]
		if total in prop.numbers:
			var won := _pay_and_leave(key, int(prop.pays), 1)
			if not quiet:
				notes.append("%s pays $%s and stays up" % [prop.label, Bank.fmt(won)])
		else:
			_lose(key)
			if not quiet:
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
		if not quiet:
			notes.append("Horn loses $%s" % Bank.fmt(stake))
		return
	var pays: int = 30 if total in [2, 12] else ELEVEN_PAYS
	var won := roundi(stake / 4.0 * (pays - 3))
	board.deposit(won)
	_record("horn", "won", stake)
	if not quiet:
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
		board.deposit(won)
		_record("c_and_e", "won", stake)
		if not quiet:
			notes.append("C & E %d pays $%s and stays up" % [total, Bank.fmt(won)])
	else:
		_lose("c_and_e")
		if not quiet:
			notes.append("C & E loses $%s" % Bank.fmt(stake))


## A hardway wants its number rolled as a pair. The same number rolled any
## other way kills it, and so does a seven.
func _resolve_hardways(total: int, hard: bool, notes: Array) -> void:
	for number in HARD_PAYS:
		var key: String = HARD_KEYS[number]
		var stake := board.amount(key)
		if stake <= 0:
			continue
		if total == number and hard:
			var won := _pay_and_leave(key, int(HARD_PAYS[number]), 1)
			if not quiet:
				notes.append("Hard %d pays $%s and stays up" % [number, Bank.fmt(won)])
		elif total == number or total == 7:
			_lose(key)
			if not quiet:
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
			if not quiet:
				notes.append("Come pays $%s and stays on the bar" % Bank.fmt(won))
		elif total in [2, 3, 12]:
			_lose("come")
			if not quiet:
				notes.append("Come loses $%s to craps" % Bank.fmt(come))
		else:
			board.take("come")
			board.move_in("come_%d" % total, come)
			if not quiet:
				notes.append("Come travels to the %d" % total)

	var dont := board.amount("dont_come")
	if dont > 0:
		if total in [2, 3]:
			var won := _pay_and_leave("dont_come", 1, 1)
			if not quiet:
				notes.append("Don't come pays $%s and stays on the bar" % Bank.fmt(won))
		elif total == 12:
			if not quiet:
				notes.append("Bar twelve — the don't come stands off")
		elif total == 7 or total == 11:
			_lose("dont_come")
			if not quiet:
				notes.append("Don't come loses $%s" % Bank.fmt(dont))
		else:
			board.take("dont_come")
			board.move_in("dont_come_%d" % total, dont)
			if not quiet:
				notes.append("Don't come travels to the %d" % total)


## Come points win on their number and die to a seven; don't come points do
## the reverse. Their odds sleep through the come-out, so a come-out seven
## takes the flat bet but hands the odds back.
func _resolve_come_points(total: int, came_out: bool, notes: Array) -> void:
	for number in POINTS:
		var flat_key: String = COME_KEYS[number]
		var odds_key: String = COME_ODDS_KEYS[number]
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
				if not quiet:
					notes.append("Come %d pays $%s" % [number, Bank.fmt(won)])
			elif total == 7:
				_lose(flat_key)
				if board.amount(odds_key) > 0:
					if came_out:
						_push(odds_key)
					else:
						_lose(odds_key)
				if not quiet:
					notes.append("Come %d down $%s" % [number, Bank.fmt(flat)])

		var dont_key: String = DONT_COME_KEYS[number]
		var lay_key: String = DONT_COME_ODDS_KEYS[number]
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
				if not quiet:
					notes.append("Don't come %d pays $%s" % [number, Bank.fmt(won)])
			elif total == number:
				_lose(dont_key)
				if board.amount(lay_key) > 0:
					if came_out:
						_push(lay_key)
					else:
						_lose(lay_key)
				if not quiet:
					notes.append("Don't come %d down $%s" % [number, Bank.fmt(dont)])


## Place bets pay and stay up. A seven takes the lot.
func _resolve_place(total: int, notes: Array) -> void:
	if total == 7:
		var lost := 0
		for number in POINTS:
			lost += _lose(PLACE_KEYS[number])
		if lost > 0:
			if not quiet:
				notes.append("Place bets down $%s" % Bank.fmt(lost))
		return
	if not (total in POINTS):
		return
	var key: String = PLACE_KEYS[total]
	if board.amount(key) <= 0:
		return
	var o: Array = PLACE_ODDS[total]
	var won := _pay_and_leave(key, int(o[0]), int(o[1]))
	if not quiet:
		notes.append("Place %d pays $%s and stays up" % [total, Bank.fmt(won)])


## Big 6 and Big 8 are always working, which is exactly why they are a worse
## way to bet the same numbers than placing them.
func _resolve_big(total: int, notes: Array) -> void:
	if total == 7:
		var lost := _lose("big_6") + _lose("big_8")
		if lost > 0:
			if not quiet:
				notes.append("Big 6 and 8 down $%s" % Bank.fmt(lost))
		return
	for number in [6, 8]:
		if total != number:
			continue
		var key := "big_%d" % number
		if board.amount(key) > 0:
			var won := _pay_and_leave(key, 1, 1)
			if not quiet:
				notes.append("Big %d pays $%s and stays up" % [number, Bank.fmt(won)])


func _resolve_come_out(total: int, notes: Array) -> String:
	if total == 7 or total == 11:
		var won := _pay_and_leave("pass", 1, 1)
		var lost := _lose("dont_pass")
		if lost > 0:
			if not quiet:
				notes.append("Don't pass down $%s" % Bank.fmt(lost))
		if won > 0:
			return "%d — a natural. Pass line pays $%s and stays up." % [total, Bank.fmt(won)]
		return "%d — a natural." % total
	if total in [2, 3, 12]:
		var lost := _lose("pass")
		if lost > 0:
			if not quiet:
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
			if not quiet:
				notes.append("Don't pass down $%s" % Bank.fmt(lost))
		point = 0
		return "%d — point made! Pass line pays $%s and stays up." % [made, Bank.fmt(won)]
	if total == 7:
		var lost := _lose("pass") + _lose("pass_odds")
		var won := _pay_and_leave("dont_pass", 1, 1)
		var o: Array = TRUE_ODDS[point]
		won += _pay("dont_pass_odds", int(o[1]), int(o[0]))
		if won > 0:
			if not quiet:
				notes.append("Don't pass pays $%s and stays up" % Bank.fmt(won))
		point = 0
		return "Seven out. The line loses $%s and the dice pass on." % Bank.fmt(lost)
	return "%d. Point is still %d." % [total, point]

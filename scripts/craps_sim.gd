class_name CrapsSim
extends RefCounted
## Craps for the Systems Lab: the table's own CrapsEngine on a board with no
## buttons, playing from the session's wallet.
##
## Craps bets don't all settle each roll, so a system's layout means "keep
## these bets up", as far as the table allows at that moment:
##   * Pass and don't pass go down on a come-out; come and don't come once a
##     point is on. A bet that's out of season simply waits.
##   * Each bet is topped up to its stake before the roll — so a bet that
##     lost goes back up, and one that won and stayed up is left alone.
##   * A bet the layout drops is taken down, unless the table says it's a
##     contract (the pass line on a point, a come bet that has travelled).
##   * Odds go behind the pass line, the don't pass, or every come or don't
##     come point, at the multiple asked for (0 = the table maximum).

## Positions a system can bet on, in the picker's groups.
const POSITIONS := [
	["pass", "Pass line", "Line"], ["dont_pass", "Don't pass", "Line"],
	["come", "Come", "Line"], ["dont_come", "Don't come", "Line"],
	["place_4", "Place 4", "Place"], ["place_5", "Place 5", "Place"], ["place_6", "Place 6", "Place"],
	["place_8", "Place 8", "Place"], ["place_9", "Place 9", "Place"], ["place_10", "Place 10", "Place"],
	["field", "Field", "Field and Big"], ["big_6", "Big 6", "Field and Big"], ["big_8", "Big 8", "Field and Big"],
	["hard_4", "Hard 4", "Hardways"], ["hard_6", "Hard 6", "Hardways"],
	["hard_8", "Hard 8", "Hardways"], ["hard_10", "Hard 10", "Hardways"],
	["any_7", "Any 7", "Propositions"], ["any_craps", "Any craps", "Propositions"],
	["prop_2", "Snake eyes (2)", "Propositions"], ["prop_3", "Ace-deuce (3)", "Propositions"],
	["prop_11", "Yo (11)", "Propositions"], ["prop_12", "Boxcars (12)", "Propositions"],
	["horn", "Horn", "Propositions"], ["c_and_e", "C & E", "Propositions"],
]
const EVENTS := [
	["seven_out", "a seven-out"], ["point_made", "the point made"], ["point_set", "a point set"],
	["natural", "a come-out 7 or 11"], ["craps", "a come-out 2, 3 or 12"], ["seven", "any 7"],
	["hard_4", "a hard 4"], ["hard_6", "a hard 6"], ["hard_8", "a hard 8"], ["hard_10", "a hard 10"],
	["total_2", "a 2"], ["total_3", "a 3"], ["total_4", "a 4"], ["total_5", "a 5"], ["total_6", "a 6"],
	["total_8", "an 8"], ["total_9", "a 9"], ["total_10", "a 10"], ["total_11", "an 11"], ["total_12", "a 12"],
]
## Numbers a craps system can test besides the shared ones.
const VARIABLES := {"come_points": "come bets on numbers", "point": "the point (0 = off)"}
const ODDS_KEYS := {"pass": "pass_odds", "dont_pass": "dont_pass_odds"}

var wallet: SystemRunner.Wallet
var engine: CrapsEngine
## Set by tests to force known dice; consumed before the generator.
var scripted: Array = []
var _stakes := {}
## The bets and odds this table has put up, so each round only looks at
## those rather than the whole felt.
var _placed := {}


static func positions() -> Array:
	var out: Array = []
	for entry in POSITIONS:
		out.append({"key": entry[0], "label": entry[1], "group": entry[2]})
	return out


static func events() -> Array:
	return EVENTS


func reset(new_wallet: SystemRunner.Wallet) -> void:
	wallet = new_wallet
	engine = CrapsEngine.new()
	engine.quiet = true
	engine.board.wallet = wallet
	var meta := CrapsEngine.bet_meta()
	for key in meta:
		engine.board.add(key, null, meta[key])
	_placed = {}


## Chips riding on the table, still the player's until they lose.
func on_table() -> int:
	return engine.board.total()


## Puts the round's bets up: {position: dollars} and {line bet: odds
## multiple}. False if the wallet can't cover them.
func place(stakes: Dictionary, odds: Dictionary) -> bool:
	_stakes = stakes
	var board := engine.board
	# Take down what the layout no longer wants, where the table allows.
	for key in _placed.keys():
		if board.amount(key) <= 0:
			_placed.erase(key)
			continue
		var wanted: bool = stakes.has(key) or (String(key).contains("odds") and odds.has(_placed[key]))
		if not wanted and not engine.is_contract(key):
			board.refund(key)
			_placed.erase(key)

	for key in stakes:
		var want := int(stakes[key])
		var have := board.amount(key)
		if not _in_season(key):
			continue
		if have < want:
			if not board.place(key, want - have):
				return false
			_placed[key] = key
		elif have > want and not engine.is_contract(key):
			# Bring a bet that stayed up after a win back to the layout's size.
			board.take(key)
			board.move_in(key, want)
			board.deposit(have - want)

	for key in odds:
		for odds_key in _odds_keys_for(key):
			var cap := engine.max_odds(odds_key)
			if cap <= 0:
				continue
			var mult := int(odds[key])
			var flat := board.amount(String(board.meta(odds_key).flat))
			var want := cap if mult <= 0 else mini(cap, flat * mult)
			var short := want - board.amount(odds_key)
			if short > 0:
				if not board.place(odds_key, short):
					return false
				# Remembered against the bet it rides on, so dropping that
				# bet's odds from the layout takes them down.
				_placed[odds_key] = key
	return true


func play(rng: RandomNumberGenerator) -> Dictionary:
	var dice: Array = scripted.pop_front() if not scripted.is_empty() \
		else [rng.randi_range(1, 6), rng.randi_range(1, 6)]
	var d1 := int(dice[0])
	var d2 := int(dice[1])
	var total := d1 + d2
	var point_before := engine.point
	engine.resolve_roll(d1, d2, [])

	var events := {"total_%d" % total: true}
	if d1 == d2:
		events["hard_%d" % total] = true
	# String keys throughout, matching the event names rules ask about.
	if total == 7:
		events["seven"] = true
	if point_before == 0:
		if total in [7, 11]:
			events["natural"] = true
		elif total in [2, 3, 12]:
			events["craps"] = true
		else:
			events["point_set"] = true
	elif total == point_before:
		events["point_made"] = true
	elif total == 7:
		events["seven_out"] = true

	var staked := 0
	var cost := 0.0
	for key in engine.resolved:
		var stake := int(engine.resolved[key])
		staked += stake
		cost += stake * CrapsEngine.edge(key)

	var label := "%d (%d+%d)" % [total, d1, d2]
	if engine.point != 0:
		label += ", point %d" % engine.point
	return {
		"dice": [d1, d2], "total": total, "label": label, "events": events,
		"results": engine.results.duplicate(), "stakes": _stakes,
		"staked": staked, "cost": cost,
	}


## Whether a bet won this roll. "Come" and "don't come" count a win on any
## of their travelled points as well as on the bar.
func hit(key: String, outcome: Dictionary) -> bool:
	return _result(key, outcome) == "won"


func lost(key: String, outcome: Dictionary) -> bool:
	return _result(key, outcome) == "lost"


func has_event(event: String, outcome: Dictionary) -> bool:
	return outcome.events.has(event)


func variable(name: String) -> float:
	match name:
		"point":
			return float(engine.point)
		"come_points":
			var count := 0
			for number in CrapsEngine.POINTS:
				if engine.board.amount("come_%d" % number) > 0:
					count += 1
			return float(count)
	return 0.0


func _result(key: String, outcome: Dictionary) -> String:
	var results: Dictionary = outcome.results
	if results.has(key):
		return results[key]
	if key == "come" or key == "dont_come":
		var any := ""
		for number in CrapsEngine.POINTS:
			var result: String = results.get("%s_%d" % [key, number], "")
			if result == "won":
				return "won"
			if result == "lost":
				any = "lost"
		return any
	return ""


## Whether the table takes this bet right now.
func _in_season(key: String) -> bool:
	match key:
		"pass", "dont_pass":
			return engine.point == 0
		"come", "dont_come":
			return engine.point != 0
	return true


func _odds_keys_for(key: String) -> Array:
	if ODDS_KEYS.has(key):
		return [ODDS_KEYS[key]]
	var out: Array = []
	if key == "come" or key == "dont_come":
		var prefix := "come_odds_" if key == "come" else "dont_come_odds_"
		for number in CrapsEngine.POINTS:
			out.append(prefix + str(number))
	return out

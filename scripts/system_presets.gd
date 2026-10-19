class_name SystemPresets
extends RefCounted
## The well-known betting systems, written in the Systems Lab's own rules so
## every one can be opened, read as a flowchart, and edited. None of them
## beats the house edge — that's rather the point of testing them — but they
## are faithful versions of what people actually play.


static func for_game(game: String) -> Array:
	if game == "craps":
		return []
	return roulette()


static func roulette() -> Array:
	return [
		_flat(), _martingale(), _paroli(), _dalembert(), _fibonacci(),
		_two_dozens(), _wait_for_reds(), _triple_cover(), _repeat_until_win(),
	]


# --- Roulette ----------------------------------------------------------------------------

static func _flat() -> Dictionary:
	return _system("Flat bet", "The control group: the same bet on red, every spin.",
		[_step(0, "Bet red", {"red": 1})])


static func _martingale() -> Dictionary:
	return _system("Martingale",
		"Double the bet after every loss, so one win recovers everything and makes a unit. Until the table maximum or the bankroll runs out.",
		[_step(0, "Bet red", {"red": 1},
			[_rule(_round("lost"), [_unit("multiply", 2)])],
			[_unit("reset")])])


static func _paroli() -> Dictionary:
	return _system("Paroli (reverse Martingale)",
		"Double after every win and take the profit after three in a row; reset after a loss.",
		[_step(0, "Bet red", {"red": 1},
			[
				_rule(_all([_round("won"), _compare("win_streak", ">=", 3)]), [_unit("reset")]),
				_rule(_round("won"), [_unit("multiply", 2)]),
			],
			[_unit("reset")])])


static func _dalembert() -> Dictionary:
	return _system("D'Alembert",
		"Raise the bet a unit after a loss and lower it a unit after a win.",
		[_step(0, "Bet red", {"red": 1},
			[
				_rule(_round("won"), [_unit("add", -1)]),
				_rule(_round("lost"), [_unit("add", 1)]),
			])])


## A ladder of steps, one per Fibonacci number: a loss climbs one rung, a
## win drops two.
static func _fibonacci() -> Dictionary:
	var ladder := [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
	var steps: Array = []
	for i in ladder.size():
		var up := mini(i + 1, ladder.size() - 1)
		var down := maxi(i - 2, 0)
		steps.append(_step(i, "Rung %d (%du)" % [i + 1, ladder[i]], {"red": ladder[i]},
			[_rule(_round("won"), [_goto(down)])],
			[_goto(up)]))
	return _system("Fibonacci",
		"Bet the Fibonacci sequence: one rung up after a loss, two rungs down after a win.", steps)


static func _two_dozens() -> Dictionary:
	return _system("Two dozens",
		"Cover two of the three dozens: wins two spins in three, and loses double when it doesn't.",
		[_step(0, "Two dozens", {"dozen_0": 1, "dozen_1": 1})])


static func _wait_for_reds() -> Dictionary:
	return _system("Wait for 5 reds",
		"Watch until red comes up five times running, then Martingale on black — as if the wheel remembered. Gives up after six losses.",
		[
			_step(0, "Watch", {},
				[_rule(_pattern("red", "hit", 5), [_unit("reset"), _goto(1)])]),
			_step(1, "Bet black", {"black": 1},
				[
					_rule(_round("won"), [_unit("reset"), _goto(0)]),
					_rule(_compare("loss_streak", ">=", 6), [_unit("reset"), _goto(0)]),
				],
				[_unit("multiply", 2)]),
		])


static func _triple_cover() -> Dictionary:
	return _system("Triple cover",
		"17, the 2nd dozen and black together. All three land on 17: walk away. None land: double. Exactly one: add a unit.",
		[_step(0, "17 + 2nd 12 + black", {"straight_17": 1, "dozen_1": 1, "black": 1},
			[
				_rule(_group("all", ["straight_17", "dozen_1", "black"]), [_unit("reset"), _stop()]),
				_rule(_group("none", ["straight_17", "dozen_1", "black"]), [_unit("multiply", 2)]),
				_rule(_group("exactly", ["straight_17", "dozen_1", "black"], 1), [_unit("add", 1)]),
			],
			[_unit("reset")])])


static func _repeat_until_win() -> Dictionary:
	var system := _system("Repeat until win",
		"The same bet, spun until a spin pays more than it cost — the table's Repeat Until Win, over many sessions.",
		[_step(0, "Repeat", {"red": 1}, [_rule(_round("won"), [_stop()])])])
	system.settings.rounds = 250
	return system


# --- Building blocks ---------------------------------------------------------------------

static func _system(name: String, notes: String, steps: Array, game: String = "roulette") -> Dictionary:
	var system := SystemModel.new_system(game, name)
	system.notes = notes
	system.steps = steps
	system.start = 0
	return system


static func _step(id: int, name: String, layout: Dictionary, rules: Array = [], otherwise: Array = []) -> Dictionary:
	var entry := SystemModel.new_step(id, name, layout)
	entry.rules = rules
	entry.otherwise = otherwise
	return entry


static func _rule(cond: Dictionary, actions: Array) -> Dictionary:
	return {"when": cond, "then": actions}


static func _round(result: String) -> Dictionary:
	return {"type": "round", "result": result}


static func _compare(variable: String, op: String, value: float) -> Dictionary:
	return {"type": "compare", "var": variable, "op": op, "value": value}


static func _pattern(what: String, mode: String, n: int) -> Dictionary:
	return {"type": "pattern", "what": what, "mode": mode, "n": n}


static func _group(mode: String, keys: Array, n: int = 1) -> Dictionary:
	return {"type": "group", "mode": mode, "positions": keys, "n": n}


static func _all(items: Array) -> Dictionary:
	return {"type": "and", "items": items}


static func _unit(op: String, value: float = 1) -> Dictionary:
	return {"type": "unit", "op": op, "value": value}


static func _goto(id: int) -> Dictionary:
	return {"type": "goto", "step": id}


static func _stop() -> Dictionary:
	return {"type": "stop"}

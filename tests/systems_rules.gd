extends CasinoTest
## The Systems Lab engine: that the lab pays exactly what the table pays,
## that rules run as the editor describes them, that sessions stop when they
## should, and that over enough spins every system loses the house edge.

const RED := 1
const RED_2 := 3
const BLACK := 2
const BLACK_2 := 4


func run() -> void:
	await _test_bets_match_the_table()
	_test_martingale_sequence()
	_test_first_match_and_otherwise()
	_test_group_modes()
	_test_pattern_and_steps()
	_test_sit_out()
	_test_stops()
	_test_table_cap()
	_test_counters()
	_test_reproducible()
	_test_converges_to_the_edge()
	_test_presets()
	_test_validation()
	_test_sharing()
	_test_speed()


func _system(layout: Dictionary, rules: Array = [], otherwise: Array = [], settings: Dictionary = {}) -> Dictionary:
	var system := SystemModel.new_system("roulette", "test")
	system.steps[0].layout = layout
	system.steps[0].rules = rules
	system.steps[0].otherwise = otherwise
	system.settings.merge(settings, true)
	return system


func _test_bets_match_the_table() -> void:
	var t: Control = load("res://scenes/roulette.tscn").instantiate()
	add_child(t)
	await frames()
	var table_keys: Array = t.board.bets.keys()
	check(table_keys.size() == RouletteBets.keys().size(), "the lab should know every bet on the table")
	for key in table_keys:
		check(RouletteBets.has(key), "the table's %s should be a lab bet" % key)
		check(t.board.meta(key).numbers == RouletteBets.numbers(key), "%s covers different numbers" % key)
		check(int(t.board.meta(key).payout) == RouletteBets.payout(key), "%s pays differently" % key)
	t.queue_free()
	await frames()
	note("the lab and the table cover and pay every one of %d bets identically" % table_keys.size())


func _test_martingale_sequence() -> void:
	var martingale: Dictionary = SystemPresets.roulette()[1]
	var result := SystemRunner.run_session(martingale, 1, true, [BLACK, BLACK_2, RED, BLACK])
	var bets: Array = []
	var banks: Array = []
	for row in result.trace.slice(0, 4):
		bets.append(row.bets)
		banks.append(int(row.bankroll))
	check(bets == ["Red $5", "Red $10", "Red $20", "Red $5"], "Martingale doubles then resets, got %s" % [bets])
	check(banks == [995, 985, 1005, 1000], "bankroll should go 995, 985, 1005, 1000, got %s" % [banks])
	note("Martingale: $5, $10, $20 — a win — back to $5, one unit up")


func _test_first_match_and_otherwise() -> void:
	var system := _system({"red": 1}, [
		{"when": {"type": "wins", "pos": "red"}, "then": [{"type": "unit", "op": "set", "value": 3}]},
		{"when": {"type": "wins", "pos": "odd"}, "then": [{"type": "unit", "op": "set", "value": 5}]},
	], [{"type": "unit", "op": "set", "value": 2}])
	# 1 is red and odd: the first rule wins. 9 is red and odd too. 2 is
	# black and even: nothing matches, so OTHERWISE. 13 is black and odd.
	var result := SystemRunner.run_session(system, 1, true, [RED, BLACK, 13, RED])
	var fired: Array = []
	var bets: Array = []
	for row in result.trace.slice(0, 4):
		fired.append(row.rule)
		bets.append(row.bets)
	check(fired == ["Rule 1", "Otherwise", "Rule 2", "Rule 1"], "first match wins, else OTHERWISE: %s" % [fired])
	check(bets == ["Red $5", "Red $15", "Red $10", "Red $25"], "each rule's unit should apply next round: %s" % [bets])
	note("rules run top to bottom, the first match only, and OTHERWISE when none match")


func _test_group_modes() -> void:
	var trio := ["straight_17", "dozen_1", "black"]
	var cases := [
		[17, {"all": true, "any": true, "none": false, "exactly": 3, "at_least_2": true}],
		[20, {"all": false, "any": true, "none": false, "exactly": 2, "at_least_2": true}],
		[2, {"all": false, "any": true, "none": false, "exactly": 1, "at_least_2": false}],
		[1, {"all": false, "any": false, "none": true, "exactly": 0, "at_least_2": false}],
	]
	var adapter := RouletteSim.new()
	var state := {"history": []}
	for c in cases:
		var outcome := {"number": c[0], "stakes": {}}
		var want: Dictionary = c[1]
		for mode in ["all", "any", "none"]:
			var got := SystemRunner._holds({"type": "group", "mode": mode, "positions": trio}, state, adapter, outcome, 0)
			check(got == want[mode], "%d: %s of %s should be %s" % [c[0], mode, trio, want[mode]])
		for n in 4:
			var got := SystemRunner._holds({"type": "group", "mode": "exactly", "n": n, "positions": trio}, state, adapter, outcome, 0)
			check(got == (n == int(want.exactly)), "%d: exactly %d should be %s" % [c[0], n, n == int(want.exactly)])
		var two := SystemRunner._holds({"type": "group", "mode": "at_least", "n": 2, "positions": trio}, state, adapter, outcome, 0)
		check(two == want.at_least_2, "%d: at least 2 should be %s" % [c[0], want.at_least_2])

	var preset: Dictionary = SystemPresets.roulette()[7]
	var result := SystemRunner.run_session(preset, 1, true, [1, 2, 17])
	var fired: Array = []
	for row in result.trace:
		fired.append(row.rule)
	check(fired == ["Rule 2", "Rule 3", "Rule 1"], "Triple cover: none, exactly one, then all three: %s" % [fired])
	check(result.reason == "stopped", "all three landing should stop the session")
	note("several bets together: all, any, none, exactly N and at least N")


func _test_pattern_and_steps() -> void:
	var preset: Dictionary = SystemPresets.roulette()[6]
	# Five reds, then the first black bet loses to red and the doubled one
	# wins on black.
	var spins := [RED, RED_2, RED, RED_2, RED, RED, BLACK]
	var result := SystemRunner.run_session(preset, 1, true, spins)
	var steps: Array = []
	var bets: Array = []
	for row in result.trace.slice(0, 7):
		steps.append(row.step)
		bets.append(row.bets)
	check(steps == ["Watch", "Watch", "Watch", "Watch", "Watch", "Bet black", "Bet black"],
		"five reds should move to the betting step: %s" % [steps])
	check(bets.slice(0, 5) == ["no bets", "no bets", "no bets", "no bets", "no bets"], "watching places no bets")
	check(bets[5] == "Black $5" and bets[6] == "Black $10", "then Martingale on black: %s" % [bets.slice(5)])
	note("a run of results moves the flowchart from Watch to Bet, and the bets follow the step")


func _test_sit_out() -> void:
	var system := _system({"red": 1}, [
		{"when": {"type": "round", "result": "lost"}, "then": [{"type": "sit_out", "rounds": 2}]},
	])
	var result := SystemRunner.run_session(system, 1, true, [BLACK, RED, RED, RED])
	var bets: Array = []
	for row in result.trace.slice(0, 4):
		bets.append(row.bets)
	check(bets == ["Red $5", "sitting out", "sitting out", "Red $5"], "a loss sits out two spins: %s" % [bets])
	note("sitting out skips exactly the rounds asked")


func _test_stops() -> void:
	var flat := _system({"red": 1}, [], [], {"unit": 10, "take_profit": 20})
	var result := SystemRunner.run_session(flat, 1, true, [RED, RED, RED])
	check(result.reason == "take_profit" and result.rounds == 2, "take-profit +20 at $10 a spin stops after two wins")

	flat = _system({"red": 1}, [], [], {"unit": 10, "stop_loss": 30})
	result = SystemRunner.run_session(flat, 1, true, [BLACK, BLACK, BLACK, RED])
	check(result.reason == "stop_loss" and result.rounds == 3, "stop-loss 30 at $10 a spin stops after three losses")

	var martingale: Dictionary = SystemPresets.roulette()[1]
	martingale.settings.bankroll = 30
	martingale.settings.unit = 10
	result = SystemRunner.run_session(martingale, 1, true, [BLACK, BLACK, BLACK])
	check(result.reason == "broke" and result.busted and int(result.final) == 0,
		"$30 can't cover a third Martingale bet of $40: %s with $%d" % [result.reason, result.final])

	flat = _system({"red": 1}, [], [], {"rounds": 37})
	result = SystemRunner.run_session(flat, 1, false)
	check(result.reason == "rounds" and result.rounds == 37, "a session plays exactly its rounds")
	note("sessions stop at take-profit, stop-loss, going broke, or the round limit")


func _test_table_cap() -> void:
	var martingale: Dictionary = SystemPresets.roulette()[1]
	martingale.settings.table_max = 40
	martingale.settings.rounds = 6
	var result := SystemRunner.run_session(martingale, 1, true, [BLACK, BLACK, BLACK, BLACK, BLACK, RED])
	var bets: Array = []
	for row in result.trace.slice(0, 6):
		bets.append(row.bets)
	check(bets == ["Red $5", "Red $10", "Red $20", "Red $40", "Red $40", "Red $40"],
		"the table maximum caps the doubling: %s" % [bets])
	check(int(result.capped) == 2, "two bets were capped, counted %d" % int(result.capped))
	check(int(result.trace[5].bankroll) == 1000 - 5 - 10 - 20 - 40 - 40 + 40,
		"after the cap one win no longer recovers the losses")
	note("the table maximum caps a progression — which is what breaks Martingale")


func _test_counters() -> void:
	var system := SystemModel.new_system("roulette", "counter")
	system.steps = [
		{"id": 0, "name": "Count losses", "layout": {"red": 1}, "rules": [
			{"when": {"type": "compare", "var": "a", "op": ">=", "value": 2}, "then": [{"type": "goto", "step": 1}]},
			{"when": {"type": "round", "result": "lost"}, "then": [{"type": "counter", "which": "a", "op": "add", "value": 1}]},
		], "otherwise": []},
		{"id": 1, "name": "Switch", "layout": {"black": 2}, "rules": [], "otherwise": []},
	]
	var result := SystemRunner.run_session(system, 1, true, [BLACK, BLACK, RED, RED])
	var steps: Array = []
	for row in result.trace.slice(0, 4):
		steps.append(row.step)
	check(steps == ["Count losses", "Count losses", "Count losses", "Switch"],
		"the counter should reach 2 and switch steps: %s" % [steps])
	check(result.trace[3].bets == "Black $10", "the new step brings its own layout")
	note("counters count, and a comparison on them can move the flowchart")


func _test_reproducible() -> void:
	var martingale: Dictionary = SystemPresets.roulette()[1]
	var a := SystemRunner.run_session(martingale, 99, false)
	var b := SystemRunner.run_session(martingale, 99, false)
	var c := SystemRunner.run_session(martingale, 100, false)
	check(a == b, "the same seed should replay the same session")
	check(a != c, "a different seed should play a different session")
	note("a seed replays a session exactly")


## Flat-betting red over ~370,000 spins: the result should be the house edge.
func _test_converges_to_the_edge() -> void:
	var before := Bank.balance
	var flat := _system({"red": 1}, [], [], {"rounds": 3700, "bankroll": 100000, "unit": 1})
	var summary := SystemRunner.monte_carlo(flat, 100, 7)
	var ratio := float(summary.total_net) / float(summary.total_staked)
	check(absf(ratio + 1.0 / 37.0) < 0.006, "flat red should lose ~2.70%% of the money staked, lost %.2f%%" % (-100.0 * ratio))
	check(absf(float(summary.mean_expected) * 100 / float(summary.mean_staked) + 100.0 / 37.0) < 0.0001,
		"the expected loss should be exactly 1/37 of the stake")
	check(Bank.balance == before, "running systems must never touch the real bankroll")
	note("370,000 spins of flat red lose %.2f%% of the stake; the edge is 2.70%%" % (-100.0 * ratio))


func _test_presets() -> void:
	for preset in SystemPresets.roulette():
		var problems := SystemModel.validate(preset)
		check(problems.is_empty(), "%s: %s" % [preset.name, problems])
		check(String(preset.notes) != "", "%s should say what it does" % preset.name)
		var result := SystemRunner.run_session(preset, 5, true)
		check(int(result.rounds) > 0, "%s should play" % preset.name)
	check(SystemModel.reachable(SystemPresets.roulette()[4]).size() == 10, "every Fibonacci rung is reachable")
	note("all %d roulette presets validate and run" % SystemPresets.roulette().size())


func _test_validation() -> void:
	var system := SystemModel.new_system("roulette", "broken")
	system.steps = [
		{"id": 0, "name": "Start", "layout": {"red": 1}, "rules": [
			{"when": {"type": "always"}, "then": [{"type": "goto", "step": 7}, {"type": "press", "pos": "red"}]},
		], "otherwise": []},
		{"id": 1, "name": "Island", "layout": {"black": 1}, "rules": [], "otherwise": []},
		{"id": 2, "name": "Idle", "layout": {}, "rules": [], "otherwise": []},
	]
	system.steps[0].otherwise = [{"type": "goto", "step": 2}]
	var problems := " ".join(SystemModel.validate(system))
	check("no longer exists" in problems, "a goto to a deleted step should be caught")
	check("craps-only" in problems, "a craps action in a roulette system should be caught")
	check("Nothing ever goes to Island" in problems, "an unreachable step should be caught")
	check("Idle never bets and never moves on" in problems, "a dead-end watching step should be caught")
	note("validation catches missing steps, unreachable steps, dead ends and wrong-game actions")


func _test_sharing() -> void:
	for preset in SystemPresets.roulette():
		var code := SystemModel.export_code(preset)
		check(code.begins_with(SystemModel.CODE_PREFIX), "an export should carry its prefix")
		var back := SystemModel.import_code(code)
		check(not back.is_empty(), "%s should import" % preset.name)
		check(SystemRunner.run_session(back, 3, false) == SystemRunner.run_session(preset, 3, false),
			"%s should play identically after a round trip" % preset.name)
	check(SystemModel.import_code("hello").is_empty(), "random text isn't a system")
	check(SystemModel.import_code(SystemModel.CODE_PREFIX + "!!!").is_empty(), "a damaged code isn't a system")
	note("systems export and import as a line of text and play identically")


func _test_speed() -> void:
	var martingale: Dictionary = SystemPresets.roulette()[1]
	martingale.settings.rounds = 10000
	martingale.settings.bankroll = 10000000
	martingale.settings.table_max = 1000000
	var started := Time.get_ticks_msec()
	var result := SystemRunner.run_session(martingale, 11, true)
	var took := Time.get_ticks_msec() - started
	check(int(result.rounds) == 10000, "the long session should play all 10,000 rounds")
	check(took < 5000, "10,000 Martingale rounds should take a few seconds at most, took %d ms" % took)
	note("10,000 rounds of Martingale in %d ms" % took)

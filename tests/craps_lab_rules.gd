extends CasinoTest
## The Craps Systems Lab: that a system's bets go down only when the table
## takes them, that contracts are never pulled, that odds stay inside the
## caps, that every event and win is reported as it happened, and that the
## house edge it predicts is each bet's own.


func run() -> void:
	_test_seasons_and_contracts()
	_test_odds()
	_test_come_bets()
	_test_events()
	_test_iron_cross()
	_test_molly()
	_test_presets()
	_test_edge()
	await _test_lab_screen()
	await _test_table_button()


func _sim() -> CrapsSim:
	var wallet := SystemRunner.Wallet.new()
	wallet.balance = 10000
	var sim := CrapsSim.new()
	sim.reset(wallet)
	return sim


func _roll(sim: CrapsSim, d1: int, d2: int) -> Dictionary:
	sim.scripted = [[d1, d2]]
	return sim.play(RandomNumberGenerator.new())


func _test_seasons_and_contracts() -> void:
	var sim := _sim()
	check(sim.place({"pass": 10, "come": 10}, {}), "placing should succeed")
	check(sim.engine.board.amount("pass") == 10, "the pass line goes down on a come-out")
	check(sim.engine.board.amount("come") == 0, "a come bet waits for a point")
	_roll(sim, 2, 4)
	check(sim.engine.point == 6, "a 6 sets the point")
	sim.place({"pass": 40}, {})
	check(sim.engine.board.amount("pass") == 10, "the pass line can't be raised once the point is on")
	sim.place({}, {})
	check(sim.engine.board.amount("pass") == 10, "and it can't be taken down: it's a contract")
	sim.place({"come": 5, "place_8": 12}, {})
	check(sim.engine.board.amount("come") == 5 and sim.engine.board.amount("place_8") == 12,
		"come and place bets go up once the point is on")
	sim.place({"come": 5}, {})
	check(sim.engine.board.amount("place_8") == 0, "a place bet the layout drops comes down")
	note("bets go down only in season, and contracts are never pulled or raised")


func _test_odds() -> void:
	var sim := _sim()
	sim.place({"pass": 10}, {"pass": 0})
	check(sim.engine.board.amount("pass_odds") == 0, "no odds before there's a point")
	_roll(sim, 4, 4)
	sim.place({"pass": 10}, {"pass": 0})
	check(sim.engine.board.amount("pass_odds") == 50, "max odds behind a $10 line on the 8 is $50 (5x)")
	var lay := _sim()
	lay.place({"dont_pass": 10}, {"dont_pass": 2})
	_roll(lay, 3, 1)
	lay.place({"dont_pass": 10}, {"dont_pass": 2})
	check(lay.engine.board.amount("dont_pass_odds") == 20, "2x lay odds on a $10 don't pass is $20")
	lay.place({"dont_pass": 10}, {})
	check(lay.engine.board.amount("dont_pass_odds") == 0, "odds the layout drops come down")
	note("odds go behind the line at the multiple asked, within the 3-4-5x caps")


func _test_come_bets() -> void:
	var sim := _sim()
	sim.place({"pass": 5}, {})
	_roll(sim, 3, 3)
	sim.place({"pass": 5, "come": 5}, {"come": 0})
	_roll(sim, 2, 2)
	check(sim.engine.board.amount("come_4") == 5, "the come bet travels to the 4")
	check(sim.variable("come_points") == 1.0, "one come bet is working")
	sim.place({"pass": 5, "come": 5}, {"come": 0})
	check(sim.engine.board.amount("come_odds_4") == 15, "max odds behind a come 4 is 3x, $15")
	sim.place({"pass": 5}, {})
	check(sim.engine.board.amount("come_4") == 5, "a travelled come bet is a contract and stays")
	var outcome := _roll(sim, 1, 3)
	check(sim.hit("come", outcome), "a come point winning counts as the come bet winning")
	check(sim.variable("come_points") == 0.0, "and it comes down with its pay")
	note("come bets travel, take odds, stay as contracts, and their wins count as come wins")


func _test_events() -> void:
	var cases := [
		[[3, 4], 0, ["natural", "seven", "total_7"]],
		[[1, 1], 0, ["craps", "hard_2", "total_2"]],
		[[2, 2], 0, ["point_set", "hard_4", "total_4"]],
		[[1, 3], 4, ["point_made", "total_4"]],
		[[6, 1], 9, ["seven_out", "seven", "total_7"]],
		[[5, 5], 6, ["hard_10", "total_10"]],
	]
	for c in cases:
		var sim := _sim()
		sim.engine.point = c[1]
		var outcome := _roll(sim, c[0][0], c[0][1])
		var got: Array = outcome.events.keys()
		got.sort()
		var want: Array = c[2]
		want.sort()
		check(got == want, "%s on point %d should be %s, got %s" % [c[0], c[1], want, got])
	note("naturals, craps, points set and made, seven-outs, hard ways and totals are reported")


func _test_iron_cross() -> void:
	var preset: Dictionary = SystemPresets.craps()[2]
	var result := SystemRunner.run_session(preset, 1, true, [[3, 1], [2, 3], [4, 4], [3, 4], [1, 1]])
	var steps: Array = []
	for row in result.trace.slice(0, 5):
		steps.append(row.step)
	check(steps == ["Wait for a point", "Iron Cross", "Iron Cross", "Iron Cross", "Wait for a point"],
		"Iron Cross waits for a point, then covers until the seven-out: %s" % [steps])
	check(result.trace[1].bets == "Place 5 $5, Place 6 $6, Place 8 $6, Field $5",
		"the cross is $5, $6, $6 and the $5 field: %s" % result.trace[1].bets)
	check(int(result.trace[3].net) == -22, "the seven-out takes all $22, lost %d" % int(result.trace[3].net))
	note("Iron Cross: waits for a point, covers 5-6-8 and the field, loses the lot to a seven")


func _test_molly() -> void:
	var preset: Dictionary = SystemPresets.craps()[3]
	# Point 6, then come bets travel to the 4 and the 5: two working.
	var result := SystemRunner.run_session(preset, 1, true, [[3, 3], [2, 2], [4, 1], [2, 1]])
	check("Come" in String(result.trace[1].bets) and "Come" in String(result.trace[2].bets),
		"come bets go up while fewer than two are working")
	check(not "Come" in String(result.trace[3].bets), "with two come points working, no third: %s" % result.trace[3].bets)
	note("3-Point Molly keeps exactly three numbers working")


func _test_presets() -> void:
	for preset in SystemPresets.craps():
		var problems := SystemModel.validate(preset)
		check(problems.is_empty(), "%s: %s" % [preset.name, problems])
		var result := SystemRunner.run_session(preset, 9, true)
		check(int(result.rounds) > 0, "%s should play" % preset.name)
		check(int(result.final) == int(result.net) + int(preset.settings.bankroll), "%s should balance its books" % preset.name)
	note("all %d craps presets validate, play and balance" % SystemPresets.craps().size())


func _test_edge() -> void:
	var before := Bank.balance
	var pass_only: Dictionary = SystemPresets.craps()[5].duplicate(true)
	pass_only.name = "Flat pass"
	pass_only.steps[0].rules = []
	pass_only.settings.rounds = 1000
	pass_only.settings.bankroll = 100000
	var started := Time.get_ticks_msec()
	var summary := SystemRunner.monte_carlo(pass_only, 60, 3)
	var took := Time.get_ticks_msec() - started
	var expected_ratio := float(summary.mean_expected) / float(summary.mean_staked)
	check(absf(expected_ratio + 0.0141) < 0.00001, "the pass line's expected loss is 1.41%% of what settles, got %.4f%%" % (-100 * expected_ratio))
	var actual := float(summary.total_net) / float(summary.total_staked)
	check(absf(actual + 0.0141) < 0.02, "flat pass should lose about 1.41%%, lost %.2f%%" % (-100 * actual))
	check(Bank.balance == before, "the lab never touches the real bankroll")
	note("60,000 rolls of flat pass: expected −1.41%%, actual %.2f%% (%d ms)" % [100 * actual, took])


func _test_lab_screen() -> void:
	Store.use_test_backend()
	Store.buy("craps_lab")
	SystemLab.open_game = "craps"
	SystemLab.open_layout = {"pass": 10, "pass_odds": 20, "place_6": 12}
	var lab: Control = load("res://scenes/system_lab.tscn").instantiate()
	add_child(lab)
	await frames()
	check(lab.system.game == "craps", "the lab should open on craps")
	check(lab.system.steps[0].layout == {"pass": 5, "place_6": 6}, "odds aren't a layout bet: %s" % [lab.system.steps[0].layout])
	lab.load_system(SystemPresets.craps()[2])
	await frames()
	check(lab.flowchart._boxes.size() == 2, "Iron Cross draws as two boxes")
	var editor := RuleEditor.edit_action(lab, lab.system, {}, func(_a: Dictionary) -> void: pass)
	await frames()
	var picker: OptionButton = editor.content.get_child(1).get_child(1)
	check(picker.item_count == SystemModel.ACTIONS.size(), "craps offers every action, odds and presses included")
	editor.close()
	lab.run_one()
	check("house edge" in lab.results_label.text, "craps results are read against the edge too")
	lab.queue_free()
	await frames()
	note("the lab opens on craps with the table's bets, and offers the craps actions")


func _test_table_button() -> void:
	var t: Control = load("res://scenes/craps.tscn").instantiate()
	add_child(t)
	await frames()
	Bank.reset()
	t.point = 0
	t.board.clear_all()
	t.board.place("pass", 10)
	t.point = 6
	t._on_lab_pressed()
	check("Finish the hand" in t.message_label.text, "the lab won't strand a contract bet")
	check(t.board.amount("pass") == 10, "the pass line stays where it is")
	t.board.clear_all()
	t.point = 0
	t.queue_free()
	await frames()
	Bank.reset()
	Store.use_test_backend()
	note("the table's Systems Lab button won't forfeit a contract bet")

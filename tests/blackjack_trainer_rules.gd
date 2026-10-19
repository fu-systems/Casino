extends CasinoTest
## The blackjack charts and trainers. The charts and the quiz never hold an
## answer of their own — they ask BlackjackStrategy — so these checks are
## about that plumbing: right rows, right cells, right hands, and spot checks
## against the published chart so a plumbing slip can't hide.

const SAMPLES := 3000


func run() -> void:
	_test_chart_spot_checks()
	_test_chart_grouped_rows()
	_test_count_rows()
	await _test_chart_widget()
	_test_quiz_answers()
	_test_count_mode_hits_indices()
	_test_question_for_every_key()
	_test_weak_keys()
	await _test_table_buttons()
	await _test_strategy_drill()


func _code(table: String, row: String, up: int) -> String:
	for entry in StrategyChart.rows_for(table):
		if entry[0] == row:
			return StrategyChart.code_for(table, entry[2], up)
	fail("no %s row '%s'" % [table, row])
	return ""


## Cells straight off a standard S17, double-after-split chart.
func _test_chart_spot_checks() -> void:
	var expected := [
		["hard", "16", 10, "H"], ["hard", "16", 6, "S"], ["hard", "12", 4, "S"],
		["hard", "12", 3, "H"], ["hard", "11", 6, "D"], ["hard", "11", 11, "H"],
		["hard", "10", 10, "H"], ["hard", "9", 3, "D"], ["hard", "9", 2, "H"],
		["hard", "5-8", 6, "H"], ["hard", "17+", 11, "S"],
		["soft", "A,7", 9, "H"], ["soft", "A,7", 3, "Ds"], ["soft", "A,7", 2, "S"],
		["soft", "A,6", 3, "D"], ["soft", "A,6", 7, "H"], ["soft", "A,2", 5, "D"],
		["soft", "A,8", 6, "S"],
		["pair", "A,A", 11, "P"], ["pair", "10,10", 6, "S"], ["pair", "9,9", 7, "S"],
		["pair", "9,9", 8, "P"], ["pair", "8,8", 10, "P"], ["pair", "5,5", 10, "H"],
		["pair", "5,5", 6, "D"], ["pair", "4,4", 5, "P"], ["pair", "4,4", 4, "H"],
		["pair", "2,2", 7, "P"], ["pair", "2,2", 8, "H"],
	]
	for e in expected:
		var got := _code(e[0], e[1], e[2])
		check(got == e[3], "%s %s v %s should be %s, chart says %s" % [e[0], e[1], e[2], e[3], got])
	note("chart cells match the published S17/DAS chart at %d spot checks" % expected.size())


## The chart folds 5-8 into one row and 17+ into another; every total in
## each must really play the same.
func _test_chart_grouped_rows() -> void:
	var groups := {"5-8": [["2", "3"], ["2", "4"], ["2", "5"], ["3", "5"]],
		"17+": [["10", "7"], ["10", "8"], ["10", "9"]]}
	for label in groups:
		for ranks in groups[label]:
			for up in StrategyChart.UPCARDS:
				var got := StrategyChart.code_for("hard", ranks, up)
				check(got == _code("hard", label, up),
					"%s v %d should play like the %s row" % [ranks, up, label])
	note("every total folded into the 5-8 and 17+ rows plays the same")


func _test_count_rows() -> void:
	var rows := StrategyChart.count_rows()
	var expected := BlackjackStrategy.DEVIATIONS.size() + BlackjackStrategy.PAIR_DEVIATIONS.size() + 1
	check(rows.size() == expected, "the count chart should list all %d index plays, got %d" % [expected, rows.size()])
	check(rows.size() == 18, "the Illustrious 18 is 18 plays, got %d" % rows.size())
	var labels := {}
	for row in rows:
		labels[row[0]] = true
	for d in StrategyQuiz.deviations():
		check(labels.has(d.label), "the quiz's %s should be a row on the count chart" % d.label)
	check(labels.has("Insurance"), "insurance belongs on the count chart")
	note("the count chart is the full Illustrious 18, in the quiz's own terms")


func _test_chart_widget() -> void:
	var chart := StrategyChart.new()
	add_child(chart)
	await frames()
	for table in ["hard", "soft", "pair"]:
		chart.show_table(table)
		var cells: int = chart._cells.size()
		check(cells == StrategyChart.rows_for(table).size() * StrategyChart.UPCARDS.size(),
			"the %s chart should draw a cell per row and upcard, got %d" % [table, cells])
	chart.highlight("soft", "A,7", 9)
	var cell: Label = chart._cells["soft:A,7:9"]
	var box: StyleBoxFlat = cell.get_theme_stylebox("normal")
	check(box.border_color == StrategyChart.COLOR_GOLD and box.border_width_top > 0,
		"a highlighted cell should be outlined in gold")
	chart.highlight("count", "16 v 10")
	check(chart.table == "count" and chart._cells.has("count:16 v 10:0"),
		"highlighting an index play should switch to the count chart")
	chart.queue_free()
	await frames()
	note("the chart widget draws every table and can point at one cell")


func _test_quiz_answers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 18
	for mode in ["basic", "count"]:
		for i in SAMPLES:
			var q := StrategyQuiz.make(rng, mode)
			if q.kind == "insurance":
				var take: bool = BlackjackStrategy.insurance(q.true_count).take
				check(q.answer == ("Insure" if take else "Decline"), "insurance answer mismatch")
				check(int(q.up) == 11, "insurance is only offered against an ace")
				continue
			var expected: String
			if q.has("true_count"):
				expected = BlackjackStrategy.with_count(q.hand, q.up, q.can_double, q.can_split, q.true_count).action
			else:
				expected = BlackjackStrategy.basic(q.hand, q.up, q.can_double, q.can_split).action
			check(q.answer == expected, "%s: %s v %d answered %s, strategy says %s" % [
				mode, q.hand, q.up, q.answer, expected])
			check(not (q.answer == "Double" and not q.can_double), "Double can't be the answer when doubling isn't allowed")
			check(not (q.answer == "Split" and not q.can_split), "Split can't be the answer on a hand that can't split")
			check(int(BlackjackStrategy.evaluate(q.hand).total) <= 21, "a question hand can't already be bust")
			if q.table != "count":
				var rows := []
				for entry in StrategyChart.rows_for(q.table):
					rows.append(entry[0])
				check(q.row in rows, "%s isn't a row of the %s chart" % [q.row, q.table])
	note("%d quiz answers per mode agree with BlackjackStrategy, and point at real chart cells" % SAMPLES)


func _test_count_mode_hits_indices() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var deviating := 0
	var near_index := 0
	var insurance := 0
	for i in SAMPLES:
		var q := StrategyQuiz.count_question(rng)
		if q.kind == "insurance":
			insurance += 1
			check(absf(q.true_count - BlackjackStrategy.INSURANCE_INDEX) <= StrategyQuiz.INDEX_SPREAD + 1,
				"insurance questions sit near the +3 index")
			continue
		if q.deviates:
			deviating += 1
		if q.table == "count":
			near_index += 1
	check(deviating > SAMPLES / 6, "count mode should often change the play, only %d of %d did" % [deviating, SAMPLES])
	check(near_index > SAMPLES * 0.4, "about half of count questions should sit at an index, got %d" % near_index)
	check(insurance > SAMPLES * 0.05, "count mode should ask about insurance, got %d" % insurance)
	note("count mode: %d at an index, %d where the count changes the play, %d insurance" % [
		near_index, deviating, insurance])


func _test_question_for_every_key() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var keys: Array = []
	for table in ["hard", "soft", "pair"]:
		for entry in StrategyChart.rows_for(table):
			for up in StrategyChart.UPCARDS:
				keys.append("%s:%s:%d" % [table, entry[0], up])
	for d in StrategyQuiz.deviations():
		keys.append("dev:" + String(d.label))
	keys.append("dev:Insurance")
	for key in keys:
		for i in 3:
			var q := StrategyQuiz.question_for_key(rng, key)
			check(q.key == key, "a question for %s came back as %s" % [key, q.key])
	note("Weak Spots can rebuild a question for all %d chart cells and index plays" % keys.size())


func _test_weak_keys() -> void:
	var cells := {
		"hard:16:10": [1, 4], "soft:A,7:9": [0, 2], "pair:9,9:7": [3, 3],
		"hard:12:3": [1, 2], "dev:16 v 10": [0, 5],
	}
	var weak := StrategyQuiz.weak_keys(cells)
	check(weak == ["dev:16 v 10", "soft:A,7:9", "hard:16:10", "hard:12:3"],
		"weak spots should be worst-first and leave out the perfect ones, got %s" % [weak])
	note("weak spots are the misses, worst first")


func _test_table_buttons() -> void:
	Store.use_test_backend()
	var t: Control = load("res://scenes/blackjack.tscn").instantiate()
	add_child(t)
	await frames()
	var button: Button = t.drill_buttons["strategy_trainer"]
	check("Extras" in button.text, "a locked drill should say it lives in Extras, got '%s'" % button.text)
	Store.buy("strategy_trainer")
	check(button.text == "Strategy Trainer", "buying should unlock the button in place, got '%s'" % button.text)
	var modal: Modal = t._on_charts_pressed()
	await frames()
	check(modal.content.get_child(0) is StrategyChart, "the free charts should open over the table")
	modal.close()
	t.queue_free()
	await frames()
	Store.use_test_backend()
	note("the table offers the free charts, and its drill buttons follow ownership")


func _test_strategy_drill() -> void:
	Store.use_test_backend()
	Store.buy("strategy_trainer")
	var d: Control = load("res://scenes/strategy_drill.tscn").instantiate()
	add_child(d)
	await frames()
	d.rng.seed = 42
	d._set_mode("basic")
	check(d.answer_buttons.size() == 4, "a play question offers Hit, Stand, Double and Split")

	d.answer(d.question.answer)
	check(d.score == StrategyDrillPoints.POINTS and d.streak == 1, "a right answer should score")
	for i in 4:
		d.answer(d.question.answer)
	check(d.multiplier() == 2, "five in a row should double the points, got x%d" % d.multiplier())

	var key: String = d.question.key
	var wrong := "Hit" if d.question.answer != "Hit" else "Stand"
	d.answer(wrong)
	await frames()
	check(d.streak == 0, "a wrong answer should end the streak")
	var correction: Modal = d.get_node_or_null("Correction")
	check(correction != null, "a wrong answer should stop to explain")
	if correction != null:
		var chart: StrategyChart = correction.content.get_child(2)
		check(chart._cells.has(chart._highlight), "the correction should point at the chart cell, '%s'" % chart._highlight)
		correction.close()
	var cells: Dictionary = SaveData.get_value("strategy_trainer", "cells", {})
	check(cells.has(key) and int(cells[key][0]) < int(cells[key][1]), "the miss should be remembered for Weak Spots")
	check(int(SaveData.get_value("strategy_trainer", "best_streak_basic", 0)) == 5, "the best streak should be saved")

	d._set_mode("weak")
	check(d.question.key in StrategyQuiz.weak_keys(d.cells), "Weak Spots should ask about a miss")

	d._set_mode("count")
	check(d.count_label.visible == d.question.has("true_count"), "count questions should show the true count")

	d._set_mode("blitz")
	d.answer(d.question.answer)
	d.answer("Hit" if d.question.answer != "Hit" else "Stand")
	await frames()
	check(d.get_node_or_null("Correction") == null, "Blitz doesn't stop for corrections")
	d._process(StrategyDrillPoints.BLITZ + 1.0)
	await frames()
	check(d.get_node_or_null("BlitzOver") != null, "Blitz should end after 60 seconds")
	check(int(SaveData.get_value("strategy_trainer", "best_blitz", 0)) == d.score, "the Blitz score should be saved")
	d.queue_free()
	await frames()
	Store.use_test_backend()
	note("the drill scores, multiplies streaks, corrects on the chart, and times Blitz")


class StrategyDrillPoints:
	const POINTS := 10
	const BLITZ := 60.0

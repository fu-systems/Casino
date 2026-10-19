extends CasinoTest
## The Systems Lab screen: that it starts from the right system, that every
## kind of condition and action can be built in the editor, and that runs,
## saving and sharing work from the screen itself.

var lab: Control


func run() -> void:
	Store.use_test_backend()
	Store.buy("roulette_lab")
	_test_from_table_layout()
	SystemLab.open_game = "roulette"
	SystemLab.open_layout = {"red": 25, "straight_17": 5}
	lab = load("res://scenes/system_lab.tscn").instantiate()
	add_child(lab)
	await frames()

	_test_opened_on_table_bets()
	await _test_steps_and_warnings()
	await _test_condition_editor()
	await _test_action_editor()
	await _test_picker()
	await _test_runs()
	await _test_save_and_share()
	await _test_remembered()

	lab.queue_free()
	await frames()
	Store.use_test_backend()


func _test_from_table_layout() -> void:
	SystemLab.open_game = "roulette"
	var system := SystemLab._system_from_layout({"red": 25, "straight_17": 5, "dozen_1": 10})
	check(int(system.settings.unit) == 5, "the unit should be the chips' common factor, got %d" % int(system.settings.unit))
	check(system.steps[0].layout == {"red": 5, "straight_17": 1, "dozen_1": 2},
		"the table's chips become units: %s" % [system.steps[0].layout])
	note("the chips on the table become a system: $25 red and $5 on 17 are 5u and 1u of $5")


func _test_opened_on_table_bets() -> void:
	check(lab.system.name == "My table bets", "opening from the table should load the table's bets")
	check(SystemLab.open_layout.is_empty(), "the hand-over is used once")
	check(lab.get_node_or_null("Locked") == null, "an owned lab isn't covered")
	note("the lab opens on the bets that were on the table")


func _test_steps_and_warnings() -> void:
	lab.load_system(SystemPresets.roulette()[6])
	await frames()
	check(lab.steps_list.get_child_count() == 2, "Wait for 5 reds has two steps")
	check(lab.flowchart._boxes.size() == 2, "the flowchart draws a box per step")
	check(lab.warnings_label.text == "", "a famous system shouldn't need warnings")
	lab._add_step()
	await frames()
	check(lab.system.steps.size() == 3, "+ Step adds a step")
	check("Nothing ever goes to" in lab.warnings_label.text, "a step nothing reaches should be flagged")
	lab._delete_step()
	await frames()
	check(lab.system.steps.size() == 2 and lab.warnings_label.text == "", "deleting it clears the warning")
	lab.select_step(1)
	check(lab.selected_step == 1 and lab.step_editor.get_child_count() > 0, "selecting a step edits it")
	note("steps can be added, removed and selected, and problems show as warnings")


## Builds one condition of every kind through the editor's own controls.
func _test_condition_editor() -> void:
	var built: Array = []
	var editor := RuleEditor.edit_condition(lab, lab.system, {}, func(c: Dictionary) -> void: built.append(c))
	await frames()
	var picker: OptionButton = editor.content.get_child(1).get_child(1)
	for i in picker.item_count:
		picker.select(i)
		picker.item_selected.emit(i)
		await frames()
		var summary: Label = editor.content.get_child(0)
		check(summary.text.begins_with("IF ") and not "?" in summary.text,
			"the %s condition should describe itself, got '%s'" % [picker.get_item_text(i), summary.text])
	editor.actions.get_child(0).emit_signal("pressed")
	await frames()
	check(built.size() == 1 and built[0].type == "not", "Done hands back the condition built (the last kind)")
	note("every kind of condition can be built and reads back in plain words")


func _test_action_editor() -> void:
	var built: Array = []
	var editor := RuleEditor.edit_action(lab, lab.system, {}, func(a: Dictionary) -> void: built.append(a))
	await frames()
	var picker: OptionButton = editor.content.get_child(1).get_child(1)
	var kinds := 0
	for i in picker.item_count:
		picker.select(i)
		picker.item_selected.emit(i)
		await frames()
		kinds += 1
		var summary: Label = editor.content.get_child(0)
		check(summary.text != "" and summary.text != "?", "action %s should describe itself" % picker.get_item_text(i))
	check(kinds == SystemModel.ACTIONS.size() - SystemModel.CRAPS_ONLY_ACTIONS.size(),
		"roulette should offer every action but the craps ones, offered %d" % kinds)
	editor.actions.get_child(0).emit_signal("pressed")
	await frames()
	check(built.size() == 1 and built[0].type == "stop", "Done hands back the action built")

	var list: Array = []
	var actions := RuleEditor.edit_actions(lab, lab.system, [{"type": "unit", "op": "reset"}],
		func(a: Array) -> void: list.append_array(a))
	await frames()
	actions.actions.get_child(0).emit_signal("pressed")
	await frames()
	check(list.size() == 1 and list[0].type == "unit", "the action list comes back from Done")
	note("every roulette action can be built; craps-only actions aren't offered")


func _test_picker() -> void:
	var chosen: Array = []
	var picker := PositionPicker.open(lab, "roulette", false, [], func(keys: Array) -> void: chosen.append_array(keys))
	await frames()
	var buttons: Array = picker.find_children("*", "Button", true, false)
	var seventeen: Button
	for button in buttons:
		if button.text == "17":
			seventeen = button
	check(seventeen != null, "the picker should lay out the numbers")
	if seventeen != null:
		seventeen.emit_signal("pressed")
	await frames()
	check(chosen == ["straight_17"], "tapping 17 should choose a straight bet on 17, got %s" % [chosen])
	note("the bet picker is a miniature board")


func _test_runs() -> void:
	lab.load_system(SystemPresets.roulette()[1])
	lab.run_one()
	check("house edge" in lab.results_label.text, "a session's result should be read against the house edge")
	var grid: GridContainer = lab.trace_list.get_child(0)
	check(grid.get_child_count() == 7 * (1 + mini(200, 200)) or grid.get_child_count() > 7,
		"the trace should list the session's rounds")
	lab.system.settings.sessions = 25
	await lab.run_many()
	check("Finished ahead" in lab.results_label.text, "many sessions should be summarised")
	check(lab.chart.mode == "histogram", "many sessions draw a histogram")
	note("one session shows its rounds; many sessions show the spread, both against the edge")


func _test_save_and_share() -> void:
	lab.load_system(SystemPresets.roulette()[3])
	lab.save_current()
	check("D'Alembert" in SaveData.keys("systems_roulette"), "saving should keep the system under its name")
	var code := SystemModel.export_code(SystemPresets.roulette()[4])
	lab._show_share()
	await frames()
	var modal: Modal = null
	for child in lab.get_children():
		if child is Modal:
			modal = child
	var edits: Array = modal.find_children("*", "LineEdit", true, false)
	edits[1].text = code
	modal.actions.get_child(0).emit_signal("pressed")
	await frames()
	check(lab.system.name == "Fibonacci", "importing a code should load it, got %s" % lab.system.name)
	note("systems save by name, and import from a shared code")


func _test_remembered() -> void:
	var name: String = lab.system.name
	SystemLab.open_game = "roulette"
	var again: Control = load("res://scenes/system_lab.tscn").instantiate()
	add_child(again)
	await frames()
	check(again.system.name == name, "the lab should reopen on the last system, got %s" % again.system.name)
	again.queue_free()
	await frames()
	note("the lab reopens where it was left")

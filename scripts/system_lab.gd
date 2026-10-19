class_name SystemLab
extends Control
## The Systems Lab packs (one for roulette, one for craps): build a betting
## system as a flowchart of steps and IF / THEN rules, start from one of the
## famous ones, and run it for thousands of rounds to see what it really does.
##
## Three tabs: Build (the steps, their bets and rules), Flowchart (the same
## system drawn as boxes and arrows) and Results (one session round by round,
## or many sessions at once). Every result is shown beside what the house
## edge predicts.

const COLOR_FELT := Color(0.04, 0.2, 0.11)
const COLOR_PANEL := Color(0.03, 0.15, 0.08)
const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_MUTED := Color(0.78, 0.85, 0.78)
const COLOR_WARN := Color(0.98, 0.66, 0.35)
const COLOR_WIN := Color(0.5, 0.92, 0.55)
const COLOR_LOSE := Color(0.96, 0.5, 0.45)
const TABS := ["build", "flowchart", "results"]
const TAB_NAMES := {"build": "Build", "flowchart": "Flowchart", "results": "Results"}
const PACKS := {"roulette": "roulette_lab", "craps": "craps_lab"}
const GAME_SCENES := {"roulette": "res://scenes/roulette.tscn", "craps": "res://scenes/craps.tscn"}

## Set by the game screen before opening the lab.
static var open_game := "roulette"
## Chips on the table when the lab was opened ({position: dollars}), to test
## that exact layout.
static var open_layout := {}

var game := "roulette"
var system: Dictionary = {}
var selected_step := 0
var tab := "build"

var tab_buttons := {}
var pages := {}
var name_edit: LineEdit
var steps_list: VBoxContainer
var step_editor: VBoxContainer
var warnings_label: Label
var flowchart: FlowchartView
var chart: LabChart
var results_label: Label
var trace_list: VBoxContainer
var progress: ProgressBar
var run_buttons: Array = []
var cancel_button: Button
var _batch: SystemRunner.MonteCarlo
var _cancelled := false


func _ready() -> void:
	game = open_game
	system = _initial_system()
	_build_ui()
	_show_tab("build")
	_refresh()
	if not Store.owns(PACKS[game]):
		LockedPack.cover(self, PACKS[game], GAME_SCENES[game])


func _initial_system() -> Dictionary:
	if not open_layout.is_empty():
		var from_table := _system_from_layout(open_layout)
		open_layout = {}
		return from_table
	var saved: Variant = SaveData.get_value("lab_" + game, "current", "")
	if saved is String and saved != "":
		var parsed: Variant = JSON.parse_string(saved)
		if parsed is Dictionary and String(parsed.get("game", "")) == game:
			return SystemModel.normalised(parsed)
	var presets := SystemPresets.for_game(game)
	return presets[1].duplicate(true) if presets.size() > 1 else SystemModel.new_system(game)


## A flat system made of the chips on the table: the unit is their greatest
## common chip, so $25 on red and $5 on 17 becomes 5u red and 1u 17.
static func _system_from_layout(chips: Dictionary) -> Dictionary:
	var unit := 0
	for key in chips:
		unit = _gcd(unit, int(chips[key]))
	var layout := {}
	for key in chips:
		layout[key] = int(chips[key]) / maxi(unit, 1)
	var system := SystemModel.new_system(open_game, "My table bets")
	system.notes = "The bets that were on the table, repeated every round. Add rules to make it a system."
	system.settings.unit = maxi(unit, 1)
	system.steps[0].name = "Table bets"
	system.steps[0].layout = layout
	return system


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return a


# --- Keeping the screen in step -----------------------------------------------------------

## Redraws everything that shows the system, and remembers it.
func _refresh() -> void:
	if SystemModel.step(system, selected_step).is_empty():
		selected_step = int(system.steps[0].id)
	name_edit.text = system.name
	_fill_steps()
	_fill_step_editor()
	flowchart.show_system(system)
	var problems := SystemModel.validate(system)
	warnings_label.text = "" if problems.is_empty() else "⚠ " + "\n⚠ ".join(problems)
	SaveData.set_value("lab_" + game, "current", JSON.stringify(system))


func _show_tab(key: String) -> void:
	tab = key
	for name in TABS:
		pages[name].visible = name == key
		var active: bool = name == key
		CasinoUI.style_button(tab_buttons[name], Color(0.45, 0.36, 0.1) if active else Color(0.08, 0.2, 0.12),
			18, 14, 8, 8, COLOR_GOLD if active else Color(0, 0, 0, 0))


# --- Build tab ---------------------------------------------------------------------------

func _fill_steps() -> void:
	_clear(steps_list)
	for entry in system.steps:
		var id := int(entry.id)
		var button := Button.new()
		button.text = ("▶ " if id == int(system.start) else "") + String(entry.name)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 44)
		var active := id == selected_step
		CasinoUI.style_button(button, Color(0.45, 0.36, 0.1) if active else Color(0.08, 0.2, 0.12), 16, 10, 6, 8,
			COLOR_GOLD if active else Color(0, 0, 0, 0))
		button.pressed.connect(select_step.bind(id))
		steps_list.add_child(button)


func select_step(id: int) -> void:
	selected_step = id
	_fill_steps()
	_fill_step_editor()
	_show_tab("build")


func _fill_step_editor() -> void:
	_clear(step_editor)
	var entry := SystemModel.step(system, selected_step)
	if entry.is_empty():
		return

	_header(step_editor, "BETS IN THIS STEP", "Units are multiplied by the current unit (starts at $%d)." % int(system.settings.unit))
	for key in entry.layout:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		step_editor.add_child(row)
		var label := Label.new()
		label.text = SystemModel.position_label(game, key)
		label.custom_minimum_size = Vector2(200, 0)
		label.add_theme_font_size_override("font_size", 18)
		row.add_child(label)
		RuleEditor._stepper(row, int(entry.layout[key]), 1, 1000, func(v: int) -> void:
			entry.layout[key] = v
			_refresh_soon())
		RuleEditor._small(row, "✕", func() -> void:
			entry.layout.erase(key)
			_refresh())
	if entry.layout.is_empty():
		_note(step_editor, "No bets: this step only watches.")
	RuleEditor._small(step_editor, "+ Add bets", func() -> void:
		PositionPicker.open(self, game, true, entry.layout.keys(), func(keys: Array) -> void:
			for key in keys:
				if not entry.layout.has(key):
					entry.layout[key] = 1
			for key in entry.layout.keys():
				if not key in keys:
					entry.layout.erase(key)
			_refresh()))

	_header(step_editor, "AFTER EACH ROUND", "Rules are checked top to bottom; the first one that matches runs, and the rest are skipped.")
	for i in entry.rules.size():
		_rule_card(entry, i)
	RuleEditor._small(step_editor, "+ Add a rule", func() -> void:
		RuleEditor.edit_condition(self, system, {}, func(cond: Dictionary) -> void:
			entry.rules.append({"when": cond, "then": []})
			_refresh()
			RuleEditor.edit_actions(self, system, [], func(actions: Array) -> void:
				entry.rules[-1].then = actions
				_refresh())))

	var other := _card(step_editor)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	other.add_child(line)
	var text := Label.new()
	text.text = "OTHERWISE  " + SystemModel.describe_actions(entry.otherwise, system)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 17)
	line.add_child(text)
	RuleEditor._small(line, "Edit", func() -> void:
		RuleEditor.edit_actions(self, system, entry.otherwise, func(actions: Array) -> void:
			entry.otherwise = actions
			_refresh(), "OTHERWISE…"))


func _rule_card(entry: Dictionary, i: int) -> void:
	var rule: Dictionary = entry.rules[i]
	var card := _card(step_editor)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	card.add_child(top)
	var when := Label.new()
	when.text = "%d.  IF %s" % [i + 1, SystemModel.describe_condition(rule.when, game)]
	when.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	when.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	when.add_theme_font_size_override("font_size", 17)
	when.add_theme_color_override("font_color", COLOR_GOLD)
	top.add_child(when)
	RuleEditor._small(top, "Edit", func() -> void:
		RuleEditor.edit_condition(self, system, rule.when, func(cond: Dictionary) -> void:
			rule.when = cond
			_refresh()))
	if i > 0:
		RuleEditor._small(top, "↑", func() -> void:
			entry.rules.remove_at(i)
			entry.rules.insert(i - 1, rule)
			_refresh())
	RuleEditor._small(top, "✕", func() -> void:
		entry.rules.remove_at(i)
		_refresh())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	card.add_child(bottom)
	var then := Label.new()
	then.text = "      THEN " + SystemModel.describe_actions(rule.then, system)
	then.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	then.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	then.add_theme_font_size_override("font_size", 17)
	bottom.add_child(then)
	RuleEditor._small(bottom, "Edit", func() -> void:
		RuleEditor.edit_actions(self, system, rule.then, func(actions: Array) -> void:
			rule.then = actions
			_refresh()))


## The steppers change numbers many times a second; redrawing the whole
## editor under a finger would lose the button being held.
func _refresh_soon() -> void:
	flowchart.show_system(system)
	SaveData.set_value("lab_" + game, "current", JSON.stringify(system))


func _add_step() -> void:
	var id := SystemModel.next_step_id(system)
	system.steps.append(SystemModel.new_step(id, "Step %d" % (system.steps.size() + 1)))
	selected_step = id
	_refresh()


func _rename_step() -> void:
	var entry := SystemModel.step(system, selected_step)
	_ask_text("Rename step", entry.name, func(text: String) -> void:
		entry.name = text
		_refresh())


func _delete_step() -> void:
	if system.steps.size() <= 1:
		return
	var entry := SystemModel.step(system, selected_step)
	system.steps.erase(entry)
	if int(system.start) == selected_step:
		system.start = int(system.steps[0].id)
	selected_step = int(system.steps[0].id)
	_refresh()


func _make_start() -> void:
	system.start = selected_step
	_refresh()


# --- Systems: presets, saving, sharing ---------------------------------------------------

func _show_presets() -> void:
	var modal := Modal.open(self, "Start from a famous system", 900)
	for preset in SystemPresets.for_game(game):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		modal.content.add_child(row)
		var text := Label.new()
		text.text = "%s — %s" % [preset.name, preset.notes]
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_size_override("font_size", 16)
		row.add_child(text)
		RuleEditor._small(row, "Open", func() -> void:
			load_system(preset)
			modal.close())
	modal.add_button("Close", Color(0.25, 0.22, 0.2))


func load_system(new_system: Dictionary) -> void:
	system = SystemModel.normalised(new_system)
	selected_step = int(system.start)
	chart.clear()
	results_label.text = ""
	_clear(trace_list)
	_refresh()


func _show_saved() -> void:
	var section := "systems_" + game
	var modal := Modal.open(self, "My systems", 760)
	var names := SaveData.keys(section)
	if names.is_empty():
		modal.add_text("Nothing saved yet. Build a system, then Save it here.", 17, COLOR_MUTED)
	for key in names:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		modal.content.add_child(row)
		var text := Label.new()
		text.text = key
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_size_override("font_size", 18)
		row.add_child(text)
		RuleEditor._small(row, "Open", func() -> void:
			var parsed: Variant = JSON.parse_string(String(SaveData.get_value(section, key, "")))
			if parsed is Dictionary:
				load_system(parsed)
			modal.close())
		RuleEditor._small(row, "Delete", func() -> void:
			SaveData.erase_value(section, key)
			row.queue_free())
	modal.add_button("Save current", Color(0.16, 0.38, 0.24), save_current)
	modal.add_button("Close", Color(0.25, 0.22, 0.2))


func save_current() -> void:
	SaveData.set_value("systems_" + game, String(system.name), JSON.stringify(system))


func _show_share() -> void:
	var modal := Modal.open(self, "Share a system", 860)
	modal.add_text("This line of text is the whole system. Send it to someone with the Systems Lab and they can import it.", 16, COLOR_MUTED)
	var code := LineEdit.new()
	code.text = SystemModel.export_code(system)
	code.editable = false
	code.custom_minimum_size = Vector2(0, 46)
	modal.content.add_child(code)
	RuleEditor._small(modal.content, "Copy to clipboard", func() -> void:
		DisplayServer.clipboard_set(code.text))
	modal.add_text("Import one: paste it below.", 16, COLOR_MUTED)
	var paste := LineEdit.new()
	paste.placeholder_text = SystemModel.CODE_PREFIX + "…"
	paste.custom_minimum_size = Vector2(0, 46)
	modal.content.add_child(paste)
	var status := modal.add_text("", 16, COLOR_WARN)
	RuleEditor._small(modal.content, "Paste from clipboard", func() -> void:
		paste.text = DisplayServer.clipboard_get())
	modal.add_button("Import", Color(0.16, 0.38, 0.24), func() -> void:
		var imported := SystemModel.import_code(paste.text)
		if imported.is_empty():
			status.text = "That isn't a system code."
		elif String(imported.game) != game:
			status.text = "That's a %s system; this is the %s lab." % [SystemModel.game_name(imported.game), SystemModel.game_name(game)]
		else:
			load_system(imported)
			modal.close(), false)
	modal.add_button("Close", Color(0.25, 0.22, 0.2))


func _show_settings() -> void:
	var modal := Modal.open(self, "Session settings", 760)
	var labels := {
		"bankroll": "Bankroll ($)", "unit": "Starting unit ($)", "table_min": "Table minimum ($)",
		"table_max": "Table maximum ($)", "rounds": "Rounds per session",
		"stop_loss": "Stop-loss ($, 0 = off)", "take_profit": "Take-profit ($, 0 = off)",
		"sessions": "Sessions to simulate",
	}
	var boxes := {}
	for key in labels:
		var row := RuleEditor._row(modal.content, labels[key])
		row.get_child(0).custom_minimum_size = Vector2(300, 0)
		boxes[key] = RuleEditor._number_box(row, float(system.settings[key]),
			SystemModel.LIMITS[key][0], SystemModel.LIMITS[key][1], 1, func(_v: float) -> void: pass)
	modal.add_button("Done", Color(0.16, 0.38, 0.24), func() -> void:
		for key in boxes:
			system.settings[key] = int(boxes[key].value)
		system = SystemModel.normalised(system)
		_refresh())
	modal.add_button("Cancel", Color(0.25, 0.22, 0.2))


func _ask_text(title: String, value: String, on_done: Callable) -> void:
	var modal := Modal.open(self, title, 600)
	var edit := LineEdit.new()
	edit.text = value
	edit.custom_minimum_size = Vector2(0, 46)
	edit.max_length = 40
	modal.content.add_child(edit)
	modal.add_button("Done", Color(0.16, 0.38, 0.24), func() -> void:
		if edit.text.strip_edges() != "":
			on_done.call(edit.text.strip_edges()))
	modal.add_button("Cancel", Color(0.25, 0.22, 0.2))


# --- Results tab ---------------------------------------------------------------------------

func run_one() -> void:
	var seed := randi()
	var result := SystemRunner.run_session(system, seed, true)
	var bankroll := int(system.settings.bankroll)
	chart.show_curve(result.curve, bankroll, float(result.expected))
	var lines: PackedStringArray = []
	lines.append("One session: finished on $%s (%s) after %d round%s — %s." % [
		Bank.fmt(int(result.final)), money(int(result.net)), int(result.rounds),
		"" if int(result.rounds) == 1 else "s", SystemRunner.REASONS[result.reason]])
	lines.append("The house edge on $%s staked predicts %s. This session: %s." % [
		Bank.fmt(int(result.staked)), LabChart.money(float(result.expected)), money(int(result.net))])
	lines.append("Peak $%s  ·  deepest fall from a peak $%s  ·  biggest bet $%s%s" % [
		Bank.fmt(int(result.peak)), Bank.fmt(int(result.max_drawdown)), Bank.fmt(int(result.largest_bet)),
		"  ·  %d bet%s capped at the table maximum" % [int(result.capped), "" if int(result.capped) == 1 else "s"]
			if int(result.capped) > 0 else ""])
	lines.append("One session proves nothing either way — run many to see the pattern.")
	results_label.text = "\n".join(lines)
	_fill_trace(result.trace)


func run_many() -> void:
	if _batch != null:
		return
	_cancelled = false
	_batch = SystemRunner.MonteCarlo.new(system, int(system.settings.sessions), randi())
	progress.visible = true
	cancel_button.visible = true
	for button in run_buttons:
		button.disabled = true
	_clear(trace_list)
	while not _batch.done() and not _cancelled:
		_batch.step(12)
		progress.value = _batch.progress() * 100.0
		results_label.text = "Running %d of %d sessions…" % [_batch.done_sessions, _batch.sessions]
		await get_tree().process_frame
	if _batch.results.size() > 0:
		show_summary(_batch.summary())
	progress.visible = false
	cancel_button.visible = false
	for button in run_buttons:
		button.disabled = false
	_batch = null


func show_summary(summary: Dictionary) -> void:
	chart.show_histogram(summary.histogram, float(summary.mean_expected))
	var lines: PackedStringArray = []
	lines.append("%d sessions of up to %d rounds, each from a $%s bankroll%s." % [
		int(summary.sessions), int(system.settings.rounds), Bank.fmt(int(summary.bankroll)),
		" (stopped early)" if int(summary.sessions) < int(system.settings.sessions) else ""])
	lines.append("Finished ahead: %d%%   ·   Ran short of the next bet: %d%%" % [
		roundi(100 * float(summary.ahead_share)), roundi(100 * float(summary.bust_share))])
	lines.append("Average result: %s   ·   Median: %s   ·   Best: %s   ·   Worst: %s" % [
		money(roundi(float(summary.mean_net))), money(int(summary.median_net)),
		money(int(summary.best)), money(int(summary.worst))])
	lines.append("The house edge predicts %s a session on the $%s staked on average." % [
		LabChart.money(float(summary.mean_expected)), Bank.fmt(roundi(float(summary.mean_staked)))])
	lines.append("Biggest bet needed: $%s   ·   Longest losing streak: %d%s" % [
		Bank.fmt(int(summary.largest_bet)), int(summary.longest_losing),
		"   ·   Bets capped by the table maximum: %d" % int(summary.capped) if int(summary.capped) > 0 else ""])
	lines.append(verdict(summary))
	results_label.text = "\n".join(lines)


## One plain sentence on what the numbers mean.
static func verdict(summary: Dictionary) -> String:
	var mean := float(summary.mean_net)
	var ahead := float(summary.ahead_share)
	if mean < 0.0 and ahead > 0.5:
		return "Most sessions end a little ahead, but the losing ones lose big — on average it costs about what the edge says. That's how progressions feel like they work."
	if mean < 0.0:
		return "On average it loses, close to what the edge predicts. No arrangement of bets changes the edge on each one."
	return "This batch came out ahead on average — that's variance. Run more sessions and it settles toward the edge."


## The session round by round: what the system did and why, for checking a
## flowchart does what you meant.
func _fill_trace(trace: Array) -> void:
	_clear(trace_list)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	trace_list.add_child(grid)
	for heading in ["Round", "Step", "Result", "Bets", "Net", "Bankroll", "Rule"]:
		_trace_cell(grid, heading, COLOR_GOLD)
	for row in trace:
		var colour := COLOR_WIN if int(row.net) > 0 else (COLOR_LOSE if int(row.net) < 0 else COLOR_MUTED)
		_trace_cell(grid, str(int(row.round)), COLOR_MUTED)
		_trace_cell(grid, row.step, COLOR_MUTED)
		_trace_cell(grid, row.outcome, Color.WHITE)
		_trace_cell(grid, row.bets, Color.WHITE)
		_trace_cell(grid, money(int(row.net)), colour)
		_trace_cell(grid, "$" + Bank.fmt(int(row.bankroll)), Color.WHITE)
		_trace_cell(grid, row.rule if row.rule != "" else "—", COLOR_MUTED)


func _trace_cell(grid: GridContainer, text: String, colour: Color) -> void:
	var cell := Label.new()
	cell.text = text
	cell.add_theme_font_size_override("font_size", 14)
	cell.add_theme_color_override("font_color", colour)
	grid.add_child(cell)


static func money(n: int) -> String:
	return LabChart.money(n)


# --- Building the screen ---------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_FELT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := SafeArea.create(16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)
	var back := Button.new()
	back.text = "< Back"
	back.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(back, Color(0.09, 0.2, 0.13), 18, 14, 8)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(GAME_SCENES[game]))
	top.add_child(back)
	var title := Label.new()
	title.text = "%s SYSTEMS LAB" % SystemModel.game_name(game).to_upper()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	top.add_child(title)
	for key in TABS:
		var button := Button.new()
		button.text = TAB_NAMES[key]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(120, 42)
		button.pressed.connect(_show_tab.bind(key))
		top.add_child(button)
		tab_buttons[key] = button

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	column.add_child(bar)
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(300, 44)
	name_edit.max_length = 40
	name_edit.text_changed.connect(func(text: String) -> void:
		system.name = text if text.strip_edges() != "" else "Untitled"
		SaveData.set_value("lab_" + game, "current", JSON.stringify(system)))
	bar.add_child(name_edit)
	for spec in [["Famous systems", _show_presets], ["My systems", _show_saved], ["Share", _show_share],
			["Settings", _show_settings], ["New", func() -> void: load_system(SystemModel.new_system(game))]]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		CasinoUI.style_button(button, Color(0.12, 0.24, 0.32), 17, 12, 8)
		button.pressed.connect(spec[1])
		bar.add_child(button)

	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	pages.build = _build_page()
	pages.flowchart = _flowchart_page()
	pages.results = _results_page()
	for key in TABS:
		pages[key].set_anchors_preset(Control.PRESET_FULL_RECT)
		body.add_child(pages[key])


func _build_page() -> Control:
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 12)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	left.add_theme_constant_override("separation", 6)
	page.add_child(left)
	_header(left, "STEPS", "▶ marks where it starts.")
	var steps_scroll := ScrollContainer.new()
	steps_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	steps_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(steps_scroll)
	steps_list = VBoxContainer.new()
	steps_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	steps_list.add_theme_constant_override("separation", 4)
	steps_scroll.add_child(steps_list)
	var step_tools := GridContainer.new()
	step_tools.columns = 2
	step_tools.add_theme_constant_override("h_separation", 4)
	step_tools.add_theme_constant_override("v_separation", 4)
	left.add_child(step_tools)
	for spec in [["+ Step", _add_step], ["Rename", _rename_step], ["Delete", _delete_step], ["Start here", _make_start]]:
		var button := RuleEditor._small(step_tools, spec[0], spec[1])
		button.custom_minimum_size = Vector2(122, 40)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	page.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	step_editor = VBoxContainer.new()
	step_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_editor.add_theme_constant_override("separation", 8)
	scroll.add_child(step_editor)
	warnings_label = Label.new()
	warnings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warnings_label.add_theme_font_size_override("font_size", 15)
	warnings_label.add_theme_color_override("font_color", COLOR_WARN)
	right.add_child(warnings_label)
	return page


func _flowchart_page() -> Control:
	var scroll := ScrollContainer.new()
	flowchart = FlowchartView.new()
	flowchart.step_pressed.connect(select_step)
	scroll.add_child(flowchart)
	return scroll


func _results_page() -> Control:
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.add_theme_constant_override("separation", 8)
	page.add_child(left)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	left.add_child(buttons)
	for spec in [["Run one session", run_one], ["Run many sessions", run_many]]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 48)
		CasinoUI.style_button(button, Color(0.16, 0.38, 0.24), 18, 14, 8, 8, COLOR_GOLD)
		button.pressed.connect(spec[1])
		buttons.add_child(button)
		run_buttons.append(button)
	cancel_button = RuleEditor._small(buttons, "Cancel", func() -> void: _cancelled = true)
	cancel_button.visible = false
	progress = ProgressBar.new()
	progress.visible = false
	progress.custom_minimum_size = Vector2(0, 14)
	left.add_child(progress)
	results_label = Label.new()
	results_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	results_label.add_theme_font_size_override("font_size", 16)
	results_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(results_label)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	page.add_child(right)
	chart = LabChart.new()
	right.add_child(chart)
	var trace_scroll := ScrollContainer.new()
	trace_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(trace_scroll)
	trace_list = VBoxContainer.new()
	trace_scroll.add_child(trace_list)
	return page


func _header(parent: Control, text: String, sub: String = "") -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", COLOR_GOLD)
	parent.add_child(label)
	if sub != "":
		_note(parent, sub)


func _note(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", COLOR_MUTED)
	parent.add_child(label)


func _card(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CasinoUI.panel_style(COLOR_PANEL, Color(0.2, 0.35, 0.25), 10, 10))
	parent.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	panel.add_child(inner)
	return inner


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

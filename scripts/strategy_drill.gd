extends Control
## The Strategy Trainer pack: a hand, an upcard, sometimes a count — what's
## the play?
##
## Four modes: Basic (every chart decision), Count (the Illustrious 18 and
## insurance, at counts either side of their index), Weak Spots (the cells
## you miss most) and Blitz (as many as you can in 60 seconds). A right
## answer scores, with a multiplier for a streak; a wrong one stops to show
## the right play, the reason, and the cell on the chart.

const PACK_ID := "strategy_trainer"
const BLITZ_SECONDS := 60.0
const POINTS := 10
## The streak multiplier steps up every this many right answers...
const STREAK_STEP := 5
## ...up to this.
const MAX_MULTIPLIER := 5
const CARD_SIZE := Vector2(80, 112)

const MODES := ["basic", "count", "weak", "blitz"]
const MODE_NAMES := {"basic": "Basic", "count": "Count", "weak": "Weak Spots", "blitz": "Blitz 60s"}
const MODE_HELP := {
	"basic": "Basic strategy: dealer stands on all 17s, double any two cards, double after splitting.",
	"count": "The count changes some plays. These hands sit near an Illustrious 18 index, so watch the true count.",
	"weak": "The hands you get wrong most often, until you stop getting them wrong.",
	"blitz": "Basic strategy against the clock. Wrong answers don't stop you — they just cost the streak.",
}
const PLAYS := ["Hit", "Stand", "Double", "Split"]

const COLOR_FELT := Color(0.05, 0.3, 0.15)
const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_WIN := Color(0.5, 0.92, 0.55)
const COLOR_LOSE := Color(0.96, 0.5, 0.45)
const COLOR_MUTED := Color(0.82, 0.88, 0.82)

var rng := RandomNumberGenerator.new()
var mode := "basic"
var question: Dictionary = {}
var score := 0
var streak := 0
var right := 0
var asked := 0
var blitz_left := 0.0
var blitz_running := false
## Stats key -> [right, asked], kept across sessions for Weak Spots.
var cells: Dictionary = {}

var mode_buttons := {}
var answer_buttons := {}
var help_label: Label
var dealer_box: HBoxContainer
var player_box: HBoxContainer
var count_label: Label
var prompt_label: Label
var feedback_label: Label
var stats_label: Label
var timer_label: Label
var answer_row: HBoxContainer


func _ready() -> void:
	rng.randomize()
	cells = SaveData.get_value("strategy_trainer", "cells", {})
	_build_ui()
	_set_mode("basic")
	if not Store.owns(PACK_ID):
		LockedPack.cover(self, PACK_ID, "res://scenes/blackjack.tscn")


func _process(delta: float) -> void:
	if not blitz_running:
		return
	blitz_left -= delta
	timer_label.text = "%d s" % ceili(maxf(blitz_left, 0.0))
	if blitz_left <= 0.0:
		_end_blitz()


# --- Flow ------------------------------------------------------------------------

func _set_mode(new_mode: String) -> void:
	mode = new_mode
	blitz_running = false
	score = 0
	streak = 0
	right = 0
	asked = 0
	for key in mode_buttons:
		var active: bool = key == mode
		CasinoUI.style_button(mode_buttons[key], Color(0.45, 0.36, 0.1) if active else Color(0.08, 0.2, 0.12),
			18, 12, 8, 8, COLOR_GOLD if active else Color(0, 0, 0, 0))
	help_label.text = MODE_HELP[mode]
	if mode == "weak" and StrategyQuiz.weak_keys(cells).is_empty():
		help_label.text = "No weak spots yet — everything you've been asked, you've got right. These are ordinary hands until you miss one."
	timer_label.visible = mode == "blitz"
	feedback_label.text = ""
	if mode == "blitz":
		blitz_left = BLITZ_SECONDS
		blitz_running = true
	_next_question()


func _next_question() -> void:
	var source := "basic" if mode == "blitz" else mode
	question = StrategyQuiz.make(rng, source, cells)
	_show_question()


func answer(play: String) -> void:
	if question.is_empty():
		return
	if mode == "blitz" and not blitz_running:
		return
	asked += 1
	var correct: bool = play == question.answer
	_record(question.key, correct)
	if correct:
		right += 1
		streak += 1
		score += POINTS * multiplier()
		_save_best("best_streak_" + mode, streak)
		feedback_label.text = "Right — %s. %s" % [String(question.answer).to_upper(), question.reason]
		feedback_label.add_theme_color_override("font_color", COLOR_WIN)
		_update_stats()
		_next_question()
		return

	streak = 0
	_update_stats()
	if mode == "blitz":
		# No stopping the clock: say what it was and move on.
		feedback_label.text = "%s was wrong — it's %s. %s" % [play, String(question.answer).to_upper(), question.reason]
		feedback_label.add_theme_color_override("font_color", COLOR_LOSE)
		_next_question()
		return
	feedback_label.text = ""
	_show_correction(play)


func multiplier() -> int:
	return mini(1 + streak / STREAK_STEP, MAX_MULTIPLIER)


func _end_blitz() -> void:
	blitz_running = false
	timer_label.text = "0 s"
	var best := int(SaveData.get_value("strategy_trainer", "best_blitz", 0))
	var new_best := score > best
	if new_best:
		SaveData.set_value("strategy_trainer", "best_blitz", score)
	var modal := Modal.open(self, "Time!", 560)
	modal.name = "BlitzOver"
	modal.add_text("%d right out of %d, for %d points." % [right, asked, score], 22, Color.WHITE)
	modal.add_text("A new best!" if new_best else "Your best is %d." % best, 18,
		COLOR_GOLD if new_best else COLOR_MUTED)
	modal.add_button("Again", Color(0.16, 0.38, 0.24), _set_mode.bind("blitz"))
	modal.add_button("Done", Color(0.25, 0.22, 0.2), _set_mode.bind("basic"))
	_update_stats()


# --- Records ------------------------------------------------------------------------

func _record(key: String, correct: bool) -> void:
	var record: Array = cells.get(key, [0, 0])
	cells[key] = [int(record[0]) + (1 if correct else 0), int(record[1]) + 1]
	SaveData.set_value("strategy_trainer", "cells", cells)


func _save_best(key: String, value: int) -> void:
	if value > int(SaveData.get_value("strategy_trainer", key, 0)):
		SaveData.set_value("strategy_trainer", key, value)


func _update_stats() -> void:
	var accuracy := "—" if asked == 0 else "%d%%" % roundi(100.0 * right / asked)
	var best_streak := int(SaveData.get_value("strategy_trainer", "best_streak_" + mode, 0))
	var text := "Score %d   ·   Streak %d (x%d)   ·   %d/%d right (%s)   ·   Best streak %d" % [
		score, streak, multiplier(), right, asked, accuracy, best_streak]
	if mode == "blitz":
		text += "   ·   Best Blitz %d" % int(SaveData.get_value("strategy_trainer", "best_blitz", 0))
	stats_label.text = text


# --- Showing a question ---------------------------------------------------------------

func _show_question() -> void:
	_clear(dealer_box)
	_clear(player_box)
	dealer_box.add_child(CardView.make(question.up_card, false, CARD_SIZE))
	dealer_box.add_child(CardView.make({}, true, CARD_SIZE))
	for card in question.hand:
		player_box.add_child(CardView.make(card, false, CARD_SIZE))

	var has_count: bool = question.has("true_count")
	count_label.visible = has_count
	if has_count:
		count_label.text = "TRUE COUNT  %s" % BlackjackStrategy._signed(question.true_count)

	var up := BlackjackStrategy.up_label(int(question.up))
	if question.kind == "insurance":
		prompt_label.text = "The dealer shows an ace. Insurance?"
	else:
		var notes: PackedStringArray = []
		if not question.can_double:
			notes.append("no doubling on three cards")
		var tail := "" if notes.is_empty() else "  (%s)" % ", ".join(notes)
		prompt_label.text = "%s against %s — your play?%s" % [
			StrategyQuiz.describe(question.hand, question.can_split), up, tail]

	_clear(answer_row)
	answer_buttons.clear()
	var plays: Array = ["Insure", "Decline"] if question.kind == "insurance" else PLAYS
	for play in plays:
		var button := Button.new()
		button.text = play
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(190, 64)
		CasinoUI.style_button(button, _play_colour(play), 24, 14, 10, 10, COLOR_GOLD)
		button.pressed.connect(answer.bind(play))
		if play == "Double":
			button.disabled = not question.can_double
		elif play == "Split":
			button.disabled = not question.can_split
		answer_row.add_child(button)
		answer_buttons[play] = button
	_update_stats()


## A wrong answer stops for the explanation, with the chart cell picked out.
func _show_correction(play: String) -> Modal:
	var modal := Modal.open(self, "Not quite", 900)
	modal.name = "Correction"
	modal.add_text("You chose %s. The play is %s." % [play.to_upper(), String(question.answer).to_upper()],
		22, Color.WHITE)
	modal.add_text(question.reason, 17, COLOR_MUTED)
	var chart := StrategyChart.new(true)
	chart.table = question.table
	modal.content.add_child(chart)
	chart.highlight(question.table, question.row, 0 if question.table == "count" else int(question.up))
	modal.add_button("Next hand", Color(0.16, 0.38, 0.24), _next_question)
	return modal


func _play_colour(play: String) -> Color:
	match play:
		"Hit":
			return StrategyChart.CODE_COLOURS.H.darkened(0.15)
		"Stand", "Decline":
			return StrategyChart.CODE_COLOURS.S.darkened(0.3)
		"Double":
			return StrategyChart.CODE_COLOURS.D.darkened(0.15)
	return StrategyChart.CODE_COLOURS.P.darkened(0.15)


func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


# --- Building ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_FELT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := SafeArea.create(18)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var top := HBoxContainer.new()
	column.add_child(top)
	var back := Button.new()
	back.text = "< Back"
	back.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(back, Color(0.09, 0.2, 0.13), 18, 14, 8)
	back.pressed.connect(_on_back_pressed)
	top.add_child(back)
	var title := Label.new()
	title.text = "STRATEGY TRAINER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	top.add_child(title)
	var charts := Button.new()
	charts.text = "Charts"
	charts.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(charts, Color(0.2, 0.3, 0.55), 18, 14, 8)
	charts.pressed.connect(_on_charts_pressed)
	top.add_child(charts)

	var modes := HBoxContainer.new()
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	modes.add_theme_constant_override("separation", 10)
	column.add_child(modes)
	for key in MODES:
		var button := Button.new()
		button.text = MODE_NAMES[key]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(170, 44)
		button.pressed.connect(_set_mode.bind(key))
		modes.add_child(button)
		mode_buttons[key] = button
	timer_label = Label.new()
	timer_label.custom_minimum_size = Vector2(80, 0)
	timer_label.add_theme_font_size_override("font_size", 26)
	timer_label.add_theme_color_override("font_color", COLOR_GOLD)
	modes.add_child(timer_label)

	help_label = Label.new()
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.add_theme_font_size_override("font_size", 16)
	help_label.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(help_label)

	# The hand: dealer above, you below, the count beside them.
	var table := HBoxContainer.new()
	table.alignment = BoxContainer.ALIGNMENT_CENTER
	table.add_theme_constant_override("separation", 60)
	column.add_child(table)
	var hands := VBoxContainer.new()
	hands.add_theme_constant_override("separation", 6)
	table.add_child(hands)
	hands.add_child(_caption("DEALER"))
	dealer_box = HBoxContainer.new()
	dealer_box.alignment = BoxContainer.ALIGNMENT_CENTER
	dealer_box.add_theme_constant_override("separation", 8)
	hands.add_child(dealer_box)
	hands.add_child(_caption("YOU"))
	player_box = HBoxContainer.new()
	player_box.alignment = BoxContainer.ALIGNMENT_CENTER
	player_box.add_theme_constant_override("separation", 8)
	player_box.custom_minimum_size = Vector2(3 * CARD_SIZE.x + 16, CARD_SIZE.y)
	hands.add_child(player_box)
	count_label = Label.new()
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count_label.add_theme_font_size_override("font_size", 30)
	count_label.add_theme_color_override("font_color", COLOR_GOLD)
	var count_box := StyleBoxFlat.new()
	count_box.bg_color = Color(0.03, 0.18, 0.09)
	count_box.border_color = COLOR_GOLD
	count_box.set_border_width_all(2)
	count_box.set_corner_radius_all(10)
	count_box.content_margin_left = 18
	count_box.content_margin_right = 18
	count_box.content_margin_top = 10
	count_box.content_margin_bottom = 10
	count_label.add_theme_stylebox_override("normal", count_box)
	table.add_child(count_label)

	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 24)
	prompt_label.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(prompt_label)

	answer_row = HBoxContainer.new()
	answer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	answer_row.add_theme_constant_override("separation", 14)
	column.add_child(answer_row)

	feedback_label = Label.new()
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.custom_minimum_size = Vector2(0, 44)
	feedback_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feedback_label.add_theme_font_size_override("font_size", 16)
	column.add_child(feedback_label)

	stats_label = Label.new()
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 16)
	stats_label.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(stats_label)


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", COLOR_MUTED)
	return label


func _on_charts_pressed() -> void:
	var modal := Modal.open(self, "Strategy Charts", 900)
	modal.content.add_child(StrategyChart.new(true))
	modal.add_button("Close", Color(0.25, 0.22, 0.2))


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/blackjack.tscn")

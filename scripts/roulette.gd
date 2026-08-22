extends Control
## European roulette: place chips on the board, spin the wheel, get paid.
## Straight bets pay 35:1, dozens/columns 2:1, even-money bets 1:1.

const CHIP_VALUES := [1, 5, 25, 100, 500]
const CELL := Vector2(50, 46)

const SPIN_TIME := 4.2
const SPIN_TURNS := 5.0
## Repeat mode spins much faster, so a long losing streak doesn't take all
## night to play out.
const REPEAT_SPIN_TIME := 0.8
const REPEAT_SPIN_TURNS := 2.0
## A beat between spins so the result stays readable.
const REPEAT_PAUSE := 0.3
## Safety valve: a cold streak on a small bet could otherwise run for
## thousands of spins unattended.
const MAX_REPEAT_SPINS := 250

const COLOR_BG := Color(0.04, 0.2, 0.11)
const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_WIN := Color(0.5, 0.92, 0.55)
const COLOR_LOSE := Color(0.96, 0.5, 0.45)
const COLOR_RED := Color(0.72, 0.11, 0.15)
const COLOR_BLACK := Color(0.09, 0.09, 0.11)
const COLOR_GREEN := Color(0.05, 0.42, 0.2)
const COLOR_OUTSIDE := Color(0.07, 0.3, 0.16)

var selected_chip := 5
var spinning := false
## Chips on the table. Each area's meta carries the numbers it covers and
## what it pays.
var board := BetBoard.new()
var history: Array = []

## Repeat-until-win state. `repeat_template` is the layout (key -> amount)
## re-staked before every spin of a run.
var repeat_mode := false
var repeat_stop := false
var repeat_template := {}

var wheel: RouletteWheel
var balance_label: Label
var total_bet_label: Label
var message_label: Label
var result_label: Label
var history_box: HBoxContainer
var back_button: Button
var spin_button: Button
var repeat_button: Button
var clear_button: Button


func _ready() -> void:
	_build_ui()
	Bank.balance_changed.connect(_on_balance_changed)
	_on_balance_changed(Bank.balance)
	_update_totals()
	_set_message("Pick a chip and place your bets.", Color.WHITE)


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := SafeArea.create(18)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Top bar.
	var top_bar := HBoxContainer.new()
	vbox.add_child(top_bar)

	back_button = Button.new()
	back_button.text = "< Back"
	back_button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(back_button, Color(0.1, 0.18, 0.12), 18, 14, 8)
	back_button.pressed.connect(_on_back_pressed)
	top_bar.add_child(back_button)

	var title := Label.new()
	title.text = "ROULETTE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	top_bar.add_child(title)

	balance_label = Label.new()
	balance_label.add_theme_font_size_override("font_size", 22)
	balance_label.add_theme_color_override("font_color", Color.WHITE)
	top_bar.add_child(balance_label)

	# Content: wheel on the left, board on the right.
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content)

	content.add_child(_build_wheel_panel())
	content.add_child(_build_board_panel())


func _build_wheel_panel() -> Control:
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	# Centred vertically so a taller-than-design screen (a 4:3 tablet gives
	# 1280x960) doesn't strand the table against the top edge.
	left.alignment = BoxContainer.ALIGNMENT_CENTER

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(420, 420)
	left.add_child(holder)

	wheel = RouletteWheel.new()
	wheel.position = Vector2(10, 10)
	wheel.size = Vector2(400, 400)
	wheel.pivot_offset = Vector2(200, 200)
	holder.add_child(wheel)

	var pointer := WheelPointer.new()
	pointer.set_anchors_preset(Control.PRESET_FULL_RECT)
	pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pointer)

	result_label = Label.new()
	result_label.text = "Ready to spin"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 24)
	result_label.add_theme_color_override("font_color", COLOR_GOLD)
	left.add_child(result_label)

	var history_title := Label.new()
	history_title.text = "Recent numbers"
	history_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	history_title.add_theme_font_size_override("font_size", 15)
	history_title.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8))
	left.add_child(history_title)

	var history_center := CenterContainer.new()
	left.add_child(history_center)
	history_box = HBoxContainer.new()
	history_box.add_theme_constant_override("separation", 5)
	history_center.add_child(history_box)

	return left


func _build_board_panel() -> Control:
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER

	var board_panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.26, 0.13)
	panel_style.set_corner_radius_all(12)
	panel_style.border_color = COLOR_GOLD
	panel_style.set_border_width_all(2)
	panel_style.content_margin_left = 14
	panel_style.content_margin_right = 14
	panel_style.content_margin_top = 14
	panel_style.content_margin_bottom = 14
	board_panel.add_theme_stylebox_override("panel", panel_style)
	right.add_child(board_panel)

	# Centred so a wider-than-design viewport doesn't strand the board on the
	# left of its panel.
	var board_center := CenterContainer.new()
	board_panel.add_child(board_center)

	var board := VBoxContainer.new()
	board.add_theme_constant_override("separation", 4)
	board_center.add_child(board)
	_build_board(board)

	# Chip selector.
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	right.add_child(chip_row)

	var chip_label := Label.new()
	chip_label.text = "Chip:"
	chip_label.add_theme_font_size_override("font_size", 20)
	chip_label.add_theme_color_override("font_color", Color.WHITE)
	chip_row.add_child(chip_label)

	var chip_group := ButtonGroup.new()
	for value in CHIP_VALUES:
		var chip := Button.new()
		chip.text = "$%d" % value
		chip.toggle_mode = true
		chip.button_group = chip_group
		chip.custom_minimum_size = Vector2(76, 44)
		chip.focus_mode = Control.FOCUS_NONE
		CasinoUI.style_button(chip, Color(0.13, 0.13, 0.16), 18, 6, 6, 22)
		var pressed_style := StyleBoxFlat.new()
		pressed_style.bg_color = COLOR_GOLD
		pressed_style.set_corner_radius_all(22)
		pressed_style.content_margin_left = 6
		pressed_style.content_margin_right = 6
		pressed_style.content_margin_top = 6
		pressed_style.content_margin_bottom = 6
		chip.add_theme_stylebox_override("pressed", pressed_style)
		chip.add_theme_color_override("font_pressed_color", Color(0.15, 0.1, 0.0))
		chip.toggled.connect(func(is_pressed: bool) -> void:
			if is_pressed:
				selected_chip = value)
		if value == selected_chip:
			chip.button_pressed = true
		chip_row.add_child(chip)

	# Spin / clear + totals.
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	right.add_child(action_row)

	spin_button = Button.new()
	spin_button.text = "SPIN"
	spin_button.custom_minimum_size = Vector2(170, 54)
	spin_button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(spin_button, Color(0.72, 0.55, 0.1), 24, 18, 10)
	spin_button.pressed.connect(_on_spin_pressed)
	action_row.add_child(spin_button)

	repeat_button = Button.new()
	repeat_button.text = "Repeat Until Win"
	repeat_button.custom_minimum_size = Vector2(196, 54)
	repeat_button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(repeat_button, Color(0.42, 0.24, 0.52), 18, 10, 10)
	repeat_button.pressed.connect(_on_repeat_pressed)
	action_row.add_child(repeat_button)

	clear_button = Button.new()
	clear_button.text = "Clear Bets"
	clear_button.custom_minimum_size = Vector2(140, 54)
	clear_button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(clear_button, Color(0.35, 0.3, 0.25), 20, 14, 10)
	clear_button.pressed.connect(_on_clear_pressed)
	action_row.add_child(clear_button)

	total_bet_label = Label.new()
	total_bet_label.add_theme_font_size_override("font_size", 22)
	total_bet_label.add_theme_color_override("font_color", COLOR_GOLD)
	total_bet_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action_row.add_child(total_bet_label)

	message_label = Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(0, 56)
	message_label.add_theme_font_size_override("font_size", 22)
	right.add_child(message_label)

	return right


func _build_board(board: VBoxContainer) -> void:
	# Main strip: zero, the 12x3 number grid, and column bets.
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	board.add_child(strip)

	strip.add_child(_make_bet_button(
		"straight_0", "0", [0], 35, COLOR_GREEN,
		Vector2(CELL.x, CELL.y * 3 + 8), 20))

	var grid := GridContainer.new()
	grid.columns = 12
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	strip.add_child(grid)

	for row in 3:
		for col in 12:
			var n := (col + 1) * 3 - row
			var cell_color := COLOR_RED if n in RouletteWheel.RED_NUMBERS else COLOR_BLACK
			grid.add_child(_make_bet_button(
				"straight_%d" % n, str(n), [n], 35, cell_color, CELL, 16))

	var column_box := VBoxContainer.new()
	column_box.add_theme_constant_override("separation", 4)
	strip.add_child(column_box)

	for row in 3:
		var numbers: Array = []
		for col in 12:
			numbers.append((col + 1) * 3 - row)
		column_box.add_child(_make_bet_button(
			"column_%d" % row, "2:1", numbers, 2, COLOR_OUTSIDE,
			Vector2(56, CELL.y), 14))

	# Dozens.
	var dozen_row := HBoxContainer.new()
	dozen_row.add_theme_constant_override("separation", 4)
	board.add_child(dozen_row)
	dozen_row.add_child(_make_row_spacer())

	var dozen_labels := ["1st 12", "2nd 12", "3rd 12"]
	for i in 3:
		var numbers: Array = []
		for n in range(i * 12 + 1, i * 12 + 13):
			numbers.append(n)
		dozen_row.add_child(_make_bet_button(
			"dozen_%d" % i, dozen_labels[i], numbers, 2, COLOR_OUTSIDE,
			Vector2(212, 40), 15))

	# Even-money bets.
	var outside_row := HBoxContainer.new()
	outside_row.add_theme_constant_override("separation", 4)
	board.add_child(outside_row)
	outside_row.add_child(_make_row_spacer())

	var reds: Array = RouletteWheel.RED_NUMBERS.duplicate()
	var blacks: Array = []
	var evens: Array = []
	var odds: Array = []
	var lows: Array = []
	var highs: Array = []
	for n in range(1, 37):
		if not n in RouletteWheel.RED_NUMBERS:
			blacks.append(n)
		if n % 2 == 0:
			evens.append(n)
		else:
			odds.append(n)
		if n <= 18:
			lows.append(n)
		else:
			highs.append(n)

	var outside_size := Vector2(104, 40)
	outside_row.add_child(_make_bet_button("low", "1-18", lows, 1, COLOR_OUTSIDE, outside_size, 15))
	outside_row.add_child(_make_bet_button("even", "EVEN", evens, 1, COLOR_OUTSIDE, outside_size, 15))
	outside_row.add_child(_make_bet_button("red", "RED", reds, 1, COLOR_RED, outside_size, 15))
	outside_row.add_child(_make_bet_button("black", "BLACK", blacks, 1, COLOR_BLACK, outside_size, 15))
	outside_row.add_child(_make_bet_button("odd", "ODD", odds, 1, COLOR_OUTSIDE, outside_size, 15))
	outside_row.add_child(_make_bet_button("high", "19-36", highs, 1, COLOR_OUTSIDE, outside_size, 15))


func _make_row_spacer() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(CELL.x, 0)
	return spacer


func _make_bet_button(key: String, text: String, numbers: Array, payout: int, color: Color, min_size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(button, color, font_size, 2, 2, 6)
	button.pressed.connect(_on_bet_button_pressed.bind(key))
	board.add(key, button, {"numbers": numbers, "payout": payout})
	return button


# --- Betting -----------------------------------------------------------------

func _on_bet_button_pressed(key: String) -> void:
	if repeat_mode:
		_set_message("Repeat is running — press Stop Repeating to change the bet.", COLOR_GOLD)
		return
	if spinning:
		return
	if not board.place(key, selected_chip):
		_set_message("Not enough balance for a $%d chip." % selected_chip, COLOR_LOSE)
		return
	_update_totals()
	_set_message("Bet placed. Spin when ready.", Color.WHITE)


func _on_clear_pressed() -> void:
	if _busy():
		return
	if board.refund_all() > 0:
		_set_message("Bets cleared and refunded.", Color.WHITE)
	_update_totals()


func _total_bet() -> int:
	return board.total()


func _update_totals() -> void:
	total_bet_label.text = "Total bet: $%s" % Bank.fmt(_total_bet())


# --- Spinning ----------------------------------------------------------------

func _busy() -> bool:
	return spinning or repeat_mode


## Locks the controls a spin shouldn't be interrupted by. The repeat button
## stays live during a run so it can be stopped.
func _lock_controls(locked: bool) -> void:
	spin_button.disabled = locked
	clear_button.disabled = locked
	back_button.disabled = locked
	repeat_button.disabled = locked and not repeat_mode


func _on_spin_pressed() -> void:
	if _busy():
		return
	if _total_bet() == 0:
		_set_message("Place a bet before spinning.", COLOR_GOLD)
		return
	spinning = true
	_lock_controls(true)
	_set_message("No more bets…", Color.WHITE)

	var number := await _spin_wheel(SPIN_TIME, SPIN_TURNS)
	_resolve_spin(number)

	spinning = false
	_lock_controls(false)


## Spins the wheel to a random pocket and returns the winning number.
func _spin_wheel(duration: float, turns: float) -> int:
	wheel.result_index = -1
	wheel.queue_redraw()

	var pocket := randi() % 37
	var number: int = RouletteWheel.WHEEL_ORDER[pocket]
	var step := TAU / 37.0
	var current := fposmod(wheel.rotation, TAU)
	wheel.rotation = current
	# The pocket lands under the top pointer when rotation == -pocket * step.
	var target := fposmod(-pocket * step, TAU)
	var travel := fposmod(target - current, TAU) + TAU * turns
	var tween := create_tween()
	tween.tween_property(wheel, "rotation", current + travel, duration) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await tween.finished

	wheel.result_index = pocket
	wheel.queue_redraw()
	return number


## Re-stakes the saved layout for another spin. Returns false when the bank
## can't cover it, leaving the balance untouched.
func _replace_bets() -> bool:
	var needed := 0
	for key in repeat_template:
		needed += int(repeat_template[key])
	if needed <= 0 or not Bank.withdraw(needed):
		return false
	for key in repeat_template:
		board.move_in(key, int(repeat_template[key]))
	_update_totals()
	return true


## Re-stakes and re-spins the same bet until it turns a profit on a single
## spin, the bank runs dry, or the player stops it.
func _on_repeat_pressed() -> void:
	if repeat_mode:
		repeat_stop = true
		repeat_button.text = "Stopping…"
		return
	if spinning:
		return
	if _total_bet() == 0:
		_set_message("Place the bet you want repeated first.", COLOR_GOLD)
		return

	repeat_template.clear()
	for key in board.staked_keys():
		repeat_template[key] = board.amount(key)

	repeat_mode = true
	repeat_stop = false
	repeat_button.text = "Stop Repeating"
	_lock_controls(true)

	var spins := 0
	var run_net := 0
	while true:
		spins += 1
		_set_message("Repeat spin %d — no more bets…" % spins, Color.WHITE)
		var number := await _spin_wheel(REPEAT_SPIN_TIME, REPEAT_SPIN_TURNS)
		var net := _resolve_spin(number)
		run_net += net

		if net > 0:
			_set_message("%d %s pays $%s — won on spin %d.%s" % [
				number, _number_color_name(number), Bank.fmt(net), spins,
				_run_summary(run_net)], COLOR_WIN)
			break
		if repeat_stop:
			_set_message("Stopped after %d spins.%s" % [spins, _run_summary(run_net)], COLOR_GOLD)
			break
		if spins >= MAX_REPEAT_SPINS:
			_set_message("Paused after %d spins with no win — press Repeat Until Win to carry on.%s" % [
				spins, _run_summary(run_net)], COLOR_GOLD)
			break
		if not _replace_bets():
			_set_message("Not enough left to repeat that bet — stopped after %d spins.%s" % [
				spins, _run_summary(run_net)], COLOR_LOSE)
			break
		await get_tree().create_timer(REPEAT_PAUSE).timeout

	repeat_mode = false
	repeat_stop = false
	repeat_button.text = "Repeat Until Win"
	_lock_controls(false)


## Winning the last spin doesn't mean the run made money, so say where it
## actually ended up.
func _run_summary(run_net: int) -> String:
	if run_net > 0:
		return " Up $%s over the run." % Bank.fmt(run_net)
	if run_net < 0:
		return " Down $%s over the run." % Bank.fmt(-run_net)
	return " Break-even over the run."


## Pays out the winning bets, clears the board, and returns the spin's net.
func _resolve_spin(number: int) -> int:
	var staked := _total_bet()
	var returned := 0
	for key in board.staked_keys():
		var meta := board.meta(key)
		if number in meta.numbers:
			returned += board.amount(key) * (int(meta.payout) + 1)
	if returned > 0:
		Bank.deposit(returned)

	var color_name := _number_color_name(number)
	result_label.text = "%d %s" % [number, color_name]
	_add_history(number)

	var net := returned - staked
	if net > 0:
		_set_message("Ball lands on %d %s — you win $%s!" % [number, color_name, Bank.fmt(net)], COLOR_WIN)
	elif net == 0:
		_set_message("Ball lands on %d %s — you break even." % [number, color_name], COLOR_GOLD)
	else:
		_set_message("Ball lands on %d %s — you lose $%s." % [number, color_name, Bank.fmt(-net)], COLOR_LOSE)

	# The stakes were taken when the chips went down, so the board just
	# clears rather than refunding.
	board.clear_all()
	_update_totals()
	return net


func _add_history(number: int) -> void:
	history.push_front(number)
	if history.size() > 10:
		history.resize(10)
	for child in history_box.get_children():
		history_box.remove_child(child)
		child.queue_free()
	for n in history:
		var chip := Label.new()
		chip.text = str(n)
		chip.custom_minimum_size = Vector2(34, 30)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = _number_color(n)
		sb.set_corner_radius_all(6)
		chip.add_theme_stylebox_override("normal", sb)
		chip.add_theme_color_override("font_color", Color.WHITE)
		chip.add_theme_font_size_override("font_size", 14)
		history_box.add_child(chip)


# --- Helpers -----------------------------------------------------------------

func _number_color(number: int) -> Color:
	if number == 0:
		return COLOR_GREEN
	if number in RouletteWheel.RED_NUMBERS:
		return COLOR_RED
	return COLOR_BLACK


func _number_color_name(number: int) -> String:
	if number == 0:
		return "Green"
	if number in RouletteWheel.RED_NUMBERS:
		return "Red"
	return "Black"


func _set_message(text: String, color: Color) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", color)


func _on_balance_changed(new_balance: int) -> void:
	balance_label.text = "Balance: $%s" % Bank.fmt(new_balance)


func _on_back_pressed() -> void:
	if _busy():
		return
	# Refund anything still on the table before leaving.
	board.refund_all()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## Fixed gold triangle above the wheel marking the winning pocket.
class WheelPointer:
	extends Control

	func _draw() -> void:
		var cx := size.x / 2.0
		var points := PackedVector2Array([
			Vector2(cx - 13, 0),
			Vector2(cx + 13, 0),
			Vector2(cx, 28),
		])
		draw_colored_polygon(points, Color(0.94, 0.78, 0.29))

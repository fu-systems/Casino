class_name PositionPicker
extends RefCounted
## Picks bets for the Systems Lab: one bet, or several (for "several bets
## together"). Roulette gets a miniature board laid out like the table's;
## other games get their bets in labelled groups. Optional extra choices —
## things that can happen rather than bets — go underneath.

const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_CHOSEN := Color(0.62, 0.48, 0.12)
const CELL := Vector2(46, 36)


## Opens the picker. `on_done` gets an Array of chosen keys (one for a
## single pick, as soon as it's tapped).
static func open(parent: Node, game: String, multi: bool, chosen: Array, on_done: Callable,
		extras: Array = []) -> Modal:
	var modal := Modal.open(parent, "Choose bets" if multi else "Choose a bet", 1100)
	modal.name = "Picker"
	var picked: Array = chosen.duplicate()
	var buttons := {}

	var refresh := func() -> void:
		for key in buttons:
			var on: bool = key in picked
			var button: Button = buttons[key]
			CasinoUI.style_button(button, COLOR_CHOSEN if on else button.get_meta("colour"),
				int(button.get_meta("font")), 2, 2, 6, COLOR_GOLD if on else Color(0, 0, 0, 0))

	var tap := func(key: String) -> void:
		if not multi:
			on_done.call([key])
			modal.close()
			return
		if key in picked:
			picked.erase(key)
		else:
			picked.append(key)
		refresh.call()

	if game == "roulette":
		_roulette_board(modal.content, buttons, tap)
	else:
		_grouped(modal.content, SystemModel.positions(game), buttons, tap)
	if not extras.is_empty():
		var label := Label.new()
		label.text = "Or something that happens:"
		label.add_theme_font_size_override("font_size", 16)
		modal.content.add_child(label)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		modal.content.add_child(flow)
		for entry in extras:
			flow.add_child(_button(entry[0], entry[1], Color(0.25, 0.22, 0.32), Vector2(150, 40), 15, buttons, tap))
	refresh.call()

	if multi:
		modal.add_button("Done", Color(0.16, 0.38, 0.24), func() -> void: on_done.call(picked))
	modal.add_button("Cancel", Color(0.25, 0.22, 0.2))
	return modal


static func _roulette_board(parent: Control, buttons: Dictionary, tap: Callable) -> void:
	var holder := CenterContainer.new()
	parent.add_child(holder)
	var board := VBoxContainer.new()
	board.add_theme_constant_override("separation", 3)
	holder.add_child(board)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 3)
	board.add_child(strip)
	strip.add_child(_button("straight_0", "0", Color(0.05, 0.42, 0.2), Vector2(CELL.x, CELL.y * 3 + 6), 16, buttons, tap))
	var grid := GridContainer.new()
	grid.columns = 12
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	strip.add_child(grid)
	for row in 3:
		for col in 12:
			var n := (col + 1) * 3 - row
			var colour := Color(0.72, 0.11, 0.15) if n in RouletteWheel.RED_NUMBERS else Color(0.09, 0.09, 0.11)
			grid.add_child(_button("straight_%d" % n, str(n), colour, CELL, 15, buttons, tap))
	var columns := VBoxContainer.new()
	columns.add_theme_constant_override("separation", 3)
	strip.add_child(columns)
	for row in 3:
		columns.add_child(_button("column_%d" % row, "2:1", Color(0.07, 0.3, 0.16), Vector2(52, CELL.y), 13, buttons, tap))

	var outside := Color(0.07, 0.3, 0.16)
	var dozens := HBoxContainer.new()
	dozens.add_theme_constant_override("separation", 3)
	board.add_child(dozens)
	dozens.add_child(_spacer())
	for i in 3:
		dozens.add_child(_button("dozen_%d" % i, RouletteBets.label("dozen_%d" % i), outside, Vector2(CELL.x * 4 + 9, 34), 14, buttons, tap))
	var evens := HBoxContainer.new()
	evens.add_theme_constant_override("separation", 3)
	board.add_child(evens)
	evens.add_child(_spacer())
	for key in ["low", "even", "red", "black", "odd", "high"]:
		var colour := outside
		if key == "red":
			colour = Color(0.72, 0.11, 0.15)
		elif key == "black":
			colour = Color(0.09, 0.09, 0.11)
		evens.add_child(_button(key, RouletteBets.label(key), colour, Vector2(CELL.x * 2 + 3, 34), 14, buttons, tap))


static func _grouped(parent: Control, positions: Array, buttons: Dictionary, tap: Callable) -> void:
	var groups := {}
	for entry in positions:
		if not groups.has(entry.group):
			groups[entry.group] = []
		groups[entry.group].append(entry)
	for group in groups:
		var label := Label.new()
		label.text = group
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", COLOR_GOLD)
		parent.add_child(label)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		parent.add_child(flow)
		for entry in groups[group]:
			flow.add_child(_button(entry.key, entry.label, Color(0.1, 0.24, 0.16), Vector2(130, 40), 15, buttons, tap))


static func _button(key: String, text: String, colour: Color, size: Vector2, font: int,
		buttons: Dictionary, tap: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("colour", colour)
	button.set_meta("font", font)
	button.pressed.connect(tap.bind(key))
	buttons[key] = button
	return button


static func _spacer() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(CELL.x, 0)
	return spacer

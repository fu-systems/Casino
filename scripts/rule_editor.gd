class_name RuleEditor
extends RefCounted
## The forms behind the Systems Lab's IF and THEN cards: one for a condition
## (which can hold other conditions, two levels deep) and one for a list of
## actions. Everything is a dropdown, a stepper or a bet picker — nothing to
## type but numbers — so it works with a thumb.

const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_MUTED := Color(0.78, 0.85, 0.78)
const COLOR_FIELD := Color(0.1, 0.22, 0.15)
## Conditions nest at most this deep: "all of (any of (...))".
const MAX_DEPTH := 2


# --- Conditions ------------------------------------------------------------------------

static func edit_condition(parent: Node, system: Dictionary, cond: Dictionary, on_done: Callable,
		depth: int = 0) -> Modal:
	var game := String(system.game)
	var draft: Dictionary = cond.duplicate(true)
	if draft.is_empty():
		draft = {"type": "round", "result": "lost"}
	var modal := Modal.open(parent, "IF…", 860)
	modal.name = "ConditionEditor"
	var summary := modal.add_text("", 18, COLOR_GOLD)
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 10)

	var refresh := func() -> void:
		summary.text = "IF " + SystemModel.describe_condition(draft, game)

	var types: Array = []
	for key in SystemModel.CONDITIONS:
		if key in ["and", "or", "not"] and depth >= MAX_DEPTH:
			continue
		types.append(key)
	var type_row := _row(modal.content, "Check")
	var type_pick := _options(type_row, types.map(func(k: String) -> String: return SystemModel.CONDITIONS[k]),
		types.find(String(draft.type)))
	modal.content.add_child(fields)

	var rebuild := func() -> void:
		for child in fields.get_children():
			fields.remove_child(child)
			child.queue_free()
		_condition_fields(parent, fields, system, draft, depth, refresh)
		refresh.call()
	# The draft is changed in place, never replaced: every handler here holds
	# the same Dictionary.
	type_pick.item_selected.connect(func(index: int) -> void:
		draft.clear()
		draft.merge(_blank_condition(String(types[index]), game))
		rebuild.call())
	rebuild.call()

	modal.add_button("Done", Color(0.16, 0.38, 0.24), func() -> void: on_done.call(draft))
	modal.add_button("Cancel", Color(0.25, 0.22, 0.2))
	return modal


static func _blank_condition(kind: String, game: String) -> Dictionary:
	var first: String = SystemModel.positions(game)[0].key if game == "craps" else "red"
	match kind:
		"round":
			return {"type": "round", "result": "lost"}
		"wins", "loses":
			return {"type": kind, "pos": first}
		"group":
			return {"type": "group", "mode": "all", "n": 1, "positions": []}
		"event":
			return {"type": "event", "event": SystemModel.events(game)[0][0]}
		"pattern":
			return {"type": "pattern", "what": first, "mode": "hit", "n": 3}
		"compare":
			return {"type": "compare", "var": "loss_streak", "op": ">=", "value": 3}
		"and", "or":
			return {"type": kind, "items": []}
		"not":
			return {"type": "not", "item": {"type": "round", "result": "won"}}
	return {"type": "always"}


static func _condition_fields(parent: Node, fields: VBoxContainer, system: Dictionary, draft: Dictionary,
		depth: int, refresh: Callable) -> void:
	var game := String(system.game)
	match String(draft.type):
		"round":
			var keys: Array = SystemModel.ROUND_RESULTS.keys()
			var pick := _options(_row(fields, "The round"),
				keys.map(func(k: String) -> String: return SystemModel.ROUND_RESULTS[k]), keys.find(draft.result))
			pick.item_selected.connect(func(i: int) -> void:
				draft.result = keys[i]
				refresh.call())
		"wins", "loses":
			_bet_button(parent, _row(fields, "Bet"), system, draft, "pos", refresh)
		"group":
			var modes: Array = SystemModel.GROUP_MODES.keys()
			var row := _row(fields, "How many")
			var n_box := _stepper(null, int(draft.get("n", 1)), 0, 12, func(v: int) -> void:
				draft.n = v
				refresh.call())
			var pick := _options(row, modes.map(func(k: String) -> String: return SystemModel.GROUP_MODES[k]),
				modes.find(draft.mode))
			row.add_child(n_box)
			n_box.visible = draft.mode in ["exactly", "at_least"]
			pick.item_selected.connect(func(i: int) -> void:
				draft.mode = modes[i]
				n_box.visible = draft.mode in ["exactly", "at_least"]
				refresh.call())
			var bets_row := _row(fields, "Of these bets")
			var bets := _field_button(bets_row, _names(game, draft.positions))
			bets.pressed.connect(func() -> void:
				PositionPicker.open(parent, game, true, draft.positions, func(keys: Array) -> void:
					draft.positions = keys
					bets.text = _names(game, keys)
					refresh.call()))
		"event":
			var events: Array = SystemModel.events(game)
			var pick := _options(_row(fields, "When"), events.map(func(e: Array) -> String: return e[1]),
				events.map(func(e: Array) -> String: return e[0]).find(draft.event))
			pick.item_selected.connect(func(i: int) -> void:
				draft.event = events[i][0]
				refresh.call())
		"pattern":
			var modes := ["hit", "missed"]
			var pick := _options(_row(fields, "Has"), ["come up every time", "not come up at all"], modes.find(draft.mode))
			pick.item_selected.connect(func(i: int) -> void:
				draft.mode = modes[i]
				refresh.call())
			_bet_button(parent, _row(fields, "What"), system, draft, "what", refresh, SystemModel.events(game))
			_stepper(_row(fields, "Over the last"), int(draft.n), 1, 50, func(v: int) -> void:
				draft.n = v
				refresh.call())
		"compare":
			var row := _row(fields, "Compare")
			var names := SystemModel.compare_vars(game)
			var vars: Array = names.keys()
			var var_pick := _options(row, vars.map(func(k: String) -> String: return names[k]),
				vars.find(draft.var))
			var_pick.item_selected.connect(func(i: int) -> void:
				draft.var = vars[i]
				refresh.call())
			var op_pick := _options(row, SystemModel.OPS.map(func(k: String) -> String: return SystemModel.OP_SIGNS[k]),
				SystemModel.OPS.find(draft.op))
			op_pick.item_selected.connect(func(i: int) -> void:
				draft.op = SystemModel.OPS[i]
				refresh.call())
			_number_box(row, float(draft.value), -10000000, 10000000, 1, func(v: float) -> void:
				draft.value = v
				refresh.call())
		"and", "or":
			var list := VBoxContainer.new()
			list.add_theme_constant_override("separation", 6)
			fields.add_child(list)
			# Held in a Dictionary so the redraw can call itself; emptied when
			# the list goes, or the closure and the Dictionary keep each
			# other alive.
			var fn := {}
			list.tree_exiting.connect(func() -> void: fn.clear())
			fn.redraw = func() -> void:
				for child in list.get_children():
					list.remove_child(child)
					child.queue_free()
				for i in draft.items.size():
					var item_row := HBoxContainer.new()
					item_row.add_theme_constant_override("separation", 8)
					list.add_child(item_row)
					var text := Label.new()
					text.text = SystemModel.describe_condition(draft.items[i], game)
					text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					text.add_theme_font_size_override("font_size", 16)
					item_row.add_child(text)
					_small(item_row, "Edit", func() -> void:
						edit_condition(parent, system, draft.items[i], func(c: Dictionary) -> void:
							draft.items[i] = c
							fn.redraw.call()
							refresh.call(), depth + 1))
					_small(item_row, "✕", func() -> void:
						draft.items.remove_at(i)
						fn.redraw.call()
						refresh.call())
				_small(list, "+ Add a condition", func() -> void:
					edit_condition(parent, system, {}, func(c: Dictionary) -> void:
						draft.items.append(c)
						fn.redraw.call()
						refresh.call(), depth + 1))
			fn.redraw.call()
		"not":
			var row := _row(fields, "Not")
			var text := _field_button(row, SystemModel.describe_condition(draft.item, game))
			text.pressed.connect(func() -> void:
				edit_condition(parent, system, draft.item, func(c: Dictionary) -> void:
					draft.item = c
					text.text = SystemModel.describe_condition(c, game)
					refresh.call(), depth + 1))
		_:
			var hint := Label.new()
			hint.text = "This rule always runs when it's reached — handy as a last rule."
			hint.add_theme_color_override("font_color", COLOR_MUTED)
			fields.add_child(hint)


# --- Actions ---------------------------------------------------------------------------

## Edits a list of actions in place of the whole THEN (or OTHERWISE) card.
static func edit_actions(parent: Node, system: Dictionary, actions: Array, on_done: Callable,
		title: String = "THEN…") -> Modal:
	var draft: Array = actions.duplicate(true)
	var modal := Modal.open(parent, title, 860)
	modal.name = "ActionsEditor"
	var hint := modal.add_text("Actions run in order, top to bottom.", 15, COLOR_MUTED)
	hint.name = "Hint"
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	modal.content.add_child(list)
	var fn := {}
	list.tree_exiting.connect(func() -> void: fn.clear())
	fn.redraw = func() -> void:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
		for i in draft.size():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			list.add_child(row)
			var text := Label.new()
			text.text = "%d.  %s" % [i + 1, SystemModel.describe_action(draft[i], system)]
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.add_theme_font_size_override("font_size", 17)
			row.add_child(text)
			_small(row, "Edit", func() -> void:
				edit_action(parent, system, draft[i], func(a: Dictionary) -> void:
					draft[i] = a
					fn.redraw.call()))
			if i > 0:
				_small(row, "↑", func() -> void:
					var moved: Dictionary = draft[i]
					draft.remove_at(i)
					draft.insert(i - 1, moved)
					fn.redraw.call())
			_small(row, "✕", func() -> void:
				draft.remove_at(i)
				fn.redraw.call())
		_small(list, "+ Add an action", func() -> void:
			edit_action(parent, system, {}, func(a: Dictionary) -> void:
				draft.append(a)
				fn.redraw.call()))
	fn.redraw.call()
	modal.add_button("Done", Color(0.16, 0.38, 0.24), func() -> void: on_done.call(draft))
	modal.add_button("Cancel", Color(0.25, 0.22, 0.2))
	return modal


static func edit_action(parent: Node, system: Dictionary, action: Dictionary, on_done: Callable) -> Modal:
	var game := String(system.game)
	var draft: Dictionary = action.duplicate(true)
	if draft.is_empty():
		draft = {"type": "unit", "op": "multiply", "value": 2}
	var modal := Modal.open(parent, "Action", 760)
	modal.name = "ActionEditor"
	var summary := modal.add_text("", 18, COLOR_GOLD)
	var refresh := func() -> void:
		summary.text = SystemModel.describe_action(draft, system)
	var types: Array = []
	for key in SystemModel.ACTIONS:
		if key in SystemModel.CRAPS_ONLY_ACTIONS and game != "craps":
			continue
		types.append(key)
	var type_pick := _options(_row(modal.content, "Do"),
		types.map(func(k: String) -> String: return SystemModel.ACTIONS[k]), types.find(String(draft.type)))
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 10)
	modal.content.add_child(fields)
	var rebuild := func() -> void:
		for child in fields.get_children():
			fields.remove_child(child)
			child.queue_free()
		_action_fields(parent, fields, system, draft, refresh)
		refresh.call()
	type_pick.item_selected.connect(func(index: int) -> void:
		draft.clear()
		draft.merge(_blank_action(String(types[index]), system))
		rebuild.call())
	rebuild.call()
	modal.add_button("Done", Color(0.16, 0.38, 0.24), func() -> void: on_done.call(draft))
	modal.add_button("Cancel", Color(0.25, 0.22, 0.2))
	return modal


static func _blank_action(kind: String, system: Dictionary) -> Dictionary:
	var game := String(system.game)
	var first: String = SystemModel.positions(game)[0].key if game == "craps" else "red"
	match kind:
		"bet":
			return {"type": "bet", "pos": first, "units": 1}
		"add_bet":
			return {"type": "add_bet", "pos": first, "units": 1}
		"unit":
			return {"type": "unit", "op": "multiply", "value": 2}
		"goto":
			return {"type": "goto", "step": int(system.steps[0].id)}
		"counter":
			return {"type": "counter", "which": "a", "op": "add", "value": 1}
		"sit_out":
			return {"type": "sit_out", "rounds": 1}
		"odds":
			return {"type": "odds", "pos": "pass", "mult": 0}
		"press", "regress":
			return {"type": kind, "pos": first}
	return {"type": kind}


static func _action_fields(parent: Node, fields: VBoxContainer, system: Dictionary, draft: Dictionary,
		refresh: Callable) -> void:
	match String(draft.type):
		"bet", "add_bet":
			_bet_button(parent, _row(fields, "Bet"), system, draft, "pos", refresh)
			var low := 0 if draft.type == "bet" else -1000
			_stepper(_row(fields, "Units" if draft.type == "bet" else "Change by"), int(draft.units), low, 1000,
				func(v: int) -> void:
					draft.units = v
					refresh.call())
		"unit":
			var ops: Array = SystemModel.UNIT_OPS.keys()
			var row := _row(fields, "Unit")
			var pick := _options(row, ops.map(func(k: String) -> String: return SystemModel.UNIT_OPS[k]), ops.find(draft.op))
			var value := _number_box(row, float(draft.get("value", 1)), -1000, 1000, 0.5, func(v: float) -> void:
				draft.value = v
				refresh.call())
			value.visible = draft.op != "reset"
			pick.item_selected.connect(func(i: int) -> void:
				draft.op = ops[i]
				value.visible = draft.op != "reset"
				refresh.call())
		"goto":
			var steps: Array = system.steps
			var pick := _options(_row(fields, "Step"), steps.map(func(s: Dictionary) -> String: return s.name),
				steps.map(func(s: Dictionary) -> int: return int(s.id)).find(int(draft.step)))
			pick.item_selected.connect(func(i: int) -> void:
				draft.step = int(steps[i].id)
				refresh.call())
		"counter":
			var row := _row(fields, "Counter")
			var which := _options(row, ["A", "B"], ["a", "b"].find(draft.which))
			which.item_selected.connect(func(i: int) -> void:
				draft.which = ["a", "b"][i]
				refresh.call())
			var op := _options(row, ["add", "set to"], ["add", "set"].find(draft.op))
			op.item_selected.connect(func(i: int) -> void:
				draft.op = ["add", "set"][i]
				refresh.call())
			_number_box(row, float(draft.get("value", 1)), -1000000, 1000000, 1, func(v: float) -> void:
				draft.value = v
				refresh.call())
		"sit_out":
			_stepper(_row(fields, "Rounds"), int(draft.rounds), 1, 100, func(v: int) -> void:
				draft.rounds = v
				refresh.call())
		"odds":
			_bet_button(parent, _row(fields, "On"), system, draft, "pos", refresh)
			_stepper(_row(fields, "Times (0 = max)"), int(draft.mult), 0, 5, func(v: int) -> void:
				draft.mult = v
				refresh.call())
		"press", "regress":
			_bet_button(parent, _row(fields, "Bet"), system, draft, "pos", refresh)


# --- Form pieces -------------------------------------------------------------------------

static func _row(parent: Control, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(160, 0)
	label.add_theme_font_size_override("font_size", 18)
	row.add_child(label)
	parent.add_child(row)
	return row


static func _options(row: Control, labels: Array, selected: int) -> OptionButton:
	var pick := OptionButton.new()
	pick.focus_mode = Control.FOCUS_NONE
	pick.custom_minimum_size = Vector2(220, 46)
	pick.add_theme_font_size_override("font_size", 17)
	for text in labels:
		pick.add_item(text)
	pick.select(maxi(0, selected))
	row.add_child(pick)
	return pick


## A − value + stepper. Built detached when `row` is null.
static func _stepper(row: Control, value: int, low: int, high: int, on_change: Callable) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var shown := Label.new()
	shown.text = str(value)
	shown.custom_minimum_size = Vector2(56, 0)
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shown.add_theme_font_size_override("font_size", 20)
	var current := [value]
	var change := func(delta: int) -> void:
		current[0] = clampi(current[0] + delta, low, high)
		shown.text = str(current[0])
		on_change.call(current[0])
	_small(box, "−", change.bind(-1))
	box.add_child(shown)
	_small(box, "+", change.bind(1))
	if row != null:
		row.add_child(box)
	return box


static func _number_box(row: Control, value: float, low: float, high: float, step: float, on_change: Callable) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = low
	box.max_value = high
	box.step = step
	box.value = value
	box.custom_minimum_size = Vector2(150, 46)
	box.value_changed.connect(on_change)
	row.add_child(box)
	return box


## A button showing the chosen bet; tapping it opens the picker.
static func _bet_button(parent: Node, row: Control, system: Dictionary, draft: Dictionary, key: String,
		refresh: Callable, extras: Array = []) -> Button:
	var game := String(system.game)
	var button := _field_button(row, SystemModel.position_label(game, String(draft.get(key, ""))))
	button.pressed.connect(func() -> void:
		PositionPicker.open(parent, game, false, [draft.get(key, "")], func(keys: Array) -> void:
			draft[key] = keys[0]
			button.text = SystemModel.position_label(game, keys[0])
			refresh.call(), extras))
	return button


static func _field_button(row: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text if text != "" else "Choose…"
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.custom_minimum_size = Vector2(320, 46)
	CasinoUI.style_button(button, COLOR_FIELD, 17, 12, 8, 8, COLOR_GOLD)
	row.add_child(button)
	return button


static func _small(parent: Control, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(46, 42)
	CasinoUI.style_button(button, Color(0.14, 0.24, 0.18), 17, 10, 6)
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


static func _names(game: String, keys: Array) -> String:
	if keys.is_empty():
		return "Choose bets…"
	var parts: PackedStringArray = []
	for key in keys:
		parts.append(SystemModel.position_label(game, key))
	return ", ".join(parts)

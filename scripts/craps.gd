extends Control
## Craps, with the whole table: line and odds, come and don't come, place
## bets, the field, Big 6/8, the hardways, and the proposition box.
##
## House rules, stated on the board because they change what a bet does:
##   * Place bets and every odds bet are OFF on the come-out roll — they
##     neither win nor lose, and sit there waiting for a point.
##   * Odds are capped 3-4-5x, so the most you can win behind the line is
##     six times it whichever number the point is.
##   * Winners are paid and come down, except place bets and Big 6/8, which
##     stay working until they lose — that is the real table rule and it is
##     what makes those bets worth making.
##   * Place and odds payouts round down to the dollar, as a dealer does.

const CHIP_VALUES := [5, 25, 100, 500]
## The table's rules live in CrapsEngine; these keep their names here for the
## felt, which prints its prices from them.
const POINTS := CrapsEngine.POINTS
const TRUE_ODDS := CrapsEngine.TRUE_ODDS
const PLACE_ODDS := CrapsEngine.PLACE_ODDS
const PLACE_EDGE := CrapsEngine.PLACE_EDGE
const ODDS_MULTIPLE := CrapsEngine.ODDS_MULTIPLE
const HARD_PAYS := CrapsEngine.HARD_PAYS
const PROPS := CrapsEngine.PROPS

const COLOR_FELT := Color(0.05, 0.22, 0.13)
const COLOR_PANEL := Color(0.04, 0.17, 0.1)
const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_WIN := Color(0.5, 0.92, 0.55)
const COLOR_LOSE := Color(0.96, 0.5, 0.45)
const COLOR_MUTED := Color(0.78, 0.85, 0.78)
const COLOR_PASS := Color(0.13, 0.35, 0.6)
const COLOR_DONT := Color(0.5, 0.14, 0.16)
const COLOR_ODDS := Color(0.1, 0.28, 0.22)
const COLOR_PLACE := Color(0.09, 0.3, 0.18)
const COLOR_FIELD := Color(0.2, 0.28, 0.42)
const COLOR_HARD := Color(0.36, 0.2, 0.45)
const COLOR_PROP := Color(0.42, 0.22, 0.14)

const ROLL_TIME := 0.75
const TUMBLE_STEPS := 8

var engine := CrapsEngine.new()
## 0 when the point is off and the next roll is a come-out.
var point: int:
	get:
		return engine.point
	set(value):
		engine.point = value
var rolling := false
var selected_chip := 25
var board: BetBoard:
	get:
		return engine.board
var history: Array = []
## Set by tests to force known dice; consumed before the generator.
var scripted_rolls: Array = []

var felt: CrapsTable
var die_a: CrapsDie
var die_b: CrapsDie
var balance_label: Label
var total_bet_label: Label
var message_label: Label
var detail_label: Label
var point_label: Label
var roll_label: Label
var history_box: HBoxContainer
var back_button: Button
var roll_button: Button
var clear_button: Button
var max_odds_button: Button
var edges_button: Button
var lab_button: Button


func _ready() -> void:
	_build_ui()
	Bank.balance_changed.connect(_on_balance_changed)
	_on_balance_changed(Bank.balance)
	_refresh()
	_set_message("Come-out roll. Back the pass line, or fade it.", Color.WHITE)


# --- dice --------------------------------------------------------------------

## Two independent dice, so the totals come out 6-heavy the way they should.
## Rolling `randi() % 11 + 2` would be uniform across 2-12 and would quietly
## turn craps into a different game; the rule suite histograms this.
func _roll_dice() -> Array:
	if not scripted_rolls.is_empty():
		return scripted_rolls.pop_front()
	return [randi() % 6 + 1, randi() % 6 + 1]


# --- odds --------------------------------------------------------------------

func _odds_number(key: String) -> int:
	return engine.odds_number(key)


func _max_odds(key: String) -> int:
	return engine.max_odds(key)


# --- betting -----------------------------------------------------------------

## Why a bet can't be made right now, or "" when it can.
func _refusal(key: String) -> String:
	if rolling:
		return "The dice are out."
	return engine.refusal(key, selected_chip)


func _on_bet_pressed(key: String) -> void:
	# Tapping a come point that already carries a bet takes odds behind it,
	# since that is the only thing you can actually do to one.
	if String(board.meta(key).get("kind", "")) == "point" and board.amount(key) > 0:
		key = _odds_key_for(key)
	var refusal := _refusal(key)
	if refusal != "":
		_set_message(refusal, COLOR_GOLD)
		return
	if not board.place(key, selected_chip):
		_set_message("Not enough balance for a $%d chip." % selected_chip, COLOR_LOSE)
		return
	_refresh()


func _odds_key_for(point_key: String) -> String:
	return engine.odds_key_for(point_key)


## Tops every odds bet up to its 3-4-5x maximum, as far as the bank allows.
func _on_max_odds_pressed() -> void:
	if rolling:
		return
	var taken := 0
	for key in board.bets:
		if String(board.meta(key).get("kind", "")) != "odds":
			continue
		var want := _max_odds(key) - board.amount(key)
		if want <= 0:
			continue
		want = mini(want, Bank.balance)
		if want > 0 and board.place(key, want):
			taken += want
	if taken > 0:
		_set_message("Took $%s in odds behind the line." % Bank.fmt(taken), Color.WHITE)
	else:
		_set_message("Nothing to take odds on, or nothing left to take them with.", COLOR_GOLD)
	_refresh()


func _is_contract(key: String) -> bool:
	return engine.is_contract(key)


func _on_clear_pressed() -> void:
	if rolling:
		return
	var kept := 0
	var refunded := 0
	for key in board.staked_keys():
		if _is_contract(key):
			kept += board.amount(key)
		else:
			refunded += board.refund(key)
	if refunded > 0 and kept > 0:
		_set_message("Removable bets refunded. $%s of contract bets ride until they win or lose." % Bank.fmt(kept), COLOR_GOLD)
	elif refunded > 0:
		_set_message("Bets cleared and refunded.", Color.WHITE)
	elif kept > 0:
		_set_message("The pass line and travelled come bets are contracts — they ride until they win or lose.", COLOR_GOLD)
	_refresh()


## Settles the table for a player walking away: every removable bet is
## handed back, and the contracts are forfeited to the house — a contract
## bet cannot come down, and the table doesn't pause for someone who left.
## Returns what the walk cost.
func _settle_walk_away() -> int:
	var forfeited := 0
	for key in board.staked_keys():
		if _is_contract(key):
			forfeited += board.take(key)
		else:
			board.refund(key)
	return forfeited


func _on_back_pressed() -> void:
	if rolling:
		return
	_settle_walk_away()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## Opens the Systems Lab with the bets on the table as its starting system,
## or the lab's entry in Extras if it isn't unlocked. Unlike walking away, it
## won't forfeit a contract bet: finish the hand first.
func _on_lab_pressed() -> void:
	if rolling:
		return
	if not Store.owns("craps_lab"):
		Store.show_extras(get_tree(), "craps_lab", "res://scenes/craps.tscn")
		return
	for key in board.staked_keys():
		if _is_contract(key):
			_set_message("Finish the hand first — the pass line and travelled come bets can't come down.", COLOR_GOLD)
			return
	var layout := {}
	for key in board.staked_keys():
		layout[key] = board.amount(key)
	board.refund_all()
	SystemLab.open_game = "craps"
	SystemLab.open_layout = layout
	get_tree().change_scene_to_file("res://scenes/system_lab.tscn")


# --- settling ----------------------------------------------------------------

func _on_roll_pressed() -> void:
	if rolling:
		return
	if board.total() <= 0:
		_set_message("Get a bet down first.", COLOR_GOLD)
		return
	rolling = true
	_refresh()

	var dice := _roll_dice()
	# Tumble through faces before landing, so the result reads as a roll.
	for i in TUMBLE_STEPS:
		die_a.value = randi() % 6 + 1
		die_b.value = randi() % 6 + 1
		await get_tree().create_timer(ROLL_TIME / TUMBLE_STEPS).timeout
	die_a.value = int(dice[0])
	die_b.value = int(dice[1])

	var before := Bank.balance
	var notes: Array = []
	var headline := _resolve_roll(int(dice[0]), int(dice[1]), notes)

	rolling = false
	_add_history(int(dice[0]) + int(dice[1]))
	_refresh()

	var net := Bank.balance - before
	var colour := COLOR_GOLD
	var tail := ""
	if net > 0:
		colour = COLOR_WIN
		tail = " You're up $%s on the roll." % Bank.fmt(net)
	elif net < 0:
		colour = COLOR_LOSE
		tail = " That cost you $%s." % Bank.fmt(-net)
	_set_message(headline + tail, colour)
	detail_label.text = " · ".join(notes)


## Settles every bet on the table against one roll and returns the headline.
func _resolve_roll(d1: int, d2: int, notes: Array) -> String:
	return engine.resolve_roll(d1, d2, notes)


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_FELT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := SafeArea.create(16)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	column.add_child(_build_top_bar())
	column.add_child(_build_messages())

	# The felt paints itself and owns every area's geometry; the buttons are
	# transparent polygons layered over it.
	felt = CrapsTable.new()
	felt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	felt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	felt.geometry_changed.connect(_fit_areas)
	column.add_child(felt)
	_describe_bets()
	_build_areas()

	column.add_child(_build_rail())


func _build_top_bar() -> Control:
	var top := HBoxContainer.new()

	back_button = Button.new()
	back_button.text = "< Back"
	back_button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(back_button, Color(0.08, 0.16, 0.1), 18, 14, 8)
	back_button.pressed.connect(_on_back_pressed)
	top.add_child(back_button)

	var title := Label.new()
	title.text = "CRAPS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	top.add_child(title)

	lab_button = Button.new()
	lab_button.text = "Systems Lab"
	lab_button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(lab_button, Color(0.4, 0.3, 0.1), 17, 14, 8)
	lab_button.pressed.connect(_on_lab_pressed)
	top.add_child(lab_button)

	var lab_gap := Control.new()
	lab_gap.custom_minimum_size = Vector2(16, 0)
	top.add_child(lab_gap)

	balance_label = Label.new()
	balance_label.add_theme_font_size_override("font_size", 22)
	balance_label.add_theme_color_override("font_color", Color.WHITE)
	top.add_child(balance_label)
	return top


func _build_messages() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(0, 26)
	message_label.add_theme_font_size_override("font_size", 19)
	box.add_child(message_label)

	detail_label = Label.new()
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size = Vector2(0, 28)
	detail_label.add_theme_font_size_override("font_size", 13)
	detail_label.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(detail_label)
	return box


## What each area prints. The price comes from the same constant that pays
## it, so the felt can't drift from the payout.
func _describe_bets() -> void:
	felt.set_text("pass", "PASS LINE", "1 TO 1", "edge 1.41%")
	felt.set_text("dont_pass", "DON'T PASS", "1 TO 1", "edge 1.36%")
	felt.set_text("pass_odds", "ODDS", "true price", "no edge")
	felt.set_text("dont_pass_odds", "LAY ODDS", "true price", "no edge")
	felt.set_text("come", "COME", "1 TO 1", "edge 1.41%")
	felt.set_text("dont_come", "DON'T COME", "1 TO 1", "edge 1.36%")
	felt.set_text("field", "FIELD", "1 TO 1", "edge 2.78%")
	felt.set_text("big_6", "BIG 6", "1 TO 1", "9.09%")
	felt.set_text("big_8", "BIG 8", "1 TO 1", "9.09%")

	for number in POINTS:
		var o: Array = PLACE_ODDS[number]
		felt.set_text("place_%d" % number, "PLACE %d" % number,
			"%d TO %d" % [int(o[0]), int(o[1])], String(PLACE_EDGE[number]))
		var t: Array = TRUE_ODDS[number]
		var price := "%d TO %d" % [int(t[0]), int(t[1])]
		felt.set_text("come_%d" % number, "COME %d" % number, "1 TO 1", "edge 1.41%")
		felt.set_text("dont_come_%d" % number, "DON'T COME %d" % number, "1 TO 1", "edge 1.36%")
		# The 3-4-5x multiple is printed on the take-odds spot; the lay pays
		# the same odds the other way up, so its price is inverted.
		felt.set_text("come_odds_%d" % number,
			"ODDS %dx" % int(ODDS_MULTIPLE[number]), price, "no edge")
		felt.set_text("dont_come_odds_%d" % number, "LAY ODDS",
			"%d TO %d" % [int(t[1]), int(t[0])], "no edge")

	for number in HARD_PAYS:
		felt.set_text("hard_%d" % number, "HARD %d" % number,
			"%d TO 1" % int(HARD_PAYS[number]),
			"11.1%" if number in [4, 10] else "9.09%")

	for key in PROPS:
		var prop: Dictionary = PROPS[key]
		felt.set_text(key, String(prop.label), "%d TO 1" % int(prop.pays), String(prop.edge))
	felt.set_text("horn", "HORN", "quartered", "12.5%")
	felt.set_text("c_and_e", "C & E", "halved", "11.1%")


## One transparent polygon button per area, stacked over the felt. Each
## covers the whole felt and hit-tests its own polygon, so a click lands on
## the area whose shape actually contains it rather than whichever bounding
## box happens to be on top.
func _build_areas() -> void:
	for key in _bet_meta():
		var button := PolyButton.new()
		button.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Come points and odds spots never dim. Neither is a bet turned off:
		# one is a place chips have not reached yet, the other a spot with
		# nothing behind it. Greying either reads as a rendering fault, and
		# a dark patch in the middle of the pass line especially so — the
		# refusal message explains why a tap did nothing.
		var kind := String(_bet_meta()[key].get("kind", ""))
		button.dim_when_disabled = not (kind in ["point", "odds"])
		button.pressed.connect(_on_bet_pressed.bind(key))
		felt.add_child(button)
		# A copy: the felt writes each area's chip spot into its meta.
		board.add(key, button, _bet_meta()[key].duplicate())


func _bet_meta() -> Dictionary:
	return CrapsEngine.bet_meta()


## Copies the felt's freshly computed geometry onto the buttons: the hit
## polygon, and the chip spot the badge sits on.
func _fit_areas() -> void:
	for key in board.bets:
		if not felt.areas.has(key):
			continue
		var area: Dictionary = felt.areas[key]
		var button: PolyButton = board.bets[key].button
		button.polygon = area.poly
		board.bets[key].meta["badge_at"] = area.chip
	board.refresh_all_badges()


func _build_rail() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CasinoUI.panel_style(COLOR_PANEL, COLOR_GOLD, 10, 8))

	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 5)
	panel.add_child(rail)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	rail.add_child(top)

	die_a = CrapsDie.new()
	die_a.custom_minimum_size = Vector2(46, 46)
	top.add_child(die_a)
	die_b = CrapsDie.new()
	die_b.custom_minimum_size = Vector2(46, 46)
	top.add_child(die_b)

	point_label = Label.new()
	point_label.custom_minimum_size = Vector2(150, 0)
	point_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	point_label.add_theme_font_size_override("font_size", 19)
	point_label.add_theme_color_override("font_color", COLOR_GOLD)
	top.add_child(point_label)

	var group := ButtonGroup.new()
	for value in CHIP_VALUES:
		var chip := Button.new()
		chip.text = "$%d" % value
		chip.toggle_mode = true
		chip.button_group = group
		chip.custom_minimum_size = Vector2(66, 40)
		chip.focus_mode = Control.FOCUS_NONE
		CasinoUI.style_button(chip, Color(0.1, 0.14, 0.11), 16, 4, 4, 20)
		var chosen := StyleBoxFlat.new()
		chosen.bg_color = COLOR_GOLD
		chosen.set_corner_radius_all(20)
		chip.add_theme_stylebox_override("pressed", chosen)
		chip.add_theme_color_override("font_pressed_color", Color(0.15, 0.1, 0.0))
		chip.pressed.connect(func() -> void: selected_chip = value)
		if value == selected_chip:
			chip.button_pressed = true
		top.add_child(chip)

	roll_button = _rail_button(top, "ROLL", Color(0.72, 0.55, 0.1), _on_roll_pressed, 132)
	roll_button.add_theme_font_size_override("font_size", 22)
	max_odds_button = _rail_button(top, "Max Odds", COLOR_ODDS.lightened(0.12), _on_max_odds_pressed, 100)
	clear_button = _rail_button(top, "Clear", Color(0.32, 0.28, 0.23), _on_clear_pressed, 82)
	edges_button = _rail_button(top, "Show Edges", Color(0.24, 0.2, 0.34), _on_edges_pressed, 116)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	rail.add_child(bottom)

	total_bet_label = Label.new()
	total_bet_label.add_theme_font_size_override("font_size", 15)
	total_bet_label.add_theme_color_override("font_color", COLOR_GOLD)
	bottom.add_child(total_bet_label)

	roll_label = Label.new()
	roll_label.add_theme_font_size_override("font_size", 13)
	roll_label.add_theme_color_override("font_color", COLOR_MUTED)
	bottom.add_child(roll_label)

	history_box = HBoxContainer.new()
	history_box.add_theme_constant_override("separation", 4)
	bottom.add_child(history_box)

	var rules := Label.new()
	rules.text = "Winners stay up, as at a live table — travelled come bets and odds come down with pay. Place bets and odds sit out the come-out; odds capped 3-4-5x."
	# Wraps when squeezed, so the sentence can't widen the scene's minimum.
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules.custom_minimum_size = Vector2(300, 0)
	rules.add_theme_font_size_override("font_size", 12)
	rules.add_theme_color_override("font_color", COLOR_MUTED)
	bottom.add_child(rules)
	return panel


func _rail_button(parent: Control, text: String, colour: Color, handler: Callable,
		width: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 40)
	button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(button, colour, 16, 8, 6)
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _on_edges_pressed() -> void:
	felt.edges_shown = not felt.edges_shown
	edges_button.text = "Hide Edges" if felt.edges_shown else "Show Edges"


func _add_history(total: int) -> void:
	history.push_front(total)
	if history.size() > 10:
		history.resize(10)
	for child in history_box.get_children():
		history_box.remove_child(child)
		child.queue_free()
	for entry in history:
		var dot := Label.new()
		dot.text = str(entry)
		dot.custom_minimum_size = Vector2(20, 20)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = COLOR_DONT if entry == 7 else Color(0.1, 0.28, 0.16)
		sb.set_corner_radius_all(10)
		dot.add_theme_stylebox_override("normal", sb)
		dot.add_theme_color_override("font_color", Color.WHITE)
		dot.add_theme_font_size_override("font_size", 12)
		history_box.add_child(dot)


func _refresh() -> void:
	felt.point = point
	# A number carrying a come or don't come bet grows its odds box.
	var come_open: Array = []
	var dont_open: Array = []
	for number in POINTS:
		if board.amount("come_%d" % number) > 0:
			come_open.append(number)
		if board.amount("dont_come_%d" % number) > 0:
			dont_open.append(number)
	felt.set_odds_open(come_open, dont_open)
	point_label.text = "Come-out roll" if point == 0 else "Point:  %d" % point
	roll_label.text = "Rolling…" if rolling else "Last roll: %d" % (die_a.value + die_b.value)
	if history.is_empty() and not rolling:
		roll_label.text = "The dice are yours."
	total_bet_label.text = "On the table: $%s" % Bank.fmt(board.total())
	roll_button.disabled = rolling
	clear_button.disabled = rolling
	max_odds_button.disabled = rolling
	back_button.disabled = rolling
	for key in board.bets:
		var kind := String(board.meta(key).get("kind", ""))
		var button: Button = board.bets[key].button
		match kind:
			"line":
				button.disabled = point != 0
			"come":
				button.disabled = point == 0
			"odds":
				button.disabled = _max_odds(key) <= 0
			"point":
				button.disabled = board.amount(key) <= 0
	board.refresh_all_badges()


func _set_message(text: String, colour: Color) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", colour)


func _on_balance_changed(new_balance: int) -> void:
	balance_label.text = "Balance: $%s" % Bank.fmt(new_balance)

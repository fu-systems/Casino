class_name StrategyChart
extends VBoxContainer
## Basic strategy and the Illustrious 18, drawn as charts — free, in the
## blackjack trainer panel and behind every wrong answer in the Strategy
## Trainer.
##
## Nothing here is typed in by hand. Every cell asks `BlackjackStrategy` what
## to do with a real hand, and the count table is read straight from its
## index lists, so a chart can never disagree with the hints at the table.

const UPCARDS := [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
const TABLES := ["hard", "soft", "pair", "count"]
const TAB_NAMES := {"hard": "Hard totals", "soft": "Soft totals", "pair": "Pairs", "count": "Count (I18)"}

## Hard rows: label, the total, and the two cards that make it. Totals of
## 8 and under all play alike, as do 17 and up; the rule suite checks that.
const HARD_ROWS := [
	["5-8", 8, ["3", "5"]], ["9", 9, ["4", "5"]], ["10", 10, ["4", "6"]],
	["11", 11, ["5", "6"]], ["12", 12, ["10", "2"]], ["13", 13, ["10", "3"]],
	["14", 14, ["10", "4"]], ["15", 15, ["10", "5"]], ["16", 16, ["10", "6"]],
	["17+", 17, ["10", "7"]],
]
const SOFT_ROWS := [
	["A,2", 13, ["A", "2"]], ["A,3", 14, ["A", "3"]], ["A,4", 15, ["A", "4"]],
	["A,5", 16, ["A", "5"]], ["A,6", 17, ["A", "6"]], ["A,7", 18, ["A", "7"]],
	["A,8", 19, ["A", "8"]], ["A,9", 20, ["A", "9"]],
]
const PAIR_ROWS := [
	["A,A", 11, ["A", "A"]], ["10,10", 10, ["10", "10"]], ["9,9", 9, ["9", "9"]],
	["8,8", 8, ["8", "8"]], ["7,7", 7, ["7", "7"]], ["6,6", 6, ["6", "6"]],
	["5,5", 5, ["5", "5"]], ["4,4", 4, ["4", "4"]], ["3,3", 3, ["3", "3"]],
	["2,2", 2, ["2", "2"]],
]

const CODE_COLOURS := {
	"H": Color(0.72, 0.24, 0.22),
	"S": Color(0.78, 0.64, 0.16),
	"D": Color(0.18, 0.45, 0.72),
	"Ds": Color(0.16, 0.56, 0.52),
	"P": Color(0.5, 0.28, 0.62),
}
const CODE_NAMES := {
	"H": "Hit", "S": "Stand", "D": "Double (else hit)",
	"Ds": "Double (else stand)", "P": "Split",
}
const COLOR_HEAD := Color(0.06, 0.12, 0.09)
const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_MUTED := Color(0.78, 0.85, 0.78)

var table := "hard"
var cell_size := Vector2(60, 32)
var _tabs := {}
var _grid_holder: Control
var _legend: Label
## Cell controls by "table:row:up", so one can be highlighted.
var _cells := {}
var _highlight := ""


func _init(compact: bool = false) -> void:
	add_theme_constant_override("separation", 8)
	if compact:
		cell_size = Vector2(52, 28)


func _ready() -> void:
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	add_child(tab_row)
	for key in TABLES:
		var tab := Button.new()
		tab.text = TAB_NAMES[key]
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(150, 40)
		tab.pressed.connect(show_table.bind(key))
		tab_row.add_child(tab)
		_tabs[key] = tab

	_legend = Label.new()
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legend.add_theme_font_size_override("font_size", 14)
	_legend.add_theme_color_override("font_color", COLOR_MUTED)
	add_child(_legend)

	_grid_holder = VBoxContainer.new()
	add_child(_grid_holder)
	show_table(table)


func show_table(key: String) -> void:
	table = key
	for tab_key in _tabs:
		var active: bool = tab_key == key
		CasinoUI.style_button(_tabs[tab_key], Color(0.45, 0.36, 0.1) if active else Color(0.1, 0.18, 0.13),
			16, 10, 6, 8, COLOR_GOLD if active else Color(0, 0, 0, 0))
	for child in _grid_holder.get_children():
		_grid_holder.remove_child(child)
		child.queue_free()
	_cells.clear()
	if key == "count":
		_build_count_table()
		_legend.text = "Index plays for the Hi-Lo count. Use the true count (running count ÷ decks left): at or above the index, make the first play; below it, the second."
	else:
		_build_grid(key)
		var parts: PackedStringArray = []
		for code in CODE_NAMES:
			parts.append("%s = %s" % [code, CODE_NAMES[code]])
		_legend.text = "  ·  ".join(parts) + ".  Dealer stands on all 17s; double any two cards, also after a split."
	_apply_highlight()


## Outlines one cell in gold and switches to its table. `row` is the row
## label as shown ("16", "A,7", "8,8"); for the count table it's the hand
## label of an index play ("16 v 10", "Insurance").
func highlight(key: String, row: String, up: int = 0) -> void:
	_highlight = "%s:%s:%d" % [key, row, up]
	if table != key:
		show_table(key)
	else:
		_apply_highlight()


func _apply_highlight() -> void:
	if _cells.has(_highlight):
		var cell: Label = _cells[_highlight]
		var sb: StyleBoxFlat = cell.get_theme_stylebox("normal").duplicate()
		sb.border_color = COLOR_GOLD
		sb.set_border_width_all(3)
		cell.add_theme_stylebox_override("normal", sb)


# --- Chart data -----------------------------------------------------------------

static func rows_for(key: String) -> Array:
	match key:
		"hard":
			return HARD_ROWS
		"soft":
			return SOFT_ROWS
		"pair":
			return PAIR_ROWS
	return []


## The chart code for a row against an upcard, worked out by asking
## BlackjackStrategy about the row's actual cards: H, S, D, Ds or P. A double
## is marked Ds when the fallback (no doubling allowed) is to stand.
static func code_for(key: String, ranks: Array, up: int) -> String:
	var hand: Array = []
	for rank in ranks:
		hand.append(BlackjackShoe.make_card(rank))
	var can_split := key == "pair"
	var play: String = BlackjackStrategy.basic(hand, up, true, can_split).action
	match play:
		"Split":
			return "P"
		"Stand":
			return "S"
		"Hit":
			return "H"
		"Double":
			var fallback: String = BlackjackStrategy.basic(hand, up, false, can_split).action
			return "Ds" if fallback == "Stand" else "D"
	return "?"


## The count table as rows: hand label, dealer upcard label, index, the play
## at or above the index, and the play below it.
static func count_rows() -> Array:
	var rows: Array = []
	for entry in BlackjackStrategy.DEVIATIONS:
		rows.append(["%d v %s" % [int(entry.total), BlackjackStrategy.up_label(int(entry.up))],
			float(entry.index), String(entry.above), String(entry.below)])
	for entry in BlackjackStrategy.PAIR_DEVIATIONS:
		rows.append(["10,10 v %s" % BlackjackStrategy.up_label(int(entry.up)),
			float(entry.index), String(entry.above), String(entry.below)])
	rows.append(["Insurance", BlackjackStrategy.INSURANCE_INDEX, "Insure", "Decline"])
	return rows


# --- Drawing --------------------------------------------------------------------

func _build_grid(key: String) -> void:
	var grid := GridContainer.new()
	grid.columns = UPCARDS.size() + 1
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	_grid_holder.add_child(grid)
	grid.add_child(_make_cell("You  \\  Dealer", COLOR_HEAD, Vector2(cell_size.x * 1.6, cell_size.y), COLOR_GOLD))
	for up in UPCARDS:
		grid.add_child(_make_cell(BlackjackStrategy.up_label(up), COLOR_HEAD, cell_size, COLOR_GOLD))
	for row in rows_for(key):
		grid.add_child(_make_cell(row[0], COLOR_HEAD, Vector2(cell_size.x * 1.6, cell_size.y), COLOR_GOLD))
		for up in UPCARDS:
			var code := code_for(key, row[2], up)
			var cell := _make_cell(code, CODE_COLOURS.get(code, Color.GRAY), cell_size, Color.WHITE)
			_cells["%s:%s:%d" % [key, row[0], up]] = cell
			grid.add_child(cell)


func _build_count_table() -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	_grid_holder.add_child(grid)
	var widths := [cell_size.x * 2.4, cell_size.x * 1.6, cell_size.x * 2.6, cell_size.x * 2.6]
	var heads := ["Hand v dealer", "True count", "At or above", "Below"]
	for i in heads.size():
		grid.add_child(_make_cell(heads[i], COLOR_HEAD, Vector2(widths[i], cell_size.y), COLOR_GOLD))
	for row in count_rows():
		var label: String = row[0]
		var hand_cell := _make_cell(label, COLOR_HEAD, Vector2(widths[0], cell_size.y), Color.WHITE)
		_cells["count:%s:0" % label] = hand_cell
		grid.add_child(hand_cell)
		grid.add_child(_make_cell(BlackjackStrategy._signed(row[1]), COLOR_HEAD, Vector2(widths[1], cell_size.y), COLOR_GOLD))
		grid.add_child(_make_cell(row[2], _play_colour(row[2]), Vector2(widths[2], cell_size.y), Color.WHITE))
		grid.add_child(_make_cell(row[3], _play_colour(row[3]), Vector2(widths[3], cell_size.y), Color.WHITE))


func _play_colour(play: String) -> Color:
	match play:
		"Hit":
			return CODE_COLOURS.H
		"Stand", "Decline":
			return CODE_COLOURS.S
		"Double":
			return CODE_COLOURS.D
		"Split", "Insure":
			return CODE_COLOURS.P
	return Color.GRAY


func _make_cell(text: String, bg: Color, size: Vector2, fg: Color) -> Label:
	var cell := Label.new()
	cell.text = text
	cell.custom_minimum_size = size
	cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	cell.add_theme_stylebox_override("normal", sb)
	cell.add_theme_font_size_override("font_size", int(cell_size.y * 0.5))
	cell.add_theme_color_override("font_color", fg)
	return cell

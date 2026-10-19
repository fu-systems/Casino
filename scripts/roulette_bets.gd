class_name RouletteBets
extends RefCounted
## Every bet on the roulette board: what it covers, what it pays, and what to
## call it. The table builds its buttons from this and the Systems Lab pays
## from it, so the two can never disagree about a bet.
##
## Keys: straight_0 .. straight_36; column_0 .. column_2 (top row to bottom,
## so column_2 is the "1st column" of 1, 4, 7 ... 34); dozen_0 .. dozen_2;
## and red, black, even, odd, low, high.

## The single zero's share of the wheel: the house edge on every bet.
const HOUSE_EDGE := 1.0 / 37.0

static var _table := {}


## key -> {"numbers": Array, "payout": int (to 1), "label": String,
## "group": String}, in board order.
static func all() -> Dictionary:
	if _table.is_empty():
		_build()
	return _table


static func keys() -> Array:
	return all().keys()


static func has(key: String) -> bool:
	return all().has(key)


static func numbers(key: String) -> Array:
	return all()[key].numbers


static func payout(key: String) -> int:
	return int(all()[key].payout)


static func label(key: String) -> String:
	return String(all()[key].label) if all().has(key) else key


## Whether `number` wins a bet on `key`.
static func covers(key: String, number: int) -> bool:
	return number in all()[key].numbers


static func _build() -> void:
	_add("straight_0", [0], 35, "0", "Numbers")
	for n in range(1, 37):
		_add("straight_%d" % n, [n], 35, str(n), "Numbers")

	# The board's rows run 3-6-9 along the top down to 1-4-7 along the
	# bottom, which is what makes the bottom row the "1st column".
	var column_names := ["3rd column", "2nd column", "1st column"]
	for row in 3:
		var column: Array = []
		for col in 12:
			column.append((col + 1) * 3 - row)
		_add("column_%d" % row, column, 2, column_names[row], "Columns")

	var dozen_names := ["1st 12", "2nd 12", "3rd 12"]
	for i in 3:
		var dozen: Array = []
		for n in range(i * 12 + 1, i * 12 + 13):
			dozen.append(n)
		_add("dozen_%d" % i, dozen, 2, dozen_names[i], "Dozens")

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
	_add("low", lows, 1, "1-18", "Even money")
	_add("even", evens, 1, "Even", "Even money")
	_add("red", reds, 1, "Red", "Even money")
	_add("black", blacks, 1, "Black", "Even money")
	_add("odd", odds, 1, "Odd", "Even money")
	_add("high", highs, 1, "19-36", "Even money")


static func _add(key: String, covered: Array, pays: int, name: String, group: String) -> void:
	_table[key] = {"numbers": covered, "payout": pays, "label": name, "group": group}

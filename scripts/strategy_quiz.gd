class_name StrategyQuiz
extends RefCounted
## Questions for the Strategy Trainer pack.
##
## A question is a real hand against a real upcard, plus the true count when
## the count matters. The answer is never stored anywhere: it's whatever
## `BlackjackStrategy` says for that exact hand, so the trainer, the table's
## hints and the charts all agree by construction.
##
## Question: {kind ("play" or "insurance"), hand, up, up_card, can_double,
## can_split, true_count (count questions only), answer, reason, deviates,
## table and row (the chart cell to point at), key (for weak-spot stats)}.

const VALUE_RANKS := {
	2: ["2"], 3: ["3"], 4: ["4"], 5: ["5"], 6: ["6"], 7: ["7"], 8: ["8"], 9: ["9"],
	10: ["10", "J", "Q", "K"], 11: ["A"],
}

## Of count-mode questions: this share asks about insurance...
const INSURANCE_SHARE := 0.1
## ...this share sits right by an index play, where the count changes the
## answer, and the rest are ordinary hands at an ordinary count.
const DEVIATION_SHARE := 0.5
## How far either side of an index a deviation question's count may fall.
const INDEX_SPREAD := 2


static func make(rng: RandomNumberGenerator, mode: String, cells: Dictionary = {}) -> Dictionary:
	match mode:
		"count":
			return count_question(rng)
		"weak":
			var weak := weak_keys(cells)
			if weak.is_empty():
				return basic_question(rng)
			return question_for_key(rng, weak[rng.randi_range(0, weak.size() - 1)])
	return basic_question(rng)


# --- Question kinds ---------------------------------------------------------------

## A random hand against a random upcard, no count.
static func basic_question(rng: RandomNumberGenerator) -> Dictionary:
	var q := _random_hand(rng)
	q.up = rng.randi_range(2, 11)
	return _answer(rng, q)


static func count_question(rng: RandomNumberGenerator) -> Dictionary:
	var roll := rng.randf()
	if roll < INSURANCE_SHARE:
		return insurance_question(rng, BlackjackStrategy.INSURANCE_INDEX
			+ rng.randi_range(-INDEX_SPREAD - 1, INDEX_SPREAD + 1))
	if roll < INSURANCE_SHARE + DEVIATION_SHARE:
		var all := deviations()
		var d: Dictionary = all[rng.randi_range(0, all.size() - 1)]
		return deviation_question(rng, d, float(d.index) + rng.randi_range(-INDEX_SPREAD, INDEX_SPREAD))
	var q := _random_hand(rng)
	q.up = rng.randi_range(2, 11)
	q.true_count = float(rng.randi_range(-3, 5))
	return _answer(rng, q)


## Every index play as one list: {label, kind ("hard" or "pair"), total,
## up, index}. The labels match the count chart's rows.
static func deviations() -> Array:
	var out: Array = []
	for d in BlackjackStrategy.DEVIATIONS:
		out.append({"label": "%d v %s" % [int(d.total), BlackjackStrategy.up_label(int(d.up))],
			"kind": "hard", "total": int(d.total), "up": int(d.up), "index": float(d.index)})
	for d in BlackjackStrategy.PAIR_DEVIATIONS:
		out.append({"label": "10,10 v %s" % BlackjackStrategy.up_label(int(d.up)),
			"kind": "pair", "total": 20, "up": int(d.up), "index": float(d.index)})
	return out


static func deviation_question(rng: RandomNumberGenerator, d: Dictionary, true_count: float) -> Dictionary:
	var q := {"can_double": true, "can_split": false}
	if d.kind == "pair":
		q.hand = _pair_hand(rng, 10)
		q.can_split = true
	else:
		q.hand = _hard_hand(rng, int(d.total))
	q.up = int(d.up)
	q.true_count = true_count
	q = _answer(rng, q)
	q.table = "count"
	q.row = d.label
	q.key = "dev:" + String(d.label)
	return q


static func insurance_question(rng: RandomNumberGenerator, true_count: float) -> Dictionary:
	var q := _random_hand(rng)
	# Insurance is offered before anything else happens, on the first two cards.
	while q.hand.size() != 2:
		q = _random_hand(rng)
	q.up = 11
	q.up_card = _card(rng, 11)
	q.true_count = true_count
	q.kind = "insurance"
	var advice := BlackjackStrategy.insurance(true_count)
	q.answer = "Insure" if advice.take else "Decline"
	q.reason = advice.reason
	q.deviates = advice.take
	q.table = "count"
	q.row = "Insurance"
	q.key = "dev:Insurance"
	return q


## A fresh question on one stats key — a chart cell ("hard:16:10") or an
## index play ("dev:16 v 10") — for the Weak Spots mode.
static func question_for_key(rng: RandomNumberGenerator, key: String) -> Dictionary:
	if key == "dev:Insurance":
		return insurance_question(rng, BlackjackStrategy.INSURANCE_INDEX
			+ rng.randi_range(-INDEX_SPREAD, INDEX_SPREAD))
	if key.begins_with("dev:"):
		for d in deviations():
			if "dev:" + String(d.label) == key:
				return deviation_question(rng, d, float(d.index) + rng.randi_range(-INDEX_SPREAD, INDEX_SPREAD))
		return basic_question(rng)
	var parts := key.split(":")
	var table := parts[0]
	var row := parts[1]
	var q := {"can_double": true, "can_split": false}
	match table:
		"hard":
			# The chart's grouped rows stand for any total in their range.
			var total := int(row)
			if row == "5-8":
				total = rng.randi_range(5, 8)
			elif row == "17+":
				total = rng.randi_range(17, 19)
			q.hand = _hard_hand(rng, total)
		"soft":
			q.hand = _soft_hand(rng, 11 + int(row.split(",")[1]))
		"pair":
			var value := 11 if row == "A,A" else int(row.split(",")[0])
			q.hand = _pair_hand(rng, value)
			q.can_split = true
		_:
			return basic_question(rng)
	q.up = int(parts[2])
	return _answer(rng, q)


## The chart cells and index plays answered worst, worst first: anything
## missed at least once, ordered by accuracy and then by how often it came
## up. `cells` maps a key to [right, asked].
static func weak_keys(cells: Dictionary, limit: int = 8) -> Array:
	var weak: Array = []
	for key in cells:
		var record: Array = cells[key]
		var right := int(record[0])
		var asked := int(record[1])
		if asked > 0 and right < asked:
			weak.append([key, float(right) / asked, asked])
	weak.sort_custom(func(a: Array, b: Array) -> bool:
		if not is_equal_approx(a[1], b[1]):
			return a[1] < b[1]
		return a[2] > b[2])
	var keys: Array = []
	for entry in weak.slice(0, limit):
		keys.append(entry[0])
	return keys


# --- Hands --------------------------------------------------------------------------

## A random two- or three-card hand. Three-card hands can't double or split,
## which is half the lesson in them.
static func _random_hand(rng: RandomNumberGenerator) -> Dictionary:
	var roll := rng.randf()
	if roll < 0.42:
		return {"hand": _hard_hand(rng, rng.randi_range(5, 19)), "can_double": true, "can_split": false}
	if roll < 0.54:
		return {"hand": _hard_hand(rng, rng.randi_range(12, 16), 3), "can_double": false, "can_split": false}
	if roll < 0.77:
		return {"hand": _soft_hand(rng, rng.randi_range(13, 20)), "can_double": true, "can_split": false}
	return {"hand": _pair_hand(rng, rng.randi_range(2, 11)), "can_double": true, "can_split": true}


## A hard total from non-ace cards that aren't a pair, so it plays as a total.
static func _hard_hand(rng: RandomNumberGenerator, total: int, cards: int = 2) -> Array:
	var options: Array = []
	if cards == 2:
		for a in range(2, 11):
			var b := total - a
			if b >= 2 and b <= 10 and a < b:
				options.append([a, b])
	else:
		for a in range(2, 11):
			for b in range(2, 11):
				var c := total - a - b
				if c >= 2 and c <= 10 and a != b:
					options.append([a, b, c])
	var values: Array = options[rng.randi_range(0, options.size() - 1)].duplicate()
	if rng.randf() < 0.5:
		values.reverse()
	var hand: Array = []
	for v in values:
		hand.append(_card(rng, v))
	return hand


static func _soft_hand(rng: RandomNumberGenerator, total: int) -> Array:
	var hand := [_card(rng, 11), _card(rng, total - 11)]
	if rng.randf() < 0.5:
		hand.reverse()
	return hand


static func _pair_hand(rng: RandomNumberGenerator, value: int) -> Array:
	return [_card(rng, value), _card(rng, value)]


static func _card(rng: RandomNumberGenerator, value: int) -> Dictionary:
	var ranks: Array = VALUE_RANKS[value]
	var rank: String = ranks[rng.randi_range(0, ranks.size() - 1)]
	return BlackjackShoe.make_card(rank, BlackjackShoe.SUITS[rng.randi_range(0, 3)])


# --- Answers ------------------------------------------------------------------------

## Fills in the answer, its reason, and the chart cell to point at.
static func _answer(rng: RandomNumberGenerator, q: Dictionary) -> Dictionary:
	q.kind = "play"
	if not q.has("up_card"):
		q.up_card = _card(rng, int(q.up))
	var play: Dictionary
	if q.has("true_count"):
		play = BlackjackStrategy.with_count(q.hand, q.up, q.can_double, q.can_split, q.true_count)
	else:
		play = BlackjackStrategy.basic(q.hand, q.up, q.can_double, q.can_split)
	q.answer = play.action
	q.reason = play.reason
	q.deviates = bool(play.get("deviates", false))
	var cell := chart_cell(q.hand, q.can_split)
	q.table = cell[0]
	q.row = cell[1]
	q.key = "%s:%s:%d" % [cell[0], cell[1], int(q.up)]
	return q


## The strategy chart's table and row label for a hand.
static func chart_cell(hand: Array, can_split: bool) -> Array:
	if can_split and BlackjackStrategy.is_pair(hand):
		var value := int(hand[0].value)
		if value == 11:
			return ["pair", "A,A"]
		return ["pair", "%d,%d" % [value, value]]
	var shape := BlackjackStrategy.evaluate(hand)
	var total := int(shape.total)
	if shape.soft:
		return ["soft", "A,%d" % (total - 11)]
	if total <= 8:
		return ["hard", "5-8"]
	if total >= 17:
		return ["hard", "17+"]
	return ["hard", str(total)]


## "Hard 16", "Soft 18" or "Pair of 8s", for the question prompt.
static func describe(hand: Array, can_split: bool) -> String:
	if can_split and BlackjackStrategy.is_pair(hand):
		var value := int(hand[0].value)
		return "Pair of aces" if value == 11 else "Pair of %ds" % value
	var shape := BlackjackStrategy.evaluate(hand)
	return "%s %d" % ["Soft" if shape.soft else "Hard", int(shape.total)]

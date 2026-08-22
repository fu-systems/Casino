class_name BlackjackStrategy
extends RefCounted
## Hi-Lo counting values plus basic and count-deviated playing strategy.
##
## Strategy assumes the house rules the table actually deals: a dealer who
## stands on all 17s, doubling allowed on any first two cards, and no splits
## or insurance. Because the table cannot split, pairs are advised on their
## total rather than as a split decision.

## Cards counted +1 by the Hi-Lo system; 7-9 are neutral and everything
## else (10, J, Q, K, A) counts -1.
const HI_LO_PLUS := ["2", "3", "4", "5", "6"]
const HI_LO_NEUTRAL := ["7", "8", "9"]

## Index plays for hard totals, drawn from the standard Illustrious 18
## (minus the insurance and pair-splitting entries this table can't use).
## `above` applies at a true count >= `index`, `below` under it.
const DEVIATIONS := [
	{"total": 16, "up": 10, "index": 0.0, "above": "Stand", "below": "Hit"},
	{"total": 16, "up": 9, "index": 5.0, "above": "Stand", "below": "Hit"},
	{"total": 15, "up": 10, "index": 4.0, "above": "Stand", "below": "Hit"},
	{"total": 13, "up": 2, "index": -1.0, "above": "Stand", "below": "Hit"},
	{"total": 13, "up": 3, "index": -2.0, "above": "Stand", "below": "Hit"},
	{"total": 12, "up": 2, "index": 3.0, "above": "Stand", "below": "Hit"},
	{"total": 12, "up": 3, "index": 2.0, "above": "Stand", "below": "Hit"},
	{"total": 12, "up": 4, "index": 0.0, "above": "Stand", "below": "Hit"},
	{"total": 12, "up": 5, "index": -2.0, "above": "Stand", "below": "Hit"},
	{"total": 12, "up": 6, "index": -1.0, "above": "Stand", "below": "Hit"},
	{"total": 11, "up": 11, "index": 1.0, "above": "Double", "below": "Hit"},
	{"total": 10, "up": 10, "index": 4.0, "above": "Double", "below": "Hit"},
	{"total": 10, "up": 11, "index": 4.0, "above": "Double", "below": "Hit"},
	{"total": 9, "up": 2, "index": 1.0, "above": "Double", "below": "Hit"},
	{"total": 9, "up": 7, "index": 3.0, "above": "Double", "below": "Hit"},
]


## Hi-Lo value of a single card.
static func hi_lo(card: Dictionary) -> int:
	if card.rank in HI_LO_PLUS:
		return 1
	if card.rank in HI_LO_NEUTRAL:
		return 0
	return -1


## Best total for a hand plus whether an ace is still counted as 11.
static func evaluate(hand: Array) -> Dictionary:
	var total := 0
	var aces := 0
	for card in hand:
		total += int(card.value)
		if card.rank == "A":
			aces += 1
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return {"total": total, "soft": aces > 0}


## The play basic strategy calls for. `dealer_up` is the upcard's value,
## with an ace counted as 11.
static func basic(hand: Array, dealer_up: int, can_double: bool) -> Dictionary:
	var shape := evaluate(hand)
	if shape.soft:
		return _basic_soft(int(shape.total), dealer_up, can_double)
	return _basic_hard(int(shape.total), dealer_up, can_double)


## The play once the true count is taken into account. Adds `deviates`,
## true when the count moves the play off basic strategy.
static func with_count(hand: Array, dealer_up: int, can_double: bool, true_count: float) -> Dictionary:
	var shape := evaluate(hand)
	var base := basic(hand, dealer_up, can_double)

	if not shape.soft:
		for entry in DEVIATIONS:
			var d: Dictionary = entry
			if int(d.total) != int(shape.total) or int(d.up) != dealer_up:
				continue
			return _resolve_index(d, base, dealer_up, can_double, true_count)

	return {
		"action": base.action,
		"reason": "No index play covers %s vs %s, so the count doesn't change it. %s" % [
			_hand_label(shape), up_label(dealer_up), base.reason],
		"deviates": false,
	}


static func up_label(up: int) -> String:
	return "A" if up == 11 else str(up)


# --- Internals ---------------------------------------------------------------

static func _resolve_index(d: Dictionary, base: Dictionary, dealer_up: int, can_double: bool, true_count: float) -> Dictionary:
	var index := float(d.index)
	var wanted: String = d.above if true_count >= index else d.below
	var note := ""

	# A doubling index can't be taken on a hand that may no longer double.
	if wanted == "Double" and not can_double:
		wanted = "Hit"
		note = " Doubling isn't available on this hand, so hit instead."

	var rule := "%s on %d vs %s at a true count of %s or higher, otherwise %s." % [
		String(d.above), int(d.total), up_label(dealer_up),
		_signed(index), String(d.below).to_lower()]
	var reason := "%s The count is %s, so %s.%s" % [
		rule, _signed(true_count), wanted.to_lower(), note]

	return {
		"action": wanted,
		"reason": reason,
		"deviates": wanted != base.action,
	}


static func _basic_hard(total: int, up: int, can_double: bool) -> Dictionary:
	if total > 21:
		return _act("Stand", "This hand is already busted at %d." % total)
	if total >= 17:
		return _act("Stand", "Hard %d stands: any card above a 4 busts it, and it already beats a dealer bust." % total)
	if total >= 13:
		if up <= 6:
			return _act("Stand", "Dealer's %s is a bust card, so stand on %d and let them draw into it." % [_prose(up), total])
		return _act("Hit", "Dealer's %s will usually finish 17 or better, so a stiff %d has to improve." % [_prose(up), total])
	if total == 12:
		if up >= 4 and up <= 6:
			return _act("Stand", "Dealer's %s busts often enough to beat the 31%% chance a 10 breaks your 12." % _prose(up))
		return _act("Hit", "Only a 10 busts a 12, and dealer's %s is too strong to stand against." % _prose(up))
	if total == 11:
		if up <= 10:
			return _double_or("Hit", can_double, "11 is the strongest doubling total — one card reaches 20 or 21 more often than not.")
		return _act("Hit", "Basic strategy hits 11 against an ace: the dealer makes 21 too often to risk a doubled bet.")
	if total == 10:
		if up <= 9:
			return _double_or("Hit", can_double, "10 draws to 20 while dealer's %s is behind, so double the bet." % _prose(up))
		return _act("Hit", "Dealer's %s reaches 20 as easily as you do, so take one card without doubling." % _prose(up))
	if total == 9:
		if up >= 3 and up <= 6:
			return _double_or("Hit", can_double, "9 against a weak %s is a small but real doubling edge." % _prose(up))
		return _act("Hit", "9 needs improving, and dealer's %s isn't weak enough to double into." % _prose(up))
	return _act("Hit", "Hard %d can't bust, so always take another card." % total)


static func _basic_soft(total: int, up: int, can_double: bool) -> Dictionary:
	if total >= 19:
		return _act("Stand", "Soft %d already beats the dealer's average hand — don't touch it." % total)
	if total == 18:
		if up >= 3 and up <= 6:
			return _double_or("Stand", can_double, "Soft 18 doubles against a weak %s: the ace means one card can't bust you." % _prose(up))
		if up == 2 or up == 7 or up == 8:
			return _act("Stand", "Soft 18 stands against %s — it ties or beats the dealer's likely total." % _prose(up))
		return _act("Hit", "Soft 18 loses to a %s more often than it wins, and the ace makes hitting free." % _prose(up))
	if total == 17:
		if up >= 3 and up <= 6:
			return _double_or("Hit", can_double, "Soft 17 doubles against 3-6: you can't bust and the dealer is weak.")
		return _act("Hit", "Soft 17 never stands — 17 rarely wins and the ace makes drawing risk-free.")
	if total >= 15:
		if up >= 4 and up <= 6:
			return _double_or("Hit", can_double, "Soft %d doubles against 4-6, the dealer's weakest upcards." % total)
		return _act("Hit", "Soft %d is free to improve, and dealer's %s isn't weak enough to double." % [total, _prose(up)])
	if total >= 13:
		if up == 5 or up == 6:
			return _double_or("Hit", can_double, "Soft %d doubles against 5 and 6 only — the dealer's two worst cards." % total)
		return _act("Hit", "Soft %d can't bust, so take a card." % total)
	return _act("Hit", "Soft %d always draws; there's no way to bust." % total)


static func _double_or(fallback: String, can_double: bool, reason: String) -> Dictionary:
	if can_double:
		return _act("Double", reason)
	return _act(fallback, "%s Doubling isn't available on this hand, so %s instead." % [reason, fallback.to_lower()])


static func _act(action: String, reason: String) -> Dictionary:
	return {"action": action, "reason": reason}


static func _prose(up: int) -> String:
	return "ace" if up == 11 else str(up)


static func _hand_label(shape: Dictionary) -> String:
	return "soft %d" % int(shape.total) if shape.soft else "hard %d" % int(shape.total)


static func _signed(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%+d" % int(roundf(value))
	return "%+.1f" % value

class_name BlackjackStrategy
extends RefCounted
## Hi-Lo counting values plus basic and count-deviated playing strategy.
##
## Strategy assumes the house rules the table actually deals: a dealer who
## stands on all 17s, doubling on any first two cards, doubling after a split,
## splitting to at most four hands, and split aces drawing one card each.

## Cards counted +1 by the Hi-Lo system; 7-9 are neutral and everything
## else (10, J, Q, K, A) counts -1.
const HI_LO_PLUS := ["2", "3", "4", "5", "6"]
const HI_LO_NEUTRAL := ["7", "8", "9"]

## True count at or above which insurance stops being a losing bet.
const INSURANCE_INDEX := 3.0

## Index plays for hard totals, from the Illustrious 18. `above` applies at a
## true count >= `index`, `below` under it.
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

## The two pair index plays in the Illustrious 18: splitting tens against a
## dealer bust card once the shoe is rich enough.
const PAIR_DEVIATIONS := [
	{"value": 10, "up": 5, "index": 5.0, "above": "Split", "below": "Stand"},
	{"value": 10, "up": 6, "index": 4.0, "above": "Split", "below": "Stand"},
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


## Two cards of matching value, which is what a table lets you split.
static func is_pair(hand: Array) -> bool:
	return hand.size() == 2 and int(hand[0].value) == int(hand[1].value)


## The play basic strategy calls for. `dealer_up` is the upcard's value,
## with an ace counted as 11.
static func basic(hand: Array, dealer_up: int, can_double: bool, can_split: bool) -> Dictionary:
	if is_pair(hand):
		var pair_value := int(hand[0].value)
		var pair_play := _pair_action(pair_value, dealer_up)
		if pair_play == "Split":
			if can_split:
				return _act("Split", _pair_reason(pair_value, dealer_up))
			var fallback := _basic_total(hand, dealer_up, can_double)
			return _act(fallback.action, "Basic strategy splits %s here, but this hand can't be split, so %s instead. %s" % [
				_pair_name(pair_value), String(fallback.action).to_lower(), fallback.reason])
		if pair_play == "Stand":
			return _act("Stand", _pair_reason(pair_value, dealer_up))
	return _basic_total(hand, dealer_up, can_double)


## The play once the true count is taken into account. Adds `deviates`,
## true when the count moves the play off basic strategy.
static func with_count(hand: Array, dealer_up: int, can_double: bool, can_split: bool, true_count: float) -> Dictionary:
	var shape := evaluate(hand)
	var base := basic(hand, dealer_up, can_double, can_split)

	if is_pair(hand) and can_split:
		var pair_value := int(hand[0].value)
		for entry in PAIR_DEVIATIONS:
			var d: Dictionary = entry
			if int(d.value) != pair_value or int(d.up) != dealer_up:
				continue
			return _resolve_index(d, base, dealer_up, can_double, true_count, _pair_name(pair_value))
		if base.action == "Split":
			return {
				"action": "Split",
				"reason": "No index play changes splitting %s — it stays right at every count." % _pair_name(pair_value),
				"deviates": false,
			}

	if not shape.soft:
		for entry in DEVIATIONS:
			var d: Dictionary = entry
			if int(d.total) != int(shape.total) or int(d.up) != dealer_up:
				continue
			return _resolve_index(d, base, dealer_up, can_double, true_count, str(int(d.total)))

	return {
		"action": base.action,
		"reason": "No index play covers %s vs %s, so the count doesn't change it. %s" % [
			_hand_label(shape), up_label(dealer_up), base.reason],
		"deviates": false,
	}


## Whether the insurance side bet is worth taking at this count.
static func insurance(true_count: float) -> Dictionary:
	if true_count >= INSURANCE_INDEX:
		return {
			"take": true,
			"reason": "Take insurance at a true count of +3 or higher — that's where tens are dense enough for it to profit. The count is %s." % _signed(true_count),
		}
	return {
		"take": false,
		"reason": "Insurance is a side bet on tens, not a hedge, and it loses below a true count of +3. The count is %s." % _signed(true_count),
	}


static func up_label(up: int) -> String:
	return "A" if up == 11 else str(up)


# --- Internals ---------------------------------------------------------------

## Returns "Split", "Stand", or "" when the pair has no rule of its own and
## should simply be played on its total.
static func _pair_action(pair_value: int, up: int) -> String:
	match pair_value:
		11:
			return "Split"
		10:
			return "Stand"
		9:
			if up == 7 or up >= 10:
				return "Stand"
			return "Split"
		8:
			return "Split"
		7:
			return "Split" if up <= 7 else ""
		6:
			return "Split" if up <= 6 else ""
		5:
			return ""
		4:
			return "Split" if up == 5 or up == 6 else ""
		3, 2:
			return "Split" if up <= 7 else ""
	return ""


static func _pair_reason(pair_value: int, up: int) -> String:
	match pair_value:
		11:
			return "Always split aces — two hands starting at 11 beat one soft 12."
		10:
			return "Never split a 20; it already beats almost everything the dealer makes."
		9:
			if up == 7 or up >= 10:
				return "Stand on 18 against %s — splitting here gives up a good hand." % _prose(up)
			return "Split 9s against %s: 18 isn't strong enough to settle for." % _prose(up)
		8:
			return "Always split 8s — 16 is the worst total in the game, and two hands from 8 are far better."
		7:
			return "Split 7s against a weak %s; 14 is a losing total." % _prose(up)
		6:
			return "Split 6s against a bust card; 12 is too weak to play as one hand."
		4:
			return "Split 4s only against 5-6, where doubling after the split pays for it."
		3, 2:
			return "Split against %s — with doubling allowed after a split, two live hands beat one bad one." % _prose(up)
	return "Play this pair on its total."


static func _pair_name(pair_value: int) -> String:
	if pair_value == 11:
		return "aces"
	return "%ds" % pair_value


static func _resolve_index(d: Dictionary, base: Dictionary, dealer_up: int, can_double: bool, true_count: float, subject: String) -> Dictionary:
	var index := float(d.index)
	var wanted: String = d.above if true_count >= index else d.below
	var note := ""

	# A doubling index can't be taken on a hand that may no longer double.
	if wanted == "Double" and not can_double:
		wanted = "Hit"
		note = " Doubling isn't available on this hand, so hit instead."

	var rule := "%s on %s vs %s at a true count of %s or higher, otherwise %s." % [
		String(d.above), subject, up_label(dealer_up),
		_signed(index), String(d.below).to_lower()]
	var reason := "%s The count is %s, so %s.%s" % [
		rule, _signed(true_count), wanted.to_lower(), note]

	return {
		"action": wanted,
		"reason": reason,
		"deviates": wanted != base.action,
	}


static func _basic_total(hand: Array, up: int, can_double: bool) -> Dictionary:
	var shape := evaluate(hand)
	if shape.soft:
		return _basic_soft(int(shape.total), up, can_double)
	return _basic_hard(int(shape.total), up, can_double)


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
	return "an ace" if up == 11 else str(up)


static func _hand_label(shape: Dictionary) -> String:
	return "soft %d" % int(shape.total) if shape.soft else "hard %d" % int(shape.total)


static func _signed(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%+d" % int(roundf(value))
	return "%+.1f" % value

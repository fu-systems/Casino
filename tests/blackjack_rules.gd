extends CasinoTest
## Blackjack rules, driven against the real table scene.
##
## The shoe is stacked directly where a scenario needs to be deterministic,
## which is the only way to test things like split aces or a dealer natural
## without waiting on luck.

const RANKS := {
	"A": 11, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
	"8": 8, "9": 9, "10": 10, "J": 10, "Q": 10, "K": 10,
}

# Phase enum on the table, restated so the tests don't silently follow a
# renumbering.
const BETTING := 0
const INSURANCE := 1
const PLAYER_TURN := 2
const DEALER_TURN := 3
const ROUND_OVER := 4

var t: Control
var start_balance := 0


func run() -> void:
	t = load("res://scenes/blackjack.tscn").instantiate()
	add_child(t)
	await frames()

	_test_hi_lo()
	_test_shoe_composition()
	_test_basic_strategy()
	_test_pair_strategy()
	_test_indices()
	_test_insurance_advice()
	await _test_hole_card_excluded()
	await _test_count_invariant()
	await _test_reshuffle()
	await _test_split()
	await _test_split_aces()
	_test_split_limits()
	await _test_double_after_split()
	await _test_insurance_pays()
	await _test_multi_hand_settlement()

	t.queue_free()


# --- helpers -----------------------------------------------------------------

func _card(rank: String) -> Dictionary:
	return {"rank": rank, "suit": "S", "value": RANKS[rank]}


func _hand(ranks: Array) -> Array:
	var out: Array = []
	for r in ranks:
		out.append(_card(r))
	return out


func _hi_lo_sum(cards: Array) -> int:
	var total := 0
	for c in cards:
		total += BlackjackStrategy.hi_lo(c)
	return total


## Stacks the shoe so `ranks[0]` is dealt next, with neutral filler behind it.
func _stack(ranks: Array, stake: int = 100) -> void:
	Bank.reset()
	Bank.deposit(500000)
	t.phase = BETTING
	t.bet = stake
	t.deck_count = 6
	t.shoe_start_size = 312
	var filler: Array = []
	for i in 150:
		filler.append(_card("8"))
	var ordered := _hand(ranks)
	ordered.reverse()
	t.shoe = filler + ordered
	t.running_count = 0
	start_balance = Bank.balance
	t._on_deal_pressed()


func _round_over() -> void:
	await settle(func() -> bool: return t.phase == ROUND_OVER, 20000, "the round to finish")


# --- counting ----------------------------------------------------------------

func _test_hi_lo() -> void:
	for r in ["2", "3", "4", "5", "6"]:
		check(BlackjackStrategy.hi_lo(_card(r)) == 1, "hi_lo(%s) should be +1" % r)
	for r in ["7", "8", "9"]:
		check(BlackjackStrategy.hi_lo(_card(r)) == 0, "hi_lo(%s) should be 0" % r)
	for r in ["10", "J", "Q", "K", "A"]:
		check(BlackjackStrategy.hi_lo(_card(r)) == -1, "hi_lo(%s) should be -1" % r)
	note("Hi-Lo values: +1 on 2-6, 0 on 7-9, -1 on tens and aces")


func _test_shoe_composition() -> void:
	for decks in range(1, 9):
		t.deck_count = decks
		t._reshuffle_shoe()
		check(t.shoe.size() == 52 * decks, "%d-deck shoe should hold %d cards" % [decks, 52 * decks])
		var per_rank := {}
		for c in t.shoe:
			per_rank[c.rank] = int(per_rank.get(c.rank, 0)) + 1
		for r in RANKS:
			check(int(per_rank.get(r, 0)) == 4 * decks,
				"%d-deck shoe should hold %d %ss" % [decks, 4 * decks, r])
		check(_hi_lo_sum(t.shoe) == 0, "a full %d-deck shoe must be count-neutral" % decks)
		check(t.running_count == 0, "reshuffle must zero the running count")
	note("shoes of 1-8 decks are complete, balanced, and reset the count")


func _test_hole_card_excluded() -> void:
	t.deck_count = 6
	t._reshuffle_shoe()
	_stack(["10", "6", "7", "9", "5"])
	await frames()
	if t.phase == ROUND_OVER:
		return  # a natural ended it; the invariant test still covers this
	var visible: Array = t.hands[0].cards.duplicate()
	visible.append(t.dealer_hand[0])
	check(t.running_count == _hi_lo_sum(visible),
		"count should equal the Hi-Lo sum of the cards actually visible")
	check(not t.hole_counted, "the hole card must not be counted while face down")
	var before: int = t.running_count
	var hole: int = BlackjackStrategy.hi_lo(t.dealer_hand[1])
	t._reveal_hole()
	check(t.running_count == before + hole, "revealing the hole should add its value")
	t._on_stand_pressed()
	await _round_over()
	note("the hole card stays out of the count until it is turned over")


func _test_count_invariant() -> void:
	# A full shoe sums to zero, so once every dealt card is face up the running
	# count must be the exact negative of what is left undealt.
	t.deck_count = 2
	t._reshuffle_shoe()
	Bank.reset()
	Bank.deposit(500000)
	var rounds := 0
	for i in 30:
		var before: int = t.shoe.size()
		t.phase = BETTING
		t.bet = 25
		t._on_deal_pressed()
		if t.phase == INSURANCE:
			t._on_insurance_pressed(i % 2 == 0)
			await frames()
		while t.phase == PLAYER_TURN:
			if t._can_split():
				t._on_split_pressed()
			else:
				t._on_stand_pressed()
			await frames()
		await _round_over()
		if t.shoe.size() > before:
			continue  # a reshuffle landed mid-test
		rounds += 1
		var expected := -_hi_lo_sum(t.shoe)
		if t.running_count != expected:
			fail("after round %d count is %d but the undealt shoe implies %d" % [
				i, t.running_count, expected])
			break
	check(rounds >= 15, "only %d comparable rounds ran" % rounds)
	note("count matched the undealt shoe across %d split/insured rounds" % rounds)


func _test_reshuffle() -> void:
	t.deck_count = 1
	t._reshuffle_shoe()
	Bank.reset()
	Bank.deposit(500000)
	var threshold: int = t._reshuffle_threshold()
	check(threshold == 13, "a 1-deck shoe should cut at 13 cards, got %d" % threshold)
	var saw := false
	for i in 40:
		var before: int = t.shoe.size()
		t.phase = BETTING
		t.bet = 25
		t._on_deal_pressed()
		if t.phase == INSURANCE:
			t._on_insurance_pressed(false)
			await frames()
		while t.phase == PLAYER_TURN:
			t._on_stand_pressed()
			await frames()
		await _round_over()
		if t.shoe.size() > before:
			saw = true
			check(before <= threshold, "reshuffled with %d cards left, cut is %d" % [before, threshold])
			check(t.shoe_start_size == 52, "a reshuffled 1-deck shoe should be sized 52")
			break
	check(saw, "a 1-deck shoe should have reshuffled within 40 rounds")
	note("the shoe reshuffles once the last quarter is reached")


# --- strategy ----------------------------------------------------------------

func _expect_basic(ranks: Array, up: int, can_double: bool, want: String) -> void:
	var got: String = BlackjackStrategy.basic(_hand(ranks), up, can_double, false).action
	check(got == want, "basic %s vs %d (double=%s) gave %s, want %s" % [
		str(ranks), up, can_double, got, want])


func _test_basic_strategy() -> void:
	_expect_basic(["10", "7"], 10, false, "Stand")
	_expect_basic(["10", "6"], 10, false, "Hit")
	_expect_basic(["10", "6"], 6, false, "Stand")
	_expect_basic(["10", "2"], 4, false, "Stand")
	_expect_basic(["10", "2"], 3, false, "Hit")
	_expect_basic(["9", "2"], 5, true, "Double")
	_expect_basic(["9", "2"], 11, true, "Hit")     # 11 vs A hits under S17
	_expect_basic(["9", "2"], 5, false, "Hit")
	_expect_basic(["6", "4"], 9, true, "Double")
	_expect_basic(["6", "4"], 10, true, "Hit")
	_expect_basic(["5", "4"], 4, true, "Double")
	_expect_basic(["5", "4"], 2, true, "Hit")
	_expect_basic(["A", "9"], 6, true, "Stand")
	_expect_basic(["A", "8"], 6, true, "Stand")    # soft 19 stands under S17
	_expect_basic(["A", "7"], 4, true, "Double")
	_expect_basic(["A", "7"], 8, true, "Stand")
	_expect_basic(["A", "7"], 9, true, "Hit")
	_expect_basic(["A", "7"], 4, false, "Stand")   # Ds: stand when double is off
	_expect_basic(["A", "6"], 4, true, "Double")
	_expect_basic(["A", "2"], 5, true, "Double")
	_expect_basic(["A", "2"], 4, true, "Hit")
	note("non-pair basic strategy matches the S17 chart")


func _expect_pair(ranks: Array, up: int, want: String, can_split: bool = true) -> void:
	var got: String = BlackjackStrategy.basic(_hand(ranks), up, true, can_split).action
	check(got == want, "pair %s vs %d (split=%s) gave %s, want %s" % [
		str(ranks), up, can_split, got, want])


func _test_pair_strategy() -> void:
	_expect_pair(["A", "A"], 6, "Split")
	_expect_pair(["A", "A"], 10, "Split")
	_expect_pair(["8", "8"], 10, "Split")
	_expect_pair(["10", "K"], 6, "Stand")          # never split 20
	_expect_pair(["9", "9"], 6, "Split")
	_expect_pair(["9", "9"], 7, "Stand")
	_expect_pair(["9", "9"], 11, "Stand")
	_expect_pair(["7", "7"], 7, "Split")
	_expect_pair(["7", "7"], 8, "Hit")
	_expect_pair(["6", "6"], 6, "Split")
	_expect_pair(["6", "6"], 7, "Hit")
	_expect_pair(["5", "5"], 6, "Double")          # played as hard 10
	_expect_pair(["4", "4"], 5, "Split")
	_expect_pair(["4", "4"], 2, "Hit")
	_expect_pair(["3", "3"], 7, "Split")
	_expect_pair(["2", "2"], 8, "Hit")
	_expect_pair(["8", "8"], 10, "Hit", false)     # falls back to its total
	note("pair chart matches the double-after-split table")


func _expect_index(ranks: Array, up: int, tc: float, want: String, deviates: bool) -> void:
	var play := BlackjackStrategy.with_count(_hand(ranks), up, true, false, tc)
	check(play.action == want, "index %s vs %d at TC %.1f gave %s, want %s" % [
		str(ranks), up, tc, play.action, want])
	check(bool(play.deviates) == deviates,
		"index %s vs %d at TC %.1f: deviates=%s, want %s" % [str(ranks), up, tc, play.deviates, deviates])


func _test_indices() -> void:
	_expect_index(["10", "6"], 10, -1.0, "Hit", false)
	_expect_index(["10", "6"], 10, 0.0, "Stand", true)
	_expect_index(["10", "5"], 10, 3.0, "Hit", false)
	_expect_index(["10", "5"], 10, 4.0, "Stand", true)
	_expect_index(["10", "2"], 3, 1.0, "Hit", false)
	_expect_index(["10", "2"], 3, 2.0, "Stand", true)
	_expect_index(["10", "3"], 2, -2.0, "Hit", true)
	_expect_index(["10", "3"], 2, -1.0, "Stand", false)
	_expect_index(["9", "2"], 11, 0.0, "Hit", false)
	_expect_index(["9", "2"], 11, 1.0, "Double", true)
	_expect_index(["5", "4"], 2, 1.0, "Double", true)
	_expect_index(["6", "4"], 10, 4.0, "Double", true)
	_expect_index(["6", "4"], 10, 3.0, "Hit", false)
	# The two ten-splitting indices.
	check(BlackjackStrategy.with_count(_hand(["10", "K"]), 5, true, true, 5.0).action == "Split",
		"10,10 vs 5 should split at TC +5")
	check(BlackjackStrategy.with_count(_hand(["10", "K"]), 5, true, true, 4.0).action == "Stand",
		"10,10 vs 5 should stand below TC +5")
	check(BlackjackStrategy.with_count(_hand(["10", "K"]), 6, true, true, 4.0).action == "Split",
		"10,10 vs 6 should split at TC +4")
	note("hard-total and pair indices flip at their published numbers")


func _test_insurance_advice() -> void:
	check(not BlackjackStrategy.insurance(2.9).take, "decline insurance below TC +3")
	check(BlackjackStrategy.insurance(3.0).take, "take insurance at TC +3")
	check(not BlackjackStrategy.insurance(-1.0).take, "decline insurance at a negative count")
	note("insurance advice turns on at true count +3")


# --- splitting and insurance -------------------------------------------------

func _test_split() -> void:
	_stack(["8", "6", "8", "9", "3", "4"])
	check(t.phase == PLAYER_TURN, "expected the player's turn")
	check(t._can_split(), "8,8 should be splittable")
	var before: int = Bank.balance
	t._on_split_pressed()
	await frames()
	check(t.hands.size() == 2, "splitting should make a second hand")
	check(Bank.balance == before - 100, "the split should stake a second $100")
	check(int(t.hands[0].bet) == 100 and int(t.hands[1].bet) == 100, "both hands carry $100")
	check(t.hands[0].cards.size() == 2, "the played hand draws its second card at once")
	check(t.hands[1].cards.size() == 1, "the waiting hand is dealt to on arrival")
	t._on_stand_pressed()
	await frames()
	check(t.active_hand == 1, "standing should advance to hand 2")
	check(t.hands[1].cards.size() == 2, "hand 2 is dealt its second card on arrival")
	t._on_stand_pressed()
	await _round_over()
	note("splitting makes two independently staked hands")


func _test_split_aces() -> void:
	# Each split ace draws a ten, the dealer draws to 18: both hands win 1:1.
	_stack(["A", "6", "A", "9", "10", "K", "3"])
	t._on_split_pressed()
	await _round_over()
	check(t.hands.size() == 2, "aces should split into two hands")
	check(t.hands[0].cards.size() == 2 and t.hands[1].cards.size() == 2,
		"each split ace draws exactly one card")
	check(bool(t.hands[0].split_aces) and bool(t.hands[1].split_aces), "both flagged as split aces")
	# Paying either as a 3:2 blackjack would show up as +$250 or more.
	var net: int = Bank.balance - start_balance
	check(net == 200, "two winning split-ace hands should net +$200, got %+d" % net)
	note("split aces take one card each and pay 1:1, not 3:2")


func _test_split_limits() -> void:
	Bank.reset()
	Bank.deposit(500000)
	t.phase = PLAYER_TURN
	t.hands = []
	for i in 4:
		t.hands.append({"cards": _hand(["8", "8"]), "bet": 100, "done": false, "split_aces": false})
	t.active_hand = 0
	check(not t._can_split(), "a fourth hand must not split again")
	t.hands.resize(3)
	check(t._can_split(), "three hands should still allow one more split")
	t.hands = [{"cards": _hand(["A", "A"]), "bet": 100, "done": false, "split_aces": true}]
	check(not t._can_split(), "split aces are never re-split")
	t.hands = [{"cards": _hand(["8", "8"]), "bet": 100, "done": false, "split_aces": false}]
	var saved: int = Bank.balance
	Bank.withdraw(saved - 50)
	check(not t._can_split(), "splitting needs the extra stake in the bank")
	Bank.deposit(saved)
	t.phase = ROUND_OVER
	t._on_new_round_pressed()
	note("split capped at four hands, aces never re-split, stake required")


func _test_double_after_split() -> void:
	_stack(["8", "6", "8", "9", "3", "4", "10", "10"])
	t._on_split_pressed()
	await frames()
	check(t._can_double(), "doubling should be allowed after a split")
	var before: int = Bank.balance
	t._on_double_pressed()
	await frames()
	check(int(t.hands[0].bet) == 200, "doubling should take hand 1 to $200")
	check(int(t.hands[1].bet) == 100, "doubling hand 1 must not touch hand 2")
	check(Bank.balance == before - 100, "doubling stakes another $100")
	check(t.phase == PLAYER_TURN and t.active_hand == 1, "play should pass to hand 2")
	t._on_stand_pressed()
	await _round_over()
	note("double after split raises only that hand's stake")


func _test_insurance_pays() -> void:
	# Dealer shows an ace over a king: a natural.
	_stack(["10", "A", "7", "K"])
	check(t.phase == INSURANCE, "an ace upcard should offer insurance")
	t._on_insurance_pressed(true)
	await frames()
	check(t.phase == ROUND_OVER, "a dealer natural ends the round")
	check(int(t.insurance_bet) == 50, "the premium should be half the $100 bet")
	# The whole point of insurance: $50 at 2:1 returns $150, exactly cancelling
	# the $100 main bet lost to the natural.
	check(Bank.balance - start_balance == 0,
		"insurance should exactly offset the lost main bet, got %+d" % (Bank.balance - start_balance))

	# And it is simply lost when the dealer has no natural.
	_stack(["10", "A", "7", "5"])
	var before: int = Bank.balance
	t._on_insurance_pressed(true)
	await frames()
	check(t.phase == PLAYER_TURN, "play continues when the dealer has no natural")
	check(Bank.balance == before - 50, "the lost premium should be $50")
	t._on_stand_pressed()
	await _round_over()

	# Never offered against anything but an ace.
	_stack(["10", "10", "7", "5"])
	check(t.phase != INSURANCE, "a ten upcard must not offer insurance")
	t.phase = ROUND_OVER
	t._on_new_round_pressed()
	note("insurance pays 2:1 on a natural, is lost otherwise, offered only vs an ace")


func _test_multi_hand_settlement() -> void:
	# Split 8s: hand 1 makes 18 and wins, hand 2 makes 12 and loses to the
	# dealer's 17. Net zero on $100 a side.
	_stack(["8", "7", "8", "10", "10", "4", "8"])
	t._on_split_pressed()
	await frames()
	check(t._hand_value(t.hands[0].cards) == 18, "hand 1 should be 8+10=18")
	t._on_stand_pressed()
	await frames()
	check(t._hand_value(t.hands[1].cards) == 12, "hand 2 should be 8+4=12")
	t._on_stand_pressed()
	await _round_over()
	check(t._hand_value(t.dealer_hand) == 17, "the dealer should stand on 17")
	check(Bank.balance - start_balance == 0,
		"one hand winning and one losing at $100 should net zero, got %+d" % (Bank.balance - start_balance))
	note("split hands settle against the dealer independently")

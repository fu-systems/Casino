extends CasinoTest
## The Card Counting Trainer: that the simulated table deals in table order,
## that its players and dealer play the house's rules, that the count it
## checks you against is exactly the Hi-Lo count of what you saw, and that
## the drill scores and ends runs fairly.

const ROUNDS := 1500


func run() -> void:
	_test_deal_order()
	_test_rounds()
	_test_checks_never_at_shoe_end()
	await _test_drill()


func _seeded_shoe(decks: int, seed: int) -> BlackjackShoe:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var shoe := BlackjackShoe.new(decks, rng)
	shoe.reshuffle()
	return shoe


func _test_deal_order() -> void:
	var shoe := _seeded_shoe(6, 1)
	var events: Array = BlackjackRoundSim.deal_round(shoe, 5).events
	var expected := [0, 1, 2, 3, 4, -1, 0, 1, 2, 3, 4, -1]
	for i in expected.size():
		check(int(events[i].seat) == expected[i], "card %d should go to seat %d, went to %d" % [
			i, expected[i], int(events[i].seat)])
	check(events[5].face_up and not events[11].face_up, "the dealer's first card is up, the second face down")
	check(int(events[11].count) == int(events[10].count), "the hole card isn't counted while it's face down")
	var reveal := -1
	for i in events.size():
		if events[i].type == "reveal":
			reveal = i
	check(reveal > 11, "the hole card should be turned over after the deal")
	if reveal > 0:
		check(int(events[reveal].count) == int(events[reveal - 1].count) + BlackjackStrategy.hi_lo(events[reveal].card),
			"turning the hole card over should count it")
	note("cards go round the table in order, the hole card counted only when it turns over")


## Thousands of rounds: every seat plays basic strategy, the dealer stands
## on all 17s, and the count is the Hi-Lo sum of every card that was seen.
func _test_rounds() -> void:
	var shoe := _seeded_shoe(6, 2)
	var splits := 0
	var doubles := 0
	for r in ROUNDS:
		if shoe.is_spent():
			shoe.reshuffle()
		var start_count := shoe.running_count
		var result := BlackjackRoundSim.deal_round(shoe, 7)
		var events: Array = result.events
		var dealer: Array = result.dealer
		var up := int(dealer[0].value)

		var seen := start_count
		for e in events:
			if e.type == "reveal" or (e.type == "card" and e.face_up):
				seen += BlackjackStrategy.hi_lo(e.card)
			check(int(e.count) == seen, "event count should be the running Hi-Lo sum")
		check(shoe.running_count == seen, "the shoe's count should end where the events do")

		var dealer_natural := dealer.size() == 2 and int(BlackjackStrategy.evaluate(dealer).total) == 21
		if dealer_natural and up >= 10:
			continue
		var live := false
		for seat in result.seats:
			for hand in seat:
				var outcome := _check_played(hand, up, seat.size() > 1)
				if outcome == "double":
					doubles += 1
				if int(BlackjackStrategy.evaluate(hand).total) <= 21 and not (seat.size() == 1 and hand.size() == 2 and int(BlackjackStrategy.evaluate(hand).total) == 21):
					live = true
			if seat.size() > 1:
				splits += 1
				check(seat.size() <= BlackjackRoundSim.MAX_HANDS_PER_SEAT, "a seat splits at most once")
		var dealer_total := int(BlackjackStrategy.evaluate(dealer).total)
		if live:
			check(dealer_total >= 17, "the dealer draws to 17, stopped at %d" % dealer_total)
			check(int(BlackjackStrategy.evaluate(dealer.slice(0, dealer.size() - 1)).total) < 17 or dealer.size() == 2,
				"the dealer stands on any 17")
	check(splits > 0 and doubles > 0, "the players should split and double sometimes (%d, %d)" % [splits, doubles])
	note("%d rounds at seven seats: basic strategy, dealer stands on 17, count exact (%d splits, %d doubles)" % [
		ROUNDS, splits, doubles])


## Replays a finished hand decision by decision and checks each was the
## basic-strategy play. Returns "double" for a doubled hand.
func _check_played(hand: Array, up: int, was_split: bool) -> String:
	var split_aces: bool = was_split and hand[0].rank == "A"
	if split_aces:
		check(hand.size() == 2, "split aces get exactly one card each")
		return "split_aces"
	for n in range(2, hand.size() + 1):
		var prefix := hand.slice(0, n)
		var total := int(BlackjackStrategy.evaluate(prefix).total)
		if total >= 21:
			check(n == hand.size(), "a hand stops at 21 or a bust")
			return ""
		var can_double := n == 2
		# The pair at the start of a split hand can't split again (one split
		# per seat), and a pair kept together only stays together if basic
		# strategy said not to split it.
		var can_split := n == 2 and not was_split and BlackjackStrategy.is_pair(prefix)
		var play: String = BlackjackStrategy.basic(prefix, up, can_double, can_split).action
		if n == hand.size():
			check(play == "Stand", "%s v %d stood but basic strategy says %s" % [prefix, up, play])
			return ""
		if play == "Double":
			check(hand.size() == 3, "%s v %d doubled, so it should take exactly one card" % [prefix, up])
			return "double"
		check(play == "Hit", "%s v %d drew a card but basic strategy says %s" % [prefix, up, play])
	return ""


func _test_checks_never_at_shoe_end() -> void:
	for decks in [2, 4, 6, 8]:
		var shoe := _seeded_shoe(decks, decks)
		var smallest := 10000
		for r in 800:
			if shoe.is_spent():
				shoe.reshuffle()
			BlackjackRoundSim.deal_round(shoe, 7)
			smallest = mini(smallest, shoe.cards.size())
		check(smallest > 0, "a %d-deck count check came at the very end of the shoe" % decks)
	note("count checks never fall at the end of a shoe, where the count is always 0")


func _test_drill() -> void:
	Store.use_test_backend()
	Store.buy("count_trainer")
	var d: Control = load("res://scenes/count_drill.tscn").instantiate()
	add_child(d)
	await frames()
	var setup: Modal = d.get_node_or_null("Setup")
	check(setup != null, "the drill should open on its settings")
	if setup != null:
		setup.close()
	d.difficulty = "casino"
	d.seat_count = 5
	d.decks = 6
	d.ask_true = false
	d.start_run()

	# Deal the round out tap by tap; the pad appears with the last card.
	var taps := 0
	while d.phase == d.Phase.DEALING and taps < 200:
		d.advance()
		taps += 1
	check(d.phase == d.Phase.ANSWER, "the count is asked for once the round is dealt")
	check(d.tray == d.shoe.start_size - d.shoe.cards.size(),
		"by the end of the round the tray holds every card dealt, %d vs %d" % [
			d.tray, d.shoe.start_size - d.shoe.cards.size()])
	var expected := int(d.events[-1].count)
	var pad: Modal = d.get_node_or_null("Pad")
	check(pad != null, "a number pad should ask for the count")
	_type(d, expected)
	check(d.entered() == expected, "the pad should build %+d, got %+d" % [expected, d.entered()])
	d._on_running_count(d.entered())
	if pad != null:
		pad.close()
	check(d.run_rounds == 1 and d.run_cards > 0, "a right count should score the round's cards")
	check(d.phase == d.Phase.DEALING, "a right count deals the next round")

	# A round too slow for the limit ends the run.
	d.advance()
	d._process(21.0)
	await frames()
	check(d.phase == d.Phase.OVER, "a round over the time limit should end the run")
	var over: Modal = d.get_node_or_null("RunOver")
	check(over != null and "Too slow" in _text(over), "the run summary should say why it ended")
	check(int(SaveData.get_value("count_trainer", "most_cards_casino", 0)) == d.run_cards,
		"the run's cards should be saved as the best")
	if over != null:
		over.close()

	# A wrong count ends the run too, and the true count accepts rounding.
	d.ask_true = true
	d.start_run()
	while d.phase == d.Phase.DEALING:
		d.advance()
	var count := int(d.events[-1].count)
	d._on_running_count(count)
	var shown: float = d.true_count_shown()
	d._on_true_count(roundi(shown))
	check(d.phase == d.Phase.DEALING, "a true count rounded to the nearest whole number is right")
	while d.phase == d.Phase.DEALING:
		d.advance()
	d._on_running_count(int(d.events[-1].count) + 1)
	await frames()
	check(d.phase == d.Phase.OVER, "a wrong running count should end the run")
	d.queue_free()
	await frames()
	Store.use_test_backend()
	note("the drill deals on tap, checks the count, times rounds, and records bests")


func _type(d: Control, value: int) -> void:
	for digit in str(absi(value)):
		d.press_key(digit)
	if value < 0:
		d.press_key("±")


func _text(node: Node) -> String:
	var parts: PackedStringArray = []
	if node is Label:
		parts.append(node.text)
	for child in node.get_children():
		parts.append(_text(child))
	return " ".join(parts)

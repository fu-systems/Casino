class_name BlackjackRoundSim
extends RefCounted
## Deals one whole round at a table of auto-players, for the Card Counting
## Trainer, and returns it as the cards a player at that table would see
## land, in the order they land.
##
## The seats play basic strategy — hits, doubles and splits — against a
## dealer who peeks for blackjack and stands on all 17s, the same house the
## main table deals. The hole card goes down unseen and is only counted when
## it's turned over, exactly as the table's own count does it.
##
## Events: {"type", "seat" (-1 for the dealer), "hand" (which of the seat's
## hands), "card", "face_up", "count" (the running count once this event has
## been seen)}. The type is "card" for a card dealt, "reveal" for the hole
## card turning over, or "split" when a pair is split — no new card, just
## the hand's second card moving across to start hand number `hand`.

const DEALER := -1
## Seats split at most once, so a seat never holds more than two hands; any
## more and the table stops being readable at a glance.
const MAX_HANDS_PER_SEAT := 2


## Plays a round from `shoe`, which keeps its running count up to date as
## the cards come out. Returns {"events", "seats" (each an array of hands),
## "dealer"}.
static func deal_round(shoe: BlackjackShoe, seat_count: int) -> Dictionary:
	var events: Array = []
	var seats: Array = []
	for s in seat_count:
		seats.append([[]])
	var dealer: Array = []

	# Two passes round the table, the dealer's second card face down.
	for pass_number in 2:
		for s in seat_count:
			_deal(shoe, events, seats[s][0], s, 0, true)
		_deal(shoe, events, dealer, DEALER, 0, pass_number == 0)

	var up := int(dealer[0].value)
	var dealer_natural := _is_natural(dealer)
	# The dealer peeks under a ten or an ace; a natural ends the round there.
	if dealer_natural and up >= 10:
		_reveal(shoe, events, dealer)
		return {"events": events, "seats": seats, "dealer": dealer}

	var live := false
	for s in seat_count:
		var hands: Array = seats[s]
		if _is_natural(hands[0]):
			continue
		var h := 0
		while h < hands.size():
			_play_hand(shoe, events, hands, h, s, up)
			if BlackjackStrategy.evaluate(hands[h]).total <= 21:
				live = true
			h += 1

	_reveal(shoe, events, dealer)
	# Nobody left to beat, so the dealer doesn't draw.
	if live:
		while int(BlackjackStrategy.evaluate(dealer).total) < 17:
			_deal(shoe, events, dealer, DEALER, 0, true)
	return {"events": events, "seats": seats, "dealer": dealer}


static func _play_hand(shoe: BlackjackShoe, events: Array, hands: Array, h: int, seat: int, up: int) -> void:
	var hand: Array = hands[h]
	var split_aces: bool = hands.size() > 1 and hand[0].rank == "A"
	# A split hand starts with one card and gets its second here.
	if hand.size() == 1:
		_deal(shoe, events, hand, seat, h, true)
		if split_aces:
			return
	while int(BlackjackStrategy.evaluate(hand).total) < 21:
		var can_double := hand.size() == 2
		var can_split := hand.size() == 2 and BlackjackStrategy.is_pair(hand) \
			and hands.size() < MAX_HANDS_PER_SEAT
		var play: String = BlackjackStrategy.basic(hand, up, can_double, can_split).action
		match play:
			"Stand":
				return
			"Double":
				_deal(shoe, events, hand, seat, h, true)
				return
			"Split":
				hands.append([hand.pop_back()])
				events.append({"type": "split", "seat": seat, "hand": hands.size() - 1,
					"card": hands[-1][0], "face_up": true, "count": shoe.running_count})
				_deal(shoe, events, hand, seat, h, true)
				if hand[0].rank == "A":
					return
			_:
				_deal(shoe, events, hand, seat, h, true)


static func _deal(shoe: BlackjackShoe, events: Array, hand: Array, seat: int, h: int, face_up: bool) -> void:
	# A round that outruns the whole shoe gets a fresh deck added rather than
	# a reshuffle, so the running count the player is keeping stays true.
	if shoe.cards.is_empty():
		var extra := BlackjackShoe.new(1, shoe.rng)
		extra.reshuffle()
		shoe.cards = extra.cards
	var card := shoe.draw(face_up)
	hand.append(card)
	events.append({"type": "card", "seat": seat, "hand": h, "card": card,
		"face_up": face_up, "count": shoe.running_count})


static func _reveal(shoe: BlackjackShoe, events: Array, dealer: Array) -> void:
	shoe.count(dealer[1])
	events.append({"type": "reveal", "seat": DEALER, "hand": 0, "card": dealer[1],
		"face_up": true, "count": shoe.running_count})


static func _is_natural(hand: Array) -> bool:
	return hand.size() == 2 and int(BlackjackStrategy.evaluate(hand).total) == 21

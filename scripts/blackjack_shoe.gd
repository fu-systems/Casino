class_name BlackjackShoe
extends RefCounted
## A persistent multi-deck shoe with its Hi-Lo running count, shared by the
## blackjack table and both blackjack trainers so they all deal and count
## exactly the same way.
##
## The shoe only counts what it is told to: the table passes `count_it =
## false` for the dealer's hole card and counts it on reveal, which is what a
## player at a real table can actually see.

const SUITS := ["♠", "♥", "♦", "♣"]
const RANKS := {
	"A": 11, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
	"8": 8, "9": 9, "10": 10, "J": 10, "Q": 10, "K": 10,
}
## Fraction of the shoe still undealt when the dealer reshuffles.
const RESHUFFLE_AT := 0.25

## Undealt cards; the next card is the back of the array.
var cards: Array = []
var start_size := 0
var decks := 6
var running_count := 0
## Optional, for drills that want a reproducible shoe. Without it the shoe
## shuffles from the global generator, as the table always has.
var rng: RandomNumberGenerator


func _init(deck_count: int = 6, seeded: RandomNumberGenerator = null) -> void:
	decks = deck_count
	rng = seeded


static func make_card(rank: String, suit: String = "♠") -> Dictionary:
	return {"rank": rank, "suit": suit, "value": RANKS[rank]}


## A fresh shuffled shoe with the count back at zero, as a real reshuffle.
func reshuffle() -> void:
	cards.clear()
	for _d in decks:
		for suit in SUITS:
			for rank in RANKS:
				cards.append(make_card(rank, suit))
	if rng == null:
		cards.shuffle()
	else:
		for i in range(cards.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var held: Dictionary = cards[i]
			cards[i] = cards[j]
			cards[j] = held
	start_size = cards.size()
	running_count = 0


## How many cards are left when the cut card comes out.
func threshold() -> int:
	return int(start_size * RESHUFFLE_AT)


func is_spent() -> bool:
	return cards.size() <= threshold()


## Takes the next card, counting it unless told not to. An empty shoe is
## reshuffled first; callers that care say so before drawing.
func draw(count_it: bool = true) -> Dictionary:
	if cards.is_empty():
		reshuffle()
	var card: Dictionary = cards.pop_back()
	if count_it:
		count(card)
	return card


func count(card: Dictionary) -> void:
	running_count += BlackjackStrategy.hi_lo(card)


func decks_left() -> float:
	return cards.size() / 52.0


func true_count() -> float:
	# Guarded so a nearly empty shoe can't divide the count by zero.
	return running_count / maxf(decks_left(), 0.25)

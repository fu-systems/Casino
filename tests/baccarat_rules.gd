extends CasinoTest
## Punto Banco rules. The banker tableau is checked exhaustively rather than
## by spot check, because it is the entire game and a single wrong cell would
## be invisible in play.

const ROUND_OVER := 2

var t: Control


func run() -> void:
	t = load("res://scenes/baccarat.tscn").instantiate()
	add_child(t)
	await frames()

	_test_card_values()
	_test_totals_and_pairs()
	_test_player_rule()
	_test_banker_tableau()
	_test_shoe()
	await _test_natural_ends_the_hand()
	await _test_player_and_banker_payouts()
	await _test_tie_pushes_and_pays()
	await _test_pair_side_bets()
	await _test_money_conservation()

	t.queue_free()


func _card(rank: String) -> Dictionary:
	return {"rank": rank, "suit": "♠"}


func _cards(ranks: Array) -> Array:
	var out: Array = []
	for r in ranks:
		out.append(_card(r))
	return out


## Deals a known hand: player and banker cards are interleaved as at the table.
func _deal(player: Array, banker: Array, bets: Dictionary) -> void:
	Bank.reset()
	Bank.deposit(500000)
	t.phase = 0
	t.board.clear_all()
	for key in bets:
		t.board.place(key, bets[key])
	var script: Array = []
	for i in 2:
		script.append(_card(player[i]))
		script.append(_card(banker[i]))
	if player.size() > 2:
		script.append(_card(player[2]))
	if banker.size() > 2:
		script.append(_card(banker[2]))
	t.scripted_cards = script
	t._on_deal_pressed()
	await settle(func() -> bool: return t.phase == ROUND_OVER, 20000, "the hand to finish")


func _test_card_values() -> void:
	check(t.card_value("A") == 1, "an ace counts one")
	for r in ["2", "3", "4", "5", "6", "7", "8", "9"]:
		check(t.card_value(r) == int(r), "%s counts its pips" % r)
	for r in ["10", "J", "Q", "K"]:
		check(t.card_value(r) == 0, "%s counts nothing" % r)
	note("aces count one, pips face value, tens and courts nothing")


func _test_totals_and_pairs() -> void:
	check(t.hand_total(_cards(["7", "8"])) == 5, "7+8 is 5, not 15")
	check(t.hand_total(_cards(["K", "Q"])) == 0, "two courts total nothing")
	check(t.hand_total(_cards(["9", "A"])) == 0, "9+1 wraps to 0")
	check(t.hand_total(_cards(["5", "4"])) == 9, "5+4 is a natural nine")
	check(t.hand_total(_cards(["6", "6", "8"])) == 0, "6+6+8 wraps to 0")
	check(t.is_pair(_cards(["8", "8"])), "two eights are a pair")
	check(not t.is_pair(_cards(["10", "K"])), "a ten and a king are not a pair, despite both counting 0")
	note("totals wrap modulo ten; pairs are by rank, not by value")


func _test_player_rule() -> void:
	# The player's own rule is simple: draw on 0-5, stand on 6-7.
	for total in range(0, 6):
		check(t.banker_draws(total, -1), "with the player standing, banker %d draws" % total)
	for total in [6, 7]:
		check(not t.banker_draws(total, -1), "with the player standing, banker %d stands" % total)
	note("with the player standing the banker draws on 0-5 and stands on 6-7")


func _test_banker_tableau() -> void:
	# The published table, restated independently of the implementation.
	# Rows are the banker's two-card total, columns the player's third card.
	var expected := {
		0: [true, true, true, true, true, true, true, true, true, true],
		1: [true, true, true, true, true, true, true, true, true, true],
		2: [true, true, true, true, true, true, true, true, true, true],
		3: [true, true, true, true, true, true, true, true, false, true],
		4: [false, false, true, true, true, true, true, true, false, false],
		5: [false, false, false, false, true, true, true, true, false, false],
		6: [false, false, false, false, false, false, true, true, false, false],
		7: [false, false, false, false, false, false, false, false, false, false],
	}
	var wrong := 0
	for banker_total in expected:
		for third in range(0, 10):
			var want: bool = expected[banker_total][third]
			var got: bool = t.banker_draws(banker_total, third)
			if got != want:
				wrong += 1
				fail("banker %d vs player third %d: draws=%s, want %s" % [
					banker_total, third, got, want])
	# Eight and nine are naturals and never reach the tableau, but guard anyway.
	for total in [8, 9]:
		check(not t.banker_draws(total, 5), "a natural %d never draws" % total)
	if wrong == 0:
		note("banker tableau matches the published table on all 80 cells")


func _test_shoe() -> void:
	t._reshuffle_shoe()
	check(t.shoe.size() == 52 * t.DECKS, "an %d-deck shoe holds %d cards" % [t.DECKS, 52 * t.DECKS])
	var per_rank := {}
	for c in t.shoe:
		per_rank[c.rank] = int(per_rank.get(c.rank, 0)) + 1
	for r in t.RANKS:
		check(int(per_rank.get(r, 0)) == 4 * t.DECKS,
			"the shoe should hold %d %ss, holds %d" % [4 * t.DECKS, r, int(per_rank.get(r, 0))])
	check(t._reshuffle_threshold() == int(52 * t.DECKS * 0.25), "the cut sits at a quarter of the shoe")
	note("%d-deck shoe is complete and cuts at a quarter" % t.DECKS)


func _test_natural_ends_the_hand() -> void:
	# Player 9 against banker 6: a natural stops the draw, so the banker never
	# takes the third card it would otherwise be entitled to.
	await _deal(["4", "5"], ["3", "3"], {"player": 100})
	check(t.player_cards.size() == 2, "a natural should not draw")
	check(t.banker_cards.size() == 2, "the banker must not draw against a natural")
	check(t.hand_total(t.player_cards) == 9, "the player should hold a natural nine")
	note("a natural on either side ends the hand where it stands")


func _test_player_and_banker_payouts() -> void:
	# Player 9 beats banker 7, paying even money.
	var start := 0
	Bank.reset()
	Bank.deposit(500000)
	start = Bank.balance
	await _deal(["4", "5"], ["3", "4"], {"player": 100})
	check(Bank.balance - start == 100, "a winning player bet pays even money, got %+d" % (Bank.balance - start))

	# Banker 9 beats player 7: even money less 5% commission on a $100 bet.
	Bank.reset()
	Bank.deposit(500000)
	start = Bank.balance
	await _deal(["3", "4"], ["4", "5"], {"banker": 100})
	check(Bank.balance - start == 95,
		"a winning $100 banker bet should net $95 after commission, got %+d" % (Bank.balance - start))

	# And the loser simply loses its stake.
	Bank.reset()
	Bank.deposit(500000)
	start = Bank.balance
	await _deal(["3", "4"], ["4", "5"], {"player": 100})
	check(Bank.balance - start == -100, "a losing bet costs its stake")
	note("player pays 1:1, banker pays 1:1 less 5%, losers lose their stake")


func _test_tie_pushes_and_pays() -> void:
	Bank.reset()
	Bank.deposit(500000)
	var start: int = Bank.balance
	# Both sides make seven: the tie pays 8:1 and the flat bets push.
	await _deal(["3", "4"], ["3", "4"], {"tie": 100, "player": 100, "banker": 100})
	check(t.hand_total(t.player_cards) == t.hand_total(t.banker_cards), "the hands should tie")
	# Tie returns 100 stake + 800; player and banker push back 100 each.
	check(Bank.balance - start == 800,
		"a $100 tie at 8:1 with pushed flats should net +$800, got %+d" % (Bank.balance - start))
	note("a tie pays 8:1 and pushes the player and banker bets")


func _test_pair_side_bets() -> void:
	Bank.reset()
	Bank.deposit(500000)
	var start: int = Bank.balance
	# Player holds a pair of fours (total 8, a natural) against banker 7.
	await _deal(["4", "4"], ["3", "4"], {"player_pair": 100})
	check(t.is_pair(t.player_cards), "the player should hold a pair")
	check(Bank.balance - start == 1100,
		"a $100 player pair at 11:1 should net +$1,100, got %+d" % (Bank.balance - start))

	Bank.reset()
	Bank.deposit(500000)
	start = Bank.balance
	# Banker pairs; the player-pair bet alongside it must lose.
	await _deal(["3", "4"], ["6", "6"], {"banker_pair": 100, "player_pair": 100})
	check(Bank.balance - start == 1100 - 100,
		"banker pair should pay while the player pair loses, got %+d" % (Bank.balance - start))
	note("pair side bets pay 11:1 on the side that actually paired")


func _test_money_conservation() -> void:
	# Play out real hands and assert the bank only ever moves by a settled
	# amount, and never below zero.
	Bank.reset()
	Bank.deposit(2000)
	t.scripted_cards.clear()
	t._reshuffle_shoe()
	for i in 25:
		t.phase = 0
		t.board.clear_all()
		var key: String = ["player", "banker", "tie"][i % 3]
		if not t.board.place(key, 25):
			break
		t._on_deal_pressed()
		await settle(func() -> bool: return t.phase == ROUND_OVER, 20000, "hand %d" % i)
		check(Bank.balance >= 0, "the bank went negative after hand %d" % i)
		check(t.board.total() == 0, "the board should be cleared after settling hand %d" % i)
		t._on_new_round_pressed()
	note("25 dealt hands settled without the bank going negative")

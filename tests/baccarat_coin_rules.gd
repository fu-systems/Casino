extends CasinoTest
## Coin Flip mode: the same baccarat, shown as a coin. The cards are still
## dealt and settled by the tableau, so the outcome and the money must match
## card mode exactly.

const ROUND_OVER := 2

var t: Control


func run() -> void:
	Store.use_test_backend()
	t = load("res://scenes/baccarat.tscn").instantiate()
	add_child(t)
	await frames()
	check(not t.coin_button.visible, "Coin Flip should be hidden until it's unlocked")
	t.queue_free()
	await frames()

	Store.unlock_free("baccarat_coin_flip")
	t = load("res://scenes/baccarat.tscn").instantiate()
	add_child(t)
	await frames()
	check(t.coin_button.visible, "Coin Flip should appear once unlocked")
	check(not t.coin_mode, "the table still starts in card mode")

	await _test_toggle_refunds_pairs()
	await _test_faces_and_payouts()
	await _test_matches_card_mode()
	await _test_remembered()

	t.queue_free()
	Store.use_test_backend()


func _card(rank: String) -> Dictionary:
	return {"rank": rank, "suit": "♠"}


func _deal(player: Array, banker: Array, bets: Dictionary) -> int:
	Bank.reset()
	Bank.deposit(500000)
	var before := Bank.balance
	t.phase = 0
	t.board.clear_all()
	for key in bets:
		t.board.place(key, bets[key])
	before = Bank.balance + t.board.total()
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
	check(t.scripted_cards.is_empty(), "the deal should use exactly the scripted cards")
	return Bank.balance - before


func _test_toggle_refunds_pairs() -> void:
	Bank.reset()
	t.phase = 0
	t.board.clear_all()
	t.board.place("player_pair", 25)
	t.board.place("banker", 25)
	t._on_coin_pressed()
	check(t.coin_mode, "the button should switch Coin Flip on")
	check(t.board.amount("player_pair") == 0, "pair bets need cards, so they come off the table")
	check(Bank.balance == Bank.START_BALANCE - 25, "the pair stake should be refunded, only the banker bet stays")
	check(not t.pair_row.visible and not t.hands_row.visible and t.coin_panel.visible,
		"the coin should replace the hands and the pair bets")
	t.board.refund_all()
	note("switching on swaps cards for the coin and refunds the pair bets")


func _test_faces_and_payouts() -> void:
	var net := await _deal(["10", "K"], ["9", "K"], {"banker": 100})
	check(t.coin.face == "heads", "a banker win lands heads, got '%s'" % t.coin.face)
	check(net == 95, "the banker still pays 1:1 less 5%%, got %d" % net)
	check("Heads" in t.message_label.text, "the result should read as a coin")

	net = await _deal(["9", "K"], ["10", "K"], {"player": 100})
	check(t.coin.face == "tails", "a player win lands tails, got '%s'" % t.coin.face)
	check(net == 100, "the player still pays 1:1, got %d" % net)

	net = await _deal(["8", "K"], ["8", "K"], {"tie": 100, "banker": 50})
	check(t.coin.face == "edge", "a tie lands on its edge, got '%s'" % t.coin.face)
	check(net == 800, "a tie still pays 8:1 and pushes the banker bet, got %d" % net)
	note("heads is banker, tails is player, the edge is a tie, and payouts are unchanged")


func _test_matches_card_mode() -> void:
	# The same hands, every drawn card scripted, in both modes: the player
	# draws to 9 and the banker draws to 0; the player draws and the banker's
	# 5 stands against a third-card 9; and the banker's 7 stands.
	var hands := [
		[["2", "3", "4"], ["4", "K", "6"], {"banker": 100}],
		[["A", "2", "9"], ["5", "K"], {"player": 100, "tie": 25}],
		[["K", "Q", "5"], ["3", "4"], {"banker": 200}],
	]
	for hand in hands:
		var coin_net := await _deal(hand[0], hand[1], hand[2])
		t._set_coin_mode(false)
		var card_net := await _deal(hand[0], hand[1], hand[2])
		t._set_coin_mode(true)
		check(coin_net == card_net, "coin and card mode should settle %s vs %s the same: %d vs %d" % [
			hand[0], hand[1], coin_net, card_net])
	note("coin mode settles every hand exactly as card mode does")


func _test_remembered() -> void:
	t._on_new_round_pressed()
	check(bool(SaveData.get_value("baccarat", "coin_flip", false)), "the mode should be remembered")
	var again: Control = load("res://scenes/baccarat.tscn").instantiate()
	add_child(again)
	await frames()
	check(again.coin_mode, "the table should reopen in Coin Flip mode")
	again._set_coin_mode(false)
	again.queue_free()
	await frames()
	note("the table remembers Coin Flip mode")

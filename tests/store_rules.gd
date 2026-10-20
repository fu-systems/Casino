extends CasinoTest
## The store: what's owned, what a purchase grants, what restore and a refund
## do, and that tips and free unlocks behave. Google Play itself is replaced
## by a fake billing client that records what the store asks of it.

## A pack id for the Google Play checks; they work on any id, listed or not.
const PACK := "strategy_trainer"


## Stands in for the plugin's BillingClient, recording calls.
class FakeBilling:
	extends Node
	signal connected
	signal disconnected
	signal connect_error(code: int, message: String)
	signal query_product_details_response(response: Dictionary)
	signal query_purchases_response(response: Dictionary)
	signal on_purchase_updated(response: Dictionary)
	signal consume_purchase_response(response: Dictionary)
	signal acknowledge_purchase_response(response: Dictionary)
	var acknowledged: Array = []
	var consumed: Array = []
	var launched: Array = []
	var queries := 0

	func start_connection() -> void:
		pass

	func query_product_details(_ids: PackedStringArray, _type: int) -> void:
		pass

	func query_purchases(_type: int) -> void:
		queries += 1

	func purchase(id: String) -> Dictionary:
		launched.append(id)
		return {"response_code": 0}

	func acknowledge_purchase(token: String) -> void:
		acknowledged.append(token)

	func consume_purchase(token: String) -> void:
		consumed.append(token)


func run() -> void:
	_test_test_backend()
	_test_tips_and_free_unlocks()
	_test_restore_and_refund()
	_test_unlocked_builds()
	_test_steam_edition()
	_test_play_purchases()
	await _test_extras_screen()
	await _test_steam_extras()
	Store.use_test_backend()


func _test_test_backend() -> void:
	Store.use_test_backend()
	for entry in Store.PACKS:
		check(not Store.owns(entry.id), "%s should start locked" % entry.id)
		check(Store.can_buy(entry.id), "%s should be buyable" % entry.id)
		check(Store.price(entry.id) == entry.price, "%s should show its price" % entry.id)
		Store.buy(entry.id)
		check(Store.owns(entry.id), "buying %s should unlock it" % entry.id)
		check(entry.id in SaveData.get_value("store", "owned", []),
			"%s should be cached for offline play" % entry.id)
		check(entry.has("lines") and not entry.lines.is_empty(),
			"%s should say plainly what it contains" % entry.id)
	note("packs start locked, show their price, and unlock and cache when bought")


func _test_tips_and_free_unlocks() -> void:
	Store.use_test_backend()
	var thanked: Array = []
	var on_thanks := func(id: String) -> void: thanked.append(id)
	Store.tip_thanked.connect(on_thanks)
	for entry in Store.TIPS:
		Store.buy(entry.id)
		check(not Store.owns(entry.id), "a tip should never become something you own")
	Store.tip_thanked.disconnect(on_thanks)
	check(thanked.size() == Store.TIPS.size(), "every tip should be thanked, got %d" % thanked.size())

	for entry in Store.FREE_UNLOCKS:
		check(not Store.owns(entry.id), "%s should start locked" % entry.id)
		Store.unlock_free(entry.id)
		check(Store.owns(entry.id), "%s should unlock with a tap" % entry.id)
		check(entry.id in SaveData.get_value("store", "free", []), "%s should be remembered" % entry.id)
	note("tips are thanked and never owned; free unlocks unlock and persist")


func _test_restore_and_refund() -> void:
	Store.use_test_backend()
	Store.buy(PACK)
	# A reinstall: nothing cached, but the account still owns it.
	Store._owned.clear()
	check(not Store.owns(PACK), "a fresh install starts with nothing cached")
	Store.restore()
	check(Store.owns(PACK), "restore should bring back what the account owns")
	Store.test_refund(PACK)
	Store.restore()
	check(not Store.owns(PACK), "a refunded pack should go away on the next restore")
	note("restore brings purchases back, and a refund takes them away")


func _test_unlocked_builds() -> void:
	Store.use_test_backend()
	Store.backend = Store.Backend.UNLOCKED
	check(Store.owns(PACK), "a build with nowhere to buy should unlock every pack")
	for entry in Store.FREE_UNLOCKS:
		check(not Store.owns(entry.id), "free unlocks stay a deliberate tap even then")
	for entry in Store.TIPS:
		check(not Store.can_buy(entry.id), "there's nowhere to tip in a build without a store")
	Store.use_test_backend()
	note("desktop and debug builds unlock every pack but still ask for free unlocks")


func _test_steam_edition() -> void:
	Store.use_test_backend()
	Store.backend = Store.Backend.STEAM
	check(Store.all_included(), "the Steam edition should include everything")
	for entry in Store.PACKS:
		check(Store.owns(entry.id), "the Steam edition should own %s" % entry.id)
		check(not Store.can_buy(entry.id), "nothing should be for sale in the Steam edition")
	for entry in Store.FREE_UNLOCKS:
		check(not Store.owns(entry.id), "free unlocks stay a deliberate tap on Steam too")
	check(not Store.sells_tips(), "a game someone paid for shouldn't ask for tips")
	check("Steam" in Store.status_text(), "the status line should name the Steam edition")
	check("Steam" in Store.privacy_note() and "Google" not in Store.privacy_note(),
		"the privacy line should name Steam, not Google Play")

	var said: Array = []
	var listen := func(text: String) -> void: said.append(text)
	Store.store_message.connect(listen)
	Store.buy("tip_small")
	Store.store_message.disconnect(listen)
	check(said.size() == 1 and "includes everything" in str(said[0]),
		"buying on Steam should explain there's nothing to buy")
	Store.use_test_backend()
	note("the Steam edition includes every pack, sells nothing and has no tip jar")


func _test_play_purchases() -> void:
	Store.use_test_backend()
	var fake := FakeBilling.new()
	add_child(fake)
	Store._billing = fake
	Store.backend = Store.Backend.PLAY
	Store._connected = true
	Store._prices.clear()

	check(not Store.can_buy(PACK), "nothing is buyable until Google Play has priced it")
	Store._on_play_product_details({"response_code": 0, "product_details": [
		{"product_id": PACK, "one_time_purchase_offer_details_list": [{"formatted_price": "£2.49"}]}]})
	check(Store.price(PACK) == "£2.49", "prices should be the store's localized ones")
	check(Store.can_buy(PACK), "a priced pack should be buyable")
	Store.buy(PACK)
	check(fake.launched == [PACK], "buying should launch Google Play's purchase flow")

	var messages: Array = []
	var on_message := func(text: String) -> void: messages.append(text)
	Store.store_message.connect(on_message)
	Store._on_play_purchases({"response_code": 0, "purchases": [
		{"product_ids": [PACK], "purchase_state": 2, "purchase_token": "pending", "is_acknowledged": false}]}, false)
	check(not Store.owns(PACK), "a pending payment must not unlock anything")
	check(messages.size() == 1 and "pending" in messages[0], "a pending payment should be explained")
	Store.store_message.disconnect(on_message)

	Store._on_play_purchases({"response_code": 0, "purchases": [
		{"product_ids": [PACK], "purchase_state": 1, "purchase_token": "paid", "is_acknowledged": false}]}, false)
	check(Store.owns(PACK), "a completed purchase should unlock the pack")
	check(fake.acknowledged == ["paid"], "a new purchase must be acknowledged or Google refunds it")

	Store._on_play_purchases({"response_code": 0, "purchases": [
		{"product_ids": [PACK], "purchase_state": 1, "purchase_token": "paid", "is_acknowledged": true}]}, true)
	check(fake.acknowledged == ["paid"], "an acknowledged purchase isn't acknowledged twice")

	var thanked: Array = []
	var on_thanks := func(id: String) -> void: thanked.append(id)
	Store.tip_thanked.connect(on_thanks)
	Store._on_play_purchases({"response_code": 0, "purchases": [
		{"product_ids": ["tip_small"], "purchase_state": 1, "purchase_token": "tip", "is_acknowledged": false}]}, false)
	check(fake.consumed == ["tip"], "a tip should be consumed so it can be given again")
	check(thanked.is_empty(), "the thanks waits for the consume to succeed")
	Store._on_play_consumed({"response_code": 0, "token": "tip"})
	check(thanked == ["tip_small"], "a consumed tip should be thanked")
	Store.tip_thanked.disconnect(on_thanks)

	# A full purchase query that no longer lists the pack: it was refunded.
	Store._on_play_purchases({"response_code": 0, "purchases": []}, true)
	check(not Store.owns(PACK), "a pack missing from a full query has been refunded")

	Store._billing = null
	fake.queue_free()
	note("Google Play: localized prices, pending stays locked, acknowledge, consume tips, refunds")


func _test_extras_screen() -> void:
	Store.use_test_backend()
	var extras: Control = load("res://scenes/extras.tscn").instantiate()
	add_child(extras)
	await frames(2)
	for entry in Store.PACKS + Store.FREE_UNLOCKS:
		check(extras.cards.has(entry.id), "Extras should list %s" % entry.id)
	var coin_card: Control = extras.cards.get("baccarat_coin_flip")
	var action: Button = coin_card.find_child("Action", true, false)
	check(action.text == "Unlock — Free", "a free unlock should say it's free, got '%s'" % action.text)
	action.emit_signal("pressed")
	await frames(2)
	check(Store.owns("baccarat_coin_flip"), "tapping a free unlock should unlock it")
	coin_card = extras.cards.get("baccarat_coin_flip")
	action = coin_card.find_child("Action", true, false)
	check(action.text == "Open", "an unlocked extra should offer to open, got '%s'" % action.text)

	var tips: Control = extras.cards.get("tips")
	var tip: Button = tips.get_child(0)
	check(not tip.disabled, "tips should be offered when there's a store")
	tip.emit_signal("pressed")
	await frames()
	check("Thank you" in extras.message_label.text, "a tip should be thanked on screen")
	extras.queue_free()
	await frames()
	Store.use_test_backend()
	note("Extras lists every pack and free unlock, unlocks for free, and thanks tips")


func _test_steam_extras() -> void:
	Store.use_test_backend()
	Store.backend = Store.Backend.STEAM
	var extras: Control = load("res://scenes/extras.tscn").instantiate()
	add_child(extras)
	await frames(2)
	check(not extras.cards.has("tips"), "the Steam edition's Extras should have no tip jar")
	check(not extras.restore_button.visible, "there's nothing to restore in the Steam edition")
	var headers: Array = []
	for child in extras.list.get_children():
		if child is Label:
			headers.append(child.text)
	check("INCLUDED" in headers and "PACKS" not in headers,
		"packs should be listed as included, not for sale")
	for entry in Store.PACKS:
		var action: Button = extras.cards[entry.id].find_child("Action", true, false)
		check(action.text == "Open" and not action.disabled,
			"%s should open straight away, got '%s'" % [entry.id, action.text])
	check("Steam" in extras.status_label.text, "the status line should name the Steam edition")
	extras.queue_free()
	await frames()
	Store.use_test_backend()
	note("the Steam edition's Extras opens every pack and shows no tip jar or restore")

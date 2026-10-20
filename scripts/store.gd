extends Node
## What the player owns, registered as the "Store" autoload.
##
## Four ways to run, picked once at startup:
##
## - PLAY: builds exported with the `play_store` feature (the "Android Play"
##   preset) sell through Google Play Billing. Ownership is cached in
##   `SaveData` so packs keep working offline, but Google Play stays the source
##   of truth: every connect re-queries purchases, which is what makes Restore
##   work and what takes a refunded pack away again.
## - STEAM: builds exported with the `steam` feature (the "Steam" presets) are
##   bought whole, so every pack comes included and there's no tip jar.
## - UNLOCKED: every other build (desktop, the debug APK) has nowhere to buy
##   from, and the code is public anyway, so every pack is simply unlocked.
## - TEST: the rule suites drive a fake account with `use_test_backend()`.
##
## Free unlocks are local-only and never touch the store.
##
## The house rules for selling live here as much as anywhere: only one-time
## packs and tips are sold, never chips; a pack is acknowledged as soon as
## Google says it's paid; and a pending payment unlocks nothing until it
## clears.

signal purchases_changed
signal prices_changed
## A line worth showing the player: pending payments, errors, thanks.
signal store_message(text: String)
signal tip_thanked(id: String)

enum Backend { UNLOCKED, PLAY, TEST, STEAM }

## Paid packs, in the order the Extras screen lists them. `scene` is where
## the pack's Open button goes once it's owned; `price` is only the fallback
## shown by the test store, as Google Play supplies the real, local one.
const PACKS := [
	{
		"id": "strategy_trainer",
		"title": "Strategy Trainer",
		"game": "Blackjack",
		"price": "$2.99",
		"lines": [
			"Drills every basic-strategy decision: hard totals, soft totals and pairs against every upcard.",
			"Count mode drills the Illustrious 18 and insurance at counts either side of where they flip.",
			"Weak Spots replays the hands you miss most; Blitz gives you 60 seconds against the clock.",
			"Every wrong answer explains the right play and shows it on the chart.",
		],
		"scene": "res://scenes/strategy_drill.tscn",
	},
	{
		"id": "count_trainer",
		"title": "Card Counting Trainer",
		"game": "Blackjack",
		"price": "$2.99",
		"lines": [
			"A dealer and up to seven players, all playing basic strategy — you tap to lay every card.",
			"Keep the Hi-Lo count and enter it when each round ends; add the true count for a harder test.",
			"Four time limits, from Relaxed to 6 seconds a round, with best scores for cards counted and pace.",
			"When you miss, it shows the round card by card with each card's +1, 0 or -1.",
		],
		"scene": "res://scenes/count_drill.tscn",
	},
	{
		"id": "roulette_lab",
		"title": "Roulette Systems Lab",
		"game": "Roulette",
		"price": "$3.99",
		"lines": [
			"Build any betting system as a flowchart of steps and IF / THEN rules — or open a famous one and change it.",
			"Rules can watch single bets, several bets landing together, streaks, runs of results, the bankroll and two counters.",
			"Run one session spin by spin, or thousands at once: how often it ends ahead, how often it goes broke, the worst it gets.",
			"Every result sits next to what the 2.7% house edge predicts, so luck can't pass for a working system.",
		],
		"scene": "res://scenes/system_lab.tscn",
		"lab_game": "roulette",
	},
	{
		"id": "craps_lab",
		"title": "Craps Systems Lab",
		"game": "Craps",
		"price": "$3.99",
		"lines": [
			"The Systems Lab for the dice: line bets with odds, come bets, place bets, the field, hardways and props.",
			"Rules can react to seven-outs, points made, naturals, hard ways and any total — plus press, regress and take odds.",
			"Famous systems to start from: Iron Cross, 3-Point Molly, place-and-press, and Martingale on the pass line.",
			"Plays exactly the table's rules, and sets every result against each bet's own house edge.",
		],
		"scene": "res://scenes/system_lab.tscn",
		"lab_game": "craps",
	},
]

const TIPS := [
	{"id": "tip_small", "title": "Small tip", "price": "$1.99"},
	{"id": "tip_medium", "title": "Medium tip", "price": "$4.99"},
	{"id": "tip_large", "title": "Large tip", "price": "$9.99"},
]

## Unlocked with a tap on the Extras screen; no store involved.
const FREE_UNLOCKS := [
	{
		"id": "baccarat_coin_flip",
		"title": "Coin Flip",
		"game": "Baccarat",
		"lines": [
			"Turns baccarat into what it really is: a weighted coin flip.",
			"Heads is Banker, tails is Player, and on its edge is a Tie.",
			"Same shoe, same tableau, same payouts — just none of the theatre.",
		],
		"scene": "res://scenes/baccarat.tscn",
	},
]

const BILLING_SCRIPT := "res://addons/GodotGooglePlayBilling/BillingClient.gd"
const PLAY_OK := 0
const PLAY_USER_CANCELED := 1
const PLAY_ITEM_ALREADY_OWNED := 7
const PLAY_PURCHASED := 1
const PLAY_PENDING := 2
const PLAY_INAPP := 0

var backend: int = Backend.UNLOCKED

## Where Extras' Back button returns to, and which card it should open on.
var return_scene := "res://scenes/main_menu.tscn"
var focus_id := ""

var _owned := {}
var _free := {}
var _prices := {}
var _billing: Node
var _connected := false
var _status := ""
## Purchase token -> tip id, for tips waiting to be consumed.
var _tip_tokens := {}
## The fake Google account behind the TEST backend: what has been paid for.
var _test_account := {}


func _ready() -> void:
	for id in SaveData.get_value("store", "free", []):
		_free[str(id)] = true
	if OS.has_feature("play_store"):
		_start_play()
	elif OS.has_feature("steam"):
		backend = Backend.STEAM
	else:
		backend = Backend.UNLOCKED


# --- Queries -------------------------------------------------------------------

func owns(id: String) -> bool:
	# Free unlocks are a deliberate tap in every build, even one where the
	# paid packs come unlocked.
	if _is_free(id):
		return _free.has(id)
	if _is_tip(id):
		return false
	if all_included():
		return true
	return _owned.has(id)


## Whether this build comes with every pack, so there's nothing to buy.
func all_included() -> bool:
	return backend == Backend.UNLOCKED or backend == Backend.STEAM


## Whether the tip jar belongs here. A game someone has already paid for
## doesn't ask for tips on top.
func sells_tips() -> bool:
	return backend != Backend.STEAM


## The store's localized price, or "" until Google Play has said.
func price(id: String) -> String:
	return str(_prices.get(id, ""))


## Whether a Buy button should be live right now.
func can_buy(id: String) -> bool:
	match backend:
		Backend.TEST:
			return true
		Backend.PLAY:
			return _connected and _prices.has(id)
	return false


## One line on where purchases stand, for the bottom of the Extras screen.
func status_text() -> String:
	match backend:
		Backend.UNLOCKED:
			return "Every pack is unlocked in this build. Packs and tips are sold through Google Play."
		Backend.STEAM:
			return "Everything is included in the Steam edition. Thanks for buying Casino."
		Backend.TEST:
			return "Test store."
	return _status


## The About box's line on who handles the money.
func privacy_note() -> String:
	match backend:
		Backend.STEAM:
			return "Steam handles the purchase; the game itself never connects to the internet."
		Backend.UNLOCKED:
			return "Nothing is sold in this build."
	return "Purchases are handled entirely by Google Play."


func pack(id: String) -> Dictionary:
	for entry in PACKS + FREE_UNLOCKS:
		if entry.id == id:
			return entry
	return {}


# --- Actions -------------------------------------------------------------------

func buy(id: String) -> void:
	match backend:
		Backend.UNLOCKED:
			store_message.emit("There's nothing to buy in this build — every pack is already unlocked.")
		Backend.STEAM:
			store_message.emit("There's nothing to buy — the Steam edition already includes everything.")
		Backend.TEST:
			if _is_tip(id):
				tip_thanked.emit(id)
			else:
				_test_account[id] = true
				_grant([id], false)
		Backend.PLAY:
			if not can_buy(id):
				store_message.emit("Google Play isn't ready yet. Try again in a moment.")
				_reconnect()
				return
			var result: Dictionary = _billing.purchase(id)
			var code := int(result.get("response_code", -1))
			if code == PLAY_ITEM_ALREADY_OWNED:
				restore()
			elif code != PLAY_OK:
				store_message.emit("Google Play couldn't start the purchase (%s)." % result.get("debug_message", code))


func restore() -> void:
	match backend:
		Backend.TEST:
			_owned = _test_account.duplicate()
			_save_owned()
			purchases_changed.emit()
		Backend.PLAY:
			if _connected:
				_billing.query_purchases(PLAY_INAPP)
				store_message.emit("Checking Google Play for your purchases…")
			else:
				_reconnect()


func unlock_free(id: String) -> void:
	_free[id] = true
	SaveData.set_value("store", "free", _free.keys())
	purchases_changed.emit()


## Opens the Extras screen on one card, coming back to `from` afterwards.
func show_extras(tree: SceneTree, id: String = "", from: String = "") -> void:
	focus_id = id
	if from != "":
		return_scene = from
	tree.change_scene_to_file("res://scenes/extras.tscn")


# --- Test backend --------------------------------------------------------------

## A fresh fake account with nothing bought and nothing unlocked.
func use_test_backend() -> void:
	backend = Backend.TEST
	_owned.clear()
	_free.clear()
	_test_account.clear()
	_prices.clear()
	for entry in PACKS:
		_prices[entry.id] = entry.price
	for entry in TIPS:
		_prices[entry.id] = entry.price
	purchases_changed.emit()


## Has the fake account refund a pack, as Google would; the next restore
## takes it away.
func test_refund(id: String) -> void:
	_test_account.erase(id)


# --- Google Play ---------------------------------------------------------------

func _start_play() -> void:
	backend = Backend.PLAY
	for id in SaveData.get_value("store", "owned", []):
		_owned[str(id)] = true
	if not ResourceLoader.exists(BILLING_SCRIPT):
		_status = "Google Play Billing isn't included in this build."
		return
	_billing = load(BILLING_SCRIPT).new()
	add_child(_billing)
	_billing.connected.connect(_on_play_connected)
	_billing.disconnected.connect(_on_play_disconnected)
	_billing.connect_error.connect(_on_play_connect_error)
	_billing.query_product_details_response.connect(_on_play_product_details)
	_billing.query_purchases_response.connect(_on_play_purchases.bind(true))
	_billing.on_purchase_updated.connect(_on_play_purchases.bind(false))
	_billing.consume_purchase_response.connect(_on_play_consumed)
	_billing.acknowledge_purchase_response.connect(_on_play_acknowledged)
	_reconnect()


func _reconnect() -> void:
	if _billing == null or _connected:
		return
	_status = "Connecting to Google Play…"
	_billing.start_connection()


func _on_play_connected() -> void:
	_connected = true
	_status = "Prices from Google Play."
	var ids := PackedStringArray()
	for entry in PACKS + TIPS:
		ids.append(entry.id)
	_billing.query_product_details(ids, PLAY_INAPP)
	_billing.query_purchases(PLAY_INAPP)
	prices_changed.emit()


func _on_play_disconnected() -> void:
	_connected = false
	_status = "Disconnected from Google Play."
	prices_changed.emit()


func _on_play_connect_error(code: int, message: String) -> void:
	_connected = false
	_status = "Couldn't reach Google Play (%d): %s" % [code, message]
	prices_changed.emit()


func _on_play_product_details(response: Dictionary) -> void:
	if int(response.get("response_code", -1)) != PLAY_OK:
		_status = "Google Play didn't return prices: %s" % response.get("debug_message", "")
		prices_changed.emit()
		return
	for details in response.get("product_details", []):
		var offers: Variant = details.get("one_time_purchase_offer_details_list")
		if offers is Array and not offers.is_empty():
			_prices[str(details.product_id)] = str(offers[0].get("formatted_price", ""))
	prices_changed.emit()


## `complete` is true for a full query of what the account owns, which may
## take things away (a refund); a purchase update only ever adds.
func _on_play_purchases(response: Dictionary, complete: bool) -> void:
	var code := int(response.get("response_code", -1))
	if code == PLAY_USER_CANCELED:
		return
	if code != PLAY_OK:
		store_message.emit("Google Play: %s" % response.get("debug_message", code))
		return

	var granted: Array = []
	for purchase in response.get("purchases", []):
		var state := int(purchase.get("purchase_state", 0))
		var token := str(purchase.get("purchase_token", ""))
		for raw_id in purchase.get("product_ids", []):
			var id := str(raw_id)
			if state == PLAY_PENDING:
				store_message.emit("Payment pending — it unlocks as soon as Google Play confirms it.")
				continue
			if state != PLAY_PURCHASED:
				continue
			if _is_tip(id):
				# Consumed so it can be given again; the thanks waits for the
				# consume to succeed.
				_tip_tokens[token] = id
				_billing.consume_purchase(token)
				continue
			granted.append(id)
			if not bool(purchase.get("is_acknowledged", false)):
				_billing.acknowledge_purchase(token)
	_grant(granted, complete)


func _on_play_consumed(response: Dictionary) -> void:
	var token := str(response.get("token", ""))
	var id: String = _tip_tokens.get(token, "")
	_tip_tokens.erase(token)
	if int(response.get("response_code", -1)) == PLAY_OK and id != "":
		tip_thanked.emit(id)


func _on_play_acknowledged(response: Dictionary) -> void:
	# Nothing to do on success. A failure is retried by the next purchase
	# query, which reports the pack as still unacknowledged.
	if int(response.get("response_code", -1)) != PLAY_OK:
		push_warning("Acknowledge failed: %s" % response.get("debug_message", ""))


# --- Shared ----------------------------------------------------------------------

func _grant(ids: Array, replace: bool) -> void:
	if replace:
		_owned.clear()
	for id in ids:
		_owned[str(id)] = true
	_save_owned()
	purchases_changed.emit()


func _save_owned() -> void:
	if backend == Backend.PLAY or backend == Backend.TEST:
		SaveData.set_value("store", "owned", _owned.keys())


func _is_tip(id: String) -> bool:
	for entry in TIPS:
		if entry.id == id:
			return true
	return false


func _is_free(id: String) -> bool:
	for entry in FREE_UNLOCKS:
		if entry.id == id:
			return true
	return false

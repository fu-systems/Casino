class_name BetBoard
extends RefCounted
## A board of chip-takeable bet areas, shared by roulette, craps and baccarat.
##
## Tracks how much is staked on each area, keeps a gold chip badge on every
## button carrying a bet, and moves money through `Bank`. Stakes are
## paid up front the moment a chip is placed, exactly as on a real table, so
## clearing a bet refunds it.
##
## Resolution is deliberately not here: what beats what is different in every
## game and belongs with that game.

const COLOR_BADGE := Color(0.94, 0.78, 0.29)
const COLOR_BADGE_TEXT := Color(0.15, 0.1, 0.0)

## Where the chip badge sits on its button. CENTRE suits bare cells like
## roulette's numbers, where the badge standing in for the label is exactly
## right; CORNER suits boards whose areas carry their name and price, where
## a centred badge would sit on top of the words.
enum Badge { CENTRE, CORNER }

## key -> {"button": Button, "amount": int, "meta": Dictionary}
var bets := {}
var badge_position: int = Badge.CENTRE


## Registers a bet area. `meta` carries whatever the game needs at resolution
## time (winning numbers, payout ratio, and so on).
func add(key: String, button: Button, meta: Dictionary = {}) -> void:
	bets[key] = {"button": button, "amount": 0, "meta": meta}


func has(key: String) -> bool:
	return bets.has(key)


func amount(key: String) -> int:
	return int(bets[key].amount) if bets.has(key) else 0


func meta(key: String) -> Dictionary:
	return bets[key].meta if bets.has(key) else {}


func total() -> int:
	var sum := 0
	for key in bets:
		sum += int(bets[key].amount)
	return sum


## Any area currently carrying chips.
func staked_keys() -> Array:
	var keys := []
	for key in bets:
		if int(bets[key].amount) > 0:
			keys.append(key)
	return keys


## Takes `chips` from the bank and adds them to a bet area. False (and no
## change) when the bank can't cover it.
func place(key: String, chips: int) -> bool:
	if not bets.has(key) or chips <= 0:
		return false
	if not Bank.withdraw(chips):
		return false
	bets[key].amount = int(bets[key].amount) + chips
	refresh_badge(key)
	return true


## Puts chips on an area without charging for them — for moving a stake
## already paid for, such as a come bet travelling to its number.
func move_in(key: String, chips: int) -> void:
	if not bets.has(key) or chips <= 0:
		return
	bets[key].amount = int(bets[key].amount) + chips
	refresh_badge(key)


## Takes an area's chips off the board and returns them to the caller to
## settle. Does not touch the bank.
func take(key: String) -> int:
	if not bets.has(key):
		return 0
	var staked := int(bets[key].amount)
	bets[key].amount = 0
	refresh_badge(key)
	return staked


## Clears one area and refunds it.
func refund(key: String) -> int:
	var staked := take(key)
	if staked > 0:
		Bank.deposit(staked)
	return staked


## Clears the whole board, refunding every stake. Returns the total returned.
func refund_all() -> int:
	var returned := 0
	for key in bets:
		returned += int(bets[key].amount)
		bets[key].amount = 0
		refresh_badge(key)
	if returned > 0:
		Bank.deposit(returned)
	return returned


## Clears the board without refunding, for stakes already settled.
func clear_all() -> void:
	for key in bets:
		bets[key].amount = 0
		refresh_badge(key)


func refresh_all_badges() -> void:
	for key in bets:
		refresh_badge(key)


## Puts a gold chip badge on the button, or removes it when the area is
## empty.
func refresh_badge(key: String) -> void:
	var entry: Dictionary = bets[key]
	var button: Button = entry.button
	if not is_instance_valid(button):
		return
	var badge: Label = button.get_node_or_null("ChipBadge")

	if int(entry.amount) <= 0:
		if badge != null:
			# Renamed first so a badge added again this frame doesn't collide
			# with the one still queued for deletion.
			badge.name = "DeadBadge"
			badge.hide()
			badge.queue_free()
		return

	if badge == null:
		badge = Label.new()
		badge.name = "ChipBadge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = COLOR_BADGE
		sb.set_corner_radius_all(11)
		sb.content_margin_left = 7
		sb.content_margin_right = 7
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		badge.add_theme_stylebox_override("normal", sb)
		badge.add_theme_color_override("font_color", COLOR_BADGE_TEXT)
		badge.add_theme_font_size_override("font_size", 12)
		button.add_child(badge)

	badge.text = str(int(entry.amount))
	badge.reset_size()
	if badge_position == Badge.CORNER:
		badge.position = Vector2(button.size.x - badge.size.x - 3,
			button.size.y - badge.size.y - 2)
	else:
		badge.position = (button.size - badge.size) / 2.0

class_name RouletteSim
extends RefCounted
## Roulette for the Systems Lab: the same bets and payouts as the table (both
## read RouletteBets), but no wheel to watch, so a system can play thousands
## of spins in a moment.
##
## The runner drives every game through the same few calls: `reset` with a
## wallet, `place` the round's stakes, `play` a round, then ask `hit`, `lost`
## and `has_event` about the outcome.

var wallet: SystemRunner.Wallet
## Set by tests to force known numbers; consumed before the generator.
var scripted: Array = []
var _stakes := {}

## position -> PackedByteArray of 37, 1 where the number wins it. Built once;
## looking a win up is then a single index.
static var _covers := {}


static func positions() -> Array:
	var out: Array = []
	var bets := RouletteBets.all()
	for key in bets:
		out.append({"key": key, "label": bets[key].label, "group": bets[key].group})
	return out


static func events() -> Array:
	return [["zero", "the zero"]]


func reset(new_wallet: SystemRunner.Wallet) -> void:
	wallet = new_wallet
	_stakes = {}


## Roulette bets all settle every spin, so nothing stays on the table.
func on_table() -> int:
	return 0


## Takes the round's stakes ({position: dollars}) from the wallet, all or
## nothing. False if the wallet can't cover them. Roulette has no odds bets.
func place(stakes: Dictionary, _odds: Dictionary = {}) -> bool:
	var total := 0
	for key in stakes:
		total += int(stakes[key])
	if total > wallet.balance:
		return false
	wallet.withdraw(total)
	_stakes = stakes
	return true


func play(rng: RandomNumberGenerator) -> Dictionary:
	var number: int = scripted.pop_front() if not scripted.is_empty() else rng.randi_range(0, 36)
	var staked := 0
	var returned := 0
	for key in _stakes:
		var stake := int(_stakes[key])
		staked += stake
		if _covered(key)[number] == 1:
			returned += stake * (RouletteBets.payout(key) + 1)
	wallet.deposit(returned)
	var colour := "green" if number == 0 else ("red" if number in RouletteWheel.RED_NUMBERS else "black")
	var outcome := {
		"number": number,
		"label": "%d %s" % [number, colour],
		"stakes": _stakes,
		"staked": staked,
		# Every roulette bet gives the house the zero: 1/37 of the stake.
		"cost": staked * RouletteBets.HOUSE_EDGE,
	}
	_stakes = {}
	return outcome


## Whether a position wins on this outcome — staked or not, so a system can
## watch bets it isn't making.
func hit(key: String, outcome: Dictionary) -> bool:
	if not RouletteBets.has(key):
		return false
	return _covered(key)[int(outcome.number)] == 1


func lost(key: String, outcome: Dictionary) -> bool:
	return outcome.stakes.has(key) and not hit(key, outcome)


func has_event(event: String, outcome: Dictionary) -> bool:
	return event == "zero" and int(outcome.number) == 0


static func _covered(key: String) -> PackedByteArray:
	if not _covers.has(key):
		var row := PackedByteArray()
		row.resize(37)
		for n in RouletteBets.numbers(key):
			row[n] = 1
		_covers[key] = row
	return _covers[key]

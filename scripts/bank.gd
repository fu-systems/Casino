extends Node
## Shared player bankroll, registered as the "Bank" autoload.
## Balance persists across scene changes, and across launches through
## `SaveData`, so closing the app no longer quietly resets it.

signal balance_changed(new_balance: int)

const START_BALANCE := 1000

var balance: int = START_BALANCE


func _ready() -> void:
	var saved: Variant = SaveData.get_value("bank", "balance", START_BALANCE)
	# Anything that isn't a sane chip count (a hand-edited or corrupt save)
	# falls back to a fresh bankroll rather than an odd one.
	balance = int(saved) if typeof(saved) == TYPE_INT and int(saved) >= 0 else START_BALANCE
	balance_changed.connect(_save)


func _save(new_balance: int) -> void:
	SaveData.set_value("bank", "balance", new_balance)


func can_afford(amount: int) -> bool:
	return amount > 0 and amount <= balance


## Removes chips from the bankroll. Returns false (and changes nothing)
## if the amount is invalid or exceeds the current balance.
func withdraw(amount: int) -> bool:
	if amount <= 0 or amount > balance:
		return false
	balance -= amount
	balance_changed.emit(balance)
	return true


func deposit(amount: int) -> void:
	if amount <= 0:
		return
	balance += amount
	balance_changed.emit(balance)


func reset() -> void:
	balance = START_BALANCE
	balance_changed.emit(balance)


## Formats an integer with thousands separators, e.g. 12345 -> "12,345".
func fmt(n: int) -> String:
	var negative := n < 0
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3, 3) + out
		digits = digits.substr(0, digits.length() - 3)
	out = digits + out
	if negative:
		return "-" + out
	return out

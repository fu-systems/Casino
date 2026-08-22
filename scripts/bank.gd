extends Node
## Shared player bankroll, registered as the "Bank" autoload.
## Balance persists across scene changes (menu, blackjack, roulette).

signal balance_changed(new_balance: int)

const START_BALANCE := 1000

var balance: int = START_BALANCE


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

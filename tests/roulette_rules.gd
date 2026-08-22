extends CasinoTest
## Roulette wheel, board and repeat-until-win, driven against the real scene.

var t: Control


func run() -> void:
	t = load("res://scenes/roulette.tscn").instantiate()
	add_child(t)
	await frames()

	_test_wheel()
	_test_board_coverage()
	_test_payout_table()
	_test_run_summary()
	_test_replace_bets()
	await _test_repeat_requires_a_bet()
	await _test_repeat_locks_controls()
	await _test_repeat_stops_on_a_win()
	await _test_repeat_stops_when_broke()
	await _test_repeat_spin_cap()

	t.queue_free()


func _stake(key: String, amount: int) -> void:
	# Bets are pre-paid on the board, so mirror what clicking it does.
	t.board.place(key, amount)
	t._update_totals()


func _clear_board() -> void:
	t.board.clear_all()
	t._update_totals()


func _idle() -> void:
	await settle(func() -> bool: return not t.repeat_mode and not t.spinning,
		40000, "the wheel to come to rest")


func _test_wheel() -> void:
	var order: Array = RouletteWheel.WHEEL_ORDER
	check(order.size() == 37, "a European wheel has 37 pockets, got %d" % order.size())
	var seen := {}
	for n in order:
		check(n >= 0 and n <= 36, "pocket %s is outside 0-36" % n)
		check(not seen.has(n), "pocket %s appears twice" % n)
		seen[n] = true
	check(seen.size() == 37, "every number 0-36 should appear exactly once")
	# The real wheel alternates colours away from the zero.
	check(order[0] == 0, "the wheel should start at the zero")
	var reds: Array = RouletteWheel.RED_NUMBERS
	check(reds.size() == 18, "there are 18 red numbers, got %d" % reds.size())
	for n in reds:
		check(n >= 1 and n <= 36, "red %s is outside 1-36" % n)
	# Reds and blacks must alternate around the wheel, ignoring the zero.
	var flips := 0
	for i in range(1, 37):
		var a: int = order[i]
		var b: int = order[1 + (i % 36)]
		if (a in reds) == (b in reds):
			flips += 1
	check(flips == 0, "wheel colours should alternate; %d neighbours matched" % flips)
	note("wheel: 37 unique pockets, 18 reds, colours alternate")


func _test_board_coverage() -> void:
	# The board grid is built from (col + 1) * 3 - row; every number 1-36 must
	# appear exactly once, or a straight bet would be unreachable.
	var seen := {}
	for row in 3:
		for col in 12:
			var n := (col + 1) * 3 - row
			check(n >= 1 and n <= 36, "grid produced %d, outside 1-36" % n)
			check(not seen.has(n), "grid produced %d twice" % n)
			seen[n] = true
	check(seen.size() == 36, "the grid should cover all 36 numbers")

	# Outside bets must partition the board correctly, and none may cover zero.
	for key in ["red", "black", "even", "odd", "low", "high"]:
		var numbers: Array = t.board.meta(key).numbers
		check(numbers.size() == 18, "%s should cover 18 numbers, covers %d" % [key, numbers.size()])
		check(not (0 in numbers), "%s must not cover the zero" % key)
	for i in 3:
		check(t.board.meta("dozen_%d" % i).numbers.size() == 12, "dozen %d should cover 12 numbers" % i)
		check(t.board.meta("column_%d" % i).numbers.size() == 12, "column %d should cover 12 numbers" % i)
	note("board covers 1-36 once, outside bets are 18s and exclude the zero")


func _test_payout_table() -> void:
	check(int(t.board.meta("straight_17").payout) == 35, "a straight bet pays 35:1")
	check(int(t.board.meta("dozen_0").payout) == 2, "a dozen pays 2:1")
	check(int(t.board.meta("column_0").payout) == 2, "a column pays 2:1")
	for key in ["red", "black", "even", "odd", "low", "high"]:
		check(int(t.board.meta(key).payout) == 1, "%s pays 1:1" % key)
	note("payouts: 35:1 straight, 2:1 dozens and columns, 1:1 even money")


func _test_run_summary() -> void:
	check(String(t._run_summary(50)).contains("Up $50"), "a winning run should read as up")
	check(String(t._run_summary(-50)).contains("Down $50"), "a losing run should read as down")
	check(String(t._run_summary(0)).contains("Break-even"), "a flat run should read as break-even")
	note("the run summary reports the whole run, not just the last spin")


func _test_replace_bets() -> void:
	Bank.reset()
	Bank.deposit(1000)
	_clear_board()
	t.repeat_template = {"red": 25, "straight_7": 10}
	var before: int = Bank.balance
	check(t._replace_bets(), "re-staking should succeed when affordable")
	check(Bank.balance == before - 35, "re-staking should take exactly $35")
	check(t.board.amount("red") == 25 and t.board.amount("straight_7") == 10,
		"both stakes should be restored")
	_clear_board()
	Bank.withdraw(Bank.balance - 10)
	var poor: int = Bank.balance
	check(not t._replace_bets(), "re-staking should fail when the bank is short")
	check(Bank.balance == poor, "a failed re-stake must not touch the balance")
	check(t._total_bet() == 0, "a failed re-stake must not put chips on the board")
	note("the saved layout is re-staked atomically, or not at all")


func _test_repeat_requires_a_bet() -> void:
	Bank.reset()
	_clear_board()
	t._on_repeat_pressed()
	await frames()
	check(not t.repeat_mode, "repeat must refuse to start with nothing staked")
	note("repeat refuses to start without a bet")


func _test_repeat_locks_controls() -> void:
	Bank.reset()
	Bank.deposit(500000)
	_clear_board()
	_stake("black", 5)
	t._on_repeat_pressed()
	check(t.repeat_mode, "expected a run to be under way")
	check(t.spin_button.disabled, "SPIN should be locked during a run")
	check(t.clear_button.disabled, "Clear Bets should be locked during a run")
	check(t.back_button.disabled, "Back should be locked during a run")
	check(not t.repeat_button.disabled, "the repeat button must stay live so it can be stopped")
	var before: int = Bank.balance
	t._on_bet_button_pressed("straight_1")
	check(Bank.balance == before, "a mid-run board click must not take chips")
	t._on_repeat_pressed()
	await _idle()
	check(not t.spin_button.disabled, "controls should unlock when the run ends")
	note("controls lock during a run, unlock after, and the board is refused")


func _test_repeat_stops_on_a_win() -> void:
	# A red-only bet pays 1:1, so any red is a profitable spin. With a deep
	# bank the only reachable stop is a win, so the run must end on red.
	Bank.reset()
	Bank.deposit(500000)
	_clear_board()
	t.history.clear()
	_stake("red", 10)
	t._on_repeat_pressed()
	await _idle()
	check(t.history.size() > 0, "the run should have spun at least once")
	check(t.history[0] in RouletteWheel.RED_NUMBERS,
		"a red-only run must stop on red, ended on %s" % t.history[0])
	note("the run stops on the spin that wins")


func _test_repeat_stops_when_broke() -> void:
	# Stake all but a few dollars: whether it wins or loses, a second spin is
	# unaffordable, so exactly one spin can run.
	Bank.reset()
	_clear_board()
	t.history.clear()
	var all_in: int = Bank.balance - 3
	_stake("red", all_in)
	t._on_repeat_pressed()
	await _idle()
	check(t.history.size() == 1, "only one spin was affordable, but %d ran" % t.history.size())
	note("repeat stops when the bank can't cover the next stake")


func _test_repeat_spin_cap() -> void:
	# Covering all 37 numbers returns 36 on a 37 stake — a guaranteed one-unit
	# loss every spin, so this run can only ever end at the safety cap.
	Bank.reset()
	Bank.deposit(500000)
	_clear_board()
	for n in range(0, 37):
		_stake("straight_%d" % n, 1)
	check(t._total_bet() == 37, "expected $37 across the whole board")
	var cap: int = t.MAX_REPEAT_SPINS
	var before: int = Bank.balance
	t._on_repeat_pressed()
	await _idle()
	# Each of `cap` spins pays back 36; the layout is re-staked cap-1 times.
	var expected: int = before + 36 * cap - 37 * (cap - 1)
	check(Bank.balance == expected,
		"after %d capped spins expected $%d, got $%d" % [cap, expected, Bank.balance])
	note("a run with no win stops at the %d-spin cap, down exactly $%d" % [cap, cap])

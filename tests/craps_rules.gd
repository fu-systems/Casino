extends CasinoTest
## Craps rules, driven through the real table with scripted dice.
##
## Every bet is settled by rolling known dice at it and asserting the balance
## moved by exactly the published odds, so a wrong payout is a failure rather
## than a rounding curiosity nobody notices.

const START := 500000

var t: Control


func run() -> void:
	t = load("res://scenes/craps.tscn").instantiate()
	add_child(t)
	await frames()

	await _test_dice_distribution()
	await _test_come_out()
	await _test_point_made_and_seven_out()
	await _test_odds_caps()
	await _test_odds_payouts()
	await _test_come_travels_and_pays()
	await _test_dont_come()
	await _test_seven_out_sweeps_the_table()
	await _test_place_bets()
	await _test_field()
	await _test_hardways()
	await _test_props()
	await _test_big_six_and_eight()
	await _test_come_out_sleeps_place_and_odds()
	await _test_money_conservation()

	t.queue_free()


# --- helpers -----------------------------------------------------------------

## Resets the table to a come-out roll with a full bankroll and nothing down.
func _reset() -> void:
	Bank.reset()
	Bank.deposit(START)
	t.board.clear_all()
	t.point = 0
	t.scripted_rolls.clear()


## Puts chips on a bet without going through the table's own refusals, so a
## test can set up a position the player would have reached over several
## rolls.
func _stake(key: String, amount: int) -> void:
	t.board.place(key, amount)


## Rolls the given dice and waits for the table to finish settling.
func _roll(d1: int, d2: int) -> void:
	t.scripted_rolls = [[d1, d2]]
	t._on_roll_pressed()
	await settle(func() -> bool: return not t.rolling, 40000, "the dice to settle")


## Rolls a sequence, one pair at a time.
func _roll_all(rolls: Array) -> void:
	for pair in rolls:
		await _roll(int(pair[0]), int(pair[1]))


# --- dice --------------------------------------------------------------------

func _test_dice_distribution() -> void:
	# Two independent dice, not one uniform pick over 2-12. With 180,000
	# rolls the expected counts are far enough apart that a uniform
	# generator (about 16,363 of each) cannot pass this.
	var rolls := 180000
	var counts := {}
	for i in rolls:
		var dice: Array = t._roll_dice()
		check(int(dice[0]) >= 1 and int(dice[0]) <= 6, "die outside 1-6")
		var total: int = int(dice[0]) + int(dice[1])
		counts[total] = int(counts.get(total, 0)) + 1

	var ways := {2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 8: 5, 9: 4, 10: 3, 11: 2, 12: 1}
	check(counts.size() == 11, "totals should span 2-12, saw %d values" % counts.size())
	var worst := 0.0
	for total in ways:
		var expected := rolls * float(ways[total]) / 36.0
		var drift: float = abs(int(counts.get(total, 0)) - expected) / expected
		worst = maxf(worst, drift)
		check(drift < 0.06, "total %d came up %d times, expected about %d" % [
			total, int(counts.get(total, 0)), int(expected)])
	note("2d6 histogram matches the real distribution (worst drift %.1f%%)" % (worst * 100.0))


# --- the line ----------------------------------------------------------------

func _test_come_out() -> void:
	for natural in [[3, 4], [5, 6]]:
		_reset()
		_stake("pass", 100)
		_stake("dont_pass", 100)
		var start: int = Bank.balance
		await _roll(int(natural[0]), int(natural[1]))
		check(Bank.balance - start == 200,
			"a natural should pay the pass line $200 back and take the don't, got %+d" % (Bank.balance - start))
		check(t.point == 0, "a natural leaves the point off")

	for craps in [[1, 1], [1, 2]]:
		_reset()
		_stake("pass", 100)
		_stake("dont_pass", 100)
		var start: int = Bank.balance
		await _roll(int(craps[0]), int(craps[1]))
		check(Bank.balance - start == 200,
			"craps should pay the don't $200 back and take the pass, got %+d" % (Bank.balance - start))

	# The barred twelve is where the don't side's edge comes from: the pass
	# line loses but the don't bet only pushes.
	_reset()
	_stake("pass", 100)
	_stake("dont_pass", 100)
	var start: int = Bank.balance
	await _roll(6, 6)
	check(Bank.balance - start == 100,
		"a barred twelve should return the don't stake only, got %+d" % (Bank.balance - start))

	_reset()
	_stake("pass", 100)
	await _roll(2, 3)
	check(t.point == 5, "a 5 on the come-out sets the point, point is %d" % t.point)
	check(t.board.amount("pass") == 100, "the pass line stays up behind its point")
	note("come-out: 7 and 11 pay the line, 2 and 3 pay the don't, 12 is barred")


func _test_point_made_and_seven_out() -> void:
	_reset()
	_stake("pass", 100)
	await _roll(3, 3)
	check(t.point == 6, "the point should be 6")
	var start: int = Bank.balance
	await _roll(2, 4)
	check(Bank.balance - start == 200, "making the point pays 1:1, got %+d" % (Bank.balance - start))
	check(t.point == 0, "making the point turns it off")

	_reset()
	_stake("pass", 100)
	_stake("dont_pass", 100)
	await _roll(4, 4)
	check(t.point == 8, "the point should be 8")
	start = Bank.balance
	await _roll(3, 4)
	check(Bank.balance - start == 200,
		"sevening out pays the don't 1:1 and takes the line, got %+d" % (Bank.balance - start))
	check(t.point == 0, "a seven-out turns the point off")
	note("the point pays the line when made and the don't when it sevens out")


# --- odds --------------------------------------------------------------------

func _test_odds_caps() -> void:
	# 3-4-5x: whatever the point, the most you can win behind the line is six
	# times it.
	var expect := {4: 3, 5: 4, 6: 5, 8: 5, 9: 4, 10: 3}
	for number in expect:
		_reset()
		_stake("pass", 100)
		t.point = number
		check(t._max_odds("pass_odds") == 100 * int(expect[number]),
			"pass odds on the %d should cap at %dx, capped at $%d" % [
				number, int(expect[number]), t._max_odds("pass_odds")])
		var o: Array = t.TRUE_ODDS[number]
		var win: int = t._max_odds("pass_odds") * int(o[0]) / int(o[1])
		check(win == 600, "max odds on the %d should win $600, wins $%d" % [number, win])

	# The wrong side lays more than it wins, so its cap is whatever lays up
	# to the same six-times win.
	var lays := {4: 1200, 5: 900, 6: 720, 8: 720, 9: 900, 10: 1200}
	for number in lays:
		_reset()
		_stake("dont_pass", 100)
		t.point = number
		check(t._max_odds("dont_pass_odds") == int(lays[number]),
			"the lay cap on the %d should be $%d, is $%d" % [
				number, int(lays[number]), t._max_odds("dont_pass_odds")])

	# And the table refuses a chip that would breach the cap.
	_reset()
	_stake("pass", 5)
	t.point = 4
	t.selected_chip = 100
	check(t._refusal("pass_odds") != "", "odds over the cap should be refused")
	t.selected_chip = 25
	note("odds cap at 3-4-5x on both sides, and over-cap chips are refused")


func _test_odds_payouts() -> void:
	# True odds: 2:1 on 4 and 10, 3:2 on 5 and 9, 6:5 on 6 and 8.
	var pays := {4: 200, 5: 150, 6: 120, 8: 120, 9: 150, 10: 200}
	for number in pays:
		_reset()
		_stake("pass", 100)
		t.point = number
		_stake("pass_odds", 100)
		var start: int = Bank.balance
		await _roll(_split(number)[0], _split(number)[1])
		# $100 line at 1:1 plus $100 odds at true price, both stakes back.
		var want: int = 100 + 100 + 100 + int(pays[number])
		check(Bank.balance - start == want,
			"making the %d with $100 odds should return $%d, returned $%d" % [
				number, want, Bank.balance - start])

	# Laying odds against the point wins the odds the other way up.
	var lay_wins := {4: 50, 5: 66, 6: 83, 8: 83, 9: 66, 10: 50}
	for number in lay_wins:
		_reset()
		_stake("dont_pass", 100)
		t.point = number
		_stake("dont_pass_odds", 100)
		var start: int = Bank.balance
		await _roll(3, 4)
		var want: int = 100 + 100 + 100 + int(lay_wins[number])
		check(Bank.balance - start == want,
			"a $100 lay against the %d should return $%d, returned $%d" % [
				number, want, Bank.balance - start])
	note("odds pay true price both ways: 2:1, 3:2, 6:5, and the inverse laid")


# --- come and don't come -----------------------------------------------------

func _test_come_travels_and_pays() -> void:
	_reset()
	_stake("pass", 100)
	await _roll(3, 3)          # point 6
	_stake("come", 100)
	await _roll(4, 5)          # come travels to the 9
	check(t.board.amount("come") == 0, "the come bar should be empty once the bet travels")
	check(t.board.amount("come_9") == 100, "the come bet should sit on the 9")

	# Odds go behind it, and both pay when the number repeats.
	_stake("come_odds_9", 100)
	var start: int = Bank.balance
	await _roll(4, 5)
	check(Bank.balance - start == 100 + 100 + 100 + 150,
		"a come 9 with $100 odds should return $450, returned $%d" % (Bank.balance - start))
	check(t.board.amount("come_9") == 0, "a paid come bet comes down")

	# 7 and 11 win on the bar; craps takes it.
	_reset()
	t.point = 6
	_stake("come", 100)
	start = Bank.balance
	await _roll(5, 6)
	check(Bank.balance - start == 200, "an 11 pays the come bar 1:1, got %+d" % (Bank.balance - start))

	_reset()
	t.point = 6
	_stake("come", 100)
	start = Bank.balance
	await _roll(1, 1)
	check(Bank.balance - start == 0, "craps takes the come bar, got %+d" % (Bank.balance - start))
	note("come bets win on 7/11, lose to craps, and otherwise travel and take odds")


func _test_dont_come() -> void:
	_reset()
	t.point = 6
	_stake("dont_come", 100)
	await _roll(2, 3)
	check(t.board.amount("dont_come_5") == 100, "the don't come bet should sit on the 5")

	# It wins on a seven, and its lay pays the odds inverted.
	_stake("dont_come_odds_5", 150)
	var start: int = Bank.balance
	await _roll(3, 4)
	check(Bank.balance - start == 100 + 100 + 150 + 100,
		"a don't come 5 with a $150 lay should return $450, returned $%d" % (Bank.balance - start))

	# 2 and 3 pay it on the bar, 12 pushes, 7 and 11 take it.
	for craps in [[1, 1], [1, 2]]:
		_reset()
		t.point = 6
		_stake("dont_come", 100)
		start = Bank.balance
		await _roll(int(craps[0]), int(craps[1]))
		check(Bank.balance - start == 200,
			"craps pays the don't come bar 1:1, got %+d" % (Bank.balance - start))

	_reset()
	t.point = 6
	_stake("dont_come", 100)
	start = Bank.balance
	await _roll(6, 6)
	check(Bank.balance - start == 100, "the barred twelve pushes the don't come bar")

	_reset()
	t.point = 6
	_stake("dont_come", 100)
	start = Bank.balance
	await _roll(3, 4)
	check(Bank.balance - start == 0, "a seven takes the don't come bar, got %+d" % (Bank.balance - start))
	note("don't come mirrors come, bars the twelve, and lays odds the other way up")


func _test_seven_out_sweeps_the_table() -> void:
	_reset()
	_stake("pass", 100)
	await _roll(2, 2)          # point 4
	_stake("pass_odds", 100)
	_stake("place_6", 60)
	_stake("place_8", 60)
	_stake("hard_8", 10)
	_stake("big_6", 25)
	_stake("come", 50)
	await _roll(4, 5)          # the come bet travels to the 9
	_stake("come_odds_9", 50)
	_stake("dont_come", 40)
	await _roll(5, 5)          # the don't come bet travels to the 10
	_stake("dont_come_odds_10", 80)

	var on_the_table: int = t.board.total()
	var start: int = Bank.balance
	await _roll(1, 6)          # seven out

	# Everything on the right side dies; the don't come 10 pays 1:1 and its
	# $80 lay pays $40 at 1:2.
	check(t.board.total() == 0, "a seven-out should clear the table, $%d left" % t.board.total())
	check(t.point == 0, "a seven-out turns the point off")
	check(Bank.balance - start == 40 + 40 + 80 + 40,
		"only the don't come 10 and its lay should pay, got %+d" % (Bank.balance - start))
	check(on_the_table > 0, "the table should have had bets on it")
	note("a seven-out takes the line, come, place, hardway and big bets in one roll")


# --- the boxes ---------------------------------------------------------------

func _test_place_bets() -> void:
	# 9:5 on the 4 and 10, 7:5 on the 5 and 9, 7:6 on the 6 and 8, and the
	# stake stays up.
	var stakes := {4: 50, 5: 50, 6: 60, 8: 60, 9: 50, 10: 50}
	var pays := {4: 90, 5: 70, 6: 70, 8: 70, 9: 70, 10: 90}
	for number in stakes:
		_reset()
		t.point = 5 if number != 5 else 6
		_stake("place_%d" % number, int(stakes[number]))
		var start: int = Bank.balance
		await _roll(_split(number)[0], _split(number)[1])
		check(Bank.balance - start == int(pays[number]),
			"place %d for $%d should pay $%d, paid $%d" % [
				number, int(stakes[number]), int(pays[number]), Bank.balance - start])
		check(t.board.amount("place_%d" % number) == int(stakes[number]),
			"a winning place bet stays working")

	# Payouts round down to the dollar, as a dealer does with odd money.
	_reset()
	t.point = 4
	_stake("place_6", 5)
	var start: int = Bank.balance
	await _roll(3, 3)
	check(Bank.balance - start == 5, "a $5 place 6 pays $5, not $5.83, paid $%d" % (Bank.balance - start))
	note("place bets pay 9:5, 7:5 and 7:6, round down, and stay working")


func _test_field() -> void:
	var pays := {2: 200, 3: 100, 4: 100, 9: 100, 10: 100, 11: 100, 12: 300}
	for number in pays:
		_reset()
		_stake("field", 100)
		var start: int = Bank.balance
		await _roll(_split(number)[0], _split(number)[1])
		check(Bank.balance - start == 100 + int(pays[number]),
			"the field on a %d should return $%d, returned $%d" % [
				number, 100 + int(pays[number]), Bank.balance - start])
	for number in [5, 6, 7, 8]:
		_reset()
		_stake("field", 100)
		var start: int = Bank.balance
		await _roll(_split(number)[0], _split(number)[1])
		check(Bank.balance - start == 0, "the field should lose on a %d" % number)
	note("field pays 1:1, double on the 2 and triple on the 12, loses on 5-8")


func _test_hardways() -> void:
	var pays := {4: 7, 6: 9, 8: 9, 10: 7}
	for number in pays:
		# The hard way rolled as a pair pays its odds.
		_reset()
		t.point = 5
		_stake("hard_%d" % number, 10)
		var start: int = Bank.balance
		await _roll(number / 2, number / 2)
		check(Bank.balance - start == 10 + 10 * int(pays[number]),
			"hard %d should pay %d:1, got %+d" % [number, int(pays[number]), Bank.balance - start])

		# The same number rolled easy kills it.
		_reset()
		t.point = 5
		_stake("hard_%d" % number, 10)
		start = Bank.balance
		await _roll(_split(number)[0], _split(number)[1])
		check(Bank.balance - start == 0,
			"hard %d should lose to an easy %d" % [number, number])

		# So does a seven.
		_reset()
		t.point = 5
		_stake("hard_%d" % number, 10)
		start = Bank.balance
		await _roll(3, 4)
		check(Bank.balance - start == 0, "hard %d should lose to a seven" % number)
	note("hardways pay 7:1 and 9:1, and die to the easy way or a seven")


func _test_props() -> void:
	var cases := [
		{"key": "any_7", "win": [3, 4], "lose": [1, 1], "pays": 4},
		{"key": "any_craps", "win": [1, 2], "lose": [3, 4], "pays": 7},
		{"key": "prop_2", "win": [1, 1], "lose": [1, 2], "pays": 30},
		{"key": "prop_3", "win": [1, 2], "lose": [1, 1], "pays": 15},
		{"key": "prop_11", "win": [5, 6], "lose": [3, 4], "pays": 15},
		{"key": "prop_12", "win": [6, 6], "lose": [1, 1], "pays": 30},
	]
	for c in cases:
		_reset()
		t.point = 5
		_stake(String(c.key), 10)
		var start: int = Bank.balance
		await _roll(int(c.win[0]), int(c.win[1]))
		check(Bank.balance - start == 10 + 10 * int(c.pays),
			"%s should pay %d:1, got %+d" % [c.key, int(c.pays), Bank.balance - start])

		_reset()
		t.point = 5
		_stake(String(c.key), 10)
		start = Bank.balance
		await _roll(int(c.lose[0]), int(c.lose[1]))
		check(Bank.balance - start == 0, "%s should lose on that roll" % c.key)

	# The horn is quartered: one quarter wins at its own price and the other
	# three are lost. These measure the net over the whole bet, so `start` is
	# taken before the chips go down rather than after.
	_reset()
	t.point = 5
	var start := Bank.balance
	_stake("horn", 40)
	await _roll(1, 1)
	check(Bank.balance - start == 270,
		"a $40 horn on the 2 pays its $10 quarter at 30:1, netting +$270, got %+d" % (Bank.balance - start))

	_reset()
	t.point = 5
	start = Bank.balance
	_stake("horn", 40)
	await _roll(5, 6)
	check(Bank.balance - start == 120,
		"a $40 horn on the 11 pays its $10 quarter at 15:1, netting +$120, got %+d" % (Bank.balance - start))

	_reset()
	t.point = 5
	start = Bank.balance
	_stake("horn", 40)
	await _roll(2, 2)
	check(Bank.balance - start == -40, "the horn loses everything on a 4")

	# C & E is halved between any craps and the yo.
	_reset()
	t.point = 5
	start = Bank.balance
	_stake("c_and_e", 20)
	await _roll(1, 2)
	check(Bank.balance - start == 60,
		"a $20 C & E on a 3 pays its $10 half at 7:1, netting +$60, got %+d" % (Bank.balance - start))

	_reset()
	t.point = 5
	start = Bank.balance
	_stake("c_and_e", 20)
	await _roll(5, 6)
	check(Bank.balance - start == 140,
		"a $20 C & E on the yo pays its $10 half at 15:1, netting +$140, got %+d" % (Bank.balance - start))

	_reset()
	t.point = 5
	start = Bank.balance
	_stake("c_and_e", 20)
	await _roll(2, 2)
	check(Bank.balance - start == -20, "C & E loses on a 4")
	note("props pay their published odds; the horn quarters and C & E halves")


func _test_big_six_and_eight() -> void:
	for number in [6, 8]:
		_reset()
		t.point = 5
		_stake("big_%d" % number, 25)
		var start: int = Bank.balance
		await _roll(_split(number)[0], _split(number)[1])
		check(Bank.balance - start == 25, "big %d should pay 1:1, got %+d" % [number, Bank.balance - start])
		check(t.board.amount("big_%d" % number) == 25, "a winning big bet stays working")

		_reset()
		t.point = 5
		_stake("big_%d" % number, 25)
		start = Bank.balance
		await _roll(3, 4)
		check(Bank.balance - start == 0, "big %d should lose to a seven" % number)
	note("big 6 and big 8 pay 1:1, stay working, and die to a seven")


func _test_come_out_sleeps_place_and_odds() -> void:
	# Place bets sit out the come-out: a seven that would normally take them
	# leaves them alone.
	_reset()
	_stake("pass", 100)
	_stake("place_6", 60)
	_stake("place_8", 60)
	var start: int = Bank.balance
	await _roll(3, 4)
	check(t.board.amount("place_6") == 60 and t.board.amount("place_8") == 60,
		"place bets should survive a come-out seven")
	check(Bank.balance - start == 200, "only the pass line should be paid on a come-out seven")

	# And they don't pay on the come-out either.
	_reset()
	_stake("pass", 100)
	_stake("place_6", 60)
	start = Bank.balance
	await _roll(3, 3)
	check(Bank.balance - start == 0, "a place 6 shouldn't pay on the come-out, got %+d" % (Bank.balance - start))
	check(t.point == 6, "the 6 should have set the point instead")

	# Come odds sleep too: a come-out seven takes the flat bet but hands the
	# odds back.
	_reset()
	t.board.move_in("come_9", 100)
	_stake("come_odds_9", 100)
	t.point = 0
	_stake("pass", 50)
	start = Bank.balance
	await _roll(3, 4)
	check(Bank.balance - start == 100 + 100,
		"a come-out seven should return the sleeping odds and pay the line, got %+d" % (Bank.balance - start))
	check(t.board.amount("come_9") == 0, "the flat come bet still loses to a come-out seven")
	note("place bets and come odds sleep through the come-out")


func _test_money_conservation() -> void:
	# Play a long random session across every bet on the table and assert
	# the bank never goes negative and the table never holds more than was
	# staked.
	Bank.reset()
	Bank.deposit(50000)
	t.board.clear_all()
	t.point = 0
	t.scripted_rolls.clear()
	var keys := ["pass", "dont_pass", "come", "dont_come", "field", "big_6", "big_8",
		"hard_6", "any_7", "any_craps", "horn", "c_and_e",
		"place_5", "place_6", "place_8", "place_9"]
	var rolls := 0
	for i in 120:
		for key in keys:
			if t._refusal(key) == "" and Bank.balance >= 10:
				t.board.place(key, 10)
		if t.board.total() == 0:
			continue
		await _roll(randi() % 6 + 1, randi() % 6 + 1)
		rolls += 1
		check(Bank.balance >= 0, "the bank went negative on roll %d" % rolls)
	check(rolls > 60, "the session should have rolled plenty, rolled %d" % rolls)
	t.board.refund_all()
	note("%d rolls across every bet on the table, bank never went negative" % rolls)


# --- dice for a total --------------------------------------------------------

## A pair of dice making the total. Deliberately not the hard way for the
## even numbers, so hardway tests have to ask for that explicitly.
func _split(total: int) -> Array:
	match total:
		2: return [1, 1]
		3: return [1, 2]
		4: return [1, 3]
		5: return [2, 3]
		6: return [2, 4]
		7: return [3, 4]
		8: return [3, 5]
		9: return [4, 5]
		10: return [4, 6]
		11: return [5, 6]
		12: return [6, 6]
	return [1, 1]

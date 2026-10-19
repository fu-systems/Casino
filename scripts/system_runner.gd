class_name SystemRunner
extends RefCounted
## Plays a Systems Lab system: one session round by round with a full record,
## or many sessions for the odds.
##
## The runner never touches the player's real bankroll; every session plays
## from its own wallet. And every result carries the house's expected take —
## each resolved stake times its bet's edge — beside what actually happened,
## because a short run can make any system look like it works.
##
## Each round:
##   1. The step's bets go down: units times the current unit, raised to the
##      table minimum and capped at the table maximum.
##   2. The game plays the round.
##   3. The streaks and the history update.
##   4. The first rule whose condition holds runs its actions; if none does,
##      the step's OTHERWISE actions run.
##   5. Stop if the system said so, the take-profit or stop-loss is reached,
##      or the rounds are done. A wallet that can't cover the next bets stops
##      the session too: that's going broke.

const TRACE_LIMIT := 200
const CURVE_POINTS := 400
const HISTORY := 64
const HISTOGRAM_BINS := 21

## Stop reasons, as the results screen says them.
const REASONS := {
	"rounds": "played every round",
	"broke": "couldn't cover the next bet",
	"stopped": "the system said stop",
	"take_profit": "hit the take-profit",
	"stop_loss": "hit the stop-loss",
}


class Wallet:
	extends RefCounted
	var balance := 0

	func withdraw(amount: int) -> bool:
		if amount < 0 or amount > balance:
			return false
		balance -= amount
		return true

	func deposit(amount: int) -> void:
		if amount > 0:
			balance += amount


## Runs many sessions a slice at a time, so a screen can show progress and
## stay responsive. `step` runs sessions until `budget_ms` is spent.
class MonteCarlo:
	extends RefCounted
	var system: Dictionary
	var sessions := 0
	var seed := 0
	var done_sessions := 0
	var results: Array = []

	func _init(sys: Dictionary, count: int, first_seed: int) -> void:
		system = SystemModel.normalised(sys)
		sessions = count
		seed = first_seed

	func step(budget_ms: int = 12) -> void:
		var until := Time.get_ticks_msec() + budget_ms
		while done_sessions < sessions and Time.get_ticks_msec() < until:
			results.append(SystemRunner.run_session(system, seed + done_sessions, false))
			done_sessions += 1

	func done() -> bool:
		return done_sessions >= sessions

	func progress() -> float:
		return float(done_sessions) / maxf(1.0, sessions)

	func summary() -> Dictionary:
		return SystemRunner.summarise(results, int(system.settings.bankroll))


## Plays one session. With `detail`, also returns the bankroll curve and a
## trace of the first TRACE_LIMIT rounds. `scripted` forces the first
## outcomes, for the rule suites.
static func run_session(sys: Dictionary, seed: int, detail: bool = true, scripted: Array = []) -> Dictionary:
	var system := SystemModel.normalised(sys)
	var settings: Dictionary = system.settings
	var game := String(system.game)
	var base := float(settings.unit)
	var wallet := Wallet.new()
	wallet.balance = int(settings.bankroll)
	var adapter: Variant = SystemModel.make_adapter(game)
	adapter.reset(wallet)
	adapter.scripted = scripted.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var steps := {}
	for entry in system.steps:
		steps[int(entry.id)] = entry
	var state := {
		"step": int(system.start), "layout": {}, "unit": base, "base": base, "a": 0.0, "b": 0.0,
		"win_streak": 0, "loss_streak": 0, "round": 0, "step_rounds": 0,
		"sit_out": 0, "stop": false, "history": [], "net": 0, "bankroll": wallet.balance,
	}
	_enter(state, steps, int(system.start))

	var start := int(settings.bankroll)
	var peak := start
	var max_drawdown := 0
	var total_staked := 0
	var expected := 0.0
	var largest_bet := 0
	var capped := 0
	var longest_losing := 0
	var reason := "rounds"
	var curve: Array = [start]
	var trace: Array = []

	while int(state.round) < int(settings.rounds):
		var equity_before: int = wallet.balance + adapter.on_table()
		var stakes := {}
		var odds := {}
		var sitting: bool = int(state.sit_out) > 0
		if sitting:
			state.sit_out = int(state.sit_out) - 1
		else:
			for key in state.layout:
				var units := int(state.layout[key])
				if String(key).begins_with("odds:"):
					odds[String(key).substr(5)] = units
					continue
				if units <= 0:
					continue
				var stake := maxi(int(settings.table_min), roundi(units * float(state.unit)))
				if stake > int(settings.table_max):
					stake = int(settings.table_max)
					capped += 1
				stakes[key] = stake
				largest_bet = maxi(largest_bet, stake)
		if not adapter.place(stakes, odds):
			reason = "broke"
			break

		var outcome: Dictionary = adapter.play(rng)
		state.round = int(state.round) + 1
		state.step_rounds = int(state.step_rounds) + 1
		var equity: int = wallet.balance + adapter.on_table()
		var net := equity - equity_before
		total_staked += int(outcome.staked)
		expected -= float(outcome.cost)
		if net > 0:
			state.win_streak = int(state.win_streak) + 1
			state.loss_streak = 0
		elif net < 0:
			state.loss_streak = int(state.loss_streak) + 1
			state.win_streak = 0
			longest_losing = maxi(longest_losing, int(state.loss_streak))
		state.net = equity - start
		state.bankroll = equity
		var history: Array = state.history
		history.push_front(outcome)
		if history.size() > HISTORY:
			history.pop_back()

		var step_name: String = steps[int(state.step)].name
		var fired := _run_rules(state, steps, adapter, outcome, net, game, base)

		peak = maxi(peak, equity)
		max_drawdown = maxi(max_drawdown, peak - equity)
		if detail:
			curve.append(equity)
			if trace.size() < TRACE_LIMIT:
				trace.append({
					"round": int(state.round), "step": step_name, "outcome": outcome.label,
					"bets": _describe_stakes(stakes, game, sitting), "net": net,
					"bankroll": equity, "rule": fired,
				})

		if state.stop:
			reason = "stopped"
			break
		if int(settings.take_profit) > 0 and int(state.net) >= int(settings.take_profit):
			reason = "take_profit"
			break
		if int(settings.stop_loss) > 0 and int(state.net) <= -int(settings.stop_loss):
			reason = "stop_loss"
			break

	var final: int = wallet.balance + adapter.on_table()
	var result := {
		"final": final, "net": final - start, "rounds": int(state.round), "reason": reason,
		"staked": total_staked, "expected": expected, "peak": peak,
		"max_drawdown": max_drawdown, "largest_bet": largest_bet, "capped": capped,
		"longest_losing": longest_losing, "busted": reason == "broke",
	}
	if detail:
		result.curve = _downsample(curve)
		result.trace = trace
	return result


## Many sessions, all at once — for tests, and for anything that doesn't
## need a progress bar.
static func monte_carlo(sys: Dictionary, sessions: int, seed: int) -> Dictionary:
	var batch := MonteCarlo.new(sys, sessions, seed)
	while not batch.done():
		batch.step(1000)
	return batch.summary()


static func summarise(results: Array, bankroll: int) -> Dictionary:
	var nets: Array = []
	var ahead := 0
	var busted := 0
	var staked := 0
	var expected := 0.0
	var rounds := 0
	var longest := 0
	var largest := 0
	var capped := 0
	var reasons := {}
	for r in results:
		nets.append(int(r.net))
		if int(r.net) > 0:
			ahead += 1
		if r.busted:
			busted += 1
		staked += int(r.staked)
		expected += float(r.expected)
		rounds += int(r.rounds)
		longest = maxi(longest, int(r.longest_losing))
		largest = maxi(largest, int(r.largest_bet))
		capped += int(r.capped)
		reasons[r.reason] = int(reasons.get(r.reason, 0)) + 1
	nets.sort()
	var count := maxi(1, results.size())
	var total_net := 0
	for n in nets:
		total_net += int(n)
	return {
		"sessions": results.size(),
		"bankroll": bankroll,
		"mean_net": float(total_net) / count,
		"median_net": nets[nets.size() / 2] if not nets.is_empty() else 0,
		"best": nets[-1] if not nets.is_empty() else 0,
		"worst": nets[0] if not nets.is_empty() else 0,
		"ahead_share": float(ahead) / count,
		"bust_share": float(busted) / count,
		"mean_staked": float(staked) / count,
		"mean_expected": expected / count,
		"total_staked": staked,
		"total_net": total_net,
		"mean_rounds": float(rounds) / count,
		"longest_losing": longest,
		"largest_bet": largest,
		"capped": capped,
		"reasons": reasons,
		"histogram": _histogram(nets),
	}


# --- Inside a round ------------------------------------------------------------------

static func _enter(state: Dictionary, steps: Dictionary, id: int) -> void:
	if not steps.has(id):
		state.stop = true
		return
	state.step = id
	state.layout = steps[id].layout.duplicate()
	state.step_rounds = 0


## Runs the current step's rules and returns which fired: "Rule 2",
## "Otherwise", or "" when there was nothing to run.
static func _run_rules(state: Dictionary, steps: Dictionary, adapter: Variant, outcome: Dictionary,
		net: int, game: String, base: float) -> String:
	var entry: Dictionary = steps[int(state.step)]
	var rules: Array = entry.rules
	for i in rules.size():
		if _holds(rules[i].when, state, adapter, outcome, net):
			_apply(rules[i].then, state, steps, base)
			return "Rule %d" % (i + 1)
	if not entry.otherwise.is_empty():
		_apply(entry.otherwise, state, steps, base)
		return "Otherwise"
	return ""


static func _holds(cond: Dictionary, state: Dictionary, adapter: Variant, outcome: Dictionary, net: int) -> bool:
	match String(cond.get("type", "")):
		"always":
			return true
		"round":
			match String(cond.get("result", "won")):
				"won":
					return net > 0
				"lost":
					return net < 0
			return net == 0
		"wins":
			return adapter.hit(String(cond.get("pos", "")), outcome)
		"loses":
			return adapter.lost(String(cond.get("pos", "")), outcome)
		"group":
			var won := 0
			var keys: Array = cond.get("positions", [])
			for key in keys:
				if adapter.hit(String(key), outcome):
					won += 1
			match String(cond.get("mode", "all")):
				"all":
					return not keys.is_empty() and won == keys.size()
				"any":
					return won > 0
				"none":
					return won == 0
				"exactly":
					return won == int(cond.get("n", 1))
				"at_least":
					return won >= int(cond.get("n", 1))
			return false
		"event":
			return adapter.has_event(String(cond.get("event", "")), outcome)
		"pattern":
			var n := int(cond.get("n", 1))
			var history: Array = state.history
			if history.size() < n:
				return false
			var what := String(cond.get("what", ""))
			var want_hit := String(cond.get("mode", "hit")) == "hit"
			for i in n:
				var past: Dictionary = history[i]
				var happened: bool = adapter.hit(what, past) or adapter.has_event(what, past)
				if happened != want_hit:
					return false
			return true
		"compare":
			var value := _variable(state, String(cond.get("var", "")))
			var target := float(cond.get("value", 0))
			match String(cond.get("op", ">=")):
				">=":
					return value >= target
				">":
					return value > target
				"==":
					return is_equal_approx(value, target)
				"<=":
					return value <= target
				"<":
					return value < target
			return false
		"and":
			for item in cond.get("items", []):
				if not _holds(item, state, adapter, outcome, net):
					return false
			return true
		"or":
			for item in cond.get("items", []):
				if _holds(item, state, adapter, outcome, net):
					return true
			return false
		"not":
			return not _holds(cond.get("item", {"type": "always"}), state, adapter, outcome, net)
	return false


static func _variable(state: Dictionary, name: String) -> float:
	match name:
		"unit":
			# In units, as the editor shows it.
			return float(state.unit) / float(state.base)
		"a", "b", "win_streak", "loss_streak", "round", "step_rounds", "net", "bankroll":
			return float(state[name])
	return 0.0


static func _apply(actions: Array, state: Dictionary, steps: Dictionary, base: float) -> void:
	for action in actions:
		var layout: Dictionary = state.layout
		var key := String(action.get("pos", ""))
		match String(action.get("type", "")):
			"bet":
				var units := int(action.get("units", 1))
				if units > 0:
					layout[key] = units
				else:
					layout.erase(key)
			"add_bet":
				var units := int(layout.get(key, 0)) + int(action.get("units", 1))
				if units > 0:
					layout[key] = units
				else:
					layout.erase(key)
			"clear_bets":
				layout.clear()
			"unit":
				var value := float(action.get("value", 1))
				var unit := float(state.unit)
				match String(action.get("op", "reset")):
					"reset":
						unit = base
					"set":
						unit = value * base
					"add":
						unit += value * base
					"multiply":
						unit *= value
				# Never below one unit, and never so large it stops meaning
				# anything (the table cap bites long before this).
				state.unit = clampf(unit, base, base * 1000000.0)
			"goto":
				_enter(state, steps, int(action.get("step", -1)))
			"counter":
				var which := String(action.get("which", "a"))
				if action.get("op", "add") == "set":
					state[which] = float(action.get("value", 0))
				else:
					state[which] = float(state[which]) + float(action.get("value", 1))
			"sit_out":
				state.sit_out = maxi(0, int(action.get("rounds", 1)))
			"stop":
				state.stop = true
			"press":
				if layout.has(key):
					layout[key] = int(layout[key]) * 2
			"regress":
				if layout.has(key):
					layout[key] = maxi(1, int(layout[key]) / 2)
			"odds":
				# Odds ride on a line or come bet, so they're kept in the
				# layout as "odds:<bet>" = the multiple, 0 meaning the table
				# maximum, and handed to the game separately from the bets.
				layout["odds:" + key] = maxi(0, int(action.get("mult", 0)))


static func _describe_stakes(stakes: Dictionary, game: String, sitting: bool) -> String:
	if sitting:
		return "sitting out"
	if stakes.is_empty():
		return "no bets"
	var parts: PackedStringArray = []
	for key in stakes:
		parts.append("%s $%d" % [SystemModel.position_label(game, key), int(stakes[key])])
	return ", ".join(parts)


static func _downsample(curve: Array) -> Array:
	if curve.size() <= CURVE_POINTS:
		return curve
	var out: Array = []
	var step := float(curve.size() - 1) / (CURVE_POINTS - 1)
	for i in CURVE_POINTS:
		out.append(curve[roundi(i * step)])
	return out


## Session results spread over HISTOGRAM_BINS equal bins: {min, max, counts}.
static func _histogram(sorted_nets: Array) -> Dictionary:
	var counts: Array = []
	counts.resize(HISTOGRAM_BINS)
	counts.fill(0)
	if sorted_nets.is_empty():
		return {"min": 0, "max": 0, "counts": counts}
	var low := float(sorted_nets[0])
	var high := float(sorted_nets[-1])
	var width := maxf(1.0, (high - low) / HISTOGRAM_BINS)
	for n in sorted_nets:
		var bin := clampi(int((float(n) - low) / width), 0, HISTOGRAM_BINS - 1)
		counts[bin] = int(counts[bin]) + 1
	return {"min": low, "max": high, "counts": counts}

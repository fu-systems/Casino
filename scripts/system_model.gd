class_name SystemModel
extends RefCounted
## The shape of a betting system in the Systems Lab packs, shared by roulette
## and craps: plain Dictionaries, so a system saves, exports and imports as
## JSON.
##
## A system is a flowchart of steps. Each step has a layout (the bets it
## makes, in units) and an ordered list of IF / THEN rules checked after
## every round — the first rule that matches runs its actions, and if none
## does the step's OTHERWISE actions run. Actions change the bets, the unit,
## two counters, or jump to another step.
##
## {version, game, name, notes,
##  settings: {bankroll, unit, table_min, table_max, rounds, stop_loss,
##             take_profit, sessions},
##  start: step id,
##  steps: [{id, name, layout: {position: units}, rules: [{when, then}],
##           otherwise: [action]}]}

const VERSION := 1
const CODE_PREFIX := "CASINO-SYS1:"

const DEFAULT_SETTINGS := {
	"bankroll": 1000, "unit": 5, "table_min": 1, "table_max": 500,
	"rounds": 200, "stop_loss": 0, "take_profit": 0, "sessions": 1000,
}
const LIMITS := {
	"bankroll": [10, 10000000], "unit": [1, 100000], "table_min": [1, 100000],
	"table_max": [1, 10000000], "rounds": [1, 100000], "stop_loss": [0, 10000000],
	"take_profit": [0, 10000000], "sessions": [1, 10000],
}

## Condition types, in the order the editor offers them.
const CONDITIONS := {
	"round": "The round's result",
	"wins": "A bet wins",
	"loses": "A bet loses",
	"group": "Several bets together",
	"event": "Something happens",
	"pattern": "A run of results",
	"compare": "A number (streak, bankroll…)",
	"always": "Always",
	"and": "All of these",
	"or": "Any of these",
	"not": "Not this",
}
const ACTIONS := {
	"bet": "Set a bet",
	"add_bet": "Add to / take from a bet",
	"clear_bets": "Clear all bets",
	"unit": "Change the unit",
	"goto": "Go to a step",
	"counter": "Change a counter",
	"sit_out": "Sit out rounds",
	"stop": "Stop the session",
	"odds": "Take odds (craps)",
	"press": "Press a bet (craps)",
	"regress": "Regress a bet (craps)",
}
const CRAPS_ONLY_ACTIONS := ["odds", "press", "regress"]
const GROUP_MODES := {"all": "all of", "any": "any of", "none": "none of",
	"exactly": "exactly", "at_least": "at least"}
const ROUND_RESULTS := {"won": "is won", "lost": "is lost", "push": "breaks even"}
const COMPARE_VARS := {
	"loss_streak": "loss streak", "win_streak": "win streak",
	"net": "session net ($)", "bankroll": "bankroll ($)", "unit": "unit (units)",
	"round": "rounds played", "step_rounds": "rounds in this step",
	"a": "counter A", "b": "counter B",
}
const OPS := [">=", ">", "==", "<=", "<"]
const OP_SIGNS := {">=": "≥", ">": ">", "==": "=", "<=": "≤", "<": "<"}
const UNIT_OPS := {"reset": "reset", "set": "set to", "add": "add", "multiply": "multiply by"}


# --- Games ---------------------------------------------------------------------------

## Positions you can bet on: [{key, label, group}].
static func positions(game: String) -> Array:
	if game == "craps":
		return CrapsSim.positions()
	return RouletteSim.positions()


## Things that can happen in a round, for "Something happens" and "A run of
## results": [[id, label]].
static func events(game: String) -> Array:
	if game == "craps":
		return CrapsSim.events()
	return RouletteSim.events()


static func position_label(game: String, key: String) -> String:
	for entry in positions(game):
		if entry.key == key:
			return entry.label
	for entry in events(game):
		if entry[0] == key:
			return entry[1]
	return key


static func make_adapter(game: String) -> RefCounted:
	if game == "craps":
		return CrapsSim.new()
	return RouletteSim.new()


## The numbers a rule can compare: the shared ones, plus the game's own.
static func compare_vars(game: String) -> Dictionary:
	var vars := COMPARE_VARS.duplicate()
	if game == "craps":
		vars.merge(CrapsSim.VARIABLES)
	return vars


static func game_name(game: String) -> String:
	return "Craps" if game == "craps" else "Roulette"


# --- Building ------------------------------------------------------------------------

static func new_system(game: String, name: String = "My system") -> Dictionary:
	return {
		"version": VERSION, "game": game, "name": name, "notes": "",
		"settings": DEFAULT_SETTINGS.duplicate(),
		"start": 0,
		"steps": [new_step(0, "Start")],
	}


static func new_step(id: int, name: String, layout: Dictionary = {}) -> Dictionary:
	return {"id": id, "name": name, "layout": layout.duplicate(), "rules": [], "otherwise": []}


static func step(system: Dictionary, id: int) -> Dictionary:
	for entry in system.steps:
		if int(entry.id) == id:
			return entry
	return {}


static func next_step_id(system: Dictionary) -> int:
	var top := -1
	for entry in system.steps:
		top = maxi(top, int(entry.id))
	return top + 1


# --- Describing ------------------------------------------------------------------------

static func describe_condition(cond: Dictionary, game: String) -> String:
	match String(cond.get("type", "")):
		"always":
			return "always"
		"round":
			return "the round %s" % ROUND_RESULTS.get(cond.get("result", "won"), "?")
		"wins":
			return "%s wins" % position_label(game, cond.get("pos", ""))
		"loses":
			return "%s loses" % position_label(game, cond.get("pos", ""))
		"group":
			var names := _names(game, cond.get("positions", []))
			var mode := String(cond.get("mode", "all"))
			if mode == "exactly" or mode == "at_least":
				return "%s %d of %s win" % [GROUP_MODES[mode], int(cond.get("n", 1)), names]
			return "%s %s win" % [GROUP_MODES.get(mode, mode), names]
		"event":
			return position_label(game, cond.get("event", ""))
		"pattern":
			var what := position_label(game, cond.get("what", ""))
			var n := int(cond.get("n", 1))
			if cond.get("mode", "hit") == "missed":
				return "no %s in the last %d rounds" % [what, n]
			return "%s in each of the last %d rounds" % [what, n]
		"compare":
			return "%s %s %s" % [compare_vars(game).get(cond.get("var", ""), "?"),
				OP_SIGNS.get(cond.get("op", ">="), "?"), _number(cond.get("value", 0))]
		"and", "or":
			var parts: PackedStringArray = []
			for item in cond.get("items", []):
				parts.append(describe_condition(item, game))
			if parts.is_empty():
				return "(nothing)"
			return "(" + (") %s (" % cond.type).join(parts) + ")"
		"not":
			return "not (%s)" % describe_condition(cond.get("item", {"type": "always"}), game)
	return "?"


static func describe_action(action: Dictionary, system: Dictionary) -> String:
	var game := String(system.get("game", "roulette"))
	var pos := position_label(game, action.get("pos", ""))
	match String(action.get("type", "")):
		"bet":
			var units := int(action.get("units", 1))
			return "take the bet off %s" % pos if units <= 0 else "bet %du on %s" % [units, pos]
		"add_bet":
			var units := int(action.get("units", 1))
			return "add %du to %s" % [units, pos] if units >= 0 else "take %du off %s" % [-units, pos]
		"clear_bets":
			return "clear all bets"
		"unit":
			var value: Variant = action.get("value", 1)
			match String(action.get("op", "reset")):
				"reset":
					return "reset the unit"
				"set":
					return "set the unit to %su" % _number(value)
				"add":
					return "raise the unit by %su" % _number(value) if float(value) >= 0 \
						else "lower the unit by %su" % _number(-float(value))
				"multiply":
					if is_equal_approx(float(value), 2.0):
						return "double the unit"
					if is_equal_approx(float(value), 0.5):
						return "halve the unit"
					return "multiply the unit by %s" % _number(value)
		"goto":
			var target := step(system, int(action.get("step", -1)))
			return "go to %s" % (target.name if not target.is_empty() else "a missing step")
		"counter":
			var which := String(action.get("which", "a")).to_upper()
			if action.get("op", "add") == "set":
				return "set counter %s to %s" % [which, _number(action.get("value", 0))]
			return "add %s to counter %s" % [_number(action.get("value", 1)), which]
		"sit_out":
			return "sit out %d round%s" % [int(action.get("rounds", 1)), "" if int(action.get("rounds", 1)) == 1 else "s"]
		"stop":
			return "stop the session"
		"odds":
			var mult := int(action.get("mult", 0))
			return "take max odds on %s" % pos if mult <= 0 else "take %dx odds on %s" % [mult, pos]
		"press":
			return "press %s (double it)" % pos
		"regress":
			return "regress %s (halve it)" % pos
	return "?"


static func describe_actions(actions: Array, system: Dictionary) -> String:
	if actions.is_empty():
		return "do nothing"
	var parts: PackedStringArray = []
	for action in actions:
		parts.append(describe_action(action, system))
	return ", then ".join(parts)


static func describe_layout(layout: Dictionary, game: String) -> String:
	if layout.is_empty():
		return "no bets — watching"
	var parts: PackedStringArray = []
	for key in layout:
		parts.append("%du %s" % [int(layout[key]), position_label(game, key)])
	return ", ".join(parts)


static func _names(game: String, keys: Array) -> String:
	var parts: PackedStringArray = []
	for key in keys:
		parts.append(position_label(game, key))
	return "{%s}" % ", ".join(parts)


static func _number(value: Variant) -> String:
	var f := float(value)
	if is_equal_approx(f, roundf(f)):
		return str(int(roundf(f)))
	return "%.2f" % f


# --- Checking --------------------------------------------------------------------------

## Problems worth telling the player about, as sentences. Empty means the
## system will run as written.
static func validate(system: Dictionary) -> Array:
	var problems: Array = []
	var steps: Array = system.get("steps", [])
	if steps.is_empty():
		return ["A system needs at least one step."]
	if step(system, int(system.get("start", -1))).is_empty():
		problems.append("The start step is missing.")

	var game := String(system.get("game", "roulette"))
	var known := {}
	for entry in positions(game):
		known[entry.key] = true

	var settings: Dictionary = system.get("settings", {})
	if int(settings.get("table_max", 1)) < int(settings.get("table_min", 1)):
		problems.append("The table maximum is below the minimum.")

	for entry in steps:
		for key in entry.layout:
			if not known.has(key):
				problems.append("%s bets on %s, which isn't a %s bet." % [entry.name, key, game_name(game)])
		for rule in entry.rules:
			for action in rule.then:
				_check_action(system, entry, action, game, problems)
		for action in entry.otherwise:
			_check_action(system, entry, action, game, problems)

	var reached := reachable(system)
	for entry in steps:
		if not reached.has(int(entry.id)):
			problems.append("Nothing ever goes to %s." % entry.name)
		elif entry.layout.is_empty() and not _ever_leaves(entry):
			problems.append("%s never bets and never moves on." % entry.name)
	return problems


static func _check_action(system: Dictionary, from: Dictionary, action: Dictionary, game: String, problems: Array) -> void:
	var kind := String(action.get("type", ""))
	if kind == "goto" and step(system, int(action.get("step", -1))).is_empty():
		problems.append("%s goes to a step that no longer exists." % from.name)
	if kind in CRAPS_ONLY_ACTIONS and game != "craps":
		problems.append("%s uses a craps-only action." % from.name)


## Steps reachable from the start by following "go to" actions.
static func reachable(system: Dictionary) -> Dictionary:
	var seen := {}
	var queue: Array = [int(system.get("start", 0))]
	while not queue.is_empty():
		var id: int = queue.pop_front()
		if seen.has(id):
			continue
		var entry := step(system, id)
		if entry.is_empty():
			continue
		seen[id] = true
		for target in targets(entry):
			queue.append(target)
	return seen


## The steps a step can jump to: [step id], in rule order, otherwise last.
static func targets(entry: Dictionary) -> Array:
	var out: Array = []
	for rule in entry.rules:
		for action in rule.then:
			if action.get("type", "") == "goto":
				out.append(int(action.step))
	for action in entry.otherwise:
		if action.get("type", "") == "goto":
			out.append(int(action.step))
	return out


static func _ever_leaves(entry: Dictionary) -> bool:
	for rule in entry.rules:
		for action in rule.then:
			if action.get("type", "") in ["goto", "stop", "bet", "add_bet"]:
				return true
	for action in entry.otherwise:
		if action.get("type", "") in ["goto", "stop", "bet", "add_bet"]:
			return true
	return false


# --- Saving and sharing -------------------------------------------------------------------

## A copy with every setting present and in range, safe to run.
static func normalised(system: Dictionary) -> Dictionary:
	var out: Dictionary = system.duplicate(true)
	var settings: Dictionary = DEFAULT_SETTINGS.duplicate()
	settings.merge(out.get("settings", {}), true)
	for key in LIMITS:
		settings[key] = clampi(int(settings[key]), LIMITS[key][0], LIMITS[key][1])
	out.settings = settings
	for entry in out.steps:
		entry.id = int(entry.id)
		var layout := {}
		for key in entry.get("layout", {}):
			layout[String(key)] = int(entry.layout[key])
		entry.layout = layout
		if not entry.has("rules"):
			entry.rules = []
		if not entry.has("otherwise"):
			entry.otherwise = []
	out.start = int(out.get("start", 0))
	return out


## A line of text that carries a whole system, for sharing.
static func export_code(system: Dictionary) -> String:
	return CODE_PREFIX + Marshalls.utf8_to_base64(JSON.stringify(system))


## The system in a shared line of text, or {} if it isn't one.
static func import_code(text: String) -> Dictionary:
	var trimmed := text.strip_edges()
	if not trimmed.begins_with(CODE_PREFIX):
		return {}
	var payload := trimmed.substr(CODE_PREFIX.length())
	# Checked first, so pasting a damaged code fails quietly instead of
	# tripping the decoder's own errors.
	var base64 := RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$")
	if payload.length() % 4 != 0 or base64.search(payload) == null:
		return {}
	var parser := JSON.new()
	if parser.parse(Marshalls.base64_to_utf8(payload)) != OK or not parser.data is Dictionary:
		return {}
	var system: Dictionary = parser.data
	if int(system.get("version", 0)) != VERSION or not system.has("steps") \
			or not String(system.get("game", "")) in ["roulette", "craps"]:
		return {}
	return normalised(system)

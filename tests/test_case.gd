class_name CasinoTest
extends Node
## Base for the game rule suites.
##
## Each suite overrides `run()` and reports through `check`/`note`. The suites
## drive the real scenes rather than reimplementing the rules, so a suite
## passing means the shipped game behaves, not just a copy of it.

var failures := 0
var suite_name := "suite"


func fail(message: String) -> void:
	failures += 1
	print("  FAIL: ", message)


func check(condition: bool, message: String) -> void:
	if not condition:
		fail(message)


func note(message: String) -> void:
	print("  ok: ", message)


## Overridden by each suite. Always a coroutine so the runner can await it.
func run() -> void:
	await get_tree().process_frame


## Waits for `predicate` to hold, so tests can drive scenes that animate.
func settle(predicate: Callable, limit: int = 30000, what: String = "condition") -> void:
	for i in limit:
		if predicate.call():
			return
		await get_tree().process_frame
	fail("timed out after %d frames waiting for %s" % [limit, what])


func frames(count: int = 1) -> void:
	for i in count:
		await get_tree().process_frame

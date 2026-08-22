extends Node
## Runs every rule suite and the layout guard, and fails the process if any
## check fails. CI runs this; so can you:
##
##   godot --headless --path . tests/run_all.tscn

const SUITES := [
	"res://tests/layout_fits.gd",
	"res://tests/blackjack_rules.gd",
	"res://tests/roulette_rules.gd",
	"res://tests/craps_rules.gd",
	"res://tests/baccarat_rules.gd",
]


func _ready() -> void:
	# Animations are driven by real timers; run them fast so the suite doesn't
	# take minutes.
	Engine.time_scale = 60.0
	var total := 0
	var ran := 0

	for path in SUITES:
		if not ResourceLoader.exists(path):
			print("SKIP %s (not present)" % path)
			continue
		var suite: CasinoTest = load(path).new()
		suite.suite_name = path.get_file().get_basename()
		add_child(suite)
		print("== %s ==" % suite.suite_name)
		await suite.run()
		if suite.failures > 0:
			print("== %s: %d FAILED ==" % [suite.suite_name, suite.failures])
		total += suite.failures
		ran += 1
		suite.queue_free()
		await get_tree().process_frame

	Engine.time_scale = 1.0
	if total == 0:
		print("=== ALL SUITES PASSED (%d) ===" % ran)
	else:
		print("=== %d CHECK(S) FAILED ACROSS %d SUITES ===" % [total, ran])
	get_tree().quit(1 if total > 0 else 0)

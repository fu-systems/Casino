extends CasinoTest
## Persistence: what survives a restart, and that the suites never touch the
## real save file.


func run() -> void:
	_test_suites_run_in_memory()
	_test_round_trip()
	_test_bank_persists()
	await _test_notice_shows_once()
	await _test_about_lists_help()


func _test_suites_run_in_memory() -> void:
	check(not SaveData.enabled, "the runner must detach SaveData from disk before any suite runs")
	check(Bank.balance == Bank.START_BALANCE,
		"the runner must start from a fresh bankroll, got %d" % Bank.balance)
	note("suites run against an in-memory save and a fresh bankroll")


## A real ConfigFile write and read, to a scratch path rather than the save.
func _test_round_trip() -> void:
	var path := "user://save_rules_scratch.cfg"
	var out := ConfigFile.new()
	out.set_value("bank", "balance", 4321)
	out.set_value("notice", "accepted", 1)
	out.set_value("store", "owned", ["roulette_lab"])
	out.set_value("scores", "blitz", [{"score": 90, "date": "2026-10-19"}])
	check(out.save(path) == OK, "couldn't write the scratch save")

	var back := ConfigFile.new()
	check(back.load(path) == OK, "couldn't read the scratch save back")
	check(int(back.get_value("bank", "balance", 0)) == 4321, "the balance should round-trip")
	check(int(back.get_value("notice", "accepted", 0)) == 1, "the notice flag should round-trip")
	check(back.get_value("store", "owned", []) == ["roulette_lab"], "owned products should round-trip")
	var scores: Array = back.get_value("scores", "blitz", [])
	check(scores.size() == 1 and int(scores[0].score) == 90, "high scores should round-trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	note("balance, notice, purchases and scores round-trip through a ConfigFile")


func _test_bank_persists() -> void:
	Bank.withdraw(250)
	check(int(SaveData.get_value("bank", "balance", -1)) == Bank.START_BALANCE - 250,
		"a withdrawal should be written to the save straight away")
	Bank.deposit(100)
	check(int(SaveData.get_value("bank", "balance", -1)) == Bank.START_BALANCE - 150,
		"a deposit should be written to the save straight away")

	# A fresh Bank reads back what the last one saved.
	var reborn: Node = load("res://scripts/bank.gd").new()
	add_child(reborn)
	check(reborn.balance == Bank.START_BALANCE - 150,
		"a restarted bank should load the saved balance, got %d" % reborn.balance)
	reborn.queue_free()

	# A corrupt value falls back to a fresh bankroll instead of a weird one.
	SaveData.set_value("bank", "balance", "lots")
	var fallback: Node = load("res://scripts/bank.gd").new()
	add_child(fallback)
	check(fallback.balance == Bank.START_BALANCE, "a corrupt balance should fall back to the start")
	fallback.queue_free()

	Bank.reset()
	check(int(SaveData.get_value("bank", "balance", -1)) == Bank.START_BALANCE,
		"a reset should be saved too")
	note("the bankroll is saved on every change and reloads on restart")


func _test_notice_shows_once() -> void:
	SaveData.erase_value("notice", "accepted")
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await frames(2)
	var notice: Modal = menu.get_node_or_null("Notice")
	check(notice != null, "the play-money notice should show on first launch")
	if notice != null:
		var text := _all_text(notice)
		check("18" in text, "the notice should say the game is for adults")
		check("worth nothing" in text and "cashed out" in text,
			"the notice should say chips have no value and can't be cashed out")
		notice.actions.get_child(0).emit_signal("pressed")
		await frames(2)
		check(menu.get_node_or_null("Notice") == null, "accepting should dismiss the notice")
	check(int(SaveData.get_value("notice", "accepted", 0)) == menu.NOTICE_VERSION,
		"accepting should be remembered")
	menu.queue_free()
	await frames()

	var again: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(again)
	await frames(2)
	check(again.get_node_or_null("Notice") == null, "the notice should not show again once accepted")
	check(again.FOOTER in _all_text(again), "the lobby should always carry the play-money footer")
	again.queue_free()
	await frames()
	note("the 18+ play-money notice shows once, and the footer always")


func _test_about_lists_help() -> void:
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await frames(2)
	var about: Modal = menu._show_about()
	await frames()
	var text := _all_text(about)
	check("collects no personal data" in text, "About should carry the privacy statement")
	for link in menu.HELP_LINKS:
		check(link[0] in text, "About should offer %s" % link[0])
	menu.queue_free()
	await frames()
	note("About carries the privacy line and the help links")


## Every Label and Button caption under `node`, joined, for text assertions.
func _all_text(node: Node) -> String:
	var parts: PackedStringArray = []
	if node is Label:
		parts.append(node.text)
	elif node is Button:
		parts.append(node.text)
	for child in node.get_children():
		parts.append(_all_text(child))
	return " ".join(parts)

extends Control
## Extras: the optional packs, the free unlocks, and the tip jar.
##
## Everything here is stated plainly — what a pack contains, its price, and
## whether you own it. No countdowns, no "best value" badges, no discounts
## that were never real, and nothing that buys chips.

const COLOR_FELT := Color(0.04, 0.2, 0.12)
const COLOR_CARD := Color(0.03, 0.15, 0.09)
const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_MUTED := Color(0.78, 0.85, 0.78)
const COLOR_WIN := Color(0.5, 0.92, 0.55)
const COLOR_BUY := Color(0.16, 0.38, 0.24)
const CARD_WIDTH := 1060

var list: VBoxContainer
var scroll: ScrollContainer
var message_label: Label
var status_label: Label
var restore_button: Button
## Card per product id, for focusing and tests.
var cards := {}


func _ready() -> void:
	_build_ui()
	_rebuild()
	Store.purchases_changed.connect(_rebuild)
	Store.prices_changed.connect(_rebuild)
	Store.store_message.connect(_set_message.bind(COLOR_GOLD))
	Store.tip_thanked.connect(_on_tip_thanked)
	if Store.focus_id != "":
		_focus.call_deferred(Store.focus_id)
		Store.focus_id = ""


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_FELT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := SafeArea.create(20)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var top := HBoxContainer.new()
	column.add_child(top)
	var back := Button.new()
	back.text = "< Back"
	back.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(back, Color(0.09, 0.2, 0.13), 18, 14, 8)
	back.pressed.connect(_on_back_pressed)
	top.add_child(back)
	var title := Label.new()
	title.text = "EXTRAS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	top.add_child(title)
	# Balances the Back button so the title stays centred.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(back.get_combined_minimum_size().x, 0)
	top.add_child(spacer)

	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	list.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	centre.add_child(list)

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_font_size_override("font_size", 18)
	column.add_child(message_label)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	column.add_child(bottom)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", COLOR_MUTED)
	bottom.add_child(status_label)
	restore_button = Button.new()
	restore_button.text = "Restore Purchases"
	restore_button.focus_mode = Control.FOCUS_NONE
	CasinoUI.style_button(restore_button, Color(0.18, 0.24, 0.3), 17, 14, 8)
	restore_button.pressed.connect(Store.restore)
	bottom.add_child(restore_button)


## Rebuilt whole whenever ownership or prices change; it's a short list.
func _rebuild() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	cards.clear()

	if not Store.PACKS.is_empty():
		_add_header("PACKS", "One-time purchases. Buy once, keep forever, restore on any device.")
		for entry in Store.PACKS:
			_add_card(entry, false)

	_add_header("FREE", "No purchase needed — just tap to switch it on.")
	for entry in Store.FREE_UNLOCKS:
		_add_card(entry, true)

	_add_tip_jar()

	status_label.text = Store.status_text()
	restore_button.visible = Store.backend != Store.Backend.UNLOCKED


func _add_header(text: String, sub: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", COLOR_GOLD)
	list.add_child(label)
	var hint := Label.new()
	hint.text = sub
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", COLOR_MUTED)
	list.add_child(hint)


func _add_card(entry: Dictionary, free: bool) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", CasinoUI.panel_style(COLOR_CARD, Color(0.2, 0.35, 0.25), 12, 14))
	list.add_child(card)
	cards[entry.id] = card

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	card.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = "%s   ·   %s" % [entry.title, entry.game]
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	text.add_child(name_label)
	for line in entry.lines:
		var bullet := Label.new()
		bullet.text = "•  " + line
		bullet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bullet.add_theme_font_size_override("font_size", 16)
		bullet.add_theme_color_override("font_color", COLOR_MUTED)
		text.add_child(bullet)

	var button := Button.new()
	button.name = "Action"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(200, 54)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var owned := Store.owns(entry.id)
	if owned:
		button.text = "Open" if entry.has("scene") else "Owned"
		button.disabled = not entry.has("scene")
		if entry.has("scene"):
			button.pressed.connect(_open.bind(entry))
	elif free:
		button.text = "Unlock — Free"
		button.pressed.connect(_unlock_free.bind(entry.id))
	else:
		var price := Store.price(entry.id)
		button.text = "Buy  %s" % price if price != "" else "Buy"
		button.disabled = not Store.can_buy(entry.id)
		button.pressed.connect(Store.buy.bind(entry.id))
	CasinoUI.style_button(button, COLOR_WIN.darkened(0.6) if owned else COLOR_BUY, 19, 14, 8, 10, COLOR_GOLD)
	row.add_child(button)


func _add_tip_jar() -> void:
	_add_header("SUPPORT THE DEVELOPER",
		"Casino is free and stays free. Tips are optional, change nothing in the game, and are hugely appreciated.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	list.add_child(row)
	for entry in Store.TIPS:
		var button := Button.new()
		button.name = entry.id
		var price := Store.price(entry.id)
		button.text = entry.title if price == "" else "%s  %s" % [entry.title, price]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(240, 54)
		button.disabled = not Store.can_buy(entry.id)
		CasinoUI.style_button(button, Color(0.4, 0.3, 0.1), 18, 14, 8, 10)
		button.pressed.connect(Store.buy.bind(entry.id))
		row.add_child(button)
	cards["tips"] = row


func _unlock_free(id: String) -> void:
	Store.unlock_free(id)
	_set_message("%s is on. Find it in %s." % [Store.pack(id).title, Store.pack(id).game], COLOR_WIN)


func _on_tip_thanked(_id: String) -> void:
	_set_message("Thank you — that genuinely helps keep Casino going.", COLOR_WIN)


## Scrolls to a card and outlines it in gold, for "tap a locked feature".
func _focus(id: String) -> void:
	if not cards.has(id):
		return
	var card: Control = cards[id]
	if card is PanelContainer:
		card.add_theme_stylebox_override("panel", CasinoUI.panel_style(COLOR_CARD, COLOR_GOLD, 12, 14))
	scroll.ensure_control_visible(card)


func _open(entry: Dictionary) -> void:
	Store.return_scene = "res://scenes/main_menu.tscn"
	# One lab scene serves both games; tell it which one this is.
	if entry.has("lab_game"):
		SystemLab.open_game = entry.lab_game
	get_tree().change_scene_to_file(entry.scene)


func _on_back_pressed() -> void:
	var target := Store.return_scene
	Store.return_scene = "res://scenes/main_menu.tscn"
	get_tree().change_scene_to_file(target)


func _set_message(text: String, colour: Color) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", colour)

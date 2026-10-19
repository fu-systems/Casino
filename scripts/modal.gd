class_name Modal
extends Control
## A dimmed full-screen overlay holding one centred panel — the play-money
## notice, the About box, purchase prompts and run summaries all use it.
##
## The dim layer stops clicks reaching the table underneath, and the panel
## scrolls, so a long body can never push its own buttons off a short screen.

signal closed

const COLOR_DIM := Color(0, 0, 0, 0.72)
const COLOR_PANEL := Color(0.04, 0.2, 0.11)
const COLOR_GOLD := Color(0.94, 0.78, 0.29)
const COLOR_TEXT := Color(0.92, 0.94, 0.9)
## Most a modal's body may take before it scrolls, leaving room for the title,
## the buttons and the margins on a 720px-tall screen.
const MAX_BODY_HEIGHT := 440

## Body widgets go here; `add_text` and `add_button` are shortcuts.
var content: VBoxContainer
## Buttons along the bottom of the panel.
var actions: HBoxContainer

var _scroll: ScrollContainer


## Builds a modal and adds it to `parent`. `width` is the panel's width in
## design pixels; the height follows the content up to the screen.
static func open(parent: Node, title: String, width: int = 640) -> Modal:
	var modal := Modal.new()
	modal._build(title, width)
	parent.add_child(modal)
	return modal


func _build(title: String, width: int) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = COLOR_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var margin := SafeArea.create(24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_stylebox_override("panel", CasinoUI.panel_style(COLOR_PANEL, COLOR_GOLD, 14, 20))
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", COLOR_GOLD)
	column.add_child(heading)

	# Capped so the panel never outgrows a 720px-tall screen; anything longer
	# scrolls inside it.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)

	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)

	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)

	content.resized.connect(_fit_scroll)


## The scroll area reports almost no minimum height of its own, so it is sized
## to its content by hand, up to the cap.
func _fit_scroll() -> void:
	_scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, MAX_BODY_HEIGHT)


## A wrapped paragraph in the body.
func add_text(text: String, font_size: int = 18, colour: Color = COLOR_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(120, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	content.add_child(label)
	return label


## A button along the bottom. `handler` runs on press; pass `closes = true`
## to also dismiss the modal afterwards.
func add_button(text: String, colour: Color, handler: Callable = Callable(),
		closes: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(160, 52)
	CasinoUI.style_button(button, colour, 20, 18, 10, 10, COLOR_GOLD)
	button.pressed.connect(func() -> void:
		if handler.is_valid():
			handler.call()
		if closes:
			close())
	actions.add_child(button)
	return button


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()

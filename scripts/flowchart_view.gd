class_name FlowchartView
extends Control
## A system drawn as a flowchart: each step a box (its name and its bets),
## each "go to" an arrow labelled with the rule that takes it. Columns follow
## the distance from the start, so a ladder like Fibonacci reads left to
## right. Tap a box to edit that step.

signal step_pressed(id: int)

const BOX := Vector2(230, 92)
const GAP := Vector2(200, 120)
const MARGIN := Vector2(90, 40)
const COLOR_BOX := Color(0.05, 0.22, 0.13)
const COLOR_START := Color(0.18, 0.34, 0.2)
const COLOR_EDGE := Color(0.94, 0.78, 0.29)
const COLOR_TEXT := Color(0.94, 0.95, 0.92)
const COLOR_MUTED := Color(0.72, 0.8, 0.74)
const COLOR_ARROW := Color(0.85, 0.88, 0.85, 0.85)
const COLOR_BACK_ARROW := Color(0.6, 0.78, 0.95, 0.85)
## Arrow labels are cut to this many characters; the step editor has the rest.
const LABEL_CHARS := 28
const COLOR_LABEL_BG := Color(0.02, 0.12, 0.07, 0.92)

var system: Dictionary = {}
var _boxes := {}
## Arrow labels are drawn last, over the boxes: [position, text, colour].
var _labels: Array = []


func show_system(new_system: Dictionary) -> void:
	system = new_system
	_layout()
	queue_redraw()


func _layout() -> void:
	_boxes.clear()
	if system.is_empty():
		return
	# Columns by breadth-first distance from the start; anything unreachable
	# goes in a column of its own at the end.
	var column := {}
	var queue: Array = [int(system.start)]
	column[int(system.start)] = 0
	while not queue.is_empty():
		var id: int = queue.pop_front()
		var entry := SystemModel.step(system, id)
		for target in SystemModel.targets(entry):
			if not column.has(target) and not SystemModel.step(system, target).is_empty():
				column[target] = int(column[id]) + 1
				queue.append(target)
	var last := 0
	for id in column:
		last = maxi(last, int(column[id]))
	var rows := {}
	for entry in system.steps:
		var id := int(entry.id)
		if not column.has(id):
			column[id] = last + 1
		var col := int(column[id])
		var row := int(rows.get(col, 0))
		rows[col] = row + 1
		_boxes[id] = Rect2(MARGIN + Vector2(col * (BOX.x + GAP.x), row * (BOX.y + GAP.y) + 30), BOX)
	var size_needed := Vector2.ZERO
	for id in _boxes:
		size_needed = size_needed.max(_boxes[id].end)
	custom_minimum_size = size_needed + MARGIN


func _gui_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if not tapped:
		return
	for id in _boxes:
		if _boxes[id].has_point(event.position):
			step_pressed.emit(int(id))
			accept_event()
			return


func _draw() -> void:
	if system.is_empty():
		return
	var font := ThemeDB.fallback_font
	var game := String(system.game)
	_labels.clear()

	# Arrows first, so the boxes sit on top of them.
	for entry in system.steps:
		var from_id := int(entry.id)
		var lane := 0
		for rule in entry.rules:
			for action in rule.then:
				if action.get("type", "") == "goto":
					_arrow(from_id, int(action.step), "IF " + SystemModel.describe_condition(rule.when, game), lane, font)
					lane += 1
		for action in entry.otherwise:
			if action.get("type", "") == "goto":
				_arrow(from_id, int(action.step), "otherwise", lane, font)
				lane += 1

	for entry in system.steps:
		var id := int(entry.id)
		if not _boxes.has(id):
			continue
		var box: Rect2 = _boxes[id]
		var start := id == int(system.start)
		draw_rect(box, COLOR_START if start else COLOR_BOX)
		draw_rect(box, COLOR_EDGE, false, 2.0)
		draw_string(font, box.position + Vector2(10, 26), _cut(entry.name, 22),
			HORIZONTAL_ALIGNMENT_LEFT, BOX.x - 20, 18, COLOR_TEXT)
		draw_string(font, box.position + Vector2(10, 50), _cut(SystemModel.describe_layout(entry.layout, game), 30),
			HORIZONTAL_ALIGNMENT_LEFT, BOX.x - 20, 14, COLOR_MUTED)
		var count: int = entry.rules.size()
		draw_string(font, box.position + Vector2(10, 74), "%d rule%s%s" % [count, "" if count == 1 else "s",
			", otherwise…" if not entry.otherwise.is_empty() else ""],
			HORIZONTAL_ALIGNMENT_LEFT, BOX.x - 20, 13, COLOR_MUTED)
		if start:
			var mark := box.position + Vector2(-70, BOX.y / 2 + 5)
			draw_string(font, mark, "START", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_EDGE)
			_head(box.position + Vector2(-6, BOX.y / 2), Vector2.RIGHT, COLOR_EDGE)
			draw_line(box.position + Vector2(-20, BOX.y / 2), box.position + Vector2(-6, BOX.y / 2), COLOR_EDGE, 2.0)

	# Labels last, on a backing, so no box or line can cover one.
	for entry in _labels:
		var width := font.get_string_size(entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10
		var at: Vector2 = entry[0]
		draw_rect(Rect2(at - Vector2(width / 2, 13), Vector2(width, 18)), COLOR_LABEL_BG)
		draw_string(font, at - Vector2(width / 2 - 5, 0), entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, entry[2])


func _arrow(from_id: int, to_id: int, label: String, lane: int, font: Font) -> void:
	if not _boxes.has(from_id) or not _boxes.has(to_id):
		return
	var a: Rect2 = _boxes[from_id]
	var b: Rect2 = _boxes[to_id]
	var text := _cut(label, LABEL_CHARS)
	if from_id == to_id:
		# A loop back to the same step: an arc over the box's top edge.
		var left := a.position + Vector2(BOX.x * 0.3, 0)
		var right := a.position + Vector2(BOX.x * 0.7, 0)
		var lift := 30.0 + lane * 22.0
		var points := _bezier(right, right + Vector2(10, -lift), left + Vector2(-10, -lift), left)
		draw_polyline(points, COLOR_BACK_ARROW, 2.0, true)
		_head(left, Vector2.DOWN, COLOR_BACK_ARROW)
		_labels.append([a.position + Vector2(BOX.x / 2, -lift * 0.75 - 2), text, COLOR_BACK_ARROW])
		return
	var forward := b.position.x > a.position.x
	var colour := COLOR_ARROW if forward else COLOR_BACK_ARROW
	var start: Vector2
	var finish: Vector2
	var points: PackedVector2Array
	var offset := lane * 12.0
	if forward:
		start = Vector2(a.end.x, a.position.y + 24 + offset)
		finish = Vector2(b.position.x, b.position.y + BOX.y / 2)
		var bend := (finish.x - start.x) * 0.5
		points = _bezier(start, start + Vector2(bend, 0), finish - Vector2(bend, 0), finish)
		_head(finish, Vector2.RIGHT, colour)
	else:
		# Backwards (or straight down a column): loop underneath, each lane
		# and each source column a little deeper so neighbours don't overlap.
		start = Vector2(a.position.x + BOX.x * 0.6 - offset, a.end.y)
		finish = Vector2(b.position.x + BOX.x * 0.4 + offset, b.end.y)
		var column := int(a.position.x / (BOX.x + GAP.x))
		var depth := 34.0 + lane * 30.0 + (column % 3) * 24.0
		var low := maxf(a.end.y, b.end.y) + depth
		points = _bezier(start, Vector2(start.x, low), Vector2(finish.x, low), finish)
		_head(finish, Vector2.UP, colour)
	draw_polyline(points, colour, 2.0, true)
	var middle: Vector2 = points[points.size() / 2]
	_labels.append([middle + Vector2(0, -4 if forward else 14), text, colour])


func _head(tip: Vector2, direction: Vector2, colour: Color) -> void:
	var back := -direction * 10.0
	var side := Vector2(-direction.y, direction.x) * 6.0
	draw_colored_polygon(PackedVector2Array([tip, tip + back + side, tip + back - side]), colour)


func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 21:
		var t := i / 20.0
		var u := 1.0 - t
		out.append(u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3)
	return out


static func _cut(text: String, chars: int) -> String:
	return text if text.length() <= chars else text.substr(0, chars - 1) + "…"

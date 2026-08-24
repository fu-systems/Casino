class_name CrapsTable
extends Control
## The craps felt: one painted picture, plus the geometry of every betting
## area on it.
##
## The layout follows a real table's, because that is the point of it — the
## point boxes across the top with the don't come box at their end, the come
## band beneath, the field, and the pass line hooking around the outer
## corner with don't pass running parallel just inside it. The stickman's
## proposition box sits to the side.
##
## Geometry is recomputed from whatever rect the container gives this node,
## so the scene's layout minimum is one deliberate number rather than
## something that emerges from a tree of nested containers.
##
## Areas are polygons rather than rectangles: the pass line curves, and Big
## 6/8 splits on the diagonal. Each also carries a *chip spot* — where chips
## physically sit on a real table, which is not the centre of the area.
## Place chips sit on the bottom line of a point box, come chips inside it,
## don't come chips in the strip above, and odds heeled beside their flat
## bet. Getting those right is what makes a glance at the table readable.

const POINTS := [4, 5, 6, 8, 9, 10]
## Casinos spell the six and nine out, so they can't be misread upside down
## across the table.
const BOX_NAMES := {4: "4", 5: "5", 6: "SIX", 8: "8", 9: "NINE", 10: "TEN"}

const PROP_W := 292.0
const PROP_GAP := 12.0
const PASS_T := 34.0
const DONT_T := 26.0
const BAND_GAP := 4.0
const CORNER_R := 58.0
const ROW_GAP := 4.0
const ARC_STEPS := 14

const FELT := Color(0.055, 0.26, 0.145)
const FELT_DEEP := Color(0.04, 0.19, 0.11)
const LINE := Color(0.93, 0.92, 0.86)
const LINE_DIM := Color(0.93, 0.92, 0.86, 0.5)
const TEXT := Color(0.97, 0.96, 0.92)
const GOLD := Color(0.94, 0.78, 0.29)
const RED := Color(0.68, 0.14, 0.16)
const EDGE_TEXT := Color(0.98, 0.83, 0.4)

## Raised once `areas` holds fresh geometry. The buttons layered over the
## felt copy from it, and `resized` fires independently of the resize
## notification that rebuilds — listening to the wrong one hands them the
## previous layout's polygons.
signal geometry_changed

## key -> {"poly": PackedVector2Array, "chip": Vector2, "sub": bool}
var areas := {}
## key -> {"label": String, "pays": String, "edge": String}, set by the game
## so the printed price and the paid price come from one constant.
var text := {}

## The point, or 0 for a come-out roll. Moves the ON/OFF puck.
var point := 0:
	set(value):
		point = value
		queue_redraw()

## Real tables print no house edge anywhere. This puts it back on request.
var edges_shown := false:
	set(value):
		edges_shown = value
		queue_redraw()

## Numbers currently carrying a come or don't come bet. While a bet sits on
## a number, its box grows a little take-odds (or lay-odds) spot, since that
## is the one thing a player can still do to a travelled bet.
var come_odds_open: Array = []
var dont_odds_open: Array = []


func set_odds_open(come_numbers: Array, dont_numbers: Array) -> void:
	if come_numbers == come_odds_open and dont_numbers == dont_odds_open:
		return
	come_odds_open = come_numbers
	dont_odds_open = dont_numbers
	queue_redraw()

var _rows := {}


func _init() -> void:
	custom_minimum_size = Vector2(1080, 320)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		rebuild()


func set_text(key: String, label: String, pays: String, edge: String) -> void:
	text[key] = {"label": label, "pays": pays, "edge": edge}


# --- geometry ----------------------------------------------------------------

func rebuild() -> void:
	areas.clear()
	_rows.clear()
	if size.x < 200.0 or size.y < 120.0:
		return

	var table_w: float = size.x - PROP_W - PROP_GAP
	# The two bands take the bottom; everything else stacks above them.
	var bands: float = PASS_T + BAND_GAP + DONT_T
	var content_bottom: float = size.y - bands - 6.0
	var usable: float = content_bottom - 2.0 * ROW_GAP
	# Come is one word in a box, so it takes a share of a short screen but
	# never balloons on a tall one — the surplus is worth far more to the
	# point boxes, where the chips actually go.
	var come_h: float = minf(usable * 0.23, 112.0)
	var box_h: float = (usable - come_h) * 0.55
	var field_h: float = usable - box_h - come_h

	var box_top := 0.0
	var come_top: float = box_top + box_h + ROW_GAP
	var field_top: float = come_top + come_h + ROW_GAP

	_build_boxes(Rect2(0, box_top, table_w, box_h))
	_rect_area("come", Rect2(0, come_top, table_w, come_h), Vector2(0.5, 0.66))

	# The hook arms run up the outer end beside the field, so the field row
	# starts inboard of them.
	var arm: float = PASS_T + BAND_GAP + DONT_T + 6.0
	var field_w: float = (table_w - arm) * 0.72
	_rect_area("field", Rect2(arm, field_top, field_w, field_h), Vector2(0.5, 0.72))
	_build_big(Rect2(arm + field_w + ROW_GAP, field_top,
		table_w - arm - field_w - ROW_GAP, field_h))

	# Pass line outermost, don't pass concentric just inside it.
	_band_area("pass", field_top, 0.0, table_w, size.y, PASS_T, CORNER_R)
	var inset: float = PASS_T + BAND_GAP
	_band_area("dont_pass", field_top, inset, table_w, size.y - inset, DONT_T, CORNER_R - inset)
	# Odds are laid behind the line bet, so they share its band and differ
	# only in where the chips sit.
	_odds_behind("pass_odds", "pass", 0.72, PASS_T)
	_odds_behind("dont_pass_odds", "dont_pass", 0.72, DONT_T)

	_build_props(Rect2(table_w + PROP_GAP, 0, PROP_W, size.y))
	queue_redraw()
	geometry_changed.emit()


## A rectangular area. `chip` is a normalised position inside it.
func _rect_area(key: String, rect: Rect2, chip: Vector2, sub: bool = false) -> void:
	areas[key] = {
		"sub": sub,
		"poly": PackedVector2Array([
			rect.position,
			rect.position + Vector2(rect.size.x, 0),
			rect.end,
			rect.position + Vector2(0, rect.size.y)]),
		"chip": rect.position + rect.size * chip,
	}
	_rows[key] = rect


## Each point box stacks everything that can ride on that number, the way
## chips stack on a real one: don't come and its lay in the strip above the
## number, come and its odds in the body, place on the bottom line.
func _build_boxes(rect: Rect2) -> void:
	var cell: float = (rect.size.x - 6.0 * ROW_GAP) / 7.0
	_rect_area("dont_come", Rect2(rect.position.x, rect.position.y, cell, rect.size.y),
		Vector2(0.5, 0.7))

	var strip: float = maxf(18.0, rect.size.y * 0.19)
	var place_h: float = maxf(20.0, rect.size.y * 0.21)
	for i in POINTS.size():
		var number: int = POINTS[i]
		var x: float = rect.position.x + (i + 1) * (cell + ROW_GAP)
		var body_top: float = rect.position.y + strip
		var body_h: float = rect.size.y - strip - place_h
		var split: float = cell * 0.55

		_rect_area("dont_come_%d" % number,
			Rect2(x, rect.position.y, split, strip), Vector2(0.5, 0.5), true)
		_rect_area("dont_come_odds_%d" % number,
			Rect2(x + split, rect.position.y, cell - split, strip), Vector2(0.5, 0.5), true)
		_rect_area("come_%d" % number,
			Rect2(x, body_top, split, body_h), Vector2(0.4, 0.76), true)
		_rect_area("come_odds_%d" % number,
			Rect2(x + split, body_top, cell - split, body_h), Vector2(0.58, 0.82), true)
		_rect_area("place_%d" % number,
			Rect2(x, body_top + body_h, cell, place_h), Vector2(0.72, 0.5), true)
		_rows["box_%d" % number] = Rect2(x, rect.position.y, cell, rect.size.y)


## Big 6 and Big 8 share a square split corner to corner, as printed.
func _build_big(rect: Rect2) -> void:
	var a := rect.position
	var b := rect.position + Vector2(rect.size.x, 0)
	var c := rect.end
	var d := rect.position + Vector2(0, rect.size.y)
	areas["big_6"] = {
		"poly": PackedVector2Array([a, b, d]),
		"chip": a + Vector2(rect.size.x * 0.28, rect.size.y * 0.4),
	}
	areas["big_8"] = {
		"poly": PackedVector2Array([b, c, d]),
		"chip": a + Vector2(rect.size.x * 0.72, rect.size.y * 0.66),
	}
	_rows["big"] = rect


## An L-shaped band: down the outer arm, round the corner, along the bottom.
## Traced outer edge forward then inner edge backward, so it stays a simple
## polygon that `Geometry2D.is_point_in_polygon` handles exactly.
func _band_area(key: String, top: float, left: float, right: float,
		bottom: float, thickness: float, radius: float) -> void:
	radius = maxf(radius, thickness + 2.0)
	var centre := Vector2(left + radius, bottom - radius)
	var points := PackedVector2Array()
	points.append(Vector2(left, top))
	points.append_array(_arc(centre, radius))
	points.append(Vector2(right, bottom))
	points.append(Vector2(right, bottom - thickness))
	var inner := _arc(centre, radius - thickness)
	inner.reverse()
	points.append_array(inner)
	points.append(Vector2(left + thickness, top))
	areas[key] = {
		"sub": false,
		"poly": points,
		# Well clear of where the odds land further along the band, or the
		# flat bet's chips would sit on the odds spot and clicks meant for
		# the line would take odds instead.
		"chip": Vector2(left + (right - left) * 0.42, bottom - thickness * 0.5),
	}
	_rows[key] = Rect2(left, top, right - left, bottom - top)


## The outer corner quarter, sweeping from pointing left round to pointing
## down. Screen y grows downward, so sin is *not* negated here — flipping it
## curves the corner the wrong way and folds the band into a self-
## intersecting polygon that won't triangulate.
func _arc(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in ARC_STEPS + 1:
		var angle: float = lerpf(PI, PI / 2.0, float(i) / float(ARC_STEPS))
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


## Odds sit on their flat bet's band, at the spot a dealer heels them: a
## landing zone of their own rather than the whole band, so disabling them
## on a come-out greys out that spot and not the entire pass line.
func _odds_behind(key: String, flat: String, along: float, thickness: float) -> void:
	if not areas.has(flat):
		return
	var band: Rect2 = _rows[flat]
	var centre := Vector2(band.position.x + band.size.x * along, areas[flat].chip.y)
	var half := Vector2(46.0, thickness * 0.5)
	_rect_area(key, Rect2(centre - half, half * 2.0), Vector2(0.5, 0.5), true)


## The stickman's centre box: any seven across the top, the hardways
## flanking the one-roll dice numbers, horn and C & E, any craps beneath.
func _build_props(rect: Rect2) -> void:
	var gap := 3.0
	var unit: float = (rect.size.y - 4.0 * gap) / 6.0
	var y: float = rect.position.y

	_rect_area("any_7", Rect2(rect.position.x, y, rect.size.x, unit), Vector2(0.5, 0.72))
	y += unit + gap

	var quarter: float = (rect.size.x - 3.0 * gap) / 4.0
	for row in [["hard_6", "prop_2", "prop_12", "hard_10"],
			["hard_8", "prop_3", "prop_11", "hard_4"]]:
		for i in 4:
			_rect_area(String(row[i]),
				Rect2(rect.position.x + i * (quarter + gap), y, quarter, unit * 1.5),
				Vector2(0.5, 0.82))
		y += unit * 1.5 + gap

	var half: float = (rect.size.x - gap) / 2.0
	_rect_area("horn", Rect2(rect.position.x, y, half, unit), Vector2(0.5, 0.7))
	_rect_area("c_and_e", Rect2(rect.position.x + half + gap, y, half, unit), Vector2(0.5, 0.7))
	y += unit + gap

	_rect_area("any_craps", Rect2(rect.position.x, y, rect.size.x, unit), Vector2(0.5, 0.72))


# --- paint -------------------------------------------------------------------

func _draw() -> void:
	if areas.is_empty():
		return

	# Felt, then every area outlined in white the way a table is printed.
	draw_rect(Rect2(Vector2.ZERO, size), FELT, true)
	for key in areas:
		_fill(key)
	for key in areas:
		if bool(areas[key].get("sub", false)):
			continue  # Drawn as part of the box or band it sits in.
		draw_polyline(_closed(areas[key].poly), LINE, 1.6, true)

	_draw_boxes()
	_draw_bands()
	_draw_come()
	_draw_field()
	_draw_big()
	_draw_props()
	_draw_puck()


## Areas are mostly bare felt; a few carry their own wash so the eye can
## group them the way it does on a real table.
func _fill(key: String) -> void:
	var wash := Color(0, 0, 0, 0)
	# The line's odds spots sit on a band that is already washed; washing
	# them again just prints a darker rectangle on the pass line.
	if key.ends_with("_odds"):
		return
	if key.begins_with("dont_come_") or key == "dont_come":
		wash = Color(0.34, 0.1, 0.12, 0.85)
	elif key.begins_with("come_"):
		wash = Color(0.09, 0.32, 0.19, 1.0)
	elif key.begins_with("place_"):
		wash = Color(0.05, 0.22, 0.13, 1.0)
	elif key == "field":
		wash = Color(0.11, 0.2, 0.36, 0.7)
	elif key.begins_with("dont"):
		wash = Color(0.3, 0.09, 0.11, 0.45)
	elif key == "pass":
		wash = Color(0.1, 0.28, 0.5, 0.4)
	elif key.begins_with("hard") or key.begins_with("prop") or key in ["horn", "c_and_e", "any_7", "any_craps"]:
		wash = FELT_DEEP
	elif key.begins_with("big"):
		wash = Color(0.08, 0.3, 0.18, 0.8)
	if wash.a > 0.0:
		draw_colored_polygon(areas[key].poly, wash)


func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(poly)
	if out.size() > 0:
		out.append(out[0])
	return out


func _draw_boxes() -> void:
	for number in POINTS:
		var box: Rect2 = _rows["box_%d" % number]
		draw_rect(box, LINE, false, 2.0)
		var body: Rect2 = _bbox(areas["come_%d" % number].poly)
		var place: Rect2 = _bbox(areas["place_%d" % number].poly)
		# The number spans the box until the odds spot opens, then shrinks
		# into the come half so the two don't print on top of each other.
		var name_w: float = body.size.x if number in come_odds_open else box.size.x
		var name_size := int(clampf(minf(body.size.y * 0.62,
			name_w / maxf(2.0, String(BOX_NAMES[number]).length()) * 1.55), 13, 32))
		_centre(String(BOX_NAMES[number]), Rect2(box.position.x, body.position.y,
			name_w, body.size.y), name_size, TEXT)
		_text(_pays("place_%d" % number),
			Rect2(place.position.x + 6, place.position.y, place.size.x - 12, place.size.y),
			12, LINE_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		_edge("place_%d" % number, place)

		# The don't come strip above the number is printed, not labelled —
		# there is no room, and chips landing there say what it is.
		var strip: Rect2 = _bbox(areas["dont_come_%d" % number].poly)
		draw_line(Vector2(box.position.x, strip.end.y),
			Vector2(box.end.x, strip.end.y), LINE_DIM, 1.0)
		draw_line(Vector2(box.position.x, place.position.y),
			Vector2(box.end.x, place.position.y), LINE_DIM, 1.0)

		# While a bet is on the number, its odds spot becomes a visible box
		# — drawn exactly on the hit-zone that was always there, so paint
		# and clicks stay one thing.
		if number in come_odds_open:
			var spot: Rect2 = _bbox(areas["come_odds_%d" % number].poly).grow(-3.0)
			draw_rect(spot, Color(1, 1, 1, 0.07), true)
			draw_rect(spot, GOLD, false, 1.2)
			_centre(_label("come_odds_%d" % number),
				Rect2(spot.position.x, spot.position.y + spot.size.y * 0.16,
					spot.size.x, spot.size.y * 0.34), 11, GOLD)
			_centre(_pays("come_odds_%d" % number),
				Rect2(spot.position.x, spot.position.y + spot.size.y * 0.52,
					spot.size.x, spot.size.y * 0.3), 10, LINE_DIM)
		if number in dont_odds_open:
			var lay_spot: Rect2 = _bbox(areas["dont_come_odds_%d" % number].poly).grow(-2.0)
			draw_rect(lay_spot, Color(1, 1, 1, 0.07), true)
			draw_rect(lay_spot, GOLD, false, 1.2)
			_centre(_label("dont_come_odds_%d" % number), lay_spot, 10, GOLD)

	var dc: Rect2 = _rows["dont_come"]
	_centre("DON'T\nCOME",
		Rect2(dc.position.x, dc.position.y + dc.size.y * 0.34, dc.size.x, dc.size.y * 0.34),
		int(clampf(dc.size.y * 0.15, 12, 18)), TEXT)
	_centre("BAR 12", Rect2(dc.position.x, dc.position.y + dc.size.y * 0.7, dc.size.x, dc.size.y * 0.16),
		12, LINE_DIM)
	_edge("dont_come", Rect2(dc.position.x, dc.end.y - dc.size.y * 0.18, dc.size.x, dc.size.y * 0.16))


func _draw_bands() -> void:
	var pass_rect: Rect2 = _rows["pass"]
	_centre("P A S S   L I N E",
		Rect2(pass_rect.position.x + pass_rect.size.x * 0.34, size.y - PASS_T,
			pass_rect.size.x * 0.5, PASS_T),
		int(clampf(PASS_T * 0.52, 13, 20)), TEXT)
	_edge("pass", Rect2(pass_rect.position.x + pass_rect.size.x * 0.84, size.y - PASS_T,
		pass_rect.size.x * 0.15, PASS_T))

	var dont: float = size.y - PASS_T - BAND_GAP - DONT_T
	_centre("DON'T PASS  BAR 12",
		Rect2(pass_rect.position.x + pass_rect.size.x * 0.34, dont, pass_rect.size.x * 0.5, DONT_T),
		int(clampf(DONT_T * 0.5, 11, 16)), TEXT)
	_edge("dont_pass", Rect2(pass_rect.position.x + pass_rect.size.x * 0.84, dont,
		pass_rect.size.x * 0.15, DONT_T))


func _draw_come() -> void:
	var rect: Rect2 = _rows["come"]
	_centre("C O M E", Rect2(rect.position.x, rect.position.y + rect.size.y * 0.06,
		rect.size.x, rect.size.y * 0.5), int(clampf(rect.size.y * 0.4, 18, 34)), TEXT)
	_edge("come", Rect2(rect.position.x, rect.position.y + rect.size.y * 0.58,
		rect.size.x, rect.size.y * 0.2))


func _draw_field() -> void:
	var rect: Rect2 = _rows["field"]
	_centre("F I E L D", Rect2(rect.position.x, rect.position.y + rect.size.y * 0.02,
		rect.size.x, rect.size.y * 0.34), int(clampf(rect.size.y * 0.26, 13, 22)), TEXT)
	# The field numbers are the whole bet, so they are printed large, with
	# the two that pay a bonus ringed as a table rings them.
	var numbers := [2, 3, 4, 9, 10, 11, 12]
	var step: float = rect.size.x / float(numbers.size())
	var y: float = rect.position.y + rect.size.y * 0.56
	for i in numbers.size():
		var cell := Rect2(rect.position.x + i * step, y - rect.size.y * 0.16, step, rect.size.y * 0.36)
		var number: int = numbers[i]
		if number in [2, 12]:
			draw_arc(cell.get_center(), minf(step, rect.size.y * 0.34) * 0.46, 0.0, TAU, 24,
				GOLD, 1.6, true)
		_centre(str(number), cell, int(clampf(rect.size.y * 0.3, 14, 24)),
			GOLD if number in [2, 12] else TEXT)
	_centre("2 PAYS DOUBLE   ·   12 PAYS TRIPLE",
		Rect2(rect.position.x, rect.end.y - rect.size.y * 0.22, rect.size.x, rect.size.y * 0.2),
		11, LINE_DIM)
	# Shares the line with the bonus note rather than landing on a number.
	if edges_shown:
		_text(String(text.get("field", {}).get("edge", "")),
			Rect2(rect.position.x, rect.end.y - rect.size.y * 0.22,
				rect.size.x - 12, rect.size.y * 0.2),
			11, EDGE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_big() -> void:
	var rect: Rect2 = _rows["big"]
	draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + Vector2(0, rect.size.y),
		LINE, 1.6, true)
	_centre("BIG 6", Rect2(rect.position.x, rect.position.y + rect.size.y * 0.08,
		rect.size.x * 0.62, rect.size.y * 0.3), int(clampf(rect.size.y * 0.22, 11, 17)), TEXT)
	_centre("BIG 8", Rect2(rect.position.x + rect.size.x * 0.38, rect.position.y + rect.size.y * 0.6,
		rect.size.x * 0.62, rect.size.y * 0.3), int(clampf(rect.size.y * 0.22, 11, 17)), TEXT)
	_edge("big_6", Rect2(rect.position.x, rect.position.y + rect.size.y * 0.34,
		rect.size.x * 0.5, rect.size.y * 0.16))
	_edge("big_8", Rect2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.84,
		rect.size.x * 0.5, rect.size.y * 0.16))


func _draw_props() -> void:
	# Dice pairs on the one-roll numbers, as a table prints them.
	const FACES := {
		"prop_2": [1, 1], "prop_3": [1, 2], "prop_11": [5, 6], "prop_12": [6, 6],
		"hard_4": [2, 2], "hard_6": [3, 3], "hard_8": [4, 4], "hard_10": [5, 5],
	}
	for key in areas:
		if not (key.begins_with("hard") or key.begins_with("prop")
				or key in ["horn", "c_and_e", "any_7", "any_craps"]):
			continue
		var rect: Rect2 = _bbox(areas[key].poly)
		if FACES.has(key):
			var hard: bool = key.begins_with("hard")
			var pip: float = minf(rect.size.x * 0.3, rect.size.y * 0.36)
			var top: float = rect.position.y + rect.size.y * (0.24 if hard else 0.12)
			var mid: float = rect.get_center().x
			for i in 2:
				CrapsDie.draw_face(self,
					Rect2(mid + (i * 2 - 1) * pip * 0.56 - pip * 0.5, top, pip, pip),
					int(FACES[key][i]))
			if hard:
				_centre("HARD %s" % key.trim_prefix("hard_"),
					Rect2(rect.position.x, rect.position.y + rect.size.y * 0.04,
						rect.size.x, rect.size.y * 0.18), 13, TEXT)
			_centre(_pays(key), Rect2(rect.position.x, top + pip, rect.size.x, rect.size.y * 0.26),
				12, GOLD)
		else:
			var label := _label(key)
			var tall := rect.size.y > 46.0
			_centre(label, Rect2(rect.position.x, rect.position.y + rect.size.y * (0.12 if tall else 0.06),
				rect.size.x, rect.size.y * 0.42),
				int(clampf(rect.size.y * (0.24 if tall else 0.4), 11, 17)), TEXT)
			_centre(_pays(key), Rect2(rect.position.x, rect.position.y + rect.size.y * 0.52,
				rect.size.x, rect.size.y * 0.3), 12, GOLD)
		_edge(key, Rect2(rect.position.x, rect.end.y - rect.size.y * 0.26, rect.size.x, rect.size.y * 0.22))


## The puck a dealer moves: black and OFF beside the boxes on a come-out,
## white and ON sitting on the point once there is one.
func _draw_puck() -> void:
	var spot: Vector2
	var radius := 17.0
	if point == 0:
		# Parked in the don't come box, above its name, the way a dealer
		# leaves it between points.
		var dc: Rect2 = _rows["dont_come"]
		spot = Vector2(dc.get_center().x, dc.position.y + radius + 4.0)
	else:
		var box: Rect2 = _rows["box_%d" % point]
		spot = Vector2(box.get_center().x, box.position.y + radius * 0.8)
	var face := Color(0.95, 0.95, 0.93) if point != 0 else Color(0.1, 0.1, 0.11)
	var ink := Color(0.1, 0.1, 0.11) if point != 0 else Color(0.9, 0.9, 0.88)
	draw_circle(spot, radius, face)
	draw_arc(spot, radius, 0.0, TAU, 28, ink, 2.0, true)
	_centre("ON" if point != 0 else "OFF",
		Rect2(spot.x - radius, spot.y - radius * 0.6, radius * 2.0, radius * 1.2), 12, ink)


# --- text --------------------------------------------------------------------

func _label(key: String) -> String:
	return String(text.get(key, {}).get("label", ""))


func _pays(key: String) -> String:
	return String(text.get(key, {}).get("pays", ""))


## Only drawn while the toggle is on — a real table prints no edges.
func _edge(key: String, rect: Rect2) -> void:
	if not edges_shown:
		return
	var edge := String(text.get(key, {}).get("edge", ""))
	if edge != "":
		_centre(edge, rect, 11, EDGE_TEXT)


## Centres one or more lines in a rect.
func _centre(what: String, rect: Rect2, font_size: int, colour: Color) -> void:
	_text(what, rect, font_size, colour, HORIZONTAL_ALIGNMENT_CENTER)


## Lays one or more lines vertically centred in a rect, at the given
## horizontal alignment.
func _text(what: String, rect: Rect2, font_size: int, colour: Color,
		align: int) -> void:
	var font := get_theme_default_font()
	var lines := what.split("\n")
	var line_h: float = font.get_height(font_size)
	var block: float = line_h * lines.size()
	var y: float = rect.position.y + (rect.size.y - block) * 0.5 + font.get_ascent(font_size)
	for line in lines:
		draw_string(font, Vector2(rect.position.x, y), line, align,
			rect.size.x, font_size, colour)
		y += line_h


func _bbox(poly: PackedVector2Array) -> Rect2:
	var rect := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		rect = rect.expand(p)
	return rect

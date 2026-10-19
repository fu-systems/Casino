class_name LabChart
extends Control
## The Systems Lab's results picture: one session's bankroll over its
## rounds, or many sessions' results as a histogram. Either way the house's
## expectation is drawn on top, so the actual result is always read against
## what the edge predicts.

const COLOR_AXIS := Color(0.72, 0.8, 0.74)
const COLOR_LINE := Color(0.94, 0.78, 0.29)
const COLOR_EXPECTED := Color(0.96, 0.5, 0.45)
const COLOR_START := Color(0.72, 0.8, 0.74, 0.6)
const COLOR_BAR := Color(0.36, 0.62, 0.84)
const COLOR_BAR_LOSS := Color(0.75, 0.3, 0.28)
const PAD := Vector2(70, 26)

## "curve" or "histogram".
var mode := ""
var curve: Array = []
var start := 0
var expected_final := 0.0
var histogram: Dictionary = {}
var expected_mean := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(520, 250)


func show_curve(points: Array, bankroll: int, expected_net: float) -> void:
	mode = "curve"
	curve = points
	start = bankroll
	expected_final = bankroll + expected_net
	queue_redraw()


func show_histogram(bins: Dictionary, mean_expected: float) -> void:
	mode = "histogram"
	histogram = bins
	expected_mean = mean_expected
	queue_redraw()


func clear() -> void:
	mode = ""
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var area := Rect2(PAD, size - PAD * 2)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.12, 0.07))
	if mode == "":
		draw_string(font, Vector2(0, size.y / 2), "Run the system to see how it does.",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, COLOR_AXIS)
		return
	draw_line(area.position, Vector2(area.position.x, area.end.y), COLOR_AXIS, 1.0)
	draw_line(Vector2(area.position.x, area.end.y), area.end, COLOR_AXIS, 1.0)
	if mode == "curve":
		_draw_curve(area, font)
	else:
		_draw_histogram(area, font)


func _draw_curve(area: Rect2, font: Font) -> void:
	if curve.size() < 2:
		return
	var low := float(mini(start, int(expected_final)))
	var high := float(maxi(start, int(expected_final)))
	for v in curve:
		low = minf(low, float(v))
		high = maxf(high, float(v))
	if is_equal_approx(low, high):
		high = low + 1.0
	var to_y := func(v: float) -> float:
		return area.end.y - (v - low) / (high - low) * area.size.y
	var points := PackedVector2Array()
	for i in curve.size():
		points.append(Vector2(area.position.x + area.size.x * i / (curve.size() - 1), to_y.call(float(curve[i]))))
	# Where you started, and the straight line the edge says you'd drift down.
	var start_y: float = to_y.call(float(start))
	draw_dashed_line(Vector2(area.position.x, start_y), Vector2(area.end.x, start_y), COLOR_START, 1.0, 6.0)
	draw_line(Vector2(area.position.x, start_y), Vector2(area.end.x, to_y.call(expected_final)), COLOR_EXPECTED, 2.0)
	draw_polyline(points, COLOR_LINE, 2.0, true)
	draw_string(font, Vector2(4, area.position.y + 12), "$%s" % Bank.fmt(int(high)), HORIZONTAL_ALIGNMENT_LEFT, PAD.x - 8, 13, COLOR_AXIS)
	draw_string(font, Vector2(4, area.end.y), "$%s" % Bank.fmt(int(low)), HORIZONTAL_ALIGNMENT_LEFT, PAD.x - 8, 13, COLOR_AXIS)
	draw_string(font, Vector2(area.position.x, area.end.y + 18), "Bankroll by round", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_LINE)
	draw_string(font, Vector2(area.position.x + 170, area.end.y + 18), "What the house edge predicts", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_EXPECTED)


func _draw_histogram(area: Rect2, font: Font) -> void:
	var counts: Array = histogram.get("counts", [])
	if counts.is_empty():
		return
	var low := float(histogram.min)
	var high := float(histogram.max)
	var span := maxf(1.0, high - low)
	var tallest := 1
	for c in counts:
		tallest = maxi(tallest, int(c))
	var width := area.size.x / counts.size()
	for i in counts.size():
		var bin_low := low + span * i / counts.size()
		var h := area.size.y * int(counts[i]) / tallest
		var bar := Rect2(area.position.x + i * width + 1, area.end.y - h, width - 2, h)
		draw_rect(bar, COLOR_BAR_LOSS if bin_low + span / counts.size() <= 0.0 else COLOR_BAR)
	var to_x := func(v: float) -> float:
		return area.position.x + clampf((v - low) / span, 0.0, 1.0) * area.size.x
	if low <= 0.0 and high >= 0.0:
		var zero_x: float = to_x.call(0.0)
		draw_dashed_line(Vector2(zero_x, area.position.y), Vector2(zero_x, area.end.y), COLOR_START, 1.0, 6.0)
		draw_string(font, Vector2(zero_x - 40, area.position.y - 6), "break even", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, COLOR_AXIS)
	var expected_x: float = to_x.call(expected_mean)
	draw_line(Vector2(expected_x, area.position.y + 14), Vector2(expected_x, area.end.y), COLOR_EXPECTED, 2.0)
	draw_string(font, Vector2(4, area.end.y + 18), money(low), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_AXIS)
	draw_string(font, Vector2(area.end.x - 80, area.end.y + 18), money(high), HORIZONTAL_ALIGNMENT_RIGHT, 80, 13, COLOR_AXIS)
	draw_string(font, Vector2(area.position.x + area.size.x / 2 - 160, area.end.y + 18),
		"Session results  ·  red line: the edge's average", HORIZONTAL_ALIGNMENT_CENTER, 320, 13, COLOR_EXPECTED)


## Signed money: "+$120", "−$1,000", "$0" — with cents for amounts under
## $100 that aren't whole, so a small expected loss doesn't read as nothing.
static func money(value: float) -> String:
	if absf(value) < 100.0 and not is_equal_approx(value, roundf(value)):
		var cents := "%.2f" % absf(value)
		return ("+$" if value > 0 else "−$") + cents
	var n := int(roundf(value))
	if n > 0:
		return "+$%s" % Bank.fmt(n)
	if n < 0:
		return "−$%s" % Bank.fmt(-n)
	return "$0"

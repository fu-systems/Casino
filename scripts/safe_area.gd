class_name SafeArea
extends MarginContainer
## Full-rect margin container that also keeps its contents clear of notches,
## camera cutouts and rounded corners.
##
## Held in landscape, a phone's cutout eats into one short edge — exactly
## where the Back button and the balance readout sit. The device-reported
## safe area is in physical window pixels, so it is converted into the
## viewport's logical units before being applied.
##
## Only mobile reports a meaningful safe area; on desktop
## `get_display_safe_area()` describes the screen (minus the taskbar) rather
## than the window, so this collapses to a plain uniform margin there.

var base_margin := 20


static func create(margin: int) -> SafeArea:
	var node := SafeArea.new()
	node.base_margin = margin
	# Anchored before it enters the tree: setting the preset from _ready()
	# lands after the first layout pass and leaves the container stuck at
	# its minimum size instead of filling the screen.
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	return node


func _ready() -> void:
	_apply_margins()
	get_viewport().size_changed.connect(_apply_margins)


func _apply_margins() -> void:
	var insets := _safe_insets()
	add_theme_constant_override("margin_left", base_margin + int(insets.x))
	add_theme_constant_override("margin_top", base_margin + int(insets.y))
	add_theme_constant_override("margin_right", base_margin + int(insets.z))
	add_theme_constant_override("margin_bottom", base_margin + int(insets.w))


## Left/top/right/bottom insets in viewport-logical pixels.
func _safe_insets() -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO

	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		return Vector4.ZERO

	var safe := DisplayServer.get_display_safe_area()
	# The stretch scale is uniform, so one axis is enough to convert.
	var to_logical := get_viewport_rect().size.x / window.x
	return Vector4(
		maxf(0.0, float(safe.position.x)) * to_logical,
		maxf(0.0, float(safe.position.y)) * to_logical,
		maxf(0.0, window.x - float(safe.position.x + safe.size.x)) * to_logical,
		maxf(0.0, window.y - float(safe.position.y + safe.size.y)) * to_logical)

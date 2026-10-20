extends Node
## Fullscreen on desktop, registered as the "WindowMode" autoload after
## `Store`, which says whether this is the Steam edition.
##
## F11 or Alt+Enter switches between a window and fullscreen, and the choice
## is remembered. The Steam edition starts fullscreen, as Steam players
## expect; the other desktop builds start in a window. Phones have no window
## to switch, so there it does nothing.

const SECTION := "display"
const SAVE_KEY := "fullscreen"


func _ready() -> void:
	if available():
		_apply(is_fullscreen())


## Whether there's a window to switch at all.
func available() -> bool:
	return not OS.has_feature("mobile") and not OS.has_feature("web")


func is_fullscreen() -> bool:
	return bool(SaveData.get_value(SECTION, SAVE_KEY, starts_fullscreen()))


## Where a first launch begins, before the player has chosen.
func starts_fullscreen() -> bool:
	return Store.backend == Store.Backend.STEAM


func toggle() -> void:
	var on := not is_fullscreen()
	SaveData.set_value(SECTION, SAVE_KEY, on)
	_apply(on)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not available():
		return
	if key.keycode == KEY_F11 or (key.alt_pressed and key.keycode in [KEY_ENTER, KEY_KP_ENTER]):
		toggle()
		get_viewport().set_input_as_handled()


func _apply(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)

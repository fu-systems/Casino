extends Node
## Asserts every scene fits inside the design viewport.
##
## The project uses `stretch/aspect = "expand"`, which guarantees the
## viewport is never smaller than the 1280x720 design size in either
## direction — but only helps if the scenes themselves fit that size. This
## checks each scene's combined minimum against it, so a layout change that
## would clip on a 4:3 tablet fails CI instead of shipping.
##
## Run headless:
##   godot --headless --path . tests/layout_fits.tscn

const DESIGN := Vector2(1280, 720)
const SCENES := [
	"res://scenes/main_menu.tscn",
	"res://scenes/blackjack.tscn",
	"res://scenes/roulette.tscn",
]

var failures := 0


func _ready() -> void:
	for path in SCENES:
		await _check_scene(path)
	if failures == 0:
		print("=== ALL SCENES FIT %dx%d ===" % [int(DESIGN.x), int(DESIGN.y)])
	else:
		print("=== %d SCENE(S) OVERFLOW THE DESIGN VIEWPORT ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check_scene(path: String) -> void:
	var scene: PackedScene = load(path)
	var root: Control = scene.instantiate()
	add_child(root)
	# The root is anchored full-rect, so it takes the viewport size, which
	# headless reports as the design size. Let containers settle first.
	for i in 4:
		await get_tree().process_frame

	var needed := _deep_minimum(root)
	var name := path.get_file().get_basename()
	var headroom := DESIGN - needed
	if needed.x > DESIGN.x or needed.y > DESIGN.y:
		failures += 1
		print("FAIL: %s needs %dx%d, over the %dx%d design size by %dx%d" % [
			name, needed.x, needed.y, DESIGN.x, DESIGN.y,
			maxf(0.0, -headroom.x), maxf(0.0, -headroom.y)])
	else:
		print("OK: %-10s needs %4dx%-4d  (headroom %3dx%-3d)" % [
			name, needed.x, needed.y, headroom.x, headroom.y])

	root.queue_free()
	await get_tree().process_frame


## Largest minimum size demanded anywhere in the tree. Scroll containers
## report a tiny minimum of their own, so their contents are skipped rather
## than counted — they are allowed to overflow, that is their job.
func _deep_minimum(node: Node) -> Vector2:
	var needed := Vector2.ZERO
	if node is Control:
		needed = (node as Control).get_combined_minimum_size()
	if node is ScrollContainer:
		return needed
	for child in node.get_children():
		needed = needed.max(_deep_minimum(child))
	return needed

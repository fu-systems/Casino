extends CasinoTest
## Asserts every scene fits inside the design viewport.
##
## The project uses `stretch/aspect = "expand"`, which guarantees the viewport
## is never smaller than the 1280x720 design size in either direction — but
## only helps if the scenes themselves fit that size. Roulette clears it by
## just 22px, so this guard is what stops a layout change clipping on a 4:3
## tablet.

const DESIGN := Vector2(1280, 720)
const SCENES := [
	"res://scenes/main_menu.tscn",
	"res://scenes/blackjack.tscn",
	"res://scenes/roulette.tscn",
	"res://scenes/craps.tscn",
	"res://scenes/baccarat.tscn",
]


func run() -> void:
	for path in SCENES:
		if not ResourceLoader.exists(path):
			continue
		await _check_scene(path)


func _check_scene(path: String) -> void:
	var root: Control = load(path).instantiate()
	add_child(root)
	# The root is anchored full-rect, so it takes the viewport size, which
	# headless reports as the design size. Let containers settle first.
	await frames(4)

	var needed := _deep_minimum(root)
	var name := path.get_file().get_basename()
	var headroom := DESIGN - needed
	if needed.x > DESIGN.x or needed.y > DESIGN.y:
		fail("%s needs %dx%d, over the %dx%d design size" % [
			name, needed.x, needed.y, DESIGN.x, DESIGN.y])
	else:
		note("%-10s needs %4dx%-4d  (headroom %3dx%-3d)" % [
			name, needed.x, needed.y, headroom.x, headroom.y])

	root.queue_free()
	await frames()


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

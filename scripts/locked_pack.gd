class_name LockedPack
extends RefCounted
## What a pack's screen shows if it's somehow opened without the pack — a
## plain cover saying where it lives, never a pop-up sales pitch. The normal
## ways in already check ownership, so this is a backstop.


static func cover(screen: Control, id: String, back_to: String) -> Modal:
	var entry := Store.pack(id)
	var modal := Modal.open(screen, String(entry.get("title", "This pack")), 620)
	modal.name = "Locked"
	modal.add_text("%s is an optional one-time pack. You'll find it in Extras, with exactly what it contains."
		% entry.get("title", "This"))
	modal.add_button("See it in Extras", Color(0.4, 0.3, 0.1),
		func() -> void: Store.show_extras(screen.get_tree(), id, back_to), false)
	modal.add_button("Back", Color(0.25, 0.22, 0.2),
		func() -> void: screen.get_tree().change_scene_to_file(back_to), false)
	return modal

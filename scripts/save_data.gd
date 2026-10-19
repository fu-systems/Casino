extends Node
## Everything the game remembers between launches, registered as the
## "SaveData" autoload ahead of everything that reads from it.
##
## One small ConfigFile is plenty: the bankroll, whether the play-money notice
## has been accepted, cached purchases, high scores and saved systems. Every
## write goes straight to disk, so a phone killing the app mid-game loses
## nothing.
##
## The rule suites call `use_memory_only()` first, so running them never
## reads a developer's real save or writes over it.

const PATH := "user://save.cfg"

var enabled := true
var _config := ConfigFile.new()


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var err := _config.load(PATH)
		if err != OK:
			# A corrupt save shouldn't stop the game starting; it just starts
			# fresh, which for a free-chip game costs nothing.
			push_warning("Couldn't read %s (error %d); starting fresh." % [PATH, err])
			_config = ConfigFile.new()


func get_value(section: String, key: String, default: Variant = null) -> Variant:
	return _config.get_value(section, key, default)


func set_value(section: String, key: String, value: Variant) -> void:
	_config.set_value(section, key, value)
	_flush()


func has_value(section: String, key: String) -> bool:
	return _config.has_section_key(section, key)


func erase_value(section: String, key: String) -> void:
	if _config.has_section_key(section, key):
		_config.erase_section_key(section, key)
		_flush()


## Every key in a section, for things stored one-per-key like saved systems.
func keys(section: String) -> PackedStringArray:
	if not _config.has_section(section):
		return PackedStringArray()
	return _config.get_section_keys(section)


## Detaches from disk and starts from an empty save. Used by the rule suites,
## and harmless to call twice.
func use_memory_only() -> void:
	enabled = false
	_config = ConfigFile.new()


func _flush() -> void:
	if not enabled:
		return
	var err := _config.save(PATH)
	if err != OK:
		push_warning("Couldn't write %s (error %d)." % [PATH, err])

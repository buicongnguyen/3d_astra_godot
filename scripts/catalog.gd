extends RefCounted

static var definitions: Dictionary = {}
static var rocks: Array = []

static func load_data():
	if definitions.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
		definitions = data.definitions
		rocks = data.rocks

static func get_def(key: String) -> Dictionary:
	load_data()
	return definitions.get(key, {})

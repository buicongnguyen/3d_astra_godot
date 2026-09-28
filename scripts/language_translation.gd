extends Translation
# Shared catalog. Original Control text remains intact when switching languages.
var catalog: Dictionary = {}
var patterns: Array = []

func _init():
	locale = "vi"
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/vi.json"))
	for key in data.messages:
		catalog[normalize(key)] = data.messages[key]
	for entry in data.patterns:
		var pattern = RegEx.new()
		pattern.compile("(?i)"+entry[0])
		patterns.append([pattern,entry[1]])

func normalize(value: String) -> String:
	return value.strip_edges().replace("\n"," ").replace("\r","").replace("\t"," ").to_lower()

func _get_message(src_message: StringName, _context: StringName) -> StringName:
	return StringName(translate_text(str(src_message)))

func translate_text(text: String, depth: int = 0) -> String:
	if depth > 6 or text == "" or text.to_lower() == text.to_upper(): return text
	var source = text.strip_edges()
	var key = normalize(source)
	var result = ""
	if catalog.has(key):
		result = catalog[key]
		if source == source.to_upper() and source != source.to_lower(): result = result.to_upper()
	else:
		for entry in patterns:
			var found = entry[0].search(source)
			if found == null: continue
			result = entry[1]
			for i in range(found.get_group_count(),0,-1):
				result = result.replace("{%d}" % i,translate_text(found.get_string(i),depth+1))
			break
		if result == "":
			result = source
			for separator in ["\n"," · "," — "," / ",". "]:
				if not source.contains(separator): continue
				var pieces = source.split(separator)
				for i in range(pieces.size()):
					var suffix = "." if separator == ". " and i < pieces.size()-1 else ""
					pieces[i] = translate_text(pieces[i]+suffix,depth+1)
				result = (" " if separator == ". " else separator).join(pieces)
				break
	var start = text.find(source)
	return text.substr(0,start)+result+text.substr(start+source.length())

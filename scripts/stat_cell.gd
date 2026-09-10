extends VBoxContainer
const Icons = preload("res://scripts/ui_icons.gd")

var heading: Label
var value: Label
var symbol: TextureRect
var icon_key = ""
var text: String:
	get: return heading.text+"\n"+value.text
	set(content):
		heading.text = content.get_slice("\n",0)
		value.text = content.get_slice("\n",1)

func _init():
	add_theme_constant_override("separation",1)
	add_theme_font_size_override("font_size",12)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",4)
	add_child(row)
	symbol = TextureRect.new()
	symbol.custom_minimum_size = Vector2(16,16)
	symbol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	symbol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(symbol)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size",10)
	heading.clip_text = true
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	value = Label.new()
	value.add_theme_font_size_override("font_size",12)
	value.clip_text = true
	add_child(value)

func configure(title: String, kind: String):
	icon_key = kind
	symbol.texture = Icons.texture(kind)
	text = title+"\n0"

func get_line_count() -> int:
	return heading.get_line_count()+value.get_line_count()

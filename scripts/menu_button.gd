extends Button
const Icons = preload("res://scripts/ui_icons.gd")

var icon_key = ""
var caption = ""
var price: Array = []
var menu_icon: Texture2D
var key_space = 0

func configure(command: String, kind: String, short_name: String, cost: Array, keyboard: bool):
	set_meta("command_label",command)
	set_meta("stable_width",144)
	text = ""
	icon_key = kind
	menu_icon = Icons.texture(kind)
	caption = short_name if short_name != "" else command
	price = cost
	key_space = 16 if keyboard else 0
	custom_minimum_size = Vector2(144,44)
	if tooltip_text == "": tooltip_text = command

func _draw():
	var tint = Color(1,1,1,0.45 if disabled else 1)
	draw_texture_rect(menu_icon,Rect2(7,(size.y-22)/2,22,22),false,tint)
	var font = get_theme_font("font")
	var baseline = (size.y-font.get_height(12))/2+font.get_ascent(12) if price.is_empty() else 18.0
	draw_string(font,Vector2(35,baseline),caption,HORIZONTAL_ALIGNMENT_LEFT,size.x-41-key_space,12,Color("e5f2ec")*tint)
	if not price.is_empty():
		var pen = 35.0
		for i in range(2):
			if i == 1 and price[i] == 0: continue
			var amount = str(int(price[i]))
			var color = Color("edc76f") if i == 0 else Color("69cbee")
			draw_texture_rect(Icons.texture("alloy" if i == 0 else "energy"),Rect2(pen,24,10,10),false,color*tint)
			draw_string(font,Vector2(pen+12,34),amount,HORIZONTAL_ALIGNMENT_LEFT,-1,11,color*tint)
			pen += 19+font.get_string_size(amount,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x

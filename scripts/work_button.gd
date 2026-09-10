extends Button

var glyph = ""
var progress = 0.0
var waiting = false

func _draw():
	var tint = Color(1,1,1,0.45 if disabled else 1)
	draw_string(get_theme_font("font"),Vector2(2,20),glyph,HORIZONTAL_ALIGNMENT_CENTER,size.x-4,12,Color("d3e4d6")*tint)
	for i in range(10):
		var cell = Rect2(Vector2(2+i*4,27),Vector2(3,3))
		draw_rect(cell,(Color("72e990") if i < ceili(clampf(progress,0,1)*10) else Color("304d3c"))*tint)
		if waiting: draw_rect(cell,Color("c79842")*tint,false,1)
	# A small visible red strip, backed by the complete 44px button hit target.
	draw_rect(Rect2(Vector2(1,35),Vector2(size.x-2,8)),Color("b84040")*tint)
	var center = Vector2(size.x/2,39)
	draw_line(center-Vector2(2,2),center+Vector2(2,2),tint,1)
	draw_line(center+Vector2(-2,2),center+Vector2(2,-2),tint,1)

extends Control
var game

func _draw():
	if not game or not game.view: return
	for e in game.sim.entities:
		if e.team != 0 and not game.sim.seen(e.p): continue
		if not game.selected.has(e.id) and e.hp >= e.max_hp: continue
		var point = game.view.camera.unproject_position(Vector3(e.p.x,3.2 if e.kind == "unit" else 5,e.p.y))
		draw_rect(Rect2(point-Vector2(20,0),Vector2(40,4)),Color("15282b"))
		draw_rect(Rect2(point-Vector2(20,0),Vector2(40*clampf(e.hp/e.max_hp,0,1),4)),game.view.colors[e.team])
	if game.dragging and not game.touch_active and game.mode == "":
		var rect = Rect2(game.pointer_start,game.pointer_now-game.pointer_start).abs()
		draw_rect(rect,Color(0.5,0.9,0.75,0.1))
		draw_rect(rect,Color("92ebc5"),false,1.5)
	var rect = game.minimap_rect
	if rect.size.x <= 0: return
	draw_rect(rect.grow(3),Color("1d393e"))
	draw_rect(rect,Color("536653"))
	if game.sim.nav.river:
		draw_rect(Rect2(rect.position+Vector2(0,rect.size.y*0.46875),Vector2(rect.size.x,rect.size.y*0.0625)),Color("477e85"))
		for x in [-22,0,22]:
			draw_rect(Rect2(map_point(Vector2(x-5,-3)),rect.size*Vector2(10.0/96,6.0/96)),Color("b7ac86"))
	for y in range(24):
		for x in range(24):
			var index = y*2*48+x*2
			if not game.sim.visible[0][index]:
				draw_rect(Rect2(rect.position+rect.size*Vector2(x,y)/24,rect.size/24+Vector2.ONE),Color(0.015,0.04,0.05,0.55 if game.sim.explored[0][index] else 0.94))
	for r in game.sim.deposits:
		if r.amount > 0 and game.sim.discovered(r.p): draw_circle(map_point(r.p),2,Color("edc76f") if r.type == "alloy" else Color("69cbee"))
	for e in game.sim.entities:
		if e.team != 0 and not game.sim.seen(e.p): continue
		var p = map_point(e.p)
		if e.team == 0: draw_circle(p,2.5,game.view.colors[0])
		else: draw_colored_polygon(PackedVector2Array([p+Vector2(0,-3),p+Vector2(3,0),p+Vector2(0,3),p+Vector2(-3,0)]),game.view.colors[1])
	for memory in game.known_buildings.values():
		if not game.sim.seen(memory.p):
			var p = map_point(memory.p)
			draw_rect(Rect2(p-Vector2(3,3),Vector2(6,6)),Color(game.view.colors[1],0.45),false,1)
	var focus = map_point(game.view.focus)
	draw_rect(Rect2(focus-Vector2(10,7),Vector2(20,14)),Color("f4edcb"),false,1)

func map_point(p: Vector2) -> Vector2:
	return game.minimap_rect.position+(p+Vector2(48,48))/96*game.minimap_rect.size

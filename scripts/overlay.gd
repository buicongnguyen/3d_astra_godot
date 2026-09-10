extends Control
const Activity = preload("res://scripts/activity.gd")
var game
var activity_snapshot = {"buildings":[],"resources":[],"workers":[]}

func _draw():
	if not game or not game.view: return
	for e in game.sim.entities:
		if e.team != 0 and not game.sim.seen(e.p): continue
		if e.hp <= 0: continue
		if not game.selected.has(e.id) and e.hp >= e.max_hp and e.shield >= e.max_shield: continue
		var point = game.view.camera.unproject_position(Vector3(e.p.x,3.2 if e.kind == "unit" else 5,e.p.y))
		if not feedback_visible(Rect2(point-Vector2(20,6),Vector2(40,10))): continue
		draw_rect(Rect2(point-Vector2(20,0),Vector2(40,4)),Color("15282b"))
		draw_rect(Rect2(point-Vector2(20,0),Vector2(40*clampf(e.hp/e.max_hp,0,1),4)),game.view.colors[e.team])
		if e.max_shield > 0:
			draw_rect(Rect2(point-Vector2(20,6),Vector2(40,3)),Color("15282b"))
			draw_rect(Rect2(point-Vector2(20,6),Vector2(40*clampf(e.shield/e.max_shield,0,1),3)),Color("69cbee"))
	draw_activity()
	if game.dragging and not game.touch_active and game.mode == "":
		var rect = Rect2(game.pointer_start,game.pointer_now-game.pointer_start).abs()
		draw_rect(rect,Color(0.5,0.9,0.75,0.1))
		draw_rect(rect,Color("92ebc5"),false,1.5)
	var rect = game.minimap_rect
	if rect.size.x <= 0: return
	draw_rect(rect.grow(3),Color("1d393e"))
	draw_rect(rect,Color("536653"))
	if game.sim.nav.river:
		draw_rect(Rect2(rect.position+Vector2(0,rect.size.y*(0.5-3.0/(game.sim.nav.half*2))),Vector2(rect.size.x,rect.size.y*6.0/(game.sim.nav.half*2))),Color("477e85"))
		for x in [-22,0,22]:
			draw_rect(Rect2(map_point(Vector2(x-5,-3)),rect.size*Vector2(10,6)/(game.sim.nav.half*2)),Color("b7ac86"))
	var fog_cells = game.sim.nav.grid_size/2
	for y in range(fog_cells):
		for x in range(fog_cells):
			var index = y*2*game.sim.nav.grid_size+x*2
			if not game.sim.visible[0][index]:
				draw_rect(Rect2(rect.position+rect.size*Vector2(x,y)/fog_cells,rect.size/fog_cells+Vector2.ONE),Color(0.015,0.04,0.05,0.55 if game.sim.explored[0][index] else 0.94))
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
	return game.minimap_rect.position+(p+Vector2.ONE*game.sim.nav.half)/(game.sim.nav.half*2)*game.minimap_rect.size

func project(p: Vector2,height: float) -> Vector2:
	return game.view.camera.unproject_position(Vector3(p.x,height,p.y))

func badge(p: Vector2,progress: float,color: Color):
	var width = 59.0
	if not get_viewport_rect().grow(width).has_point(p): return
	# Keep world labels clear of touch controls and the minimap on small screens.
	p.x = clampf(p.x,width/2+4,get_viewport_rect().size.x-width/2-4)
	var bounds = Rect2(p-Vector2(width/2+2,2),Vector2(width+4,9))
	if bounds.intersects(game.minimap_rect.grow(4)):
		p.x = game.minimap_rect.position.x-width/2-8
		bounds.position.x = p.x-width/2-2
	if not feedback_visible(bounds): return
	draw_rect(bounds,Color("0b1c20"))
	for i in range(10):
		draw_rect(Rect2(p+Vector2(-width/2+i*6,0),Vector2(5,5)),color if i < ceili(clampf(progress,0,1)*10) else Color("304a3a"))

func feedback_visible(bounds: Rect2) -> bool:
	return get_viewport_rect().encloses(bounds) and not bounds.intersects(game.header.get_global_rect().grow(3)) and not bounds.intersects(game.bottom.get_global_rect().grow(3)) and not bounds.intersects(game.minimap_rect.grow(3))

func draw_activity():
	var sim = game.sim
	var view = game.view
	var targets = {}
	activity_snapshot = {"buildings":[],"resources":[],"workers":[]}
	for e in sim.entities:
		if e.hp <= 0 or e.team != 0: continue
		var a = Activity.building(sim,e)
		if not a.is_empty():
			var p = project(e.p,6.4)
			badge(p,a.progress,Color("ffbd75") if a.get("waiting",false) else Color("a8edc6"))
			var record = a.duplicate(); record.id = e.id; record.x = p.x; record.y = p.y
			activity_snapshot.buildings.append(record)
		if e.type != "worker": continue
		var r = Activity.harvest_target(sim,e)
		var mining = Activity.harvesting(sim,e)
		if game.selected.has(e.id) and not r.is_empty() and sim.seen(r.p): targets[r.id] = r
		if mining:
			var p = project(e.p,1.8)
			var t = project(r.p,1.2)
			var color = Color("ffce75") if r.type == "alloy" else Color("8ce7ff")
			color.a = 0.65+0.35*sin(sim.time*7+e.id) if view.water_motion else 1.0
			if feedback_visible(Rect2(p,Vector2.ZERO).expand(t).grow(3)):
				draw_line(p,p.lerp(t,0.65),color,2)
				draw_rect(Rect2(p-Vector2(2,2),Vector2(4,4)),color)
		if game.selected.has(e.id) and (not r.is_empty() or e.carry > 0):
			var order = e.orders[0].type if not e.orders.is_empty() else ""
			var text = "Harvesting" if mining else ("Returning cargo" if order == "deliver" else (("To deposit" if e.moving else "Waiting") if not r.is_empty() else "Cargo"))
			badge(project(e.p,4),e.carry/10.0,Color("ffd17d"))
			activity_snapshot.workers.append({"id":e.id,"label":text,"carry":e.carry,"mining":mining})
	for r in targets.values():
		var points = PackedVector2Array()
		for i in range(25):
			var angle = i*TAU/24
			points.append(project(r.p+Vector2(cos(angle),sin(angle))*(r.radius+0.5),0.22))
		var bounds = Rect2(points[0],Vector2.ZERO)
		for point in points: bounds = bounds.expand(point)
		if feedback_visible(bounds.grow(2)): draw_polyline(points,Color("ffcf75") if r.type == "alloy" else Color("8ce7ff"),2.5,true)
		activity_snapshot.resources.append(r.id)
	for e in view.activity_effects:
		if not sim.seen(e.p): continue
		var p = project(e.p,3 if e.type == "impact" else 1)
		var fade = e.life/e.max_life
		var radius = (12 if e.type == "impact" else (28 if e.get("building",false) else (22 if e.get("heavy",false) else 13)))*(2-fade if view.water_motion else 1)
		if not feedback_visible(Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2)): continue
		var color = Color("9beaff") if e.get("shield",false) else Color("ffd199")
		color.a = fade
		draw_arc(p,radius,0,TAU,24,color,3 if e.type == "impact" else 2,true)
		if view.water_motion:
			for i in range(6):
				var direction = Vector2.from_angle(i*TAU/6)
				draw_line(p+direction*radius*0.55,p+direction*radius,color,2)

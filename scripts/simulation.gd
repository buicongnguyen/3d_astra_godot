extends RefCounted
const Catalog = preload("res://scripts/catalog.gd")
const Navigation = preload("res://scripts/navigation.gd")
var entities: Array = []
var deposits: Array = []
var players: Array = []
var visible: Array = []
var explored: Array = []
var events: Array = []
var nav = Navigation.new()
var next_id = 1
var time = 0.0
var result = ""
var ai_enabled = true
var ai_clock = 0.0
var vision_clock = 0.0
var wave_at = 85.0
var message = "Assign Harvesters to the amber alloy deposits."

func feedback(text: String,team: int):
	if team == 0: message = text

func _init(ai: bool = true, river: bool = true):
	Catalog.load_data()
	ai_enabled = ai
	nav.river = river
	for team in range(2):
		players.append({"alloy":450.0,"energy":150.0,"upgrade":false,"kills":0})
		var v = PackedByteArray()
		v.resize(2304)
		visible.append(v.duplicate())
		explored.append(v.duplicate())
		var side = 1 if team == 0 else -1
		spawn("hq",team,Vector2(-25,24)*side)
		spawn("barracks",team,Vector2(-16,25)*side)
		for i in range(4): spawn("worker",team,Vector2(-29+i*2,16)*side)
		spawn("ranger",team,Vector2(-18,17)*side)
		spawn("ranger",team,Vector2(-15,17)*side)
		spawn("vanguard",team,Vector2(-12,17)*side)
		for p in [Vector2(-36,18),Vector2(-37,22),Vector2(-35,26)]: resource("alloy",p*side,1600)
		resource("energy",Vector2(-30,34)*side,1400)
		resource("alloy",Vector2(-31,-25)*side,2400)
		resource("energy",Vector2(-25,-32)*side,1800)
	nav.rebuild(entities)
	update_vision()

func resource(type: String,p: Vector2,amount: int):
	deposits.append({"id":next_id,"type":type,"kind":"resource","p":p,"amount":amount,"initial":amount,"radius":1.7})
	next_id += 1

func spawn(type: String,team: int,p: Vector2,complete: bool = true) -> Dictionary:
	var e = Catalog.get_def(type).duplicate(true)
	e.merge({"type":type,"id":next_id,"team":team,"p":p,"max_hp":e.hp,"hp":e.hp if complete else 1.0,"complete":complete,"progress":1.0 if complete else 0.0,"orders":[],"path":[],"path_clock":0.0,"revision":-1,"cooldown":0.0,"carry":0,"carry_type":"","resource":0,"queue":[],"rally":null,"angle":0.0,"moving":false,"work":0.0,"stalled":0.0,"builder":0},true)
	next_id += 1
	entities.append(e)
	return e

func entity(id: int) -> Dictionary:
	for e in entities:
		if e.id == id and e.hp > 0: return e
	for r in deposits:
		if r.id == id and r.amount > 0: return r
	return {}

func own(team: int) -> Array:
	return entities.filter(func(e): return e.team == team and e.hp > 0)

func population(team: int) -> Dictionary:
	var p = {"used":0,"reserved":0,"cap":0}
	for e in own(team):
		p.used += e.get("pop",0)
		if e.complete: p.cap += e.get("supply",0)
		for q in e.queue: p.reserved += Catalog.get_def(q.type).get("pop",0)
	p.cap = mini(100,p.cap)
	return p

func can_pay(team: int,cost: Array) -> bool:
	return players[team].alloy >= cost[0] and players[team].energy >= cost[1]

func pay(team: int,cost: Array,factor: float = 1.0):
	players[team].alloy -= cost[0]*factor
	players[team].energy -= cost[1]*factor

func seen(p: Vector2,team: int = 0) -> bool:
	var c = nav.cell(p)
	return visible[team][c.y*48+c.x] == 1

func discovered(p: Vector2,team: int = 0) -> bool:
	var c = nav.cell(p)
	return explored[team][c.y*48+c.x] == 1

func update_vision():
	for team in range(2):
		visible[team].fill(0)
		for e in own(team):
			var c = nav.cell(e.p)
			var r = ceili(e.vision/2)
			for y in range(maxi(0,c.y-r),mini(48,c.y+r+1)):
				for x in range(maxi(0,c.x-r),mini(48,c.x+r+1)):
					if e.p.distance_to(Vector2(x*2-47,y*2-47)) <= e.vision:
						visible[team][y*48+x] = 1
						explored[team][y*48+x] = 1

func issue(ids: Array,order: Dictionary,append: bool = false,team: int = 0):
	if result != "" or not order.get("type","") in ["move","attackmove","attack","gather","deliver","build","stop"]: return
	if order.type in ["move","attackmove"] and (not order.get("p") is Vector2 or not order.p.is_finite()): return
	var units = []
	for id in ids:
		var e = entity(id)
		if not e.is_empty() and e.get("team",-1) == team and e.kind == "unit" and not units.has(e): units.append(e)
	var side = ceili(sqrt(units.size()))
	for i in range(units.size()):
		var e = units[i]
		var target = entity(order.get("target",0))
		if order.type == "attack" and (target.is_empty() or target.get("team",team) == team or not seen(target.p,team)): continue
		if order.type in ["gather","deliver","build"] and e.type != "worker": continue
		if order.type == "gather" and (target.is_empty() or target.kind != "resource"): continue
		if order.type == "build" and (target.is_empty() or target.get("team",-1) != team or target.kind != "building" or target.complete): continue
		var o = order.duplicate()
		if o.type in ["move","attackmove"] and units.size() > 1:
			o.p += Vector2((i%side)-(side-1)*0.5,floori(float(i)/side)-(side-1)*0.5)*2.1
			o.p = o.p.clamp(Vector2(-45,-45),Vector2(45,45))
		if not append or o.type == "stop":
			e.orders.clear()
			e.path.clear()
			e.path_clock = 0
			e.stalled = 0
		if o.type != "stop" and e.orders.size() < 32: e.orders.append(o)

func enqueue(id: int,type: String,team: int = 0) -> bool:
	var b = entity(id)
	var d = Catalog.get_def(type)
	if result != "" or b.is_empty() or b.get("team",-1) != team or not b.complete or not type in b.get("trains",[]) or d.is_empty(): return false
	if b.queue.size() >= 5:
		feedback("Production queue is full.",team)
		return false
	if not can_pay(team,d.cost):
		feedback("Insufficient resources. Assign more Harvesters.",team)
		return false
	var p = population(team)
	if d.get("pop",0) > 0 and p.used+p.reserved+d.get("pop",0) > p.cap:
		feedback("Supply limit: construct a Relay.",team)
		return false
	if type == "upgrade":
		if players[team].upgrade: return false
		for e in own(team):
			for q in e.queue:
				if q.type == "upgrade": return false
	pay(team,d.cost)
	b.queue.append({"type":type,"elapsed":0.0,"blocked":""})
	return true

func cancel_queue(id: int,index: int,team: int = 0) -> bool:
	var b = entity(id)
	if result != "" or b.is_empty() or b.get("team",-1) != team or index < 0 or index >= b.queue.size(): return false
	pay(team,Catalog.get_def(b.queue[index].type).cost,-1)
	b.queue.remove_at(index)
	return true

func construction_requirements(type: String,team: int = 0) -> String:
	var d = Catalog.get_def(type)
	if d.get("kind","") != "building": return "Choose a valid structure."
	if d.has("requires") and not own(team).any(func(e): return e.type == d.requires and e.complete):
		var prerequisite = Catalog.get_def(d.requires).name
		var underway = own(team).any(func(e): return e.type == d.requires and not e.complete)
		return ("Finish building %s before building %s." if underway else "Build %s before building %s.") % [prerequisite,d.name]
	var missing = []
	var alloy = maxi(0,ceili(d.cost[0]-players[team].alloy))
	var energy = maxi(0,ceili(d.cost[1]-players[team].energy))
	if alloy > 0: missing.append("%d alloy" % alloy)
	if energy > 0: missing.append("%d energy" % energy)
	if not missing.is_empty(): return "Need %s more to build %s. Assign Harvesters to deposits." % [" and ".join(missing),d.name]
	return ""

func placement(type: String,p: Vector2,team: int = 0) -> String:
	var d = Catalog.get_def(type)
	if d.get("kind","") != "building" or not p.is_finite(): return "Invalid site."
	var missing = construction_requirements(type,team)
	if missing != "": return missing
	if absf(p.x) > 46-d.radius or absf(p.y) > 46-d.radius: return "Outside buildable area."
	if nav.river and absf(p.y) < 7+d.radius: return "Keep river banks and crossing approaches clear."
	if not seen(p,team): return "Explore the site first."
	for o in nav.obstacles:
		if p.distance_to(o.p) < d.radius+o.r+1.5: return "Blocked by terrain or a structure."
	for r in deposits:
		if r.amount > 0 and p.distance_to(r.p) < d.radius+r.radius+1.5: return "Keep deposits clear."
	for e in entities:
		if e.hp > 0 and e.kind == "unit" and p.distance_to(e.p) < d.radius+e.radius+0.3: return "Units occupy this footprint."
	return ""

func build(id: int,type: String,p: Vector2,team: int = 0) -> Dictionary:
	var w = entity(id)
	if result != "" or w.is_empty() or w.get("team",-1) != team or w.type != "worker": return {}
	var error = placement(type,p,team)
	if error != "":
		feedback(error,team)
		return {}
	var goal = p+(w.p-p).normalized()*(Catalog.get_def(type).radius+1.4)
	if nav.path(w.p,goal,w.radius).is_empty():
		feedback("Harvester cannot reach this site.",team)
		return {}
	pay(team,Catalog.get_def(type).cost)
	var b = spawn(type,team,p,false)
	nav.rebuild(entities)
	issue([w.id],{"type":"build","target":b.id},false,team)
	feedback(b.name+" construction started.",team)
	return b

func cancel_building(id: int,team: int = 0) -> bool:
	var b = entity(id)
	if result != "" or b.is_empty() or b.get("team",-1) != team or b.kind != "building" or b.complete: return false
	pay(team,b.cost,-0.75)
	b.hp = 0
	nav.rebuild(entities)
	return true

func approach(e: Dictionary,target: Dictionary,margin: float = 1.4) -> Vector2:
	var direction = (e.p-target.p).normalized()
	if direction == Vector2.ZERO: direction = Vector2.RIGHT
	return target.p+direction*(target.radius+margin)

func finish(e: Dictionary):
	if not e.orders.is_empty(): e.orders.pop_front()
	e.path.clear()
	e.path_clock = 0
	e.stalled = 0
	e.work = 0
	e.moving = false

func move(e: Dictionary,goal: Vector2,dt: float,tolerance: float = 0.25) -> bool:
	if e.p.distance_to(goal) < tolerance:
		e.path.clear()
		return true
	e.path_clock -= dt
	if e.path_clock <= 0 or e.revision != nav.revision:
		e.path = nav.path(e.p,goal,e.radius)
		e.path_clock = 1.4+float(e.id%5)*0.1
		e.revision = nav.revision
	if e.path.is_empty():
		e.stalled += dt
		if e.stalled > 6: finish(e)
		return false
	while not e.path.is_empty() and e.p.distance_to(e.path[0]) < 0.25: e.path.pop_front()
	if e.path.is_empty(): return true
	var next = e.p.move_toward(e.path[0],e.speed*dt)
	if not nav.traverse(e.p,next,e.radius):
		e.path_clock = 0
		e.stalled += dt
		if e.stalled > 6: finish(e)
		return false
	e.angle = atan2(next.x-e.p.x,next.y-e.p.y)
	e.p = next
	e.moving = true
	e.stalled = 0
	return false

func enemy(e: Dictionary,radius: float) -> Dictionary:
	var best = {}
	var best_d = radius
	for t in entities:
		if t.hp <= 0 or t.team == e.team or not seen(t.p,e.team): continue
		var d = e.p.distance_to(t.p)-t.radius
		if d < best_d:
			best = t
			best_d = d
	return best

func apply_damage(t: Dictionary,damage: float,team: int):
	if t.hp <= 0: return
	t.hp -= damage
	if t.hp <= 0:
		players[team].kills += 1
		events.append({"type":"death","p":t.p,"team":t.team})
		if t.kind == "building": nav.rebuild(entities)

func hit(e: Dictionary,t: Dictionary):
	var damage = e.damage*(1.6 if e.get("counter","") == t.type else 1.0)
	if players[e.team].upgrade and e.kind == "unit" and e.type != "worker": damage *= 1.1
	apply_damage(t,damage,e.team)
	if e.type == "breaker":
		for other in entities:
			if other.id != t.id and other.team != e.team and other.p.distance_to(t.p) < 3: apply_damage(other,damage*0.5,e.team)
	events.append({"type":"shot","p":e.p,"to":t.p,"team":e.team})
	e.cooldown = e.interval

func fight(e: Dictionary,t: Dictionary,dt: float,chase: bool = true) -> bool:
	if t.is_empty() or t.get("hp",0) <= 0 or t.team == e.team or not seen(t.p,e.team): return false
	if e.p.distance_to(t.p) <= e.range+t.radius and nav.clear_line(e.p,t.p,e.id,t.id):
		e.angle = atan2(t.p.x-e.p.x,t.p.y-e.p.y)
		if e.cooldown <= 0: hit(e,t)
	elif chase and e.kind == "unit": move(e,approach(e,t,maxf(1.2,e.range*0.7)),dt)
	return true

func update_worker(e: Dictionary,o: Dictionary,dt: float):
	var t = entity(o.get("target",0))
	if o.type == "build":
		if t.is_empty() or t.get("team",-1) != e.team or t.kind != "building" or t.complete:
			finish(e)
			return
		if e.p.distance_to(t.p) > t.radius+2.2:
			move(e,approach(e,t),dt)
			return
		var builder = entity(t.builder)
		if not builder.is_empty() and builder.id != e.id and not builder.orders.is_empty() and builder.orders[0].type == "build" and builder.orders[0].get("target",0) == t.id and builder.p.distance_to(t.p) <= t.radius+2.2: return
		t.builder = e.id
		t.progress = minf(1,t.progress+dt/t.time)
		t.hp = minf(t.max_hp,t.hp+dt*t.max_hp/t.time)
		if t.progress >= 1:
			t.complete = true
			feedback(t.name+" is operational.",e.team)
			finish(e)
	elif o.type == "gather":
		if t.is_empty() or t.kind != "resource":
			if e.carry > 0: o.type = "deliver"
			else: finish(e)
			return
		e.resource = t.id
		if e.carry >= 10 or (e.carry > 0 and e.carry_type != t.type):
			o.type = "deliver"
			return
		if e.p.distance_to(t.p) > t.radius+1.4:
			move(e,approach(e,t,1.0),dt)
			return
		e.work += dt
		if e.work >= 0.7:
			e.work -= 0.7
			var amount = mini(2,mini(t.amount,10-e.carry))
			e.carry += amount
			e.carry_type = t.type
			t.amount -= amount
	elif o.type == "deliver":
		var depots = own(e.team).filter(func(b): return b.type == "hq" and b.complete)
		depots.sort_custom(func(a,b): return e.p.distance_squared_to(a.p) < e.p.distance_squared_to(b.p))
		if depots.is_empty():
			finish(e)
			return
		var depot = depots[0]
		if e.p.distance_to(depot.p) > depot.radius+2.2:
			move(e,approach(e,depot),dt)
			return
		if e.carry_type != "": players[e.team][e.carry_type] += e.carry
		e.carry = 0
		e.carry_type = ""
		if e.orders.size() > 1: finish(e)
		elif not entity(e.resource).is_empty():
			o.type = "gather"
			o.target = e.resource
			e.path.clear()
		else: finish(e)

func update_production(b: Dictionary,dt: float):
	if not b.complete or b.queue.is_empty(): return
	var q = b.queue[0]
	var d = Catalog.get_def(q.type)
	q.elapsed += dt
	if q.elapsed < d.time: return
	if q.type == "upgrade":
		players[b.team].upgrade = true
		b.queue.pop_front()
		return
	var pop = population(b.team)
	if pop.used+d.pop > pop.cap:
		q.blocked = "Awaiting supply"
		return
	for i in range(24):
		var angle = float(i)/24*TAU
		var p = b.p+Vector2(cos(angle),sin(angle))*(b.radius+2.5)
		if not nav.can_stand(p,d.radius): continue
		if entities.any(func(e): return e.hp > 0 and e.kind == "unit" and e.p.distance_to(p) < e.radius+d.radius+0.2): continue
		b.queue.pop_front()
		var u = spawn(q.type,b.team,p)
		if b.rally != null: issue([u.id],{"type":"move","p":b.rally},false,b.team)
		return
	q.blocked = "Exit blocked"

func update_ai():
	var units = own(1)
	var workers = units.filter(func(e): return e.type == "worker")
	var army = units.filter(func(e): return e.kind == "unit" and e.type != "worker")
	for i in range(workers.size()):
		var w = workers[i]
		if not w.orders.is_empty(): continue
		var type = "energy" if i%4 == 0 else "alloy"
		var resources = deposits.filter(func(r): return r.amount > 0 and r.type == type and discovered(r.p,1))
		resources.sort_custom(func(a,b): return w.p.distance_squared_to(a.p) < w.p.distance_squared_to(b.p))
		if not resources.is_empty(): issue([w.id],{"type":"gather","target":resources[0].id},false,1)
	var headquarters = units.filter(func(e): return e.type == "hq" and e.complete)
	if not headquarters.is_empty() and workers.size() < 9 and headquarters[0].queue.is_empty(): enqueue(headquarters[0].id,"worker",1)
	var pop = population(1)
	var want = ""
	if not units.any(func(e): return e.type == "barracks"): want = "barracks"
	elif pop.cap-pop.used-pop.reserved < 5 and pop.cap < 100: want = "relay"
	elif time > 100 and not units.any(func(e): return e.type == "foundry"): want = "foundry"
	if want != "" and not workers.is_empty() and can_pay(1,Catalog.get_def(want).cost) and not units.any(func(e): return not e.complete):
		var built = false
		for radius in [10,17,23]:
			for i in range(12):
				var p = Vector2(25,-24)+Vector2(cos(float(i)/12*TAU),sin(float(i)/12*TAU))*radius
				if placement(want,p,1) == "" and not build(workers[0].id,want,p,1).is_empty():
					built = true
					break
			if built: break
	for b in units:
		if b.complete and b.type in ["barracks","foundry"] and b.queue.size() < 2:
			enqueue(b.id,"breaker" if b.type == "foundry" else ("vanguard" if floori(time/4)%3 == 0 else "ranger"),1)
	var threat = {}
	if not headquarters.is_empty(): threat = enemy(headquarters[0],25)
	if not threat.is_empty():
		issue(army.filter(func(e): return e.orders.is_empty() or e.orders[0].type != "attack").map(func(e): return e.id),{"type":"attack","target":threat.id},false,1)
	elif time >= wave_at and army.size() >= 4:
		issue(army.map(func(e): return e.id),{"type":"attackmove","p":Vector2(-25,24)},false,1)
		wave_at = time+50

func tick(dt: float):
	if result != "" or dt <= 0 or not is_finite(dt): return
	time += dt
	vision_clock -= dt
	if vision_clock <= 0:
		update_vision()
		vision_clock = 0.25
	for e in entities.duplicate():
		if e.hp <= 0: continue
		e.cooldown -= dt
		e.moving = false
		if e.kind == "building":
			update_production(e,dt)
			if e.complete and e.has("damage"): fight(e,enemy(e,e.range),dt,false)
			continue
		if e.orders.is_empty():
			if e.type != "worker": fight(e,enemy(e,e.range+2),dt,false)
			continue
		var o = e.orders[0]
		if o.type in ["gather","deliver","build"]: update_worker(e,o,dt)
		elif o.type == "attack":
			if not fight(e,entity(o.target),dt): finish(e)
		elif o.type == "attackmove":
			var target = enemy(e,12)
			if not target.is_empty(): fight(e,target,dt)
			elif move(e,o.p,dt,1.1): finish(e)
		elif o.type == "move" and move(e,o.p,dt,1.1): finish(e)
	var units = entities.filter(func(e): return e.hp > 0 and e.kind == "unit")
	for i in range(units.size()):
		for j in range(i+1,units.size()):
			var a = units[i]
			var b = units[j]
			var delta = a.p-b.p
			var distance = delta.length()
			var separation = (a.radius+b.radius)*0.92
			if distance >= separation: continue
			var dir = delta/distance if distance > 0.001 else Vector2.RIGHT
			var push = dir*minf((separation-distance)*0.5,dt*2)
			if nav.traverse(a.p,a.p+push,a.radius): a.p += push
			if nav.traverse(b.p,b.p-push,b.radius): b.p -= push
	if ai_enabled:
		ai_clock -= dt
		if ai_clock <= 0:
			update_ai()
			ai_clock = 2.5
	var alive0 = own(0).any(func(e): return e.type == "hq")
	var alive1 = own(1).any(func(e): return e.type == "hq")
	if not alive0 or not alive1: result = "draw" if not alive0 and not alive1 else ("victory" if alive0 else "defeat")
	entities = entities.filter(func(e): return e.hp > 0)
	if events.size() > 256: events = events.slice(-128)

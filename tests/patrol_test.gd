extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
var failures = 0
var checks = 0
func check(ok: bool,text: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL: "+text)
	else: print("PASS: "+text)
func step(s,seconds: float):
	for i in range(ceili(seconds*20)): s.tick(0.05)
func setup(type: String = "ranger") -> Dictionary:
	var s = Simulation.new(false,false)
	s.entities = s.entities.filter(func(e): return e.kind == "building")
	var u = s.spawn(type,0,Vector2(0,20))
	s.nav.rebuild(s.entities); s.update_vision()
	return {"s":s,"u":u}
func hostile(s,u) -> Dictionary:
	var e = s.spawn("worker",1,Vector2(u.range+0.55,20))
	e.hp = 10000; e.max_hp = 10000
	s.update_vision()
	return e
func health(e) -> float: return e.hp+e.shield
func _initialize():
	for type in ["vanguard","ranger","breaker","tank","antitank"]:
		var f = setup(type)
		f.s.issue([f.u.id],{"type":"patrol","p":Vector2(0,32)})
		var previous = 32.0
		var reversals = 0
		for i in range(700):
			f.s.tick(0.05)
			if f.u.orders.is_empty(): break
			if f.u.orders[0].p.y != previous:
				reversals += 1
				previous = f.u.orders[0].p.y
		check(reversals >= 4 and not f.u.orders.is_empty(),type+": repeats both patrol legs")
		f = setup(type)
		var enemy = hostile(f.s,f.u)
		var before = health(enemy)
		f.s.issue([f.u.id],{"type":"patrol","p":Vector2(0,32)})
		f.s.tick(0.05)
		check(health(enemy) < before,type+": fires at exact weapon range")
		before = health(enemy); f.s.tick(0.05)
		check(health(enemy) == before,type+": respects weapon cooldown")
		step(f.s,7)
		check(f.u.p == Vector2(0,20) and f.u.orders.size() == 1,type+": combat preserves the route without stalled timeout")
		enemy.p = Vector2(40,-40); f.s.tick(0.05)
		check(f.u.moving,type+": resumes when the threat leaves")
		f = setup(type); enemy = hostile(f.s,f.u)
		f.s.issue([f.u.id],{"type":"patrol","p":Vector2(0,32)}); f.s.tick(0.05)
		before = health(enemy)
		var cooldown = f.u.cooldown
		f.s.issue([f.u.id],{"type":"move","p":Vector2(0,36)})
		check(f.u.cooldown == cooldown,type+": Move keeps cooldown")
		f.s.tick(0.05)
		check(f.u.moving and health(enemy) == before and f.u.orders[0].type == "move",type+": immediately withdraws from patrol combat")
		f.s.issue([f.u.id],{"type":"patrol","p":Vector2(0,32)})
		f.s.issue([f.u.id],{"type":"stop"})
		check(f.u.orders.is_empty(),type+": Stop clears patrol")
	for reason in ["hidden","distant","blocked"]:
		var f = setup()
		var enemy = hostile(f.s,f.u)
		if reason == "hidden": f.s.visible[0].fill(0); f.s.vision_clock = 100
		if reason == "distant": enemy.p.x += 2
		if reason == "blocked": f.s.spawn("barracks",0,Vector2(3,20)); f.s.nav.rebuild(f.s.entities)
		var before = health(enemy)
		f.s.issue([f.u.id],{"type":"patrol","p":Vector2(0,32)}); f.s.tick(0.05)
		check(health(enemy) == before and f.u.moving,"patrol ignores "+reason+" targets")
	var f = setup()
	var blocked = hostile(f.s,f.u); blocked.p.x = 6
	f.s.spawn("barracks",0,Vector2(3,20))
	var clear = f.s.spawn("worker",1,Vector2(0,26.3))
	var before = health(clear)
	f.s.nav.rebuild(f.s.entities); f.s.update_vision()
	f.s.issue([f.u.id],{"type":"patrol","p":Vector2(0,32)}); f.s.tick(0.05)
	check(health(clear) < before,"blocked target does not hide another clear enemy")
	f = setup("tank")
	var enemy = hostile(f.s,f.u); enemy.hp = 1; enemy.shield = 0
	f.s.issue([f.u.id],{"type":"patrol","p":Vector2(0,32)}); step(f.s,0.1)
	check(f.s.entity(enemy.id).is_empty() and f.u.moving,"patrol resumes after a kill")
	f = setup()
	f.s.issue([f.u.id],{"type":"move","p":Vector2(0,26)})
	f.s.issue([f.u.id],{"type":"patrol","p":Vector2(0,34)},true)
	for i in range(150):
		f.s.tick(0.05)
		if f.u.orders[0].get("origin") != null: break
	check(f.u.orders[0].origin.y > 24,"queued patrol starts at the end of earlier movement")
	f.s.issue([f.u.id],{"type":"move","p":Vector2(0,20)},true)
	step(f.s,15)
	check(f.u.orders.is_empty() and f.u.p.y < 22,"queued follow-up takes over at next patrol endpoint")
	for type in ["worker","medic","engineer"]:
		f = setup(type)
		f.s.issue([f.u.id],{"type":"move","p":Vector2(0,32)})
		f.s.issue([f.u.id],{"type":"patrol","p":Vector2(0,28)})
		check(f.u.orders[0].type == "move",type+": unsupported patrol preserves existing order")
	f = setup("tank")
	f.s.issue([f.u.id],{"type":"move","p":Vector2(0,32)})
	for invalid in [null,Vector2(NAN,2),Vector2(INF,2)]:
		f.s.issue([f.u.id],{"type":"patrol","p":invalid})
		check(f.u.orders[0].type == "move","invalid patrol position preserves orders")
	f.s.issue([f.u.id],{"type":"patrol","p":Vector2(999,-999)})
	check(absf(f.u.orders[0].p.x) <= f.s.nav.half-f.u.radius and absf(f.u.orders[0].p.y) <= f.s.nav.half-f.u.radius,"patrol map limits include tank radius")
	f = setup("worker"); enemy = hostile(f.s,f.u)
	f.u.carry = 7; f.u.carry_type = "alloy"
	before = health(enemy); f.s.tick(0.05)
	check(health(enemy) == before,"idle Harvester does not attack automatically")
	f.s.issue([f.u.id],{"type":"attack","target":enemy.id}); f.s.tick(0.05)
	check(health(enemy) == before-4 and f.u.carry == 7,"Harvester attacks on command with existing damage and keeps cargo")
	var cooldown = f.u.cooldown
	f.s.issue([f.u.id],{"type":"move","p":Vector2(0,32)})
	check(f.u.cooldown == cooldown,"Harvester Move keeps cooldown")
	f.s.tick(0.05)
	check(f.u.moving and health(enemy) == before-4,"Harvester can immediately withdraw")
	f.s.issue([f.u.id],{"type":"attack","target":enemy.id}); f.s.tick(0.05)
	check(health(enemy) == before-4,"Harvester micro cannot bypass cooldown")
	var ally = f.s.spawn("worker",0,Vector2(-3,20))
	f.s.issue([f.u.id],{"type":"move","p":Vector2(0,32)})
	for target in [ally.id,f.s.deposits[0].id,999999]:
		f.s.issue([f.u.id],{"type":"attack","target":target})
		check(f.u.orders[0].type == "move","Harvester rejects non-enemy attack target")
	enemy.hp = 1; enemy.shield = 0; f.u.cooldown = 0
	f.s.issue([f.u.id],{"type":"attack","target":enemy.id})
	f.s.issue([f.u.id],{"type":"move","p":Vector2(0,32)},true)
	step(f.s,0.2)
	check(f.u.orders[0].type == "move" and f.u.moving,"Harvester follows queued order after enemy dies")
	print("Patrol / Attack: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

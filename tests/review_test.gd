extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
var failures = 0
func check(ok: bool,text: String):
	if not ok: failures += 1;printerr("FAIL: "+text)
	else: print("PASS: "+text)
func setup(level: int = 1) -> Dictionary:
	var sim = Simulation.new(false,false)
	var core = sim.own(1).filter(func(e): return e.type == "hq")[0]
	var barracks = sim.own(1).filter(func(e): return e.type == "barracks")[0]
	sim.time=200;core.level=2;core.supply=100;barracks.level=level
	for i in range(5): sim.spawn("worker",1,Vector2(32+i,-16))
	sim.spawn("foundry",1,Vector2(10,-34)).level=2
	sim.players[1].alloy=100;sim.players[1].energy=0
	return {"sim":sim,"b":barracks}
func _initialize():
	check_commands()
	for map in ["basin","expanse"]:
		var sim = Simulation.new(false,true,map)
		var x = -sim.nav.half+9
		var units = [sim.spawn("ranger",0,Vector2(-39,10)),sim.spawn("tank",0,Vector2(-36,10))]
		var ids = units.map(func(e): return e.id)
		sim.issue(ids,{"type":"move","p":Vector2(x,10)})
		check(units.all(func(e): return e.orders[0].p.x < -45),"squad destination beyond old boundary: "+map)
		for i in range(800): sim.tick(0.05)
		check(units.all(func(e): return e.p.x < -48),"actual squad travel: "+map)
		sim.issue(ids,{"type":"attackmove","p":Vector2(x,14)})
		check(units.all(func(e): return e.orders[0].p.x < -45),"attack-move destination: "+map)
		sim.issue(ids,{"type":"move","p":Vector2(-999,999)})
		check(units.all(func(e): return absf(e.orders[0].p.x) <= sim.nav.half-3 and absf(e.orders[0].p.y) <= sim.nav.half-3),"active-map edge clamping")
	for level in [1,2]:
		var fixture = setup(level)
		fixture.sim.update_ai()
		check(fixture.b.queue.size() == 1 and fixture.b.queue[0].type == "vanguard","affordable defense without upgrade/support starvation")
		check(fixture.sim.players[1].alloy == 0 and fixture.sim.players[1].energy == 0,"AI pays exact cost")
	var fixture = setup()
	fixture.sim.players[1].alloy=200;fixture.sim.players[1].energy=50
	fixture.sim.enqueue(fixture.b.id,"vanguard",1)
	fixture.sim.update_ai()
	check(fixture.b.queue.size() == 1 and fixture.b.level_job.is_empty(),"affordable upgrade waits for queued production")
	fixture.sim.update_production(fixture.b,11);fixture.sim.update_ai()
	check(not fixture.b.level_job.is_empty() and fixture.b.queue.is_empty(),"upgrade starts after production finishes")
	fixture=setup(2);fixture.sim.own(1).filter(func(e): return e.type == "hq")[0].supply=1
	fixture.sim.update_ai();check(fixture.b.queue.is_empty(),"AI cannot bypass supply cap")
	fixture=setup(2)
	var sim = fixture.sim
	sim.own(1).filter(func(e): return e.type == "hq")[0].hp=0
	fixture.b.hp=0
	var relocated = sim.spawn("hq",1,Vector2(-15,-28))
	relocated.level=2;relocated.supply=100
	sim.players[1].alloy=1000;sim.players[1].energy=500
	sim.nav.rebuild(sim.entities);sim.update_vision();sim.update_ai()
	check(sim.own(1).any(func(e): return e.type == "barracks" and not e.complete and e.p.distance_to(relocated.p)<24),"AI rebuilds beside surviving headquarters")
	print("REVIEW: %d failures" % failures)
	quit(1 if failures else 0)

func check_commands():
	var sim = Simulation.new(false,false,"classic")
	sim.entities = sim.entities.filter(func(e): return e.kind == "building")
	var unit = sim.spawn("ranger",0,Vector2(0,20))
	var blocked = sim.spawn("worker",1,Vector2(6,20))
	var clear = sim.spawn("worker",1,Vector2(0,26.3))
	sim.spawn("barracks",0,Vector2(3,20))
	sim.nav.rebuild(sim.entities); sim.update_vision()
	sim.issue([unit.id],{"type":"attackmove","p":Vector2(20,20)})
	sim.issue([unit.id],{"type":"move","p":Vector2(20,30)},true)
	var before = clear.hp+clear.shield; var blocked_before = blocked.hp+blocked.shield
	unit.stalled = 5.99; unit.move_sample = unit.p
	sim.tick(0.05)
	check(clear.hp+clear.shield < before and blocked.hp+blocked.shield == blocked_before,"attack-move prefers a clear shot over a screened enemy")
	check(unit.p == Vector2(0,20) and unit.orders.size() == 2 and unit.stalled == 0,"engagement preserves the route and resets movement stall tracking")
	before = clear.hp+clear.shield
	sim.issue([unit.id],{"type":"move","p":Vector2(0,16)})
	sim.tick(0.05)
	check(unit.moving and clear.hp+clear.shield == before,"explicit Move still withdraws instead of auto-firing")
	for map in ["classic","expanse"]:
		for type in ["ranger","tank"]:
			var edge_sim = Simulation.new(false,false,map)
			var edge = edge_sim.nav.half
			var traveler = edge_sim.spawn(type,0,Vector2(edge-10,edge-10))
			var limit = edge-maxf(1,traveler.radius+0.1)
			for command in ["move","attackmove"]:
				edge_sim.issue([traveler.id],{"type":command,"p":Vector2(999,999)})
				check(traveler.orders[0].p == Vector2(limit,limit),"single %s %s clamps to the %s boundary" % [type,command,map])
			edge_sim.issue([traveler.id],{"type":"move","p":Vector2(999,999)})
			for i in range(600):
				if traveler.orders.is_empty(): break
				edge_sim.tick(0.05)
			check(traveler.orders.is_empty() and traveler.p.distance_to(Vector2(limit,limit)) < 2.2,"single %s reaches the %s corner" % [type,map])
			check(not edge_sim.message.contains("cannot reach"),"corner movement finishes without a false blockage warning")

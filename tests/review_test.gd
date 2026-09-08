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
	sim.players[1].alloy=75;sim.players[1].energy=0
	return {"sim":sim,"b":barracks}
func _initialize():
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
	fixture.sim.players[1].alloy=175;fixture.sim.players[1].energy=50
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

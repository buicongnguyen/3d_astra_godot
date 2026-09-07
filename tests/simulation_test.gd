extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/catalog.gd")
var failures = 0
var checks = 0

func check(condition: bool,message: String):
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: "+message)
	else: print("PASS: "+message)

func step(sim,seconds: float):
	for i in range(int(seconds*20)): sim.tick(0.05)

func first(sim,type: String,team: int = 0) -> Dictionary:
	return sim.own(team).filter(func(e): return e.type == type)[0]

func _initialize():
	call_deferred("run")

func run():
	var sim = Simulation.new(false)
	check(sim.own(0).size() == 9,"initial symmetric roster")
	check(sim.population(0).used == 7 and sim.population(0).cap == 15,"initial population")
	var hq = first(sim,"hq")
	var worker = first(sim,"worker")
	var alloy = sim.players[0].alloy
	check(sim.enqueue(hq.id,"worker"),"production accepted")
	check(sim.players[0].alloy == alloy-50 and sim.population(0).reserved == 1,"queue charged and population reserved")
	check(sim.cancel_queue(hq.id,0) and sim.players[0].alloy == alloy and sim.population(0).reserved == 0,"cancel refunds exactly once")
	check(not sim.cancel_queue(hq.id,0),"duplicate queue cancel rejected")
	check(not sim.enqueue(first(sim,"hq",1).id,"worker"),"enemy production rejected")
	sim.issue([first(sim,"worker",1).id],{"type":"move","p":Vector2.ZERO})
	check(first(sim,"worker",1).orders.is_empty(),"enemy orders rejected")
	check(not sim.enqueue(hq.id,"breaker"),"producer type validated")
	sim.enqueue(hq.id,"worker")
	step(sim,9)
	check(sim.population(0).used == 8 and sim.population(0).reserved == 0,"production spawns and releases reservation")
	sim.issue([worker.id],{"type":"gather","target":sim.deposits[0].id})
	alloy = sim.players[0].alloy
	step(sim,50)
	check(sim.players[0].alloy > alloy,"workers return finite gathered resources")
	check(sim.deposits[0].amount < sim.deposits[0].initial,"deposit is depleted by gathering")
	check(not sim.nav.can_stand(Vector2(10,0),0.95),"deep water blocks full footprint")
	check(sim.nav.can_stand(Vector2(0,0),0.95) and sim.nav.can_stand(Vector2(-22,0),0.95),"ford and bridge traversable")
	check(not sim.nav.traverse(Vector2(10,-5),Vector2(10,5),0.55),"swept movement cannot jump water")
	check(sim.placement("relay",Vector2(0,0)) != "","crossings cannot be built over")
	var prerequisite = first(sim,"barracks")
	prerequisite.complete = false
	check(sim.placement("foundry",Vector2(-13,13)) == "Finish building Barracks before building Foundry.","foundry names the unfinished prerequisite")
	prerequisite.hp = 0
	check(sim.construction_requirements("foundry") == "Build Barracks before building Foundry.","missing prerequisite names the building to construct")
	prerequisite.hp = prerequisite.max_hp
	prerequisite.complete = true
	var saved = sim.players[0].duplicate()
	sim.players[0].alloy = 20
	sim.players[0].energy = 10
	check(sim.construction_requirements("foundry").begins_with("Need 180 alloy and 90 energy more to build Foundry."),"construction lists exact missing resources")
	check(sim.placement("foundry",Vector2.ZERO).begins_with("Need 180 alloy"),"requirements appear before site restrictions")
	sim.players[0] = saved
	var old = sim.players[0].alloy
	var bad = sim.build(worker.id,"relay",Vector2(0,0))
	check(bad.is_empty() and sim.players[0].alloy == old,"invalid construction has no charge")
	var site = sim.build(worker.id,"relay",Vector2(-22,34))
	check(not site.is_empty(),"reachable construction site accepted")
	if not site.is_empty():
		check(sim.cancel_building(site.id),"construction can be canceled")
		check(is_equal_approx(sim.players[0].alloy,old-25),"construction refund is exactly 75 percent")
		check(not sim.cancel_building(site.id),"canceled site cannot refund twice")
	sim = Simulation.new(false)
	var army = []
	for i in range(5): army.append(sim.spawn("breaker",0,Vector2(-23+i*2,9)))
	sim.nav.rebuild(sim.entities)
	sim.issue(army.map(func(e): return e.id),{"type":"move","p":Vector2(-22,-20)})
	var safe = true
	for i in range(1800):
		sim.tick(0.05)
		for e in army:
			if not sim.nav.terrain_free(e.p,e.radius): safe = false
	check(safe,"five Breakers remain inside full-radius terrain clearance every tick")
	check(army.all(func(e): return e.p.y < -14),"five Breakers reach the opposite bank")
	sim = Simulation.new(false)
	var target = first(sim,"hq",1)
	worker = first(sim,"worker")
	sim.issue([worker.id],{"type":"attack","target":target.id})
	check(worker.orders.is_empty(),"fog rejects attacks on hidden enemies")
	for team in range(2): first(sim,"hq",team).hp = 0
	sim.tick(0.05)
	check(sim.result == "draw","simultaneous headquarters destruction is draw")
	old = sim.time
	sim.tick(1)
	check(sim.time == old,"finished matches stop simulation")
	# Review pass 3: information boundaries and production lifecycle.
	sim = Simulation.new(false)
	sim.message = "Player briefing"
	sim.players[1].alloy = 0
	sim.enqueue(first(sim,"hq",1).id,"worker",1)
	check(sim.message == "Player briefing","AI failures cannot leak into player notices")
	hq = first(sim,"hq")
	sim.enqueue(hq.id,"worker")
	var blockers = []
	for i in range(24):
		var p = hq.p+Vector2(cos(float(i)/24*TAU),sin(float(i)/24*TAU))*(hq.radius+2.5)
		blockers.append(sim.spawn("worker",1,p))
	sim.update_production(hq,20)
	check(hq.queue.size() == 1 and hq.queue[0].blocked == "Exit blocked","completed production holds at blocked exits")
	blockers[0].hp = 0
	sim.update_production(hq,0.05)
	check(hq.queue.is_empty(),"production resumes when an exit clears")
	sim.enqueue(hq.id,"worker")
	hq.hp = 0
	check(sim.population(0).reserved == 0,"destroyed producer releases reservations")
	sim = Simulation.new(false)
	var barracks = first(sim,"barracks")
	sim.enqueue(barracks.id,"ranger")
	first(sim,"hq").supply = 7
	sim.update_production(barracks,20)
	check(barracks.queue.size() == 1 and barracks.queue[0].blocked == "Awaiting supply","lost supply blocks completed production")
	var foundry = sim.spawn("foundry",0,Vector2(-10,34))
	check(sim.enqueue(foundry.id,"upgrade"),"weapon research can be queued")
	check(not sim.enqueue(foundry.id,"upgrade"),"research cannot be queued twice")
	sim.update_production(foundry,30)
	check(sim.players[0].upgrade and not sim.enqueue(foundry.id,"upgrade"),"research applies once")
	var ranger = first(sim,"ranger")
	var enemy_hq = first(sim,"hq",1)
	old = enemy_hq.hp
	sim.hit(ranger,enemy_hq)
	check(is_equal_approx(old-enemy_hq.hp,13.2),"research updates existing combat units")
	var new_ranger = sim.spawn("ranger",0,Vector2(-10,18))
	old = enemy_hq.hp
	sim.hit(new_ranger,enemy_hq)
	check(is_equal_approx(old-enemy_hq.hp,13.2),"research applies to newly produced combat units")
	worker = first(sim,"worker")
	sim.issue([worker.id],{"type":"gather","target":sim.deposits[0].id})
	sim.deposits[0].amount = 0
	sim.tick(0.05)
	check(worker.orders.is_empty(),"depleted command target is safely discarded")
	check(not sim.nav.terrain_free(Vector2.ZERO,-1),"invalid footprint radius rejected")
	sim = Simulation.new(false)
	check(sim.population(0).used == 7 and sim.players[0].alloy == 450 and sim.time == 0,"new match resets economy, entities, and time")
	for river in [false,true]:
		sim = Simulation.new(true,river)
		step(sim,600)
		check(sim.result == "defeat","AI wins against idle player on "+("river" if river else "classic"))
	# A player-style economy and training sequence wins through ordinary combat.
	sim = Simulation.new(false)
	var workers = sim.own(0).filter(func(e): return e.type == "worker")
	for i in range(4): sim.issue([workers[i].id],{"type":"gather","target":sim.deposits[3 if i == 3 else i].id})
	site = sim.build(workers[0].id,"relay",Vector2(-22,34))
	step(sim,30)
	check(not site.is_empty() and site.complete and sim.population(0).cap == 25,"worker completes construction and increases supply")
	sim.issue([workers[0].id],{"type":"gather","target":sim.deposits[0].id})
	barracks = first(sim,"barracks")
	barracks.rally = Vector2(-15,13)
	for i in range(7200):
		if i%40 == 0 and sim.own(0).filter(func(e): return e.type == "ranger").size() < 14: sim.enqueue(barracks.id,"ranger")
		sim.tick(0.05)
	army = sim.own(0).filter(func(e): return e.kind == "unit" and e.type != "worker")
	sim.issue(army.map(func(e): return e.id),{"type":"attackmove","p":Vector2(25,-24)})
	step(sim,240)
	check(sim.result == "victory","gathered resources fund a trained army that wins through normal combat")
	print("RESULT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

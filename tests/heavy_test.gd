extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
var failures = 0
func check(ok: bool, text: String):
	if not ok: failures += 1; printerr("FAIL: "+text)
	else: print("PASS: "+text)
func _initialize():
	var sim = Simulation.new(false,false)
	var rocket = sim.spawn("antitank",0,Vector2(0,20))
	for pair in [["tank",60],["breaker",60],["ranger",20],["tower",20]]:
		var target = sim.spawn(pair[0],1,Vector2(0,24))
		var near = sim.spawn("ranger",1,Vector2(1,24))
		var ally = sim.spawn("ranger",0,Vector2(0.5,24))
		var before = target.hp+target.shield
		sim.hit(rocket,target)
		check(is_equal_approx(before-target.hp-target.shield,pair[1]),"rocket matchup: "+pair[0])
		check(near.shield == 25 and ally.shield == 25 and rocket.cooldown == 2.4,"rockets have no splash/friendly fire and reload correctly")
	var tank = sim.spawn("tank",0,Vector2(0,20))
	var medic = sim.spawn("medic",0,Vector2(0,21))
	var engineer = sim.spawn("engineer",0,Vector2(1,21))
	check(not sim.support_valid(medic,tank) and sim.support_valid(engineer,tank),"tank needs Engineer repair")
	check(sim.support_valid(medic,rocket) and not sim.support_valid(engineer,rocket),"anti-tank soldier needs Medic healing")
	tank.hp = 400; sim.assist(engineer,tank,0.05)
	check(tank.hp == 418,"tank hull repairs correctly")
	var enemy = sim.spawn("ranger",1,Vector2(0,24))
	sim.hit(tank,enemy)
	check(enemy.hp+enemy.shield == 62 and tank.cooldown == 2.2,"tank cannon damage and cooldown")
	sim.players[0].upgrade = true
	var enemy_tank = sim.spawn("tank",1,Vector2(0,24))
	sim.hit(rocket,enemy_tank)
	check(is_equal_approx(enemy_tank.shield,34),"weapon research scales rocket bonus once")
	sim = Simulation.new(false,false)
	sim.players[0].alloy = 5000; sim.players[0].energy = 5000
	var foundry = sim.spawn("foundry",0,Vector2(-9,34))
	var barracks = sim.own(0).filter(func(e): return e.type == "barracks")[0]
	for row in [[barracks,"antitank",2,2],[foundry,"tank",3,4]]:
		var building = row[0]
		building.level = row[2]-1
		check(not sim.enqueue(building.id,row[1]) and sim.message.contains("level %d" % row[2]) and sim.players[0].alloy == 5000,"locked training explains prerequisite without charging")
		building.level = row[2]
		check(sim.enqueue(building.id,row[1]) and sim.population(0).reserved == row[3],"heavy supply reserved")
		sim.cancel_queue(building.id,0)
		check(sim.players[0].alloy == 5000 and sim.population(0).reserved == 0,"heavy cancellation refunds and releases supply")
	var core = sim.own(0).filter(func(e): return e.type == "hq")[0]
	core.supply = 10
	check(not sim.enqueue(foundry.id,"tank"),"tank cannot bypass supply cap")
	core.supply = 15
	check(sim.enqueue(foundry.id,"tank"),"unlocked tank production starts")
	for i in range(420): sim.tick(0.05)
	check(sim.own(0).any(func(e): return e.type == "tank"),"tank finishes production")
	print("HEAVY: %d failures" % failures)
	quit(1 if failures else 0)

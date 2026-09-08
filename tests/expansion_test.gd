extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/catalog.gd")
var failures = 0
func check(ok: bool,text: String):
	if not ok: failures += 1; printerr("FAIL: "+text)
	else: print("PASS: "+text)
func _initialize():
	Catalog.load_data()
	for id in Catalog.maps:
		var sim = Simulation.new(false,true,id)
		var config = Catalog.maps[id]
		check(sim.visible[0].size() == sim.nav.grid_size*sim.nav.grid_size,"fog dimensions: "+id)
		check(sim.deposits.size() == 12+config.sites.size()*6,"extra mining sites: "+id)
		for r in sim.deposits:
			check(sim.deposits.any(func(other): return other.type == r.type and other.p == -r.p and other.amount == r.amount),"symmetric reserve")
			check(sim.nav.can_stand(r.p,r.radius),"deposit placement clear")
		var core = sim.own(0).filter(func(e): return e.type == "hq")[0]
		check(sim.discovered(core.p),"starting base explored: "+id)
		check(sim.deposits[0].amount == 2000 and sim.deposits[3].amount == 1750,"25 percent more starting reserves")
		check(not sim.nav.can_stand(Vector2(sim.nav.half+1,20)),"map edge blocks movement")
		var ranger = sim.own(0).filter(func(e): return e.type == "ranger")[0]
		for site in config.sites:
			check(not sim.nav.path(ranger.p,Vector2(site[0]-3,site[1]+1),1.05).is_empty(),"tank route to outer mining site: "+id)
		if config.size > 96:
			var worker = sim.spawn("worker",0,Vector2(-sim.nav.half+9,30))
			sim.resource("alloy",worker.p+Vector2(3,0),100)
			sim.update_vision()
			var funds = sim.players[0].alloy
			sim.issue([worker.id],{"type":"gather","target":sim.deposits[-1].id})
			for i in range(2000): sim.tick(0.05)
			check(sim.players[0].alloy > funds,"outer deposit delivers resources")
			sim.visible[0].fill(1)
			check(sim.placement("relay",Vector2(-sim.nav.half+9,38)) == "","outer building site is usable")
	var large = Simulation.new(false,true,"expanse")
	check(not large.nav.can_stand(Vector2(65,0)),"river collision spans large map")
	for row in [["antitank",2,false],["breaker",1,true]]:
		var sim = Simulation.new(false,false)
		sim.entities = sim.entities.filter(func(e): return e.type == "hq")
		var tank = sim.spawn("tank",0,Vector2(0,20))
		var enemies = []
		for i in range(row[1]): enemies.append(sim.spawn(row[0],1,Vector2(10,17+i*2)))
		sim.nav.rebuild(sim.entities);sim.visible[0].fill(1);sim.visible[1].fill(1);sim.vision_clock = 99999
		sim.issue([tank.id],{"type":"attackmove","p":Vector2(14,20)})
		sim.issue(enemies.map(func(e): return e.id),{"type":"attackmove","p":Vector2(0,20)},false,1)
		for i in range(2400):
			if tank.hp <= 0 or not enemies.any(func(e): return e.hp > 0): break
			sim.tick(0.05)
		check((tank.hp > 0) == row[2],"tank cost/counter matchup: "+row[0])
	print("EXPANSION: %d failures" % failures)
	quit(1 if failures else 0)

extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Main = preload("res://scenes/main.tscn")
var failures = 0
func check(ok: bool,text: String):
	if not ok: failures += 1; printerr("FAIL: "+text)
	else: print("PASS: "+text)
func _initialize(): call_deferred("run")
func run():
	for map in ["riverlands","classic","basin","expanse","dunes","woodlands","highlands"]:
		var sim = Simulation.new(false,true,map,{"enemies":3})
		check(sim.players.size() == 4 and sim.own(3).size() == 9,"four factions on "+map)
		check(sim.own(3).all(func(e): return absf(e.p.x) < sim.nav.half and absf(e.p.y) < sim.nav.half),"spawns fit "+map)
		for team in range(1,4): sim.update_ai(team)
		check(sim.own(3).any(func(e): return e.type == "worker" and not e.orders.is_empty()),"third AI gathers "+map)
	var sim = Simulation.new(false,false,"classic",{"enemies":3,"alliance":"coalition","speed":"fast"})
	check(not sim.hostile(1,2) and sim.hostile(0,2) and sim.pace.firstWave == 70,"coalition and pace")
	sim.update_vision()
	check(sim.visible[1] == sim.visible[2] and sim.explored[2] == sim.explored[3],"coalition shares vision")
	var core = sim.own(0).filter(func(e): return e.type == "hq")[0]
	var workers = sim.own(0).filter(func(e): return e.type == "worker")
	core.hp -= 500
	for w in workers: w.p = core.p+Vector2(4,0)
	sim.issue(workers.map(func(e): return e.id),{"type":"repair","target":core.id})
	var hp = core.hp
	for i in range(40): sim.tick(0.05)
	check(is_equal_approx(core.hp-hp,40),"repair crew capped at two")
	check(sim.players[0].alloy < 450,"repair charges resources")
	sim.issue([workers[0].id],{"type":"move","p":Vector2(-10,20)})
	check(workers[0].orders[0].type == "move","repair can be interrupted")
	core.rally = sim.deposits[0].p; core.rally_target = sim.deposits[0].id
	check(sim.enqueue(core.id,"worker"),"rally worker queued")
	sim.update_production(core,10)
	var trained = sim.own(0).filter(func(e): return e.type == "worker")[-1]
	check(trained.orders.size() == 1 and trained.orders[0].type == "gather","resource rally starts gathering")
	var tower = sim.spawn("tower",0,Vector2(0,25))
	var enemy_worker = sim.spawn("worker",1,Vector2(2,25))
	var ranger = sim.spawn("ranger",1,Vector2(5,25))
	sim.nav.rebuild(sim.entities); sim.update_vision()
	check(sim.defense_target(tower).get("id") == ranger.id,"tower prioritizes combat unit over worker")
	check(sim.level_cost(tower) == [75,25],"tower upgrade cost")
	var tank = sim.spawn("tank",1,Vector2(0,15))
	var ally = sim.spawn("ranger",2,Vector2(1,16))
	var victim = sim.spawn("vanguard",0,Vector2(0,16))
	var before = ally.hp+ally.shield
	sim.hit(tank,victim)
	check(ally.hp+ally.shield == before,"splash excludes coalition allies")
	for e in sim.own(1):
		if e.type == "hq": e.hp = 0
	sim.tick(0.05)
	check(sim.players[1].eliminated and sim.own(1).is_empty() and sim.result == "","one eliminated faction does not end match")
	var game = Main.instantiate(); root.add_child(game); await process_frame
	game.play_mode.select(0); game.enemy_choice.select(2); game.alliance_choice.select(1); game.scenario.select(6); game.start_match()
	game.view.refresh(0)
	check(game.sim.map_id == "highlands" and game.sim.players.size() == 4 and game.sim.coalition,"UI applies seven maps and faction settings")
	check(game.view.colors.size() == 4,"renderer supports four teams")
	game.restart_match(); game.play_mode.select(1); game.campaign_choice.select(0); game.start_match()
	check(game.campaign_index == 0 and game.sim.ai_speed == "relaxed","campaign applies stage rules")
	game.campaign_progress = {}; game.campaign_choice.select(6); var previous = game.sim; game.start_match()
	check(game.sim == previous,"locked campaign stage cannot start")
	game.queue_free(); await process_frame
	print("PARITY: %d failures" % failures)
	quit(1 if failures else 0)

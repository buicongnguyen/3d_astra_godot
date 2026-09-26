extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Tutorial = preload("res://scripts/tutorial.gd")
const Main = preload("res://scenes/main.tscn")
var failures = 0
func check(ok: bool,text: String):
	if not ok: failures += 1; printerr("FAIL: "+text)
	else: print("PASS: "+text)
func advance(sim,t,index: int):
	for i in range(1000):
		if t.index >= index: break
		t.update(sim,[]); sim.tick(0.05); t.update(sim,[])
	check(t.index == index,"lesson transition %d" % index)
func _initialize(): call_deferred("run")
func run():
	var sim = Simulation.new(true,false,"classic"); var t = Tutorial.new(sim)
	check(not sim.ai_enabled and sim.own(1).size() == 1,"safe training field")
	var w = sim.own(0).filter(func(e): return e.type == "worker")[0]
	t.update(sim,[w.id]); check(t.index == 1,"real selection")
	sim.issue([w.id],{"type":"move","p":Vector2(-23,9)}); advance(sim,t,2)
	sim.issue([w.id],{"type":"gather","target":sim.deposits[0].id}); advance(sim,t,3)
	check(not sim.build(w.id,"relay",Vector2(-20,33)).is_empty(),"build training relay"); advance(sim,t,4)
	var b = sim.own(0).filter(func(e): return e.type == "barracks")[0]
	check(sim.enqueue(b.id,"ranger"),"train new Ranger"); advance(sim,t,5)
	var soldier = sim.own(0).filter(func(e): return e.type == "ranger")[0]
	sim.issue([soldier.id],{"type":"attack","target":t.target_id}); advance(sim,t,6)
	var target = sim.entity(t.target_id); sim.apply_damage(target,1e9,0)
	check(target.hp == 1 and not target.is_empty(),"practice target survives until withdrawal")
	t.update(sim,[]); check(t.index == 6,"withdrawal needs a new movement order")
	sim.issue([soldier.id],{"type":"move","p":Vector2(-23,9)}); advance(sim,t,7)
	sim.issue([soldier.id],{"type":"attack","target":t.target_id}); advance(sim,t,8)
	check(t.done and sim.result == "victory","training completes")
	var normal = Simulation.new(); check(normal.ai_enabled,"normal AI unchanged")
	var early_sim = Simulation.new(true,false,"classic"); var early = Tutorial.new(early_sim)
	var early_worker = early_sim.own(0).filter(func(e): return e.type == "worker")[0]
	early_sim.spawn("relay",0,Vector2(-20,33)); early_sim.spawn("ranger",0,Vector2(-20,15)); early_sim.deposits[0].amount -= 10
	early.update(early_sim,[early_worker.id]); early_worker.p = Vector2(-23,9); early.update(early_sim,[])
	check(early.index == 1,"pre-positioned worker needs a movement order")
	early_sim.issue([early_worker.id],{"type":"move","p":Vector2(-23,9)})
	for i in range(4): early.update(early_sim,[])
	check(early.index == 5,"early harvest, construction and production count")
	check(Tutorial.new(Simulation.new()).index == 0,"replay starts from selection")
	var game = Main.instantiate(); root.add_child(game); await process_frame
	game.play_mode.select(2); game.start_match(); game.refresh_ui()
	check(game.tutorial != null and game.selected.is_empty() and game.sim.map_id == "classic","training menu starts clean lesson")
	game.play_mode.select(0); game.restart_match(); game.start_match()
	check(game.tutorial == null and game.sim.ai_enabled,"leaving restores normal rules")
	game.queue_free(); await process_frame
	print("TUTORIAL: %d failures" % failures); quit(1 if failures else 0)

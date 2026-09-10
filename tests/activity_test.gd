extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Activity = preload("res://scripts/activity.gd")
var failures = 0
var checks = 0
func check(value: bool,text: String):
	checks += 1
	if not value: failures += 1; print("FAIL: "+text)
func step(s,seconds: float):
	for i in range(int(seconds*20)): s.tick(0.05)
func _init():
	var s = Simulation.new(false,false)
	var w = s.own(0).filter(func(e): return e.type == "worker")[0]
	var r = s.deposits[0]
	s.issue([w.id],{"type":"gather","target":r.id})
	check(Activity.harvest_target(s,w) == r,"Resource ring before arrival")
	check(not Activity.harvesting(s,w),"No work while travelling")
	w.p = r.p+Vector2(r.radius+1,0)
	step(s,0.1)
	check(Activity.harvesting(s,w),"Actual harvesting")
	step(s,0.8)
	check(w.carry > 0,"Work gains cargo")
	s.issue([w.id],{"type":"stop"})
	check(not Activity.harvesting(s,w) and Activity.harvest_target(s,w).is_empty(),"Stop clears feedback immediately")
	s.issue([w.id],{"type":"gather","target":r.id}); w.carry = 10; step(s,0.1)
	check(w.orders[0].type == "deliver" and Activity.harvest_target(s,w) == r,"Delivery retains target ring")
	check(not Activity.harvesting(s,w),"Full cargo is not mining")
	r.amount = 0
	check(Activity.harvest_target(s,w).is_empty(),"Depleted ring clears")
	var b = s.spawn("relay",0,Vector2(0,20),false)
	check(Activity.building(s,b).label == "Needs Harvester","Unstaffed construction")
	w.p = b.p+Vector2(b.radius+1,0); s.issue([w.id],{"type":"build","target":b.id}); step(s,0.1)
	check(Activity.building(s,b).label == "Building" and b.progress > 0,"Building progress")
	s.issue([w.id],{"type":"stop"})
	check(Activity.building(s,b).label == "Needs Harvester","Withdrawn builder")
	var money = s.players[0].alloy
	check(s.cancel_building(b.id),"Cancel construction")
	check(s.players[0].alloy == money+75,"Site refunds 75 percent")
	check(not s.cancel_building(b.id),"No duplicate site refund")
	var h = s.own(0).filter(func(e): return e.type == "hq")[0]
	s.enqueue(h.id,"worker");s.enqueue(h.id,"worker");step(s,2)
	check(Activity.building(s,h).label == "Harvester","Production progress")
	var first = h.queue[0].id
	var second = h.queue[1].id
	money = s.players[0].alloy
	check(s.cancel_job(h.id,first),"Cancel active Harvester")
	check(h.queue.size() == 1 and h.queue[0].id == second and s.players[0].alloy == money+50,"Refund exactly one job")
	check(not s.cancel_job(h.id,first),"Stale tap cannot cancel next job")
	var count = s.own(0).filter(func(e): return e.type == "worker").size()
	step(s,10)
	check(s.own(0).filter(func(e): return e.type == "worker").size() == count+1,"Only remaining job spawns")
	s.events.clear()
	for i in range(10): s.apply_damage(h,1,1)
	check(s.events.filter(func(e): return e.type == "impact").size() == 1,"Impact throttle")
	var tank = s.spawn("tank",0,Vector2(0,20));s.apply_damage(tank,10000,1)
	check(s.events.filter(func(e): return e.type == "death")[0].heavy,"Tank death classified")
	print("Activity: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)

extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
var failures = 0
var checks = 0
func check(ok: bool,text: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL: "+text)
	else: print("PASS: "+text)
func step(sim,seconds: float,dt: float = 0.05):
	for i in range(ceili(seconds/dt)): sim.tick(dt)
func workers(sim,team: int = 0) -> Array:
	return sim.own(team).filter(func(e): return e.type == "worker")
func _initialize():
	for map in ["classic","riverlands","basin","expanse"]:
		var s = Simulation.new(false,true,map)
		var all_workers = []
		var deliveries = {}
		for team in range(2):
			var ws = workers(s,team)
			var rs = s.deposits.filter(func(r): return r.type == "alloy")
			rs.sort_custom(func(a,b): return ws[0].p.distance_squared_to(a.p) < ws[0].p.distance_squared_to(b.p))
			rs[0].amount = 10000
			s.issue(ws.map(func(w): return w.id),{"type":"gather","target":rs[0].id},false,team)
			all_workers.append_array(ws)
		for w in all_workers: deliveries[w.id] = 0
		for i in range(6000):
			var cargo = all_workers.map(func(w): return w.carry)
			s.tick(0.05)
			for j in range(all_workers.size()):
				if cargo[j] > 0 and all_workers[j].carry == 0: deliveries[all_workers[j].id] += 1
		check(all_workers.all(func(w): return deliveries[w.id] >= 5 and not w.orders.is_empty()),map+": every crowded worker keeps delivering for five minutes")
	for fps in [30,60,144,240]:
		var s = Simulation.new(false,true,"expanse")
		var w = workers(s)[0]
		w.p = Vector2(-12,42)
		s.issue([w.id],{"type":"gather","target":s.deposits[0].id})
		step(s,40,1.0/fps)
		check(s.players[0].alloy > 450 and not w.orders.is_empty(),"long approach and harvesting at %d FPS" % fps)
	for queued in [false,true]:
		var s = Simulation.new(false)
		var w = workers(s)[0]
		var r = s.deposits[0]
		r.amount = 3
		var initial = 0
		for d in s.deposits: initial += d.amount
		s.issue([w.id],{"type":"gather","target":r.id})
		if queued: s.issue([w.id],{"type":"move","p":Vector2(-16,12)},true)
		step(s,45)
		var remaining = 0
		for d in s.deposits: remaining += d.amount
		check(initial-remaining == s.players[0].alloy-450+w.carry,"resource accounting with queued=%s" % queued)
		check(s.players[0].energy == 150,"replacement never changes resource type")
		if queued: check(s.players[0].alloy == 453 and w.orders.is_empty() and w.p.distance_to(Vector2(-16,12)) < 2,"queued move takes priority after final delivery")
		else: check(s.players[0].alloy > 453 and w.resource != r.id and not w.orders.is_empty(),"partial cargo delivered and replacement gathered")
	var s = Simulation.new(false)
	var w = workers(s)[0]
	var r = s.deposits[0]
	r.amount = 3
	s.deposits = [r]
	s.resource("alloy",Vector2(-12,38),100)
	s.resource("alloy",Vector2(20,38),100)
	s.resource("energy",Vector2(-30,34),100)
	s.vision_clock = 1000
	s.explored[0].fill(0)
	var c = s.nav.cell(Vector2(20,38))
	s.explored[0][c.y*s.nav.grid_size+c.x] = 1
	s.issue([w.id],{"type":"gather","target":r.id})
	step(s,35)
	check(s.players[0].alloy == 453 and w.carry == 0 and w.orders.is_empty(),"unexplored, distant and wrong-type replacements excluded")
	check(s.message.contains("No reachable nearby alloy"),"no replacement explains why gathering stopped")
	s = Simulation.new(false)
	w = workers(s)[0]
	var hq = s.own(0).filter(func(e): return e.type == "hq")[0]
	hq.complete = false
	w.carry = 7; w.carry_type = "alloy"
	s.issue([w.id],{"type":"deliver"})
	step(s,1)
	check(w.carry == 7 and s.players[0].alloy == 450 and s.message.contains("completed Command core"),"missing completed core preserves cargo and explains requirement")
	hq.complete = true
	s.issue([w.id],{"type":"deliver"})
	step(s,10)
	check(w.carry == 0 and s.players[0].alloy == 457,"delivery resumes when core is available")
	print("HARVESTERS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

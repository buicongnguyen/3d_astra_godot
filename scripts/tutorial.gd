extends RefCounted
var steps = JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial-steps.json"))
var index = 0
var done = false
var moves = []
var initial_ids = []
var attackers = []
var target_id = 0
var trained = false
var built = false
var gathered = false
func _init(sim):
	initial_ids = sim.own(0).map(func(e): return e.id)
	sim.ai_enabled = false
	sim.entities = sim.entities.filter(func(e): return e.team == 0 or e.type == "hq")
	for e in sim.entities:
		if e.team > 0: e.hp = 1e9; e.max_hp = 1e9; e.shield = 0
	sim.nav.rebuild(sim.entities)
	update(sim,[])
func point(sim) -> Vector2:
	if index in [1,6]: return Vector2(-23,9)
	if index == 2:
		for r in sim.deposits:
			if r.type == "alloy" and r.p.x < 0 and r.p.y > 0 and r.amount > 0: return r.p
	if index == 4:
		for e in sim.own(0):
			if e.type == "barracks": return e.p
	if index >= 5: return Vector2(0,20)
	return Vector2(-27,16)
func update(sim,selected: Array):
	if done: return
	sim.players[0].alloy = maxf(sim.players[0].alloy,500); sim.players[0].energy = maxf(sim.players[0].energy,200)
	sim.visible[0].fill(1); sim.explored[0].fill(1)
	var own = sim.own(0)
	var workers = own.filter(func(e): return e.type == "worker")
	var soldiers = own.filter(func(e): return e.kind == "unit" and e.type != "worker" and e.get("damage",0) > 0)
	gathered = gathered or sim.deposits.any(func(r): return r.type == "alloy" and r.initial-r.amount >= 10)
	built = built or own.any(func(e): return e.type == "relay" and e.complete)
	trained = trained or own.any(func(e): return e.type == "ranger" and not initial_ids.has(e.id))
	if index == 5:
		for e in soldiers:
			if not e.orders.is_empty() and (e.orders[0].type == "attackmove" or (e.orders[0].type == "attack" and e.orders[0].target == target_id)) and not attackers.has(e.id): attackers.append(e.id)
	var candidates = workers if index == 1 else soldiers.filter(func(e): return attackers.has(e.id))
	if index in [1,6]:
		for e in candidates:
			if not e.orders.is_empty() and e.orders[0].type == "move" and e.orders[0].p.distance_to(Vector2(-23,9)) < 4 and not moves.has(e.id): moves.append(e.id)
	var arrived = candidates.any(func(e): return moves.has(e.id) and e.p.distance_to(Vector2(-23,9)) < 3)
	var target = sim.entity(target_id)
	var complete = [workers.any(func(e): return selected.has(e.id)),arrived,gathered,built,trained,not attackers.is_empty() and not target.is_empty() and target.hp < 20000,arrived,target_id > 0 and (target.is_empty() or target.hp <= 0)][index]
	if not complete: return
	index += 1; moves.clear()
	if index == 5:
		var t = sim.spawn("relay",1,Vector2(0,20)); t.name = "Practice target"; t.training_guard = true; t.hp = 20000; t.max_hp = 20000; t.shield = 0; t.max_shield = 0; target_id = t.id; sim.nav.rebuild(sim.entities)
	if index == 7:
		var t = sim.entity(target_id)
		if not t.is_empty(): t.hp = 120; t.max_hp = 120; t.training_guard = false
	if index == steps.size(): done = true; sim.result = "victory"

extends RefCounted
const Catalog = preload("res://scripts/catalog.gd")

static func harvest_target(sim,e: Dictionary) -> Dictionary:
	if e.type != "worker" or e.orders.is_empty() or not e.orders[0].type in ["gather","deliver"]: return {}
	var o = e.orders[0]
	var r = sim.entity(o.get("target",0) if o.type == "gather" else e.resource)
	return r if r.get("kind","") == "resource" else {}

static func harvesting(sim,e: Dictionary) -> bool:
	var r = harvest_target(sim,e)
	return e.hp > 0 and e.get("working",false) and not e.moving and not r.is_empty() and e.orders[0].type == "gather" and e.carry < 10 and (e.carry == 0 or e.carry_type == r.type) and e.p.distance_to(r.p) <= r.radius+1.4

static func building(sim,e: Dictionary) -> Dictionary:
	if e.kind != "building" or e.team != 0 or e.hp <= 0: return {}
	if not e.complete:
		var builders = sim.own(0).filter(func(w): return not w.orders.is_empty() and w.orders[0].type == "build" and w.orders[0].get("target",0) == e.id)
		var active = builders.any(func(w): return w.get("working",false))
		return {"progress":e.progress,"label":"Needs Harvester" if builders.is_empty() else ("Building" if active else "Builder travelling"),"waiting":not active}
	if not e.level_job.is_empty(): return {"progress":minf(1,e.level_job.elapsed/e.level_job.time),"label":"Upgrade L%d" % (e.level+1)}
	if e.queue.is_empty(): return {}
	var q = e.queue[0]
	return {"progress":minf(1,q.elapsed/Catalog.get_def(q.type).time),"label":q.blocked if q.blocked != "" else Catalog.get_def(q.type).name,"waiting":q.blocked != ""}

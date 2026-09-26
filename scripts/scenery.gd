extends RefCounted
# Reuse the exported Blender scenery through Godot-native MultiMesh batches.
static func parts(source: Node3D) -> Array:
	var result = []
	for mesh in source.find_children("*","MeshInstance3D",true,false):
		result.append({"mesh":mesh.mesh,"transform":source.global_transform.affine_inverse()*mesh.global_transform})
	return result

static func bounds(source: Node3D) -> AABB:
	var result = AABB(); var first = true
	for part in parts(source):
		var box = part.transform*part.mesh.get_aabb()
		result = box if first else result.merge(box); first = false
	return result

static func batch(source: Node3D,parent: Node3D,transforms: Array,tint: Color = Color.TRANSPARENT,shadows: bool = true):
	if transforms.is_empty(): return
	for part in parts(source):
		var node = MultiMeshInstance3D.new()
		var multi = MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = part.mesh; multi.instance_count = transforms.size()
		for i in range(transforms.size()): multi.set_instance_transform(i,transforms[i]*part.transform)
		node.multimesh = multi
		if tint.a > 0:
			var mat = part.mesh.surface_get_material(0).duplicate()
			mat.albedo_color = tint; node.material_override = mat
		if not shadows: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)

static func build(view):
	var sim = view.sim; var library = view.scenery_library
	var rocks = Node3D.new(); rocks.name = "ObstacleRocks"; view.terrain.add_child(rocks)
	for variant in range(3):
		var source = library.find_child("asset_rock_"+"abc"[variant],true,false)
		var box = bounds(source); var reach = 0.0
		for i in range(8):
			var p = box.get_endpoint(i); reach = maxf(reach,Vector2(p.x,p.z).length())
		var transforms = []
		for i in range(view.Catalog.rocks.size()):
			if i%3 != variant: continue
			var rock = view.Catalog.rocks[i]; var scale = rock[2]*0.98/reach
			transforms.append(Transform3D(Basis(Vector3.UP,i*2.1).scaled(Vector3(scale,scale*(0.9+(i%3)*0.12),scale)),Vector3(rock[0],0,rock[1])))
		batch(source,rocks,transforms,Color(view.theme().rock))
	if sim.nav.river:
		var bridges = Node3D.new(); bridges.name = "Bridges"; view.terrain.add_child(bridges)
		batch(library.find_child("asset_bridge",true,false),bridges,[Transform3D(Basis.IDENTITY,Vector3(-22,0,0)),Transform3D(Basis.IDENTITY,Vector3(22,0,0))])
	# Scenery is decorative only, stays inside the map and avoids bases, deposits,
	# real obstacles and crossings. Large maps get the same capped density.
	var rng = RandomNumberGenerator.new(); rng.seed = 773
	var groups = {"bush":[],"reed":[],"tree":[]}
	var count = mini(180,roundi(70*pow(sim.nav.half/48.0,2)))
	for i in range(count):
		var p = Vector2(rng.randf_range(-sim.nav.half+5,sim.nav.half-5),rng.randf_range(-sim.nav.half+5,sim.nav.half-5))
		if sim.nav.river and absf(p.y) < 8: continue
		if sim.entities.any(func(e): return e.kind == "building" and e.p.distance_to(p) < e.radius+10): continue
		if sim.deposits.any(func(r): return r.p.distance_to(p) < r.radius+3): continue
		if view.Catalog.rocks.any(func(r): return p.distance_to(Vector2(r[0],r[1])) < r[2]+2): continue
		var kind = "tree" if sim.map_id == "woodlands" and i%4 == 0 else "bush"
		if sim.map_id == "dunes" and i%3 != 0: continue
		var scale = rng.randf_range(0.45,0.8)
		groups[kind].append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale),Vector3(p.x,0,p.y)))
	if sim.nav.river:
		for i in range(int(sim.nav.half*2/2.5)):
			var x = -sim.nav.half+4+i*2.5
			if [-22,0,22].any(func(c): return absf(x-c) < 7): continue
			groups.reed.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*0.7),Vector3(x,0,4.5 if i%2 else -4.5)))
	for kind in groups: batch(library.find_child("asset_"+kind,true,false),view.decorative,groups[kind],Color.TRANSPARENT,false)
	for r in sim.deposits:
		var source = library.find_child("asset_crystal_"+r.type,true,false)
		var group = Node3D.new(); group.name = "Deposit_%d" % r.id
		view.add_child(group); group.position = Vector3(r.p.x,0,r.p.y)
		batch(source,group,[Transform3D.IDENTITY])
		view.resource_objects[r.id] = group

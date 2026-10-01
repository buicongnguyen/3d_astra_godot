extends SceneTree
# Ambient life and the frame-time governor: seeded plans stay inside every map, fish stay in
# the river, budgets thin the cast, each family builds one node, and slow frames calm, then
# still, the motion (a 30 Hz display cap does not).
const AmbientLife = preload("res://scripts/ambient_life.gd")
const Governor = preload("res://scripts/governor.gd")
const Catalog = preload("res://scripts/catalog.gd")
var failures = 0
var checks = 0
func check(ok: bool,text: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL: "+text)
	else: print("PASS: "+text)
func feed(g,seconds: float,ms: float):
	var t = 0.0
	while t < seconds-1e-6: g.sample(ms/1000.0,true); t += ms/1000.0
func _initialize():
	Catalog.load_data()
	var maps = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps.json"))
	for id in AmbientLife.LIFE:
		var config = maps.get(id,maps.get("maps",{}).get(id,{}))
		var half = float(config.get("size",96))/2.0; var river = config.get("river",false)
		var full = AmbientLife.plan(id,half,river,Catalog.rocks,1.0)
		var light = AmbientLife.plan(id,half,river,Catalog.rocks,0.6)
		check(JSON.stringify(full) == JSON.stringify(AmbientLife.plan(id,half,river,Catalog.rocks,1.0)),id+" plan is deterministic")
		check(light.motes.size() <= full.motes.size() and light.butterflies.size() <= full.butterflies.size(),id+" budget thins the cast")
		var inside = true
		for b in full.birds:
			if b.mode == 0.0 and maxf(absf(b.x),absf(b.z))+b.radius > half-3: inside = false
		for f in full.butterflies+full.dragonflies:
			if maxf(absf(f.x)+f.rx,absf(f.z)+f.rz)+0.5 > half-1: inside = false
		for m in full.motes:
			if maxf(absf(m.x),absf(m.z))+5.2 > half-1: inside = false
		for f in full.fish:
			if not river or absf(f.z)+0.5 >= 3 or absf(f.x) >= half-2: inside = false
		check(inside,id+" every path stays inside the map and fish stay in the river")
		# Build: one node per family, clock advances, still level and quiet hold it.
		var parent = Node3D.new(); root.add_child(parent)
		var image = Image.create(8,8,false,Image.FORMAT_R8); var texture = ImageTexture.create_from_image(image)
		var life = AmbientLife.new(parent,id,half,river,Catalog.rocks,1.0,texture,texture,Vector2(0.3,-0.3))
		var expected = (2 if not full.birds.is_empty() else 0)+(0 if full.butterflies.is_empty() else 1)+(0 if full.dragonflies.is_empty() else 1)+(0 if full.fish.is_empty() else 1)+(0 if full.motes.is_empty() else 1)
		check(life.families.size() == expected and expected >= 3,id+" builds %d families" % expected)
		life.update(0.04,10.0); var moving = life.clock > 0
		life.level = 0; var held = life.clock; life.update(0.04,10.0)
		var still = life.clock == held
		life.level = 2; life.quiet = true; life.update(0.04,10.0)
		check(moving and still and life.clock == held,id+" motion levels and reduced motion hold the clock")
		life.dispose(); parent.free()
	var g = Governor.new()
	feed(g,20,1000.0/60.0); check(g.level == 2,"smooth frames keep full motion")
	feed(g,20,1000.0/30.0); check(g.level == 2,"a steady 30 Hz cap is not slowness")
	g = Governor.new(); feed(g,4,16)
	feed(g,2.1,45); var calm = g.level
	feed(g,2.1,45); var still_level = g.level
	feed(g,30,16)
	check(calm == 1 and still_level == 0 and g.level == 2,"slow frames calm then still the motion; smooth frames restore it")
	g = Governor.new(); for i in range(50): g.sample(0.4,true)
	for i in range(100): g.sample(0.05,false)
	feed(g,2.9,50); check(g.level == 2,"hitches, pauses and the start-up grace are ignored")
	print("LIFE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

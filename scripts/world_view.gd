extends Node3D
const Catalog = preload("res://scripts/catalog.gd")
var sim
var camera: Camera3D
var focus = Vector2(-20,20)
var zoom = 44.0
var objects: Dictionary = {}
var resource_objects: Dictionary = {}
var models: Dictionary = {}
var team_materials: Array = [{},{}]
var colors: Array = [Color("92ebc5"),Color("ef7660")]
var terrain: Node3D
var effects: Array = []
var fog_texture: ImageTexture
var fog_image: Image
var fog_clock = 0.0
var water_material: ShaderMaterial
var decorative: Node3D
var water_motion = true
var selected: Array = []
var ghost: MeshInstance3D
var selection_box = Rect2()

func setup(simulation):
	sim = simulation
	for type in Catalog.definitions:
		if type == "upgrade": continue
		models[type] = load("res://assets/models/"+type+".glb")
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("14242c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b7ced0")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52,-25,0)
	light.light_color = Color("fff0d2")
	light.light_energy = 0.78
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 110
	add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 230
	add_child(camera)
	camera.make_current()
	build_map()
	update_camera()
	ghost = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 1
	cylinder.bottom_radius = 1
	cylinder.height = 0.13
	ghost.mesh = cylinder
	ghost.material_override = material(Color(0.3,1,0.6,0.45),true)
	ghost.visible = false
	add_child(ghost)

func material(color: Color,unshaded: bool = false) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.86
	if color.a < 1: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func box(parent: Node3D,p: Vector3,size: Vector3,color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color)
	node.position = p
	parent.add_child(node)
	return node

func surface(p: Vector2) -> Color:
	if not sim.nav.river: return Color("8b805e")
	if absf(p.y) < 5: return Color("777258")
	if minf(absf(p.x-22),absf(p.x+22)) < 2.3 or absf(p.y+p.x*0.35) < 1.8: return Color("af9973")
	var n = sin(p.x*0.13)*cos(p.y*0.17)+sin((p.x+p.y)*0.09)
	return Color("b09e76") if n > 0.65 else (Color("887b5d") if n < -0.4 else Color("788566"))

func build_map():
	if is_instance_valid(terrain):
		remove_child(terrain)
		terrain.queue_free()
	for o in objects.values():
		o.root.queue_free()
	objects.clear()
	for o in resource_objects.values(): o.queue_free()
	resource_objects.clear()
	for effect in effects: effect.node.queue_free()
	effects.clear()
	terrain = Node3D.new()
	add_child(terrain)
	box(terrain,Vector3(0,-1,0),Vector3(98,1,98),Color("333d36"))
	# One terrain mesh; vertex colors provide inexpensive surface variation.
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-48,48,2):
		for x in range(-48,48,2):
			for corner in [Vector2(0,0),Vector2(0,2),Vector2(2,0),Vector2(2,0),Vector2(0,2),Vector2(2,2)]:
				var p = Vector2(x,z)+corner
				var height = -0.38 if sim.nav.river and absf(p.y) <= 3 else 0.0
				st.set_color(surface(p))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(p.x,height,p.y))
	var ground = MeshInstance3D.new()
	ground.mesh = st.commit()
	var mat = material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground.material_override = mat
	terrain.add_child(ground)
	for rock in Catalog.rocks:
		var stone = MeshInstance3D.new()
		var mesh = SphereMesh.new()
		mesh.radius = rock[2]
		mesh.height = rock[2]*1.65
		mesh.radial_segments = 7
		mesh.rings = 3
		stone.mesh = mesh
		stone.position = Vector3(rock[0],rock[2]*0.35,rock[1])
		stone.rotation.y = rock[0]
		stone.material_override = material(Color("646d65"))
		terrain.add_child(stone)
	if sim.nav.river:
		var water = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(96,6)
		water.mesh = plane
		water.position.y = -0.08
		water_material = ShaderMaterial.new()
		var shader = Shader.new()
		shader.code = "shader_type spatial; render_mode unshaded; uniform float clock = 0.; void fragment(){ float ripple=sin(UV.x*180.+clock*1.1)*sin(UV.y*22.-clock*.6); ALBEDO=mix(vec3(.10,.32,.36),vec3(.30,.57,.58),.45+ripple*.14); }"
		water_material.shader = shader
		water.material_override = water_material
		terrain.add_child(water)
		for x in [-22,22]:
			box(terrain,Vector3(x,0.03,0),Vector3(10,0.22,7.6),Color("ab9e83"))
			for edge in [-4.9,4.9]:
				box(terrain,Vector3(x+edge,0.38,0),Vector3(0.18,0.5,7.8),Color("595f52"))
		box(terrain,Vector3(0,-0.035,0),Vector3(10,0.05,6),Color("78a7a0"))
	decorative = Node3D.new()
	terrain.add_child(decorative)
	var env_scene = load("res://assets/models/environment.glb") as PackedScene
	if env_scene:
		var library = env_scene.instantiate()
		for i in range(28):
			var name_hint = "tree" if i < 12 else ("bush" if i < 20 else "reed")
			var source = find_named(library,name_hint)
			if source:
				var item = source.duplicate()
				decorative.add_child(item)
				var x = -43+(i*17)%86
				var z = (-49 if i%2 == 0 else 49) if i < 12 else (-6 if i%2 == 0 else 6)
				item.position = Vector3(x,0,z)
				item.rotation.y = i*2.4
		library.free()
	for r in sim.deposits:
		var group = Node3D.new()
		group.position = Vector3(r.p.x,0,r.p.y)
		add_child(group)
		for i in range(5):
			var crystal = MeshInstance3D.new()
			var mesh = CylinderMesh.new()
			mesh.top_radius = 0.04
			mesh.bottom_radius = 0.55
			mesh.height = 1.2+float(i%3)*0.5
			mesh.radial_segments = 5
			crystal.mesh = mesh
			crystal.position = Vector3(cos(i*2.4)*0.7,mesh.height*0.5,sin(i*2.4)*0.7)
			crystal.material_override = material(Color("e8ae52") if r.type == "alloy" else Color("5dc9ed"))
			group.add_child(crystal)
		resource_objects[r.id] = group
	fog_image = Image.create(48,48,false,Image.FORMAT_RGBA8)
	fog_texture = ImageTexture.create_from_image(fog_image)
	var fog = MeshInstance3D.new()
	var fog_mesh = PlaneMesh.new()
	fog_mesh.size = Vector2(96,96)
	fog.mesh = fog_mesh
	fog.position.y = 0.65
	var fog_mat = ShaderMaterial.new()
	var fog_shader = Shader.new()
	fog_shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never; uniform sampler2D visibility_map: filter_linear; void fragment(){ vec4 fog=texture(visibility_map,UV); ALBEDO=vec3(.018,.038,.045); ALPHA=fog.a; }"
	fog_mat.shader = fog_shader
	fog_mat.set_shader_parameter("visibility_map",fog_texture)
	fog.material_override = fog_mat
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.add_child(fog)
	fog_clock = 0

func find_named(node: Node,hint: String):
	if hint in node.name.to_lower(): return node
	for child in node.get_children():
		var found = find_named(child,hint)
		if found: return found
	return null

func paint(node: Node,team: int,legs: Array):
	if node is Node3D and ("leg" in node.name.to_lower() or "arm" in node.name.to_lower()):
		legs.append({"node":node,"rotation":node.rotation})
	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count()):
			var m = node.mesh.surface_get_material(i)
			if m and "Team" in m.resource_name:
				if not team_materials[team].has(m.resource_name):
					var copy = m.duplicate()
					copy.albedo_color = colors[team]
					if copy.emission_enabled: copy.emission = colors[team]
					team_materials[team][m.resource_name] = copy
				node.set_surface_override_material(i,team_materials[team][m.resource_name])
	for child in node.get_children(): paint(child,team,legs)

func set_colors(player: Color,opponent: Color):
	colors = [player,opponent]
	for team in range(2):
		for mat in team_materials[team].values():
			mat.albedo_color = colors[team]
			if mat.emission_enabled: mat.emission = colors[team]
	for id in objects:
		var e = sim.entity(id)
		if not e.is_empty(): objects[id].ring.material_override.albedo_color = colors[e.team]

func create_entity(e: Dictionary):
	var root = Node3D.new()
	add_child(root)
	var model = models[e.type].instantiate()
	root.add_child(model)
	var legs = []
	paint(model,e.team,legs)
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = e.radius+0.15
	torus.outer_radius = e.radius+0.25
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = 0.12
	ring.material_override = material(colors[e.team],true)
	root.add_child(ring)
	var animation = find_animation(model)
	if animation:
		for clip in animation.get_animation_list():
			if clip != "Death": animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var boxes: Array = []
	collect_pick_boxes(model,model,boxes)
	objects[e.id] = {"root":root,"model":model,"ring":ring,"legs":legs,"animation":animation,"clip":"","pick_boxes":boxes}

func collect_pick_boxes(node: Node,model: Node3D,boxes: Array):
	if node is MeshInstance3D and node.mesh:
		var local = model.global_transform.affine_inverse()*node.global_transform
		boxes.append(local*node.get_aabb())
	for child in node.get_children(): collect_pick_boxes(child,model,boxes)

func find_animation(node: Node):
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var found = find_animation(child)
		if found: return found
	return null

func update_camera():
	focus = focus.clamp(Vector2(-44,-44),Vector2(44,44))
	zoom = clampf(zoom,20,80)
	camera.size = zoom
	camera.keep_aspect = Camera3D.KEEP_WIDTH if get_viewport().get_visible_rect().size.x < get_viewport().get_visible_rect().size.y else Camera3D.KEEP_HEIGHT
	camera.position = Vector3(focus.x,55,focus.y+42)
	camera.look_at(Vector3(focus.x,0,focus.y))

func ground(screen: Vector2) -> Vector2:
	var origin = camera.project_ray_origin(screen)
	var direction = camera.project_ray_normal(screen)
	var point = origin+direction*(-origin.y/direction.y)
	return Vector2(point.x,point.z)

func pick(screen: Vector2) -> Dictionary:
	var best = {}
	var closest = INF
	var fallback = {}
	var fallback_distance = 28.0
	var origin = camera.project_ray_origin(screen)
	var direction = camera.project_ray_normal(screen)
	for e in sim.entities+sim.deposits:
		if e.kind == "resource" and e.amount <= 0: continue
		if e.kind != "resource" and e.hp <= 0: continue
		if e.get("team",-1) != 0 and not sim.seen(e.p): continue
		var transform = Transform3D(Basis.IDENTITY,Vector3(e.p.x,0,e.p.y))
		var boxes = [AABB(Vector3(-e.radius,0,-e.radius),Vector3(e.radius*2,2.8,e.radius*2))]
		if objects.has(e.id):
			transform = objects[e.id].model.global_transform
			boxes = objects[e.id].pick_boxes
		var inverse = transform.affine_inverse()
		for bounds in boxes:
			# Individual visible-part bounds cover roofs and walls without one giant
			# building box swallowing nearby units or empty spaces between props.
			var hit = bounds.grow(0.08).intersects_ray(inverse*origin,inverse.basis*direction)
			if hit is Vector3:
				var depth = origin.distance_squared_to(transform*hit)
				if depth < closest:
					closest = depth
					best = e
		var pos = camera.unproject_position(Vector3(e.p.x,1.2,e.p.y))
		var d = screen.distance_to(pos)
		if d < fallback_distance:
			fallback_distance = d
			fallback = e
	return best if not best.is_empty() else fallback

func refresh(dt: float):
	update_camera()
	var alive = {}
	for e in sim.entities:
		if e.hp <= 0: continue
		alive[e.id] = true
		if not objects.has(e.id): create_entity(e)
		var o = objects[e.id]
		o.root.position = Vector3(e.p.x,0.12 if sim.nav.river and absf(e.p.y) < 4 else 0,e.p.y)
		o.root.visible = e.team == 0 or sim.seen(e.p)
		o.model.rotation.y = e.angle
		o.model.scale = Vector3.ONE*(0.25+0.75*e.progress)
		o.ring.visible = selected.has(e.id)
		if o.animation:
			var clip = "Walk" if e.moving else ("Attack" if e.cooldown > 0.1 else ("Work" if not e.orders.is_empty() and e.orders[0].type in ["gather","build"] else "Idle"))
			if o.clip != clip:
				o.animation.play(clip,0.1)
				o.clip = clip
			o.animation.speed_scale = 1.0 if dt > 0 else 0.0
	for id in objects.keys():
		if not alive.has(id):
			var o = objects[id]
			if o.root.visible and o.animation and o.animation.has_animation("Death"):
				o.ring.visible = false
				o.animation.play("Death")
				o.animation.speed_scale = 1
				effects.append({"node":o.root,"life":1.0})
			else: o.root.queue_free()
			objects.erase(id)
	for r in sim.deposits: resource_objects[r.id].visible = r.amount > 0 and sim.discovered(r.p)
	if water_material: water_material.set_shader_parameter("clock",sim.time if water_motion else 0.0)
	fog_clock -= dt
	if fog_clock <= 0:
		for y in range(48):
			for x in range(48):
				var index = y*48+x
				fog_image.set_pixel(x,y,Color(0,0,0,0.0 if sim.visible[0][index] else (0.6 if sim.explored[0][index] else 0.94)))
		fog_texture.update(fog_image)
		fog_clock = 0.25
	for event in sim.events:
		if not sim.seen(event.p): continue
		if event.type == "shot":
			var a = Vector3(event.p.x,1.2,event.p.y)
			var b = Vector3(event.to.x,1.2,event.to.y)
			var line = box(self,(a+b)*0.5,Vector3(0.075,0.075,a.distance_to(b)),colors[event.team])
			if a.distance_to(b) > 0.001: line.look_at(b)
			effects.append({"node":line,"life":0.12})
	sim.events.clear()
	for effect in effects.duplicate():
		var animation = find_animation(effect.node)
		if animation: animation.speed_scale = 1.0 if dt > 0 else 0.0
		effect.life -= dt
		if effect.life <= 0:
			effect.node.queue_free()
			effects.erase(effect)
	while effects.size() > 64:
		effects[0].node.queue_free()
		effects.pop_front()

extends SceneTree
const Main = preload("res://scenes/main.tscn")
var failures = 0
func check(ok: bool,text: String):
	if not ok: failures += 1; printerr("FAIL: "+text)
	else: print("PASS: "+text)
func inside(box: AABB,half: float) -> bool:
	return box.position.x >= -half-0.01 and box.end.x <= half+0.01 and box.position.z >= -half-0.01 and box.end.z <= half+0.01
func _initialize(): call_deferred("run")
func run():
	var game = Main.instantiate(); root.add_child(game); await process_frame
	for map in game.MAP_IDS:
		game.reset_sim(true,map); game.view.refresh(0); await process_frame
		var bounded = true; var instances = 0
		for node in game.view.terrain.find_children("*","MultiMeshInstance3D",true,false):
			var multi = node.multimesh
			for i in range(multi.instance_count):
				var box = node.global_transform*multi.get_instance_transform(i)*multi.mesh.get_aabb()
				bounded = bounded and inside(box,game.sim.nav.half); instances += 1
		check(bounded,"all scenery stays within "+map+" boundary")
		check(instances < 600,"bounded scenery budget "+map)
		var border = game.view.terrain.get_node("MapBoundary")
		check(border.get_child_count() == 4,"four clean boundary sides "+map)
		var rocks = game.view.terrain.get_node("ObstacleRocks")
		check(rocks.get_child_count() > 0,"Blender boulders present "+map)
		check(game.view.resource_objects.size() == game.sim.deposits.size(),"every resource keeps its visual "+map)
	var model = game.view.models.tank; var vertex_colors = false
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for i in range(mesh.mesh.get_surface_count()):
			var colors = mesh.mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
			if colors != null and not colors.is_empty(): vertex_colors = true
	check(vertex_colors,"baked Blender vertex shading survives batching")
	var e = game.sim.own(0)[0]; game.view.selected = [e.id]; game.view.refresh(0)
	var ring = game.view.objects[e.id].ring
	check(ring.visible and ring.material_override is ShaderMaterial,"native shader selection ring")
	game.view.set_colors(Color.RED,Color.BLUE)
	check(ring.material_override.get_shader_parameter("team_color") == Color.RED,"selection ring follows team setting")
	game.queue_free(); await process_frame
	print("VISUAL PORT: %d failures" % failures)
	quit(1 if failures else 0)

extends SceneTree
const Catalog = preload("res://scripts/catalog.gd")
const Main = preload("res://scenes/main.tscn")
var failures = 0
func verify(ok: bool,text: String):
	if not ok: failures += 1; printerr("FAIL: "+text)
	else: print("PASS: "+text)
func _initialize(): call_deferred("run")
func animation(node: Node):
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var found = animation(child)
		if found: return found
	return null
func run():
	Catalog.load_data()
	for type in Catalog.definitions:
		if type == "upgrade": continue
		var packed = load("res://assets/models/"+type+".glb")
		verify(packed is PackedScene,"Blender import: "+type)
		var model = packed.instantiate()
		if Catalog.get_def(type).kind == "unit":
			var player = animation(model)
			for clip in ["Idle","Walk","Work","Attack","Death"]: verify(player != null and player.has_animation(clip),type+" animation "+clip)
		model.free()
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.start_match()
	game.sim.ai_enabled = false
	game.toggle_pause()
	game.show_settings()
	game.close_settings()
	verify(game.paused and game.modal.visible,"closing settings preserves pause")
	game.settings.player = 3
	game.settings.enemy = 4
	game.apply_settings()
	verify(game.view.colors[0] == Color("edc76f"),"palette applied to renderer")
	var enemy_hq = game.sim.own(1).filter(func(e): return e.type == "hq")[0]
	game.sim.visible[0].fill(1)
	game.refresh_ui()
	verify(game.known_buildings.has(enemy_hq.id),"visible enemy building creates a remembered marker")
	game.sim.visible[0].fill(0)
	enemy_hq.hp = 0
	game.refresh_ui()
	verify(game.known_buildings.has(enemy_hq.id),"unseen destruction does not update remembered markers")
	game.sim.visible[0].fill(1)
	game.refresh_ui()
	verify(not game.known_buildings.has(enemy_hq.id),"revisiting an empty site clears its marker")
	game.restart_match()
	game.view.refresh(0)
	await process_frame
	var before = game.view.get_child_count()
	for i in range(5):
		game.restart_match()
		await process_frame
		await process_frame
	verify(game.view.objects.size() == 18,"restart retains one clean roster")
	verify(game.view.get_child_count() == before,"restart does not accumulate scene roots")
	game.queue_free()
	await process_frame
	print("ASSET/UI RESULT: %d failures" % failures)
	quit(1 if failures else 0)

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
	# Model-surface clicks well outside the previous center-only hit circle.
	for type in ["hq","barracks"]:
		var building = game.sim.own(0).filter(func(e): return e.type == type)[0]
		for zoom in [20,44,80]:
			game.view.zoom = zoom
			game.view.focus = building.p
			game.view.update_camera()
			var roof = Vector3(building.p.x+(2.0 if type == "hq" else 1.7),2.6,building.p.y)
			var hit = game.view.pick(game.view.camera.unproject_position(roof))
			verify(hit.get("id",-1) == building.id,"roof/edge selection: %s at zoom %d" % [type,zoom])
	var friendly_worker = game.sim.own(0).filter(func(e): return e.type == "worker")[0]
	var barracks = game.sim.own(0).filter(func(e): return e.type == "barracks")[0]
	game.selected = [friendly_worker.id]
	barracks.hp = 0
	game.begin_build("foundry")
	verify(game.mode == "" and game.notice.text == "Build Barracks before building Foundry.","missing prerequisite is shown immediately without placement mode")
	barracks.hp = barracks.max_hp
	game.sim.players[0].alloy = 20
	game.sim.players[0].energy = 10
	game.begin_build("foundry")
	verify(game.mode == "" and game.notice.text.begins_with("Need 180 alloy and 90 energy"),"UI shows exact construction resource shortage")
	game.sim.players[0].alloy = 450
	game.sim.players[0].energy = 150
	game.begin_build("relay")
	game.confirm_build()
	game.refresh_ui()
	verify(game.notice.text == "Choose a construction site on the ground first.","confirm without a site explains the required action")
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

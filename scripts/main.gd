extends Node3D
const Simulation = preload("res://scripts/simulation.gd")
const WorldView = preload("res://scripts/world_view.gd")
const Overlay = preload("res://scripts/overlay.gd")
const Catalog = preload("res://scripts/catalog.gd")
const PALETTES = ["Mint","Coral","Blue","Gold","Violet","Cyan","Orange","Ivory"]
const HEXES = ["92ebc5","ef7660","689dff","edc76f","b397ee","64d9ed","efa34f","ebe7cd"]
var sim
var view
var selected: Array = []
var groups: Dictionary = {}
var started = false
var paused = true
var mode = ""
var building_type = ""
var placement_point = Vector2.ZERO
var placement_ready = false
var queue_orders = false
var pointer_start = Vector2.ZERO
var pointer_now = Vector2.ZERO
var pointer_down = false
var dragging = false
var middle_down = false
var touch_active = false
var touches: Dictionary = {}
var multi_gesture = false
var minimap_rect = Rect2()
var accumulator = 0.0
var ui_clock = 0.0
var ui: Control
var header: Panel
var bottom: Panel
var title_label: Label
var resource_label: Label
var selection_label: Label
var info_label: Label
var notice: Label
var actions: HFlowContainer
var nav_buttons: HBoxContainer
var overlay
var modal: Panel
var scrim: ColorRect
var modal_scroll: ScrollContainer
var action_scroll: ScrollContainer
var settings_panel: Panel
var modal_body: VBoxContainer
var modal_title: Label
var modal_desc: Label
var modal_actions: VBoxContainer
var scenario: OptionButton
var action_signature = ""
var settings = {"player":0,"enemy":1,"eco":false,"water":true,"detail":true,"muted":false}
var test_callback
var test_enabled = false
var beep: AudioStreamPlayer
var last_key = ""
var objective: Label
var known_buildings: Dictionary = {}

func _input(event):
	if event is InputEventKey and event.pressed: last_key = "%d/%d shift=%s ctrl=%s" % [event.keycode,event.physical_keycode,event.shift_pressed,event.ctrl_pressed]
	# Releases over HUD do not reach _unhandled_input; clear captured gestures here.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE: middle_down = false
		if event.button_index == MOUSE_BUTTON_LEFT and not is_world_point(event.position): pointer_down = false; dragging = false
	if event is InputEventScreenTouch and not event.pressed and not is_world_point(event.position): touches.erase(event.index); multi_gesture = true

func is_world_point(point: Vector2) -> bool:
	return is_instance_valid(header) and is_instance_valid(bottom) and not header.get_global_rect().has_point(point) and not bottom.get_global_rect().has_point(point)

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and started and not paused: toggle_pause()

func _ready():
	settings.eco = bool(JavaScriptBridge.eval("matchMedia('(pointer: coarse)').matches")) if OS.has_feature("web") else DisplayServer.is_touchscreen_available()
	load_settings()
	sim = Simulation.new()
	view = WorldView.new()
	add_child(view)
	view.setup(sim)
	make_ui()
	make_audio()
	apply_settings()
	show_briefing()
	get_viewport().size_changed.connect(layout)
	layout()
	if OS.has_feature("web"):
		test_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('test') === '1'"))
		if test_enabled:
			test_callback = JavaScriptBridge.create_callback(test_call)
			JavaScriptBridge.get_interface("window").frontierCommand = test_callback

func make_audio():
	beep = AudioStreamPlayer.new()
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	var data = PackedByteArray()
	for i in range(1400): data.append(int(128+sin(float(i)*TAU*620/22050)*14*(1-float(i)/1400)))
	stream.data = data
	beep.stream = stream
	beep.volume_db = -18
	add_child(beep)

func acknowledge():
	if not settings.muted: beep.play()

func load_settings():
	var config = ConfigFile.new()
	if config.load("user://preferences.cfg") != OK: return
	for key in settings:
		var value = config.get_value("settings",key,settings[key])
		if typeof(value) == typeof(settings[key]): settings[key] = value
	settings.player = clampi(settings.player,0,HEXES.size()-1)
	settings.enemy = clampi(settings.enemy,0,HEXES.size()-1)
	if settings.enemy == settings.player: settings.enemy = (settings.player+1)%HEXES.size()

func apply_settings():
	view.set_colors(Color(HEXES[settings.player]),Color(HEXES[settings.enemy]))
	view.water_motion = settings.water
	view.decorative.visible = settings.detail
	for child in view.get_children():
		if child is DirectionalLight3D: child.shadow_enabled = not settings.eco
	var config = ConfigFile.new()
	for key in settings: config.set_value("settings",key,settings[key])
	if config.save("user://preferences.cfg") != OK: sim.message = "Preferences apply this session; storage is unavailable."

func panel_style(color: Color,border: Color = Color("294249")) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func label(text: String,font_size: int = 15) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size",font_size)
	l.add_theme_color_override("font_color",Color("e1ebe2"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func button(text: String,callback: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0,40)
	b.add_theme_font_size_override("font_size",14)
	b.pressed.connect(callback)
	return b

func make_ui():
	var layer = CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var theme = Theme.new()
	theme.default_font_size = 15
	theme.set_stylebox("normal","Button",panel_style(Color("19333c")))
	theme.set_stylebox("hover","Button",panel_style(Color("2b5055"),Color("7bc7af")))
	theme.set_stylebox("pressed","Button",panel_style(Color("42655c"),Color("92ebc5")))
	theme.set_stylebox("focus","Button",panel_style(Color(0,0,0,0),Color("edc76f")))
	theme.set_stylebox("panel","Panel",panel_style(Color(0.035,0.075,0.095,0.96)))
	ui.theme = theme
	header = Panel.new()
	ui.add_child(header)
	title_label = label("FRONTIER / GODOT",20)
	header.add_child(title_label)
	resource_label = label("",16)
	header.add_child(resource_label)
	nav_buttons = HBoxContainer.new()
	header.add_child(nav_buttons)
	nav_buttons.add_child(button("Home",func(): view.focus = Vector2(-25,24)))
	nav_buttons.add_child(button("−",func(): view.zoom += 5))
	nav_buttons.add_child(button("+",func(): view.zoom -= 5))
	nav_buttons.add_child(button("Pause",toggle_pause))
	bottom = Panel.new()
	ui.add_child(bottom)
	selection_label = label("SELECT YOUR EXPEDITION",18)
	bottom.add_child(selection_label)
	info_label = label("",13)
	bottom.add_child(info_label)
	actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation",6)
	actions.add_theme_constant_override("v_separation",6)
	action_scroll = ScrollContainer.new()
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bottom.add_child(action_scroll)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_scroll.add_child(actions)
	notice = label("",14)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.add_child(notice)
	objective = label("",14)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.add_child(objective)
	overlay = Overlay.new()
	overlay.game = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay)
	scrim = ColorRect.new()
	scrim.color = Color(0.01,0.025,0.035,0.48)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(scrim)
	modal = Panel.new()
	ui.add_child(modal)
	modal_scroll = ScrollContainer.new()
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal.add_child(modal_scroll)
	modal_body = VBoxContainer.new()
	modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_body.add_theme_constant_override("separation",14)
	modal_scroll.add_child(modal_body)
	modal_title = label("FRONTIER COMMAND",27)
	modal_body.add_child(modal_title)
	modal_desc = label("",15)
	modal_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_body.add_child(modal_desc)
	scenario = OptionButton.new()
	scenario.add_item("Meridian Riverlands")
	scenario.add_item("Ashen Frontier")
	scenario.custom_minimum_size.y = 40
	modal_body.add_child(scenario)
	modal_actions = VBoxContainer.new()
	modal_body.add_child(modal_actions)
	refresh_ui()

func layout():
	if not ui: return
	var size = get_viewport().get_visible_rect().size
	var narrow = size.x < 540
	header.position = Vector2(10,10)
	header.size = Vector2(size.x-20,98 if narrow else 68)
	title_label.position = Vector2(12,9)
	title_label.add_theme_font_size_override("font_size",16 if narrow else 20)
	resource_label.position = Vector2(12,35 if narrow else 36)
	resource_label.add_theme_font_size_override("font_size",13 if narrow else 15)
	nav_buttons.position = Vector2(12,57) if narrow else Vector2(size.x-260,12)
	var height = 235 if narrow else (145 if size.y < 520 else 170)
	bottom.position = Vector2(10,size.y-height-10)
	bottom.size = Vector2(size.x-20,height)
	selection_label.position = Vector2(12,10)
	selection_label.add_theme_font_size_override("font_size",15 if narrow else 18)
	info_label.position = Vector2(12,36)
	info_label.size = Vector2(bottom.size.x-24,38)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_scroll.position = Vector2(12,76 if narrow else 63)
	action_scroll.size = Vector2(bottom.size.x-24,height-action_scroll.position.y-10)
	notice.position = Vector2(16,bottom.position.y-44)
	notice.size = Vector2(size.x-32,40)
	var minimap_size = 100 if narrow else 154
	minimap_rect = Rect2(size.x-minimap_size-18,header.position.y+header.size.y+12,minimap_size,minimap_size)
	objective.position = Vector2(18,header.position.y+header.size.y+12)
	objective.size = Vector2(maxf(120,size.x-minimap_size-60),55)
	modal.size = Vector2(minf(490,size.x-30),minf(490,size.y-30))
	modal.position = (size-modal.size)*0.5
	modal_scroll.position = Vector2(24,22)
	modal_scroll.size = modal.size-Vector2(48,44)
	if is_instance_valid(settings_panel):
		settings_panel.size = Vector2(minf(470,size.x-24),minf(560,size.y-24))
		settings_panel.position = (size-settings_panel.size)*0.5
		settings_panel.get_child(0).size = settings_panel.size-Vector2(36,82)
		settings_panel.get_child(1).position = Vector2(18,settings_panel.size.y-55)
		settings_panel.get_child(1).size = Vector2(settings_panel.size.x-36,40)

func clear_children(node: Node):
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func show_briefing():
	paused = true
	modal.visible = true
	scrim.visible = true
	scenario.visible = true
	modal_title.text = "FRONTIER COMMAND"
	modal_desc.text = "MERIDIAN EXPEDITION · GODOT EDITION\n\nBuild an outpost. Command a mixed army. Cross the river and destroy the enemy Command core.\n\nDesktop: drag to select · right-click orders\nWASD pan · wheel zoom · Q attack-move\nTouch: tap select/order · drag pan · pinch zoom"
	clear_children(modal_actions)
	modal_actions.add_child(button("Deploy expedition",start_match))
	modal_actions.add_child(button("Army & graphics settings",show_settings))

func start_match():
	if sim.nav.river != (scenario.selected == 0): reset_sim(scenario.selected == 0)
	started = true
	paused = false
	modal.visible = false
	scrim.visible = false
	selected = sim.own(0).filter(func(e): return e.type == "worker").map(func(e): return e.id)
	action_signature = ""
	acknowledge()

func reset_sim(river: bool):
	sim = Simulation.new(true,river)
	view.sim = sim
	view.build_map()
	view.focus = Vector2(-20,20)
	view.zoom = 44
	selected.clear()
	groups.clear()
	known_buildings.clear()
	mode = ""
	placement_ready = false
	pointer_down = false
	touches.clear()
	accumulator = 0
	action_signature = ""
	apply_settings()

func restart_match():
	reset_sim(sim.nav.river)
	started = false
	show_briefing()

func toggle_pause():
	if is_instance_valid(settings_panel) or not started or sim.result != "": return
	paused = not paused
	modal.visible = paused
	scrim.visible = paused
	if paused:
		mode = ""
		placement_ready = false
		view.ghost.visible = false
		pointer_down = false
		touches.clear()
		scenario.visible = false
		modal_title.text = "EXPEDITION PAUSED"
		modal_desc.text = "The battlefield is paused.\n\nX stops selected units. Shift queues orders.\nShift + 1–9 saves groups; 1–9 recalls.\nF focuses selection. H returns to base.\nSelect a building, then right-click for its rally point."
		clear_children(modal_actions)
		modal_actions.add_child(button("Resume",toggle_pause))
		modal_actions.add_child(button("Army & graphics settings",show_settings))
		modal_actions.add_child(button("Restart expedition",restart_match))

func show_settings():
	if is_instance_valid(settings_panel): return
	modal.visible = false
	settings_panel = Panel.new()
	ui.add_child(settings_panel)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(18,15)
	settings_panel.add_child(scroll)
	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",10)
	scroll.add_child(body)
	body.add_child(label("EXPEDITION SETTINGS",22))
	body.add_child(label("Choose distinct colors for both armies.",14))
	var picks = []
	for key in ["player","enemy"]:
		body.add_child(label("Your army" if key == "player" else "Enemy army",14))
		var pick = OptionButton.new()
		for i in range(PALETTES.size()): pick.add_item(PALETTES[i])
		pick.selected = settings[key]
		pick.custom_minimum_size.y = 40
		body.add_child(pick)
		picks.append(pick)
	body.add_child(button("High contrast: Gold / Violet",func(): picks[0].selected = 3; picks[1].selected = 4))
	var toggles = {}
	for key in ["eco","water","detail","muted"]:
		var toggle = CheckButton.new()
		toggle.text = {"eco":"Eco graphics (disable shadows)","water":"Animate water","detail":"Show decorative vegetation","muted":"Mute command sounds"}[key]
		toggle.button_pressed = settings[key]
		toggle.custom_minimum_size.y = 36
		body.add_child(toggle)
		toggles[key] = toggle
	var error = label("",13)
	body.add_child(error)
	var footer = HBoxContainer.new()
	settings_panel.add_child(footer)
	var apply = button("Apply settings",func():
		if picks[0].selected == picks[1].selected:
			error.text = "Choose different army colors."
			return
		settings.player = picks[0].selected
		settings.enemy = picks[1].selected
		for key in toggles: settings[key] = toggles[key].button_pressed
		apply_settings()
		close_settings()
	)
	apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(apply)
	footer.add_child(button("Cancel",close_settings))
	layout()
	picks[0].grab_focus()

func close_settings():
	if is_instance_valid(settings_panel):
		settings_panel.queue_free()
		settings_panel = null
		modal.visible = true
		if modal_actions.get_child_count() > 0: modal_actions.get_child(0).grab_focus()

func context_order(screen: Vector2,attack: bool = false):
	var target = view.pick(screen)
	var p = view.ground(screen)
	var ids = selected.filter(func(id): return not sim.entity(id).is_empty() and sim.entity(id).kind == "unit")
	if ids.is_empty():
		for id in selected:
			var b = sim.entity(id)
			if not b.is_empty() and b.kind == "building": b.rally = p.clamp(Vector2(-45,-45),Vector2(45,45))
		return
	var order = {"type":"attackmove" if attack else "move","p":p}
	if not target.is_empty():
		if target.kind == "resource": order = {"type":"gather","target":target.id}
		elif target.team == 1: order = {"type":"attack","target":target.id}
		elif not target.complete: order = {"type":"build","target":target.id}
		elif target.type == "hq": order = {"type":"deliver","target":target.id}
	sim.issue(ids,order,queue_orders or Input.is_key_pressed(KEY_SHIFT))
	acknowledge()
	mode = ""

func click_world(point: Vector2,touch: bool = false):
	if minimap_rect.has_point(point):
		view.focus = (point-minimap_rect.position)/minimap_rect.size*96-Vector2(48,48)
		return
	if mode == "build":
		placement_point = view.ground(point)
		placement_ready = true
		if not touch: confirm_build()
		return
	if mode in ["attack","move"]:
		context_order(point,mode == "attack")
		return
	var target = view.pick(point)
	if not target.is_empty() and target.get("team",-1) == 0:
		if Input.is_key_pressed(KEY_SHIFT):
			if selected.has(target.id): selected.erase(target.id)
			else: selected.append(target.id)
		else: selected = [target.id]
	elif touch and not selected.is_empty(): context_order(point)
	else: selected.clear()
	action_signature = ""

func confirm_build():
	if not placement_ready: return
	for id in selected:
		var w = sim.entity(id)
		if not w.is_empty() and w.type == "worker":
			var b = sim.build(id,building_type,placement_point)
			if not b.is_empty():
				mode = ""
				placement_ready = false
				view.ghost.visible = false
				acknowledge()
			return

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if is_instance_valid(settings_panel): close_settings()
		elif mode != "": mode = ""; view.ghost.visible = false; placement_ready = false
		else: toggle_pause()
		return
	if paused or not started or sim.result != "" or is_instance_valid(settings_panel): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q and not event.ctrl_pressed: mode = "attack"
		if event.keycode == KEY_X: sim.issue(selected,{"type":"stop"})
		if event.keycode == KEY_H: view.focus = Vector2(-25,24)
		if event.keycode == KEY_F and not selected.is_empty():
			var e = sim.entity(selected[0])
			if not e.is_empty(): view.focus = e.p
		var digit = event.physical_keycode if event.physical_keycode else event.keycode
		if digit >= KEY_1 and digit <= KEY_9:
			if event.ctrl_pressed or event.shift_pressed: groups[digit] = selected.duplicate()
			else: selected = groups.get(digit,[]).filter(func(id): return not sim.entity(id).is_empty())
	if event is InputEventMouseButton:
		touch_active = false
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: view.zoom -= 3
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: view.zoom += 3
		if event.button_index == MOUSE_BUTTON_MIDDLE: middle_down = event.pressed
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if minimap_rect.has_point(event.position):
				var p = (event.position-minimap_rect.position)/minimap_rect.size*96-Vector2(48,48)
				sim.issue(selected,{"type":"move","p":p},event.shift_pressed)
			else: context_order(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				pointer_down = true
				pointer_start = event.position
				pointer_now = event.position
				dragging = false
			elif pointer_down:
				if dragging and mode == "":
					var rect = Rect2(pointer_start,event.position-pointer_start).abs()
					if not event.shift_pressed: selected.clear()
					for e in sim.own(0):
						if e.kind == "unit" and rect.has_point(view.camera.unproject_position(Vector3(e.p.x,1,e.p.y))) and not selected.has(e.id): selected.append(e.id)
				else: click_world(event.position)
				pointer_down = false
				dragging = false
	if event is InputEventMouseMotion:
		pointer_now = event.position
		if pointer_down and pointer_now.distance_to(pointer_start) > 7: dragging = true
		if middle_down: view.focus += view.ground(event.position-event.relative)-view.ground(event.position)
		if mode == "build": placement_point = view.ground(event.position)
	if event is InputEventScreenTouch:
		touch_active = true
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 1:
				pointer_start = event.position
				dragging = false
				multi_gesture = false
			else: multi_gesture = true
		else:
			if touches.has(event.index) and touches.size() == 1 and not dragging and not multi_gesture: click_world(event.position,true)
			touches.erase(event.index)
	if event is InputEventScreenDrag and touches.has(event.index):
		var previous = touches[event.index]
		if touches.size() == 2:
			var other = touches.values()[0] if touches.keys()[0] != event.index else touches.values()[1]
			view.zoom *= maxf(1,previous.distance_to(other))/maxf(1,event.position.distance_to(other))
		else:
			if event.position.distance_to(pointer_start) > 9: dragging = true
			if dragging: view.focus += view.ground(previous)-view.ground(event.position)
		touches[event.index] = event.position

func refresh_ui():
	selected = selected.filter(func(id): return not sim.entity(id).is_empty())
	var pop = sim.population(0)
	resource_label.text = "ALLOY %d   ENERGY %d   CREW %d + %d / %d" % [sim.players[0].alloy,sim.players[0].energy,pop.used,pop.reserved,pop.cap]
	var workers = sim.own(0).filter(func(e): return e.type == "worker")
	var idle = workers.filter(func(e): return e.orders.is_empty())
	var harvest = workers.any(func(e): return not e.orders.is_empty() and e.orders[0].type in ["gather","deliver"])
	var supply = sim.own(0).any(func(e): return e.type == "relay" and e.complete)
	var army_size = sim.own(0).filter(func(e): return e.kind == "unit" and e.type != "worker").size()
	objective.text = ("1 / 4  Assign workers to alloy and energy" if not harvest else ("2 / 4  Construct a Supply relay" if not supply else ("3 / 4  Train an army of eight" if army_size < 8 else "4 / 4  Attack across the river")))+"\nIdle workers: "+str(idle.size())
	for e in sim.entities:
		if e.team == 1 and e.kind == "building" and sim.seen(e.p): known_buildings[e.id] = {"p":e.p,"type":e.type}
	for id in known_buildings.keys():
		if sim.seen(known_buildings[id].p) and sim.entity(id).is_empty(): known_buildings.erase(id)
	var entities = selected.map(func(id): return sim.entity(id))
	selection_label.text = "%d UNITS SELECTED" % selected.size() if selected.size() > 1 else (entities[0].name.to_upper() if entities.size() == 1 else "COMMAND YOUR EXPEDITION")
	var signature = str(selected)+mode+str(queue_orders)
	info_label.text = "Select troops or a building. Harvest alloy and energy to expand."
	if not entities.is_empty():
		var e = entities[0]
		info_label.text = "%s · %d / %d HP" % [e.role,e.hp,e.max_hp]
		if not e.complete: info_label.text += " · Building %d%%" % (e.progress*100)
		if not e.queue.is_empty(): info_label.text += " · %s %d%% %s" % [Catalog.get_def(e.queue[0].type).name,mini(100,int(e.queue[0].elapsed/Catalog.get_def(e.queue[0].type).time*100)),e.queue[0].blocked]
		signature += str(e.complete)+str(e.queue.map(func(q): return q.type))
	notice.text = "Place %s: tap ground, then Confirm. %s" % [building_type,sim.placement(building_type,placement_point)] if mode == "build" else ("Attack-move: choose a destination." if mode == "attack" else sim.message)
	if signature == action_signature: return
	action_signature = signature
	clear_children(actions)
	if mode == "build":
		actions.add_child(button("Confirm site",confirm_build))
		actions.add_child(button("Cancel",func(): mode = ""; placement_ready = false; view.ghost.visible = false))
		return
	if entities.is_empty():
		actions.add_child(button("Select army",func(): selected = sim.own(0).filter(func(e): return e.kind == "unit" and e.type != "worker").map(func(e): return e.id)))
		actions.add_child(button("Select workers",func(): selected = sim.own(0).filter(func(e): return e.type == "worker").map(func(e): return e.id)))
		actions.add_child(button("Idle workers",func(): selected = sim.own(0).filter(func(e): return e.type == "worker" and e.orders.is_empty()).map(func(e): return e.id)))
		return
	var e = entities[0]
	if e.kind == "building":
		if not e.complete: actions.add_child(button("Cancel site · 75% refund",func(): sim.cancel_building(e.id)))
		else:
			for type in e.get("trains",[]):
				var d = Catalog.get_def(type)
				actions.add_child(button("%s · %d/%d" % [d.name,d.cost[0],d.cost[1]],func(): sim.enqueue(e.id,type)))
			for i in range(e.queue.size()): actions.add_child(button("Cancel #"+str(i+1),func(): sim.cancel_queue(e.id,i)))
	else:
		if entities.any(func(u): return u.type == "worker"):
			for type in ["relay","barracks","foundry","tower","hq"]:
				var d = Catalog.get_def(type)
				actions.add_child(button("%s %d/%d" % [d.name,d.cost[0],d.cost[1]],func(): building_type = type; mode = "build"; placement_ready = false))
		else:
			actions.add_child(button("Move",func(): mode = "move"))
			actions.add_child(button("Attack-move",func(): mode = "attack"))
		actions.add_child(button("Stop",func(): sim.issue(selected,{"type":"stop"})))
		actions.add_child(button("Queue: ON" if queue_orders else "Queue: OFF",func(): queue_orders = not queue_orders))

func _process(dt):
	if not sim: return
	if not paused and started and sim.result == "":
		accumulator += minf(dt,0.2)
		while accumulator >= 0.05:
			sim.tick(0.05)
			accumulator -= 0.05
		var pan = Vector2(float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))-float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))-float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
		view.focus += pan*view.zoom*0.65*dt
	view.selected = selected
	view.refresh(dt if not paused else 0.0)
	view.ghost.visible = mode == "build" and not paused
	if view.ghost.visible:
		view.ghost.position = Vector3(placement_point.x,0.18,placement_point.y)
		view.ghost.scale = Vector3(Catalog.get_def(building_type).radius,1,Catalog.get_def(building_type).radius)
		view.ghost.material_override.albedo_color = Color(0.4,1,0.65,0.5) if sim.placement(building_type,placement_point) == "" else Color(1,0.3,0.25,0.5)
	ui_clock -= dt
	if ui_clock <= 0:
		refresh_ui()
		overlay.queue_redraw()
		if test_enabled: publish_state()
		ui_clock = 0.1
	if sim.result != "" and not paused:
		paused = true
		modal.visible = true
		scrim.visible = true
		scenario.visible = false
		modal_title.text = {"victory":"THE FRONTIER IS YOURS","defeat":"EXPEDITION LOST","draw":"STALEMATE"}[sim.result]
		modal_desc.text = "Match complete in %d:%02d.\n\nEnemy units destroyed: %d\nRebuild your strategy and deploy again." % [int(sim.time)/60,int(sim.time)%60,sim.players[0].kills]
		clear_children(modal_actions)
		modal_actions.add_child(button("New expedition",restart_match))

func test_call(args):
	if args.is_empty(): return
	var command = JSON.parse_string(str(args[0]))
	if not command is Dictionary: return
	match command.get("action",""):
		"start": start_match(); sim.ai_enabled = false
		"step":
			for i in range(mini(12000,int(command.get("seconds",1)*20))): sim.tick(0.05)
		"select": selected = command.ids
		"order":
			var o = command.order
			if o.has("p"): o.p = Vector2(o.p[0],o.p[1])
			sim.issue(selected,o)
		"build": sim.build(int(command.worker),command.type,Vector2(command.x,command.z))
		"train": sim.enqueue(int(command.id),command.type)
		"restart": restart_match()
		"camera": view.focus = Vector2(command.x,command.z); view.zoom = command.get("zoom",44)
		"reveal": sim.visible[0].fill(1); sim.explored[0].fill(1); sim.vision_clock = 9999
		"outcome":
			for e in sim.own(int(command.get("team",1))):
				if e.type == "hq": e.hp = 0
			sim.tick(0.05)
		"benchmark":
			sim.ai_enabled = false
			for i in range(93): sim.spawn("ranger",0,Vector2(-40+(i%15)*2.2,8+floori(float(i)/15)*2.3))
			view.focus = Vector2(-22,18)
			view.zoom = 55
	refresh_ui()
	view.refresh(0)
	publish_state()

func publish_state():
	var list = []
	for e in sim.entities+sim.deposits:
		var point = view.camera.unproject_position(Vector3(e.p.x,1.2,e.p.y))
		list.append({"id":e.id,"type":e.type,"team":e.get("team",-1),"x":e.p.x,"z":e.p.y,"screen":[point.x,point.y],"hp":e.get("hp",0),"amount":e.get("amount",0),"complete":e.get("complete",true),"orders":e.get("orders",[]).map(func(o): return o.type),"queue":e.get("queue",[]).map(func(q): return q.type)})
	var buttons = []
	collect_buttons(ui,buttons)
	var state = {"ready":true,"started":started,"paused":paused,"result":sim.result,"time":sim.time,"selected":selected,"population":sim.population(0),"alloy":sim.players[0].alloy,"energy":sim.players[0].energy,"entities":list,"buttons":buttons,"settings":settings,"settings_open":is_instance_valid(settings_panel),"models":view.objects.size(),"focus":[view.focus.x,view.focus.y],"zoom":view.zoom,"mode":mode,"viewport":[ui.size.x,ui.size.y]}
	state.last_key = last_key
	state.groups = groups
	state.draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	state.render_objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	state.nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	JavaScriptBridge.eval("window.frontierState="+JSON.stringify(state))

func collect_buttons(node: Node,list: Array):
	if node is Button and node.is_visible_in_tree():
		var rect = node.get_global_rect()
		list.append({"text":node.text,"x":rect.position.x,"y":rect.position.y,"w":rect.size.x,"h":rect.size.y})
	for child in node.get_children(): collect_buttons(child,list)

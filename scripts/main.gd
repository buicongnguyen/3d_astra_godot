extends Node3D
const Simulation = preload("res://scripts/simulation.gd")
const WorldView = preload("res://scripts/world_view.gd")
const Overlay = preload("res://scripts/overlay.gd")
const Catalog = preload("res://scripts/catalog.gd")
const WorkButton = preload("res://scripts/work_button.gd")
const WorkActivity = preload("res://scripts/activity.gd")
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
var stat_row: HBoxContainer
var stat_labels: Array = []
var queue_strip: HBoxContainer
var queue_signature = ""
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
var build_feedback = ""
var ui_action_serial = 0
var action_pager: HBoxContainer
var action_page = 0
var action_context = ""
var test_manual_clock = false
var action_pages = 1
var mobile_layout = false
var touch_device = false
var landscape_layout = false
var guide_panel: Panel
var guide_was_paused = true
var hotkey_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/hotkeys.json"))
var last_group = 0
var last_group_time = 0

func _input(event):
	if event is InputEventKey and handle_hotkey(event):
		get_viewport().set_input_as_handled()
		return
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
	if OS.has_feature("web"):
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	touch_device = bool(JavaScriptBridge.eval("matchMedia('(pointer: coarse)').matches")) if OS.has_feature("web") else DisplayServer.is_touchscreen_available()
	settings.eco = touch_device
	load_settings()
	sim = Simulation.new()
	view = WorldView.new()
	add_child(view)
	view.setup(sim)
	make_ui()
	make_audio()
	apply_settings()
	show_briefing()
	# Finish the engine's resize before changing its logical content size.
	get_viewport().size_changed.connect(layout,CONNECT_DEFERRED)
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

func button(text: String,callback: Callable,key: String = "") -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0,44)
	b.add_theme_font_size_override("font_size",14)
	if key == "":
		var aliases = {"Home":"H","Move":"M","Attack-move":"F","Support":"R","Stop":"X","Info & stats":"I","Field guide":"I","Pause":"Space","Select army":"F2","Select workers":"F3","Idle workers":"F1","Cancel upgrade":"Backspace","Cancel site · 75% refund":"Backspace"}
		key = aliases.get(text,"")
		if text.begins_with("Upgrade L"): key = "U"
		if text.begins_with("Queue:"): key = "O"
	if key != "":
		b.tooltip_text = key+" · "+text
		var hint = Label.new()
		hint.text = key; hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.add_theme_font_size_override("font_size",9)
		hint.add_theme_color_override("font_color",Color("a5e3bf"))
		b.add_child(hint)
		hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		hint.position.y = 1; hint.position.x = -5-hint.get_minimum_size().x
		hint.visible = not touch_device
	b.pressed.connect(func():
		callback.call()
		ui_action_serial += 1
	)
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
	nav_buttons.add_child(button("Home",func(): run_shortcut("hq")))
	nav_buttons.add_child(button("−",func(): view.zoom += 5))
	nav_buttons.add_child(button("+",func(): view.zoom -= 5))
	nav_buttons.add_child(button("Pause",toggle_pause))
	nav_buttons.add_child(button("Keys",show_shortcuts,"?"))
	bottom = Panel.new()
	ui.add_child(bottom)
	selection_label = label("SELECT YOUR EXPEDITION",18)
	bottom.add_child(selection_label)
	info_label = label("",13)
	info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	info_label.clip_text = true
	info_label.mouse_filter = Control.MOUSE_FILTER_PASS
	bottom.add_child(info_label)
	stat_row = HBoxContainer.new()
	stat_row.add_theme_constant_override("separation",6)
	bottom.add_child(stat_row)
	for title in ["HP","Shield","ATK","Restore"]:
		var value = label(title,12)
		value.clip_text = true
		value.mouse_filter = Control.MOUSE_FILTER_PASS
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_row.add_child(value)
		stat_labels.append(value)
	queue_strip = HBoxContainer.new()
	queue_strip.add_theme_constant_override("separation",4)
	queue_strip.visible = false
	bottom.add_child(queue_strip)
	actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation",6)
	actions.add_theme_constant_override("v_separation",6)
	action_scroll = ScrollContainer.new()
	# SHOW_NEVER avoids propagating the previous page's minimum width on rotation.
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	bottom.add_child(action_scroll)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_scroll.add_child(actions)
	action_pager = HBoxContainer.new()
	action_pager.add_theme_constant_override("separation",6)
	bottom.add_child(action_pager)
	action_pager.add_child(button("Previous",func(): action_page -= 1; arrange_actions()))
	var page_label = label("",13)
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_pager.add_child(page_label)
	action_pager.add_child(button("More actions",func(): action_page += 1; arrange_actions()))
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
	scenario.add_item("Meridian Riverlands · 96×96")
	scenario.add_item("Ashen Frontier · 96×96")
	scenario.add_item("Copper Basin · 128×128")
	scenario.add_item("Frontier Expanse · 160×160")
	scenario.custom_minimum_size.y = 40
	modal_body.add_child(scenario)
	modal_actions = VBoxContainer.new()
	modal.add_child(modal_actions)
	refresh_ui()

func layout():
	if not ui: return
	if OS.has_feature("web"):
		# Browser touch coordinates and CSS layout use logical pixels, not DPR-scaled canvas pixels.
		var css_size = Vector2i(int(JavaScriptBridge.eval("document.getElementById('canvas').clientWidth")),int(JavaScriptBridge.eval("document.getElementById('canvas').clientHeight")))
		if css_size.x > 0 and css_size.y > 0 and get_window().content_scale_size != css_size:
			get_window().content_scale_size = css_size
			layout.call_deferred()
			return
	var size = get_viewport().get_visible_rect().size
	mobile_layout = size.x < 540 or (size.x < 960 and size.y < 540) or (touch_device and size.x < 1100)
	landscape_layout = mobile_layout and size.x > size.y
	var narrow = mobile_layout
	var field_width = size.x-300 if landscape_layout else size.x
	header.position = Vector2(10,10)
	header.size = Vector2(field_width-20,98 if narrow else 68)
	title_label.position = Vector2(12,9)
	title_label.add_theme_font_size_override("font_size",16 if narrow else 20)
	resource_label.position = Vector2(12,35 if narrow else 36)
	resource_label.add_theme_font_size_override("font_size",11 if size.x < 360 or landscape_layout else (13 if narrow else 15))
	nav_buttons.position = Vector2(12,57) if narrow else Vector2(size.x-330,12)
	var height = 250 if narrow else 170
	bottom.position = Vector2(10,size.y-height-10)
	bottom.size = Vector2(size.x-20,height)
	if landscape_layout:
		bottom.position = Vector2(size.x-290,10)
		bottom.size = Vector2(280,size.y-20)
		height = bottom.size.y
	selection_label.position = Vector2(12,10)
	selection_label.add_theme_font_size_override("font_size",15 if narrow else 18)
	stat_row.position = Vector2(12,34)
	stat_row.size = Vector2(minf(300,bottom.size.x-24),37)
	info_label.position = Vector2(12,73)
	info_label.size = Vector2(bottom.size.x-24 if narrow else 300,17)
	info_label.add_theme_font_size_override("font_size",12)
	queue_strip.position = Vector2(12,92)
	queue_strip.size = Vector2(minf(300,bottom.size.x-24),44)
	action_scroll.position = Vector2(12,140 if queue_strip.visible else 92) if narrow else Vector2(324,12)
	action_scroll.size = Vector2(bottom.size.x-action_scroll.position.x-12,height-action_scroll.position.y-10)
	action_pager.position = Vector2(12,height-54)
	action_pager.size = Vector2(bottom.size.x-24,44)
	if mobile_layout: action_scroll.size.y = action_pager.position.y-action_scroll.position.y-8
	arrange_actions.call_deferred()
	notice.position = Vector2(16,bottom.position.y-70)
	notice.size = Vector2(field_width-32,64)
	if landscape_layout: notice.position = Vector2(16,size.y-72)
	var minimap_size = 100 if narrow else 154
	minimap_rect = Rect2(field_width-minimap_size-18,header.position.y+header.size.y+12,minimap_size,minimap_size)
	objective.position = Vector2(18,header.position.y+header.size.y+12)
	objective.size = Vector2(maxf(100,field_width-minimap_size-60),55)
	modal.size = Vector2(minf(490,size.x-30),minf(490,size.y-30))
	modal.position = (size-modal.size)*0.5
	modal_scroll.position = Vector2(24,22)
	var footer_height = modal_actions.get_child_count()*44+maxi(0,modal_actions.get_child_count()-1)*4
	modal_scroll.size = modal.size-Vector2(48,footer_height+58)
	modal_actions.position = Vector2(24,modal.size.y-footer_height-22)
	modal_actions.size = Vector2(modal.size.x-48,footer_height)
	if is_instance_valid(settings_panel):
		settings_panel.size = Vector2(minf(470,size.x-24),minf(560,size.y-24))
		settings_panel.position = (size-settings_panel.size)*0.5
		settings_panel.get_child(0).size = settings_panel.size-Vector2(36,82)
		settings_panel.get_child(1).position = Vector2(18,settings_panel.size.y-55)
		settings_panel.get_child(1).size = Vector2(settings_panel.size.x-36,40)
	if is_instance_valid(guide_panel):
		guide_panel.size = Vector2(minf(560,size.x-24),minf(640,size.y-24))
		guide_panel.position = (size-guide_panel.size)*0.5
		guide_panel.get_child(0).size = guide_panel.size-Vector2(32,80)
		guide_panel.get_child(1).position = Vector2(16,guide_panel.size.y-54)
		guide_panel.get_child(1).size = Vector2(guide_panel.size.x-32,40)

func arrange_actions():
	if not is_instance_valid(action_pager): return
	var count = actions.get_child_count()
	var per_page = mini(4 if landscape_layout else 2,maxi(1,floori((action_scroll.size.y+6)/50)))
	action_pages = maxi(1,ceili(float(count)/per_page)) if mobile_layout else 1
	action_page = clampi(action_page,0,action_pages-1)
	action_pager.visible = mobile_layout and count > 0
	action_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if mobile_layout else ScrollContainer.SCROLL_MODE_AUTO
	for i in range(count):
		var child = actions.get_child(i)
		child.visible = not mobile_layout or i/per_page == action_page
		child.custom_minimum_size.x = action_scroll.size.x-2 if mobile_layout else child.get_meta("stable_width",0)
	action_pager.get_child(0).disabled = action_page == 0
	action_pager.get_child(1).text = "%d / %d" % [action_page+1,action_pages]
	action_pager.get_child(2).disabled = action_page == action_pages-1
	if test_enabled: publish_state.call_deferred()

func clear_children(node: Node):
	if node == modal_actions: layout.call_deferred()
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func show_briefing():
	paused = true
	modal.visible = true
	scrim.visible = true
	scenario.visible = true
	modal_title.text = "FRONTIER COMMAND"
	modal_desc.text = "MERIDIAN EXPEDITION · GODOT EDITION\n\nBuild an outpost. Command a mixed army. Cross the river and destroy the enemy Command core.\n\nDesktop: drag to select · right-click orders\nWASD pan · wheel zoom · F attack-move · B build · ? shortcuts\nTouch: tap select/order · drag pan · pinch zoom"
	clear_children(modal_actions)
	modal_actions.add_child(button("Deploy expedition",start_match))
	modal_actions.add_child(button("Army & graphics settings",show_settings))

func start_match():
	var stage_id = ["riverlands","classic","basin","expanse"][scenario.selected]
	if sim.map_id != stage_id: reset_sim(scenario.selected == 0,stage_id)
	started = true
	paused = false
	modal.visible = false
	scrim.visible = false
	selected = sim.own(0).filter(func(e): return e.type == "worker").map(func(e): return e.id)
	action_signature = ""
	acknowledge()

func reset_sim(river: bool, stage_id: String = ""):
	test_manual_clock = false
	sim = Simulation.new(true,river,stage_id)
	view.sim = sim
	view.build_map()
	view.focus = Vector2(-20-sim.map_config.offset,20+sim.map_config.offset)
	view.zoom = 44
	selected.clear()
	groups.clear()
	known_buildings.clear()
	mode = ""
	placement_ready = false
	build_feedback = ""
	pointer_down = false
	touches.clear()
	accumulator = 0
	action_signature = ""
	apply_settings()

func restart_match():
	reset_sim(sim.nav.river,sim.map_id)
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
		modal_desc.text = "The battlefield is paused.\n\nX stops selected units. Shift queues orders.\nCtrl + 1–9 saves groups; Shift adds; 1–9 recalls.\nHome focuses selection. H selects the core. B opens construction. Keys lists all shortcuts.\nSelect a building, then right-click for its rally point."
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
		toggle.custom_minimum_size.y = 44
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

func guide_text(type: String) -> String:
	var d = Catalog.get_def(type)
	var text = d.description+"

"
	text += "BASE STATS (LEVEL 1)
HP: %d   Shield: %d
Attack: %s per hit" % [d.hp,d.shield,str(d.get("damage",0))]
	if d.get("damage",0) > 0: text += " every %.2fs · Range: %.1f" % [d.interval,d.range]
	else: text += " (cannot attack)"
	text += "
Shields absorb damage before HP, then recharge at 4/s after 5 seconds without damage."
	text += "
Cost: %d alloy / %d energy · Time: %ds" % [d.cost[0],d.cost[1],d.time]
	if type == "worker":
		text += "\nHarvesters gather up to 10 resources and deliver to a completed friendly Command core. After depletion, remaining cargo is delivered and work resumes at an explored, reachable deposit of the same type within 30 world units. Queued orders take priority. Missing deposits or completed cores produce a message; cargo is preserved."
	if d.kind == "unit":
		text += "
Supply: %d · Speed: %.1f" % [d.pop,d.speed]
		if d.has("counter"): text += "
Deals 1.6× damage to "+Catalog.get_def(d.counter).name+"."
		if d.has("support"): text += "
Restores %d HP every second within range %.0f; no resource cost. Does not refill shields or revive destroyed targets." % [d.support,d.range]
		if d.has("required_level"): text += "
Requires level "+str(d.required_level)+" "+("Barracks" if type in ["medic","antitank"] else "Foundry")+"."
	else:
		text += "

BUILDING FUNCTIONS"
		for item in d.get("trains",[]):
			var unit = Catalog.get_def(item)
			text += "
• %s%s — %d alloy / %d energy" % [unit.name," (level %d)" % unit.required_level if unit.get("required_level",1) > 1 else "",unit.cost[0],unit.cost[1]]
		if d.has("supply"): text += "
• Provides %d supply at level 1." % d.supply
		text += "

UPGRADES
L2: +25% base HP, +25 shield. L3: +50% base HP, +50 shield total. Production runs 20% / 40% faster. Towers gain 25% / 50% base attack; Relays gain 5 / 10 supply."
		text += "
Command core: L2 200/100, L3 350/175. Other buildings: L2 100/50, L3 200/100 (alloy/energy). Upgrades take 20s / 30s."
		text += "
Other buildings require a completed Command core at the next level. Finish or cancel production first. Cancel an upgrade for a full refund; destruction gives no refund."
	text += "

MATCH STAGES
1. Establish an economy and mixed army.
2. Upgrade your core and production buildings to L2; add Medics, Engineers and Anti-tank soldiers.
3. Reach L3 to unlock Battle tanks at the Foundry and strengthen your base, then destroy the enemy cores.
These are technology stages within each selectable skirmish stage."
	return text

func show_guide(type: String = "hq"):
	if is_instance_valid(guide_panel): return
	guide_was_paused = paused
	paused = true
	modal.visible = false
	scrim.visible = true
	guide_panel = Panel.new()
	ui.add_child(guide_panel)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(16,16)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	guide_panel.add_child(scroll)
	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",12)
	scroll.add_child(body)
	body.add_child(label("FIELD GUIDE · 8 UNIT TYPES",20))
	var pick = OptionButton.new()
	pick.custom_minimum_size.y = 44
	var keys = ["hq","relay","barracks","foundry","tower","worker","vanguard","ranger","breaker","medic","engineer","tank","antitank"]
	for key in keys: pick.add_item(Catalog.get_def(key).name)
	pick.selected = maxi(0,keys.find(type))
	body.add_child(pick)
	var detail = label(guide_text(keys[pick.selected]),14)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(detail)
	pick.item_selected.connect(func(index): detail.text = guide_text(keys[index]))
	guide_panel.add_child(button("Close field guide",close_guide))
	layout()

func close_guide():
	if not is_instance_valid(guide_panel): return
	guide_panel.queue_free()
	guide_panel = null
	paused = guide_was_paused
	modal.visible = paused
	scrim.visible = paused

func context_order(screen: Vector2,attack: bool = false):
	var target = view.pick(screen)
	var p = view.ground(screen)
	var ids = selected.filter(func(id): return not sim.entity(id).is_empty() and sim.entity(id).kind == "unit")
	if ids.is_empty():
		mode = ""
		for id in selected:
			var b = sim.entity(id)
			if b.get("kind","") == "building" and b.complete and not b.get("trains",[]).is_empty():
				b.rally = p.clamp(Vector2.ONE*(-sim.nav.half+3),Vector2.ONE*(sim.nav.half-3))
				sim.message = "Rally point set. New units will move here."
		return
	if mode == "rally":
		for id in selected:
			var b = sim.entity(id)
			if b.get("kind","") == "building" and b.complete and not b.get("trains",[]).is_empty(): b.rally = p
		mode = ""; return
	if mode == "target_attack":
		if target.is_empty() or target.get("team",-1) <= 0 or not sim.seen(target.p,0):
			sim.message = "Attack: choose a visible enemy unit or building."
			return
		sim.issue(ids.filter(func(id): return sim.entity(id).get("damage",0) > 0),{"type":"attack","target":target.id},queue_orders or Input.is_key_pressed(KEY_SHIFT))
		acknowledge()
		mode = ""
		return
	var order = {"type":"patrol" if mode == "patrol" else ("attackmove" if attack else "move"),"p":p}
	if mode == "support":
		var helpers = ids.filter(func(id): return sim.entity(id).get("support",0) > 0)
		if target.is_empty() or not helpers.any(func(id): return sim.support_valid(sim.entity(id),target)):
			sim.message = "Medic: select allied infantry. Engineer: select a completed building or vehicle."
			return
		sim.issue(helpers,{"type":"support","target":target.id},queue_orders or Input.is_key_pressed(KEY_SHIFT))
		mode = ""
		return
	if not target.is_empty() and not mode in ["move","attack","patrol"]:
		if target.get("team",-1) == 0:
			sim.issue(ids,{"type":"support","target":target.id},queue_orders or Input.is_key_pressed(KEY_SHIFT))
			ids = ids.filter(func(id): return sim.entity(id).get("support",0) <= 0)
		if target.kind == "resource": order = {"type":"gather","target":target.id}
		elif target.team == 1: order = {"type":"attack","target":target.id}
		elif not target.complete: order = {"type":"build","target":target.id}
		elif target.type == "hq": order = {"type":"deliver","target":target.id}
	sim.issue(ids,order,queue_orders or Input.is_key_pressed(KEY_SHIFT))
	acknowledge()
	mode = ""

func click_world(point: Vector2,touch: bool = false):
	if minimap_rect.has_point(point):
		view.focus = (point-minimap_rect.position)/minimap_rect.size*(sim.nav.half*2)-Vector2.ONE*sim.nav.half
		return
	if mode == "build":
		placement_point = view.ground(point)
		build_feedback = ""
		placement_ready = true
		if not touch: confirm_build()
		return
	if mode in ["attack","move","support","context","rally","patrol","target_attack"]:
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

func begin_build(type: String):
	var missing = sim.construction_requirements(type)
	if missing != "":
		sim.feedback(missing,0)
		mode = ""
		view.ghost.visible = false
	else:
		building_type = type
		mode = "build"
	placement_ready = false
	build_feedback = ""
	refresh_ui()

func confirm_build():
	if not placement_ready:
		build_feedback = "Choose a construction site on the ground first."
		return
	for id in selected:
		var w = sim.entity(id)
		if not w.is_empty() and w.type == "worker":
			var b = sim.build(id,building_type,placement_point)
			if not b.is_empty():
				mode = ""
				placement_ready = false
				view.ghost.visible = false
				acknowledge()
			else: build_feedback = sim.message
			return
	build_feedback = "Select a Harvester to construct this building."

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if is_instance_valid(guide_panel): close_guide()
		elif is_instance_valid(settings_panel): close_settings()
		elif mode != "": mode = ""; view.ghost.visible = false; placement_ready = false
		else: toggle_pause()
		return
	if paused or not started or sim.result != "" or is_instance_valid(settings_panel): return
	if event is InputEventMouseButton:
		touch_active = false
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: view.zoom -= 3
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: view.zoom += 3
		if event.button_index == MOUSE_BUTTON_MIDDLE: middle_down = event.pressed
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if minimap_rect.has_point(event.position):
				var p = (event.position-minimap_rect.position)/minimap_rect.size*(sim.nav.half*2)-Vector2.ONE*sim.nav.half
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
		if mode == "build":
			placement_point = view.ground(event.position)
			build_feedback = ""
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
	objective.text = "Tech %d / 3 · " % sim.tech_level(0)+("1 / 4  Assign workers to alloy and energy" if not harvest else ("2 / 4  Construct a Supply relay" if not supply else ("3 / 4  Train an army of eight" if army_size < 8 else "4 / 4  Destroy the enemy Command core")))+"\nIdle workers: "+str(idle.size())
	for e in sim.entities:
		if e.team == 1 and e.kind == "building" and sim.seen(e.p): known_buildings[e.id] = {"p":e.p,"type":e.type}
	for id in known_buildings.keys():
		if sim.seen(known_buildings[id].p) and sim.entity(id).is_empty(): known_buildings.erase(id)
	var entities = selected.map(func(id): return sim.entity(id))
	refresh_queue(entities[0] if entities.size() == 1 else {})
	refresh_work_actions(entities[0] if entities.size() == 1 else {})
	selection_label.text = "%d UNITS SELECTED" % selected.size() if selected.size() > 1 else (entities[0].name.to_upper() if entities.size() == 1 else "COMMAND YOUR EXPEDITION")
	var signature = str(selected)+mode+str(queue_orders)
	stat_row.visible = not entities.is_empty()
	info_label.text = "Select a unit or building."
	if not entities.is_empty():
		var e = entities[0]
		selection_label.text += " · L%d" % e.level if e.kind == "building" else ""
		var hp = 0.0; var max_hp = 0.0; var shield = 0.0; var max_shield = 0.0
		for item in entities:
			hp += item.hp; max_hp += item.max_hp; shield += item.shield; max_shield += item.max_shield
		stat_labels[0].text = "HP\n%s/%s" % [compact_stat(hp),compact_stat(max_hp)]
		stat_labels[0].tooltip_text = "Health %d of %d" % [ceili(hp),max_hp]
		stat_labels[1].text = "Shield\n%s/%s" % [compact_stat(shield),compact_stat(max_shield)]
		stat_labels[1].tooltip_text = "Shield %d of %d" % [ceili(shield),max_shield]
		stat_labels[2].text = "%s\n%s" % ["ATK*" if entities.size() > 1 else "ATK",str(snappedf(sim.attack_value(e),0.1))]
		stat_labels[2].tooltip_text = "Attack of first selected unit" if entities.size() > 1 else "Attack damage per hit"
		stat_labels[3].visible = entities.size() == 1 and e.get("support",0) > 0
		stat_labels[3].text = "Restore\n%d/s" % e.get("support",0)
		info_label.text = "Operational" if e.kind == "building" else ("Standing by" if e.orders.is_empty() else e.orders[0].type.capitalize())
		if e.carry > 0: info_label.text = "Cargo %d/10 %s" % [e.carry,e.carry_type]
		if not e.complete: info_label.text = "Needs Harvester" if WorkActivity.building(sim,e).label == "Needs Harvester" else " "
		elif not e.level_job.is_empty(): info_label.text = " "
		elif not e.queue.is_empty():
			var q = e.queue[0]
			info_label.text = q.blocked if q.blocked != "" else " "
		info_label.tooltip_text = info_label.text
		signature += str(e.level)
	if mode == "build":
		var error = sim.placement(building_type,placement_point) if placement_ready or not touch_active else ""
		notice.text = build_feedback if build_feedback != "" else (error if error != "" else "Place %s: %s" % [Catalog.get_def(building_type).name,"tap ground, then Confirm site." if touch_active else "click a valid site to build."])
	else:
		var mode_hints = {"support":"Support: choose a friendly target to follow and restore.","attack":"Attack-move: choose a destination.","move":"Move: choose a destination to withdraw.","context":"Context: choose a deposit, enemy or friendly construction site.","rally":"Rally: choose a destination for newly trained units."}
		notice.text = mode_hints.get(mode,sim.message)
		if mode == "patrol": notice.text = "Patrol: choose the other end of a repeating route."
		if mode == "target_attack": notice.text = "Attack: choose a visible enemy unit or building."
		if mode == "" and (notice.text.ends_with(" construction started.") or notice.text.contains(" upgrading to level ")): notice.text = ""
		if mode == "" and not entities.is_empty() and entities[0].kind == "building" and notice.text == "Assign Harvesters to the amber alloy deposits.": notice.text = ""
	notice.add_theme_color_override("font_color",Color("ffd58a") if mode == "build" or sim.message.begins_with("Need ") or sim.message.begins_with("Build ") or sim.message.begins_with("Finish ") else Color("e1ebe2"))
	if signature == action_signature: return
	action_signature = signature
	var context = str(selected)+"|"+mode
	if action_context != context: action_page = 0
	action_context = context
	clear_children(actions)
	arrange_actions.call_deferred()
	if mode == "build":
		actions.add_child(button("Confirm site",confirm_build))
		actions.add_child(button("Cancel",func(): mode = ""; placement_ready = false; view.ghost.visible = false))
		return
	if entities.is_empty():
		actions.add_child(button("Field guide",func(): show_guide()))
		actions.add_child(button("Select army",func(): selected = sim.own(0).filter(func(e): return e.kind == "unit" and e.type != "worker").map(func(e): return e.id)))
		actions.add_child(button("Select workers",func(): selected = sim.own(0).filter(func(e): return e.type == "worker").map(func(e): return e.id)))
		actions.add_child(button("Idle workers",func(): selected = sim.own(0).filter(func(e): return e.type == "worker" and e.orders.is_empty()).map(func(e): return e.id)))
		return
	var e = entities[0]
	if e.kind != "building" or entities.size() > 1: actions.add_child(button("Info & stats",func(): show_guide(e.type)))
	if entities.size() == 1 and e.kind == "building":
		for type in e.get("trains",[]):
			var d = Catalog.get_def(type)
			var train = button("%s · %d/%d" % [d.name,d.cost[0],d.cost[1]],func(): sim.enqueue(e.id,type),hotkey_config.actionKeys[e.trains.find(type)])
			train.set_meta("work_action","train"); actions.add_child(train)
		actions.add_child(button("Info & stats",func(): show_guide(e.type)))
		var cost = sim.level_cost(e)
		var upgrade = button("Upgrade L%d · %d/%d" % [e.level+1,cost[0],cost[1]] if e.level < 3 else "Maximum level 3",func(): sim.upgrade_building(e.id))
		upgrade.set_meta("work_action","upgrade"); actions.add_child(upgrade)
		upgrade.set_meta("stable_width",180)
		refresh_work_actions.call_deferred(e)
	else:
		if entities.any(func(u): return u.type == "worker"):
			actions.add_child(button("Attack",func(): run_shortcut("attack"),"N"))
			actions.add_child(button("Move",func(): run_shortcut("move"),"M"))
			for type in ["relay","barracks","foundry","tower","hq"]:
				var d = Catalog.get_def(type)
				actions.add_child(button("%s %d/%d" % [d.name,d.cost[0],d.cost[1]],func(): begin_build(type),hotkey_config.actionKeys[["relay","barracks","foundry","tower","hq"].find(type)]))
		else:
			if entities.any(func(u): return u.get("support",0) > 0): actions.add_child(button("Support",func(): mode = "support"))
			actions.add_child(button("Move",func(): mode = "move"))
			actions.add_child(button("Attack-move",func(): mode = "attack"))
		if entities.any(func(u): return u.kind == "unit" and u.type != "worker" and u.get("damage",0) > 0):
			actions.add_child(button("Patrol",func(): run_shortcut("patrol"),"P"))
		actions.add_child(button("Stop",func(): run_shortcut("stop")))
		actions.add_child(button("Queue: ON" if queue_orders else "Queue: OFF",func(): queue_orders = not queue_orders))

func refresh_queue(e: Dictionary):
	var visible_queue = not e.is_empty() and e.kind == "building"
	if queue_strip.visible != visible_queue:
		queue_strip.visible = visible_queue
		layout.call_deferred()
	if not visible_queue:
		queue_signature = ""
		return
	var jobs = []
	if not e.complete:
		var a = WorkActivity.building(sim,e)
		jobs.append({"kind":"site","ref":e,"type":e.type,"progress":e.progress,"blocked":a.label if a.get("waiting",false) else "","label":"Cancel site · 75% refund"})
	elif not e.level_job.is_empty():
		jobs.append({"kind":"level","ref":e.level_job,"type":e.type,"progress":e.level_job.elapsed/e.level_job.time,"blocked":"","label":"Cancel upgrade"})
	else:
		for i in range(e.queue.size()):
			var q = e.queue[i]
			jobs.append({"kind":"train","ref":q,"type":q.type,"progress":q.elapsed/Catalog.get_def(q.type).time,"blocked":q.blocked,"label":"Cancel %s #%d · refund" % [Catalog.get_def(q.type).name,i+1]})
	var signature = str(e.id)+str(e.complete)+str(e.level_job.is_empty())+str(e.queue.map(func(q): return [q.id,q.type]))
	if queue_signature != signature:
		queue_signature = signature
		clear_children(queue_strip)
		for job in jobs:
			var expected_sim = sim
			var ref = job.ref
			var kind = job.kind
			var item = WorkButton.new()
			item.pressed.connect(func():
				if paused or not started or sim.result != "" or sim != expected_sim or not is_same(sim.entity(e.id),e): return
				if kind == "site":
					if not e.complete: sim.cancel_building(e.id)
				elif kind == "level":
					if is_same(e.level_job,ref): sim.cancel_level(e.id)
				else: sim.cancel_job(e.id,ref.id)
				ui_action_serial += 1
				refresh_ui()
			)
			item.custom_minimum_size = Vector2(44,44)
			item.add_theme_font_size_override("font_size",11)
			for state in ["normal","hover","pressed","disabled","focus"]:
				var style = item.get_theme_stylebox(state).duplicate()
				style.content_margin_left = 3; style.content_margin_right = 3
				style.content_margin_top = 3; style.content_margin_bottom = 3
				item.add_theme_stylebox_override(state,style)
			item.set_meta("command_label",job.label)
			item.set_meta("work_kind",kind)
			var names = {"worker":"H","vanguard":"V","ranger":"R","medic":"M+","antitank":"AT","breaker":"B","engineer":"E","tank":"T","upgrade":"W"}
			item.glyph = "↑" if kind == "level" else ("⌂" if kind == "site" else names.get(job.type,"?"))
			queue_strip.add_child(item)
	for i in range(jobs.size()):
		var job = jobs[i]
		var item = queue_strip.get_child(i)
		item.progress = job.progress; item.waiting = job.blocked != ""
		item.tooltip_text = "%s · %d%% %s" % [job.label,clampi(int(job.progress*100),0,100),job.blocked]
		item.disabled = paused or not started or sim.result != ""
		item.queue_redraw()

func refresh_work_actions(e: Dictionary):
	if e.is_empty() or e.kind != "building": return
	for item in actions.get_children():
		var kind = item.get_meta("work_action","")
		if kind == "": continue
		# Match normal padding while disabled so busy buttons cannot shrink/reflow.
		if not item.has_theme_stylebox_override("disabled"):
			var disabled_style = item.get_theme_stylebox("normal").duplicate()
			disabled_style.bg_color = Color("17282e")
			item.add_theme_stylebox_override("disabled",disabled_style)
		item.disabled = paused or not started or sim.result != "" or not e.complete or not e.level_job.is_empty() or (kind == "upgrade" and (e.level >= 3 or not e.queue.is_empty()))

func compact_stat(value: float) -> String:
	return ("%.1fk" % (value/1000) if value < 100000 else "%dk" % roundi(value/1000)) if value >= 10000 else str(ceili(value))

func _process(dt):
	if not sim: return
	if not paused and started and sim.result == "":
		if not (test_enabled and test_manual_clock):
			accumulator += minf(dt,0.2)
			while accumulator >= 0.05:
				sim.tick(0.05)
				accumulator -= 0.05
		var pan = Vector2(float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))-float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))-float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
		if not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_ALT) and not Input.is_key_pressed(KEY_META): view.focus += pan*view.zoom*0.65*dt
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
		if test_enabled: publish_state.call_deferred()
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
		"stage":
			scenario.selected = int(command.get("index",0))
		"start":
			start_match()
			sim.ai_enabled = false
			test_manual_clock = command.get("manual_clock",false) == true
			accumulator = 0
		"step":
			for i in range(mini(12000,int(command.get("seconds",1)*20))): sim.tick(0.05)
		"select": selected = command.ids
		"order":
			var o = command.order
			if o.has("p"): o.p = Vector2(o.p[0],o.p[1])
			sim.issue(selected,o)
		"build": sim.build(int(command.worker),command.type,Vector2(command.x,command.z))
		"train": sim.enqueue(int(command.id),command.type)
		"harvest_deplete":
			for r in sim.deposits:
				if r.id == int(command.get("id",0)): r.amount = 0
		"progression_setup": sim.players[0].alloy = 5000; sim.players[0].energy = 5000
		"heavy_setup":
			sim.spawn("foundry",0,Vector2(-9,34))
			sim.spawn("relay",0,Vector2(-4,34))
			sim.nav.rebuild(sim.entities)
		"activity_setup":
			for e in sim.own(0): e.orders.clear(); e.queue.clear()
			var workers = sim.own(0).filter(func(e): return e.type == "worker")
			var r = sim.deposits[0]; r.amount = 2000
			workers[0].p = r.p+Vector2(r.radius+1,0)
			workers[0].carry = 0
			sim.issue([workers[0].id],{"type":"gather","target":r.id})
			var h = sim.own(0).filter(func(e): return e.type == "hq")[0]
			sim.players[0].alloy = 1000
			sim.enqueue(h.id,"worker"); sim.enqueue(h.id,"worker")
			var site = sim.spawn("relay",0,Vector2(-20,8),false)
			workers[1].p = site.p+Vector2(site.radius+1,0)
			sim.issue([workers[1].id],{"type":"build","target":site.id})
			sim.nav.rebuild(sim.entities); sim.update_vision(); sim.tick(0.05)
			selected = [workers[0].id]; mode = ""
			view.focus = r.p+Vector2(4,5); view.zoom = 34
		"activity_damage": sim.apply_damage(sim.entity(int(command.id)),float(command.get("damage",1)),1)
		"patrol_setup":
			sim.entities = sim.entities.filter(func(e): return e.kind == "building")
			sim.spawn("worker",0,Vector2(0,20))
			sim.spawn("ranger",0,Vector2(-4,20))
			sim.spawn("tank",0,Vector2(4,20))
			sim.spawn("medic",0,Vector2(6,26))
			var enemy = sim.spawn("worker",1,Vector2(2,20))
			enemy.hp = 10000; enemy.max_hp = 10000
			sim.nav.rebuild(sim.entities); sim.update_vision()
			view.focus = Vector2(0,24); view.zoom = 42
			selected.clear(); mode = ""
		"support_setup":
			var healer = sim.own(0).filter(func(e): return e.type == "medic")[0]
			var ally = sim.own(0).filter(func(e): return e.type == "ranger")[0]
			healer.p = Vector2(-15,14); healer.orders.clear()
			ally.p = Vector2(-12,14); ally.hp = 20
			selected = [healer.id]
			view.focus = Vector2(-16,18); view.zoom = 32
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
	publish_state.call_deferred()

func publish_state():
	var list = []
	for e in sim.entities+sim.deposits:
		var point = view.camera.unproject_position(Vector3(e.p.x,1.2,e.p.y))
		list.append({"id":e.id,"type":e.type,"team":e.get("team",-1),"x":e.p.x,"z":e.p.y,"screen":[point.x,point.y],"hp":e.get("hp",0),"shield":e.get("shield",0),"level":e.get("level",1),"upgrading":not e.get("level_job",{}).is_empty(),"amount":e.get("amount",0),"carry":e.get("carry",0),"resource":e.get("resource",0),"complete":e.get("complete",true),"orders":e.get("orders",[]).map(func(o): return o.type),"rally":[e.rally.x,e.rally.y] if e.get("rally") is Vector2 else null,"queue":e.get("queue",[]).map(func(q): return q.type)})
	var buttons = []
	collect_buttons(ui,buttons)
	var state = {"ready":true,"started":started,"paused":paused,"result":sim.result,"time":sim.time,"selected":selected,"population":sim.population(0),"alloy":sim.players[0].alloy,"energy":sim.players[0].energy,"entities":list,"buttons":buttons,"settings":settings,"settings_open":is_instance_valid(settings_panel),"models":view.objects.size(),"focus":[view.focus.x,view.focus.y],"zoom":view.zoom,"mode":mode,"viewport":[ui.size.x,ui.size.y]}
	state.building_type = building_type
	state.last_key = last_key
	state.groups = groups
	state.notice = notice.text
	state.selection_info = " · ".join(stat_labels.filter(func(l): return l.visible).map(func(l): return l.text.replace("\n"," ")))+" · "+info_label.text if stat_row.visible else info_label.text
	state.selection_status = info_label.text
	state.stat_cells = stat_labels.filter(func(l): return l.is_visible_in_tree()).map(func(l): return {"text":l.text,"x":l.global_position.x,"y":l.global_position.y,"w":l.size.x,"h":l.size.y,"lines":l.get_line_count(),"text_width":l.get_theme_font("font").get_string_size(l.text.get_slice("\n",1),HORIZONTAL_ALIGNMENT_LEFT,-1,l.get_theme_font_size("font_size")).x})
	state.selection_info_rect = [info_label.global_position.x,info_label.global_position.y,info_label.size.x,info_label.size.y]
	state.selection_info_lines = info_label.get_line_count()
	state.guide_open = is_instance_valid(guide_panel)
	state.tech_level = sim.tech_level(0)
	state.mobile_layout = mobile_layout
	state.action_page = action_page
	state.action_pages = action_pages
	state.action_buttons = []
	collect_buttons(actions,state.action_buttons)
	state.queue_buttons = []
	collect_buttons(queue_strip,state.queue_buttons)
	state.action_rect = [action_scroll.global_position.x,action_scroll.global_position.y,action_scroll.size.x,action_scroll.size.y]
	state.ui_action_serial = ui_action_serial
	state.minimap_rect = [minimap_rect.position.x,minimap_rect.position.y,minimap_rect.size.x,minimap_rect.size.y]
	state.map_id = sim.map_id
	state.map_size = sim.nav.half*2
	state.building_probes = sim.own(0).filter(func(e): return e.kind == "building").map(func(e):
		var point = view.camera.unproject_position(Vector3(e.p.x+minf(2,e.radius*0.7),2.6,e.p.y))
		return {"id":e.id,"screen":[point.x,point.y]}
	)
	state.draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	state.activity = overlay.activity_snapshot
	state.activity_effects = view.activity_effects.size()
	state.render_objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	state.nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	JavaScriptBridge.eval("window.frontierState="+JSON.stringify(state))

func collect_buttons(node: Node,list: Array):
	if node is Button and node.is_visible_in_tree():
		var rect = node.get_global_rect()
		list.append({"text":node.get_meta("command_label",node.text),"display_text":node.text,"x":rect.position.x,"y":rect.position.y,"w":rect.size.x,"h":rect.size.y,"disabled":node.disabled})
		if node is WorkButton:
			list[-1].work_progress = node.progress
			list[-1].work_glyph = node.glyph
			list[-1].red_rect = [rect.position.x+1,rect.position.y+35,rect.size.x-2,8]
	for child in node.get_children(): collect_buttons(child,list)

func shortcut_actions() -> Array:
	var es = selected.map(func(id): return sim.entity(id)).filter(func(e): return not e.is_empty())
	if es.size() == 1 and es[0].kind == "building" and es[0].complete: return es[0].get("trains",[])
	if es.any(func(e): return e.type == "worker"): return ["relay","barracks","foundry","tower","hq"]
	return []

func focus_selection():
	var es = selected.map(func(id): return sim.entity(id)).filter(func(e): return not e.is_empty())
	if es.is_empty(): return
	var center = Vector2.ZERO
	for e in es: center += e.p
	view.focus = center/es.size()

func choose_shortcut(items: Array,cycle: bool = false):
	if items.is_empty(): sim.message = "No matching units or buildings."; return
	mode = ""; placement_ready = false; view.ghost.visible = false
	if cycle:
		var current = selected[0] if not selected.is_empty() else -1
		var ids = items.map(func(e): return e.id)
		selected = [ids[(ids.find(current)+1)%ids.size()]]
		focus_selection()
	else: selected = items.map(func(e): return e.id)

func use_group(digit: int,assign: bool = false,add: bool = false):
	if assign: groups[digit] = selected.duplicate()
	elif add:
		var merged = groups.get(digit,[]).duplicate()
		for id in selected:
			if not merged.has(id): merged.append(id)
		groups[digit] = merged
	else:
		mode = ""; placement_ready = false
		selected = groups.get(digit,[]).filter(func(id): return not sim.entity(id).is_empty())
		if last_group == digit and Time.get_ticks_msec()-last_group_time < 400: focus_selection()
		last_group = digit; last_group_time = Time.get_ticks_msec()
	if assign or add: sim.message = "Control group %d %s." % [digit-KEY_0,"extended" if add else "assigned"]

func run_shortcut(id: String):
	if id == "pause": toggle_pause(); return
	if not started or paused or sim.result != "": return
	var own = sim.own(0)
	var es = selected.map(func(i): return sim.entity(i)).filter(func(e): return not e.is_empty())
	var e = es[0] if not es.is_empty() else {}
	match id:
		"build":
			if not es.any(func(u): return u.type == "worker"):
				var ws = own.filter(func(u): return u.type == "worker")
				if ws.is_empty(): sim.message = "Select a Harvester to construct a building."; refresh_ui(); return
				ws.sort_custom(func(a,b): return a.orders.size() < b.orders.size())
				choose_shortcut(ws.slice(0,1))
			mode = ""; placement_ready = false; action_page = 0
			sim.message = "BUILD: Q Relay / E Barracks / R Foundry / T Tower / Y Core"
		"move","attackmove","context","support","rally":
			if not es.any(func(u): return (u.kind == "building" and u.complete and not u.get("trains",[]).is_empty()) if id == "rally" else u.kind == "unit"):
				sim.message = "Select a completed production building first." if id == "rally" else "Select units first."
			else: mode = "attack" if id == "attackmove" else id
		"patrol","attack":
			if es.any(func(u): return u.kind == "unit" and u.get("damage",0) > 0 and (id != "patrol" or u.type != "worker")):
				mode = "patrol" if id == "patrol" else "target_attack"
				placement_ready = false
			else: sim.message = "Select soldiers or tanks to patrol." if id == "patrol" else "Select a Harvester or combat unit to attack."
		"stop": mode = ""; sim.issue(selected,{"type":"stop"}); sim.message = "Orders cleared."
		"deliver":
			var ws = es.filter(func(u): return u.type == "worker" and u.carry > 0)
			if ws.is_empty(): sim.message = "Select Harvesters carrying resources."
			else: mode = ""; placement_ready = false; sim.issue(ws.map(func(u): return u.id),{"type":"deliver"},queue_orders)
		"upgrade":
			if e.get("kind","") == "building": sim.upgrade_building(e.id)
			else: sim.message = "Select a building to upgrade."
		"cancel":
			if mode != "": mode = ""; placement_ready = false
			elif e.get("kind","") == "building":
				if not e.complete: sim.cancel_building(e.id)
				elif not e.level_job.is_empty(): sim.cancel_level(e.id)
				elif not e.queue.is_empty(): sim.cancel_queue(e.id,e.queue.size()-1)
				else: sim.message = "No queued job to cancel."
		"idle": choose_shortcut(own.filter(func(u): return u.type == "worker" and u.orders.is_empty()),true)
		"army": choose_shortcut(own.filter(func(u): return u.kind == "unit" and u.type != "worker"))
		"workers": choose_shortcut(own.filter(func(u): return u.type == "worker"))
		"buildings": choose_shortcut(own.filter(func(u): return u.kind == "building"))
		"hq","barracks","foundry": choose_shortcut(own.filter(func(u): return u.type == id),true)
		"same":
			if not e.is_empty(): choose_shortcut(own.filter(func(u): return u.type == e.type))
		"all": choose_shortcut(own.filter(func(u): return u.kind == "unit"))
		"clear": selected.clear(); mode = ""; placement_ready = false
		"focus": focus_selection()
		"queue": queue_orders = not queue_orders
		"info": show_guide(e.get("type","hq"))
		"zoom-in": view.zoom = maxf(20,view.zoom-4)
		"zoom-out": view.zoom = minf(80,view.zoom+4)
	refresh_ui()

func handle_hotkey(event: InputEventKey) -> bool:
	if not event.pressed or event.alt_pressed or event.meta_pressed: return false
	var code = event.physical_keycode if event.physical_keycode else event.keycode
	if is_instance_valid(guide_panel) or is_instance_valid(settings_panel): return false
	var focus = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or focus is OptionButton: return false
	if code == KEY_SPACE and not event.ctrl_pressed:
		if not event.echo: toggle_pause()
		return true
	if paused or not started or sim.result != "": return false
	if code >= KEY_1 and code <= KEY_9:
		if not event.echo: use_group(code,event.ctrl_pressed,event.shift_pressed)
		return true
	if event.ctrl_pressed:
		if code != KEY_A: return false
		if not event.echo: run_shortcut("all")
		return true
	var action_index = hotkey_config.actionKeys.find(OS.get_keycode_string(code).to_upper())
	var available = shortcut_actions()
	if mode == "" and action_index >= 0 and action_index < available.size():
		if not event.echo:
			var type = available[action_index]
			if Catalog.get_def(type).get("kind","") == "building": begin_build(type)
			else: sim.enqueue(selected[0],type)
		return true
	if code == KEY_SLASH:
		if not event.echo: show_shortcuts()
		return true
	var key = OS.get_keycode_string(code).to_lower()
	if code == KEY_PERIOD: key = "f1"
	if code == KEY_QUOTELEFT: key = "`"
	if code == KEY_EQUAL or code == KEY_KP_ADD: key = "+"
	if code == KEY_MINUS or code == KEY_KP_SUBTRACT: key = "−"
	if code == KEY_Q: # Preserve the old attack-move alias for combat selections.
		if not event.echo and mode == "": run_shortcut("attackmove")
		return true
	for item in hotkey_config.commands:
		if item.key.split(" / ")[0].to_lower() == key:
			if not event.echo: run_shortcut(item.id)
			return true
	return false

func show_shortcuts():
	if is_instance_valid(guide_panel): return
	guide_was_paused = paused; paused = true
	guide_panel = Panel.new(); ui.add_child(guide_panel)
	var scroll = ScrollContainer.new(); scroll.position = Vector2(16,16); guide_panel.add_child(scroll)
	var body = VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(body)
	body.add_child(label("PC COMMANDS & SELECTION",20))
	var instructions = label("Q E R T Y: displayed action tiles\nB: construction / WASD: camera / Esc: cancel\nCtrl+1-9: save / Shift+1-9: add / 1-9: recall\nPress a group number twice to focus. Hold Shift to queue orders.",13)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.add_child(instructions)
	for item in hotkey_config.commands:
		body.add_child(button(item.label+" ["+item.key+"]",func(): close_guide(); run_shortcut(item.id)))
	for digit in range(KEY_1,KEY_9+1):
		body.add_child(button("Control group %d" % (digit-KEY_0),func():
			close_guide()
			if started and not paused and sim.result == "": use_group(digit,Input.is_key_pressed(KEY_CTRL),Input.is_key_pressed(KEY_SHIFT))
		))
	guide_panel.add_child(button("Close shortcuts",close_guide))
	layout()

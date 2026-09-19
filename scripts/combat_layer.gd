extends Control
const Feedback = preload("res://scripts/combat_feedback.gd")
var painter = Feedback.new()
var game
var snapshot = {"burning":[],"combat":[],"shots":0}

func _process(_dt): queue_redraw()

func feedback_visible(bounds: Rect2) -> bool:
	return get_parent().feedback_visible(bounds)

func _draw():
	if not game or not game.view: return
	var view = game.view; var sim = game.sim
	painter.canvas = self; painter.game = game
	painter.motion = view.combat_motion; painter.eco = game.settings.eco
	snapshot = {"burning":[],"combat":[],"shots":0}
	for e in view.shot_effects:
		if view.shot_visible(e): painter.shot(e); snapshot.shots += 1
	for e in view.activity_effects:
		if sim.seen(e.p) and painter.effect(e): snapshot.combat.append({"type":e.type,"life":e.life,"shield":e.get("shield",false),"heavy":e.get("heavy",false)})
	for e in sim.entities:
		if snapshot.burning.size() >= (8 if game.settings.eco else 16): break
		if Feedback.burning(e) and (e.team == 0 or sim.seen(e.p)) and painter.burn(e,sim.time): snapshot.burning.append(e.id)

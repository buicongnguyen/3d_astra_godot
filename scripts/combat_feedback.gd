extends RefCounted

# All effects share the existing overlay; no particle nodes, lights or physics.
var canvas: Control
var game
var motion = true
var eco = false

static func burning(e: Dictionary) -> bool:
	return e.get("complete",false) and e.hp > 0 and e.max_hp > 0 and e.hp < e.max_hp*0.35 and (e.kind == "building" or e.get("mechanical",false))

static func duration(e: Dictionary) -> float:
	return 0.28 if e.type == "impact" else (2.2 if e.get("building",false) or e.get("heavy",false) else 0.75)

func project(p: Vector2,height: float) -> Vector2:
	return game.view.camera.unproject_position(Vector3(p.x,height,p.y))

func scale_at(p: Vector2,height: float) -> float:
	return clampf(project(p,height).distance_to(project(p+Vector2.RIGHT,height))/14.0,0.55,1.5)

func circle(p: Vector2,radius: float,color: String,alpha: float):
	if not canvas.feedback_visible(Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2)): return
	var tint = Color(color); tint.a = alpha
	canvas.draw_circle(p,maxf(0.1,radius),tint)

func polygon(points: Array,color: String,alpha: float):
	var bounds = Rect2(points[0],Vector2.ZERO)
	for p in points: bounds = bounds.expand(p)
	if not canvas.feedback_visible(bounds): return
	var tint = Color(color); tint.a = alpha
	canvas.draw_colored_polygon(PackedVector2Array(points),tint)

func flame(p: Vector2,r: float,phase: float,alpha: float):
	var h = r*(1.8+(0.18*sin(phase) if motion else 0.0))
	polygon([p+Vector2(-r*0.5,0),p+Vector2(-r*0.65,-r*0.7),p+Vector2(-r*0.15,-h*0.7),p+Vector2(r*0.1,-h),p+Vector2(r*0.55,-r*0.65),p+Vector2(r*0.4,0)],"f16d32",alpha)
	polygon([p+Vector2(-r*0.26,0),p+Vector2(-r*0.23,-r*0.5),p+Vector2(r*0.03,-h*0.62),p+Vector2(r*0.28,-r*0.4),p+Vector2(r*0.2,0)],"ffda76",alpha*0.95)

func smoke(p: Vector2,r: float,phase: float,alpha: float):
	var count = 2 if eco else 3
	for i in range(count):
		var t = fmod(phase+float(i)/count,1.0) if motion else (i+0.4)/count
		circle(p+Vector2(r*t*0.8,-r*(0.8+t*3.2)),r*(0.45+t*0.65),"66665f",alpha*sin(PI*t)*0.36)

func burn(e: Dictionary,time: float) -> bool:
	var height = 3.8 if e.kind == "building" else 1.3
	var p = project(e.p,height)
	var r = (12 if e.kind == "building" else 8)*scale_at(e.p,height)
	if not canvas.feedback_visible(Rect2(p-Vector2.ONE*3,Vector2.ONE*6)): return false
	smoke(p,r,fmod(time*0.55+e.id*0.137,1.0),1)
	flame(p,r,time*5+e.id,0.9)
	if e.hp < e.max_hp*0.2 and not eco: flame(p+Vector2(r*0.75,3),r*0.6,time*4+e.id,0.8)
	return true

func effect(e: Dictionary) -> bool:
	var impact = e.type == "impact"
	var height = (3.8 if e.get("building",false) else 1.3) if impact else 0.4
	var p = project(e.p,height)
	var age = e.max_life-e.life
	var fade = e.life/e.max_life
	var size = scale_at(e.p,height)
	var r = ((14 if e.get("building",false) else 8) if impact else (26 if e.get("building",false) else (19 if e.get("heavy",false) else 10)))*size
	if not canvas.feedback_visible(Rect2(p-Vector2.ONE*3,Vector2.ONE*6)): return false
	if impact:
		var color = Color("a2eaff" if e.get("shield",false) else "ffd28a"); color.a = fade
		if e.get("shield",false):
			var radius = r*(1+age*2 if motion else 1)
			if canvas.feedback_visible(Rect2(p-Vector2.ONE*(radius+2),Vector2.ONE*(radius+2)*2)): canvas.draw_arc(p,radius,0,TAU,24,color,2,true)
		else:
			circle(p,3*size,"ffe4ab",fade)
			for i in range(3 if eco else 5):
				var direction = Vector2.from_angle(i*2.4+e.get("seed",0))
				var distance = r*(0.4+age*3 if motion else 0.8)
				var a = p+direction*distance*0.4
				var b = p+direction*distance
				if canvas.feedback_visible(Rect2(a,Vector2.ZERO).expand(b).grow(2)): canvas.draw_line(a,b,color,2)
	else:
		# Temporary scorch marks and fragments are cosmetic, never path obstacles.
		var mark: Array = []
		for i in range(16): mark.append(p+Vector2(cos(i*TAU/16)*r*0.9,r*0.3+sin(i*TAU/16)*r*0.28))
		polygon(mark,"252b27",fade*0.5)
		for i in range(3 if eco else 5):
			var a = i*2.4+e.get("seed",0)
			var travel = minf(1,age*3) if motion else 0.65
			var q = p+Vector2(cos(a)*r*travel,sin(a)*r*0.4*travel-(sin(travel*PI)*r*0.4 if motion else 0.0))
			polygon([q+Vector2(-3*size,0),q+Vector2(0,-2*size),q+Vector2(4*size,2*size)],"7e8172",fade)
		var burst = maxf(0,1-age/0.45)
		if burst > 0: circle(p-Vector2(0,r*0.2),r*(0.5+age*2 if motion else 0.65),"ffce76",burst*0.8)
		if e.get("building",false) or e.get("heavy",false):
			smoke(p,r*0.75,age*0.45,minf(1,fade*2))
			if age < 1.1: flame(p,r*0.65,age*5,minf(1,fade)*maxf(0,1-age/1.1))
	return true

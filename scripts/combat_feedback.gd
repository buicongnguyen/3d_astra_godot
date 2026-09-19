extends RefCounted

# All effects share the existing overlay; no particle nodes, lights or physics.
var canvas: Control
var game
var motion = true
var eco = false
var soft_texture: ImageTexture

func _init():
	var image = Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var alpha = pow(maxf(0,1-Vector2(x-31.5,y-31.5).length()/32.0),1.6)
			image.set_pixel(x,y,Color(1,1,1,alpha))
	soft_texture = ImageTexture.create_from_image(image)

func soft(p: Vector2,r: float,color: String,alpha: float):
	var rect = Rect2(p-Vector2.ONE*r,Vector2.ONE*r*2)
	if not canvas.feedback_visible(rect): return
	var tint = Color(color); tint.a = clampf(alpha,0,1)
	canvas.draw_texture_rect(soft_texture,rect,false,tint)

func shot(e: Dictionary):
	var style = game.view.weapon_style(e)
	var age = e.max_life-e.life; var t = age/e.max_life
	var reach = minf(style.reach,e.p.distance_to(e.to)*0.45)
	var origin = e.p+e.p.direction_to(e.to)*reach
	var a = project(origin,style.height); var b = project(e.to,0.9)
	var size = scale_at(origin,style.height)
	var support = style.kind == "support"; var rocket = style.kind == "rocket"; var heavy = style.kind == "cannon"
	var front = 1.0 if support else (minf(1,0.25+t*2) if motion else 0.65)
	var start = a.lerp(b,0.0 if support else maxf(0,front-(0.28 if rocket else 0.17)))
	var end = a.lerp(b,front)
	var repair = support and e.get("weapon","") == "engineer"
	var color = Color("e1eaff" if repair else ("88e2cf" if support else "ffd5a0")); color.a = (1-t)*0.85
	if canvas.feedback_visible(Rect2(start,Vector2.ZERO).expand(end).grow(3)):
		if support: canvas.draw_dashed_line(start,end,color,1.3*size,4)
		else: canvas.draw_line(start,end,color,(2.5 if heavy else (2.0 if rocket else 1.3))*size,true)
	if repair and canvas.feedback_visible(Rect2(b-Vector2.ONE*6*size,Vector2.ONE*12*size)):
		for i in range(3): canvas.draw_line(b,b+Vector2.from_angle(i*2.1+(t*3 if motion else 0))*5*size,color,1.3*size,true)
	if not support and age < 0.1:
		soft(a,(12 if heavy else (7 if rocket else 4))*size,"ff9e48",(1-age/0.1)*0.85)
		soft(a,(5 if heavy else 2)*size,"fff0b0",1-age/0.1)
	if heavy and age > 0.05: soft(a-Vector2(0,age*13 if motion else 2),8*size,"66665f",(1-t)*0.27)
	if rocket and not eco:
		for i in range(1,4): soft(a.lerp(b,maxf(0,front-i*0.07)),(2+i)*size,"66665f",(1-t)*0.22)
		circle(end,2*size,"fff0b0",1-t)

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
		soft(p+Vector2(r*t*0.8,-r*(0.8+t*2.5)),r*(0.7+t*0.8),"66665f",alpha*sin(PI*t)*0.44)

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
		if burst > 0 and (e.get("building",false) or e.get("heavy",false)):
			for i in range(2 if eco else 4):
				var angle = i*2.4+e.get("seed",0); var d = r*(age*0.7 if motion else 0.15)
				soft(p+Vector2(cos(angle)*d,-r*0.2+sin(angle)*d*0.5),r*(0.45+age if motion else 0.65),"ff9e48",burst*0.75)
			soft(p-Vector2(0,r*0.2),r*0.32,"fff0b0",maxf(0,1-age/0.12))
		if age < 0.7:
			var dust = Color(game.view.theme().dust); dust.a = (1-age/0.7)*0.4
			var ring = PackedVector2Array()
			for i in range(25): ring.append(p+Vector2(cos(i*TAU/24)*r*(0.4+age*1.5 if motion else 1),r*0.2+sin(i*TAU/24)*r*(0.12+age*0.4 if motion else 0.3)))
			var bounds = Rect2(ring[0],Vector2.ZERO)
			for point in ring: bounds = bounds.expand(point)
			if canvas.feedback_visible(bounds.grow(2)): canvas.draw_polyline(ring,dust,2*size,true)
		if e.get("building",false) or e.get("heavy",false):
			smoke(p,r*0.75,age*0.45,minf(1,fade*2))
			if age < 1.1: flame(p,r*0.65,age*5,minf(1,fade)*maxf(0,1-age/1.1))
	return true

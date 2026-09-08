extends RefCounted
const Catalog = preload("res://scripts/catalog.gd")
var half = 48.0
var grid_size = 48
var grids: Dictionary = {}
var obstacles: Array = []
var revision = 0
var river = true

func _init():
	Catalog.load_data()

func terrain_free(p: Vector2, r: float) -> bool:
	if not p.is_finite() or not is_finite(r) or r < 0 or absf(p.x) > half-r or absf(p.y) > half-r:
		return false
	if river:
		for span in [Vector2(-half,-27),Vector2(-17,-5),Vector2(5,17),Vector2(27,half)]:
			var closest = Vector2(clampf(p.x,span.x,span.y),clampf(p.y,-3,3))
			if p.distance_to(closest) < r + 0.01:
				return false
	return true

func can_stand(p: Vector2, r: float = 0.55) -> bool:
	if not terrain_free(p,r): return false
	for o in obstacles:
		if p.distance_to(o.p) < o.r + r + 0.08: return false
	return true

func traverse(a: Vector2,b: Vector2,r: float) -> bool:
	var count = maxi(1,ceili(a.distance_to(b)/0.4))
	for i in range(1,count+1):
		var p = a.lerp(b,float(i)/count)
		if not terrain_free(p,r): return false
		for o in obstacles:
			if p.distance_to(o.p) < o.r+r+0.08:
				# Allow an already displaced unit to escape, never cross inward.
				if a.distance_to(o.p) >= o.r+r+0.08 or (a-o.p).dot(b-a) <= 0: return false
	return true

func clear_line(a: Vector2,b: Vector2,source: int,target: int) -> bool:
	var delta = b-a
	for o in obstacles:
		if o.id == source or o.id == target: continue
		var along = clampf((o.p-a).dot(delta)/maxf(delta.length_squared(),0.001),0,1)
		if (a+delta*along).distance_to(o.p) < o.r: return false
	return true

func rebuild(entities: Array):
	obstacles.clear()
	for rock in Catalog.rocks:
		obstacles.append({"p":Vector2(rock[0],rock[1]),"r":float(rock[2]),"id":-1})
	for e in entities:
		if e.hp > 0 and e.kind == "building":
			obstacles.append({"p":e.p,"r":e.radius,"id":e.id})
	grids.clear()
	revision += 1

func grid_for(radius: float) -> AStarGrid2D:
	var key = ceili(radius*100)
	if grids.has(key): return grids[key]
	var grid = AStarGrid2D.new()
	grid.region = Rect2i(0,0,grid_size,grid_size)
	grid.cell_size = Vector2(2,2)
	grid.offset = Vector2(-half+1,-half+1)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for z in range(grid_size):
		for x in range(grid_size):
			# Grid vertices need clearance for the segments between cell centers.
			# Without this margin, a path can graze a circular building at its midpoint.
			grid.set_point_solid(Vector2i(x,z),not can_stand(Vector2(x*2-half+1,z*2-half+1),radius+0.6))
	grids[key] = grid
	return grid

func cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x+half)/2),0,grid_size-1),clampi(floori((p.y+half)/2),0,grid_size-1))

func nearest(grid: AStarGrid2D,p: Vector2) -> Vector2i:
	var center = cell(p)
	if not grid.is_point_solid(center): return center
	for r in range(1,7):
		var best = Vector2i(-1,-1)
		var distance = INF
		for y in range(maxi(0,center.y-r),mini(grid_size,center.y+r+1)):
			for x in range(maxi(0,center.x-r),mini(grid_size,center.x+r+1)):
				var c = Vector2i(x,y)
				if grid.is_point_solid(c): continue
				var d = grid.get_point_position(c).distance_squared_to(p)
				if d < distance:
					distance = d
					best = c
		if best.x >= 0: return best
	return Vector2i(-1,-1)

func path(a: Vector2,b: Vector2,r: float) -> Array:
	if not a.is_finite() or not b.is_finite(): return []
	if traverse(a,b,r): return [b]
	var grid = grid_for(r)
	var start = nearest(grid,a)
	var end = nearest(grid,b)
	if start.x < 0 or end.x < 0: return []
	var points = Array(grid.get_point_path(start,end))
	if points.is_empty() or not traverse(a,points[0],r): return []
	if traverse(points[-1],b,r): points.append(b)
	return points

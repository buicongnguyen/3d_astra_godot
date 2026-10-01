extends RefCounted
# Small living details per battlefield, ported from the Three.js edition (ambient-life.js):
# birds with ground shadows, butterflies, dragonflies, fish and drifting motes (ash, dust,
# pollen, fireflies, embers). Each family is one MultiMesh (motes: one point mesh) whose motion
# runs in the vertex shader; GDScript only advances one clock. Per-instance numbers ride in the
# instance transform (origin plus the nine basis slots) and custom data, so the shaders write
# the final position themselves. Creatures sample the fog of war, and every path stays inside
# the map. Motion levels: 2 full, 1 calm, 0 still (clock stopped, wings at rest).

const LIFE = {
	"classic": {"birds": {"look": "crow", "count": 6, "height": [9.0, 12.0], "speed": [2.6, 3.4], "soar": 0.25, "radius": [7.0, 13.0]}, "motes": {"look": "ash", "count": 90}},
	"riverlands": {"birds": {"look": "gull", "count": 7, "height": [9.0, 13.0], "speed": [3.0, 4.0], "soar": 0.45, "radius": [8.0, 14.0]}, "fish": 26, "butterflies": 14, "dragonflies": 8, "motes": {"look": "pollen", "count": 50}},
	"basin": {"birds": {"look": "hawk", "count": 4, "height": [12.0, 15.0], "speed": [2.2, 2.8], "soar": 0.9, "radius": [10.0, 16.0]}, "butterflies": 6, "motes": {"look": "dust", "count": 90}},
	"expanse": {"geese": {"flocks": 2, "size": 7}, "fish": 30, "butterflies": 16, "dragonflies": 8, "motes": {"look": "pollen", "count": 50}},
	"dunes": {"birds": {"look": "vulture", "count": 5, "height": [12.0, 15.0], "speed": [2.0, 2.6], "soar": 0.92, "radius": [9.0, 15.0]}, "motes": {"look": "sand", "count": 120}},
	"woodlands": {"birds": {"look": "songbird", "count": 8, "height": [7.0, 10.0], "speed": [3.4, 4.4], "soar": 0.1, "radius": [5.0, 9.0]}, "fish": 22, "butterflies": 28, "dragonflies": 10, "motes": {"look": "firefly", "count": 70}},
	"highlands": {"birds": {"look": "raven", "count": 6, "height": [10.0, 13.0], "speed": [2.6, 3.4], "soar": 0.5, "radius": [8.0, 14.0]}, "motes": {"look": "ember", "count": 110}},
}
const BIRDS = {"crow": ["2b2927", "1f1e1c", "121110"], "gull": ["f4f2ea", "dedcd2", "4b5054"], "hawk": ["94704a", "6f5232", "2e241a"],
	"vulture": ["3e352f", "2d2622", "8a7c6c"], "songbird": ["f2a53c", "9a6230", "3b2b1f"], "raven": ["272a34", "1b1d26", "0f1016"], "goose": ["8f8676", "6f675b", "2a2622"]}
const BIRD_SIZE = {"crow": 0.9, "gull": 1.0, "hawk": 1.15, "vulture": 1.35, "songbird": 0.62, "raven": 0.95, "goose": 1.1}
const MOTES = {"ash": {"colors": ["bdb8ad", "8f8a80"], "size": [0.1, 0.16], "additive": false, "kind": 0},
	"dust": {"colors": ["e2b583", "c98f5e"], "size": [0.09, 0.15], "additive": false, "kind": 1},
	"sand": {"colors": ["ecd3a0", "d8b77c"], "size": [0.08, 0.13], "additive": false, "kind": 1},
	"pollen": {"colors": ["fff7d8", "f4ffd0"], "size": [0.07, 0.11], "additive": false, "kind": 2},
	"firefly": {"colors": ["e6ff86", "b9ff6a"], "size": [0.12, 0.18], "additive": true, "kind": 3},
	"ember": {"colors": ["ff9a3c", "ff5426"], "size": [0.09, 0.15], "additive": true, "kind": 4}}
const BUTTERFLY_COLORS = ["ff9a2e", "ffd43b", "f7f3e3", "6ec6ff", "ff6fb5", "ff7a3d"]
const DRAGONFLY_COLORS = ["2fd1c6", "3b8cff", "7be04f"]

var root: Node3D
var materials: Array = []
var families: Array = []
var clock = 0.0
var level = 2
var quiet = false
var plan_data: Dictionary
# Each family's live creatures sit first in its MultiMesh; `alive` of them are drawn (times
# `share`), so creatures killed by combat or thinned by the governor cost nothing.
var groups: Array = []
var share = 1.0
var half_size = 48.0
var mote_look = ""

# Pure, seeded placement: the same map always gets the same cast; tests check the bounds.
static func plan(map_id: String, half: float, river: bool, rocks: Array, budget: float) -> Dictionary:
	var recipe: Dictionary = LIFE.get(map_id, {})
	var rng = RandomNumberGenerator.new(); rng.seed = hash(map_id)
	var area = pow(half/48.0, 2)*budget
	var out = {"birds": [], "fish": [], "butterflies": [], "dragonflies": [], "motes": [], "look": "", "mote_look": ""}
	var land = func(x: float, z: float) -> bool:
		if river and absf(z) < 6: return false
		for r in rocks:
			if Vector2(x, z).distance_to(Vector2(r[0], r[1])) < r[2]+1: return false
		return true
	if recipe.has("birds"):
		var b = recipe.birds; out.look = b.look
		for i in range(maxi(0, roundi(b.count*area))):
			var radius = rng.randf_range(b.radius[0], b.radius[1]); var reach = half-radius-3
			out.birds.append({"x": rng.randf_range(-reach, reach), "y": rng.randf_range(b.height[0], b.height[1]), "z": rng.randf_range(-reach, reach),
				"size": rng.randf_range(0.9, 1.2)*BIRD_SIZE[b.look], "radius": radius, "speed": rng.randf_range(b.speed[0], b.speed[1])*(-1.0 if rng.randf() < 0.5 else 1.0),
				"phase": rng.randf()*TAU, "mode": 0.0, "flap": 9.0+rng.randf()*3.0, "soar": b.soar, "back": 0.0, "side": 0.0})
	if recipe.has("geese"):
		out.look = "goose"
		for f in range(maxi(1, roundi(recipe.geese.flocks*minf(1.0, budget+0.2)))):
			var dir = rng.randf()*TAU; var phase = rng.randf(); var x = rng.randf_range(-0.3, 0.3)*half; var z = rng.randf_range(-0.3, 0.3)*half; var y = 11.0+rng.randf()*2.0
			for k in range(recipe.geese.size):
				var rank = ceili(k/2.0); var side = 0 if k == 0 else (1 if k%2 else -1)
				out.birds.append({"x": x, "y": y+rank*0.08, "z": z, "size": BIRD_SIZE.goose, "radius": dir, "speed": 4.2, "phase": phase, "mode": 1.0,
					"flap": 7.5+(k%3)*0.4, "soar": 0.15, "back": rank*1.5, "side": side*rank*1.25})
	if recipe.has("fish") and river:
		for i in range(maxi(0, roundi(recipe.fish*area))):
			out.fish.append({"x": rng.randf_range(-(half-4), half-4), "z": rng.randf_range(-2.1, 2.1), "size": 0.85+rng.randf()*0.45,
				"dir": -1.0 if rng.randf() < 0.5 else 1.0, "speed": 0.9+rng.randf()*1.3, "phase": rng.randf()*TAU, "koi": 1.0 if rng.randf() < 0.22 else 0.0})
	if recipe.has("butterflies"):
		for i in range(maxi(0, roundi(recipe.butterflies*area))):
			for attempt in range(12):
				var x = rng.randf_range(-(half-6), half-6); var z = rng.randf_range(-(half-6), half-6)
				if not land.call(x, z): continue
				out.butterflies.append({"x": x, "y": 0.75, "z": z, "size": 0.95+rng.randf()*0.35, "rx": 1.5+rng.randf()*2.5, "rz": 1.5+rng.randf()*2.5,
					"speed": 0.7+rng.randf()*0.6, "phase": rng.randf()*TAU, "color": BUTTERFLY_COLORS[rng.randi()%BUTTERFLY_COLORS.size()]})
				break
	if recipe.has("dragonflies") and river:
		for i in range(maxi(0, roundi(recipe.dragonflies*area))):
			var side = -1.0 if rng.randf() < 0.5 else 1.0
			out.dragonflies.append({"x": rng.randf_range(-(half-8), half-8), "y": 0.95, "z": side*(3.6+rng.randf()*2.4), "size": 1.0, "rx": 1.6, "rz": 0.7,
				"speed": 0.4+rng.randf()*0.25, "phase": rng.randf()*50.0, "color": DRAGONFLY_COLORS[rng.randi()%DRAGONFLY_COLORS.size()]})
	if recipe.has("motes"):
		var look = MOTES[recipe.motes.look]; out.mote_look = recipe.motes.look
		for i in range(maxi(0, roundi(recipe.motes.count*area))):
			out.motes.append({"x": rng.randf_range(-(half-8), half-8), "y": rng.randf(), "z": rng.randf_range(-(half-8), half-8),
				"size": rng.randf_range(look.size[0], look.size[1]), "rate": 0.05+rng.randf()*0.08, "phase": rng.randf(), "tone": rng.randf()})
	return out

const COMMON = """
uniform float clock = 0.0;
uniform float amp = 1.0;
uniform float half_size = 48.0;
uniform sampler2D visible_map : filter_linear;
uniform sampler2D explored_map : filter_linear;
// Fog of war as the ground draws it: 0 visible, 0.6 explored, 0.94 unexplored.
float fog_at(vec3 p) {
	vec2 uv = vec2((p.x + half_size) / (2.0 * half_size), (p.z + half_size) / (2.0 * half_size));
	float v = clamp(textureLod(visible_map, uv, 0.0).r * 255.0, 0.0, 1.0);
	float e = clamp(textureLod(explored_map, uv, 0.0).r * 255.0, 0.0, 1.0);
	return mix(0.94, 0.6, e) * (1.0 - v);
}
float inside(vec3 p, float margin) { return 1.0 - smoothstep(half_size - margin - 3.0, half_size - margin, max(abs(p.x), abs(p.z))); }
vec3 place(vec3 local, vec2 fwd, vec3 origin) {
	vec2 right = vec2(fwd.y, -fwd.x);
	return origin + vec3(right.x * local.x + fwd.x * local.z, local.y, right.y * local.x + fwd.y * local.z);
}
float hash1(float n) { return fract(sin(n) * 43758.5453); }
"""
# Birds: MODEL_MATRIX[3] = centre and height; [0] = size, radius (circle) or heading (line), speed;
# [1] = phase, mode, flap rate; [2] = soar, formation back, formation side.
const BIRD_PATH = """
void bird_path(mat4 m, float t, out vec3 p, out vec2 fwd, out float bank) {
	float radius = m[0].y, speed = m[0].z, phase = m[1].x;
	if (m[1].y < 0.5) {
		float a = phase + t * speed / max(radius, 1.0);
		p = vec3(m[3].x + cos(a) * radius, m[3].y, m[3].z + sin(a) * radius);
		fwd = normalize(vec2(-sin(a), cos(a)) * sign(speed));
		bank = -0.32 * sign(speed);
	} else {
		fwd = vec2(cos(radius), sin(radius));
		float span = half_size * 2.0 + 40.0;
		float s = mod(t * speed + phase * span, span) - span * 0.5;
		vec2 right = vec2(fwd.y, -fwd.x);
		vec2 xz = m[3].xz + fwd * (s - m[2].y) + right * m[2].z;
		p = vec3(xz.x, m[3].y, xz.y);
		bank = 0.0;
	}
	p.y += sin(t * 0.5 + phase) * 0.45 * amp;
}
float bird_flap(mat4 m, float t) {
	float glide = smoothstep(0.5, 0.92, sin(t * 0.33 + m[1].x * 3.1));
	float flapping = mix(1.0, glide, m[2].x);
	return mix(0.14, sin(t * m[1].z + m[1].x * 7.0) * 0.85, flapping) * amp + 0.12 * (1.0 - amp);
}
"""
const BIRD_SHADER = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled;\n" + COMMON + BIRD_PATH + """
uniform vec3 body_color : source_color;
uniform vec3 wing_color : source_color;
uniform vec3 tip_color : source_color;
varying vec3 tint;
void vertex() {
	vec3 p; vec2 fwd; float bank;
	bird_path(MODEL_MATRIX, clock, p, fwd, bank);
	float span = COLOR.r, a = bird_flap(MODEL_MATRIX, clock) * (1.0 + 0.45 * span);
	vec3 local = VERTEX * MODEL_MATRIX[0].x;
	if (span > 0.0) { float x = local.x; local.x = x * cos(a); local.y += abs(x) * sin(a); }
	local.y += local.x * sin(bank);
	float show = inside(p, 1.0) * (1.0 - smoothstep(0.7, 0.85, fog_at(p)));
	tint = mix(mix(body_color, wing_color, step(0.01, span)), tip_color, COLOR.g) * mix(1.05, 0.78, clamp(abs(sin(a)) * span, 0.0, 1.0));
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(place(local * show, fwd, p), 1.0);
}
void fragment() { ALBEDO = tint; }
"""
const SHADOW_SHADER = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;\n" + COMMON + BIRD_PATH + """
uniform vec2 sun_shift;
varying vec2 quad;
varying float shade;
void vertex() {
	vec3 p; vec2 fwd; float bank;
	bird_path(MODEL_MATRIX, clock, p, fwd, bank);
	float a = bird_flap(MODEL_MATRIX, clock);
	vec3 ground = vec3(p.x + sun_shift.x * p.y, 0.06, p.z + sun_shift.y * p.y);
	vec3 local = vec3(VERTEX.x * 0.62 * cos(a), 0.0, VERTEX.z * 0.42) * MODEL_MATRIX[0].x;
	quad = VERTEX.xz;
	shade = 0.16 * inside(ground, 1.0) * (1.0 - smoothstep(0.5, 0.8, fog_at(ground)));
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(place(local, fwd, ground), 1.0);
}
void fragment() { ALBEDO = vec3(0.05, 0.08, 0.07); ALPHA = shade * (1.0 - smoothstep(0.35, 1.0, length(quad))); }
"""
# Butterflies (mode 0) loop loosely; dragonflies (mode 1) hover, then dart.
# MODEL_MATRIX[3] = anchor; [0] = size, loop x, loop z; [1] = speed, phase, mode; [2] = flap rate.
# INSTANCE_CUSTOM = wing colour. Vertex COLOR: r = side (-1..1 stored as 0..1), g = rim.
const FLUTTER_SHADER = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled;\n" + COMMON + """
varying vec3 tint;
vec3 flutter_at(mat4 m, float t) {
	float ph = m[1].y;
	if (m[1].z < 0.5)
		return m[3].xyz + vec3(sin(t * 0.5 * m[1].x + ph) * m[0].y + sin(t * 1.3 * m[1].x + ph * 2.0) * 0.4,
			0.35 * sin(t * 1.7 + ph),
			sin(t * 0.37 * m[1].x + ph * 1.7) * m[0].z + cos(t * 1.1 * m[1].x + ph) * 0.4);
	float k = t * m[1].x + ph, seg = floor(k), u = fract(k);
	vec2 from = vec2(hash1(seg), hash1(seg + 17.3)) * 2.0 - 1.0, to = vec2(hash1(seg + 1.0), hash1(seg + 18.3)) * 2.0 - 1.0;
	vec2 o = mix(from, to, smoothstep(0.72, 0.94, u)) * vec2(m[0].y, m[0].z);
	return m[3].xyz + vec3(o.x, 0.15 * sin(t * 3.0 + ph), o.y);
}
void vertex() {
	mat4 m = MODEL_MATRIX;
	vec3 p = flutter_at(m, clock), ahead = flutter_at(m, clock + 0.08) - p;
	vec2 fwd = length(ahead.xz) > 1e-4 ? normalize(ahead.xz) : vec2(0.0, 1.0);
	float dragonfly = m[1].z, flap = sin(clock * m[2].x + m[1].y * 5.0);
	float a = (dragonfly < 0.5 ? (0.25 + 0.75 * (0.5 + 0.5 * flap)) * 1.2 : 0.35 * flap) * amp;
	p.y += (dragonfly < 0.5 ? 0.06 * flap : 0.0) * amp;
	float side = COLOR.r * 2.0 - 1.0;
	vec3 local = VERTEX * m[0].x;
	if (abs(side) > 0.5) { float x = local.x; local.x = x * cos(a); local.y += abs(x) * sin(a); }
	float show = inside(p, 1.0) * (1.0 - smoothstep(0.7, 0.85, fog_at(p)));
	vec3 color = INSTANCE_CUSTOM.rgb;
	vec3 wing = dragonfly < 0.5 ? mix(color, color * 0.25, COLOR.g * 0.7) : mix(color, vec3(0.86, 0.93, 0.96), 0.72);
	vec3 body = dragonfly < 0.5 ? vec3(0.16, 0.14, 0.12) : color;
	tint = (abs(side) > 0.5 ? wing : body) * mix(1.0, 0.82, abs(sin(a)));
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(place(local * show, fwd, p), 1.0);
}
void fragment() { ALBEDO = tint; }
"""
# Fish: MODEL_MATRIX[3] = (x, size, z); [0] = direction, speed, phase; [1] = koi.
const FISH_SHADER = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;\n" + COMMON + """
varying vec3 tint;
varying float shade;
void vertex() {
	mat4 m = MODEL_MATRIX;
	float span = half_size * 2.0 - 4.0, dir = m[0].x, size = m[3].y;
	float x = mod(m[3].x + half_size - 2.0 + clock * m[0].y * dir, span) - span * 0.5;
	float z = m[3].z + sin(clock * 0.4 + m[0].z) * 0.5;
	vec3 p = vec3(x, -0.05, z);
	vec2 fwd = normalize(vec2(dir, cos(clock * 0.4 + m[0].z) * 0.2));
	vec3 local = VERTEX * size;
	local.x += sin(clock * 9.0 + m[0].z - VERTEX.z * 9.0) * 0.08 * (0.45 - VERTEX.z) * size * amp;
	float show = inside(p, 1.0) * smoothstep(4.5, 6.5, abs(x));
	tint = mix(vec3(0.12, 0.27, 0.3), vec3(0.94, 0.54, 0.24), m[1].x);
	shade = 0.6 * show * (1.0 - smoothstep(0.7, 0.85, fog_at(p)));
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(place(local * show, fwd, p), 1.0);
}
void fragment() { ALBEDO = tint; ALPHA = shade; }
"""
# Motes: one point per mote. VERTEX = base x, height (0..1), z; COLOR = rate, phase, tone, size.
const MOTE_SHADER_HEAD = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never%s;\n"
const MOTE_SHADER = COMMON + """
uniform float kind = 0.0;
uniform float pixels = 10.0;
uniform vec3 color_a : source_color;
uniform vec3 color_b : source_color;
varying vec3 tint;
varying float shade;
void vertex() {
	float t = clock, life = fract(t * COLOR.r + COLOR.g), ph = COLOR.g * 6.283;
	vec3 b = VERTEX, p; float alpha;
	if (kind < 0.5) { p = vec3(b.x + sin(t * 0.3 + ph) * 1.2 + life * 4.0, 5.0 - life * 4.8, b.z + life * 2.0); alpha = sin(life * 3.1416) * 0.6; }
	else if (kind < 1.5) { p = vec3(b.x + (life - 0.5) * 14.0, 0.25 + b.y * 1.2 + sin(t * 1.3 + ph) * 0.15, b.z + (life - 0.5) * 5.0); alpha = sin(life * 3.1416) * 0.55; }
	else if (kind < 2.5) { p = vec3(b.x + sin(t * 0.4 + ph) * 0.8, 0.6 + b.y * 2.4 + sin(t * 0.6 + ph) * 0.4, b.z + cos(t * 0.35 + ph) * 0.8); alpha = 0.55 + 0.25 * sin(t * 1.7 + ph); }
	else if (kind < 3.5) { p = vec3(b.x + sin(t * 0.45 + ph) * 1.2, 0.5 + b.y * 1.2 + sin(t * 0.9 + ph) * 0.3, b.z + cos(t * 0.33 + ph) * 1.2); alpha = pow(0.5 + 0.5 * sin(t * 2.4 + ph * 9.0), 6.0) * 0.95 + 0.05; }
	else { p = vec3(b.x + sin(t * 1.5 + ph) * 0.3, life * 5.5, b.z + cos(t * 1.2 + ph) * 0.3); alpha = (1.0 - life) * smoothstep(0.0, 0.08, life) * 0.9; }
	shade = alpha * inside(p, 1.0) * (1.0 - smoothstep(0.3, 0.75, fog_at(p)));
	tint = mix(color_a, color_b, kind > 3.5 ? life : COLOR.b);
	POINT_SIZE = clamp(COLOR.a * pixels, 1.5, 14.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
}
void fragment() { float d = length(POINT_COORD - vec2(0.5)); ALBEDO = tint; ALPHA = shade * (1.0 - smoothstep(0.15, 0.5, d)); }
"""

func _init(parent: Node3D, map_id: String, half: float, river: bool, rocks: Array, budget: float, visible_texture: Texture2D, explored_texture: Texture2D, sun_shift: Vector2):
	root = Node3D.new(); root.name = "AmbientLife"; parent.add_child(root)
	half_size = half
	plan_data = plan(map_id, half, river, rocks, budget)
	var p = plan_data
	if not p.birds.is_empty():
		var colors = BIRDS[p.look]
		var birds = family("birds", bird_mesh(), p.birds.map(func(b): return [Transform3D(Basis(Vector3(b.size, b.radius, b.speed), Vector3(b.phase, b.mode, b.flap), Vector3(b.soar, b.back, b.side)), Vector3(b.x, b.y, b.z)), Color.WHITE]),
			shader(BIRD_SHADER, half, visible_texture, explored_texture))
		birds.material_override.set_shader_parameter("body_color", Color(colors[0]))
		birds.material_override.set_shader_parameter("wing_color", Color(colors[1]))
		birds.material_override.set_shader_parameter("tip_color", Color(colors[2]))
		var shadows = family("bird-shadows", quad_mesh(), p.birds.map(func(b): return [Transform3D(Basis(Vector3(b.size, b.radius, b.speed), Vector3(b.phase, b.mode, b.flap), Vector3(b.soar, b.back, b.side)), Vector3(b.x, b.y, b.z)), Color.WHITE]),
			shader(SHADOW_SHADER, half, visible_texture, explored_texture))
		shadows.material_override.set_shader_parameter("sun_shift", sun_shift)
		# Birds fly above the battle: never killed, only thinned. Shadows follow their birds.
		groups.append({"name": "birds", "multi": birds.multimesh, "shadow": shadows.multimesh, "rows": p.birds.duplicate(), "alive": p.birds.size(), "at": Callable()})
	for kind in ["butterflies", "dragonflies"]:
		if p[kind].is_empty(): continue
		var dragonfly = 1.0 if kind == "dragonflies" else 0.0
		var node = family(kind, flutter_mesh(dragonfly > 0.5), p[kind].map(func(f): return [Transform3D(Basis(Vector3(f.size, f.rx, f.rz), Vector3(f.speed, f.phase, dragonfly), Vector3(46.0 if dragonfly > 0.5 else 16.0, 0, 0)), Vector3(f.x, f.y, f.z)), Color(f.color)]),
			shader(FLUTTER_SHADER, half, visible_texture, explored_texture))
		groups.append({"name": kind, "multi": node.multimesh, "rows": p[kind].duplicate(), "alive": p[kind].size(), "at": func(f, _t): return Vector3(f.x, f.z, maxf(f.rx, f.rz))})
	if not p.fish.is_empty():
		var fish = family("fish", fish_mesh(), p.fish.map(func(f): return [Transform3D(Basis(Vector3(f.dir, f.speed, f.phase), Vector3(f.koi, 0, 0), Vector3.ZERO), Vector3(f.x, f.size, f.z)), Color.WHITE]),
			shader(FISH_SHADER, half, visible_texture, explored_texture))
		# Same path as FISH_SHADER, so a blast kills the fish that is actually there now.
		var span = half*2.0-4.0
		groups.append({"name": "fish", "multi": fish.multimesh, "rows": p.fish.duplicate(), "alive": p.fish.size(),
			"at": func(f, t): return Vector3(fposmod(f.x+half-2.0+t*f.speed*f.dir, span)-span*0.5, f.z, 0.6)})
	if not p.motes.is_empty():
		var look = MOTES[p.mote_look]; mote_look = p.mote_look
		var node = MeshInstance3D.new(); node.name = "life_motes"; node.mesh = mote_mesh(p.motes, p.motes.size())
		groups.append({"name": "motes", "node": node, "rows": p.motes.duplicate(), "alive": p.motes.size(), "at": func(m, _t): return Vector3(m.x, m.z, 1.5)})
		var material = shader(MOTE_SHADER_HEAD % (", blend_add" if look.additive else "") + MOTE_SHADER, half, visible_texture, explored_texture)
		material.set_shader_parameter("kind", float(look.kind))
		material.set_shader_parameter("color_a", Color(look.colors[0])); material.set_shader_parameter("color_b", Color(look.colors[1]))
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-half, -1, -half), Vector3(half*2, 20, half*2))
		root.add_child(node); families.append(node)

static func mote_mesh(rows: Array, count: int) -> ArrayMesh:
	var arrays = []; arrays.resize(Mesh.ARRAY_MAX)
	var vertices = PackedVector3Array(); var data = PackedColorArray()
	for i in range(maxi(1, count)):
		var m = rows[mini(i, rows.size()-1)]
		vertices.append(Vector3(m.x, m.y if count > 0 else -100.0, m.z)); data.append(Color(m.rate, m.phase, m.tone, m.size if count > 0 else 0.0))
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_COLOR] = data
	var mesh = ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	return mesh

# Fraction of live creatures drawn: the governor thins them (and hides them at 0).
func set_share(value: float):
	share = value
	for group in groups: apply_count(group)

func apply_count(group: Dictionary):
	var n = ceili(group.alive*share)
	if group.has("multi"): group.multi.visible_instance_count = n
	if group.has("shadow"): group.shadow.visible_instance_count = n
	if group.has("node"): group.node.mesh = mote_mesh(group.rows, n)

func alive_count() -> int:
	var n = 0
	for group in groups: n += group.alive
	return n

# Combat kills the small creatures it reaches (birds fly above it). A dead creature swaps
# places with the last live one, and the draw shrinks by one.
func disturb(x: float, z: float, radius: float) -> int:
	var killed = 0
	for group in groups:
		if not group.at.is_valid(): continue
		var before = group.alive
		for i in range(group.alive-1, -1, -1):
			var at: Vector3 = group.at.call(group.rows[i], clock)
			if Vector2(at.x-x, at.y-z).length() > radius+at.z*0.5: continue
			var last = group.alive-1
			if group.has("multi"):
				var multi: MultiMesh = group.multi
				var t = multi.get_instance_transform(i); var c = multi.get_instance_custom_data(i)
				multi.set_instance_transform(i, multi.get_instance_transform(last)); multi.set_instance_custom_data(i, multi.get_instance_custom_data(last))
				multi.set_instance_transform(last, t); multi.set_instance_custom_data(last, c)
			var row = group.rows[i]; group.rows[i] = group.rows[last]; group.rows[last] = row
			group.alive -= 1; killed += 1
		if group.alive != before: apply_count(group)
	return killed

func shader(code: String, half: float, visible_texture: Texture2D, explored_texture: Texture2D) -> ShaderMaterial:
	var s = Shader.new(); s.code = code
	var m = ShaderMaterial.new(); m.shader = s
	m.set_shader_parameter("half_size", half)
	m.set_shader_parameter("visible_map", visible_texture)
	m.set_shader_parameter("explored_map", explored_texture)
	materials.append(m)
	return m

func family(name: String, mesh: Mesh, rows: Array, material: ShaderMaterial) -> MultiMeshInstance3D:
	var multi = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = mesh
	multi.instance_count = rows.size()
	for i in range(rows.size()):
		multi.set_instance_transform(i, rows[i][0])
		multi.set_instance_custom_data(i, rows[i][1])
	var node = MultiMeshInstance3D.new(); node.name = "life_"+name
	node.multimesh = multi
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Instance transforms carry parameters, not poses: cull against the whole map instead.
	var half = material.get_shader_parameter("half_size")
	node.custom_aabb = AABB(Vector3(-half, -2, -half), Vector3(half*2, 24, half*2))
	root.add_child(node); families.append(node)
	return node

# Local frame: +z forward, +x right, y up. Vertex COLOR carries per-vertex roles.
static func surface(vertices: PackedVector3Array, colors: PackedColorArray) -> ArrayMesh:
	var arrays = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_COLOR] = colors
	var mesh = ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func bird_mesh() -> ArrayMesh:
	var v = PackedVector3Array(); var c = PackedColorArray()
	var tri = func(points: Array):
		for q in points: v.append(Vector3(q[0], q[1], q[2])); c.append(Color(q[3] if q.size() > 3 else 0.0, q[4] if q.size() > 4 else 0.0, 0, 1))
	tri.call([[0, 0.03, 0.36], [-0.07, 0, 0.06], [0.07, 0, 0.06]])
	tri.call([[-0.07, 0, 0.06], [0, 0.02, -0.34], [0.07, 0, 0.06]])
	tri.call([[0, 0.02, -0.28], [-0.12, 0, -0.46], [0.12, 0, -0.46]])
	for s in [-1.0, 1.0]:
		var rf = [0.05*s, 0, 0.12, 0.08]; var rb = [0.05*s, 0, -0.12, 0.08]
		var ef = [0.32*s, 0, 0.08, 0.5]; var eb = [0.3*s, 0, -0.12, 0.5]; var tp = [0.64*s, 0, -0.16, 1.0, 1.0]
		tri.call([rf, rb, eb]); tri.call([rf, eb, ef]); tri.call([ef, eb, tp])
	return surface(v, c)

static func flutter_mesh(dragonfly: bool) -> ArrayMesh:
	var v = PackedVector3Array(); var c = PackedColorArray()
	# Corners [x, z, rim]; side stored as 0..1 in COLOR.r (0.5 = body).
	var quad = func(a: Array, b: Array, cc: Array, d: Array, side: float):
		for q in [a, b, cc, a, cc, d]: v.append(Vector3(q[0], 0, q[1])); c.append(Color(side*0.5+0.5, q[2], 0, 1))
	if dragonfly:
		quad.call([-0.025, -0.34, 0], [0.025, -0.34, 0], [0.025, 0.22, 0], [-0.025, 0.22, 0], 0.0)
		for s in [-1.0, 1.0]:
			quad.call([0.02*s, 0.1, 0], [0.36*s, 0.1, 0], [0.36*s, 0.03, 0], [0.02*s, 0.02, 0], s)
			quad.call([0.02*s, 0.0, 0], [0.3*s, 0.0, 0], [0.3*s, -0.07, 0], [0.02*s, -0.08, 0], s)
	else:
		quad.call([-0.02, -0.13, 0], [0.02, -0.13, 0], [0.02, 0.14, 0], [-0.02, 0.14, 0], 0.0)
		for s in [-1.0, 1.0]:
			quad.call([0.01*s, 0.11, 0], [0.31*s, 0.2, 1], [0.27*s, -0.03, 0.8], [0.01*s, -0.02, 0], s)
			quad.call([0.01*s, -0.02, 0], [0.23*s, -0.06, 0.8], [0.15*s, -0.22, 1], [0.01*s, -0.12, 0], s)
	return surface(v, c)

static func fish_mesh() -> ArrayMesh:
	var v = PackedVector3Array([Vector3(0, 0, 0.42), Vector3(-0.13, 0, 0.05), Vector3(0.13, 0, 0.05), Vector3(-0.13, 0, 0.05), Vector3(0, 0, -0.26), Vector3(0.13, 0, 0.05),
		Vector3(0, 0, -0.22), Vector3(-0.15, 0, -0.44), Vector3(0.15, 0, -0.44)])
	var c = PackedColorArray(); c.resize(v.size()); c.fill(Color.WHITE)
	return surface(v, c)

static func quad_mesh() -> ArrayMesh:
	var v = PackedVector3Array([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)])
	var c = PackedColorArray(); c.resize(v.size()); c.fill(Color.WHITE)
	return surface(v, c)

# level: 2 full, 1 calm, 0 still. quiet (reduced motion or animation settings off) holds still.
func update(dt: float, pixels_per_unit: float):
	var current = 0 if quiet else level
	clock = fmod(clock+clampf(dt, 0.0, 0.05)*[0.0, 0.35, 1.0][current], 3600.0)
	var wing = [0.0, 0.45, 1.0][current]
	for m in materials:
		m.set_shader_parameter("clock", clock)
		m.set_shader_parameter("amp", wing)
		m.set_shader_parameter("pixels", pixels_per_unit)

func dispose():
	if is_instance_valid(root): root.queue_free()

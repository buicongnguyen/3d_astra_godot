shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 team_color : source_color = vec4(0.5,0.9,0.7,1.0);
uniform float radius = 1.0;
uniform float clock = 0.0;
void fragment() {
 vec2 p = (UV*2.0-1.0)*(radius+0.9);
 float r = length(p); float edge = radius+0.28;
 float w = max(fwidth(r),0.015);
 float core = 1.0-smoothstep(0.035,0.035+w,abs(r-edge));
 float halo = exp(-pow((r-edge)/0.19,2.0))*0.3;
 float band = 1.0-smoothstep(0.025,0.025+w,abs(r-edge-0.28));
 float dash = step(0.45,fract(atan(p.y,p.x)/6.2831853*floor(radius*5.0+8.0)+clock*0.07));
 ALBEDO = mix(team_color.rgb,vec3(1.0),core*0.3);
 ALPHA = min(1.0,core+halo+band*dash*0.8);
}

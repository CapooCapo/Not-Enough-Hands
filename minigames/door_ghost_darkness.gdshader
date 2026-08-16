shader_type canvas_item;
render_mode unshaded;

uniform vec2 light_position = vec2(0.5, 0.5);
uniform float light_radius = 0.16;
uniform float viewport_aspect = 1.7777778;
uniform float agitation = 0.0;

float random_noise(vec2 point) {
	return fract(sin(dot(point, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 from_light = UV - light_position;
	from_light.x *= viewport_aspect;
	float distance_to_light = length(from_light);
	float reveal = 1.0 - smoothstep(light_radius * 0.54, light_radius, distance_to_light);
	float halo = 1.0 - smoothstep(light_radius, light_radius * 1.55, distance_to_light);

	float grain = random_noise(FRAGCOORD.xy + vec2(TIME * 91.0, TIME * 37.0)) - 0.5;
	float scanline = sin(FRAGCOORD.y * 0.72 + TIME * 18.0) * 0.5 + 0.5;
	float interference = grain * (0.025 + agitation * 0.075);
	interference += scanline * agitation * 0.018;

	vec3 cold_glow = vec3(0.055, 0.082, 0.105) * reveal;
	cold_glow += vec3(0.018, 0.025, 0.032) * halo;
	float darkness = 1.0 - reveal * 0.965;
	COLOR = vec4(cold_glow, clamp(darkness + interference, 0.025, 1.0));
}

shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Procedural weathered marble for the statue ghost.
// Everything is generated in world space so no texture assets are needed and
// neighbouring body parts never repeat the same pattern.

uniform vec3 stone_color : source_color = vec3(0.155, 0.163, 0.156);
uniform vec3 pale_color : source_color = vec3(0.335, 0.345, 0.325);
uniform vec3 grime_color : source_color = vec3(0.026, 0.031, 0.028);
uniform vec3 vein_color : source_color = vec3(0.62, 0.055, 0.025);
uniform vec3 rim_color : source_color = vec3(0.34, 0.43, 0.52);
uniform float noise_scale : hint_range(0.5, 24.0) = 6.0;
uniform float grime_amount : hint_range(0.0, 1.0) = 0.7;
uniform float crack_density : hint_range(0.0, 1.0) = 0.6;
uniform float bump_strength : hint_range(0.0, 3.0) = 1.15;
uniform float rim_power : hint_range(0.5, 8.0) = 3.4;
uniform float rim_strength : hint_range(0.0, 4.0) = 1.1;
uniform float damp_sheen : hint_range(0.0, 1.0) = 0.35;
// Driven from statue_ghost.gd: 0.0 = inert stone, 1.0 = about to kill you.
uniform float agitation : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_position;
varying vec3 world_normal;

float hash13(vec3 p) {
	p = fract(p * vec3(0.1031, 0.11369, 0.13787));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(cell);
	float n100 = hash13(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(cell + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amplitude;
		p = p * 2.07 + vec3(11.3, 7.1, 5.9);
		amplitude *= 0.5;
	}
	return total;
}

// Two octaves only - used for the bump gradient where detail is cheap to fake.
float fbm_cheap(vec3 p) {
	return value_noise(p) * 0.62 + value_noise(p * 2.07 + vec3(11.3, 7.1, 5.9)) * 0.31;
}

// Ridged noise squeezed into thin lines: hairline fractures through the marble.
float crack_field(vec3 p) {
	float n = value_noise(p) * 0.6 + value_noise(p * 2.3 + vec3(5.0)) * 0.4;
	float ridge = 1.0 - abs(n * 2.0 - 1.0);
	// A high exponent is what keeps these hairline. Lower it and the statue
	// turns into glowing lava tubes rather than cracked marble.
	return pow(clamp(ridge, 0.0, 1.0), 96.0);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 surface_normal = normalize(world_normal);
	vec3 sample_position = world_position * noise_scale;
	float mottle = fbm(sample_position);
	float grime = fbm(sample_position * 0.35 + vec3(37.0, 12.0, 91.0));
	float cracks = crack_field(sample_position * 3.2);

	// Dirt pools on upward-facing ledges and in the deep grime noise.
	float upward = clamp(surface_normal.y * 0.5 + 0.5, 0.0, 1.0);
	float dirt = clamp(grime_amount * (grime * 0.8 + upward * 0.35), 0.0, 1.0);

	vec3 base = mix(stone_color, pale_color, smoothstep(0.34, 0.72, mottle));
	base = mix(base, grime_color, dirt);
	base = mix(base, grime_color * 0.45, cracks * crack_density);
	ALBEDO = base;

	METALLIC = 0.0;
	ROUGHNESS = mix(0.98, 0.58, damp_sheen * smoothstep(0.30, 0.80, mottle) * (1.0 - dirt));
	SPECULAR = mix(0.1, 0.45, damp_sheen);
	AO = clamp(1.0 - dirt * 0.5 - cracks * 0.45, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.6;

	// Bump relief from the height gradient, flattened onto the tangent plane.
	float eps = 0.7;
	float height = fbm_cheap(sample_position);
	vec3 gradient = vec3(
		fbm_cheap(sample_position + vec3(eps, 0.0, 0.0)) - height,
		fbm_cheap(sample_position + vec3(0.0, eps, 0.0)) - height,
		fbm_cheap(sample_position + vec3(0.0, 0.0, eps)) - height) / eps;
	gradient -= surface_normal * dot(gradient, surface_normal);
	vec3 bumped = normalize(surface_normal - gradient * bump_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);

	// Cold fresnel rim so the silhouette still reads in an unlit corridor.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	vec3 rim = mix(rim_color, vein_color, agitation * 0.4);
	rim *= fresnel * rim_strength * (0.6 + 0.3 * agitation);

	// The fractures light up from inside as it closes on the player.
	float pulse = 0.72 + 0.28 * sin(TIME * 2.3);
	vec3 veins = vein_color * cracks * agitation * 0.5 * pulse;

	EMISSION = rim + veins;
}

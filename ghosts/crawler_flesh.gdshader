shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Procedural wet skin for the Crawler.
// Same world-space, texture-free approach as statue_stone.gdshader so the two
// ghosts stay in one art language, but every property is inverted: the statue is
// dry, cold and mineral, this is damp, warm-dark and organic. Nothing here
// repeats across neighbouring limbs because the pattern is sampled in world
// space, which matters a lot on a body made of duplicated primitives.

uniform vec3 flesh_color : source_color = vec3(0.185, 0.135, 0.128);
uniform vec3 pale_color : source_color = vec3(0.365, 0.315, 0.285);
// Skin stretched paper-thin over the bone ridges lets this bruised tone through.
uniform vec3 bruise_color : source_color = vec3(0.115, 0.055, 0.075);
uniform vec3 vein_color : source_color = vec3(0.34, 0.045, 0.045);
uniform vec3 wet_tint : source_color = vec3(0.62, 0.66, 0.7);
uniform float noise_scale : hint_range(0.5, 24.0) = 8.5;
uniform float pore_scale : hint_range(1.0, 60.0) = 26.0;
// How much of the body reads as taut skin over bone rather than slack muscle.
uniform float bone_show_through : hint_range(0.0, 1.0) = 0.66;
uniform float vein_density : hint_range(0.0, 1.0) = 0.55;
uniform float bump_strength : hint_range(0.0, 3.0) = 1.35;
uniform float wetness : hint_range(0.0, 1.0) = 0.78;
uniform float rim_power : hint_range(0.5, 8.0) = 2.6;
uniform float rim_strength : hint_range(0.0, 4.0) = 0.85;
// Driven from crawler_ghost.gd: 0.0 = dormant in a crawlspace, 1.0 = mid-pounce.
uniform float agitation : hint_range(0.0, 1.0) = 0.0;
// Rises while it is actively drawing breath, so the ribcage visibly works.
uniform float breath : hint_range(0.0, 1.0) = 0.0;

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

float fbm_cheap(vec3 p) {
	return value_noise(p) * 0.62 + value_noise(p * 2.07 + vec3(11.3, 7.1, 5.9)) * 0.31;
}

// Ridged noise, but deliberately far broader than the statue's hairline cracks:
// these are swollen vessels sitting on top of the skin, not fractures in it.
float vein_field(vec3 p) {
	float n = value_noise(p) * 0.62 + value_noise(p * 2.1 + vec3(9.0)) * 0.38;
	float ridge = 1.0 - abs(n * 2.0 - 1.0);
	return pow(clamp(ridge, 0.0, 1.0), 14.0);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 surface_normal = normalize(world_normal);
	vec3 sample_position = world_position * noise_scale;

	float flesh_mottle = fbm(sample_position);
	float pores = value_noise(world_position * pore_scale);
	float veins = vein_field(sample_position * 1.7) * vein_density;

	// Where the mesh curves away hardest is where a real body would have a bone
	// pressed against the inside of the skin. Using curvature (approximated by
	// the noise gradient) instead of a mask keeps this working on primitives.
	float taut = smoothstep(0.42, 0.86, flesh_mottle) * bone_show_through;

	vec3 base = mix(flesh_color, pale_color, taut);
	base = mix(base, bruise_color, smoothstep(0.55, 0.15, flesh_mottle) * 0.7);
	base = mix(base, vein_color, veins * 0.55);
	base *= 0.88 + pores * 0.24;
	ALBEDO = base;

	METALLIC = 0.0;
	// Wet skin is glossy in the hollows where fluid collects and duller on the
	// stretched highlights - the inverse of how the statue's grime behaves.
	float film = clamp(wetness * (0.55 + (1.0 - flesh_mottle) * 0.6), 0.0, 1.0);
	ROUGHNESS = mix(0.82, 0.14, film);
	SPECULAR = mix(0.35, 0.85, film);
	AO = clamp(1.0 - veins * 0.3 - (1.0 - taut) * 0.18, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.75;

	float eps = 0.55;
	float height = fbm_cheap(sample_position);
	vec3 gradient = vec3(
		fbm_cheap(sample_position + vec3(eps, 0.0, 0.0)) - height,
		fbm_cheap(sample_position + vec3(0.0, eps, 0.0)) - height,
		fbm_cheap(sample_position + vec3(0.0, 0.0, eps)) - height) / eps;
	gradient -= surface_normal * dot(gradient, surface_normal);
	// Veins are raised, so they push the normal outward rather than carving in.
	vec3 bumped = normalize(surface_normal - (gradient - surface_normal * veins * 0.35) * bump_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);

	// A wet, almost colourless rim. This is the only thing that reads at all in
	// a pitch-black hallway before the flashlight finds it - and it reads as
	// something slick, which is the whole point.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	vec3 rim = wet_tint * fresnel * rim_strength * (0.5 + 0.7 * wetness);

	// Blood pushed into the surface vessels: it flushes as the thing winds up,
	// and pulses on the breath rate rather than on a fixed clock.
	float pulse = 0.6 + 0.4 * sin(TIME * (2.1 + 5.5 * agitation));
	vec3 flush = vein_color * veins * (agitation * 0.55 + breath * 0.3) * pulse;

	EMISSION = rim + flush;
}

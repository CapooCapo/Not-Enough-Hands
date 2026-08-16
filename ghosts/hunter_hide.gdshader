shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Procedural waxed leather / oilcloth for the Huntsman.
// Same world-space, texture-free approach as statue_stone.gdshader and
// crawler_flesh.gdshader so all three ghosts stay in one art language, but this
// one is a third material entirely: the statue is dry mineral, the crawler is
// wet organic, this is *worn* - tanned hide, soaked coat wax, old blood in the
// seams. It is the only one of the three that is dressed, and that reads as the
// worst thing about it: something in the house is wearing clothes.

uniform vec3 hide_color : source_color = vec3(0.078, 0.062, 0.052);
// Where the wax has cracked and the bare hide underneath shows through.
uniform vec3 worn_color : source_color = vec3(0.215, 0.165, 0.118);
uniform vec3 grime_color : source_color = vec3(0.022, 0.018, 0.015);
// Dried into the folds. Not fresh, and not its own.
uniform vec3 stain_color : source_color = vec3(0.16, 0.028, 0.022);
// The lantern hangs off its own hand, so the whole body is permanently lit
// from one warm source. This tint fakes that bounce even in a black corridor.
uniform vec3 lantern_tint : source_color = vec3(0.92, 0.52, 0.2);
uniform float noise_scale : hint_range(0.5, 24.0) = 5.5;
// Coarse woven canvas over the top of the hide grain.
uniform float weave_scale : hint_range(1.0, 80.0) = 42.0;
uniform float wax_amount : hint_range(0.0, 1.0) = 0.62;
uniform float crack_density : hint_range(0.0, 1.0) = 0.55;
uniform float stain_amount : hint_range(0.0, 1.0) = 0.45;
uniform float bump_strength : hint_range(0.0, 3.0) = 1.05;
uniform float rim_power : hint_range(0.5, 8.0) = 3.1;
uniform float rim_strength : hint_range(0.0, 4.0) = 0.55;
// Driven from hunter_ghost.gd: 0.0 = walking its search pattern, 1.0 = charging.
uniform float agitation : hint_range(0.0, 1.0) = 0.0;
// How hard the lantern is currently burning. Rises with agitation, and flares
// the instant it locks on - the body brightens a beat before it moves.
uniform float lantern_glow : hint_range(0.0, 2.0) = 0.55;

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
		p = p * 2.03 + vec3(5.7, 13.1, 9.3);
		amplitude *= 0.5;
	}
	return total;
}

float fbm_cheap(vec3 p) {
	return value_noise(p) * 0.64 + value_noise(p * 2.03 + vec3(5.7, 13.1, 9.3)) * 0.3;
}

// Hairline cracks in the wax. Ridged like the statue's fractures but far
// shallower and far more numerous - this is a surface finish failing, not stone
// splitting, so the ridges have to stay thin and stop short of joining up.
float crack_field(vec3 p) {
	float n = value_noise(p) * 0.66 + value_noise(p * 2.4 + vec3(3.0)) * 0.34;
	float ridge = 1.0 - abs(n * 2.0 - 1.0);
	return pow(clamp(ridge, 0.0, 1.0), 22.0);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 surface_normal = normalize(world_normal);
	vec3 sample_position = world_position * noise_scale;

	float grain = fbm(sample_position);
	// A near-square weave, sampled on two axes rather than three so it reads as
	// woven cloth instead of three-dimensional foam.
	float weave = value_noise(vec3(world_position.x, world_position.y, 0.0) * weave_scale)
		* value_noise(vec3(0.0, world_position.y, world_position.z) * weave_scale);
	float cracks = crack_field(sample_position * 2.2) * crack_density;
	// Fluids run down a hanging coat, so the stains are stretched vertically.
	float stains = smoothstep(0.58, 0.86, fbm(world_position * vec3(6.5, 1.6, 6.5))) * stain_amount;

	vec3 base = mix(hide_color, worn_color, smoothstep(0.5, 0.95, grain) * 0.8);
	base = mix(base, grime_color, smoothstep(0.48, 0.1, grain) * 0.75);
	base = mix(base, worn_color * 1.15, cracks * 0.6);
	base = mix(base, stain_color, stains);
	base *= 0.9 + weave * 0.3;
	ALBEDO = base;

	METALLIC = 0.0;
	// Wax is glossy on the raised, rubbed areas and dead matte where it has
	// cracked away - the opposite distribution to the crawler's wet hollows.
	float wax = clamp(wax_amount * smoothstep(0.35, 0.9, grain) * (1.0 - cracks), 0.0, 1.0);
	ROUGHNESS = mix(0.94, 0.31, wax);
	SPECULAR = mix(0.2, 0.62, wax);
	AO = clamp(1.0 - cracks * 0.35 - (1.0 - grain) * 0.2, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.7;

	float eps = 0.6;
	float height = fbm_cheap(sample_position);
	vec3 gradient = vec3(
		fbm_cheap(sample_position + vec3(eps, 0.0, 0.0)) - height,
		fbm_cheap(sample_position + vec3(0.0, eps, 0.0)) - height,
		fbm_cheap(sample_position + vec3(0.0, 0.0, eps)) - height) / eps;
	gradient -= surface_normal * dot(gradient, surface_normal);
	// Cracks cut in rather than standing proud, so they subtract from the height.
	vec3 bumped = normalize(surface_normal - (gradient + surface_normal * cracks * 0.4) * bump_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);

	// The lantern's own bounce. It is deliberately warm and deliberately dim: in
	// a black hallway this is what you see first - not a shape, just a coat
	// catching orange light from something you cannot see yet.
	float lamp_flicker = 0.86 + 0.14 * sin(TIME * 11.3 + world_position.y * 4.0)
		* (0.4 + 0.6 * sin(TIME * 3.7));
	vec3 bounce = lantern_tint * lantern_glow * lamp_flicker * (0.14 + fresnel * 0.5)
		* (0.55 + wax * 0.6);
	// Blood-heat under the collar as it commits to a charge.
	vec3 heat = stain_color * stains * agitation * (0.4 + 0.6 * sin(TIME * (2.4 + 6.0 * agitation)));

	EMISSION = bounce + heat + lantern_tint * fresnel * rim_strength * 0.12;
}

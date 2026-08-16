shader_type canvas_item;

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.48;
uniform float grain_strength : hint_range(0.0, 0.15) = 0.025;
uniform float pulse_strength : hint_range(0.0, 0.2) = 0.018;

float random_noise(vec2 position) {
	return fract(sin(dot(position, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	centered_uv.x *= 0.72;
	float edge = smoothstep(0.24, 0.58, length(centered_uv));
	float pulse = sin(TIME * 0.72) * 0.5 + 0.5;
	float grain = random_noise(floor(UV * vec2(640.0, 360.0)) + floor(TIME * 18.0));
	float darkness = edge * (vignette_strength + pulse * pulse_strength);
	darkness += grain * grain_strength;
	COLOR = vec4(0.0, 0.008, 0.012, clamp(darkness, 0.0, 0.82));
}

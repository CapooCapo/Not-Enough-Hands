shader_type canvas_item;

uniform float closure : hint_range(0.0, 1.0) = 0.0;
uniform vec4 eyelid_color : source_color = vec4(0.001, 0.002, 0.003, 1.0);

void fragment() {
	float closed_amount = smoothstep(0.0, 1.0, closure);
	float half_opening = (1.0 - closed_amount) * 0.5;
	float horizontal = abs(UV.x - 0.5) * 2.0;
	float eye_curve = pow(horizontal, 2.2) * 0.105 * closed_amount;
	float feather = 0.014 + (1.0 - closed_amount) * 0.006;

	float upper_edge = 0.5 - half_opening + eye_curve;
	float lower_edge = 0.5 + half_opening - eye_curve;
	float upper_lid = 1.0 - smoothstep(upper_edge - feather, upper_edge + feather, UV.y);
	float lower_lid = smoothstep(lower_edge - feather, lower_edge + feather, UV.y);
	float lid_alpha = max(upper_lid, lower_lid) * smoothstep(0.0, 0.035, closed_amount);

	float crease = 1.0 - smoothstep(0.0, 0.025, min(abs(UV.y - upper_edge), abs(UV.y - lower_edge)));
	vec3 color = eyelid_color.rgb + vec3(0.012, 0.006, 0.004) * crease * closed_amount;
	COLOR = vec4(color, lid_alpha * eyelid_color.a);
}

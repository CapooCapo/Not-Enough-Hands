shader_type canvas_item;
render_mode unshaded;

// The licensed Sketchfab preview is landscape. Sample only the model's head
// and key out its neutral studio background at render time.
uniform vec2 crop_min = vec2(0.32, 0.12);
uniform vec2 crop_max = vec2(0.68, 0.92);

void fragment() {
	vec2 cropped_uv = mix(crop_min, crop_max, UV);
	vec4 source = texture(TEXTURE, cropped_uv);
	float brightest = max(source.r, max(source.g, source.b));
	float darkest = min(source.r, min(source.g, source.b));
	float chroma = brightest - darkest;
	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	float neutral = 1.0 - smoothstep(0.035, 0.13, chroma);
	float studio_background = neutral * smoothstep(0.68, 0.84, luminance);
	float keyed_alpha = source.a * (1.0 - studio_background);
	COLOR = vec4(source.rgb * COLOR.rgb, keyed_alpha * COLOR.a);
}

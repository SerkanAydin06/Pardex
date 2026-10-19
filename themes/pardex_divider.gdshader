shader_type canvas_item;
render_mode unshaded;

// A paired beat followed by a calm pause. Only the innermost short light strip is lit.
uniform float preview_time = -1.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float t = mod(preview_time >= 0.0 ? preview_time : TIME, 1.8);
	float first = exp(-pow((t - 0.24) / 0.105, 2.0));
	float second = 0.65 * exp(-pow((t - 0.51) / 0.14, 2.0));
	float beat = clamp(first + second, 0.0, 1.0) * intensity;
	// Coordinates of the original 232 x 18 SVG: the white core is x112..120.
	vec2 offset = (UV - vec2(0.5)) * vec2(232.0, 18.0);
	float core = (1.0 - smoothstep(3.5, 5.0, abs(offset.x)))
		* (1.0 - smoothstep(0.6, 2.0, abs(offset.y)));
	vec3 resting = base.rgb * (1.0 - core * 0.65);
	vec3 lit = mix(resting, vec3(0.78, 0.97, 1.0), core * beat);
	COLOR = vec4(lit, base.a);
}

shader_type canvas_item;
render_mode unshaded;

// A paired beat followed by a calm pause. Only the 36 px center is lit.
uniform float preview_time = -1.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float t = mod(preview_time >= 0.0 ? preview_time : TIME, 1.8);
	float first = exp(-pow((t - 0.24) / 0.105, 2.0));
	float second = 0.65 * exp(-pow((t - 0.51) / 0.14, 2.0));
	float beat = clamp(first + second, 0.0, 1.0) * intensity;
	float center = 1.0 - smoothstep(0.055, 0.095, abs(UV.x - 0.5));
	float halo = exp(-pow((UV.x - 0.5) / 0.062, 2.0)
		- pow((UV.y - 0.5) / 0.24, 2.0)) * center;
	vec3 lit = mix(base.rgb, vec3(0.68, 0.94, 1.0), beat * center * 0.88);
	float glow_alpha = beat * halo * 0.6;
	float alpha = base.a + glow_alpha * (1.0 - base.a);
	vec3 color = (lit * base.a + vec3(0.09, 0.65, 1.0) * glow_alpha * (1.0 - base.a)) / max(alpha, 0.0001);
	COLOR = vec4(color, alpha);
}

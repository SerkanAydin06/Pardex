shader_type canvas_item;
render_mode unshaded;

uniform float effect_time = 2.0;
uniform bool effects_enabled = true;
uniform bool motion_enabled = true;
uniform float sweep_period : hint_range(4.0, 20.0) = 10.0;
uniform float sweep_strength : hint_range(0.0, 1.0) = 0.38;
uniform float glow_strength : hint_range(0.0, 0.6) = 0.20;
uniform vec4 glow_color : source_color = vec4(0.12, 0.66, 1.0, 1.0);

void fragment() {
	vec4 tint = COLOR;
	vec4 original = texture(TEXTURE, UV);
	vec4 result = original;
	if (effects_enabled) {
		// The glow follows the transparent silhouette, not the rectangular image.
		vec2 radius = vec2(0.008, 0.008 * TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x);
		float halo = 0.0;
		halo += texture(TEXTURE, UV + vec2(radius.x, 0.0)).a;
		halo += texture(TEXTURE, UV - vec2(radius.x, 0.0)).a;
		halo += texture(TEXTURE, UV + vec2(0.0, radius.y)).a;
		halo += texture(TEXTURE, UV - vec2(0.0, radius.y)).a;
		halo += texture(TEXTURE, UV + radius * 0.707).a;
		halo += texture(TEXTURE, UV - radius * 0.707).a;
		halo += texture(TEXTURE, UV + vec2(radius.x, -radius.y) * 0.707).a;
		halo += texture(TEXTURE, UV + vec2(-radius.x, radius.y) * 0.707).a;
		halo = max(halo * 0.125 - original.a, 0.0);
		float pulse = motion_enabled ? 0.82 + 0.18 * sin(effect_time * 1.1) : 0.85;
		float cycle = mod(effect_time, max(sweep_period, 4.0));
		float progress = clamp(cycle / 1.8, 0.0, 1.0);
		float center = mix(-0.25, 1.25, progress);
		float distance_to_light = abs(UV.x + (UV.y - 0.5) * 0.15 - center);
		float sweep = (1.0 - smoothstep(0.0, 0.07, distance_to_light));
		sweep *= motion_enabled && cycle < 1.8 ? 1.0 : 0.0;
		// White reflections emphasize the chrome while retaining the blue accents.
		float metal = smoothstep(0.12, 0.8, dot(original.rgb, vec3(0.299, 0.587, 0.114)));
		vec3 lit = original.rgb + vec3(0.70, 0.85, 1.0) * sweep * sweep_strength * (0.35 + metal * 0.65);
		float glow_alpha = halo * glow_strength * pulse;
		float alpha = original.a + glow_alpha * (1.0 - original.a);
		result = vec4((lit * original.a + glow_color.rgb * glow_alpha * (1.0 - original.a)) / max(alpha, 0.0001), alpha);
		float intro = motion_enabled ? smoothstep(0.0, 0.9, effect_time) : 1.0;
		result.rgb *= mix(0.72, 1.0, intro);
	}
	COLOR = result * tint;
}

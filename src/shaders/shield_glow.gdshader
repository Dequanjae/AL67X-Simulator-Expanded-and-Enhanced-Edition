shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;

uniform vec4 color : source_color = vec4(0.35, 0.85, 1.0, 0.55);

void fragment() {
	float pulse = 0.7 + 0.3 * sin(TIME * 3.0);
	vec3 glow = color.rgb * (1.0 + 0.4 * abs(UV.x - 0.5) * 2.0);
	ALBEDO = glow;
	ALPHA = color.a * pulse;
}

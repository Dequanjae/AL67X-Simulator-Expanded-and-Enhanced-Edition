shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;

uniform vec4 albedo_color : source_color = vec4(0.96, 0.96, 0.94, 0.92);

void fragment() {
	vec2 uv = UV - 0.5;
	float angle = atan(uv.y, uv.x);
	float d = length(uv) * 2.0;
	float edge = 0.34 + 0.08 * sin(angle * 3.0 + 2.2) + 0.05 * sin(angle * 7.0 + 0.9);
	float alpha = smoothstep(edge, edge - 0.12, d);
	ALBEDO = albedo_color.rgb;
	ALPHA = albedo_color.a * alpha;
}

shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
// Goop projectile — spatial billboard adaptation of Erich_L's MIT-licensed
// "Goop Projectile" canvas shader (godotshaders.com/shader/goop-projectile):
// a radial blob whose UVs are displaced by scrolling noise, lerping between
// two colors. Per-instance variety via INSTANCE_CUSTOM.x (random seed) and
// flow direction from INSTANCE_CUSTOM.yz.

uniform sampler2D flow_map : filter_linear, repeat_enable;
uniform float strength : hint_range(0.0, 1.0) = 0.3;
uniform vec4 color1 : source_color = vec4(0.9, 1.0, 0.98, 1.0);
uniform vec4 color2 : source_color = vec4(0.55, 0.95, 1.0, 1.0);
uniform float blob_radius : hint_range(0.1, 0.5) = 0.32;
uniform float blob_soft : hint_range(0.01, 0.3) = 0.10;

varying float v_seed;
varying vec2 v_dir;

void vertex() {
	v_seed = INSTANCE_CUSTOM.x;
	v_dir = INSTANCE_CUSTOM.yz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 flow_uv = vec2(
		UV.x + v_seed - TIME * v_dir.x,
		UV.y + v_seed + TIME * v_dir.y);
	float noise_sample = texture(flow_map, flow_uv).r;
	vec2 offset = vec2(noise_sample) * strength - vec2(0.5) * strength;
	// Displaced radial blob instead of a source texture.
	float d = distance(UV + offset, vec2(0.5));
	float alpha = 1.0 - smoothstep(blob_radius, blob_radius + blob_soft, d);
	vec3 goop = mix(color1.rgb, color2.rgb, clamp(noise_sample * 1.3, 0.0, 1.0));
	ALBEDO = goop;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.05;
}

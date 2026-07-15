shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

uniform sampler2D sprite_tex : source_color, filter_linear_mipmap;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);

varying float v_flip;
varying float v_flash;
varying float v_telegraph;

void vertex() {
	v_flip = INSTANCE_CUSTOM.x;
	v_flash = INSTANCE_CUSTOM.y;
	v_telegraph = INSTANCE_CUSTOM.z;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV;
	if (v_flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	uv = uv_rect.xy + uv * uv_rect.zw;
	vec4 tex_color = texture(sprite_tex, uv);
	float telegraph_pulse = v_telegraph > 0.5 ? 0.5 + 0.5 * sin(TIME * 20.0) : 0.0;
	float flash = clamp(v_flash, 0.0, 1.0);
	float render_flash = max(flash, telegraph_pulse);
	ALBEDO = mix(tex_color.rgb * COLOR.rgb, vec3(1.0), render_flash);
	ALPHA = tex_color.a * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = 0.1;
}

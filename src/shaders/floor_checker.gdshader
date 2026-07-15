shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 color1 : source_color = vec4(0.29, 0.31, 0.34, 1.0);
uniform vec4 color2 : source_color = vec4(0.26, 0.27, 0.30, 1.0);
uniform vec4 accent : source_color = vec4(0.79, 0.66, 0.42, 1.0);
uniform float tile_count = 40.0;
uniform sampler2D floor_tex : source_color, filter_linear;
uniform float tex_strength = 0.0;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 tile_uv = v_world_pos.xz + 0.5;
	ivec2 tile = ivec2(floor(tile_uv));
	bool check = ((tile.x + tile.y) & 1) == 0;
	vec4 color = check ? color1 : color2;
	if ((tile.x * 31 + tile.y * 17) % 23 == 0) {
		color = mix(color, accent, 0.25);
	}
	if (tex_strength > 0.0) {
		vec4 tex = texture(floor_tex, v_world_pos.xz * 0.5);
		color = mix(color, color * tex, tex_strength);
	}
	ALBEDO = color.rgb;
	ALPHA = 1.0;
}

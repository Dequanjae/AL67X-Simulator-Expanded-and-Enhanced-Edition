shader_type canvas_item;
// Death spotlight: darkens the whole screen except a soft circle over
// Allan (spec Section 4 — spotlight on the player during the death freeze).
// Applied to a full-screen ColorRect; `center` is in UV space.

uniform vec2 center = vec2(0.5, 0.5);
uniform float radius : hint_range(0.0, 1.0) = 0.16;
uniform float softness : hint_range(0.0, 0.5) = 0.10;
uniform float darkness : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.777778;

void fragment() {
	vec2 uv = vec2(UV.x * aspect, UV.y);
	vec2 c = vec2(center.x * aspect, center.y);
	float mask = smoothstep(radius, radius + softness, distance(uv, c));
	COLOR = vec4(0.0, 0.0, 0.0, mask * darkness);
}

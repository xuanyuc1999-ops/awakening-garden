shader_type spatial;
render_mode diffuse_burley;

uniform vec4 base_color : source_color = vec4(0.72, 0.57, 0.39, 1.0);
uniform vec4 patch_color : source_color = vec4(0.85, 0.63, 0.43, 1.0);
uniform vec4 edge_color : source_color = vec4(0.29, 0.40, 0.20, 1.0);
uniform vec4 side_color : source_color = vec4(0.43, 0.39, 0.28, 1.0);
varying vec3 world_position;
varying float upward_face;

float hash_cell(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float painted_patch(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), f.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	upward_face = abs(NORMAL.y);
}

void fragment() {
	float broad = painted_patch(world_position.xz * 0.42);
	float brush = painted_patch(world_position.xz * vec2(2.8, 0.9));
	vec3 earth = mix(base_color.rgb, patch_color.rgb, 0.12 + broad * 0.38) * (0.96 + brush * 0.07);
	float edge = smoothstep(7.0 + broad * 0.9, 9.4, abs(world_position.x));
	float broken_edge = smoothstep(0.28, 0.65, painted_patch(world_position.xz * 1.8));
	earth = mix(earth, edge_color.rgb, edge * (0.45 + broken_edge * 0.5));
	vec3 side = side_color.rgb * (0.78 + painted_patch(world_position.xz * 1.3 + world_position.yy) * 0.24);
	ALBEDO = mix(side, earth, step(0.5, upward_face));
	ROUGHNESS = 0.96;
}

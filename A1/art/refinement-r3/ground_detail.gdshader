shader_type spatial;
render_mode diffuse_burley, cull_disabled;

// No displacement: the original playable planes remain at y=0.
// Modes: ground, stone, moss, furrow, pebble/leaf.
uniform int surface_kind = 0;
uniform bool moon_style = false;
uniform mat4 world_to_garden;
uniform vec4 earth_color : source_color = vec4(0.62, 0.40, 0.22, 1.0);
uniform vec4 worn_color : source_color = vec4(0.77, 0.57, 0.34, 1.0);
uniform vec4 moss_color : source_color = vec4(0.34, 0.43, 0.15, 1.0);
uniform vec4 side_color : source_color = vec4(0.38, 0.34, 0.25, 1.0);
uniform vec4 wear_segments[18];
uniform vec2 bed_centers[9];
varying vec3 garden_position;
varying float upward;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float grain(vec2 p) {
	vec2 a = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(a), hash21(a + vec2(1.0, 0.0)), f.x),
		mix(hash21(a + vec2(0.0, 1.0)), hash21(a + vec2(1.0)), f.x), f.y);
}

float segment_distance(vec2 p, vec4 segment) {
	vec2 v = segment.zw - segment.xy;
	float t = clamp(dot(p - segment.xy, v) / max(dot(v, v), 0.0001), 0.0, 1.0);
	return length(p - segment.xy - t * v);
}

void vertex() {
	garden_position = (world_to_garden * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	upward = abs((world_to_garden * MODEL_MATRIX * vec4(NORMAL, 0.0)).y);
}

void fragment() {
	vec2 p = garden_position.xz;
	float broad = grain(p * 0.73 + grain(p * 1.57) * 0.37);
	float fleck = grain(p * 12.0);
	// Fade subpixel grains instead of letting distant ground shimmer.
	float fine_visibility = 1.0 - smoothstep(0.018, 0.08, length(fwidth(p)));
	float fine = mix(0.5, grain(p * 76.0), fine_visibility);
	vec3 albedo = COLOR.rgb;
	float relief = 0.0;
	float rough = 0.94;
	if (surface_kind == 0) {
		// The authored cliff meshes replace the old rectangular floor sides.
		if (upward < 0.5) { discard; }
		float wear_distance = 50.0;
		for (int i = 0; i < 18; i++) {
			wear_distance = min(wear_distance, segment_distance(p, wear_segments[i]));
		}
		float worn = 1.0 - smoothstep(0.75, 2.45, wear_distance + (broad - 0.5) * 0.75);
		float bed_distance = 40.0;
		for (int i = 0; i < 9; i++) {
			vec2 q = abs(p - bed_centers[i]) - vec2(1.24);
			bed_distance = min(bed_distance, length(max(q, vec2(0.0))));
		}
		float border = min(9.65 - abs(p.x), bed_distance);
		float moss = (1.0 - smoothstep(0.05, 0.85, border + (broad - 0.5) * 1.25));
		moss *= smoothstep(0.20, 0.65, grain(p * 3.1)) * (1.0 - worn * 0.75);
		albedo = mix(earth_color.rgb, worn_color.rgb, worn * 0.73 + broad * 0.16);
		albedo *= 0.89 + fleck * 0.12 + fine * 0.08;
		albedo = mix(albedo, moss_color.rgb * (0.74 + fleck * 0.40), moss);
		if (moon_style) {
			// Visible only between the real individual slate meshes.
			albedo = mix(earth_color.rgb * 0.48, moss_color.rgb * 0.58,
				smoothstep(0.40, 0.70, broad));
		}
		if (upward < 0.5) {
			albedo = side_color.rgb * (0.82 + broad * 0.25);
		}
		relief = (fleck * 0.0025 + fine * 0.0015) * step(0.5, upward);
	} else if (surface_kind == 1) {
		// Mineral clouds and fractured laminae, subordinate to the actual bevels.
		float mineral = grain(p * 2.8 + vec2(grain(p * 0.9)));
		float lamina = grain(vec2(p.x * 8.0 + p.y * 1.7, p.y * 15.0));
		float crack_line = abs(UV.y - (0.45 + sin(UV.x * 12.0 + COLOR.r * 31.0) * 0.09
			+ sin(UV.x * 31.0) * 0.021));
		float aa = max(fwidth(crack_line), 0.001);
		float crack = (1.0 - smoothstep(0.002, 0.002 + aa, crack_line));
		// Vertex alpha is a stable per-slab fissure selector, never transparency.
		crack *= step(0.5, COLOR.a) * smoothstep(0.10, 0.22, UV.x)
			* (1.0 - smoothstep(0.72, 0.94, UV.x));
		albedo *= 0.80 + mineral * 0.21 + lamina * 0.07 + fine * 0.04;
		albedo = mix(albedo, albedo * 0.36, crack * 0.75);
		relief = mineral * 0.003 + lamina * 0.0015 - crack * 0.001;
		rough = 0.88 + fleck * 0.1;
	} else if (surface_kind == 2) {
		// Broad lobed mesh silhouettes carry this material; grain only adds pores.
		albedo *= 0.75 + fleck * 0.32 + fine * 0.10;
		relief = fleck * 0.002;
	} else if (surface_kind == 3) {
		albedo *= 0.79 + fleck * 0.30 + fine * 0.12;
		relief = fleck * 0.0025;
	} else {
		albedo *= 0.89 + fleck * 0.16;
		rough = 0.96;
	}
	// Analytic screen-space bump works on merged meshes without tangent UV seams.
	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	vec3 r1 = cross(dy, NORMAL);
	vec3 r2 = cross(NORMAL, dx);
	float determinant = dot(dx, r1);
	vec3 gradient = sign(determinant) * (dFdx(relief) * r1 + dFdy(relief) * r2);
	NORMAL = normalize(NORMAL - gradient / max(abs(determinant), 0.00001));
	ALBEDO = max(albedo, vec3(0.0));
	ROUGHNESS = rough;
	SPECULAR = 0.22;
}

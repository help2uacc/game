// Flat unlit shader for merged multi-coloured box meshes (weapons, crates,
// pickups, hazards). Same face tinting as flat_block, colour from vertices.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec4 tint : source_color = vec4(1.0);
uniform float flash = 0.0;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = world_normal;
	float t = 0.84;
	if (n.y > 0.5) {
		t = 1.0;
	} else if (n.y < -0.5) {
		t = 0.70;
	} else if (n.z > 0.5) {
		t = 0.94;
	}
	vec3 base = COLOR.rgb * tint.rgb * t;
	ALBEDO = mix(base, vec3(1.0), flash);
}

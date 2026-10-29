// Transparent variant of flat_block for fades, blinking pickups and blob shadows.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform bool flat_tint = false;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = world_normal;
	float tint = 0.84;
	if (flat_tint || n.y > 0.5) {
		tint = 1.0;
	} else if (n.y < -0.5) {
		tint = 0.70;
	} else if (n.z > 0.5) {
		tint = 0.94;
	}
	ALBEDO = albedo.rgb * tint;
	ALPHA = albedo.a * alpha;
}

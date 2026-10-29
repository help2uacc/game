// Flat unlit block shader (PRD §11.2).
// Fakes simple lighting by tinting each face by its world normal:
// top x1.00, front x0.94, sides x0.84, bottom x0.70.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec4 albedo : source_color = vec4(1.0);

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = world_normal;
	float tint = 0.84;
	if (n.y > 0.5) {
		tint = 1.0;
	} else if (n.y < -0.5) {
		tint = 0.70;
	} else if (n.z > 0.5) {
		tint = 0.94;
	}
	ALBEDO = albedo.rgb * tint;
}

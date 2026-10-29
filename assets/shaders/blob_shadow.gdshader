// Soft round blob shadow (PRD §6.1).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 shadow_color : source_color = vec4(0.227, 0.208, 0.314, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = (1.0 - smoothstep(0.35, 1.0, d)) * strength;
	ALBEDO = shadow_color.rgb;
	ALPHA = a;
}

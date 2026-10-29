// Vertical background gradient for the sky quad (PRD §10.3).
// The quad is parented to the camera far behind the playfield.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 top_color : source_color = vec4(0.862745, 0.921569, 1.0, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 0.941176, 0.960784, 1.0);

void fragment() {
	ALBEDO = mix(top_color.rgb, bottom_color.rgb, UV.y);
}

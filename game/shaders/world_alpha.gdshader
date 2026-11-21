shader_type spatial;
// Półprzezroczyste, nieoświetlone elementy świata (np. słup światła nad dużym złomem),
// wyginane razem z trasą.
render_mode world_vertex_coords, unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://shaders/bend.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.25);

void vertex() {
	VERTEX += bend_offset(VERTEX);
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}

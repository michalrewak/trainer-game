shader_type spatial;
// Tarcza buggy: świecąca krawędź (fresnel), siła = poziom tarczy, błysk po zablokowaniu ataku.
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.35, 0.9, 1.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.5;
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float bands = 0.85 + 0.15 * sin(UV.y * 60.0 + TIME * 3.0);
	ALBEDO = color.rgb * (1.0 + flash * 2.0);
	ALPHA = clamp(fres * bands * (0.15 + 0.55 * strength) + flash * 0.35, 0.0, 1.0);
}

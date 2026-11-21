// Wspólny materiał świata: kolor z palety × tekstura trójplanarna (zdjęcia CC0: piasek,
// skała, asfalt, rdza) z mapą normalnych, opcjonalna tekstura UV (modele Kenney), emisja,
// wydmy na piasku oraz wyginanie trasy (bend.gdshaderinc).

#include "res://shaders/bend.gdshaderinc"

uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D uv_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform sampler2D detail_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 0.25;      // powtórzeń na metr
uniform float detail_strength = 1.0;    // 0 = sam kolor, 1 = pełna tekstura
uniform float detail_gain = 2.0;        // wyrównanie jasności zdjęcia do ~1
uniform float normal_strength = 1.0;
uniform float roughness = 0.9;
uniform float metallic = 0.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float dune_amount = 0.0;        // > 0 tylko dla podłoża

varying vec3 v_pos;
varying vec3 v_nrm;

float dune_height(float x, float d) {
	float side = smoothstep(8.5, 26.0, abs(x));
	float h = 1.6 * sin(d * BEND_TAU / 64.0 + x * 0.09)
		+ 0.9 * sin(d * BEND_TAU / 23.0 - x * 0.17 + 1.3)
		+ 0.5 * sin(d * BEND_TAU / 9.0 + x * 0.31 + 4.0);
	return dune_amount * side * (h + 1.4);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_pos = VERTEX - origin;
	if (dune_amount > 0.0) {
		float d = track_d * bend_on - VERTEX.z;
		float h = dune_height(VERTEX.x, d);
		float hx = dune_height(VERTEX.x + 0.5, d);
		float hd = dune_height(VERTEX.x, d + 0.5);
		VERTEX.y += h;
		NORMAL = normalize(vec3(-(hx - h) / 0.5, 1.0, (hd - h) / 0.5));
		v_pos.y += h;
	}
	v_nrm = NORMAL;
	VERTEX += bend_offset(VERTEX);
}

void fragment() {
	vec3 n = normalize(v_nrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = v_pos * detail_scale;
	vec3 cx = texture(detail_tex, p.zy).rgb;
	vec3 cy = texture(detail_tex, p.xz).rgb;
	vec3 cz = texture(detail_tex, p.xy).rgb;
	vec3 det = cx * w.x + cy * w.y + cz * w.z;
	vec3 base = tint.rgb * texture(uv_tex, UV).rgb;
	ALBEDO = base * mix(vec3(1.0), det * detail_gain, detail_strength);

	// Trójplanarna mapa normalnych (mieszanie „whiteout”).
	vec3 tx = texture(detail_nor, p.zy).xyz * 2.0 - 1.0;
	vec3 ty = texture(detail_nor, p.xz).xyz * 2.0 - 1.0;
	vec3 tz = texture(detail_nor, p.xy).xyz * 2.0 - 1.0;
	tx.xy *= normal_strength;
	ty.xy *= normal_strength;
	tz.xy *= normal_strength;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	vec3 wn = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(mix(n, wn, step(0.001, normal_strength)), 0.0)).xyz);

	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emission.rgb * emission_energy;
}

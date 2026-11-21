// Wyginanie świata: zakręty i wzniesienia trasy liczone w shaderze wierzchołków.
// Logika gry zostaje „prosta” (pas + dystans), a obraz dostaje prawdziwą krzywiznę:
// wierzchołek odległy o `ahead` metrów przed pojazdem przesuwa się o różnicę położenia
// osi trasy między dystansem pojazdu a swoim. Parametry muszą zgadzać się z CourseProfile.

global uniform float track_d;      // dystans pojazdu wzdłuż trasy [m]
global uniform float bend_on;      // 0 = menu/garaż (bez wyginania), 1 = wyprawa
global uniform vec3 hill_phase;    // fazy trzech fal wzniesień
global uniform vec2 curve_phase;   // fazy dwóch fal zakrętów
global uniform float hill_amp;     // skala wzniesień (teren)
global uniform float curve_amp;    // skala zakrętów (teren)
global uniform float climb_slope;  // dodatkowe nachylenie (podjazd z wyzwania), już wizualne

const float BEND_TAU = 6.28318530718;
// Wzniesienia są wizualnie przesadzone – 6% wyglądałoby na ekranie jak płaska droga.
const float HILL_EXAG = 2.5;

float bend_height(float d) {
	float b = smoothstep(400.0, 700.0, d);
	float h = 0.030 * 1700.0 * cos(d / 1700.0 * BEND_TAU + hill_phase.x)
		+ 0.020 * 650.0 * cos(d / 650.0 * BEND_TAU + hill_phase.y)
		+ 0.010 * 260.0 * cos(d / 260.0 * BEND_TAU + hill_phase.z);
	return -b * hill_amp * HILL_EXAG * h / BEND_TAU;
}

float bend_lateral(float d) {
	float b = smoothstep(250.0, 550.0, d);
	return b * curve_amp * (30.0 * sin(d / 700.0 * BEND_TAU + curve_phase.x)
		+ 6.0 * sin(d / 290.0 * BEND_TAU + curve_phase.y));
}

// Przesunięcie wierzchołka w przestrzeni świata (pojazd stoi w z = 0, jedzie w stronę -Z).
vec3 bend_offset(vec3 world) {
	float ahead = -world.z;
	float d = track_d + ahead;
	float x0 = bend_lateral(track_d);
	float heading = (bend_lateral(track_d + 0.5) - bend_lateral(track_d - 0.5));
	float ox = bend_lateral(d) - x0 - heading * ahead;
	float oy = bend_height(d) - bend_height(track_d) + climb_slope * ahead;
	return vec3(ox, oy, 0.0) * bend_on;
}

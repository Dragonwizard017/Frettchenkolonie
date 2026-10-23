shader_type spatial;
render_mode cull_disabled;
// Terrain-Shader (v15.4): Textur-Look wie vorher, plus
//  - Jahreszeiten: Vegetations-Tönung (Frühling/Sommer/Herbst/Winter) und SCHNEE
//    auf nach oben zeigenden Flächen (blockig, passend zum Pixel-Look)
//  - Realismus-Modus (optional): Makro-Variation gegen Textur-Wiederholung und
//    wandernde Wolkenschatten
// Alle Werte kommen als GLOBALE Shader-Parameter (siehe GraphicsSettings.gd).

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform float veg = 1.0;            // 1 = Gras/Wald, 0 = Fels/Strand (wie stark die Saison-Tönung wirkt)
uniform float is_side = 0.0;        // 1 = Klippen-Seitenfläche
uniform float base_roughness = 0.9;

global uniform float season_snow;        // 0..1 Schneedecke
global uniform vec3 season_grass_tint;   // Multiplikator für Vegetation
global uniform float realism_enabled;    // 0/1
global uniform float realism_cloud_shadow; // 0..1
// v16.6 Erkundung: unaufgedeckte Kacheln werden verworfen (siehe ExploreSystem.gd)
global uniform float explore_enabled;    // 0/1
global uniform sampler2D explore_mask : filter_nearest;   // R8, 1 Texel je Kachel
global uniform vec2 explore_world;       // Weltausdehnung in Welteinheiten (w*TILE, h*TILE)

varying vec3 wpos;
varying vec3 wnorm;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.02 + vec2(11.7, 5.3); a *= 0.5; }
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (explore_enabled > 0.5) {
		// Punkt leicht INS Innere der Fläche schieben, damit Seitenflächen zur Kachel gehören, zu der sie zählen
		vec3 pm = wpos - wnorm * 0.05;
		vec2 uvm = pm.xz / explore_world;
		float m = (uvm.x < 0.0 || uvm.y < 0.0 || uvm.x > 1.0 || uvm.y > 1.0) ? 0.0 : texture(explore_mask, uvm).r;
		if (m < 0.5) discard;
	}
	vec3 col = texture(albedo_tex, UV).rgb * COLOR.rgb;

	// Saison-Tönung (nur Vegetation)
	col = mix(col, col * season_grass_tint, veg);

	// Realismus: sanfte Makro-Variation, damit sich die Kachel-Textur weniger wiederholt
	if (realism_enabled > 0.5) {
		float m = fbm(wpos.xz * 0.35);
		col *= mix(0.90, 1.10, m);
	}

	// Schnee: nur auf nach oben zeigenden Flächen, blockig (8 Stufen pro Kachel), ungleichmäßig
	float up = smoothstep(0.55, 0.9, wnorm.y);
	vec2 q = floor(wpos.xz * 8.0) / 8.0;
	float n = fbm(q * 0.55);
	float cover = smoothstep(0.30, 0.62, season_snow * 1.25 + (n - 0.5) * 0.9);
	float snow = cover * up * (1.0 - is_side);
	vec3 snow_col = mix(vec3(0.90, 0.93, 0.98), vec3(1.0), hash21(q * 3.1) * 0.6);
	col = mix(col, snow_col, snow);

	// Wolkenschatten (Realismus)
	if (realism_enabled > 0.5 && realism_cloud_shadow > 0.01) {
		float cs = fbm(wpos.xz * 0.04 + vec2(TIME * 0.35, TIME * 0.12));
		float shade = mix(1.0, 0.52 + 0.48 * smoothstep(0.38, 0.62, cs), realism_cloud_shadow);
		col *= shade;
	}

	ALBEDO = col;
	ROUGHNESS = mix(base_roughness, 0.55, snow);
	SPECULAR = mix(0.25, 0.6, snow);
}

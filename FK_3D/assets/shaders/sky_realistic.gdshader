shader_type sky;
// Realistischer Himmel (v15.4, Realismus-Modus): Tag/Nacht-Verlauf, Sonnenscheibe
// mit Korona, Auf-/Untergangsglühen, Wolken mit Selbstschattierung und Silberrand,
// Sterne. Die Sonnenrichtung kommt vom DirectionalLight "Sun" (LIGHT0_DIRECTION).

uniform vec3 top_day : source_color = vec3(0.13, 0.36, 0.84);
uniform vec3 hor_day : source_color = vec3(0.60, 0.77, 0.96);
uniform vec3 top_night : source_color = vec3(0.012, 0.02, 0.06);
uniform vec3 hor_night : source_color = vec3(0.04, 0.06, 0.13);
uniform vec3 glow_col : source_color = vec3(1.0, 0.50, 0.22);
uniform vec3 tint : source_color = vec3(1.0);
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float sun_elev : hint_range(-1.0, 1.0) = 0.6;   // sin(visuelle Sonnenhöhe)
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;
uniform vec2 cloud_offset = vec2(0.0);

float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(17.1, 3.7); a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 sundir = LIGHT0_DIRECTION;
	float day = 1.0 - night;

	float h = pow(clamp(1.0 - abs(y), 0.0, 1.0), 3.0);          // 1 am Horizont
	vec3 col = mix(mix(top_night, top_day, day), mix(hor_night, hor_day, day), h) * tint;

	float sdot = max(dot(d, sundir), 0.0);
	float low = smoothstep(0.55, 0.0, sun_elev) * day;            // stark bei niedriger Sonne
	// Glühen um die Sonne: zur warmen Farbe ÜBERBLENDEN statt addieren
	// (orange auf blau addiert ergibt einen magentafarbenen Hof)
	// Nahe der Sonne wird der Himmel zuerst zu neutral/warm ENTSÄTTIGT (wie in der Natur),
	// sonst läuft der Verlauf Blau -> Orange durch Violett/Pink.
	float near_sun = clamp(pow(sdot, 3.0) * (0.35 + low) + pow(sdot, 14.0) * 0.6, 0.0, 1.0);
	vec3 lum = vec3(dot(col, vec3(0.299, 0.587, 0.114)));
	col = mix(col, lum * vec3(1.20, 1.06, 0.88), near_sun * 0.9);
	vec3 warm = mix(glow_col, vec3(1.0, 0.86, 0.60), clamp(pow(sdot, 40.0) * 1.4, 0.0, 1.0));
	float glow_w = clamp(low * (pow(sdot, 4.0) * 0.55 + pow(sdot, 30.0) * 0.55) * smoothstep(-0.2, 0.25, y), 0.0, 0.92);
	col = mix(col, warm, glow_w);
	col = mix(col, col * vec3(1.14, 0.86, 0.72), low * h);

	if (y < 0.0) {
		vec3 hor = mix(hor_night, hor_day, day) * tint;
		col = mix(hor, hor * vec3(0.55, 0.62, 0.55), smoothstep(0.0, -0.35, y));
	}

	float disc = smoothstep(0.99965, 0.99990, dot(d, sundir));
	col += vec3(1.0, 0.94, 0.80) * disc * 7.0 * day * step(0.0, y);
	col += vec3(1.0, 0.90, 0.75) * pow(sdot, 220.0) * 1.6 * day;

	if (y > 0.0) {
		vec2 uv = d.xz / (y + 0.20) * 0.55 + cloud_offset;
		float n = fbm(uv * 1.4);
		float dens = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.26, n);
		float n2 = fbm(uv * 1.4 + sundir.xz * 0.14);                 // zur Sonne versetzt -> Eigenschatten
		float lit = clamp(0.58 + (n - n2) * 3.4, 0.0, 1.0);
		vec3 c_lit = mix(vec3(1.0), vec3(1.0, 0.78, 0.60), low) * day + vec3(0.08, 0.10, 0.17) * night;
		vec3 c_dark = mix(vec3(0.58, 0.64, 0.77), vec3(0.64, 0.46, 0.46), low) * day + vec3(0.03, 0.04, 0.08) * night;
		vec3 ccol = mix(c_dark, c_lit, lit) * mix(vec3(1.0), tint, 0.6);
		ccol = mix(ccol, warm, clamp(low * pow(sdot, 7.0) * 0.8, 0.0, 0.85));   // warmer Silberrand
		col = mix(col, ccol, dens * smoothstep(0.0, 0.18, y));
	}

	if (y > 0.0 && night > 0.35) {
		vec2 sp = d.xz / (y + 0.3) * 70.0;
		float st = step(0.9968, hash(floor(sp)));
		col += vec3(st) * smoothstep(0.35, 0.8, night) * smoothstep(0.08, 0.35, y);
	}
	COLOR = col;
}

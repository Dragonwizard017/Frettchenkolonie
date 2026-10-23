shader_type canvas_item;
// Rotierendes 360°-Panorama (wie im Minecraft-Hauptmenü), ohne 3D-Kamera:
// pro Pixel wird ein Sichtstrahl gebildet, um yaw/pitch gedreht und im
// Equirect-Streifen nachgeschlagen. Mapping identisch zu stitch.py:
//   lon = atan2(d.x, -d.z), lat = asin(d.y), nur |lat| <= lat_max im Bild.
uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform float yaw = 0.0;
uniform float pitch = 0.10;
uniform float fov_y = 1.05;
uniform float aspect = 1.7778;
uniform float lat_max = 0.7853982;
uniform float vignette : hint_range(0.0, 1.0) = 0.28;
uniform float dim : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float t = tan(fov_y * 0.5);
	vec3 d = normalize(vec3(p.x * t * aspect, -p.y * t, -1.0));
	float cp = cos(pitch), sp = sin(pitch);
	d = vec3(d.x, d.y * cp - d.z * sp, d.y * sp + d.z * cp);
	float cy = cos(yaw), sy = sin(yaw);
	d = vec3(d.x * cy + d.z * sy, d.y, -d.x * sy + d.z * cy);
	float lon = atan(d.x, -d.z);
	float lat = asin(clamp(d.y, -1.0, 1.0));
	vec2 uv = vec2(lon / TAU + 0.5, 0.5 - lat / (2.0 * lat_max));
	vec3 col = textureLod(pano, uv, 0.0).rgb * tint.rgb;
	// weiche Vignette + optionales Abdunkeln für Lesbarkeit
	float v = smoothstep(1.35, 0.35, length(p * vec2(0.85, 1.0)));
	col *= mix(1.0, v, vignette);
	col = mix(col, col * vec3(0.55, 0.5, 0.48), dim);
	// (v15.5: keine Nachbearbeitung mehr - das Panorama ist bereits mit Tonemapping/Farbkorrektur gerendert)
	COLOR = vec4(col, 1.0);
}

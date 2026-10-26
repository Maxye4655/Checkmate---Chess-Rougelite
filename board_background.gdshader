shader_type canvas_item;

// Same palette as before: the board sits on a dark vertical gradient.
uniform vec4 color_top : source_color = vec4(0.129, 0.180, 0.208, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.070, 0.100, 0.120, 1.0);
// Faint tint borrowed from the menu's primary colour.
uniform vec4 accent_color : source_color = vec4(0.392, 0.541, 0.616, 1.0);

uniform float aspect = 1.7778;  // width / height of the rect it covers
uniform float pixel_size : hint_range(32.0, 512.0) = 220.0;  // match the menu for a consistent look

uniform float pattern_strength : hint_range(0.0, 1.0) = 0.35;  // how visible the swirl is
uniform float accent_strength : hint_range(0.0, 0.3) = 0.05;   // how much menu-blue bleeds in
uniform float pattern_scale : hint_range(4.0, 30.0) = 12.0;    // lower = broader, calmer shapes
uniform float wave_speed : hint_range(0.0, 2.0) = 0.25;        // liquid motion
uniform float swirl_speed : hint_range(0.0, 1.0) = 0.15;       // whole-image rotation
uniform float swirl_strength : hint_range(0.0, 10.0) = 3.0;
uniform float noise_strength : hint_range(0.0, 0.2) = 0.02;

uniform float scanline_opacity : hint_range(0.0, 0.5) = 0.12;
uniform float vignette_intensity : hint_range(0.0, 3.0) = 1.1;

float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Same warp as the menu, just slower and wider.
float paint_field(vec2 p) {
	float len = length(p);
	float angle = atan(p.y, p.x)
		+ TIME * swirl_speed * 0.2
		- swirl_strength * 2.0 * (0.25 * len + 0.75);
	vec2 q = vec2(cos(angle), sin(angle)) * len * pattern_scale;

	float t = TIME * wave_speed;
	vec2 q2 = vec2(q.x + q.y);
	for (int i = 0; i < 5; i++) {
		q2 += sin(max(q.x, q.y)) + q;
		q += 0.5 * vec2(cos(5.1123314 + 0.353 * q2.y + t * 0.131121), sin(q2.x - 0.113 * t));
		q -= cos(q.x + q.y) - sin(q.x * 0.711 - q.y);
	}
	return length(q) * 0.035;
}

void fragment() {
	vec2 res = vec2(pixel_size, pixel_size / aspect);
	vec2 puv = floor(UV * res) / res;
	vec2 p = (puv - 0.5) * vec2(aspect, 1.0) / length(vec2(aspect, 1.0));

	// Soft two-band pattern (low contrast), 0..1.
	float c_mod = 1.5;
	float paint = min(2.0, max(0.0, paint_field(p) * c_mod));
	float band1 = max(0.0, 1.0 - c_mod * abs(1.0 - paint));
	float band2 = max(0.0, 1.0 - c_mod * abs(paint));
	float pattern = clamp(band1 + band2, 0.0, 1.0);

	// Base gradient, then a gentle lift where the pattern is.
	vec3 base = mix(color_top.rgb, color_bottom.rgb, UV.y);
	vec3 col = mix(base, color_top.rgb, pattern * pattern_strength);
	col += accent_color.rgb * pattern * accent_strength;

	// Fine grain.
	col += (random(puv * 97.0) - 0.5) * noise_strength;

	// Scanlines and vignette, as in the original.
	float scan = sin(UV.y * 700.0) * 0.5 + 0.5;
	col = mix(col, col * (1.0 - scan), scanline_opacity);

	float dist = distance(UV, vec2(0.5));
	col *= clamp(1.0 - pow(dist, 2.0) * vignette_intensity, 0.0, 1.0);

	COLOR = vec4(col, 1.0);
}
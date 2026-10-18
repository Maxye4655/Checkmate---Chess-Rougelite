shader_type canvas_item;

uniform vec4 primary_color : source_color = vec4(0.392, 0.541, 0.616, 1.0);
uniform vec4 background_color : source_color = vec4(0.129, 0.180, 0.208, 1.0);
uniform vec4 accent_color : source_color = vec4(0.588, 0.635, 0.659, 0.25);

uniform float pixel_size : hint_range(32.0, 512.0) = 100.0;
uniform float chrome_aberration : hint_range(0.0, 0.1) = 0.02;
uniform float noise_strength : hint_range(0.0, 0.5) = 0.06;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.4;
uniform float vignette_intensity : hint_range(0.0, 5.0) = 1.4;
uniform float wave_speed : hint_range(0.1, 10.0) = 1.4;
uniform float swirl_strength : hint_range(0.0, 10.0) = 4.5;
uniform float swirl_speed : hint_range(0.0, 5.0) = 1.0;

float random(vec2 uv) {
	return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

float layered_noise(vec2 uv) {
	vec2 p = uv * 6.0;
	float amplitude = 0.5;
	float n = 0.0;
	for(int i = 0; i < 4; i++) {
		p.x += sin(TIME * wave_speed * 0.3 + p.y * 0.5) *0.2;
		p.y += cos(TIME * wave_speed * 0.3 + p.x * 0.5) * 0.2;

		n += amplitude * random(p);
		p += vec2(3.141, 7.821);
		amplitude *= 0.5;
	}
	return n;
}

void fragment() {
	vec2 raw_uv = UV;
	vec2 uv = floor(raw_uv * pixel_size) / pixel_size;

	vec2 centered = uv - vec2(0.5);
	float dist = length(centered);
	float swirl_falloff = 1.0 - smoothstep(0.0, 0.85, dist);
	float swirl_angle = (swirl_strength + TIME * swirl_speed) * swirl_falloff;

	swirl_angle += sin(dist * 10.0 - TIME * swirl_speed);

	float sa = sin(swirl_angle);
	float ca = cos(swirl_angle);
	vec2 swuv = vec2(centered.x * ca - centered.y * sa, centered.x * sa + centered.y * ca) + vec2(0.5);

	swuv = floor(swuv * pixel_size) / pixel_size;

	float base_alpha = clamp(1.0 - dist * 1.5, 0.0, 1.0);
	vec3 col = mix(background_color.rgb, primary_color.rgb, base_alpha);

	float n = layered_noise(swuv);
	col += n * noise_strength;

	vec3 chrome_col;
	float split_dist = (dist * 1.2) * chrome_aberration;
	float time_wobble = sin(TIME * wave_speed * 0.5) * 0.008;
	float offset_mod = split_dist + time_wobble;

	vec2 red_uv = floor((swuv - offset_mod) * pixel_size) / pixel_size;
	vec2 blue_uv = floor((swuv + offset_mod) * pixel_size) / pixel_size;

	chrome_col.r = mix(col, primary_color.rgb * layered_noise(red_uv), 0.5).r;
	chrome_col.g = col.g;
	chrome_col.b = mix(col, primary_color.rgb * layered_noise(blue_uv), 0.5).b;

	float scanline = sin((raw_uv.y + (TIME * 0.05)) * pixel_size * 3.1415);
	scanline = (scanline + 1.0) * 0.5;
	chrome_col = mix(chrome_col, chrome_col * (1.0 - scanline), scanline_strength * (dist + 0.1));

	vec3 final_col = chrome_col;

	float glow_ring = sin(dist * 14.0 - TIME * wave_speed * 0.3) * 0.5 + 0.5;
	final_col += accent_color.rgb * accent_color.a * glow_ring * (1.0 - dist);

	final_col *= vec3(clamp(1.0 - pow(dist, 2.0) * vignette_intensity, 0.0, 1.0));

	COLOR = vec4(final_col, 1.0);
	}
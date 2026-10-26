shader_type canvas_item;

uniform vec4 primary_color : source_color = vec4(0.392, 0.541, 0.616, 1.0);
uniform vec4 background_color : source_color = vec4(0.129, 0.180, 0.208, 1.0);
uniform vec4 accent_color : source_color = vec4(0.588, 0.635, 0.659, 0.25);

uniform float aspect = 1.7778;  // width / height of the rect it covers
uniform float pixel_size : hint_range(32.0, 512.0) = 200.0; // pixels across the screen
uniform float chrome_aberration : hint_range(0.0, 0.1) = 0.02;
uniform float noise_strength : hint_range(0.0, 0.5) = 0.06;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.4;
uniform float vignette_intensity : hint_range(0.0, 5.0) = 1.4;
uniform float wave_speed : hint_range(0.1, 10.0) = 1.4;     // speed of the liquid warping
uniform float swirl_strength : hint_range(0.0, 10.0) = 5.0; // how hard the centre is twisted
uniform float swirl_speed : hint_range(0.0, 5.0) = 1.0;     // whole-image rotation speed
uniform float spin_amount : hint_range(0.0, 1.0) = 0.25;    // 0 = flat rotation, 1 = twist grows with distance
uniform float contrast : hint_range(0.5, 6.0) = 3.5;        // sharpness of the colour bands
uniform float lighting : hint_range(0.0, 1.0) = 0.4;        // bright highlights on band edges

float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

float paint_field(vec2 p) {
	float len = length(p);
	float angle = atan(p.y, p.x)
		+ TIME * swirl_speed * 0.2
		- swirl_strength * 2.0 * (spin_amount * len + (1.0 - spin_amount));
	vec2 q = vec2(cos(angle), sin(angle)) * len * 30.0;
	
	float t = TIME * wave_speed * 3.0;
	vec2 q2 = vec2(q.x + q.y);
	for (int i = 0; i < 5; i++) {
		q2 += sin(max(q.x, q.y)) + q;
		q += 0.5 * vec2(cos(5.1123314 + 0.353 * q2.y + t * 0.131121), sin(q2.x - 0.113 * t));
		q -= cos(q.x + q.y) - sin(q.x * 0.711 - q.y);
	}
	return length(q) * 0.035;
}

vec3 shade(float field) {
	float c_mod = 0.25 * contrast + 0.5 * spin_amount + 1.2;
	float paint = min(2.0, max(0.0, field * c_mod));
	float c1 = max(0.0, 1.0 - c_mod * abs(1.0 - paint));
	float c2 = max(0.0, 1.0 - c_mod * abs(paint));
	float c3 = 1.0 - min(1.0, c1 + c2);
	
	float light = (lighting - 0.2) * max(c1 * 5.0 - 4.0, 0.0) + lighting * max(c2 * 5.0 - 4.0, 0.0);
	float k = 0.3 / contrast;
	return k * primary_color.rgb
		+ (1.0 - k) * (primary_color.rgb * c1 + accent_color.rgb * c2 + background_color.rgb * c3)
		+ light;
}

void fragment() {
	vec2 res = vec2(pixel_size, pixel_size / aspect);
	vec2 puv = floor(UV * res) / res;
	
	vec2 p = (puv - 0.5) * vec2(aspect, 1.0) / length(vec2(aspect, 1.0));
	float dist = length(UV - 0.5);
	
	float ab = chrome_aberration * (0.5 + dist);
	float field_r = paint_field(p * (1.0 + ab));
	float field_g = paint_field(p);
	float field_b = paint_field(p * (1.0 - ab));
	
	vec3 col = vec3(shade(field_r).r, shade(field_g).g, shade(field_b).b);
	
	float grain = random(puv * 97.0 + floor(TIME * 8.0)) - 0.5;
	col += grain * noise_strength;
	
	float scan = (sin((UV.y + TIME * 0.05) * pixel_size * 3.1415) + 1.0) * 0.5;
	col = mix(col, col * (1.0 - scan), scanline_strength * (dist + 0.1));
	
	col *= clamp(1.0 - pow(dist, 2.0) * vignette_intensity, 0.0, 1.0);
	
	COLOR = vec4(col, 1.0);
}

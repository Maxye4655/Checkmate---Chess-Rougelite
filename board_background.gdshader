shader_type canvas_item;

uniform vec4 color_top : source_color = vec4(0.129, 0.180, 0.208, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.070, 0.100, 0.120, 1.0);

uniform float scanline_opacity : hint_range(0.0, 0.5) = 0.12;
uniform float vignette_intensity : hint_range(0.0, 3.0) = 1.1;

void fragment() {
	vec2 uv = UV;

	vec3 col = mix(color_top.rgb, color_bottom.rgb, uv.y);

	float scanline = sin(uv.y * 700.0) * 0.5 + 0.5;
	col = mix(col, col * (1.0 - scanline), scanline_opacity);

	float dist = distance(uv, vec2(0.5, 0.5));
	col *= clamp(1.0 - pow(dist, 2.0) * vignette_intensity, 0.0, 1.0);

	COLOR = vec4(col, 1.0);
}

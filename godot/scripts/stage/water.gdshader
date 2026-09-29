// 흙탕물 강 (A 소유) — 600m BROKEN BRIDGE 구간
shader_type spatial;
render_mode cull_back;

uniform vec3 water_color : source_color = vec3(0.16, 0.14, 0.11);
uniform vec3 deep_color : source_color = vec3(0.06, 0.06, 0.06);

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 flow = world_pos.xz * 0.35 + vec2(TIME * 0.35, 0.0);   // 강은 옆(x)으로 흐른다
	float a = noise(flow);
	float b = noise(flow * 2.3 + 7.0);
	NORMAL_MAP = normalize(vec3(a - 0.5, b - 0.5, 2.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	ALBEDO = mix(deep_color, water_color, a * 0.6 + 0.2);
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
}

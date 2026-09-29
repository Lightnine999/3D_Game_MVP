// 바닥: 가운데 흙길 + 양옆 풀밭 흙 (A 소유)
// 월드 좌표로 무늬를 만들어 1,000m 전체가 이음매 없이 이어진다.
shader_type spatial;
render_mode cull_back;

uniform float road_half = 1.8;
uniform vec3 dirt_color : source_color = vec3(0.36, 0.28, 0.20);
uniform vec3 track_color : source_color = vec3(0.22, 0.17, 0.12);
uniform vec3 field_color : source_color = vec3(0.09, 0.075, 0.055);

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
	float n = noise(world_pos.xz * 0.35) * 0.6 + noise(world_pos.xz * 2.3) * 0.4;
	float edge = road_half + (noise(vec2(world_pos.z * 0.2, 3.0)) - 0.5) * 0.8;   // 흙길 가장자리를 삐뚤게
	float road = 1.0 - smoothstep(edge - 0.4, edge + 0.6, abs(world_pos.x));
	// 바퀴 자국 두 줄
	float ruts = smoothstep(0.35, 0.0, abs(abs(world_pos.x) - 0.75)) * road;
	vec3 col = mix(field_color, dirt_color, road);
	col = mix(col, track_color, ruts * 0.7);
	col *= 0.8 + n * 0.4;
	ALBEDO = col;
	ROUGHNESS = 1.0;
}

// 바닥 v2: 진흙 흙길 + 물웅덩이 + 바퀴 자국 + 어두운 풀밭 흙 (A 소유)
// 월드 좌표로 무늬를 만들어 1,000m 전체가 이음매 없이 이어진다.
// 강(river_z0 - river_z1)은 바닥을 뚫어서(discard) 아래의 물이 보이게 한다.
shader_type spatial;
render_mode cull_back;

uniform float road_half = 2.2;
uniform float river_z0 = 680.0;   // 강이 시작하는 거리 (양수 m)
uniform float river_z1 = 720.0;
uniform vec3 mud_color : source_color = vec3(0.19, 0.17, 0.15);
uniform vec3 mud_wet : source_color = vec3(0.09, 0.085, 0.08);
uniform vec3 soil_color : source_color = vec3(0.075, 0.075, 0.065);
uniform vec3 moss_color : source_color = vec3(0.09, 0.10, 0.07);

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { return noise(p) * 0.5 + noise(p * 2.1) * 0.25 + noise(p * 4.3) * 0.15 + noise(p * 9.7) * 0.1; }

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = -world_pos.z;
	if (d > river_z0 && d < river_z1) {
		discard;   // 강물이 보이도록 바닥을 뚫는다
	}
	float n = fbm(world_pos.xz * 0.4);
	float fine = fbm(world_pos.xz * 3.5);
	float edge = road_half + (noise(vec2(world_pos.z * 0.15, 5.0)) - 0.5) * 1.4;
	float road = 1.0 - smoothstep(edge - 0.6, edge + 0.9, abs(world_pos.x));
	float ruts = smoothstep(0.32, 0.0, abs(abs(world_pos.x) - 0.8)) * road;
	float puddle = smoothstep(0.62, 0.7, fbm(world_pos.xz * 0.28 + 11.0)) * road;   // 물웅덩이
	vec3 field = mix(soil_color, moss_color, smoothstep(0.35, 0.7, n));
	vec3 col = mix(field, mud_color, road);
	col = mix(col, mud_wet, max(ruts * 0.8, puddle));
	col *= 0.78 + fine * 0.44;
	// 강가(둑) 근처는 젖어서 어둡게
	float bank = 1.0 - smoothstep(0.0, 8.0, min(abs(d - river_z0), abs(d - river_z1)));
	col = mix(col, mud_wet, bank * 0.7);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.55, max(puddle, bank * 0.4));   // 웅덩이는 반짝
	SPECULAR = mix(0.3, 0.45, puddle);
}

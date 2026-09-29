// 바닥 v2: 길 없는 광활한 대지 — 진흙·낙엽·이끼 흙 + 드문드문 물웅덩이 (A 소유)
// 월드 좌표로 무늬를 만들어 1,000m 전체가 이음매 없이 이어진다.
// 강(river_z0 - river_z1)은 바닥을 뚫어서(discard) 아래의 물이 보이게 한다.
shader_type spatial;
render_mode cull_back;

uniform float river_z0 = 680.0;   // 강이 시작하는 거리 (양수 m)
uniform float river_z1 = 720.0;
uniform float bridge_half = 3.8;   // 다리 상판 반폭 (m)
uniform vec3 mud_wet : source_color = vec3(0.09, 0.085, 0.08);
uniform vec3 soil_color : source_color = vec3(0.075, 0.075, 0.065);
uniform vec3 moss_color : source_color = vec3(0.09, 0.10, 0.07);
uniform sampler2D mud_tex : source_color, filter_linear_mipmap, repeat_enable;   // Poly Haven 진흙 (색)
uniform sampler2D mud_nrm : hint_normal, filter_linear_mipmap, repeat_enable;    // 노멀
uniform sampler2D mud_rgh : hint_default_white, filter_linear_mipmap, repeat_enable;   // 거칠기
uniform float mud_scale = 0.35;   // 1m당 반복 횟수

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
	if (d > river_z0 - 10.2 && d <= river_z0 && abs(world_pos.x) < bridge_half) {
		discard;   // 다리 첫 칸 상판 아래: 상판 윗면과 바닥이 같은 높이라 폰에서 번갈아 보이며 깜빡였다
	}
	float n = fbm(world_pos.xz * 0.4);
	float fine = fbm(world_pos.xz * 3.5);
	// 물웅덩이: 큰 노이즈의 봉우리만 골라 대지 곳곳에 드문드문
	float puddle = smoothstep(0.7, 0.76, fbm(world_pos.xz * 0.16 + 11.0));
	vec2 uv = world_pos.xz * mud_scale;
	vec3 photo = texture(mud_tex, uv).rgb;                        // 실사 진흙·낙엽
	float photo_l = dot(photo, vec3(0.333));
	float bare = smoothstep(0.55, 0.8, fbm(world_pos.xz * 0.07 + 3.0));   // 풀이 벗겨진 맨흙 자리
	vec3 field = mix(soil_color, moss_color, smoothstep(0.35, 0.7, n)) * (0.55 + photo_l * 1.6);
	vec3 col = mix(field, photo * 0.8, bare * 0.6);
	col = mix(col, mud_wet, puddle);
	col *= 0.85 + fine * 0.3;
	NORMAL_MAP = mix(texture(mud_nrm, uv).rgb, vec3(0.5, 0.5, 1.0), puddle);   // 웅덩이는 평평하게
	float rough_tex = texture(mud_rgh, uv).r;
	// 강가(둑) 근처는 젖어서 어둡게
	float bank = 1.0 - smoothstep(0.0, 8.0, min(abs(d - river_z0), abs(d - river_z1)));
	col = mix(col, mud_wet, bank * 0.3);   // 0.7 이면 다리 앞 바닥이 그림자처럼 까맣게 보였다
	ALBEDO = col;
	ROUGHNESS = mix(rough_tex, 0.55, max(puddle, bank * 0.4));   // 웅덩이는 반짝
	SPECULAR = mix(0.3, 0.45, puddle);
}

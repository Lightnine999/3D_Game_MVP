// 좀비 달빛 테두리 (2026-09-30 "안 보이다가 갑자기 나타난다"): 어두운 풀·안개에 묻히던 몸 가장자리를
// 차가운 빛으로 살짝 밝혀 멀리서도 형체가 읽히게 한다. 원래 재질 위에 한 번 더 그리는 덧칠(next_pass)
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

uniform vec3 rim_color : source_color = vec3(0.62, 0.68, 0.78);
uniform float strength = 0.8;
uniform float power = 2.6;

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	ALBEDO = rim_color * f * strength;
}

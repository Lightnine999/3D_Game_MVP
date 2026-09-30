// 좀비 달빛 테두리 (2026-09-30 "안 보이다가 갑자기 나타난다"): 어두운 풀·안개에 묻히던 몸 가장자리를
// 차가운 빛으로 살짝 밝혀 멀리서도 형체가 읽히게 한다. 원래 재질 위에 한 번 더 그리는 덧칠(next_pass)
// 2차 (같은 날 "좀비가 회색이 됐다"): 가장자리에만 얇게, 가까울수록 사라진다 → 가까이 오면 원래 텍스처 그대로
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

uniform vec3 rim_color : source_color = vec3(0.62, 0.68, 0.78);
uniform float strength = 0.6;
uniform float power = 4.5;          // 클수록 가장자리에만 (2.6 → 4.5)
uniform float near_off = 4.0;       // 이보다 가까우면 테두리 없음 (m)
uniform float far_full = 15.0;      // 이보다 멀면 테두리 온전히 (m)

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	float d = smoothstep(near_off, far_full, -VERTEX.z);    // 카메라까지 거리
	ALBEDO = rim_color * f * strength * d;
}

// 먼 산 배경막 — 카메라를 따라다니는 원통 벽에 파노라마 그림을 붙인다 (A 소유)
// 비유: 연극 무대 뒤의 배경 그림 막. 하늘에 깔면 산이 지평선에 붙어 풀·안개에 가려지지만,
// 원통 벽에 세우면 산 능선이 지평선보다 6-12° 위로 올라와 늘 보인다. (FOREST TOUR 방식)
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 fog_color : source_color = vec3(0.23, 0.28, 0.32);
uniform float bottom_fog = 0.35;       // 그림 아래쪽(안개 깔린 부분)을 게임 안개색에 녹이는 정도

void fragment() {
	float u = UV.x <= 0.5 ? UV.x * 2.0 : 2.0 - UV.x * 2.0;   // 앞 180° = 원본, 뒤 180° = 좌우 반전
	vec3 c = texture(panorama, vec2(u, UV.y)).rgb;
	float low = smoothstep(0.62, 1.0, UV.y);                  // 그림 밑단은 게임 안개와 이어지게
	ALBEDO = mix(c, fog_color, low * bottom_fog + low * low * 0.5);
}

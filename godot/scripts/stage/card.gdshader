// 그림 카드 (폐차·나무) — Y축 빌보드 + 색 누르기 (A 소유)
// 비유: 사진 카드를 늘 카메라 쪽으로 돌리면서, 채도를 빼고 차가운 필터를 씌워 안개 낀 풍경에 녹아들게 한다.
// 톤 기준: FOREST TOUR 미리보기(forest_tour_v3)에서 사용자가 고른 분위기
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform float saturation = 0.6;                       // 원래 채도의 60% (35%일 때 너무 단조로웠다)
uniform float contrast = 0.9;
uniform vec3 tint : source_color = vec3(0.92, 0.94, 1.0);    // 살짝 차가운 필터
instance uniform vec3 variation = vec3(1.0);             // 카드마다 다른 색조 (단조로움 방지)
uniform float fade_begin = 88.0;                     // 여기서부터 점점 흩어져서 (Distance Fade · Pixel Dither)
uniform float fade_end = 105.0;                       // 여기서 사라진다 (visibility_range_end 와 같게)

void vertex() {
	// Y축 빌보드 (StandardMaterial3D 의 BILLBOARD_FIXED_Y 와 같은 식, 좌우 뒤집기는 부호로 유지)
	float sx = length(MODEL_MATRIX[0].xyz) * sign(MODEL_MATRIX[0].x + 1e-5);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(sx, 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	float gray = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(vec3(gray), tex.rgb, saturation);
	col = mix(vec3(0.22), col, contrast);
	ALBEDO = col * tint * variation;
	// 먼 카드는 반투명 계산 없이 픽셀에 구멍을 뚫어(디더) 서서히 사라지게 → 120m에서 뚝 사라지지 않는다
	float fade = 1.0 - smoothstep(fade_begin, fade_end, length(VERTEX));
	float bayer = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	ALPHA = tex.a * step(bayer, fade);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}

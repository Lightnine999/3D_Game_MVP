// 나무 사이에 떠 있는 안개 판 — Y축 빌보드 + 천천히 흐름 + 가까이·멀리서 사라짐 (A 소유)
// 비유: 무대 연기 사진을 붙인 반투명 판. 달리는 사람이 가까이 오면 스르르 사라져서 화면을 덮지 않는다.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D mist_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 mist_color : source_color = vec3(0.30, 0.35, 0.40);
uniform float opacity = 0.6;
uniform float near_fade_begin = 7.0;    // 이보다 가까우면 안 보임
uniform float near_fade_end = 20.0;     // 여기부터 다 보임
uniform float far_fade_begin = 70.0;    // 여기부터 흐려져서
uniform float far_fade_end = 95.0;      // 여기서 사라짐 (visibility_range 와 맞춘다)
uniform float drift = 0.012;            // 흐르는 속도 (UV/초)
varying float seed;

void vertex() {
	seed = fract(MODEL_MATRIX[3].x * 0.137 + MODEL_MATRIX[3].z * 0.071);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float dist = length(VERTEX);                              // 카메라까지 거리 (뷰 공간)
	vec2 uv = vec2(UV.x * 0.5 + TIME * drift + seed, UV.y);   // 판마다 다른 구간을 천천히 흘린다
	float a = texture(mist_tex, uv).a * smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);   // 흘러도 판 양끝은 흐리게
	a *= smoothstep(near_fade_begin, near_fade_end, dist) * (1.0 - smoothstep(far_fade_begin, far_fade_end, dist));
	ALBEDO = mist_color;
	ALPHA = clamp(a * opacity, 0.0, 1.0);
}

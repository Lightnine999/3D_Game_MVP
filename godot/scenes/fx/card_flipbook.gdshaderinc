// 카드 시퀀스 공통 (card_flipbook_add / card_flipbook_mix): 그림 한 장(스프라이트 시트)의 칸을 차례로 넘긴다
// 입자를 실제로 뿌리지 않으니 가볍다 (폰). 두 칸 사이를 부드럽게 섞어서 16칸으로도 뚝뚝 끊기지 않는다
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float cols = 4.0;
uniform float rows = 4.0;
uniform float frames = 16.0;
uniform float fps = 16.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform bool y_billboard = false;              // 연기 기둥: 세로는 세운 채 옆으로만 카메라를 본다
instance uniform float phase = 0.0;            // 카드마다 시작 칸을 어긋나게 (같은 박자로 깜빡이지 않게)
instance uniform float frame_override = -1.0;  // 0 이상이면 그 칸 (한 번만 재생하는 피 튐은 스크립트가 칸을 넘긴다)
instance uniform float fade = 1.0;             // 스크립트가 서서히 지울 때
instance uniform float spin = 0.0;             // 카드 안에서 그림을 돌리는 각도 (라디안) — 총구 불꽃이 매번 다른 모양으로

void vertex() {
	if (y_billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0), vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), MODEL_MATRIX[3]);
	} else {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

vec4 cell(float f, vec2 uv) {
	if (spin != 0.0) {                         // 가운데를 축으로 돌린다 (칸 밖으로 나간 곳은 비운다)
		vec2 d = uv - 0.5;
		float cs = cos(spin), sn = sin(spin);
		uv = vec2(cs * d.x - sn * d.y, sn * d.x + cs * d.y) + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return vec4(0.0);
	}
	vec2 c = vec2(mod(f, cols), floor(f / cols));
	return texture(atlas, (uv + c) / vec2(cols, rows));
}

vec4 flipbook(vec2 uv) {
	float t = frame_override >= 0.0 ? frame_override : mod(TIME * fps + phase * frames, frames);
	float f0 = floor(t);
	float f1 = frame_override >= 0.0 ? min(f0 + 1.0, frames - 1.0) : mod(f0 + 1.0, frames);
	return mix(cell(f0, uv), cell(f1, uv), fract(t));
}

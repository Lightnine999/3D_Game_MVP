// 빛나는 카드 시퀀스 (신호탄 불꽃): 더하기로 섞어 밝게, 안개에 묻히지 않게 (멀리서도 보인다)
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
#include "res://scenes/fx/card_flipbook.gdshaderinc"

void fragment() {
	vec4 c = flipbook(UV);
	ALBEDO = c.rgb * tint.rgb * energy * c.a * fade;
}

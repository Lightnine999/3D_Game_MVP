// 보통 카드 시퀀스 (연기·피): 투명도로 섞는다. 안개는 받는다 (멀리 있는 것은 흐리게)
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
#include "res://scenes/fx/card_flipbook.gdshaderinc"

void fragment() {
	vec4 c = flipbook(UV);
	ALBEDO = c.rgb * tint.rgb * energy;
	ALPHA = c.a * tint.a * fade;
}

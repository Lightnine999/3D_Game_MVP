# 그림 카드 소품 (폐차·나무) — 주인: A
#
# 비유: 사진을 오려 붙인 판자를 세워 두되, 판자가 늘 달리는 사람 쪽으로 몸을 돌린다(Y축 빌보드).
# 그래서 옆을 지나가도 얇은 선으로 보이지 않고, 노멀맵 덕분에 노을빛에 굴곡 음영이 생긴다.
#
# 질감: assets/textures/cards/<이름>.png (+ _n.png 노멀맵) — tools/assets/prepare_card_textures.py
# ⚠️ 가까이 가면 평면 느낌이 날 수 있다 → 테스트 후 근거리용은 3D 에셋으로 교체 예정 (원거리용으로만 사용)
class_name CardProps
extends RefCounted

const TEX := "res://assets/textures/cards/"
const SHADER := preload("res://scripts/stage/card.gdshader")

# 이름 → [크기(m), 기준] — "w" = 그림 폭(차 길이 방향), "h" = 그림 높이(나무 키)
const CARDS := {
	"card_excavator": [9.0, "w"], "card_semi_truck": [7.5, "w"], "card_jeep_wreck": [4.2, "w"],
	"card_van_front": [4.9, "w"], "card_van_rear": [4.9, "w"], "card_roadster": [4.2, "w"],
	"card_sedan_green": [5.4, "w"], "card_pickup_blue": [5.4, "w"], "card_hatchback": [4.2, "w"],
	"card_jeep": [3.9, "w"], "card_bus": [10.0, "w"],
	"card_tree_burnt": [8.0, "h"], "card_tree_rock_a": [4.5, "h"], "card_tree_moss_a": [5.0, "h"],
	"card_stump_mushroom": [1.5, "h"], "card_tree_rock_b": [4.8, "h"], "card_log_fallen": [7.0, "w"],
	"card_tree_dead_a": [9.5, "h"], "card_tree_dead_b": [8.5, "h"], "card_tree_twist_a": [7.5, "h"],
	"card_stump_roots": [2.2, "h"], "card_tree_white": [9.0, "h"], "card_tree_moss_b": [5.2, "h"],
	"card_tree_twist_b": [6.5, "h"],
	"card_stump_cut": [1.3, "h"], "card_twig_pile": [1.2, "h"], "card_stick_bundle": [1.5, "h"],   # 막대류는 풀에 반쯤 묻히게 작게
	"card_roots_gnarled": [1.8, "h"], "card_roots_stump": [1.6, "h"],
}
const VEHICLES := ["card_excavator", "card_semi_truck", "card_jeep_wreck", "card_van_front", "card_van_rear",
	"card_roadster", "card_sedan_green", "card_pickup_blue", "card_hatchback", "card_jeep", "card_bus"]
const TREES := ["card_tree_burnt", "card_tree_rock_a", "card_tree_moss_a", "card_tree_rock_b", "card_tree_dead_a",
	"card_tree_dead_b", "card_tree_twist_a", "card_tree_white", "card_tree_moss_b", "card_tree_twist_b"]
const GROUND := ["card_stump_mushroom", "card_stump_roots", "card_stump_cut", "card_twig_pile", "card_stick_bundle",
	"card_roots_gnarled", "card_roots_stump"]   # 누운 통나무(card_log_fallen)는 쓰지 않는다

var _meshes := {}


# 카드 하나 만들기. 원점 = 바닥 가운데 (다른 소품과 같은 규칙)
func make(card_name: String, scale_f: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(card_name)
	mi.scale = Vector3.ONE * scale_f
	return mi


func _mesh(card_name: String) -> QuadMesh:
	if _meshes.has(card_name):
		return _meshes[card_name]
	var tex: Texture2D = load(TEX + card_name + ".png")
	var rule: Array = CARDS[card_name]
	var aspect := float(tex.get_width()) / float(tex.get_height())
	var size := Vector2(rule[0], rule[0] / aspect) if rule[1] == "w" else Vector2(rule[0] * aspect, rule[0])
	var q := QuadMesh.new()
	q.size = size
	q.center_offset = Vector3(0, size.y * 0.5 - size.y * 0.06, 0)    # 밑동을 땅에 묻고 풀로 가려 떠 보이지 않게
	var mat := ShaderMaterial.new()                                 # Y축 빌보드 + 채도·색조 누르기 (card.gdshader)
	mat.shader = SHADER
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("normal_tex", load(TEX + card_name + "_n.png"))
	q.material = mat
	_meshes[card_name] = q
	return q

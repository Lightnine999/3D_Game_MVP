# Blender 재질 이름을 보고 질감(나무판자·녹·콘크리트)을 입힌다 — 주인: A
#
# 비유: 가구 공장에서 온 "흰 가구"에 이름표(wood_, rust_ …)를 보고 알맞은 시트지를 붙이는 일.
# 질감은 월드 좌표 기준 3방향 투영(triplanar)으로 붙여서, 모델에 UV가 없어도 이음매 없이 입혀진다.
class_name StageMaterials
extends RefCounted

const TEX := "res://assets/textures/v2/"

# 이름 앞부분 → (질감 파일, 1m당 반복 횟수, 밝기 배수)
const RULES := {
	"wood_siding": ["planks.png", 0.62, 1.0],
	"wood_dark": ["planks.png", 0.9, 0.55],
	"wood_crate": ["planks.png", 1.6, 1.25],
	"rust_": ["rust.png", 0.45, 0.72],
	"paint_bus": ["rust.png", 0.3, 1.0],
	"concrete": ["concrete.png", 0.3, 1.0],
	"bark": ["planks.png", 2.2, 0.5],
}

var _cache := {}


func apply(root: Node) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src:
				mi.set_surface_override_material(i, _material_for(src))


func _material_for(src: BaseMaterial3D) -> BaseMaterial3D:
	var key := src.resource_name
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = src.albedo_color
	mat.roughness = 0.95
	mat.metallic = 0.0
	if key.begins_with("glow_"):
		mat.emission_enabled = true
		mat.emission = src.albedo_color
		mat.emission_energy_multiplier = 8.0 if key == "glow_lamp" else 1.6
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	elif key.begins_with("dark_"):
		mat.roughness = 1.0
	else:
		for prefix in RULES:
			if key.begins_with(prefix):
				var rule: Array = RULES[prefix]
				mat.albedo_texture = load(TEX + rule[0])
				mat.uv1_triplanar = true
				mat.uv1_world_triplanar = true
				mat.uv1_scale = Vector3.ONE * rule[1]
				mat.albedo_color = _tone(src.albedo_color, rule[2])
				break
	_cache[key] = mat
	return mat


# 질감 자체에 색이 있으므로, 원래 색은 은은하게만 섞는다 (밝기 배수 × 약한 색조)
func _tone(c: Color, bright: float) -> Color:
	var lum := (c.r + c.g + c.b) / 3.0
	var tint := Color(c.r / max(lum, 0.01), c.g / max(lum, 0.01), c.b / max(lum, 0.01))
	return Color(lerpf(1.0, tint.r, 0.35), lerpf(1.0, tint.g, 0.35), lerpf(1.0, tint.b, 0.35)) * (bright * 1.4)

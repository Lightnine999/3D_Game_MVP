# Blender 재질 이름을 보고 질감(나무판자·녹·콘크리트)을 입힌다 — 주인: A
#
# 비유: 가구 공장에서 온 "흰 가구"에 이름표(wood_, rust_ …)를 보고 알맞은 시트지를 붙이는 일.
# 질감은 월드 좌표 기준 3방향 투영(triplanar)으로 붙여서, 모델에 UV가 없어도 이음매 없이 입혀진다.
class_name StageMaterials
extends RefCounted

const PH := "res://assets/textures/polyhaven/"   # Poly Haven CC0 실사 질감 (색·노멀·거칠기)

# 이름 앞부분 → (Poly Haven 질감 이름, 1m당 반복 횟수, 밝기 배수, 원래 색을 섞는 정도)
const RULES := {
	"wood_siding": ["weathered_planks", 0.45, 1.15, 0.2],
	"wood_dark": ["weathered_planks", 0.7, 0.5, 0.2],
	"wood_crate": ["weathered_planks", 1.2, 1.1, 0.3],
	"rust_": ["rusty_metal_02", 0.4, 0.6, 0.3],
	"paint_bus": ["rusty_metal_02", 0.3, 1.1, 0.7],      # 스쿨버스는 노란 칠이 보이게
	"concrete": ["concrete_wall_003", 0.35, 0.42, 0.35],
	"bark": ["weathered_planks", 1.8, 0.45, 0.2],
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
				var base: String = PH + rule[0]
				mat.albedo_texture = load(base + "_diff_1k.jpg")
				mat.normal_enabled = true
				mat.normal_texture = load(base + "_nor_gl_1k.jpg")
				mat.roughness = 1.0
				mat.roughness_texture = load(base + "_rough_1k.jpg")
				mat.uv1_triplanar = true
				mat.uv1_world_triplanar = true
				mat.uv1_triplanar_sharpness = 6.0   # 면 경계에서 질감이 번지지 않게
				mat.uv1_scale = Vector3.ONE * rule[1]
				mat.albedo_color = _tone(src.albedo_color, rule[2], rule[3])
				break
	_cache[key] = mat
	return mat


# 질감 자체에 색이 있으므로, 원래 색은 mix 만큼만 섞는다 (밝기 배수 × 색조)
func _tone(c: Color, bright: float, mix: float) -> Color:
	var lum := (c.r + c.g + c.b) / 3.0
	var tint := Color(c.r / max(lum, 0.01), c.g / max(lum, 0.01), c.b / max(lum, 0.01))
	return Color(lerpf(1.0, tint.r, mix), lerpf(1.0, tint.g, mix), lerpf(1.0, tint.b, mix)) * bright

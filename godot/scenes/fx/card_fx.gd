class_name CardFX
extends Node3D
## 카드 시퀀스 이펙트 (2026-09-30): 입자를 뿌리지 않고 스프라이트 시트 한 장의 칸을 넘기는 카드로 만든다 → 용량·폰 성능
## 그림은 tools/assets/make_fx_atlases.py 가 만든다 (assets/textures/fx/)
##   CardFX.flare(부모, 색)            보급 신호탄: 불꽃·불똥(반복) + 연기 기둥(반복) + 색 조명 — 부모를 따라 움직인다
##   CardFX.blood_splash(부모, 자리, 크기)  맞은 자리 피 튐 (한 번, 0.45초)
##   CardFX.blood_pool(부모, 자리)       쓰러진 좀비 밑 핏자국 — 4초 뒤 2초 동안 옅어져 사라진다 (PRD N-08: 바닥에 오래 고이지 않게)

const TEX := "res://assets/textures/fx/"
static var _mats := {}
static var _quad: QuadMesh

var _life := -1.0            # 0 보다 크면 이만큼 뒤에 사라진다
var _fade_from := 0.0        # 이 시각부터 옅어진다
var _fade_len := 0.0
var _t := 0.0
var _oneshot: GeometryInstance3D
var _oneshot_len := 0.0
var _light: OmniLight3D
var _light_e := 0.0
var _oneshot_frames := 15.0      # 한 번 재생할 칸 수 - 1
var _flash_light := false        # 빛이 불꽃처럼 일렁이지 않고 한 번 번쩍 줄어든다


static func _mat(key: String, shader: String, tex: String, tint: Color, energy: float, fps: float, y_bb: bool) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://scenes/fx/" + shader)
	m.set_shader_parameter("atlas", load(TEX + tex))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("fps", fps)
	m.set_shader_parameter("y_billboard", y_bb)
	_mats[key] = m
	return m


func _card(mat: Material, size: Vector2, pos: Vector3) -> MeshInstance3D:
	if _quad == null:
		_quad = QuadMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = mat
	mi.scale = Vector3(size.x, size.y, 1.0)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("phase", randf())
	add_child(mi)
	return mi


# 보급 신호탄: green = 초록 불빛 보급, 아니면 빨강
static func flare(parent: Node3D, green: bool) -> CardFX:
	var fx := CardFX.new()
	parent.add_child(fx)
	var col := Color(0.35, 1.0, 0.45) if green else Color(1.0, 0.28, 0.2)
	var key := "g" if green else "r"
	fx._card(_mat("smoke_" + key, "card_flipbook_mix.gdshader", "fx_flare_smoke_4x4.png", Color(col.lerp(Color(0.8, 0.8, 0.8), 0.35), 0.8), 1.0, 9.0, true), Vector2(2.6, 5.2), Vector3(0, 2.9, 0))
	fx._card(_mat("smoke2_" + key, "card_flipbook_mix.gdshader", "fx_flare_smoke_4x4.png", Color(col.lerp(Color(0.8, 0.8, 0.8), 0.5), 0.55), 1.0, 7.0, true), Vector2(3.4, 6.8), Vector3(0.3, 3.6, 0.2))
	fx._card(_mat("halo_" + key, "card_flipbook_add.gdshader", "fx_flare_4x4.png", col, 0.7, 8.0, false), Vector2(5.5, 5.5), Vector3(0, 1.0, 0))      # 넓은 빛무리
	fx._card(_mat("flare_" + key, "card_flipbook_add.gdshader", "fx_flare_4x4.png", col, 3.2, 20.0, false), Vector2(3.4, 3.4), Vector3(0, 1.05, 0))    # 불똥 (풍성하게)
	fx._card(_mat("flare2_" + key, "card_flipbook_add.gdshader", "fx_flare_4x4.png", col.lerp(Color.WHITE, 0.45), 2.4, 13.0, false), Vector2(2.0, 2.0), Vector3(0.1, 1.1, 0.05))   # 하얗게 타는 심지
	fx._light = OmniLight3D.new()                        # 주변 풀을 물들이는 빛 (불꽃처럼 일렁인다)
	fx._light.light_color = col
	fx._light_e = 3.0
	fx._light.light_energy = fx._light_e
	fx._light.omni_range = 7.0
	fx._light.position = Vector3(0, 1.2, 0)
	fx.add_child(fx._light)
	return fx


# 총구 불꽃 (2026-09-30 "카메라 앞인데 디테일이 구리다"): 별 모양 8칸을 0.07초에 넘긴다 + 아주 짧은 빛. 매번 각도·크기를 달리한다
static func muzzle(parent: Node3D, size := 0.38) -> CardFX:
	var fx := CardFX.new()
	parent.add_child(fx)
	var m := _mat("muzzle", "card_flipbook_add.gdshader", "fx_muzzle_4x2.png", Color(1, 1, 1, 1), 1.6, 0.0, false)
	m.set_shader_parameter("rows", 2.0)
	m.set_shader_parameter("frames", 8.0)
	fx._oneshot = fx._card(m, Vector2.ONE * size * randf_range(0.85, 1.2), Vector3(0, 0, -0.03))
	fx._oneshot.set_instance_shader_parameter("frame_override", 0.0)
	fx._oneshot.set_instance_shader_parameter("spin", randf() * TAU)
	fx._oneshot_len = 0.07
	fx._oneshot_frames = 7.0
	fx._life = 0.08
	fx._light = OmniLight3D.new()                       # 번쩍 (손·총·주변 풀을 순간 밝힌다)
	fx._light.light_color = Color(1.0, 0.72, 0.4)
	fx._light_e = 2.5
	fx._light.light_energy = fx._light_e
	fx._light.omni_range = 3.0
	fx._flash_light = true
	fx.add_child(fx._light)
	return fx


static func blood_splash(parent: Node, pos: Vector3, size := 1.1) -> CardFX:
	var fx := CardFX.new()
	parent.add_child(fx)
	fx.global_position = pos
	var m := _mat("blood", "card_flipbook_mix.gdshader", "fx_blood_splash_4x4.png", Color(1, 1, 1, 1), 1.0, 0.0, false)
	fx._oneshot = fx._card(m, Vector2(size, size), Vector3.ZERO)
	fx._oneshot.set_instance_shader_parameter("frame_override", 0.0)
	fx._oneshot_len = 0.45
	fx._life = 0.45
	return fx


static func blood_pool(parent: Node, pos: Vector3, size := 1.6) -> CardFX:
	var fx := CardFX.new()
	parent.add_child(fx)
	fx.global_position = pos + Vector3(0, 0.03, 0)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mi.mesh = plane
	if not _mats.has("pool"):
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = load(TEX + "fx_blood_pool.png")
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = Color(0.75, 0.75, 0.75, 1.0)
		_mats["pool"] = sm
	mi.material_override = (_mats["pool"] as StandardMaterial3D).duplicate()   # 옅어지는 정도가 저마다 달라서 복사
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3.ONE * 0.2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(mi)
	fx._oneshot = mi
	fx._life = 6.0
	fx._fade_from = 4.0
	fx._fade_len = 2.0
	return fx


func _process(delta: float) -> void:
	_t += delta
	if _light and _flash_light:
		_light.light_energy = _light_e * maxf(1.0 - _t / 0.06, 0.0)
	elif _light:
		_light.light_energy = _light_e * (0.85 + 0.15 * sin(_t * 23.0) * sin(_t * 7.3))
	if _oneshot and _oneshot_len > 0.0:                  # 피 튐: 칸을 차례로
		_oneshot.set_instance_shader_parameter("frame_override", clampf(_t / _oneshot_len, 0.0, 1.0) * _oneshot_frames)
	elif _oneshot and _fade_len > 0.0:                   # 핏자국: 번지고 → 옅어진다
		_oneshot.scale = Vector3.ONE * lerpf(0.2, 1.0, clampf(_t / 0.5, 0.0, 1.0))
		var a := 1.0 - clampf((_t - _fade_from) / _fade_len, 0.0, 1.0)
		((_oneshot as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = a
	if _life > 0.0 and _t >= _life:
		queue_free()

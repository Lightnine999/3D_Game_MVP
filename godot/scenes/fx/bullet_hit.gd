class_name BulletHitFX
extends Node3D
## 총알 착탄 + 피 튐 — 좀비가 총에 맞은 자리 (2026-09-30 플레이 피드백, 주인 A)
## 비유: 맞는 순간 "번쩍"(착탄 섬광) → "탁"(불똥) → "퍽"(핏방울이 뒤로 튀고 붉은 안개가 잠깐 핀다).
## 텍스처 파일 없이 엔진 안에서 만든다: 파티클(CPUParticles3D, 폰에서도 가벼움) + 둥근 그라데이션 점.
## PRD N-08(과도한 유혈 없음): 피는 0.6초 안에 사라지고 바닥에 고이지 않는다. 기존 hit_blood.tscn(세권 님, WU-29)보다 크게·또렷하게.
##
## 사용법:
##   BulletHitFX.spawn(부모, 맞은 자리, 쏜 쪽에서 맞은 쪽 방향, 세기)
##   세기 1.0 = 권총 한 발. 탱커처럼 큰 좀비는 1.3 정도

const LIFE := 0.9

static var _dot_tex: Texture2D


static func spawn(parent: Node, pos: Vector3, shot_dir: Vector3, strength := 1.0) -> BulletHitFX:
	var fx := BulletHitFX.new()
	parent.add_child(fx)
	fx.global_position = pos
	fx._build(shot_dir.normalized(), strength)
	return fx


func _build(dir: Vector3, k: float) -> void:
	var back := dir                                    # 피는 총알이 날아간 방향(좀비 뒤쪽)으로 주로 튄다
	var toward := -dir                                 # 불똥은 쏜 쪽(카메라 쪽)으로 조금 튄다
	# 1) 착탄 섬광: 아주 짧게 번쩍이는 주황-흰 빛 + 작은 빛 점 (10m 거리에서도 보이게 크게)
	_burst(2, 0.08, Vector3.UP, 0.0, 0.0, Color(1.0, 0.9, 0.6, 1.0), Color(1.0, 0.5, 0.2, 0.0), 0.8 * k, 0.3, true, 0.0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.4)
	light.light_energy = 3.0
	light.omni_range = 3.5
	add_child(light)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.12)
	# 2) 불똥: 짧게 튀고 떨어진다 (카메라까지 날아오지 않게 느리게)
	_burst(int(10 * k), 0.2, toward + Vector3(0, 0.4, 0), 50.0, 3.0, Color(1.0, 0.9, 0.6, 1.0), Color(1.0, 0.4, 0.1, 0.0), 0.06, 0.5, true, 9.8)
	# 3) 핏방울: 뒤쪽으로 원뿔 모양으로 튀고 중력으로 떨어진다
	_burst(int(36 * k), 0.6, back + Vector3(0, 0.3, 0), 32.0, 5.5, Color(0.7, 0.05, 0.04, 1.0), Color(0.4, 0.0, 0.0, 0.0), 0.13, 0.5, false, 9.8)
	# 4) 붉은 안개: 맞은 자리에 잠깐 피었다 사라지는 피 안개
	_burst(int(6 * k), 0.5, back, 70.0, 1.0, Color(0.7, 0.08, 0.06, 0.6), Color(0.45, 0.03, 0.03, 0.0), 0.6 * k, 1.7, false, 0.0)
	# 5) 앞쪽으로도 핏방울 조금 (맞은 쪽에서 튀는 것이 보이게)
	_burst(int(14 * k), 0.45, toward + Vector3(0, 0.4, 0), 45.0, 2.5, Color(0.72, 0.06, 0.05, 1.0), Color(0.4, 0.0, 0.0, 0.0), 0.1, 0.6, false, 9.8)
	get_tree().create_timer(LIFE).timeout.connect(queue_free)


# 한 번에 터지는 파티클 무리
func _burst(amount: int, life: float, dir: Vector3, spread: float, speed: float, c0: Color, c1: Color,
		size: float, size_end: float, additive: bool, gravity: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.05
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1, size_end))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, c0)
	grad.set_color(1, c1)
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _dot()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true                              # 안개 속에서도 또렷하게
	if additive:
		mat.albedo_color = Color(2.0, 1.6, 1.2)         # 빛나 보이게 (글로우 문턱 넘김)
	q.material = mat
	p.mesh = q
	p.emitting = true
	add_child(p)


# 가운데가 진하고 가장자리가 부드러운 둥근 점 (텍스처 파일 대신 엔진에서 만든다)
static func _dot() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.55, Color(1, 1, 1, 0.85))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 32
		t.height = 32
		_dot_tex = t
	return _dot_tex

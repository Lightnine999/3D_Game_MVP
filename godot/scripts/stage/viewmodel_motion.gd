class_name ViewmodelMotion
extends Node3D
## 1인칭 권총 시범 동작 — 주인 A (시범). B 가 scripts/weapons 로 옮겨 쓰거나 그대로 가져다 쓴다.
## TECH_SPEC 5.5 "걷기 흔들림(bob), 사격 반동(recoil), 재장전 동작은 코드(Tween)로 구현한다" 를 따른다.
##
## 쓰는 법 (카메라의 자식으로 붙인다):
##   var vm := ViewmodelMotion.new()
##   camera.add_child(vm)                 # weapon_pistol.glb 는 스스로 불러 자식으로 붙인다
##   vm.aim_at(zombie.global_position + Vector3.UP * 1.3)   # 자동 조준(F-11)이 고른 좀비 쪽으로 총을 돌린다
##   vm.fire()                            # 반동 + 슬라이드가 뒤로 (총구 섬광은 vm.muzzle 에 붙인다)
##   vm.reload()                          # 탄창 빼기 → 왼손이 새 탄창 → 슬라이드 당기기 (약 1.4초)
##   vm.clear_aim()                       # 조준 풀기 (정면으로 돌아옴)
##   vm.running = true                    # 달리기 흔들림
## weapon_pistol.glb 부품 이름: Frame / Slide(자식 Optic) / Magazine / Trigger / HandRight / HandLeft

signal reloaded

const MODEL := "res://assets/models/weapon_pistol.glb"
const REST_POS := Vector3(0.025, -0.12, -0.38)   # 카메라 기준 오른쪽 아래 (WU-23 "화면 오른쪽 아래"). 손이 너무 크게 보이지 않을 만큼 떨어뜨림
const REST_YAW := deg_to_rad(12.0)              # 총구를 안쪽으로 → 총 오른쪽 면과 오른손 등이 보인다
const REST_ROLL := deg_to_rad(6.0)              # 총 윗면을 살짝 왼쪽으로 기울여 → 오른손 등이 화면 쪽을 향한다
const MUZZLE := Vector3(0.0, 0.055, -0.160)     # 손잡이 원점에서 총구 (make_pistol.py 출력)
const GRIP_DOWN := Vector3(0.0, -0.951, 0.309)  # 탄창이 빠지는 방향 = 손잡이 축 아래쪽
const MAX_YAW := deg_to_rad(24.0)               # 좌우로 돌릴 수 있는 한계
const MAX_PITCH := deg_to_rad(14.0)             # 위아래 한계
const AIM_SPEED := 9.0                          # 클수록 빨리 돌아감
const SLIDE_BACK := 0.028                       # 쏠 때 슬라이드가 밀리는 거리 (m)

var running := true
var muzzle: Node3D          # 총구 위치 (총구 섬광을 여기에 붙인다)
var busy := false           # 장전 중
var rest_offset := Vector3.ZERO   # 게임이 총 위치를 살짝 옮길 때 (stage showcase — 소매가 덜 보이게, 2026-09-30)
var speed := 1.0            # 재장전 빠르기 (1 = 약 1.2초). 게임이 재장전 시간에 맞춰 늦춘다 (stage showcase, 2026-09-30)

var _model: Node3D
var _slide: Node3D
var _mag: Node3D
var _hand_left: Node3D
var _slide_rest: Vector3
var _mag_rest: Vector3
var _hand_rest: Vector3
var _target = null          # Vector3 또는 null
var _aim := Vector2.ZERO    # (좌우, 위아래) 현재 각도
var _kick := 0.0            # 반동 (1 → 0)
var _tilt := Vector3.ZERO   # 장전할 때 총을 기울이는 각도 (Tween 이 바꾼다)
var _lift := Vector3.ZERO   # 장전할 때 총을 화면 가운데로 들어 올리는 거리
var _t := 0.0


func _ready() -> void:
	position = REST_POS
	_model = (load(MODEL) as PackedScene).instantiate()
	add_child(_model)
	_slide = _model.find_child("Slide", true, false)
	_mag = _model.find_child("Magazine", true, false)
	_hand_left = _model.find_child("HandLeft", true, false)
	_slide_rest = _slide.position
	_mag_rest = _mag.position
	_hand_rest = _hand_left.position
	muzzle = Node3D.new()
	muzzle.position = MUZZLE
	_model.add_child(muzzle)
	# 어두운 맵에서 총·손이 묻히지 않게 약한 보조 조명 (총 주변 1 m 만 밝힌다)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.12, 0.18, 0.12)
	fill.light_energy = 0.25
	fill.omni_range = 0.7
	fill.light_color = Color(0.9, 0.95, 1.0)
	add_child(fill)


func aim_at(world_pos: Vector3) -> void:
	_target = world_pos


func clear_aim() -> void:
	_target = null


func fire() -> void:
	if busy:
		return
	_kick = 1.0
	var tw := create_tween()
	tw.tween_property(_slide, "position", _slide_rest + Vector3(0, 0, SLIDE_BACK), 0.04)
	tw.tween_property(_slide, "position", _slide_rest, 0.07).set_ease(Tween.EASE_OUT)


func reload() -> void:
	if busy:
		return
	busy = true
	var down := _mag_rest + GRIP_DOWN * 0.14
	var tw := create_tween()
	tw.set_speed_scale(speed)
	# 1) 총을 왼쪽으로 기울이고 살짝 들어 올린다
	tw.tween_property(self, "_tilt", Vector3(deg_to_rad(22), deg_to_rad(10), deg_to_rad(38)), 0.2).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(self, "_lift", Vector3(-0.05, 0.05, 0.03), 0.2).set_trans(Tween.TRANS_SINE)
	# 2) 빈 탄창이 손잡이 아래로 빠지고, 왼손이 새 탄창을 가지러 내려간다
	tw.tween_property(_mag, "position", down, 0.14).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_hand_left, "position", _hand_rest + Vector3(-0.04, -0.12, 0.05), 0.2)
	tw.tween_callback(func(): _mag.visible = false)
	tw.tween_interval(0.18)
	# 3) 새 탄창을 든 왼손이 올라와 손잡이에 끼운다 (탁)
	tw.tween_callback(func(): _mag.position = down; _mag.visible = true)
	tw.tween_property(_mag, "position", _mag_rest + GRIP_DOWN * 0.012, 0.2).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_hand_left, "position", _hand_rest + Vector3(0, -0.02, 0.01), 0.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_mag, "position", _mag_rest, 0.05)
	tw.parallel().tween_property(_hand_left, "position", _hand_rest, 0.08)
	# 4) 슬라이드를 뒤로 당겼다 놓는다 (철컥)
	tw.tween_property(_slide, "position", _slide_rest + Vector3(0, 0, 0.035), 0.1)
	tw.tween_property(_slide, "position", _slide_rest, 0.05)
	# 5) 원래 자세로
	tw.tween_property(self, "_tilt", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(self, "_lift", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): busy = false; reloaded.emit())


func _process(delta: float) -> void:
	_t += delta
	# 조준: 목표가 있으면 그쪽으로, 없으면 정면으로
	var want := Vector2.ZERO
	if _target != null and not busy:
		var cam := get_parent() as Node3D
		var d: Vector3 = cam.global_transform.affine_inverse() * (_target as Vector3) - REST_POS
		want.x = clampf(atan2(-d.x, -d.z), -MAX_YAW, MAX_YAW)
		want.y = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -MAX_PITCH, MAX_PITCH)
	_aim = _aim.lerp(want, 1.0 - exp(-AIM_SPEED * delta))
	# 반동은 빨리 튀고 천천히 돌아온다
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	var k := _kick * _kick
	# 달리기 흔들림 (8자 모양)
	var bob := Vector3.ZERO
	if running:
		bob = Vector3(sin(_t * 5.2) * 0.006, absf(sin(_t * 10.4)) * 0.008, 0.0)
	position = REST_POS + rest_offset + _lift + bob + Vector3(0, 0.004, 0.035) * k
	rotation = Vector3(_aim.y + deg_to_rad(9.0) * k + _tilt.x, REST_YAW + _aim.x + _tilt.y, REST_ROLL + _tilt.z)

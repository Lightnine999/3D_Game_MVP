class_name KnifeMotion
extends Node3D
## 칼로 좀비를 찌르고 탈출하는 1인칭 시범 동작 — 주인 A (시범). B 가 grab_system(WU-25) 에서 가져다 쓴다.
## PRD F-32 "칼이 있으면 칼로 좀비를 찌르고 탈출한다. 칼은 사라진다" · F-30 "칼은 1회용".
##
## 쓰는 법 (카메라의 자식으로 붙인다):
##   var km := KnifeMotion.new()
##   camera.add_child(km)                  # weapon_knife.glb (칼 + 쥔 오른손) 를 스스로 불러온다. 처음엔 숨김
##   km.hit.connect(func(): ...)          # 칼이 박히는 순간 — 피(hit_blood.play(1.5))·sfx_knife·좀비 stabbed 재생
##   km.finished.connect(func(): ...)     # 칼을 거두고 사라진 뒤 — 풀려남
##   km.stab(zombie_neck_world_pos)       # 아래에서 칼이 올라와 한 번 찌르고, 뽑고, 사라진다 (약 0.9초)

signal hit
signal finished

const MODEL := "res://assets/models/weapon_knife.glb"
const READY_POS := Vector3(0.16, -0.20, -0.32)   # 화면 오른쪽 아래에서 치켜든 자세
const HIDE_POS := Vector3(0.22, -0.55, -0.20)    # 화면 밖 (아래)
const READY_ROT := Vector3(70, 25, -20)          # 도: 칼끝이 앞·위, 팔꿈치가 뒤·아래로
const REACH := 0.55                               # 찌를 때 카메라에서 칼 손잡이까지 최대 거리 (m)

var busy := false
var speed := 1.0            # 찌르기 빠르기 (1 = 약 0.9초). 게임은 잘 보이게 늦춘다 (stage showcase, 2026-09-30)


func _ready() -> void:
	add_child((load(MODEL) as PackedScene).instantiate())
	visible = false


func stab(target_world: Vector3) -> void:
	if busy:
		return
	busy = true
	visible = true
	position = HIDE_POS
	rotation_degrees = READY_ROT + Vector3(-30, 0, 0)
	var cam := get_parent() as Node3D
	var local: Vector3 = cam.global_transform.affine_inverse() * target_world
	var thrust := local.normalized() * minf(REACH, local.length() - 0.12) + Vector3(0.04, -0.08, 0)
	var tw := create_tween()
	tw.set_speed_scale(speed)
	# 1) 아래에서 칼을 치켜듦
	tw.tween_property(self, "position", READY_POS, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(self, "rotation_degrees", READY_ROT, 0.18)
	# 2) 좀비 목을 향해 힘껏 찌름
	tw.tween_property(self, "position", thrust, 0.1).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "rotation_degrees", READY_ROT + Vector3(15, -8, 0), 0.1)
	tw.tween_callback(func(): hit.emit())
	# 3) 박힌 채 잠깐 비틀고 뽑는다
	tw.tween_property(self, "rotation_degrees", READY_ROT + Vector3(15, -8, 25), 0.12)
	tw.tween_interval(0.1)
	tw.tween_property(self, "position", READY_POS + Vector3(0.02, -0.04, 0.06), 0.14).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "rotation_degrees", READY_ROT, 0.14)
	# 4) 칼은 1회용 — 내려가며 사라진다 (F-30)
	tw.tween_property(self, "position", HIDE_POS, 0.22).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): visible = false; busy = false; finished.emit())

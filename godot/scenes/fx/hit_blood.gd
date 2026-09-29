extends Node3D
## 좀비 피격 피 이펙트 — 총·칼에 맞았을 때 (TECH_SPEC 13.3.1 ①-4, 주인 A)
## PRD N-08 "과도한 유혈 표현 없음": 작은 핏방울이 짧게 튀고 사라진다. 바닥에 고이지 않는다.
##
## B 사용법 (약속대로 play() 만 불러도 된다):
##   var fx = preload("res://scenes/fx/hit_blood.tscn").instantiate()
##   add_child(fx)
##   fx.global_position = 맞은 자리
##   fx.play()        # 총
##   fx.play(1.5)     # 칼처럼 가까이서 찌를 때 조금 더 (1.0 - 2.0 권장)
## 이 노드의 -Z 를 공격한 쪽으로 돌려 두면 피는 반대쪽(뒤)으로 튄다. 안 돌려도 위·뒤로 조금 퍼진다.

const BASE_SPRAY := 16
const BASE_MIST := 5

func play(strength: float = 1.0) -> void:
	# add_child 바로 다음에 불러도 되도록 @onready 대신 여기서 찾는다
	var spray := $Spray as CPUParticles3D
	var mist := $Mist as CPUParticles3D
	var k := clampf(strength, 0.5, 2.0)
	spray.amount = int(round(BASE_SPRAY * k))
	mist.amount = int(round(BASE_MIST * k))
	spray.restart()
	mist.restart()
	# 재생이 끝나면 스스로 사라진다 (13.3.1 ①-4). 자기 안에 타이머를 달아 언제 불러도 동작하게 한다
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(spray.lifetime, mist.lifetime) + 0.1
	timer.autostart = true
	timer.timeout.connect(queue_free)
	add_child(timer)

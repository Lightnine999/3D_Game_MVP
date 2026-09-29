extends Node3D
## 충돌 먼지 — 장애물(폐차·폐드럼통·쓰레기 더미)에 부딪혔을 때 (TECH_SPEC 13.3.1 ①-4, 주인 A)
## PRD F-58 "약 1초 동안 비틀거리며 속도가 줄고 화면이 흔들린다" 에 맞춰 먼지가 약 1초 퍼진다.
## 비틀거림·감속·화면 흔들림은 B 의 코드가 한다. 이 장면은 먼지와 작은 파편만 보여 준다.
##
## B 사용법 (약속대로 play() 만 부르면 된다):
##   var fx = preload("res://scenes/fx/dust_impact.tscn").instantiate()
##   add_child(fx)
##   fx.global_position = 부딪힌 자리 (땅 높이)
##   fx.play()
## 먼지는 땅을 따라 사방으로 퍼지고 조금 떠오른다. 방향을 맞출 필요가 없다.

const LIFE := 1.2           # 먼지(1.0초)가 흩어진 뒤 스스로 사라지는 시간


func play() -> void:
	# add_child 전후 언제 불러도 되도록 노드를 여기서 찾는다
	($Dust as CPUParticles3D).restart()
	($Debris as CPUParticles3D).restart()
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = LIFE
	timer.autostart = true
	timer.timeout.connect(queue_free)      # 재생이 끝나면 스스로 사라진다 (13.3.1 ①-4)
	add_child(timer)

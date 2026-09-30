extends Node3D
## 총구 섬광 — 사격할 때 (TECH_SPEC 13.3.1 ①-4, 주인 A / PRD F-14 "총구 섬광")
## 약 0.07초 번쩍인다. 발사 간격 0.4초(PRD F-12)보다 훨씬 짧아 연사해도 겹치지 않는다.
##
## B 사용법 (약속대로 play() 만 부르면 된다):
##   var fx = preload("res://scenes/fx/muzzle_flash.tscn").instantiate()
##   pistol.add_child(fx)
##   fx.position = MUZZLE     # weapon_pistol.glb 의 총구 = 손잡이 원점에서 (0, 0.055, -0.160)
##   fx.play()
## 불꽃·불티는 이 노드의 -Z(총구가 향한 쪽)로 나간다. 권총 자식으로 붙이면 방향은 저절로 맞는다.

const MUZZLE := Vector3(0.0, 0.055, -0.160)
const FLASH_TIME := 0.07     # 불꽃과 빛이 줄어드는 시간
const LIFE := 0.2            # 불티까지 끝나고 스스로 사라지는 시간
const LIGHT_ENERGY := 4.0
const MIN_FRAMES := 2         # 화면이 느려져도 불꽃이 최소 2 화면은 보이게

var _t := -1.0
var _size := 1.0
var _base_basis: Basis      # 장면에 저장된 불꽃 방향 (원뿔 끝 = -Z)
var _frames := 0


func _ready() -> void:
	if _t < 0.0:             # play() 전에만 꺼 둔다 (add_child 전에 play() 를 불렀을 수도 있다)
		$Flame.visible = false
		($Light as OmniLight3D).light_energy = 0.0
		set_process(false)


func play() -> void:
	var flame := $Flame as Node3D
	if _t < 0.0:
		_base_basis = flame.basis.orthonormalized()
	flame.visible = true
	_size = randf_range(0.85, 1.15)                 # 매번 조금씩 달라 보이게
	# 원뿔 자기 축(로컬 Y)으로만 돌린다 → 총구 앞(-Z)을 향한 방향은 그대로
	flame.basis = _base_basis * Basis(Vector3.UP, randf() * TAU)
	flame.scale = Vector3.ONE * _size
	($Light as OmniLight3D).light_energy = LIGHT_ENERGY
	($Sparks as CPUParticles3D).restart()
	_t = 0.0
	_frames = 0
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	var k := maxf(0.0, 1.0 - _t / FLASH_TIME)
	if _frames <= MIN_FRAMES:
		k = maxf(k, 0.4)
	var flame := $Flame as Node3D
	flame.visible = k > 0.0
	flame.scale = Vector3.ONE * _size * (0.6 + 0.4 * k)
	($Light as OmniLight3D).light_energy = LIGHT_ENERGY * k
	if _t >= LIFE:
		queue_free()          # 재생이 끝나면 스스로 사라진다 (13.3.1 ①-4)

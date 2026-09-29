extends Node3D
## 빨간 연막 — 보급 상자 위치 표시 (TECH_SPEC 13.3.1 ①-4, 주인 A / PRD F-24)
## 붉은 연기 기둥 + 깜빡이는 빨간 조명탄 빛. 안개 속 멀리서도 상자 자리를 알아보게 한다.
## 연기 재질은 안개를 무시한다(disable_fog). 시야 30 - 40 m 안개에서 45 - 60 m 앞 상자(PRD F-20)도 보이게 하려는 것.
##
## B 사용법:
##   var fx = preload("res://scenes/fx/smoke_red.tscn").instantiate()
##   crate.add_child(fx)          # 상자 자식으로 붙이면 상자를 따라 움직인다
##   fx.play()                    # 기본 15초 동안 피어오른 뒤 스스로 사라진다
##   fx.play(20.0)                # 시간을 바꿀 때
##   fx.stop()                    # 상자를 주웠을 때: 새 연기를 멈추고, 남은 연기가 흩어지면 사라진다
## 보급 간격 약 150m(PRD F-22), 달리기 5 m/s → 상자까지 약 10초라 기본 15초면 충분하다.

const DEFAULT_TIME := 15.0
const FLARE_ENERGY := 3.0

var _playing := false
var _stopping := false
var _t := 0.0


func _ready() -> void:
	if not _playing:
		($Smoke as CPUParticles3D).emitting = false
		($Flare as OmniLight3D).visible = false
		set_process(false)


func play(duration: float = DEFAULT_TIME) -> void:
	_playing = true
	($Smoke as CPUParticles3D).emitting = true
	($Flare as OmniLight3D).visible = true
	set_process(true)
	_after(duration, stop)


func stop() -> void:
	if _stopping:
		return
	_stopping = true
	var smoke := $Smoke as CPUParticles3D
	smoke.emitting = false
	($Flare as OmniLight3D).visible = false
	set_process(false)
	# 이미 나온 연기가 다 흩어진 뒤 스스로 사라진다 (13.3.1 ①-4)
	_after(smoke.lifetime + 0.2, queue_free)


func _process(delta: float) -> void:
	# 조명탄처럼 불규칙하게 깜빡인다
	_t += delta
	var flicker := 0.75 + 0.15 * sin(_t * 23.0) + 0.1 * sin(_t * 57.0)
	($Flare as OmniLight3D).light_energy = FLARE_ENERGY * flicker


func _after(seconds: float, callback: Callable) -> void:
	# 자기 안에 타이머를 달아 언제 불러도 동작하게 한다
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = seconds
	timer.autostart = true
	timer.timeout.connect(callback)
	add_child(timer)

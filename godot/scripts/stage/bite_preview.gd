# 좀비가 다가와 붙잡고 물어뜯으려는 장면 미리보기 — 주인: A (WU-20b 확인용, 게임 코드 아님)
# 팀 스테이지 맵 위, 주인공 1인칭 시점에서 좀비 4종이 차례로 정면·왼쪽·오른쪽 중 무작위 방향에서 걸어와
#   walk → grab(붙잡기, PRD F-31) → bite(물어뜯기, F-34) 를 한다.
# 붙잡힐 때 화면이 덜컥 흔들리고, 물 때 붉게 번지며 sfx_bite 가 난다 (흔들림·붉은 화면은 B·C 가 게임에서 정한다).
#
# 실행:  godot --path godot res://scenes/stage/bite_preview.tscn
# 영상:  godot --path godot --write-movie out.avi --fixed-fps 30 res://scenes/stage/bite_preview.tscn -- --seconds=26
extends Node3D

const ZOMBIES := ["zombie_walker", "zombie_runner", "zombie_tank", "zombie_ambusher"]
const START_DIST := 5.0      # 이만큼 앞에서 나타남 (풀에 가리지 않게 가까이)
const REACH := 0.95          # 이 거리까지 오면 붙잡음 (좀비 원점 = 발밑)
const EYE := 1.6
const SIDES := {"정면": 0.0, "왼쪽": 75.0, "오른쪽": -75.0}   # 다가오는 방향 (도, 왼쪽이 +)
const NOTICE := 2.8          # 이만큼 가까이 오면 주인공이 그쪽으로 고개를 돌린다

var _builder: StageBuilderV2
var _cam: Camera3D
var _red: ColorRect
var _label: Label
var _z: Node3D
var _ap: AnimationPlayer
var _i := -1
var _state := ""
var _t := 0.0
var _total := 0.0
var _shake := 0.0
var _pull := 0.0            # 붙잡혀 시선이 좀비 얼굴 쪽으로 끌려 내려간 정도 (0 - 1)
var _yaw := 0.0             # 주인공 고개 좌우 (라디안)
var _side := ""
var _seconds := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			_seconds = float(a.trim_prefix("--seconds="))
	_builder = StageBuilderV2.new()
	add_child(_builder)
	_builder.build()
	_builder.update_atmosphere(30.0)
	_cam = Camera3D.new()
	_cam.fov = 60
	_cam.near = 0.05
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.position = Vector3(0, EYE, -30.0)
	add_child(_cam)
	_cam.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	_red = ColorRect.new()
	_red.color = Color(0.55, 0.0, 0.0, 0.0)
	_red.set_anchors_preset(Control.PRESET_FULL_RECT)
	_red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_red)
	_label = Label.new()
	_label.position = Vector2(48, 32)
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_constant_override("outline_size", 8)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(_label)
	_next()


func _next() -> void:
	if _z:
		_z.queue_free()
	_i = (_i + 1) % ZOMBIES.size()
	_z = (load("res://assets/models/%s.glb" % ZOMBIES[_i]) as PackedScene).instantiate()
	add_child(_z)
	_side = SIDES.keys()[randi() % SIDES.size()]
	var ang := deg_to_rad(SIDES[_side] + randf_range(-12.0, 12.0))
	var dir := Vector3(-sin(ang), 0, -cos(ang))           # 주인공에게서 좀비 쪽
	_z.position = Vector3(_cam.position.x, 0, _cam.position.z) + dir * START_DIST
	_face_player()
	_ap = _z.find_children("*", "AnimationPlayer", true, false)[0]
	_ap.get_animation("walk").loop_mode = Animation.LOOP_LINEAR
	_ap.play("walk")
	_state = "walk"
	_t = 0.0
	_red.color.a = 0.0
	_pull = 0.0
	_label.text = "%s — %s에서 다가옴 (walk)" % [ZOMBIES[_i], _side]


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	match _state:
		"walk":
			var to := _flat_to_player()
			_z.position += to.normalized() * (1.6 if ZOMBIES[_i] == "zombie_runner" else 1.1) * delta
			_face_player()
			if to.length() <= REACH:
				_state = "grab"
				_t = 0.0
				_ap.play("grab")
				_shake = 0.35
				_sfx("sfx_zombie_scream")
				_label.text = "%s — 붙잡음 (grab)" % ZOMBIES[_i]
		"grab":
			# 붙잡는 동작의 앞부분(손을 뻗어 움켜쥐는 데까지)만 쓰고 바로 문다
			if _t >= minf(1.6, _ap.current_animation_length * 0.55):
				_state = "bite"
				_t = 0.0
				_ap.play("bite", 0.25)
				_sfx("sfx_bite")
				_label.text = "%s — 물어뜯음 (bite)" % ZOMBIES[_i]
		"bite":
			_shake = maxf(_shake, 0.12 + 0.1 * absf(sin(_t * 9.0)))
			_red.color.a = minf(0.3, _red.color.a + delta * 0.25)
			if _t >= minf(2.8, _ap.current_animation_length):
				_state = "fade"
				_t = 0.0
		"fade":
			_red.color.a = minf(0.7, _red.color.a + delta * 0.8)
			if _t >= 0.7:
				_next()
	_shake = move_toward(_shake, 0.0, delta * 0.8)
	# 붙잡히면 몸이 끌려가며 시선이 좀비 얼굴(숙인 머리) 쪽으로 내려간다
	_pull = move_toward(_pull, 1.0 if _state in ["grab", "bite", "fade"] else 0.0, delta * 2.5)
	_cam.position.y = EYE - 0.14 * _pull
	# 가까이 온 좀비 쪽으로 고개를 돌린다 (옆에서 오면 화면 밖에 있다가 보이게)
	var want := _yaw
	if _flat_to_player().length() < NOTICE or _state != "walk":
		var d := -_flat_to_player()
		want = atan2(-d.x, -d.z)
	_yaw = lerp_angle(_yaw, want, 1.0 - exp(-4.0 * delta))
	if _state == "walk" and _t < 0.1:
		_yaw = lerp_angle(_yaw, 0.0, 0.5)                   # 다음 좀비를 기다릴 때는 정면
	var look_down := 0.08 if ZOMBIES[_i] == "zombie_tank" else 0.32    # 키 큰 탱커는 얼굴이 위에 있다
	_cam.rotation = Vector3(-look_down * _pull + randf_range(-1, 1) * _shake * 0.06,
		_yaw + randf_range(-1, 1) * _shake * 0.06, randf_range(-1, 1) * _shake * 0.05)
	if _seconds > 0.0 and _total >= _seconds:
		get_tree().quit()


func _flat_to_player() -> Vector3:
	var v := _cam.position - _z.position
	v.y = 0.0
	return v


func _face_player() -> void:
	var v := _flat_to_player()
	_z.rotation.y = atan2(-v.x, -v.z)                    # 모델 앞(-Z)이 주인공 쪽을 보게


func _sfx(name: String) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/audio/%s.ogg" % name)
	p.bus = &"SFX"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

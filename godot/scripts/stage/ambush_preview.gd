# 매복 좀비 미리보기 — 주인: A (WU-20b 확인용, 게임 코드 아님)
# 주인공이 풀밭을 달린다. 풀속에 쭈그려 앉은 매복 좀비(crouch_idle)가
# 주인공이 바로 옆에 오면 비명을 지르며 일어서고(crouch_rise, PRD F-43),
# 주인공 쪽으로 덤벼(grab) 붙잡고 물어뜯는다(bite). 왼쪽·오른쪽은 무작위.
#
# 실행:  godot --path godot res://scenes/stage/ambush_preview.tscn
# 영상:  godot --path godot --write-movie out.avi --fixed-fps 30 res://scenes/stage/ambush_preview.tscn -- --seconds=30
extends Node3D

const EYE := 1.6
const RUN := 5.0             # PRD F-01
const AHEAD := 16.0          # 이만큼 앞 풀속에 숨어 있다
const SIDE := 1.6            # 달리는 길에서 옆으로 떨어진 거리
const TRIGGER := 2.2         # 주인공이 이만큼(앞뒤 거리) 다가오면 일어선다
const LUNGE := 4.5           # 덤비는 속도 (m/s)
const REACH := 0.9

var _builder: StageBuilderV2
var _cam: Camera3D
var _red: ColorRect
var _label: Label
var _z: Node3D
var _ap: AnimationPlayer
var _state := ""
var _t := 0.0
var _total := 0.0
var _speed := RUN
var _shake := 0.0
var _pull := 0.0
var _yaw := 0.0
var _side := ""
var _seconds := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			_seconds = float(a.trim_prefix("--seconds="))
	_builder = StageBuilderV2.new()
	add_child(_builder)
	_builder.build()
	_cam = Camera3D.new()
	_cam.fov = 60
	_cam.near = 0.05
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.position = Vector3(0, EYE, -20.0)
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
	_cam.position.x = 0.0
	_side = "왼쪽" if randi() % 2 == 0 else "오른쪽"
	var x := -SIDE if _side == "왼쪽" else SIDE
	_z = (load("res://assets/models/zombie_ambusher.glb") as PackedScene).instantiate()
	add_child(_z)
	_z.position = Vector3(x + randf_range(-0.3, 0.3), 0, _cam.position.z - AHEAD)
	_z.rotation.y = -signf(x) * PI / 2 + randf_range(-0.5, 0.5)   # 길 쪽을 보고 웅크림
	_ap = _z.find_children("*", "AnimationPlayer", true, false)[0]
	_ap.get_animation("crouch_idle").loop_mode = Animation.LOOP_PINGPONG   # 쭈그린 채 꿈틀
	_ap.play("crouch_idle")
	_state = "hide"
	_t = 0.0
	_speed = RUN
	_red.color.a = 0.0
	_pull = 0.0
	_label.text = "달리는 중… (%s 풀속에 매복 좀비가 쭈그려 앉아 있음)" % _side


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	_cam.position.z -= _speed * delta
	match _state:
		"hide":
			if _cam.position.z - _z.position.z <= TRIGGER:
				_state = "rise"
				_t = 0.0
				_ap.play("crouch_rise")
				_face_player()
				_sfx("sfx_zombie_scream")
				_shake = 0.2
				_label.text = "%s 옆에서 벌떡 일어남 (crouch_rise)" % _side
		"rise":
			_speed = move_toward(_speed, 1.5, delta * 6.0)          # 놀라서 주춤
			_face_player()
			if _t >= _ap.current_animation_length * 0.85:
				_state = "lunge"
				_t = 0.0
				_ap.play("grab", 0.15)
				_label.text = "덤벼듦 (grab)"
		"lunge":
			var to := _flat_to_player()
			_z.position += to.normalized() * LUNGE * delta
			_face_player()
			if to.length() <= REACH:
				_state = "bite"
				_t = 0.0
				_speed = 0.0
				_ap.play("bite", 0.2)
				_sfx("sfx_bite")
				_shake = 0.35
				_label.text = "붙잡혀 물어뜯김 (bite)"
		"bite":
			_speed = 0.0
			_face_player()
			_shake = maxf(_shake, 0.12 + 0.1 * absf(sin(_t * 9.0)))
			_red.color.a = minf(0.3, _red.color.a + delta * 0.25)
			if _t >= 2.6:
				_state = "fade"
				_t = 0.0
		"fade":
			_speed = 0.0
			_red.color.a = minf(0.7, _red.color.a + delta * 0.8)
			if _t >= 0.7:
				_next()
	_shake = move_toward(_shake, 0.0, delta * 0.8)
	# 일어나는 소리가 나면 그쪽으로 고개를 돌리고, 물리면 시선이 끌려 내려간다
	var want := 0.0
	if _state != "hide":
		var d := -_flat_to_player()
		want = atan2(-d.x, -d.z)
	_yaw = lerp_angle(_yaw, want, 1.0 - exp(-5.0 * delta))
	_pull = move_toward(_pull, 1.0 if _state in ["bite", "fade"] else 0.0, delta * 2.5)
	var bob := absf(sin(_total * TAU * 2.6)) * 0.04 * (_speed / RUN)   # 달릴 때만 흔들림
	_cam.position.y = EYE - 0.14 * _pull + bob
	_cam.rotation = Vector3(-0.3 * _pull + randf_range(-1, 1) * _shake * 0.06,
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

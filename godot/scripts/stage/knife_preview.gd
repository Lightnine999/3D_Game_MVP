# 칼로 좀비를 물리치는 장면 미리보기 — 주인: A (확인용, 게임 코드 아님)
# 주인공 1인칭. 좀비가 무작위 방향(정면·왼쪽·오른쪽)에서 다가와 붙잡는다(grab).
#   칼이 있으면 → 칼로 목을 찔러(KnifeMotion) 좀비가 쓰러지고(stabbed) 풀려난다. 칼은 사라진다 (PRD F-30·F-32·F-35)
#   칼이 없으면 → 물어뜯긴다(bite, F-34)
# 한 바퀴: 1번째 좀비 = 칼로 탈출, 2번째 좀비 = 칼이 없어 물림 → 칼을 다시 받고 반복
#
# 실행:  godot --path godot res://scenes/stage/knife_preview.tscn
# 영상:  godot --path godot --write-movie out.avi --fixed-fps 30 res://scenes/stage/knife_preview.tscn -- --seconds=30
extends Node3D

const ZOMBIES := ["zombie_walker", "zombie_runner", "zombie_tank", "zombie_ambusher"]
const SIDES := {"정면": 0.0, "왼쪽": 60.0, "오른쪽": -60.0}
const START_DIST := 5.0
const REACH := 0.95
const EYE := 1.6

var BLOOD := preload("res://scenes/fx/hit_blood.tscn")

var _builder: StageBuilderV2
var _cam: Camera3D
var _knife: KnifeMotion
var _red: ColorRect
var _label: Label
var _hud: Label
var _z: Node3D
var _ap: AnimationPlayer
var _i := -1
var _has_knife := true
var _state := ""
var _t := 0.0
var _total := 0.0
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
	_builder.update_atmosphere(30.0)
	_cam = Camera3D.new()
	_cam.fov = 60
	_cam.near = 0.05
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.position = Vector3(0, EYE, -30.0)
	add_child(_cam)
	_cam.make_current()
	_knife = KnifeMotion.new()
	_cam.add_child(_knife)
	_knife.hit.connect(_on_knife_hit)
	_knife.finished.connect(_on_knife_done)
	var layer := CanvasLayer.new()
	add_child(layer)
	_red = ColorRect.new()
	_red.color = Color(0.55, 0.0, 0.0, 0.0)
	_red.set_anchors_preset(Control.PRESET_FULL_RECT)
	_red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_red)
	for l in 2:
		var lab := Label.new()
		lab.position = Vector2(48, 32 + l * 56)
		lab.add_theme_font_size_override("font_size", 34)
		lab.add_theme_constant_override("outline_size", 8)
		lab.add_theme_color_override("font_outline_color", Color.BLACK)
		layer.add_child(lab)
		if l == 0:
			_label = lab
		else:
			_hud = lab
	_next()


func _next() -> void:
	if _z:
		_z.queue_free()
	_i += 1
	if _i % 2 == 0:
		_has_knife = true                                    # 한 바퀴마다 칼을 다시 받는다 (미리보기용)
	_z = (load("res://assets/models/%s.glb" % ZOMBIES[_i % ZOMBIES.size()]) as PackedScene).instantiate()
	add_child(_z)
	_side = SIDES.keys()[randi() % SIDES.size()]
	var ang := deg_to_rad(SIDES[_side] + randf_range(-10.0, 10.0))
	_z.position = Vector3(_cam.position.x, 0, _cam.position.z) + Vector3(-sin(ang), 0, -cos(ang)) * START_DIST
	_face_player()
	_ap = _z.find_children("*", "AnimationPlayer", true, false)[0]
	_ap.get_animation("walk").loop_mode = Animation.LOOP_LINEAR
	_ap.play("walk")
	_state = "walk"
	_t = 0.0
	_red.color.a = 0.0
	_pull = 0.0
	_label.text = "%s — %s에서 다가옴" % [ZOMBIES[_i % ZOMBIES.size()], _side]
	_update_hud()


func _update_hud() -> void:
	_hud.text = "칼: %s" % ("있음 (1회용)" if _has_knife else "없음")


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	match _state:
		"walk":
			var to := _flat_to_player()
			_z.position += to.normalized() * 1.2 * delta
			_face_player()
			if to.length() <= REACH:
				_state = "grab"
				_t = 0.0
				_ap.play("grab")
				_shake = 0.35
				_sfx("sfx_zombie_scream")
				_label.text = "붙잡힘 (grab)"
		"grab":
			if _t >= 0.7:
				if _has_knife:
					_state = "knife"
					_t = 0.0
					_label.text = "칼로 찌름! (칼은 1회용)"
					_knife.stab(_neck())
				else:
					_state = "bite"
					_t = 0.0
					_ap.play("bite", 0.25)
					_sfx("sfx_bite")
					_label.text = "칼이 없다 — 물어뜯김 (bite)"
		"knife":
			pass                                              # _on_knife_hit / _on_knife_done 이 진행
		"freed":
			# 쓰러지는 좀비에게서 벗어난다
			var away := -_flat_to_player().normalized()
			_z.position += away * maxf(0.0, 0.8 - _t) * 1.2 * delta
			if _t >= 2.2:
				_next()
		"bite":
			_shake = maxf(_shake, 0.12 + 0.1 * absf(sin(_t * 9.0)))
			_red.color.a = minf(0.3, _red.color.a + delta * 0.25)
			if _t >= 2.6:
				_state = "fade"
				_t = 0.0
		"fade":
			_red.color.a = minf(0.7, _red.color.a + delta * 0.8)
			if _t >= 0.7:
				_next()
	_shake = move_toward(_shake, 0.0, delta * 0.8)
	var want := _yaw
	if _flat_to_player().length() < 2.8 or _state != "walk":
		var d := -_flat_to_player()
		want = atan2(-d.x, -d.z)
	elif _state == "walk" and _t < 0.1:
		want = 0.0
	_yaw = lerp_angle(_yaw, want, 1.0 - exp(-4.0 * delta))
	_pull = move_toward(_pull, 1.0 if _state in ["grab", "knife", "bite", "fade"] else 0.0, delta * 2.5)
	var look_down := 0.08 if ZOMBIES[_i % ZOMBIES.size()] == "zombie_tank" else 0.28
	_cam.position.y = EYE - 0.12 * _pull
	_cam.rotation = Vector3(-look_down * _pull + randf_range(-1, 1) * _shake * 0.06,
		_yaw + randf_range(-1, 1) * _shake * 0.06, randf_range(-1, 1) * _shake * 0.05)
	if _seconds > 0.0 and _total >= _seconds:
		get_tree().quit()


func _on_knife_hit() -> void:
	# 칼이 박히는 순간: 피·소리·흔들림, 좀비는 찔려 쓰러진다 (F-32)
	var b := BLOOD.instantiate()
	add_child(b)
	b.global_position = _neck()
	b.look_at(_cam.global_position)
	b.play(1.5)
	_sfx("sfx_knife")
	_shake = 0.4
	_ap.play("stabbed", 0.1)
	_has_knife = false                                        # 칼은 1회용 → HUD 칼 아이콘이 사라진다 (F-35)
	_update_hud()


func _on_knife_done() -> void:
	_state = "freed"
	_t = 0.0
	_label.text = "탈출! 좀비가 쓰러짐 (stabbed) — 칼은 사라짐"


func _neck() -> Vector3:
	var h := 1.95 if ZOMBIES[_i % ZOMBIES.size()] == "zombie_tank" else 1.45
	return _z.global_position + Vector3.UP * h + _flat_to_player().normalized() * 0.15


func _flat_to_player() -> Vector3:
	var v := _cam.position - _z.position
	v.y = 0.0
	return v


func _face_player() -> void:
	var v := _flat_to_player()
	_z.rotation.y = atan2(-v.x, -v.z)


func _sfx(name: String) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/audio/%s.ogg" % name)
	p.bus = &"SFX"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

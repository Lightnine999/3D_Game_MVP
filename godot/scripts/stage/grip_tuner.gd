# 권총 쥔 자세 조정 화면 — 주인: A (조정용 도구, 게임 코드 아님)
# 손은 그대로 두고 총만 키보드로 조금씩 옮겨 보며, 손에 꼭 맞는 자리를 찾는다.
# Enter 를 누르면 값이 화면·콘솔·파일(user://grip_tuned.txt)에 남는다 → A 가 make_pistol.py 에 굳혀 넣는다.
#
# 실행: godot --path godot res://scenes/stage/grip_tuner.tscn
extends Node3D

const MODEL := "res://assets/models/weapon_pistol.glb"
const GUN_PARTS := ["Frame", "Slide", "Magazine", "Trigger"]

var _cam: Camera3D
var _vm: Node3D          # 화면 속 총+손 전체
var _gun: Node3D         # 총만 (손은 빼고)
var _label: Label
var _gun_pos := Vector3.ZERO      # 총을 손에 대해 옮긴 거리 (m, 총 기준: x 오른쪽, y 위, z 뒤)
var _gun_rot := Vector3.ZERO      # 총을 돌린 각도 (도: x 위아래, y 좌우, z 기울임)
var _vm_pos := Vector3(0.025, -0.12, -0.38)
var _vm_rot := Vector3(0, 12, 6)


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.33, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.55, 0.58)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 60
	_cam.near = 0.05
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(_cam)
	_vm = Node3D.new()
	_cam.add_child(_vm)
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	_vm.add_child(model)
	# 총 부품만 새 노드 아래로 옮겨, 손은 그대로 두고 총만 움직일 수 있게 한다
	_gun = Node3D.new()
	model.add_child(_gun)
	for n in GUN_PARTS:
		var part: Node3D = model.find_child(n, true, false)
		if part:
			part.reparent(_gun, true)

	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(40, 30)
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_constant_override("outline_size", 8)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(_label)
	_apply()


func _unhandled_key_input(event: InputEvent) -> void:
	var e := event as InputEventKey
	if not e or not e.pressed:
		return
	var mm := 0.005 if e.shift_pressed else 0.001      # 한 번에 1 mm (Shift: 5 mm)
	var deg := 5.0 if e.shift_pressed else 1.0          # 한 번에 1° (Shift: 5°)
	match e.keycode:
		KEY_A: _gun_pos.x -= mm          # 총을 왼쪽(엄지 쪽)으로
		KEY_D: _gun_pos.x += mm          # 오른쪽(손바닥 쪽)으로
		KEY_R: _gun_pos.y += mm          # 위로
		KEY_F: _gun_pos.y -= mm          # 아래로
		KEY_W: _gun_pos.z -= mm          # 앞으로
		KEY_S: _gun_pos.z += mm          # 뒤로
		KEY_Q: _gun_rot.y += deg         # 총구를 왼쪽으로
		KEY_E: _gun_rot.y -= deg         # 총구를 오른쪽으로
		KEY_T: _gun_rot.x += deg         # 총구를 위로
		KEY_G: _gun_rot.x -= deg         # 총구를 아래로
		KEY_Z: _gun_rot.z += deg         # 총을 왼쪽으로 기울이기
		KEY_C: _gun_rot.z -= deg         # 오른쪽으로 기울이기
		KEY_LEFT: _vm_pos.x -= mm        # (화면 속 위치) 손과 총 전체를 왼쪽으로
		KEY_RIGHT: _vm_pos.x += mm
		KEY_UP: _vm_pos.y += mm
		KEY_DOWN: _vm_pos.y -= mm
		KEY_PAGEUP: _vm_pos.z -= mm      # 멀리
		KEY_PAGEDOWN: _vm_pos.z += mm    # 가까이
		KEY_BRACKETLEFT: _vm_rot.y += deg
		KEY_BRACKETRIGHT: _vm_rot.y -= deg
		KEY_BACKSPACE:
			_gun_pos = Vector3.ZERO
			_gun_rot = Vector3.ZERO
		KEY_ENTER, KEY_KP_ENTER:
			_save()
		_:
			return
	_apply()


func _apply() -> void:
	_gun.position = _gun_pos
	_gun.rotation_degrees = _gun_rot
	_vm.position = _vm_pos
	_vm.rotation_degrees = _vm_rot
	_label.text = ("총 옮기기  A/D 좌우  R/F 위아래  W/S 앞뒤   (Shift = 5배)\n"
		+ "총 돌리기  Q/E 총구 좌우  T/G 총구 위아래  Z/C 기울이기\n"
		+ "화면 위치  방향키 · PageUp/Down 멀리/가까이 · [ ] 좌우 돌리기\n"
		+ "Backspace 처음으로   Enter 저장\n\n"
		+ "총 위치 (mm)  x %+.0f  y %+.0f  z %+.0f\n" % [_gun_pos.x * 1000, _gun_pos.y * 1000, _gun_pos.z * 1000]
		+ "총 각도 (°)   위아래 %+.0f  좌우 %+.0f  기울임 %+.0f\n" % [_gun_rot.x, _gun_rot.y, _gun_rot.z]
		+ "화면 위치     (%.3f, %.3f, %.3f)  좌우 %.0f°  기울임 %.0f°" % [_vm_pos.x, _vm_pos.y, _vm_pos.z, _vm_rot.y, _vm_rot.z])


func _save() -> void:
	var line := "GRIP_TUNED gun_pos=%.3f,%.3f,%.3f gun_rot=%.1f,%.1f,%.1f vm_pos=%.3f,%.3f,%.3f vm_rot=%.1f,%.1f,%.1f" % [
		_gun_pos.x, _gun_pos.y, _gun_pos.z, _gun_rot.x, _gun_rot.y, _gun_rot.z,
		_vm_pos.x, _vm_pos.y, _vm_pos.z, _vm_rot.x, _vm_rot.y, _vm_rot.z]
	print(line)
	var f := FileAccess.open("user://grip_tuned.txt", FileAccess.WRITE)
	if f:
		f.store_line(line)
	_label.text += "\n\n저장했습니다 → Claude 에게 '저장했어' 라고 알려 주세요"

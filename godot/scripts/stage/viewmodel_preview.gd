# 1인칭 권총 미리보기 — 주인: A
# 팀 스테이지 맵(StageBuilderV2) 위를 초속 5m 로 달리며, 좀비가 나타나면 총이 그쪽으로 돌아가 쏘고,
# 탄약이 떨어지면 장전한다. ViewmodelMotion(시범 동작)을 B 가 확인하는 용도. 게임 코드가 아니다.
#
# 실행:  godot --path godot res://scenes/stage/viewmodel_preview.tscn
# 영상:  godot --path godot --write-movie out.avi --fixed-fps 30 res://scenes/stage/viewmodel_preview.tscn -- --seconds=24
extends Node3D

const RUN_SPEED := 5.0            # PRD F-01
const FIRE_GAP := 0.4             # PRD F-12 발사 간격
const AIM_CONE := deg_to_rad(30)  # PRD F-11 전방 60° (좌우 30°씩)
const AIM_RANGE := 30.0           # PRD F-11 30m
const CLIP := 6                   # 미리보기: 6발 쏘면 장전 (게임에서는 보급 상자를 주울 때)
const ZOMBIES := ["zombie_walker", "zombie_runner", "zombie_tank", "zombie_ambusher"]
const HITS := {"zombie_walker": 2, "zombie_runner": 2, "zombie_tank": 4, "zombie_ambusher": 2}

var _builder: StageBuilderV2
var _cam: Camera3D
var _vm: ViewmodelMotion
var _label: Label
var _dist := 0.0
var _t := 0.0
var _x := 0.0
var _ammo := CLIP
var _cool := 0.0
var _zombies: Array[Node3D] = []
var _next_spawn := 1.5
var _spawn_i := 0
var _seconds := 0.0

var BLOOD := preload("res://scenes/fx/hit_blood.tscn")
var MUZZLE := preload("res://scenes/fx/muzzle_flash.tscn")


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			_seconds = float(a.trim_prefix("--seconds="))
	_builder = StageBuilderV2.new()
	add_child(_builder)
	_builder.build()
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.fov = 60.0
	_cam.near = 0.05              # 총·손이 카메라 가까이 있어 잘리지 않게 (B 가 게임 카메라에서 정한다)
	_cam.far = 400.0
	add_child(_cam)
	_cam.make_current()
	_vm = ViewmodelMotion.new()
	_cam.add_child(_vm)
	_vm.reloaded.connect(func(): _ammo = CLIP; _say())
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(48, 32)
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_constant_override("outline_size", 8)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(_label)
	_say()
	var bgm := AudioStreamPlayer.new()
	bgm.stream = load("res://assets/audio/bgm_field.ogg")
	bgm.bus = &"BGM"
	add_child(bgm)
	bgm.play()


func _say(extra := "") -> void:
	_label.text = "%dm   탄약 %d / %d   %s" % [StageBuilderV2.remaining(_dist), _ammo, CLIP, extra]


func _process(delta: float) -> void:
	_t += delta
	_dist += RUN_SPEED * delta
	_builder.update_atmosphere(_dist)
	_x = move_toward(_x, _dodge_x(), 2.2 * delta)
	_cam.position = Vector3(_x, 1.6 + absf(sin(_t * TAU * 2.6)) * 0.04, -_dist)
	_spawn(delta)
	_move_zombies(delta)
	_shoot(delta)
	if _seconds > 0.0 and _t >= _seconds:
		get_tree().quit()


func _dodge_x() -> float:
	# 앞 18m 안의 장애물 옆으로 비켜 선다 (stage_preview 와 같은 방식)
	for ob in _builder.obstacles:
		var ahead: float = ob["z"] - _dist
		if ahead > -2.0 and ahead < 18.0:
			var clear: float = ob["half_width"] + 1.1
			if absf(_x - ob["x"]) < clear:
				var left: float = ob["x"] - clear
				var right: float = ob["x"] + clear
				return right if left < -5.5 else (left if right > 5.5 else (left if absf(_x - left) < absf(_x - right) else right))
			return _x
	return sin(_t * 0.35) * 1.2


func _spawn(delta: float) -> void:
	# 왼쪽·오른쪽·가운데에서 번갈아 나타난다 → 총이 그쪽으로 돌아가는 모습
	_next_spawn -= delta
	if _next_spawn > 0.0:
		return
	_next_spawn = 2.6
	var kind: String = ZOMBIES[_spawn_i % ZOMBIES.size()]
	var side: float = [-4.5, 4.0, -2.0, 3.0, 0.5][_spawn_i % 5]
	_spawn_i += 1
	var z: Node3D = (load("res://assets/models/%s.glb" % kind) as PackedScene).instantiate()
	add_child(z)
	z.position = Vector3(_x + side, 0, -_dist - 17.0)     # 안개·풀 너머로 사라지지 않게 17m 앞
	z.rotation.y = PI
	var ap: AnimationPlayer = z.find_children("*", "AnimationPlayer", true, false)[0]
	var walk := "run" if kind == "zombie_runner" else "walk"
	ap.get_animation(walk).loop_mode = Animation.LOOP_LINEAR
	ap.play(walk)
	z.set_meta("ap", ap)
	z.set_meta("walk", walk)
	z.set_meta("hp", HITS[kind])
	z.set_meta("speed", 3.0 if kind == "zombie_runner" else 1.0)
	_zombies.append(z)


func _move_zombies(delta: float) -> void:
	for z in _zombies.duplicate():
		if z.get_meta("hp") > 0:
			z.position.z += z.get_meta("speed") * delta
		if z.position.z > _cam.position.z + 3.0:          # 뒤로 지나가면 치운다
			_zombies.erase(z)
			z.queue_free()


func _target() -> Node3D:
	var best: Node3D = null
	var best_d := AIM_RANGE
	var fwd := -_cam.global_transform.basis.z
	for z in _zombies:
		if z.get_meta("hp") <= 0:
			continue
		var to: Vector3 = z.global_position + Vector3.UP * 1.3 - _cam.global_position
		var d := to.length()
		if d < best_d and fwd.angle_to(to) < AIM_CONE:
			best = z
			best_d = d
	return best


func _shoot(delta: float) -> void:
	_cool -= delta
	var z := _target()
	if z == null:
		_vm.clear_aim()
		return
	var chest := z.global_position + Vector3.UP * (1.7 if z.scene_file_path.contains("tank") else 1.3)
	_vm.aim_at(chest)
	if _vm.busy or _cool > 0.0 or (chest - _cam.global_position).length() > 22.0:
		return
	if _ammo <= 0:
		_vm.reload()
		_sfx("sfx_empty_click")
		_say("장전 중")
		return
	_cool = FIRE_GAP
	_ammo -= 1
	_vm.fire()
	var fx := MUZZLE.instantiate()
	_vm.muzzle.add_child(fx)
	fx.play()
	_sfx("sfx_pistol")
	var b := BLOOD.instantiate()
	add_child(b)
	b.global_position = chest
	b.look_at(_cam.global_position)
	b.play()
	var hp: int = z.get_meta("hp") - 1
	z.set_meta("hp", hp)
	var ap: AnimationPlayer = z.get_meta("ap")
	if hp <= 0:
		ap.play("death")
	else:
		ap.play("hit")
		ap.queue(z.get_meta("walk"))
	_say()


func _sfx(name: String) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/audio/%s.ogg" % name)
	p.bus = &"SFX"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

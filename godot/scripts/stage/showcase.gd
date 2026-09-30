# 시연 연출 — 스테이지 미리보기에 좀비·권총·보급·이펙트·HUD 를 얹어 "한 판처럼" 보여 준다 (A 확인용)
#
# ⚠️ 게임 코드가 아니다. 실제 좀비 AI·사격·보급·HUD 는 B·C 가 만든다 (TECH_SPEC 13.3).
#    여기서는 모든 에셋을 한 화면에 모아 분위기·크기·색·소리 타이밍을 확인하는 것이 목적이다.
# 사용: stage_preview 가 --showcase 인자를 받으면 이 노드를 붙이고 매 걸음 update() 를 부른다.
# 소리: 영상 프레임에는 소리가 없어서, 사건(총성·비명·줍기) 시각을 events.json 으로 남기고 ffmpeg 로 입힌다.
class_name ShowcaseDirector
extends Node3D

const UI_DIR := "res://../art/ui/icons/"      # 세권 님 HUD 아이콘 (art/ui, 게임 폴더 밖)
const MUZZLE := Vector3(0, 0.08, -0.166)       # weapon_pistol.glb 총구 위치 (PR #4)
const SHOOT_RANGE := 10.0                     # 이 거리 안에 들어온 좀비를 쏜다 (손 뻗고 다가오는 모습이 보이게 가까이)
const SHOT_GAP := 0.45                        # 연사 간격 (초)

const ZOMBIE_COUNT := 100                     # 스테이지(500m)에 100마리 (약 5m 마다 한 마리), 4종을 25마리씩 골고루
const KINDS := ["walker", "runner", "tank", "ambusher"]
const INFINITE_AMMO := false                  # true 면 총알 무한 (HUD 에 ∞) — 2026-09-30 플레이 테스트부터 끔
# 탄창 (2026-09-30 피드백): 시작 7발. 보급 상자를 먹으면 글록 한 정이 무작위로 나오고, 그 모델의 탄창 크기(최대 30발)가
# 새 탄창 크기가 된다. 받은 총알은 예비탄으로 쟁여 두고 R(폰 RELOAD)로 재장전한다 — 재장전은 시간이 걸린다
const START_MAG := 7                          # 시작 탄창 7발 (예비탄 0)
const GLOCKS := [["G43", 6], ["G26", 10], ["G19", 15], ["G17", 17], ["G17 확장탄창", 24], ["G18 롱탄창", 30]]   # [모델, 탄창]
const RELOAD_TIME := 1.5                      # 재장전 기본 시간 (초) + 탄창이 클수록 조금 더 (30발 = 2.1초)
const RELOAD_PER_ROUND := 0.02
# 초록 불빛 보급 (2026-09-30 추가): 하늘에서 초록 불을 뿜으며 낙하산으로 내려오고, 땅에 놓인 것 앞을 지나가면 총알 충전
const GREEN_AT := [60.0, 140.0, 220.0, 300.0, 410.0]   # 달린 거리 (500m 기준)
const DROP_AHEAD := 55.0                      # 이만큼 앞에서 떨어지기 시작 → 착지할 때 약 30m 앞 (PRD F-20: 40-60m 앞 착지에 가깝게)
const DROP_HEIGHT := 20.0
const DROP_SPEED := 4.0                       # 낙하 속도 (m/s)
const PICK_X := 2.3                           # 옆으로 이 거리 안을 지나가면 줍는다
const PICK_Z := 1.6
const SUPPLY_AT := [35.0, 200.0, 360.0, 520.0, 750.0, 900.0]    # 보급 상자 지점 (1000m 기준 → × StageBuilderV2.DS, PRD F-22)
# 이동 속도 (m/s) — 2026-09-30 "너무 정적": 무게·크기에 따라 강·중·약, 한 마리마다 범위 안에서 무작위
#   러너(가볍다) 강 / 워커·매복(보통) 중 / 탱커(무겁고 크다) 약 — 탱커는 가까워지면 돌진해 빨라진다
const SPEED := {"walker": [2.0, 3.0], "runner": [4.2, 5.6], "tank": [1.3, 1.9], "ambusher": [2.6, 3.6]}
const TANK_CHARGE := 1.8                      # 탱커 돌진 배율
const RUN_ANIM_FROM := 2.4                    # 이보다 빠르면 달리기 동작 (run 없는 탱커는 걷기를 빠르게)
const HOMING_LOCK := 3.0                      # 이만큼 가까워지면 더는 방향을 틀지 않는다 → 옆으로 비키면 피할 수 있다
const HP := {"walker": 1, "runner": 1, "tank": 2, "ambusher": 1}   # 탱커 4 → 2발 (2026-09-30 "너무 세다")

signal caught(zombie: Node3D)                 # 칼 없이 잡혔다 → 사망 연출 (stage_preview)
signal knifed                                 # 칼로 잡은 좀비를 죽이고 벗어났다

var events: Array = []                        # [시각, 소리 이름] — 영상에 소리 입힐 때 씀
var catching := false                         # 플레이 테스트: 좀비가 플레이어를 잡을 수 있다
# 잡힘 규칙 (2026-09-30): 좀비는 앞에서만 덮친다. 내 앞에서 몸을 절반 이상 가린 채 닿으면 잡힌다.
# 비켜서 스쳐 지나가면 그걸로 끝 — 뒤돌아 쫓아오거나 뒤에서 잡지 않는다
const REACH := 0.8                            # 앞뒤로 이만큼 붙으면 "닿음"
const ZOMBIE_W := 0.9                         # 좀비 몸+뻗은 팔 폭
const PLAYER_W := 0.7                         # 플레이어 몸 폭
const COVER_TO_GRAB := 0.5                    # 내 몸을 이만큼(절반) 이상 가리면 잡힘
const KNIVES := 1                             # 칼은 한 스테이지에 한 번 (PRD 칼 규칙)
var _knife_left := KNIVES
const KNIFE_GRACE := 1.5                      # 칼로 벗어난 직후 이 시간은 다시 잡히지 않는다 (연달아 잡히던 문제)
var _grace_t := 0.0
var _hud_knife: TextureRect
var auto_fire := true                         # 영상·통과 검사: 가까이 온 좀비를 알아서 쏜다 / 플레이 테스트: fire() 로 직접
var live_audio := false                       # 플레이 테스트: 소리를 실제로 낸다 (영상은 events.json 으로 나중에 입힌다)
const SFX_DB := -6.0                          # 효과음 절반 크기 (2026-09-30 "소리가 크다")
const BGM_DB := -12.0                         # 배경음도 절반 (-6 → -12)
const FIRE_RANGE := 30.0                      # 직접 쏠 때 닿는 거리
const AIM_WIDTH := 0.9                        # 화면 가운데 조준선에서 옆으로 이만큼(+거리 × 0.06) 안에 있으면 맞는다
var _builder: StageBuilderV2
var _camera: Camera3D
var _pistol: Node3D
var _zombies: Array = []                      # {node, ap, kind, hp, state, x, d, t}
var _crates: Array = []                       # {node, d, x, y, landed, taken, smoke}
var _plan: Array = []                         # [나타날 지점(달린 거리), 종류]
var _next_wave := 0
var _next_crate := 0
var _next_green := 0
var _mag := START_MAG                         # 탄창에 든 총알
var _mag_cap := START_MAG                     # 지금 총의 탄창 크기
var _reserve := 0                             # 예비탄
var _gun_name := "권총"
var _reload_left := 0.0                       # 재장전 남은 시간 (0 이면 재장전 중 아님)
var _reload_total := 0.0
var _pistol_rest := Vector3.ZERO
var _shot_cd := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _hud_layer: CanvasLayer
var _hud_ammo: Label
var _hud_reserve: Label
var _hud_gun: Label
var _hud_reload: ProgressBar
var _hud_pistol: TextureRect
var _hud_dist: Label
var _hud_bar: ProgressBar
var _tex_pistol: Texture2D
var _tex_pistol_empty: Texture2D


func setup(builder: StageBuilderV2, camera: Camera3D, hud_holder: Node) -> void:
	_builder = builder
	_camera = camera
	_rng.seed = 7
	var bag: Array = []
	for i in ZOMBIE_COUNT:
		bag.append(KINDS[i % KINDS.size()])
	for i in bag.size():                               # 섞되 같은 씨앗이면 늘 같은 순서
		var j := _rng.randi_range(i, bag.size() - 1)
		var t = bag[i]
		bag[i] = bag[j]
		bag[j] = t
	for i in ZOMBIE_COUNT:
		var gap := (StageBuilderV2.STAGE_LENGTH - 45.0) / ZOMBIE_COUNT
		_plan.append([25.0 + i * gap + _rng.randf_range(-0.3, 0.3) * gap, bag[i]])
	_pistol = load("res://assets/models/weapon_pistol.glb").instantiate()
	_pistol.position = Vector3(0.03, -0.2, -0.46)       # 1인칭: 화면 가운데 아래 (살짝 틀어 총 옆모습이 보이게)
	_pistol.rotation_degrees = Vector3(6, 14, -4)
	_pistol.scale = Vector3.ONE * 0.95
	_pistol_rest = _pistol.position
	camera.add_child(_pistol)
	_build_hud(hud_holder)


func _icon(name: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path(UI_DIR + name))
	return ImageTexture.create_from_image(img)


func _build_hud(holder: Node) -> void:
	var layer := CanvasLayer.new()
	holder.add_child(layer)
	_hud_layer = layer
	var w := 1560.0
	var panel := Panel.new()                           # 무기 표시 (PRD F-78): 최상단 가운데
	panel.position = Vector2(w / 2 - 150, 18)
	panel.size = Vector2(300, 62)
	panel.self_modulate = Color(0.12, 0.13, 0.14, 0.7)
	layer.add_child(panel)
	_tex_pistol = _icon("icon_pistol.png")
	_tex_pistol_empty = _icon("icon_pistol_empty.png")
	_hud_pistol = TextureRect.new()
	_hud_pistol.texture = _tex_pistol_empty
	_hud_pistol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hud_pistol.position = Vector2(10, 1)
	_hud_pistol.size = Vector2(60, 60)
	panel.add_child(_hud_pistol)
	_hud_ammo = Label.new()
	_hud_ammo.position = Vector2(78, 6)
	_hud_ammo.add_theme_font_size_override("font_size", 38)
	panel.add_child(_hud_ammo)
	_hud_reserve = Label.new()                         # 예비탄 "/ 24"
	_hud_reserve.position = Vector2(132, 18)
	_hud_reserve.add_theme_font_size_override("font_size", 24)
	_hud_reserve.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72))
	panel.add_child(_hud_reserve)
	_hud_gun = Label.new()                             # 지금 총 모델 (패널 아래)
	_hud_gun.position = Vector2(0, 64)
	_hud_gun.size = Vector2(300, 24)
	_hud_gun.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_gun.add_theme_font_size_override("font_size", 18)
	_hud_gun.add_theme_color_override("font_color", Color(0.8, 0.8, 0.76))
	panel.add_child(_hud_gun)
	_hud_reload = ProgressBar.new()                     # 재장전 막대 (화면 가운데 아래쪽, 재장전 중에만)
	_hud_reload.position = Vector2(w / 2 - 110, 470)
	_hud_reload.size = Vector2(220, 14)
	_hud_reload.show_percentage = false
	var rfill := StyleBoxFlat.new()
	rfill.bg_color = Color(0.9, 0.85, 0.7)
	_hud_reload.add_theme_stylebox_override("fill", rfill)
	_hud_reload.visible = false
	layer.add_child(_hud_reload)
	var rl := Label.new()
	rl.text = "재장전"
	rl.position = Vector2(0, -30)
	rl.size = Vector2(220, 28)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.add_theme_font_size_override("font_size", 22)
	_hud_reload.add_child(rl)
	var knife := TextureRect.new()
	knife.texture = _icon("icon_knife.png")
	knife.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	knife.position = Vector2(235, 4)
	knife.size = Vector2(55, 55)
	panel.add_child(knife)
	_hud_knife = knife
	var bar_bg := Panel.new()                          # 남은 거리 + 진행 막대 (PRD F-54)
	bar_bg.position = Vector2(w / 2 - 300, 110)
	bar_bg.size = Vector2(600, 70)
	bar_bg.self_modulate = Color(0.12, 0.13, 0.14, 0.6)
	layer.add_child(bar_bg)
	_hud_dist = Label.new()
	_hud_dist.position = Vector2(0, 2)
	_hud_dist.size = Vector2(600, 36)
	_hud_dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_dist.add_theme_font_size_override("font_size", 30)
	bar_bg.add_child(_hud_dist)
	_hud_bar = ProgressBar.new()
	_hud_bar.position = Vector2(18, 42)
	_hud_bar.size = Vector2(564, 16)
	_hud_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.78, 0.2, 0.16)
	_hud_bar.add_theme_stylebox_override("fill", fill)
	bar_bg.add_child(_hud_bar)
	_refresh_ammo()


func _refresh_ammo() -> void:
	if INFINITE_AMMO:
		_hud_ammo.text = "∞"
		_hud_pistol.texture = _tex_pistol
		return
	_hud_ammo.text = str(_mag)
	_hud_ammo.add_theme_color_override("font_color", Color(0.9, 0.25, 0.2) if _mag == 0 else Color(0.95, 0.95, 0.93))
	_hud_reserve.text = "/ %d" % _reserve
	_hud_gun.text = "%s · 탄창 %d발" % [_gun_name, _mag_cap]
	_hud_pistol.texture = _tex_pistol if _mag + _reserve > 0 else _tex_pistol_empty


# 재장전 (R 키 · RELOAD 버튼 · 빈 탄창으로 쏠 때): 시간이 걸리고 그동안 못 쏜다
func reload() -> void:
	if INFINITE_AMMO or _reload_left > 0.0 or _mag >= _mag_cap or _reserve <= 0:
		return
	_reload_total = RELOAD_TIME + RELOAD_PER_ROUND * _mag_cap
	_reload_left = _reload_total
	_hud_reload.visible = true
	_sfx("sfx_ui_click")                                 # 탄창 빼는 소리
	print("[reload] 시작 %.1f초 (탄창 %d / 예비 %d)" % [_reload_total, _mag, _reserve])


func _update_reload(delta: float) -> void:
	if _reload_left <= 0.0:
		_pistol.position = _pistol.position.lerp(_pistol_rest, minf(delta * 12.0, 1.0))
		_pistol.rotation_degrees.x = lerpf(_pistol.rotation_degrees.x, 6.0, minf(delta * 12.0, 1.0))
		return
	_reload_left -= delta
	var k := 1.0 - _reload_left / _reload_total
	_hud_reload.value = k * 100.0
	var dip := sin(clampf(k, 0.0, 1.0) * PI)            # 총을 아래로 내렸다가 (탄창 갈고) 다시 올린다
	_pistol.position = _pistol_rest + Vector3(0.02, -0.16, 0.05) * dip
	_pistol.rotation_degrees.x = 6.0 - 35.0 * dip
	if _reload_left <= 0.0:
		var take := mini(_mag_cap - _mag, _reserve)
		_mag += take
		_reserve -= take
		_hud_reload.visible = false
		_sfx("sfx_empty_click")                          # 슬라이드 당기는 소리
		_refresh_ammo()
		print("[reload] 끝 → 탄창 %d / 예비 %d" % [_mag, _reserve])


# 효과음 (stage_preview 가 부딪힘 소리에 쓴다)
func sfx(name: String) -> void:
	_sfx(name)


# 매 걸음: 달린 거리 dist, 카메라 x, 경과 시간
func update(dist: float, cam_x: float, delta: float) -> void:
	_time += delta
	_hud_dist.text = "%dm" % StageBuilderV2.remaining(dist)
	_hud_bar.value = dist / StageBuilderV2.STAGE_LENGTH * 100.0
	while _next_wave < _plan.size() and dist >= _plan[_next_wave][0] - 34.0:   # 34m 앞에서 나타난다
		_spawn_wave([_plan[_next_wave][0], _plan[_next_wave][1], 1], dist, cam_x)
		_next_wave += 1
	while _next_crate < SUPPLY_AT.size() and dist >= SUPPLY_AT[_next_crate] * StageBuilderV2.DS - DROP_AHEAD:
		_drop_crate(SUPPLY_AT[_next_crate] * StageBuilderV2.DS, false)
		_next_crate += 1
	while _next_green < GREEN_AT.size() and dist >= GREEN_AT[_next_green] - DROP_AHEAD:
		_drop_crate(GREEN_AT[_next_green], true)
		_next_green += 1
	_update_crates(dist, cam_x, delta)
	_update_zombies(dist, cam_x, delta)
	_shot_cd -= delta
	_grace_t -= delta
	_update_reload(delta)
	if auto_fire and _mag == 0 and _reserve > 0:
		reload()                                         # 영상·통과 검사: 빈 탄창이면 알아서 재장전


func _spawn_wave(w: Array, dist: float, cam_x: float) -> void:
	var kind: String = w[1]
	for i in int(w[2]):
		var z: Node3D = load("res://assets/models/zombie_%s.glb" % kind).instantiate()
		var ahead: float = float(w[0]) - dist + (0.0 if kind != "ambusher" else -12.0)   # 매복은 더 가까이 엎드려 있다
		var x := clampf(cam_x + _rng.randf_range(-3.5, 3.5), -4.5, 4.5)
		if kind == "runner":
			x = (-1.0 if _rng.randf() < 0.5 else 1.0) * _rng.randf_range(10.0, 14.0)   # 옆에서 대각선으로 (F-41)
		add_child(z)
		var ap: AnimationPlayer = z.find_children("*", "AnimationPlayer", true, false)[0]
		var e := {"node": z, "ap": ap, "kind": kind, "hp": HP[kind], "state": "move", "x": x, "d": dist + ahead + i * 1.8, "t": 0.0,
			"spd": _rng.randf_range(SPEED[kind][0], SPEED[kind][1])}
		if kind == "ambusher":
			ap.play("getup")                              # 풀숲에 엎드린 자세로 멈춰 둔다 (F-43)
			ap.seek(0.0, true)
			ap.pause()
			e["state"] = "lie"
		else:
			_move_anim(e, e["spd"])
			ap.seek(_rng.randf() * 0.8, true)             # 무리가 똑같이 걷지 않게 시작 시점을 흩뜨린다
		_zombies.append(e)
		_place(e)


# 속도에 맞는 동작: 빠르면 달리기, 느리면 걷기 — 재생 속도도 발이 미끄러져 보이지 않게 맞춘다
func _move_anim(e: Dictionary, spd: float) -> void:
	var ap: AnimationPlayer = e["ap"]
	if spd >= RUN_ANIM_FROM and ap.has_animation("run"):
		ap.play("run")
		ap.speed_scale = clampf(spd / 4.8, 0.55, 1.3)
	else:
		ap.play("walk")
		ap.speed_scale = clampf(spd / 1.2, 0.8, 2.2)


func _place(e: Dictionary) -> void:
	var z: Node3D = e["node"]
	z.position = Vector3(e["x"], 0, -e["d"])
	var to_cam := _camera.global_position - z.global_position
	z.rotation.y = atan2(-to_cam.x, -to_cam.z)            # 정면(-Z)이 카메라를 본다 → 손 뻗고 다가온다


func _update_zombies(dist: float, cam_x: float, delta: float) -> void:
	for e in _zombies:
		if not is_instance_valid(e["node"]):
			continue
		var z: Node3D = e["node"]
		var ahead: float = e["d"] - dist
		var ap: AnimationPlayer = e["ap"]
		e["t"] += delta
		match e["state"]:
			"lie":
				if ahead < 9.0:                            # 8m 안에 들어오면 일어난다 (F-43)
					e["state"] = "getup"
					e["t"] = 0.0
					ap.play("getup")
					_sfx("sfx_zombie_scream")
			"getup":
				if e["t"] > ap.current_animation_length * 0.9:
					e["state"] = "move"
					_move_anim(e, e["spd"])
			"move":
				var spd: float = e["spd"]
				if e["kind"] == "tank" and ahead < 16.0 and not e.get("charging", false):   # 탱커 돌진 (PRD F-42, WU-20b)
					e["charging"] = true
					_move_anim(e, spd * TANK_CHARGE)
					_sfx("sfx_zombie_groan")
				if e.get("charging", false):
					spd *= TANK_CHARGE
				if e.get("passed", false):                 # 지나친 좀비: 더는 쫓지 않고 가던 방향으로 계속 간다 (뒤돌지 않는다)
					var dir: Vector2 = e.get("dir", Vector2(0, -1))
					e["x"] += dir.x * spd * delta
					e["d"] += dir.y * spd * delta
					z.position = Vector3(e["x"], 0, -e["d"])
					if ahead < -10.0:
						z.queue_free()
					continue
				if ahead > HOMING_LOCK or not e.has("dir"):  # 멀리서는 나를 향해 방향을 튼다. 가까워지면 그 방향 그대로 (비키면 피한다)
					var target := Vector2(cam_x, dist)
					var here := Vector2(e["x"], e["d"])
					e["dir"] = (target - here).normalized()
				var step: Vector2 = e["dir"] * spd * delta
				e["x"] += step.x
				e["d"] += step.y
				_place(e)
				ahead = e["d"] - dist
				if ahead < REACH and ahead > 0.05:          # 내 앞에서 닿음 → 몸을 절반 이상 가리면 잡힌다
					var dx := absf(e["x"] - cam_x)
					var cover := clampf((ZOMBIE_W * 0.5 + PLAYER_W * 0.5 - dx) / PLAYER_W, 0.0, 1.0)
					if catching and cover >= COVER_TO_GRAB and _grace_t <= 0.0:
						_grab(e, dist, cam_x)
						continue
					if cover <= 0.0:
						e["passed"] = true                 # 비켜서 스쳐 지나감
				elif ahead <= 0.05:
					e["passed"] = true                     # 옆·뒤로 넘어갔다 → 끝 (뒤에서는 잡지 않는다)
				if auto_fire and ahead < SHOOT_RANGE and ahead > 1.5 and (_mag > 0 or INFINITE_AMMO) and _reload_left <= 0.0 and _shot_cd <= 0.0:
					_shoot(e)
			"dead":
				if ahead < -4.0:
					z.queue_free()
			"grab":
				pass                                       # 사망 연출 중: 제자리에서 물어뜯는다


# 잡혔다: 칼이 남았으면 칼로 죽이고 벗어난다, 없으면 사망 (stage_preview 가 카메라 연출)
func _grab(e: Dictionary, dist: float, cam_x: float) -> void:
	var z: Node3D = e["node"]
	var ap: AnimationPlayer = e["ap"]
	ap.speed_scale = 1.0
	if _knife_left > 0:
		_knife_left -= 1
		if _hud_knife:
			_hud_knife.modulate = Color(1, 1, 1, 0.2)      # 칼 다 씀
		_sfx("sfx_knife")
		BulletHitFX.spawn(self, z.global_position + Vector3(0, 1.3, 0), z.global_position - _camera.global_position, 1.6)
		e["state"] = "dead"
		e["passed"] = true
		ap.play("death")
		_grace_t = KNIFE_GRACE
		print("[knife] %.0fm 칼로 벗어남" % dist)
		knifed.emit()
		return
	e["state"] = "grab"
	e["d"] = dist + (1.6 if e["kind"] == "tank" else 1.15)   # 코앞에 붙는다 (너무 붙으면 몸통만 화면을 덮는다 — 큰 탱커는 조금 떨어져)
	_pistol.visible = false                                # 쓰러질 때 총이 허공에 떠 보이지 않게
	_hud_layer.visible = false                             # 사망 연출에는 HUD 를 치운다 (블랙아웃 + DEAD 만)
	e["x"] = cam_x
	_place(e)
	if ap.has_animation("attack"):
		ap.get_animation("attack").loop_mode = Animation.LOOP_LINEAR
		ap.play("attack")
	_sfx("sfx_bite")
	print("[caught] %.0fm %s 에게 잡힘 (칼 없음)" % [dist, e["kind"]])
	caught.emit(z)


# 플레이 테스트 사격 (스페이스바·FIRE 버튼): 화면 가운데 조준선 앞의 가장 가까운 좀비를 쏜다. 없으면 허공에 쏜다
func fire() -> void:
	if _shot_cd > 0.0 or _reload_left > 0.0:
		return
	if _mag <= 0 and not INFINITE_AMMO:
		_shot_cd = 0.3
		if _reserve > 0:
			reload()                                     # 빈 탄창으로 쏘면 저절로 재장전
		else:
			_sfx("sfx_empty_click")                      # 빈 총 소리 (예비탄도 없음)
		return
	var cam := _camera.global_position
	var best: Dictionary = {}
	var best_d := INF
	for e in _zombies:
		if not is_instance_valid(e["node"]) or e["state"] == "dead":
			continue
		var rel: Vector3 = (e["node"] as Node3D).global_position - cam
		var ahead := -rel.z
		if ahead < 1.0 or ahead > FIRE_RANGE:
			continue
		if absf(rel.x) < AIM_WIDTH + ahead * 0.06 and ahead < best_d:
			best_d = ahead
			best = e
	_shoot(best)


func _sfx(name: String) -> void:
	events.append([_time, name])
	if not live_audio:
		return
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/audio/%s.ogg" % name)
	p.volume_db = SFX_DB
	if AudioServer.get_bus_index("SFX") >= 0:
		p.bus = "SFX"
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# 배경음 (플레이 테스트)
func start_bgm() -> void:
	var p := AudioStreamPlayer.new()
	var st: AudioStream = load("res://assets/audio/bgm_field.ogg")
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	p.stream = st
	p.volume_db = BGM_DB
	if AudioServer.get_bus_index("BGM") >= 0:
		p.bus = "BGM"
	add_child(p)
	p.play()


func _shoot(e: Dictionary) -> void:
	_shot_cd = SHOT_GAP
	if not INFINITE_AMMO:
		_mag -= 1
	_refresh_ammo()
	_sfx("sfx_pistol")
	var flash: Node3D = load("res://scenes/fx/muzzle_flash.tscn").instantiate()
	_pistol.add_child(flash)
	flash.position = MUZZLE
	flash.play()
	if e.is_empty():
		return                                            # 빗나감 (조준선 앞에 좀비 없음)
	var z: Node3D = e["node"]
	# 착탄 섬광·불똥 + 핏방울·피 안개 (엔진에서 만든 이펙트, scenes/fx/bullet_hit.gd)
	var hit_at := z.global_position + Vector3(_rng.randf_range(-0.12, 0.12), (1.35 if e["kind"] != "tank" else 1.75) + _rng.randf_range(-0.15, 0.15), 0)
	BulletHitFX.spawn(self, hit_at, hit_at - _camera.global_position, 1.3 if e["kind"] == "tank" else 1.0)
	e["hp"] -= 1
	if e["hp"] <= 0:
		e["state"] = "dead"
		e["ap"].speed_scale = 1.0
		e["ap"].play("death")


func _drop_crate(d: float, green: bool) -> void:
	var c: Node3D = load("res://assets/models/prop_supply_crate.glb").instantiate()
	add_child(c)
	var x := _free_x(d)
	var e := {"node": c, "d": d, "x": x, "y": DROP_HEIGHT, "landed": false, "taken": false, "green": green, "smoke": null}
	c.position = Vector3(x, DROP_HEIGHT, -d)
	if green:                                             # 초록 불빛: 떨어지는 동안부터 뿜는다 (멀리서도 보이게)
		var fx: Node3D = load("res://scenes/fx/smoke_green.tscn").instantiate()
		c.add_child(fx)
		fx.play(60.0)
		e["smoke"] = fx
	_crates.append(e)


# 차·소품이 없는 자리에 떨어뜨린다 (상자가 차 속에 박히지 않게)
func _free_x(d: float) -> float:
	var picks: Array = []
	var x := -4.5
	while x <= 4.5:
		var ok := true
		for ob in _builder.obstacles:
			if absf(ob["z"] - d) < ob.get("half_depth", 1.0) + 1.5 and absf(ob["x"] - x) < ob["half_width"] + 1.0:
				ok = false
				break
		if ok:
			picks.append(x)
		x += 0.5
	return picks[_rng.randi() % picks.size()] if not picks.is_empty() else 0.0


func _update_crates(dist: float, cam_x: float, delta: float) -> void:
	for c in _crates:
		if c["taken"] or not is_instance_valid(c["node"]):
			continue                                    # 주운 상자는 지워졌으니 건드리지 않는다
		var n: Node3D = c["node"]
		if not c["landed"]:
			c["y"] = maxf(0.0, c["y"] - DROP_SPEED * delta)   # 낙하산으로 천천히 내려온다
			n.position.y = c["y"]
			n.rotation.y += delta * 0.4
			if c["y"] <= 0.0:
				c["landed"] = true
				var chute := n.find_child("Parachute", true, false)
				if chute:
					chute.visible = false                  # 착지하면 낙하산만 숨긴다 (TECH_SPEC 13.3.1)
				if not c["green"]:
					var smoke: Node3D = load("res://scenes/fx/smoke_red.tscn").instantiate()
					n.add_child(smoke)
					smoke.play()
					c["smoke"] = smoke
		# 땅에 놓인 상자 앞(옆 PICK_X 안)을 지나가면 줍는다 → 글록 한 정 (탄창 크기 무작위). 멀리 비켜 가면 못 줍는다
		elif absf(c["d"] - dist) < PICK_Z and absf(c["x"] - cam_x) < PICK_X:
			c["taken"] = true
			_pick_glock()
			_sfx("sfx_supply_pickup")
			print("[supply] %s %.0fm 줍기 → %s 탄창 %d / 예비 %d" % ["초록" if c["green"] else "빨강", c["d"], _gun_name, _mag, _reserve])
			n.queue_free()


# 보급 글록: 그 모델로 바꿔 든다. 탄창 크기가 바뀌고, 탄창 하나 분량이 예비탄으로 들어온다
# (지금 탄창에 새 탄창보다 많이 들어 있으면 넘치는 만큼은 예비탄으로)
func _pick_glock() -> void:
	var g: Array = GLOCKS[_rng.randi() % GLOCKS.size()]
	_gun_name = g[0]
	_mag_cap = g[1]
	if _mag > _mag_cap:
		_reserve += _mag - _mag_cap
		_mag = _mag_cap
	_reserve += _mag_cap
	_refresh_ammo()


# 자동 달리기(영상·통과 검사)용: 앞 25m 안에 땅에 놓인 상자가 있으면 그 x (없으면 NAN)
func crate_x(dist: float) -> float:
	for c in _crates:
		if c["landed"] and not c["taken"] and is_instance_valid(c["node"]) and c["d"] - dist > 0.5 and c["d"] - dist < 25.0:
			return c["x"]
	return NAN

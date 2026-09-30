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

const FIRST_ZOMBIE := 70.0                    # 첫 좀비 지점 (2026-09-30 "초반에 좀 더 걷다가") — 25 → 70m, 약 7초 걷고 나서 멀리 보인다
const INTRO_SAFE := 3                         # 처음 이만큼은 풀숲에 엎드린 매복을 넣지 않는다 (안 보이다 갑자기 튀어나와 잡던 문제)
const ZOMBIE_COUNT := 150                     # 스테이지(750m)에 150마리 (약 4.4m 마다 한 마리 — 500m·100마리 때 밀도), 4종을 골고루
const SPAWN_AHEAD := 36.0                     # 이만큼 앞에서 나타난다 (달빛 테두리로 멀리서도 보인다)
const KINDS := ["walker", "runner", "tank", "ambusher"]
const INFINITE_AMMO := false                  # true 면 총알 무한 (HUD 에 ∞) — 2026-09-30 플레이 테스트부터 끔
# 탄창 (2026-09-30 피드백): 시작 7발. 보급 상자를 먹으면 글록 한 정이 무작위로 나오고, 그 모델의 탄창 크기(최대 30발)가
# 새 탄창 크기가 된다. 받은 총알은 예비탄으로 쟁여 두고 R(폰 RELOAD)로 재장전한다 — 재장전은 시간이 걸린다
const LINE_W := 200.0                         # 진행 실선 길이 (px) — 왼쪽 위 거리 숫자 아래
const HUD_WHITE := Color(0.96, 0.95, 0.93)    # HUD 흰색 (살짝 따뜻한 흰색 — 순백은 노을 화면에서 튄다)
const START_MAG := 7                          # 시작 탄창 7발 (예비탄 0)
const GLOCKS := [["G43", 6], ["G26", 10], ["G19", 15], ["G17", 17], ["G17 확장탄창", 24], ["G18 롱탄창", 30]]   # [모델, 탄창]
const RELOAD_TIME := 1.5                      # 재장전 기본 시간 (초) + 탄창이 클수록 조금 더 (30발 = 2.1초)
const RELOAD_PER_ROUND := 0.02
# 보급 계획 (2026-09-30 "보급이 너무 많다" 11개 → 9개, 약 20% 줄임): [달린 거리(750m 기준), 초록?] — 빨강·초록을 번갈아 약 80m 간격
# 초록 불빛 보급은 하늘에서 초록 불을 뿜으며 내려온다. 강·다리(510-530m) 위에는 떨어뜨리지 않는다
const SUPPLY_PLAN := [[26.0, false], [105.0, true], [185.0, false], [265.0, true], [345.0, false], [425.0, true], [480.0, false], [590.0, true], [675.0, false]]
const DROP_AHEAD := 55.0                      # 이만큼 앞에서 떨어지기 시작 → 착지할 때 약 30m 앞 (PRD F-20: 40-60m 앞 착지에 가깝게)
const DROP_HEIGHT := 20.0
const DROP_SPEED := 4.0                       # 낙하 속도 (m/s)
const PICK_X := 2.3                           # 옆으로 이 거리 안을 지나가면 줍는다
const PICK_Z := 1.6
# 좀비 행동 (2026-09-30 "액션·스피드·모션을 다양하게"): 모델 4종은 그대로, 한 마리마다 행동 스타일을 무작위로 고른다
#   shamble 비틀비틀 걷기 / jog 뛰어오기 / sprint 전력 질주 / idle 서 있다가 가까워지면 출발 / crawl 기어 오기
#   crawl_run 빠르게 기어 오기 / rise 누워 있다가 일어나 달려오기 / stomp 탱커(가까워지면 포효 후 돌진)
#   무게·크기에 따라 강·중·약: 러너(가볍다) 빠른 스타일 위주, 워커·매복(보통) 중간, 탱커(무겁다) 느림
const STYLES := {
	"walker": [["shamble", 40], ["jog", 25], ["idle", 15], ["crawl", 20]],
	"runner": [["sprint", 50], ["jog", 25], ["crawl_run", 25]],
	"tank": [["stomp", 100]],
	"ambusher": [["rise", 55], ["jog", 25], ["crawl", 20]],
}
const STYLE_SPEED := {"shamble": [1.6, 2.6], "jog": [2.6, 3.8], "sprint": [4.2, 5.8], "idle": [1.8, 3.2], "crawl": [0.9, 1.4],
	"crawl_run": [2.2, 3.2], "rise": [3.8, 5.0], "stomp": [1.3, 1.9], "event": [5.4, 6.6]}
const TANK_CHARGE := 1.8                      # 탱커 돌진 배율
const RISE_AT := 28.0                         # 누운 좀비가 일어나기 시작하는 거리 (일어나는 데 약 2.7초 — 멀리서 보인다)
const IDLE_WAKE := [13.0, 20.0]               # 서 있던 좀비가 출발하는 거리
# 사이드 질주 이벤트 (2026-09-30): 가끔 빠른 좀비 2-3마리가 양옆 멀리서 먼저 비명을 질러 알리고 대각선으로 달려든다
const EVENT_FROM := 130.0                     # 첫 이벤트 지점
const EVENT_GAP := [70.0, 110.0]              # 이벤트 사이 거리
const EVENT_AHEAD := 38.0                     # 이만큼 앞, 옆으로 8-11m 떨어진 곳에서 나타난다 (갑자기 튀어나오지 않게)
const SCREAM_TIME := 0.9                      # 달려들기 전에 비명을 지르며 멈춰 있는 시간
# 동작 팩 (Scary Zombie Pack, Mixamo): 동작만 담은 파일 하나를 4종 모두에 입힌다 (tools/assets/pack_zombie_anims.py)
const ANIM_PACK := "res://assets/models/zombie_anims.glb"
const PACK_HIPS := 96.29514                   # 팩 뼈대의 엉덩이 높이 (뼈대 좌표, cm) — 좀비마다 키 비율로 맞춘다
const PACK_LOOPS := ["p_walk", "p_run", "p_crawl", "p_crawl_run", "p_idle", "p_bite", "p_bite2", "p_neck_bite", "p_attack"]
const GRAB_ANIMS := ["attack", "pack/p_attack", "pack/p_bite", "pack/p_bite2", "pack/p_neck_bite"]
const DEATH_ANIMS := ["death", "pack/p_death", "pack/p_dying"]
const BLEND := 0.25                           # 동작이 바뀔 때 섞는 시간 (초) — 뚝 바뀌면 몸이 순간 튀어 끊겨 보인다 (2026-09-30)
const HOMING_LOCK := 3.0                      # 이만큼 가까워지면 더는 방향을 틀지 않는다 → 옆으로 비키면 피할 수 있다
const HP := {"walker": 1, "runner": 1, "tank": 2, "ambusher": 1}   # 탱커 4 → 2발 (2026-09-30 "너무 세다")

signal caught(zombie: Node3D)                 # 칼 없이 잡혔다 → 사망 연출 (stage_preview)
signal knifed                                 # 칼로 잡은 좀비를 죽이고 벗어났다
signal tripped                                # 기는 좀비가 발목을 잡았다 → 잠깐 휘청 (풀에 묻혀 안 보이니 죽이지는 않는다)

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
const SFX_DB := -7.94                         # 효과음: 절반(-6dB) → 거기서 20% 더 줄임(×0.8 = -1.94dB) (2026-09-30 "아직 크다")
const BGM_DB := -13.94                        # 배경음도 같은 비율로 (-12 → -13.94)
const SFX_TRIM := {"sfx_pistol": -6.02}       # 소리별 추가 조정 (dB): 총소리만 절반 더 (×0.5 = -6.02dB, 2026-09-30 "총소리가 크다")
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
var _next_event := EVENT_FROM
static var _libs := {}                        # 종류 → 동작 라이브러리 (한 번만 만든다)
static var _pack: AnimationPlayer
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
var _hud_bullets: Control
var _hud_reserve: Label
var _hud_gun: Label
var _hud_pistol: TextureRect
var _hud_dist: Label
var _hud_line_done: ColorRect                 # 진행 실선: 지나온 쪽 (조금 밝게)
var _hud_tick: ColorRect                      # 진행 작대기
var _gun_toast_t := 0.0
var _tex_pistol: Texture2D


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
	_intro_order(bag)
	_next_event = EVENT_FROM + _rng.randf_range(0.0, 20.0)
	for i in ZOMBIE_COUNT:
		var gap := (StageBuilderV2.STAGE_LENGTH - 20.0 - FIRST_ZOMBIE) / ZOMBIE_COUNT
		_plan.append([FIRST_ZOMBIE + i * gap + _rng.randf_range(-0.3, 0.3) * gap, bag[i]])
	_prewarm()
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
	# HUD (2026-09-30 "인투더데드2 처럼 깔끔한 흰색"): 어두운 상자 없이 흰색만. 가운데 위 = 장전된 총알 줄 | 예비탄,
	# 그 아래 = 권총·칼 흰 실루엣. 왼쪽 위 = 남은 거리(m) + 바로 아래 진행 실선. 굵고 좁은 글꼴 하나로 통일
	var heavy := SystemFont.new()
	heavy.font_names = PackedStringArray(["Impact", "Arial Narrow", "Arial Black", "Roboto Condensed", "sans-serif"])
	heavy.font_weight = 800
	_hud_bullets = Control.new()                       # 총알 줄 (쏠 때마다 하나씩 사라진다 — _draw_bullets)
	_hud_bullets.position = Vector2(w / 2 - 250, 22)
	_hud_bullets.size = Vector2(500, 44)
	_hud_bullets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_bullets.draw.connect(_draw_bullets)
	layer.add_child(_hud_bullets)
	_hud_reserve = Label.new()                         # 예비탄 숫자 (총알 줄 오른쪽, 세로줄 뒤)
	_hud_reserve.add_theme_font_override("font", heavy)
	_hud_reserve.add_theme_font_size_override("font_size", 50)
	_white_label(_hud_reserve)
	layer.add_child(_hud_reserve)
	_tex_pistol = _white_icon("icon_pistol.png")
	_hud_pistol = TextureRect.new()
	_hud_pistol.texture = _tex_pistol
	_hud_pistol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hud_pistol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hud_pistol.position = Vector2(w / 2 - 70, 72)
	_hud_pistol.size = Vector2(76, 54)
	layer.add_child(_hud_pistol)
	var knife := TextureRect.new()
	knife.texture = _white_icon("icon_knife.png")
	knife.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	knife.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	knife.position = Vector2(w / 2 + 22, 76)
	knife.size = Vector2(50, 46)
	layer.add_child(knife)
	_hud_knife = knife
	_hud_gun = Label.new()                             # 새 총을 주웠을 때만 잠깐 뜬다 (무기 아이콘 아래)
	_hud_gun.position = Vector2(w / 2 - 150, 128)
	_hud_gun.size = Vector2(300, 28)
	_hud_gun.modulate.a = 0.0
	_hud_gun.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_gun.add_theme_font_size_override("font_size", 20)
	_white_label(_hud_gun)
	layer.add_child(_hud_gun)
	# 남은 거리 (m): 왼쪽 위
	_hud_dist = Label.new()
	_hud_dist.position = Vector2(44, 14)
	_hud_dist.add_theme_font_override("font", heavy)
	_hud_dist.add_theme_font_size_override("font_size", 66)
	_white_label(_hud_dist)
	layer.add_child(_hud_dist)
	# 진행: 거리 숫자 바로 아래 가는 실선 + 작대기
	var line := ColorRect.new()
	line.position = Vector2(48, 98)
	line.size = Vector2(LINE_W, 2)
	line.color = Color(1, 1, 1, 0.3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(line)
	_hud_line_done = ColorRect.new()
	_hud_line_done.size = Vector2(0, 2)
	_hud_line_done.color = Color(1, 1, 1, 0.75)
	line.add_child(_hud_line_done)
	_hud_tick = ColorRect.new()
	_hud_tick.size = Vector2(3, 14)
	_hud_tick.position = Vector2(-1.5, -6)
	_hud_tick.color = Color(1, 1, 1, 0.95)
	line.add_child(_hud_tick)
	_refresh_ammo()


func _refresh_ammo() -> void:
	_hud_bullets.queue_redraw()
	_hud_reserve.text = "∞" if INFINITE_AMMO else str(_reserve)
	var row_w := _bullet_row_width(_mag_cap)
	_hud_reserve.position = Vector2(_hud_bullets.position.x + (_hud_bullets.size.x + row_w) * 0.5 + 18, 8)
	_hud_gun.text = "%s  %d발 탄창" % [_gun_name, _mag_cap]
	_hud_pistol.modulate.a = 1.0 if (_mag + _reserve > 0 or INFINITE_AMMO) else 0.3   # 총알이 하나도 없으면 흐리게


# 총알 줄: 탄창 크기가 클수록 촘촘하게 (6발 = 굵게, 30발 = 가늘게)
func _bullet_dims(cap: int) -> Vector2:
	return Vector2(10.0, 34.0) if cap <= 12 else (Vector2(8.0, 30.0) if cap <= 20 else Vector2(6.0, 26.0))


func _bullet_row_width(cap: int) -> float:
	var d := _bullet_dims(cap)
	return cap * (d.x + d.x * 0.55) - d.x * 0.55


# 장전된 총알만 그린다 (쏘면 하나씩 사라진다). 재장전 중에는 하나씩 다시 채워진다
func _draw_bullets() -> void:
	var shown := _mag
	if _reload_left > 0.0:
		var take := mini(_mag_cap - _mag, _reserve)
		shown = _mag + int(take * clampf(1.0 - _reload_left / _reload_total, 0.0, 1.0))
	var d := _bullet_dims(_mag_cap)
	var gap := d.x * 0.55
	var row_w := _bullet_row_width(_mag_cap)
	var x0 := (_hud_bullets.size.x - row_w) * 0.5
	var y0 := (_hud_bullets.size.y - d.y) * 0.5
	for i in shown:
		var x := x0 + i * (d.x + gap)
		_bullet_shape(Vector2(x + 2, y0 + 2), d, Color(0, 0, 0, 0.35))   # 그림자
		_bullet_shape(Vector2(x, y0), d, HUD_WHITE)
	var bar_x := x0 + row_w + 9.0                        # 예비탄 앞 가는 세로줄
	_hud_bullets.draw_rect(Rect2(bar_x, y0 - 2, 2, d.y + 4), Color(1, 1, 1, 0.55))


# 총알 하나: 둥근 탄두 + 탄피, 사이에 가는 홈 한 줄
func _bullet_shape(at: Vector2, d: Vector2, c: Color) -> void:
	var r := d.x * 0.5
	var tip_h := d.y * 0.36
	_hud_bullets.draw_circle(at + Vector2(r, r), r, c)
	_hud_bullets.draw_rect(Rect2(at + Vector2(0, r), Vector2(d.x, tip_h - r)), c)
	_hud_bullets.draw_rect(Rect2(at + Vector2(0, tip_h + 1.5), Vector2(d.x, d.y - tip_h - 1.5)), c)


func _white_label(l: Label) -> void:
	l.add_theme_color_override("font_color", HUD_WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)


# 아이콘을 흰 실루엣으로 (모양은 그대로, 색만 흰색)
func _white_icon(name: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path(UI_DIR + name))
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			img.set_pixel(x, y, Color(HUD_WHITE.r, HUD_WHITE.g, HUD_WHITE.b, a))
	return ImageTexture.create_from_image(img)


# 재장전 (탄창이 비면 저절로 · R 키 · RELOAD 버튼): 시간이 걸리고 그동안 못 쏜다
func reload() -> void:
	if INFINITE_AMMO or _reload_left > 0.0 or _mag >= _mag_cap or _reserve <= 0:
		return
	_reload_total = RELOAD_TIME + RELOAD_PER_ROUND * _mag_cap
	_reload_left = _reload_total
	_refresh_ammo()
	_sfx("sfx_ui_click")                                 # 탄창 빼는 소리
	print("[reload] 시작 %.1f초 (탄창 %d / 예비 %d)" % [_reload_total, _mag, _reserve])


func _update_reload(delta: float) -> void:
	if _reload_left <= 0.0:
		_pistol.position = _pistol.position.lerp(_pistol_rest, minf(delta * 12.0, 1.0))
		_pistol.rotation_degrees.x = lerpf(_pistol.rotation_degrees.x, 6.0, minf(delta * 12.0, 1.0))
		return
	_reload_left -= delta
	_hud_bullets.queue_redraw()
	var k := 1.0 - _reload_left / _reload_total
	var dip := sin(clampf(k, 0.0, 1.0) * PI)            # 총을 아래로 내렸다가 (탄창 갈고) 다시 올린다
	_pistol.position = _pistol_rest + Vector3(0.02, -0.16, 0.05) * dip
	_pistol.rotation_degrees.x = 6.0 - 35.0 * dip
	if _reload_left <= 0.0:
		var take := mini(_mag_cap - _mag, _reserve)
		_mag += take
		_reserve -= take
		_sfx("sfx_empty_click")                          # 슬라이드 당기는 소리
		_refresh_ammo()
		print("[reload] 끝 → 탄창 %d / 예비 %d" % [_mag, _reserve])


# 효과음 (stage_preview 가 부딪힘 소리에 쓴다)
func sfx(name: String) -> void:
	_sfx(name)


# 매 걸음: 달린 거리 dist, 카메라 x, 경과 시간
func update(dist: float, cam_x: float, delta: float) -> void:
	_time += delta
	if _warm and _time > 0.3:                              # 미리 그리기 끝: 풀 좀비는 숨겨서 남기고 나머지는 지운다
		for kind in _pool:
			for z in _pool[kind]:
				z.reparent(self, false)
				z.visible = false
				z.position = Vector3(0, -50, 0)
				(z.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).stop()
		_warm.queue_free()
		_warm = null
	elif _warm:
		_warm.position = Vector3(cam_x, -2.2, -dist - 14.0)   # 카메라를 따라가며 화면 안(땅 밑)에 둔다
	_hud_dist.text = "%dm" % StageBuilderV2.remaining(dist)
	var k := clampf(dist / StageBuilderV2.STAGE_LENGTH, 0.0, 1.0)
	_hud_line_done.size.x = LINE_W * k
	_hud_tick.position.x = LINE_W * k - 1.5
	_gun_toast_t -= delta
	_hud_gun.modulate.a = clampf(_gun_toast_t / 0.5, 0.0, 1.0)   # 2.5초 떠 있다가 마지막 0.5초에 사라진다
	while _next_wave < _plan.size() and dist >= _plan[_next_wave][0] - SPAWN_AHEAD:
		_spawn(_plan[_next_wave][1], "", _plan[_next_wave][0] - dist, NAN, dist, cam_x)
		_next_wave += 1
	if dist >= _next_event and dist < StageBuilderV2.STAGE_LENGTH - 60.0:
		_sprint_event(dist, cam_x)
		_next_event += _rng.randf_range(EVENT_GAP[0], EVENT_GAP[1])
	while _next_crate < SUPPLY_PLAN.size() and dist >= SUPPLY_PLAN[_next_crate][0] * StageBuilderV2.STAGE_LENGTH / 750.0 - DROP_AHEAD:
		_drop_crate(SUPPLY_PLAN[_next_crate][0] * StageBuilderV2.STAGE_LENGTH / 750.0, SUPPLY_PLAN[_next_crate][1])
		_next_crate += 1
	_update_crates(dist, cam_x, delta)
	_update_zombies(dist, cam_x, delta)
	_shot_cd -= delta
	_grace_t -= delta
	_update_reload(delta)
	if _mag == 0 and _reserve > 0:
		reload()                                         # 탄창이 비고 예비탄이 있으면 저절로 재장전 (2026-09-30 피드백 — 게이지 없이 총을 내렸다 올리는 동작만)


# 좀비 한 마리: kind 모델, style 행동 (비우면 무작위), ahead 앞 거리, x 가로 위치 (NAN 이면 내 근처 무작위)
func _spawn(kind: String, style: String, ahead: float, x: float, dist: float, cam_x: float) -> Dictionary:
	if style.is_empty():
		style = _pick_style(kind)
	var z := _take(kind)
	var ap: AnimationPlayer = z.find_children("*", "AnimationPlayer", true, false)[0]
	for n in ["walk", "run", "idle"]:                    # 가져온 동작은 한 번만 재생하고 멈춘다 → 반복으로 (굳은 채 미끄러져 오던 버그)
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if is_nan(x):
		x = clampf(cam_x + _rng.randf_range(-3.5, 3.5), -4.5, 4.5)
		if style == "sprint":
			x = (-1.0 if _rng.randf() < 0.5 else 1.0) * _rng.randf_range(9.0, 12.0)   # 옆에서 대각선으로 (F-41)
	var e := {"node": z, "ap": ap, "kind": kind, "style": style, "hp": HP[kind], "state": "move", "x": x, "d": dist + ahead, "t": 0.0,
		"spd": _rng.randf_range(STYLE_SPEED[style][0], STYLE_SPEED[style][1]), "low": style.begins_with("crawl")}
	e["walk"] = "walk" if _rng.randf() < 0.5 else "pack/p_walk"       # 같은 스타일이라도 걸음걸이·뛰는 폼을 섞는다
	e["run"] = "run" if ap.has_animation("run") and _rng.randf() < 0.5 else "pack/p_run"
	match style:
		"rise":
			ap.play("getup" if ap.has_animation("getup") else "pack/getup")   # 땅에 누운 자세로 멈춰 둔다
			ap.seek(0.0, true)
			ap.pause()
			e["state"] = "lie"
		"idle":
			ap.play("pack/p_idle")
			ap.speed_scale = _rng.randf_range(0.8, 1.2)
			ap.seek(_rng.randf() * 3.0, true)
			e["state"] = "idle"
			e["wake"] = _rng.randf_range(IDLE_WAKE[0], IDLE_WAKE[1])
		_:
			_move_anim(e)
			ap.seek(_rng.randf() * 0.8, true)             # 무리가 똑같이 걷지 않게 시작 시점을 흩뜨린다
	_zombies.append(e)
	_place(e)
	return e


# 풀에서 한 마리 꺼낸다 (없으면 새로 만든다)
func _take(kind: String) -> Node3D:
	var list: Array = _pool.get(kind, [])
	var z: Node3D = list.pop_back() if not list.is_empty() else _make_zombie(kind)
	if z.get_parent() != self:
		z.reparent(self, false)
	z.visible = true
	z.rotation = Vector3.ZERO
	return z


func _make_zombie(kind: String) -> Node3D:
	var z: Node3D = load("res://assets/models/zombie_%s.glb" % kind).instantiate()
	add_child(z)
	_add_rim(z)
	var ap: AnimationPlayer = z.find_children("*", "AnimationPlayer", true, false)[0]
	ap.add_animation_library("pack", _lib_for(kind, z.find_children("*", "Skeleton3D", true, false)[0]))
	return z


# 다 쓴 좀비는 지우지 않고 숨겨서 풀에 돌려놓는다
func _despawn(e: Dictionary) -> void:
	e["gone"] = true
	var z: Node3D = e["node"]
	z.visible = false
	z.position = Vector3(0, -50, 0)
	var ap: AnimationPlayer = e["ap"]
	ap.stop()
	ap.speed_scale = 1.0
	if not _pool.has(e["kind"]):
		_pool[e["kind"]] = []
	_pool[e["kind"]].append(z)


func _pick_style(kind: String) -> String:
	var total := 0
	for st in STYLES[kind]:
		total += st[1]
	var r := _rng.randi() % total
	for st in STYLES[kind]:
		r -= st[1]
		if r < 0:
			return st[0]
	return STYLES[kind][0][0]


# 미리 불러오기 (2026-09-30 "프레임 끊긴다"): 좀비 4종 모델·동작 라이브러리·이펙트 그림을 스테이지를 만들 때 준비해 둔다
# → 처음 나오는 순간 불러오느라 멈칫하던 것(첫 좀비 32ms, 처음 보는 것 50ms)을 없앤다
# 좀비 풀 (2026-09-30 "프레임 끊긴다"): 나올 때마다 모델을 새로 만들고 지나가면 지우면, 만드는 순간 멈칫한다 (폰은 더 크게)
# → 종류별로 미리 만들어 두고 숨겼다 꺼내 쓴다. 모자라면 그때만 새로 만든다
const POOL_PER_KIND := 10
var _pool := {}                               # 종류 → 숨겨 둔 좀비 노드들
var _warm: Node3D                             # 미리 그려 두는 것들 (시작 직후 몇 프레임만 땅 밑에 있다가 지워진다)


func _prewarm() -> void:
	# 파일만 읽어 두면 처음 화면에 나올 때 그래픽 셰이더를 만드느라 멈칫한다 → 카메라 앞 땅 밑(보이지 않는 곳)에서 한 번 실제로 그린다
	_warm = Node3D.new()
	add_child(_warm)
	_warm.position = Vector3(0, -2.2, -14.0)
	var i := 0
	for kind in KINDS:
		_pool[kind] = []
		for k in POOL_PER_KIND:
			var z := _make_zombie(kind)
			z.reparent(_warm, false)
			z.position = Vector3(-4.0 + i * 0.6, 0, -k * 0.3)
			var ap: AnimationPlayer = z.find_children("*", "AnimationPlayer", true, false)[0]
			ap.play("pack/p_run")
			_pool[kind].append(z)
		i += 3
	CardFX.flare(_warm, true)
	CardFX.flare(_warm, false)
	CardFX.blood_splash(_warm, _warm.global_position)
	CardFX.blood_pool(_warm, _warm.global_position)
	BulletHitFX.spawn(_warm, _warm.global_position, Vector3.FORWARD)
	var crate: Node3D = load("res://assets/models/prop_supply_crate.glb").instantiate()
	_warm.add_child(crate)
	var flash: Node3D = load("res://scenes/fx/muzzle_flash.tscn").instantiate()
	_warm.add_child(flash)
	for n in ["sfx_pistol", "sfx_zombie_scream", "sfx_zombie_groan", "sfx_bite", "sfx_knife", "sfx_supply_pickup", "sfx_empty_click", "sfx_ui_click", "sfx_hit_obstacle"]:
		load("res://assets/audio/%s.ogg" % n)


# 사이드 질주: 양옆 멀리(8-11m)에서 2-3마리가 비명을 지르고 대각선으로 달려든다
func _sprint_event(dist: float, cam_x: float) -> void:
	var n := _rng.randi_range(2, 3)
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	for i in n:
		var sx := side if i < 2 else -side                  # 셋째는 반대쪽에서
		var e := _spawn("runner" if _rng.randf() < 0.6 else "walker", "event", EVENT_AHEAD + i * 2.5 + _rng.randf_range(-1.0, 1.0),
			sx * _rng.randf_range(8.0, 11.0), dist, cam_x)
		var ap: AnimationPlayer = e["ap"]
		ap.play("pack/p_scream")
		ap.speed_scale = 1.0
		e["state"] = "scream"
		e["t"] = -i * 0.25                                   # 한 마리씩 차례로 비명
	_sfx("sfx_zombie_scream")
	print("[event] %.0fm 옆에서 %d마리 질주" % [dist, n])


# 동작 라이브러리: 팩 동작(뼈 이름 mixamorig10_ → mixamorig_)을 이 좀비 키에 맞춰 제자리 동작으로 바꾼다
# + 매복 모델에만 있던 getup 을 다른 좀비도 쓰게 넣는다. 종류마다 한 번만 만든다
func _lib_for(kind: String, sk: Skeleton3D) -> AnimationLibrary:
	if _libs.has(kind):
		return _libs[kind]
	if _pack == null:
		var holder: Node3D = load(ANIM_PACK).instantiate()
		_pack = holder.find_children("*", "AnimationPlayer", true, false)[0]
	var hips := absf(sk.get_bone_rest(0).origin.z)
	var lib := AnimationLibrary.new()
	for n in _pack.get_animation_list():
		lib.add_animation(n, _retarget(_pack.get_animation(n), hips / PACK_HIPS, "mixamorig10_", n in PACK_LOOPS))
	if kind != "ambusher":
		var amb: Node3D = load("res://assets/models/zombie_ambusher.glb").instantiate()
		var amb_ap: AnimationPlayer = amb.find_children("*", "AnimationPlayer", true, false)[0]
		var amb_sk: Skeleton3D = amb.find_children("*", "Skeleton3D", true, false)[0]
		lib.add_animation("getup", _retarget(amb_ap.get_animation("getup"), hips / absf(amb_sk.get_bone_rest(0).origin.z), "mixamorig_", false))
		amb.free()
	_libs[kind] = lib
	return lib


# 동작 한 개 옮기기: 엉덩이만 위치를 남기고(키 비율로), 앞뒤·좌우로 가는 움직임은 지운다 (게임이 직접 옮긴다)
# 다른 뼈의 위치·크기 트랙은 버린다 — 뼈 길이가 팩 캐릭터 것으로 바뀌어 몸이 일그러지지 않게
func _retarget(src: Animation, ratio: float, prefix: String, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = src.length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for t in src.get_track_count():
		var typ := src.track_get_type(t)
		var path := str(src.track_get_path(t)).replace(prefix, "mixamorig_")
		var hip := path.ends_with(":mixamorig_Hips")
		if typ == Animation.TYPE_SCALE_3D or (typ == Animation.TYPE_POSITION_3D and not hip):
			continue
		var nt := a.add_track(typ)
		a.track_set_path(nt, NodePath(path))
		a.track_set_interpolation_type(nt, src.track_get_interpolation_type(t))
		var first: Vector3 = src.track_get_key_value(t, 0) if typ == Animation.TYPE_POSITION_3D else Vector3.ZERO
		for k in src.track_get_key_count(t):
			var v = src.track_get_key_value(t, k)
			if typ == Animation.TYPE_POSITION_3D:
				v = Vector3(first.x * ratio, first.y * ratio, v.z * ratio)   # 뼈대 좌표: z 가 높이, x·y 는 바닥 방향
			a.track_insert_key(nt, src.track_get_key_time(t, k), v)
	return a


# 달빛 테두리를 입힌다 (scenes/fx/zombie_rim.gdshader). 같은 모델끼리 재질을 같이 쓰므로 재질마다 한 번만
var _rim: ShaderMaterial


func _add_rim(z: Node3D) -> void:
	if _rim == null:
		_rim = ShaderMaterial.new()
		_rim.shader = load("res://scenes/fx/zombie_rim.gdshader")
	for mi in z.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat and mat.next_pass == null:
				mat.next_pass = _rim


# 첫 좀비는 눈에 잘 띄는 워커, 처음 INTRO_SAFE 마리에는 매복이 없게 순서만 바꾼다 (종류별 25마리는 그대로)
func _intro_order(bag: Array) -> void:
	var w := bag.find("walker")
	if w > 0:
		bag[w] = bag[0]
		bag[0] = "walker"
	for i in INTRO_SAFE:
		if bag[i] == "ambusher":
			for j in range(INTRO_SAFE, bag.size()):
				if bag[j] != "ambusher":
					bag[i] = bag[j]
					bag[j] = "ambusher"
					break


# 스타일·속도에 맞는 동작 — 재생 속도도 발이 미끄러져 보이지 않게 맞춘다
func _move_anim(e: Dictionary, spd := -1.0) -> void:
	var ap: AnimationPlayer = e["ap"]
	if spd < 0.0:
		spd = e["spd"]
	match e["style"]:
		"crawl":
			ap.play("pack/p_crawl", BLEND)
			ap.speed_scale = clampf(spd / 1.1, 0.7, 1.6)
		"crawl_run":
			ap.play("pack/p_crawl_run", BLEND)
			ap.speed_scale = clampf(spd / 2.6, 0.7, 1.4)
		_:
			if spd >= 2.5 and (e["kind"] != "tank"):
				ap.play(e["run"], BLEND)
				ap.speed_scale = clampf(spd / 4.8, 0.6, 1.35)
			else:
				ap.play(e["walk"], BLEND)
				ap.speed_scale = clampf(spd / 1.2, 0.8, 2.2)


func _place(e: Dictionary) -> void:
	var z: Node3D = e["node"]
	z.position = Vector3(e["x"], 0, -e["d"])
	var to_cam := _camera.global_position - z.global_position
	z.rotation.y = atan2(-to_cam.x, -to_cam.z)            # 정면(-Z)이 카메라를 본다 → 손 뻗고 다가온다


func _update_zombies(dist: float, cam_x: float, delta: float) -> void:
	_zombies = _zombies.filter(func(q): return not q.get("gone", false))   # 풀로 돌아간 좀비는 목록에서 뺀다 (뒤로 갈수록 느려지지 않게)
	for e in _zombies:
		if not is_instance_valid(e["node"]):
			continue
		var z: Node3D = e["node"]
		var ahead: float = e["d"] - dist
		var ap: AnimationPlayer = e["ap"]
		e["t"] += delta
		match e["state"]:
			"lie":                                         # 누워 있다가 멀리서(28m) 일어난다 → 달려온다
				_place(e)
				if ahead < RISE_AT:
					e["state"] = "getup"
					e["t"] = 0.0
					ap.play(ap.assigned_animation)
					ap.speed_scale = 1.9
					ap.seek(ap.current_animation_length * 0.3, true)   # 가장 느린 앞부분은 건너뛴다
					_sfx("sfx_zombie_groan")
				elif ahead < -2.0:
					_despawn(e)
			"getup":
				_place(e)
				if ap.current_animation_position > ap.current_animation_length * 0.93 or not ap.is_playing():
					e["state"] = "move"
					e["style"] = "sprint"
					_move_anim(e)
					_sfx("sfx_zombie_scream")
			"idle":                                        # 서서 두리번거리다가 가까워지면 출발
				_place(e)
				if ahead < e["wake"]:
					e["state"] = "move"
					e["style"] = "shamble" if e["spd"] < 2.6 else "jog"
					_move_anim(e)
					if _rng.randf() < 0.4:
						_sfx("sfx_zombie_groan")
			"scream":                                      # 사이드 질주 전: 멈춰서 비명
				_place(e)
				if e["t"] > SCREAM_TIME:
					e["state"] = "move"
					e["style"] = "sprint"
					_move_anim(e)
			"roar":                                        # 탱커 돌진 전 포효
				_place(e)
				if e["t"] > 0.8:
					e["state"] = "move"
					_move_anim(e, e["spd"] * TANK_CHARGE)
			"stagger":                                     # 한 발 맞고 휘청 (탱커)
				if e["t"] > 0.45:
					e["state"] = "move"
					_move_anim(e, e["spd"] * (TANK_CHARGE if e.get("charging", false) else 1.0))
			"move":
				var spd: float = e["spd"]
				if e["style"] == "stomp" and ahead < 16.0 and not e.get("charging", false):   # 탱커 돌진 (PRD F-42): 포효하고 달려든다
					e["charging"] = true
					e["state"] = "roar"
					e["t"] = 0.0
					ap.play("pack/p_scream", BLEND)
					ap.speed_scale = 1.4
					_sfx("sfx_zombie_groan")
					continue
				if e.get("charging", false):
					spd *= TANK_CHARGE
				if e.get("passed", false):                 # 지나친 좀비: 더는 쫓지 않고 가던 방향으로 계속 간다 (뒤돌지 않는다)
					var dir: Vector2 = e.get("dir", Vector2(0, -1))
					e["x"] += dir.x * spd * delta
					e["d"] += dir.y * spd * delta
					z.position = Vector3(e["x"], 0, -e["d"])
					if ahead < -10.0:
						_despawn(e)
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
						if e.get("low", false):                # 기는 좀비: 풀에 묻혀 잘 안 보인다 → 발목만 잡고 휘청하게 (사망 없음)
							e["passed"] = true
							_grace_t = 0.8
							_sfx("sfx_bite")
							tripped.emit()
							continue
						_grab(e, dist, cam_x)
						continue
					if cover <= 0.0:
						e["passed"] = true                 # 비켜서 스쳐 지나감
				elif ahead <= 0.05:
					e["passed"] = true                     # 옆·뒤로 넘어갔다 → 끝 (뒤에서는 잡지 않는다)
				if auto_fire and ahead < SHOOT_RANGE and ahead > 1.5 and (_mag > 0 or INFINITE_AMMO) and _reload_left <= 0.0 and _shot_cd <= 0.0:
					_shoot(e)
			"dead":
				if e.has("pool_t"):
					e["pool_t"] -= delta
					if e["pool_t"] <= 0.0:
						e.erase("pool_t")
						CardFX.blood_pool(self, Vector3(z.global_position.x, 0.0, z.global_position.z), _rng.randf_range(1.3, 1.9))
				if ahead < -4.0:
					_despawn(e)
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
		_kill(e, z.global_position + Vector3(0, 1.3, 0), 1.6)
		e["passed"] = true
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
	var bite: String = GRAB_ANIMS[_rng.randi() % GRAB_ANIMS.size()]   # 무는 동작 5가지 중 하나
	if ap.has_animation(bite):
		ap.get_animation(bite).loop_mode = Animation.LOOP_LINEAR
		ap.play(bite, BLEND)
	e["low"] = false
	_sfx("sfx_bite")
	CardFX.blood_splash(self, _camera.global_position + (z.global_position + Vector3(0, 1.4, 0) - _camera.global_position) * 0.6, 1.4)
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
		if e.get("gone", false) or e["state"] == "dead":
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
	p.volume_db = SFX_DB + SFX_TRIM.get(name, 0.0)
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
	var hy: float = 0.35 if e.get("low", false) else (1.75 if e["kind"] == "tank" else 1.35)   # 기는 좀비는 낮게 맞는다
	var hit_at := z.global_position + Vector3(_rng.randf_range(-0.12, 0.12), hy + _rng.randf_range(-0.15, 0.15), 0)
	BulletHitFX.spawn(self, hit_at, hit_at - _camera.global_position, 1.3 if e["kind"] == "tank" else 1.0)
	var near_k := clampf(hit_at.distance_to(_camera.global_position) / 6.0, 0.35, 1.0)   # 코앞이면 작게 (화면을 붉은 원이 덮지 않게)
	CardFX.blood_splash(self, hit_at, (1.5 if e["kind"] == "tank" else 1.1) * near_k)   # 피 튐 카드 (2026-09-30 "피가 안 보인다")
	e["hp"] -= 1
	if e["hp"] <= 0:
		_kill(e, hit_at, 1.0)
	elif e["state"] == "move":
		e["state"] = "stagger"                             # 탱커 첫 발: 휘청
		e["t"] = 0.0
		if e["ap"].has_animation("hit"):
			e["ap"].play("hit", 0.1)
			e["ap"].speed_scale = 1.6


# 쓰러뜨림: 죽는 동작 3가지 중 하나 + 큰 피 튐 + 잠깐 뒤 바닥 핏자국 (몇 초 뒤 사라진다)
func _kill(e: Dictionary, at: Vector3, k: float) -> void:
	var z: Node3D = e["node"]
	var ap: AnimationPlayer = e["ap"]
	e["state"] = "dead"
	ap.speed_scale = 1.0
	var dn: String = "death" if e.get("low", false) else DEATH_ANIMS[_rng.randi() % DEATH_ANIMS.size()]
	ap.play(dn if ap.has_animation(dn) else "death", 0.15)
	CardFX.blood_splash(self, at + Vector3(0, 0.1, 0), 1.7 * k)
	e["pool_t"] = 0.9                                      # 쓰러지고 나서 바닥에 핏자국 (_update_zombies 의 dead)


# 보급 상자 (2026-09-30): 풀(1m)에 묻혀 안 보이던 0.6m 상자를 2배(1.2m)로 → 땅에 놓이면 박스가 보인다. 충돌 없음 (그냥 지나가며 줍는다)
# 연기·불꽃은 카드 시퀀스 신호탄 (scenes/fx/card_fx.gd) — 떨어지는 동안부터 불똥을 뿜는다. 밑에 깔리던 검은 원판(옛 연기 장면)은 뺐다
const CRATE_SCALE := 2.0


func _drop_crate(d: float, green: bool) -> void:
	var c: Node3D = load("res://assets/models/prop_supply_crate.glb").instantiate()
	add_child(c)
	c.scale = Vector3.ONE * CRATE_SCALE
	var x := _free_x(d)
	var e := {"node": c, "d": d, "x": x, "y": DROP_HEIGHT, "landed": false, "taken": false, "green": green, "smoke": null}
	c.position = Vector3(x, DROP_HEIGHT, -d)
	var fx := CardFX.flare(c, green)
	fx.scale = Vector3.ONE / CRATE_SCALE                  # 상자 크기와 상관없이 이펙트는 제 크기
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
	_gun_toast_t = 2.5                                   # 주운 총 이름을 잠깐 보여 준다
	_refresh_ammo()


# 자동 달리기(영상·통과 검사)용: 앞 25m 안에 땅에 놓인 상자가 있으면 그 x (없으면 NAN)
func crate_x(dist: float) -> float:
	for c in _crates:
		if c["landed"] and not c["taken"] and is_instance_valid(c["node"]) and c["d"] - dist > 0.5 and c["d"] - dist < 25.0:
			return c["x"]
	return NAN

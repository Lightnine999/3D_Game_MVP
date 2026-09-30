# 스테이지 미리보기 — 주인: A
# 1인칭 시점으로 초속 5m(PRD F-01) 자동 달리기를 하며 500m를 달린다.
#
# 플레이 테스트 (2026-09-30, 기본): 사용자가 직접 좌우로 피한다 — 레벨 디자인 확인용 (진짜 조작·판정은 B 담당)
#   PC: A·D 또는 ←·→ 로 좌우, 스페이스바로 사격 (마우스는 쓰지 않는다 — 시선은 항상 정면)
#   폰: 화면을 누른 채 좌우로 끌기, 오른쪽 아래 FIRE 버튼으로 사격
#   전진은 자동. 낮은 장애물(1.1m 이하 — 찢긴 차·방어벽·짐 더미)은 높이에 맞춰 살짝 올라탔다가 내려앉는다
#   R 키 / 폰 RELOAD 버튼: 탄창 재장전 (시간이 걸린다). 빈 탄창으로 쏘면 저절로 재장전
#   차·소품은 뚫고 지나가지 못한다. 정면으로 막히면 가까운 틈으로 저절로 미끄러지고, 낮은 것은 저절로 뛰어넘는다. 좀비·권총·HUD(시연 연출)도 함께 나온다. 끝에 닿으면 처음부터
#   --auto: 예전처럼 알아서 피해 가는 자동 달리기 / --no-showcase: 좀비 없이 맵만
# 영상 프레임: godot --path godot --resolution 1560x720 -- --frames=<폴더>
#              → 1/30초씩 진행하며 그려진 장면을 JPG(약 3,000장)로 저장 후 종료 (ffmpeg로 mp4 조립)
#              Movie Maker를 쓰지 않는 이유: macOS가 가려진 창의 그리기를 건너뛰어 영상이 어긋났다
#              실행 예: --resolution 320x148 --position 0,0 --always-on-top (구석의 작은 창, 영상은 1560x720)
# 지점 캡처:   godot --path godot -- --shots=<폴더> [--dist=0,250,500,750,990]
# 시연 연출:   위 명령에 --showcase 를 더하면 좀비·권총·보급·HUD 를 얹는다 (영상 모드는 events.json 에 소리 시각 기록)
extends Node3D

const RUN_SPEED := 5.0      # m/s (PRD F-01)
const EYE_HEIGHT := 1.6
const BOB_FREQ := 2.6       # 발걸음 주기 (Hz)
const BOB_AMP := 0.05
const LOOK_AHEAD := 18.0    # 이만큼 앞의 장애물부터 피하기 시작
const DODGE_MARGIN := 1.1   # 장애물 옆으로 두는 여유 (m)
const STEER_SPEED := 3.0    # 자동 달리기 좌우 이동 속도 (m/s) — 500m 압축 뒤 장애물이 촘촘해져 2.2 → 3.0
const PLAY_STEER := 5.0     # 플레이 테스트 좌우 최고 속도 (m/s)
const DRAG_WIDTH_M := 14.0  # 화면 끝에서 끝까지 끌면 이만큼(m) 옆으로
const PLAYER_RADIUS := 0.35
# 부딪힘 도움 (2026-09-30 플레이 피드백 "장애물이 너무 가로막는다")
const SLIDE_SPEED := 6.5    # 정면으로 막히면 이 속도로 가장 가까운 틈 쪽으로 저절로 미끄러진다 (m/s)
const SLIDE_HOLD := 0.35    # 한 번 막히면 이 시간 동안 미끄러짐을 이어 간다 (초)
const SLIDE_FORWARD := 0.8 # 미끄러지는 동안 앞으로 가는 속도 비율
const JUMP_MAX := 1.1       # 이보다 낮은 장애물은 높이에 맞춰 올라탔다가 내려앉는다 (m). 0.7 → 1.1 (2026-09-30 "점프가 빠졌다":
                            # 찢긴 은색 차 0.95m·방어벽 0.95m·짐 더미 1.0m 가 0.7 보다 높아 넘지도 못하고 정면으로 막혔다). 온전한 차(1.13m~)는 미끄러져 피한다
const JUMP_LEAD := 0.45     # 뛰기 시작하는 거리 = 그 높이까지 오르는 동안 달리는 거리 + 이만큼 (m) — 앞면에 걸리기 전에 이미 올라가 있게
const STEP_UP := 0.4        # 공중에서 윗면 모서리에 걸리면 이만큼까지는 살짝 더 올려 준다 (턱에 걸리지 않게)
const PASS_LOW := JUMP_MAX  # 틈을 고를 때 넘을 수 있는 것은 막힘으로 보지 않는다
const ASSIST_LOOK := 2.2    # 넘을 수 없는 것이 이만큼 앞에서 몸을 막으면, 닿기 전에 미리 틈으로 비켜 흐른다 (m)
const UNSTUCK_TIME := 0.7   # 이만큼 못 나아가면 가장 가까운 빈자리로 몸을 부드럽게 옮긴다 (최후 수단 — 절대 갇히지 않게). 1.2 → 0.7
const GLIDE_TIME := 0.25    # 빈자리로 옮겨 가는 시간 (순간이동처럼 보이지 않게)
const STUCK_TIME := 0.6     # 이만큼 못 나아가면 반대쪽 틈으로 + 한 번 뛴다
const JUMP_CLEAR := 0.08   # 장애물 윗면보다 이만큼만 더 뛴다 (모서리에 발이 걸리지 않을 만큼만)
const JUMP_MIN := 0.22      # 최소 점프 높이 (m)
const JUMP_CAM := 0.45      # 뛸 때 카메라는 몸 높이의 절반쯤만 따라 올라간다 ("점프"보다 살짝 올라탔다 내려앉는 느낌)
const BUMP_ROLL := 5.0      # 어깨빵: 부딪힌 쪽 반대로 기우는 각도 (도)
const BUMP_YAW := 2.5       # 어깨빵: 고개가 살짝 돌아가는 각도 (도)
const GRAVITY := 18.0       # 14 → 18: 짧고 가볍게 뛰었다 내려온다 (타이어 넘기 체공 약 0.5초)
const FRAME_FPS := 30.0     # 영상 프레임 간격
const FRAME_SIZE := Vector2i(1560, 720)   # 영상 해상도 (19.5:9, S24 Ultra 비율)

var _builder: StageBuilderV2
var _camera: Camera3D
var _label: Label
var _dist := 0.0
var _time := 0.0
var _x := 0.0
var _frames_dir := ""
var _frame_count := -1       # 테스트용: --count=N 이면 N장만
var _frame_start := 0        # 이어 찍기: --start=N 이면 N번째 프레임부터 (앞부분은 그리지 않고 계산만)
var _frame_vp: SubViewport   # 영상 모드: 창 크기와 상관없이 이 캔버스에 그린다
var _shots_dir := ""
var _shot_dists: Array[float] = [0.0, 125.0, 250.0, 375.0, 490.0]
var _showcase: ShowcaseDirector     # --showcase: 좀비·권총·보급·HUD 시연 연출 (scripts/stage/showcase.gd)
var _body: CharacterBody3D          # 플레이어 몸 (충돌용 캡슐) — 차·소품에 막힌다
var _play := false                  # 플레이 테스트: 사용자가 좌우 조작
var _steer_target := 0.0
var _touch_id := -1
var _touch_x0 := 0.0
var _steer_x0 := 0.0
var _bump := 0.0                    # 부딪힌 순간 화면 흔들림 (어깨빵)
var _bump_side := 1.0               # 어깨빵 방향 (+1 오른쪽으로 밀림 / -1 왼쪽)
var _glide_t := 0.0                 # 끼임 탈출: 빈자리로 옮겨 가는 남은 시간
var _glide_from := Vector3.ZERO
var _glide_to := Vector3.ZERO
var _unstucks := 0                  # 끼임 탈출 횟수 (통과 검사 기록용)
var _bumps := 0                     # 부딪힌 횟수 (통과 검사 기록용)
var _stall := 0.0                   # 앞으로 절반도 못 나아간 시간 합 (통과 검사: "걸림" 체감 지표)
var _stall_spots := {}              # 걸린 곳 → 시간 (통과 검사 기록용)
var _last_hit := ""                 # 마지막으로 부딪힌 것 (모델 이름)
var _wig_rng := RandomNumberGenerator.new()   # 씨앗은 _ready 에서 1 (--wseed=N 으로 바꿈)
var _wig_x := 0.0
var _wig_t := 0.0
var _vy := 0.0                      # 점프 세로 속도
var _slide_t := 0.0                 # 미끄러짐 남은 시간
var _slide_x := 0.0                 # 미끄러져 갈 x (가장 가까운 틈)
var _jumps := 0                     # 자동 점프 횟수 (통과 검사 기록용)
var _grounded := true               # 땅이나 낮은 물건(가방·상자) 위에 서 있다
var _stuck_t := 0.0                 # 앞으로 못 나아간 시간
var _stuck_total := 0.0             # 끼인 채 흐른 전체 시간 (반대쪽 틈 시도와 상관없이 쌓인다)
var _fire_held := false             # 폰 FIRE 버튼을 누르고 있다
var _stun_t := 0.0                  # 칼로 벗어나는 동안 잠깐 멈춤
var _dead := false                  # 칼 없이 잡혔다 → 사망 연출
var _dead_t := 0.0
var _killer: Node3D
var _fall_from := Vector3.ZERO      # 쓰러지기 시작할 때의 카메라 각도
var _fade: ColorRect
var _blood: TextureRect             # 물릴 때 화면 가장자리에 튄 피 (assets/textures/fx/fx_blood_screen.png)
var _dead_label: Label
var _retry: Button                  # 사망 후 "다시 시작하겠습니까?" (누르면 처음부터)


func _ready() -> void:
	_wig_rng.seed = 1
	_parse_args()
	process_mode = Node.PROCESS_MODE_ALWAYS              # 일시정지 중에도 이 노드는 입력을 받는다 (게임 진행은 _process 에서 멈춤)
	_builder = StageBuilderV2.new()
	_builder.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_builder)
	_builder.build()
	# 영상 모드는 화면 밖 캔버스(SubViewport)에 그린다 → 실제 창은 작게 띄워도 영상은 제 크기
	var holder: Node = self
	if not _frames_dir.is_empty():
		_frame_vp = SubViewport.new()
		_frame_vp.size = FRAME_SIZE
		_frame_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_frame_vp)
		holder = _frame_vp
	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT   # TECH_SPEC D11 와이드 화면
	_camera.fov = 60.0
	_camera.near = 0.15                         # 가까운 한계를 조금 늘려 먼 거리의 깊이 정밀도를 올린다 (다리 쪽 깜빡임)
	_camera.far = 400.0                         # 180m 배경막(먼 산)과 120m 카드 숲까지 보이게 (60m 였을 때 모두 잘렸다)
	holder.add_child(_camera)
	_camera.make_current()
	_build_body()
	_build_overlay(holder)
	var args := OS.get_cmdline_user_args()
	_play = _frames_dir.is_empty() and _shots_dir.is_empty() and not ("--auto" in args or "--sim" in args)
	if "--showcase" in args or (_play and not ("--no-showcase" in args)):
		_showcase = ShowcaseDirector.new()
		_showcase.process_mode = Node.PROCESS_MODE_PAUSABLE   # 일시정지하면 좀비·소리도 멈춘다
		add_child(_showcase)
		_showcase.setup(_builder, _camera, holder)
		_label.position = Vector2(48, 640)          # 시연 HUD 가 남은 거리를 보여 준다 → 구석에 FPS 만
		_label.add_theme_font_size_override("font_size", 28)
		_label.visible = _play
		if _play:
			_showcase.catching = true                     # 좀비에게 잡힐 수 있다 (칼 1번, 그다음은 사망)
			_showcase.knifed.connect(_on_knifed)
			_showcase.tripped.connect(func(): _stun_t = 0.35; _bump = 1.0; _bump_side = 1.0 if randf() < 0.5 else -1.0)
			_showcase.caught.connect(_on_caught)
			_showcase.auto_fire = false                   # 사격은 스페이스바·FIRE 버튼으로 직접
			_showcase.live_audio = true
			_showcase.start_bgm()
			if DisplayServer.is_touchscreen_available():
				_build_fire_button(holder)
			_build_pause_button(holder)
	if not _frames_dir.is_empty():
		_capture_frames()
	elif not _shots_dir.is_empty():
		_capture_shots()
	elif "--sim" in args:
		_simulate()


# 통과 검사: 그리지 않고 자동 달리기만 끝까지 돌려 부딪힌 곳을 찍는다 (godot --headless --path godot -- --sim)
func _simulate() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	var steps := 0
	while _dist < StageBuilderV2.STAGE_LENGTH and steps < 9000:
		_step(1.0 / FRAME_FPS)
		steps += 1
	var spots := _stall_spots.keys()
	spots.sort_custom(func(a, b): return _stall_spots[a] > _stall_spots[b])
	for k in spots.slice(0, 8):
		print("[stall] %s %.2fs" % [k, _stall_spots[k]])
	print("[sim] 걸림 합계 %.1fs" % _stall)
	print("[sim] %s %.0fs (막힘 없으면 %.0fs) 자동 점프 %d번 · 부딪힘 %d번 · 끼임 탈출 %d번" % ["완주" if _dist >= StageBuilderV2.STAGE_LENGTH else "멈춤", steps / FRAME_FPS, StageBuilderV2.STAGE_LENGTH / RUN_SPEED, _jumps, _bumps, _unstucks])
	get_tree().quit()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			_frames_dir = arg.trim_prefix("--frames=")
		elif arg.begins_with("--count="):
			_frame_count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--start="):
			_frame_start = int(arg.trim_prefix("--start="))
		elif arg.begins_with("--wseed="):
			_wig_rng.seed = int(arg.trim_prefix("--wseed="))   # 막 누르기 검사 씨앗 (같은 씨앗 = 같은 누르기)
		elif arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--dist="):
			_shot_dists.clear()
			for v in arg.trim_prefix("--dist=").split(","):
				_shot_dists.append(float(v))


func _on_knifed() -> void:
	_stun_t = 0.45
	_bump = 1.0


func _on_caught(z: Node3D) -> void:
	_label.visible = false
	_dead = true
	_dead_t = 0.0
	_killer = z


# 사망 연출 (2026-09-30 피드백): ① 1.4초 동안 코앞의 좀비가 물어뜯는 모습을 본다 → ② 1.1초 동안 뒤로 넘어지며
#            하늘을 올려다보고 바닥에 눕는다 → ③ 누운 채 잠깐 → 블랙아웃 + 굵은 빨간 "DEAD" → 6초 뒤 처음부터
func _death_cam(delta: float) -> void:
	_dead_t += delta
	var eye := Vector3(_x, EYE_HEIGHT, -_dist)
	_blood.modulate.a = clampf(_dead_t / 0.25, 0.0, 1.0) * (0.9 + 0.1 * sin(_dead_t * 9.0))   # 물리는 순간 화면에 피가 튄다
	if _dead_t < 1.4:
		var head := _killer.global_position + Vector3(0, 1.35, 0) if is_instance_valid(_killer) else eye + Vector3(0, 0, -1)
		var shake := Vector3(sin(_dead_t * 47.0), sin(_dead_t * 61.0), 0) * 0.03
		_camera.position = eye + shake
		_camera.look_at(head, Vector3.UP)
		_fall_from = _camera.rotation
	elif _dead_t < 2.5:
		var k := smoothstep(0.0, 1.0, (_dead_t - 1.4) / 1.1)
		_camera.position = eye.lerp(Vector3(_x + 0.1, 0.22, -_dist + 0.9), k * k)   # 뒤로 넘어지며 바닥으로
		_camera.rotation = Vector3(lerpf(_fall_from.x, deg_to_rad(80.0), k), lerpf(_fall_from.y, 0.0, k), lerpf(_fall_from.z, deg_to_rad(10.0), k))
	var black := clampf((_dead_t - 3.0) / 0.6, 0.0, 1.0)  # 누워서 하늘을 본 채 블랙아웃
	_fade.color.a = black
	if _dead_t > 3.3:
		_dead_label.visible = true
		var pop := clampf((_dead_t - 3.3) / 0.25, 0.0, 1.0)  # 글자가 크게 찍혔다가 제 크기로
		_dead_label.scale = Vector2.ONE * lerpf(1.35, 1.0, pop)
		_dead_label.modulate.a = pop
	if _dead_t > 4.0 and not _retry.visible:              # 자동으로 넘어가지 않는다 — Retry 를 눌러야 다시 시작 (2026-09-30 피드백)
		_retry.visible = true
		_retry.modulate.a = 0.0
		_retry.grab_focus()                               # 엔터·스페이스로도 누를 수 있게
	if _retry.visible:
		_retry.modulate.a = clampf((_dead_t - 4.0) / 0.6, 0.0, 1.0)   # DEAD 가 찍힌 뒤 한 번 서서히 나타난다


# 일시정지 (2026-09-30): 오른쪽 위 어두운 반투명 원 + 뼈색 아이콘 (❚❚ 진행 중 / ▶ 멈춤). P·Esc 키로도
var _pause_btn: Button
var _pause_dim: ColorRect


func _build_pause_button(holder: Node) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	holder.add_child(layer)
	_pause_dim = ColorRect.new()                           # 멈추면 화면을 살짝 어둡게
	_pause_dim.color = Color(0, 0, 0, 0.45)
	_pause_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_dim.visible = false
	layer.add_child(_pause_dim)
	_pause_btn = Button.new()
	_pause_btn.focus_mode = Control.FOCUS_NONE             # 스페이스(사격)가 버튼을 누르지 않게
	_pause_btn.anchor_left = 1.0
	_pause_btn.anchor_right = 1.0
	_pause_btn.offset_left = -108
	_pause_btn.offset_right = -36
	_pause_btn.offset_top = 26
	_pause_btn.offset_bottom = 98
	var circle := StyleBoxFlat.new()
	circle.bg_color = Color(0.05, 0.05, 0.06, 0.38)
	circle.set_corner_radius_all(36)
	var round_hi := circle.duplicate() as StyleBoxFlat
	round_hi.bg_color = Color(0.05, 0.05, 0.06, 0.6)
	_pause_btn.add_theme_stylebox_override("normal", circle)
	_pause_btn.add_theme_stylebox_override("hover", round_hi)
	_pause_btn.add_theme_stylebox_override("pressed", round_hi)
	_pause_btn.draw.connect(_draw_pause_icon)
	_pause_btn.pressed.connect(_toggle_pause)
	layer.add_child(_pause_btn)


func _draw_pause_icon() -> void:
	var c := Vector2(36, 36)
	var bone := Color8(233, 226, 214)
	if get_tree().paused:                                  # ▶ 다시 달리기
		_pause_btn.draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -14), c + Vector2(-9, 14), c + Vector2(15, 0)]), bone)
	else:                                                  # ❚❚ 일시정지
		_pause_btn.draw_rect(Rect2(c + Vector2(-11, -14), Vector2(7, 28)), bone)
		_pause_btn.draw_rect(Rect2(c + Vector2(4, -14), Vector2(7, 28)), bone)


func _toggle_pause() -> void:
	if _dead:
		return
	get_tree().paused = not get_tree().paused
	_pause_dim.visible = get_tree().paused
	_pause_btn.queue_redraw()


# Retry 모양: 아래쪽 줄 하나 (두께 w, 색 line) + 옅은 바탕
func _retry_style(w: int, line: Color, bg: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = line
	st.border_width_bottom = w
	st.content_margin_left = 40
	st.content_margin_right = 40
	st.content_margin_top = 14
	st.content_margin_bottom = 14
	return st


func _build_fire_button(holder: Node) -> void:
	var layer := CanvasLayer.new()
	holder.add_child(layer)
	var b := Button.new()
	b.text = "FIRE"
	b.add_theme_font_size_override("font_size", 40)
	b.anchor_left = 1.0
	b.anchor_top = 1.0
	b.anchor_right = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = -230
	b.offset_top = -190
	b.offset_right = -40
	b.offset_bottom = -40
	b.modulate = Color(1, 1, 1, 0.75)
	b.button_down.connect(func(): _fire_held = true)
	b.button_up.connect(func(): _fire_held = false)
	layer.add_child(b)
	var r := Button.new()                                   # 재장전 버튼: FIRE 위
	r.text = "RELOAD"
	r.add_theme_font_size_override("font_size", 30)
	r.anchor_left = 1.0
	r.anchor_top = 1.0
	r.anchor_right = 1.0
	r.anchor_bottom = 1.0
	r.offset_left = -210
	r.offset_top = -300
	r.offset_right = -60
	r.offset_bottom = -210
	r.modulate = Color(1, 1, 1, 0.7)
	r.button_down.connect(func(): _showcase.reload())
	layer.add_child(r)


func _build_body() -> void:
	_body = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = PLAYER_RADIUS
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.9
	_body.add_child(shape)
	_body.safe_margin = 0.02
	add_child(_body)


func _build_overlay(holder: Node) -> void:
	var layer := CanvasLayer.new()
	holder.add_child(layer)
	_label = Label.new()
	_label.position = Vector2(48, 32)
	_label.add_theme_font_size_override("font_size", 56)
	_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.9))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_label.add_theme_constant_override("shadow_offset_x", 3)
	_label.add_theme_constant_override("shadow_offset_y", 3)
	layer.add_child(_label)
	_blood = TextureRect.new()
	_blood.texture = load("res://assets/textures/fx/fx_blood_screen.png")
	_blood.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blood.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_blood.stretch_mode = TextureRect.STRETCH_SCALE
	_blood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blood.modulate.a = 0.0
	layer.add_child(_blood)
	_fade = ColorRect.new()                              # 사망 연출: 블랙아웃
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_dead_label = Label.new()
	_dead_label.text = "DEAD"
	_dead_label.visible = false
	_dead_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dead_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bold := SystemFont.new()                          # 굵은 글꼴 (없으면 기본 글꼴을 굵게 흉내)
	bold.font_names = PackedStringArray(["Impact", "Arial Black", "Helvetica Neue", "Roboto", "sans-serif"])
	bold.font_weight = 900
	_dead_label.add_theme_font_override("font", bold)
	_dead_label.add_theme_font_size_override("font_size", 210)
	_dead_label.add_theme_color_override("font_color", Color(0.78, 0.03, 0.03))
	_dead_label.add_theme_color_override("font_outline_color", Color(0.25, 0.0, 0.0))
	_dead_label.add_theme_constant_override("outline_size", 14)
	_dead_label.resized.connect(func(): _dead_label.pivot_offset = _dead_label.size * 0.5)
	# Retry (2026-09-30 디자인): 이 화면의 주인공은 DEAD 하나 → Retry 는 조용하게. 회색 상자 대신 뼈색 글자 + 아래 마른 피 줄 하나,
	# 고르면(마우스 올림·엔터 초점·터치) 줄이 굵어지고 선명한 피 색으로 번진다. 폰에서 누르기 쉽게 누르는 영역은 넓게
	_retry = Button.new()
	_retry.text = "Retry"
	_retry.visible = false
	_retry.flat = false
	var spaced := FontVariation.new()                     # DEAD 와 같은 굵은 글꼴, 글자 사이만 벌려 차분하게
	spaced.base_font = bold
	spaced.spacing_glyph = 6
	_retry.add_theme_font_override("font", spaced)
	_retry.add_theme_font_size_override("font_size", 52)
	var bone := Color8(217, 207, 192)
	_retry.add_theme_color_override("font_color", bone)
	_retry.add_theme_color_override("font_hover_color", Color8(242, 233, 220))
	_retry.add_theme_color_override("font_focus_color", Color8(242, 233, 220))
	_retry.add_theme_color_override("font_pressed_color", Color8(199, 8, 8))
	_retry.add_theme_stylebox_override("normal", _retry_style(3, Color8(107, 15, 15), Color(0, 0, 0, 0)))
	_retry.add_theme_stylebox_override("hover", _retry_style(6, Color8(179, 18, 15), Color(0.3, 0.01, 0.01, 0.22)))
	_retry.add_theme_stylebox_override("focus", _retry_style(6, Color8(179, 18, 15), Color(0.3, 0.01, 0.01, 0.22)))
	_retry.add_theme_stylebox_override("pressed", _retry_style(6, Color8(199, 8, 8), Color(0.3, 0.01, 0.01, 0.4)))
	_retry.set_anchors_preset(Control.PRESET_CENTER)
	_retry.offset_left = -170
	_retry.offset_right = 170
	_retry.offset_top = 175
	_retry.offset_bottom = 275
	_retry.pressed.connect(func(): get_tree().reload_current_scene())
	layer.add_child(_dead_label)
	layer.add_child(_retry)


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if not _frames_dir.is_empty() or not _shots_dir.is_empty() or "--sim" in OS.get_cmdline_user_args():
		return                                           # 캡처·통과 검사는 아래 함수가 직접 한 걸음씩 진행
	if _dead:
		_death_cam(delta)
		return
	_step(delta)
	if _dist >= StageBuilderV2.STAGE_LENGTH:
		get_tree().reload_current_scene()                 # 끝 → 처음부터 (좀비·보급도 새로)
		return
	_label.text = ("%d fps" % Engine.get_frames_per_second()) if _showcase else ("%dm   %d fps" % [StageBuilderV2.remaining(_dist), Engine.get_frames_per_second()])   # 폰 성능 확인용 (N-01: S24 Ultra 60fps)


# 플레이 테스트 조작: 폰은 누른 채 좌우로 끌기 (FIRE 버튼 위는 제외). PC 는 키보드만 (_step 에서 읽는다)
# 마우스는 쓰지 않는다: 마우스를 움직여 시선이 돌아가거나 기울지 않게 (2026-09-30 피드백)
func _unhandled_input(event: InputEvent) -> void:
	if not _play:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_P or event.physical_keycode == KEY_ESCAPE) and not _dead:
		_toggle_pause()
		return
	if get_tree().paused:
		return
	var w := get_viewport().get_visible_rect().size.x
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			_touch_id = event.index
			_touch_x0 = event.position.x
			_steer_x0 = _steer_target
		elif not event.pressed and event.index == _touch_id:
			_touch_id = -1
	elif event is InputEventScreenDrag and event.index == _touch_id:
		_steer_target = clampf(_steer_x0 + (event.position.x - _touch_x0) / w * DRAG_WIDTH_M, -_lane(), _lane())


func _lane() -> float:
	return StageBuilderV2.LANE_HALF - PLAYER_RADIUS


# 한 걸음 진행: 앞으로 달리고, 좌우로 비키고(사용자 조작 또는 자동), 차·소품에 막히면 멈칫, 카메라를 흔든다
func _step(delta: float) -> void:
	_time += delta
	var vx := 0.0
	var vz := RUN_SPEED
	if _play:
		var key := 0.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			key -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			key += 1.0
		if key != 0.0:
			_steer_target = clampf(_x + key * 1.2, -_lane(), _lane())
		if _showcase and (Input.is_physical_key_pressed(KEY_SPACE) or _fire_held):
			_showcase.fire()                              # 누르고 있으면 연사 간격(0.45초)마다
		if _showcase and Input.is_physical_key_pressed(KEY_R):
			_showcase.reload()                            # 재장전 (걸리는 시간 동안 못 쏜다)
		vx = clampf((_steer_target - _x) * 8.0, -PLAY_STEER, PLAY_STEER)
	else:
		vx = clampf((_target_x() - _x) / maxf(delta, 0.001), -STEER_SPEED, STEER_SPEED)
	if _glide_t > 0.0:                                   # 끼임 탈출: 빈자리로 부드럽게 옮겨 가는 중 (다른 움직임은 잠시 멈춤)
		_glide_t -= delta
		var k := 1.0 - clampf(_glide_t / GLIDE_TIME, 0.0, 1.0)
		_body.position = _glide_from.lerp(_glide_to, smoothstep(0.0, 1.0, k))
		_dist = -_body.position.z
		_x = _body.position.x
		_finish_step(delta)
		return
	_assist()
	if _slide_t > 0.0:                                   # 막혀서 미끄러지는 중: 조작보다 우선 (조작 안 해도 빠져나간다)
		_slide_t -= delta
		vx = clampf((_slide_x - _x) * 6.0, -SLIDE_SPEED, SLIDE_SPEED)
		vz = RUN_SPEED * SLIDE_FORWARD                    # 비스듬한 차 면을 계속 밀면 반대로 밀려나 옆걸음이 막힌다 → 앞으로는 살살
		_steer_target = _x                                # 손을 떼도 제자리로 끌려가지 않게
	if _stun_t > 0.0:                                    # 칼질하는 동안 잠깐 멈췄다가 다시 달린다
		_stun_t -= delta
		vz = 0.0
		vx = 0.0
	_auto_jump()
	if (_body.position.y > 0.0 and not _grounded) or _vy > 0.0:
		_vy -= GRAVITY * delta
	elif _body.position.y > 0.0:
		_vy = -0.5                                        # 짐 위에 서 있다: 살짝 눌러서 가장자리를 벗어나면 떨어지게
	else:
		_vy = 0.0
	_move_body(Vector3(vx, _vy, -vz) * delta)
	if _body.position.y <= 0.0 and _vy <= 0.0:             # 착지 (막 뛰어오르려는 순간은 건드리지 않는다)
		_body.position.y = 0.0
		_vy = 0.0
		_grounded = true
	_finish_step(delta)


func _finish_step(delta: float) -> void:
	_bump = maxf(_bump - delta * 3.0, 0.0)
	_builder.update_atmosphere(_dist)   # 600m 이후 하늘·안개가 회색으로 무거워짐
	_apply_camera(_time)
	if _showcase:
		_showcase.update(_dist, _x, delta)
	_label.text = "%dm" % StageBuilderV2.remaining(_dist)


# 미리 비켜 흐르기 (2026-09-30 "무조건 미끄러지거나 점프해서 빠져나와야"): 넘을 수 없는 것이 바로 앞에서 몸을 막으면
# 닿기 전에 가장 가까운 틈으로 흘러간다. 사용자가 장애물 쪽으로 키를 계속 눌러도 이것이 먼저다
func _assist() -> void:
	if _slide_t > 0.0 or not _grounded:
		return
	for ob in _builder.obstacles:
		if ob.get("top", 9.0) - _body.position.y < JUMP_MAX:
			continue                                          # 넘을 수 있는 것은 _auto_jump 가 맡는다
		var ahead: float = ob["z"] - ob.get("half_depth", 1.0) - _dist
		if ahead > -0.2 and ahead < ASSIST_LOOK and absf(ob["x"] - _x) < ob["half_width"] + PLAYER_RADIUS:
			var gx := _gap_x(ob["z"], 6.0)
			if is_nan(gx):
				gx = _gap_x(ob["z"], 1.0)
			if not is_nan(gx):
				_slide_x = gx
				_slide_t = SLIDE_HOLD
			return


# 자동 달리기: 앞에 있는 가장 가까운 장애물 "줄"(앞뒤 7m 안에 모인 것들)의 막힌 구간을 모아,
# 빈 틈 가운데 지금 위치에서 가장 가까운 곳으로 비킨다 (차 두 대가 벽을 쌓고 틈이 하나뿐인 카드도 통과)
func _target_x() -> float:
	if "--into" in OS.get_cmdline_user_args():           # 끼임 검사: 일부러 가장 가까운 장애물 한가운데로 파고든다 (--sim --into)
		var nz := INF
		var nx := _x
		for ob in _builder.obstacles:
			var a: float = ob["z"] - _dist
			if a > 0.5 and a < 12.0 and a < nz:
				nz = a
				nx = ob["x"]
		return clampf(nx, -_lane(), _lane())
	if "--wiggle" in OS.get_cmdline_user_args():          # 막 누르기 검사: 0.3-0.9초마다 아무 데로나 방향을 바꾼다 (사용자가 키를 제멋대로 누르는 흉내)
		_wig_t -= 1.0 / FRAME_FPS
		if _wig_t <= 0.0:
			_wig_t = _wig_rng.randf_range(0.3, 0.9)
			_wig_x = _wig_rng.randf_range(-_lane(), _lane())
		return _wig_x
	if "--straight" in OS.get_cmdline_user_args():
		return _x                                         # 손 놓고 달리기 검사: 조작 없이 미끄러짐·점프만으로 빠져나가는지 (--sim --straight)
	var wander := sin(_time * 0.35) * 1.2              # 장애물이 없으면 길 안에서 천천히 좌우로
	var near_z := INF
	for ob in _builder.obstacles:
		var hd: float = ob.get("half_depth", 1.0)
		if ob.get("top", 9.0) >= PASS_LOW and ob["z"] + hd - _dist > -0.3 and ob["z"] - hd - _dist < LOOK_AHEAD:
			near_z = minf(near_z, ob["z"])
	var cx := _showcase.crate_x(_dist) if _showcase else NAN
	if near_z == INF:
		return wander if is_nan(cx) else cx                 # 길이 비었으면 보급 상자 쪽으로
	var pref := _x if is_nan(cx) else cx                   # 틈이 여럿이면 상자에 가까운 틈으로
	var best := _gap_x(near_z, 7.0, pref)
	if is_nan(best):                                        # 7m 줄에 틈이 없으면(엇갈린 배치) 가장 가까운 것만 보고 비킨다
		best = _gap_x(near_z, 1.5, pref)
	return _x if is_nan(best) else best


# near_z 앞뒤 reach 안의 장애물이 막은 구간을 빼고, 남은 틈 중 지금 위치에서 가장 가까운 x (틈이 없으면 NAN)
func _gap_x(near_z: float, reach: float, pref := NAN) -> float:
	if is_nan(pref):
		pref = _x
	var blocked: Array = []
	for ob in _builder.obstacles:
		var hd2: float = ob.get("half_depth", 1.0)
		if ob.get("top", 9.0) < PASS_LOW:
			continue                                          # 아주 낮은 것은 뛰어넘으니 피하지 않는다
		if absf(ob["z"] - near_z) < reach + hd2 and ob["z"] + hd2 - _dist > -0.3:
			var m: float = ob["half_width"] + PLAYER_RADIUS + 0.35
			blocked.append([ob["x"] - m, ob["x"] + m])
	blocked.sort_custom(func(a, b): return a[0] < b[0])
	# 지금 몸 바로 옆에 붙어 있는 것 (앞뒤로 몸과 겹친다): 그 너머의 틈은 옆으로 뚫고 가야 하니 고르지 않는다
	# (2026-09-30 472m: 대각선으로 늘어선 정체 차들 — 옆차 너머 틈을 골라 제자리에서 버둥거렸다)
	var beside: Array = []
	for ob in _builder.obstacles:
		var hd3: float = ob.get("half_depth", 1.0)
		if ob.get("top", 9.0) - _body.position.y >= PASS_LOW and ob["z"] - hd3 < _dist - 0.1 and ob["z"] + hd3 > _dist - PLAYER_RADIUS:
			var m3: float = ob["half_width"] + PLAYER_RADIUS
			beside.append([ob["x"] - m3, ob["x"] + m3])
	var lane := _lane()
	var best := NAN
	var best_cost := INF
	var start := -lane
	for bl in blocked + [[lane, lane]]:
		if bl[0] > start:                                  # [start, bl[0]] 이 빈 틈
			var e0: float = bl[0]
			var tx: float = clampf(pref, start + 0.1, e0 - 0.1) if e0 - start > 0.2 else (start + e0) * 0.5
			var cost: float = absf(tx - pref)
			for bs in beside:
				if bs[1] > minf(_x, tx) and bs[0] < maxf(_x, tx):
					cost = INF                              # 가는 길을 옆차가 막는다
			if cost < best_cost:
				best_cost = cost
				best = tx
		start = maxf(start, bl[1])
	return best


# 몸을 움직이고 부딪히면 벽을 따라 미끄러진다 (move_and_slide 는 물리 틱 간격을 써서, 영상의 1/30초 걸음과 맞지 않아 직접 계산)
func _move_body(motion: Vector3) -> void:
	var before := _body.position
	var want := -motion.z
	# 위아래 먼저, 그다음 앞·옆 (한꺼번에 움직이면 앞 차와 발밑 타이어 사이에 끼어 점프가 막혔다)
	if absf(motion.y) > 0.0001:
		var vcol := _body.move_and_collide(Vector3(0.0, motion.y, 0.0))
		if vcol and motion.y < 0.0:
			_vy = 0.0                                     # 낮은 것 위에 내려앉음 → 그 위로 계속 달린다
			_grounded = true
		else:
			_grounded = false
	motion.y = 0.0
	for i in 4:
		var col := _body.move_and_collide(motion)
		if col == null:
			break
		var n := col.get_normal()
		var hit := col.get_collider() as Node
		_last_hit = str(hit.get_meta("model", hit.name)) if hit else "?"
		var rise := _collider_top(col) - _body.position.y
		if n.y > -0.3 and rise > 0.0 and rise < (JUMP_MAX if _grounded else STEP_UP):   # 낮은 것에 걸렸다 → 높이에 맞춰 올라탄다
			_jump_to(_collider_top(col))
			if _grounded:
				_jumps += 1
			_slide_t = 0.0
			break                                             # 이번 걸음은 여기까지 — 다음 걸음부터 위로 올라간다
		if absf(n.y) < 0.5 and _bump < 0.25:                 # 옆·앞으로 부딪혔다 → 어깨빵 (밀린 쪽으로 카메라가 기운다)
			_bump = 1.0
			_bumps += 1
			_bump_side = signf(n.x) if absf(n.x) > 0.2 else (1.0 if _x < 0.0 else -1.0)
			if _showcase:
				_showcase.sfx("sfx_hit_obstacle")
		n.y = 0.0
		n = n.normalized() if n.length() > 0.01 else Vector3.BACK
		motion = col.get_remainder().slide(n)
		if n.z > 0.5 and _slide_t <= 0.0:                 # 정면으로 막혔다 → 가장 가까운 틈으로 미끄러지기 시작
			var gx := _gap_x(_dist + 1.0, 6.0)              # 바로 뒤에 붙은 차까지 보고 틈을 고른다
			if is_nan(gx):
				gx = _gap_x(_dist + 1.0, 1.0)
			_slide_x = gx if not is_nan(gx) else _x + (1.0 if _x < 0.0 else -1.0) * 2.0
			_slide_t = SLIDE_HOLD
		elif n.z > 0.5:
			_slide_t = SLIDE_HOLD                          # 아직 막혀 있으면 미끄러짐 연장
			if absf(_slide_x - _x) < 0.15:                   # 목표에 왔는데도 막힘(가장자리 등) → 반대쪽 틈으로
				var far := -signf(_x if _x != 0.0 else 1.0) * _lane()
				var g2 := _gap_x(_dist + 1.0, 6.0, far)
				_slide_x = g2 if not is_nan(g2) and absf(g2 - _x) > 0.3 else clampf(_x + signf(far) * 3.0, -_lane(), _lane())
				if _grounded:
					_jump_to(0.5)                                 # 끼었으면 한 번 뛰어 본다 (낮은 짐 더미 위로)
	_body.position.x = clampf(_body.position.x, -_lane(), _lane())
	var moved := before.z - _body.position.z
	if want > 0.0 and moved < want * 0.5 and _stun_t <= 0.0:
		var dt := want / RUN_SPEED
		_stall += dt
		var key := "%s @%dm" % [_last_hit, int(_dist / 5.0) * 5]
		_stall_spots[key] = _stall_spots.get(key, 0.0) + dt
	if want > 0.0 and moved < want * 0.3:
		_stuck_t += want / RUN_SPEED
		_stuck_total += want / RUN_SPEED
	elif moved > want * 0.6:
		_stuck_t = 0.0
		_stuck_total = 0.0
	if _stuck_total > UNSTUCK_TIME:                      # 최후 수단: 몸이 들어갈 수 있는 가장 가까운 빈자리로 옮긴다
		_stuck_total = 0.0
		_unstuck()
	if _stuck_t > STUCK_TIME:                            # 오래 끼었다 → 반대쪽 틈으로 방향을 바꾸고 한 번 뛴다
		_stuck_t = 0.0
		var far := -signf(_slide_x - _x) * _lane() if absf(_slide_x - _x) > 0.05 else -signf(_x if _x != 0.0 else 1.0) * _lane()
		var g3 := _gap_x(_dist + 1.0, 6.0, far)
		_slide_x = g3 if not is_nan(g3) else clampf(_x + signf(far) * 3.0, -_lane(), _lane())
		_slide_t = SLIDE_HOLD * 2.0
		if _grounded:
			_jump_to(0.5)
	_dist = -_body.position.z
	_x = _body.position.x


# 끼임 탈출 (2026-09-30 "장애물에 걸려 못 빠져나온다"): 캡슐이 아무것과도 안 겹치는 자리를
# 지금 줄(좌우) → 1m씩 앞 줄 순서로 찾아 가장 가까운 곳으로 옮긴다. 어떤 배치에서도 갇히지 않는다
func _unstuck() -> void:
	var here := _body.position
	for ahead in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0]:
		var best := INF
		var best_x := 0.0
		var x := -_lane()
		while x <= _lane():
			var p := Vector3(x, 0.0, here.z - ahead)
			var cost: float = absf(x - here.x) + ahead * 0.8
			if cost < best and _free_path(p):
				best = cost
				best_x = x
			x += 0.25
		if best < INF:
			_glide_from = here
			_glide_to = Vector3(best_x, 0.0, here.z - ahead)
			_glide_t = GLIDE_TIME
			_unstucks += 1
			_vy = 0.0
			_grounded = true
			_slide_t = 0.0
			_steer_target = best_x
			print("[unstuck] %.1fm x %.2f → %.2f (앞 %.0fm)" % [-here.z, here.x, best_x, ahead])
			return


# 그 자리와 앞으로 2m 길이 모두 비었나 (옆으로만 조금 옮겨 곧바로 다시 막히던 문제 — 2026-09-30 472m)
func _free_path(p: Vector3) -> bool:
	for f in [0.0, 0.7, 1.4, 2.1]:
		if not _free_at(p + Vector3(0, 0, -f)):
			return false
	return true


func _free_at(p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = PLAYER_RADIUS + 0.05
	cap.height = 1.7
	q.shape = cap
	q.transform = Transform3D(Basis(), p + Vector3(0, 0.9, 0))
	q.exclude = [_body.get_rid()]
	return _body.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# 높이 top(m) 인 것 위로 올라설 만큼 뛴다 → 길면 그 위를 달리다가 끝에서 떨어져 내려온다
func _jump_to(top: float) -> void:
	var h := maxf(top - _body.position.y + JUMP_CLEAR, JUMP_MIN)
	_vy = sqrt(2.0 * GRAVITY * h)
	_grounded = false


# 부딪힌 충돌 상자의 윗면 높이
func _collider_top(col: KinematicCollision3D) -> float:
	var body := col.get_collider() as Node
	if body == null:
		return 99.0
	if body.has_meta("top"):                              # 알약 충돌 (stage_builder_v2._pill_collider)
		return body.get_meta("top")
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs and cs.shape is BoxShape3D:
			var sz: Vector3 = (cs.shape as BoxShape3D).size
			return (cs.global_transform * AABB(-sz * 0.5, sz)).end.y
	return 99.0


# 앞에 낮은 장애물(JUMP_MAX 미만)이 몸과 겹치면 저절로 뛴다 — 사용자는 점프를 조작하지 않는다
# 뛰는 거리 = 그 높이까지 오르는 동안 달리는 거리 + 여유 → 앞면에 닿기 전에 이미 윗면 높이에 있다
func _auto_jump() -> void:
	if not _grounded:
		return
	for ob in _builder.obstacles:
		var rise: float = ob.get("top", 9.0) - _body.position.y
		if rise >= JUMP_MAX or rise <= 0.02:
			continue
		var ahead: float = ob["z"] - ob.get("half_depth", 1.0) - _dist
		var look := RUN_SPEED * sqrt(2.0 * GRAVITY * (rise + JUMP_CLEAR)) / GRAVITY + JUMP_LEAD
		if ahead > -0.3 and ahead < look and absf(ob["x"] - _x) < ob["half_width"] + PLAYER_RADIUS:
			_jump_to(ob.get("top", 0.5))
			_jumps += 1
			return


func _apply_camera(t: float) -> void:
	# 발걸음 흔들림 + 살짝 좌우로 흔들리는 시선 (달리는 느낌)
	var step := sin(t * TAU * BOB_FREQ)
	var sway := sin(t * TAU * BOB_FREQ * 0.5)
	var shake := _bump * _bump * 0.06 * sin(t * 60.0)
	var air := _body.position.y * JUMP_CAM
	_camera.position = Vector3(_x + sway * 0.04 + shake, EYE_HEIGHT + air + (0.0 if air > 0.01 else absf(step) * BOB_AMP), -_dist)
	if _play:                                              # 플레이: 항상 정면 (위아래 발걸음만). 부딪히면 어깨빵처럼 잠깐 기울었다 돌아온다
		var jolt := _bump * _bump * _bump_side
		_camera.rotation = Vector3(deg_to_rad(-2.0 + step * 0.4 - _bump * _bump * 1.2), deg_to_rad(-BUMP_YAW * jolt), deg_to_rad(-BUMP_ROLL * jolt))
	else:
		_camera.rotation = Vector3(deg_to_rad(-2.0 + step * 0.4), deg_to_rad(sin(t * 0.35) * -4.0), deg_to_rad(sway * 0.6 + shake * 40.0))


# 영상용: 1/30초씩 진행하며 한 장이 그려질 때마다 JPG로 저장 (창이 가려져 느려져도 프레임이 빠지거나 겹치지 않음)
func _capture_frames() -> void:
	DirAccess.make_dir_recursive_absolute(_frames_dir)
	var total := int(StageBuilderV2.STAGE_LENGTH / RUN_SPEED * FRAME_FPS * 1.5)   # 부딪혀 멈칫한 만큼 길어진다 → 끝에 닿으면 멈춤
	if _frame_count > 0:
		total = _frame_count
	for i in _frame_start:                               # 이어 찍기: 앞부분은 이동만 계산 (같은 경로가 되도록)
		_step(1.0 / FRAME_FPS)
	for i in 3:                                          # 첫 프레임 전에 그림자·가시 범위 준비
		await get_tree().process_frame
	for i in range(_frame_start, total):
		_step(1.0 / FRAME_FPS)
		if _dist >= StageBuilderV2.STAGE_LENGTH and _frame_count <= 0:
			total = i
			break
		# 카메라 이동은 다음 엔진 프레임에 렌더러로 전달된다 → 그 프레임이 다 그려질 때까지 기다린 뒤 저장
		# (강제 그리기 force_draw는 옮기기 전 장면을 그려서 같은 장면이 반복 저장됐다)
		await RenderingServer.frame_post_draw
		var img := _frame_vp.get_texture().get_image()
		img.save_jpg("%s/f_%05d.jpg" % [_frames_dir, i], 0.88)
		if i % 300 == 0:
			print("[preview] frame %d / %d  (%dm)" % [i, total, int(_dist)])
	if _showcase:                                        # 소리 입히기용 사건 시각 (총성·비명·줍기)
		var f := FileAccess.open(_frames_dir + "/events.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(_showcase.events))
	print("[preview] frames done: %d" % total)
	get_tree().quit()


func _capture_shots() -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	for d in _shot_dists:
		_dist = d
		_x = 0.0
		_body.position = Vector3(0, 0, -d)
		_builder.update_atmosphere(d)
		_apply_camera(0.3)
		_label.text = "%dm" % StageBuilderV2.remaining(d)
		for i in 6:                                      # 실제로 그려질 때까지 기다린다 (창이 가려지면 macOS가 그리기를 늦춤)
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/dist_%04d.png" % [_shots_dir, int(d)]
		img.save_png(path)
		print("[stats] %dm objects=%d primitives=%d draw_calls=%d" % [StageBuilderV2.remaining(d),   # 성능 측정 (최적화 비교용)
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		print("[preview] shot ", path)
	get_tree().quit()

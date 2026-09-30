# 스테이지 미리보기 — 주인: A
# 1인칭 시점으로 초속 5m(PRD F-01) 자동 달리기를 하며 500m를 달린다.
#
# 플레이 테스트 (2026-09-30, 기본): 사용자가 직접 좌우로 피한다 — 레벨 디자인 확인용 (진짜 조작·판정은 B 담당)
#   폰: 화면을 누른 채 좌우로 끌기 / PC: A·D 또는 ←·→ (마우스 끌기도 됨)
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
const SLIDE_SPEED := 3.2    # 정면으로 막히면 이 속도로 가장 가까운 틈 쪽으로 저절로 미끄러진다 (m/s)
const SLIDE_HOLD := 0.35    # 한 번 막히면 이 시간 동안 미끄러짐을 이어 간다 (초)
const SLIDE_FORWARD := 0.25 # 미끄러지는 동안 앞으로 가는 속도 비율
const JUMP_MAX := 0.8       # 이보다 낮은 장애물(타이어·가방·잔해)은 자동으로 뛰어넘는다 (m)
const JUMP_LOOK := 1.3      # 낮은 장애물이 이만큼 앞에 오면 뛴다 (m)
const JUMP_SPEED := 5.2     # 뛰어오르는 속도 (m/s) → 최고 약 0.97m, 체공 약 0.74초
const GRAVITY := 14.0
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
var _bump := 0.0                    # 부딪힌 순간 화면 흔들림
var _vy := 0.0                      # 점프 세로 속도
var _slide_t := 0.0                 # 미끄러짐 남은 시간
var _slide_x := 0.0                 # 미끄러져 갈 x (가장 가까운 틈)
var _jumps := 0                     # 자동 점프 횟수 (통과 검사 기록용)
var _grounded := true               # 땅이나 낮은 물건(가방·상자) 위에 서 있다


func _ready() -> void:
	_parse_args()
	_builder = StageBuilderV2.new()
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
		add_child(_showcase)
		_showcase.setup(_builder, _camera, holder)
		_label.position = Vector2(48, 640)          # 시연 HUD 가 남은 거리를 보여 준다 → 구석에 FPS 만
		_label.add_theme_font_size_override("font_size", 28)
		_label.visible = _play
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
	print("[sim] %s %.0fs (막힘 없으면 %.0fs) 자동 점프 %d번" % ["완주" if _dist >= StageBuilderV2.STAGE_LENGTH else "멈춤", steps / FRAME_FPS, StageBuilderV2.STAGE_LENGTH / RUN_SPEED, _jumps])
	get_tree().quit()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			_frames_dir = arg.trim_prefix("--frames=")
		elif arg.begins_with("--count="):
			_frame_count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--start="):
			_frame_start = int(arg.trim_prefix("--start="))
		elif arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--dist="):
			_shot_dists.clear()
			for v in arg.trim_prefix("--dist=").split(","):
				_shot_dists.append(float(v))


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


func _process(delta: float) -> void:
	if not _frames_dir.is_empty() or not _shots_dir.is_empty() or "--sim" in OS.get_cmdline_user_args():
		return                                           # 캡처·통과 검사는 아래 함수가 직접 한 걸음씩 진행
	_step(delta)
	if _dist >= StageBuilderV2.STAGE_LENGTH:
		get_tree().reload_current_scene()                 # 끝 → 처음부터 (좀비·보급도 새로)
		return
	_label.text = ("%d fps" % Engine.get_frames_per_second()) if _showcase else ("%dm   %d fps" % [StageBuilderV2.remaining(_dist), Engine.get_frames_per_second()])   # 폰 성능 확인용 (N-01: S24 Ultra 60fps)


# 플레이 테스트 조작: 누른 채 좌우로 끌기 (폰) / 마우스 끌기 (PC)
func _unhandled_input(event: InputEvent) -> void:
	if not _play:
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
		_steer_target = _steer_x0 + (event.position.x - _touch_x0) / w * DRAG_WIDTH_M
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_touch_id = 0 if event.pressed else -1
		_touch_x0 = event.position.x
		_steer_x0 = _steer_target
	elif event is InputEventMouseMotion and _touch_id == 0:
		_steer_target = _steer_x0 + (event.position.x - _touch_x0) / w * DRAG_WIDTH_M
	_steer_target = clampf(_steer_target, -_lane(), _lane())


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
		vx = clampf((_steer_target - _x) * 8.0, -PLAY_STEER, PLAY_STEER)
	else:
		vx = clampf((_target_x() - _x) / maxf(delta, 0.001), -STEER_SPEED, STEER_SPEED)
	if _slide_t > 0.0:                                   # 막혀서 미끄러지는 중: 조작보다 우선 (조작 안 해도 빠져나간다)
		_slide_t -= delta
		vx = clampf((_slide_x - _x) * 6.0, -SLIDE_SPEED, SLIDE_SPEED)
		vz = RUN_SPEED * SLIDE_FORWARD                    # 비스듬한 차 면을 계속 밀면 반대로 밀려나 옆걸음이 막힌다 → 앞으로는 살살
		_steer_target = _x                                # 손을 떼도 제자리로 끌려가지 않게
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
	_bump = maxf(_bump - delta * 3.0, 0.0)
	_builder.update_atmosphere(_dist)   # 600m 이후 하늘·안개가 회색으로 무거워짐
	_apply_camera(_time)
	if _showcase:
		_showcase.update(_dist, _x, delta)
	_label.text = "%dm" % StageBuilderV2.remaining(_dist)


# 자동 달리기: 앞에 있는 가장 가까운 장애물 "줄"(앞뒤 7m 안에 모인 것들)의 막힌 구간을 모아,
# 빈 틈 가운데 지금 위치에서 가장 가까운 곳으로 비킨다 (차 두 대가 벽을 쌓고 틈이 하나뿐인 카드도 통과)
func _target_x() -> float:
	if "--straight" in OS.get_cmdline_user_args():
		return _x                                         # 손 놓고 달리기 검사: 조작 없이 미끄러짐·점프만으로 빠져나가는지 (--sim --straight)
	var wander := sin(_time * 0.35) * 1.2              # 장애물이 없으면 길 안에서 천천히 좌우로
	var near_z := INF
	for ob in _builder.obstacles:
		var hd: float = ob.get("half_depth", 1.0)
		if ob.get("top", 9.0) >= JUMP_MAX and ob["z"] + hd - _dist > -0.3 and ob["z"] - hd - _dist < LOOK_AHEAD:
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
		if ob.get("top", 9.0) < JUMP_MAX:
			continue                                          # 낮은 것은 뛰어넘으니 피하지 않는다
		if absf(ob["z"] - near_z) < reach + hd2 and ob["z"] + hd2 - _dist > -0.3:
			var m: float = ob["half_width"] + PLAYER_RADIUS + 0.35
			blocked.append([ob["x"] - m, ob["x"] + m])
	blocked.sort_custom(func(a, b): return a[0] < b[0])
	var lane := _lane()
	var best := NAN
	var best_cost := INF
	var start := -lane
	for bl in blocked + [[lane, lane]]:
		if bl[0] > start:                                  # [start, bl[0]] 이 빈 틈
			var e0: float = bl[0]
			var tx: float = clampf(pref, start + 0.1, e0 - 0.1) if e0 - start > 0.2 else (start + e0) * 0.5
			var cost: float = absf(tx - pref)
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
		if n.y > 0.3 and _grounded:                       # 낮은 것의 모서리·비탈(타이어·잔해)에 걸렸다 → 폴짝 넘는다
			_vy = JUMP_SPEED
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
					_vy = JUMP_SPEED                              # 끼었으면 한 번 뛰어 본다 (낮은 짐 더미 위로)
	_body.position.x = clampf(_body.position.x, -_lane(), _lane())
	var moved := before.z - _body.position.z
	if moved < want * 0.3 and _time > 0.5 and _bump <= 0.0:
		_bump = 1.0                                       # 정면으로 막혔다 → 화면을 흔든다
		print("[bump] %.1fm x=%.2f" % [-_body.position.z, _body.position.x])
	_dist = -_body.position.z
	_x = _body.position.x


# 바로 앞(JUMP_LOOK 안)에 낮은 장애물이 몸과 겹치면 저절로 뛴다 — 사용자는 점프를 조작하지 않는다
func _auto_jump() -> void:
	if not _grounded:
		return
	for ob in _builder.obstacles:
		if ob.get("top", 9.0) >= JUMP_MAX:
			continue
		var ahead: float = ob["z"] - ob.get("half_depth", 1.0) - _dist
		if ahead > -0.3 and ahead < JUMP_LOOK and absf(ob["x"] - _x) < ob["half_width"] + PLAYER_RADIUS:
			_vy = JUMP_SPEED
			_grounded = false
			_jumps += 1
			return


func _apply_camera(t: float) -> void:
	# 발걸음 흔들림 + 살짝 좌우로 흔들리는 시선 (달리는 느낌)
	var step := sin(t * TAU * BOB_FREQ)
	var sway := sin(t * TAU * BOB_FREQ * 0.5)
	var shake := _bump * _bump * 0.06 * sin(t * 60.0)
	var air := _body.position.y
	_camera.position = Vector3(_x + sway * 0.04 + shake, EYE_HEIGHT + air + (0.0 if air > 0.01 else absf(step) * BOB_AMP), -_dist)
	var look := 0.0 if _play else sin(t * 0.35) * -4.0      # 플레이 중에는 시선이 멋대로 돌지 않게
	_camera.rotation = Vector3(deg_to_rad(-2.0 + step * 0.4), deg_to_rad(look), deg_to_rad(sway * 0.6 + shake * 40.0))


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

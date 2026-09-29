# 스테이지 미리보기 — 주인: A
# 1인칭 시점으로 초속 5m(PRD F-01) 자동 달리기를 흉내 내며 1,000m를 훑는다.
# 앞 18m 안의 장애물을 보고 좌우로 피해 간다 (플레이어가 드래그로 피하는 모습 흉내).
#
# 폰·PC 실행: 끝(1,000m)에 닿으면 처음으로 돌아가 반복
# 영상 프레임: godot --path godot --resolution 1560x720 -- --frames=<폴더>
#              → 1/30초씩 진행하며 그려진 장면을 JPG 6,000장으로 저장 후 종료 (ffmpeg로 mp4 조립)
#              Movie Maker를 쓰지 않는 이유: macOS가 가려진 창의 그리기를 건너뛰어 영상이 어긋났다
#              실행 예: --resolution 320x148 --position 0,0 --always-on-top (구석의 작은 창, 영상은 1560x720)
# 지점 캡처:   godot --path godot -- --shots=<폴더> [--dist=0,250,500,750,990]
extends Node3D

const RUN_SPEED := 5.0      # m/s (PRD F-01)
const EYE_HEIGHT := 1.6
const BOB_FREQ := 2.6       # 발걸음 주기 (Hz)
const BOB_AMP := 0.05
const LOOK_AHEAD := 18.0    # 이만큼 앞의 장애물부터 피하기 시작
const DODGE_MARGIN := 1.1   # 장애물 옆으로 두는 여유 (m)
const STEER_SPEED := 2.2    # 좌우 이동 속도 (m/s)
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
var _shot_dists: Array[float] = [0.0, 250.0, 500.0, 750.0, 990.0]


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
	_camera.far = 60.0
	holder.add_child(_camera)
	_camera.make_current()
	_build_overlay(holder)
	if not _frames_dir.is_empty():
		_capture_frames()
	elif not _shots_dir.is_empty():
		_capture_shots()


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
	if not _frames_dir.is_empty() or not _shots_dir.is_empty():
		return                                           # 캡처 모드는 아래 함수가 직접 한 걸음씩 진행
	_step(delta)
	if _dist >= StageBuilderV2.STAGE_LENGTH:
		_dist = 0.0
		_x = 0.0
	_label.text = "%dm   %d fps" % [StageBuilderV2.remaining(_dist), Engine.get_frames_per_second()]   # 폰 성능 확인용 (N-01: S24 Ultra 60fps)


# 한 걸음 진행: 앞으로 달리고, 장애물을 보고 좌우로 비키고, 카메라를 흔든다
func _step(delta: float) -> void:
	_time += delta
	_dist += RUN_SPEED * delta
	_x = move_toward(_x, _target_x(), STEER_SPEED * delta)
	_builder.update_atmosphere(_dist)   # 600m 이후 하늘·안개가 회색으로 무거워짐
	_apply_camera(_time)
	_label.text = "%dm" % StageBuilderV2.remaining(_dist)


# 앞에 있는 가장 가까운 장애물을 보고, 그 옆으로 비켜설 x를 정한다
func _target_x() -> float:
	var nearest: Dictionary = {}
	for ob in _builder.obstacles:
		var ahead: float = ob["z"] - _dist
		if ahead > -2.0 and ahead < LOOK_AHEAD:
			if nearest.is_empty() or ob["z"] < nearest["z"]:
				nearest = ob
	var wander := sin(_time * 0.35) * 1.2              # 장애물이 없으면 길 안에서 천천히 좌우로
	if nearest.is_empty():
		return wander
	var ox: float = nearest["x"]
	var clear: float = nearest["half_width"] + DODGE_MARGIN
	if absf(_x - ox) >= clear:
		return _x                                       # 이미 비켜서 있으면 그대로
	var left := ox - clear
	var right := ox + clear
	var lane := StageBuilderV2.LANE_HALF - 0.5
	if left < -lane:
		return right
	if right > lane:
		return left
	return left if absf(_x - left) < absf(_x - right) else right


func _apply_camera(t: float) -> void:
	# 발걸음 흔들림 + 살짝 좌우로 흔들리는 시선 (달리는 느낌)
	var step := sin(t * TAU * BOB_FREQ)
	var sway := sin(t * TAU * BOB_FREQ * 0.5)
	_camera.position = Vector3(_x + sway * 0.04, EYE_HEIGHT + absf(step) * BOB_AMP, -_dist)
	_camera.rotation = Vector3(deg_to_rad(-2.0 + step * 0.4), deg_to_rad(sin(t * 0.35) * -4.0), deg_to_rad(sway * 0.6))


# 영상용: 1/30초씩 진행하며 한 장이 그려질 때마다 JPG로 저장 (창이 가려져 느려져도 프레임이 빠지거나 겹치지 않음)
func _capture_frames() -> void:
	DirAccess.make_dir_recursive_absolute(_frames_dir)
	var total := int(StageBuilderV2.STAGE_LENGTH / RUN_SPEED * FRAME_FPS)
	if _frame_count > 0:
		total = _frame_count
	for i in _frame_start:                               # 이어 찍기: 앞부분은 이동만 계산 (같은 경로가 되도록)
		_step(1.0 / FRAME_FPS)
	for i in 3:                                          # 첫 프레임 전에 그림자·가시 범위 준비
		await get_tree().process_frame
	for i in range(_frame_start, total):
		_step(1.0 / FRAME_FPS)
		# 카메라 이동은 다음 엔진 프레임에 렌더러로 전달된다 → 그 프레임이 다 그려질 때까지 기다린 뒤 저장
		# (강제 그리기 force_draw는 옮기기 전 장면을 그려서 같은 장면이 반복 저장됐다)
		await RenderingServer.frame_post_draw
		var img := _frame_vp.get_texture().get_image()
		img.save_jpg("%s/f_%05d.jpg" % [_frames_dir, i], 0.88)
		if i % 300 == 0:
			print("[preview] frame %d / %d  (%dm)" % [i, total, int(_dist)])
	print("[preview] frames done: %d" % total)
	get_tree().quit()


func _capture_shots() -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	for d in _shot_dists:
		_dist = d
		_x = 0.0
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

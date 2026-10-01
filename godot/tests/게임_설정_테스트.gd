extends SceneTree

var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, text: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + text)
	if not ok: failures += 1
func _run() -> void:
	var path := "res://scripts/services/게임_설정.gd"
	if not ResourceLoader.exists(path):
		check(false, "설정 모델 구현 존재")
		quit(1)
		return
	var script = load(path)
	var model = script.new()
	check(model.values() == {"control_mode":"drag", "sensitivity":1.0, "sfx_volume":1.0, "bgm_volume":1.0, "tilt_zero":0.0, "tutorial_seen":false}, "기본 설정·원래 음량 배수 보존")
	if not model.has_method("save_settings"):
		check(false, "검증·원자적 저장·복구 구현")
		quit(1)
		return
	model.storage_path = "res://tests/게임_설정_테스트.cfg"
	check(model.load_settings(), "없는 파일은 기본값으로 시작")
	check(model.save_settings({"control_mode":"tilt", "sensitivity":9, "sfx_volume":-2, "bgm_volume":0.25, "tilt_zero":0.125, "tutorial_seen":true}), "설정 원자적 저장")
	var second = script.new()
	second.storage_path = model.storage_path
	check(second.load_settings(), "설정 재로드")
	check(second.values() == {"control_mode":"tilt", "sensitivity":2.0, "sfx_volume":0.0, "bgm_volume":0.25, "tilt_zero":0.125, "tutorial_seen":true}, "전체 키·범위 검증·지속성")
	check(second.save_settings({"sensitivity":"bad", "sfx_volume":NAN, "bgm_volume":INF, "control_mode":"bad", "tutorial_seen":"true"}), "잘못된 타입도 안전한 기존값으로 저장")
	check(second.values().sensitivity == 2.0 and second.values().sfx_volume == 0.0 and second.values().bgm_volume == 0.25 and second.values().control_mode == "tilt", "비수치·NaN·무한대·잘못된 모드 보존")
	check(second.set_tutorial_seen(false), "안내 완료 상태 저장")
	var before: Dictionary = second.values()
	var file := FileAccess.open(second.storage_path, FileAccess.WRITE)
	file.store_string("[broken")
	file.close()
	check(not second.load_settings() and second.values() == before, "손상된 파일 로드 실패시 기존 메모리 설정 보존")
	check(FileAccess.get_file_as_string(second.storage_path) == "[broken", "손상 파일 자동 덮어쓰기 금지")
	second.storage_path = "res://tests/missing_directory/settings.cfg"
	check(not second.save_settings({"sensitivity":0.5}) and second.values() == before, "저장 실패시 메모리 설정 보존")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(model.storage_path))
	await _test_screen()
	print("GAME_SETTINGS_TESTS: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func _test_screen() -> void:
	var path := "res://scripts/ui/게임_설정_화면.gd"
	if not ResourceLoader.exists(path):
		check(false, "설정 화면 구현 존재")
		return
	var screen = load(path).new()
	screen.configure({"control_mode":"tilt", "sensitivity":1.4, "bgm_volume":0.3, "tutorial_seen":true, "tilt_zero":0.125}, false)
	root.add_child(screen)
	await process_frame
	var mode: OptionButton = screen.find_child("ControlMode",true,false)
	check(mode.is_item_disabled(1) and mode.selected == 0 and "PC" in screen.find_child("TiltAvailability",true,false).text, "PC 기울이기 비활성·이유·드래그 대체")
	var saves := []
	screen.saved.connect(func(data): saves.append(data))
	var slider: HSlider = screen.find_child("SensitivitySlider",true,false)
	slider.value = 2.0
	check(saves.is_empty() and "2.00" in screen.find_child("SensitivityValue",true,false).text, "값 미리보기·변경만으로 저장 신호 없음")
	screen.find_child("SaveSettingsButton",true,false).pressed.emit()
	check(saves.size() == 1 and saves[0] == {"control_mode":"drag", "sensitivity":2.0, "sfx_volume":1.0, "bgm_volume":0.3, "tutorial_seen":true, "tilt_zero":0.125}, "저장 버튼 전체 검증된 설정 신호")
	var backs := []
	screen.back_requested.connect(func(): backs.append(true))
	screen.find_child("BackSettingsButton",true,false).pressed.emit()
	check(backs.size() == 1, "뒤로 버튼 실제 신호")
	check(screen.find_child("CalibrateButton",true,false).disabled, "센서 없는 영점 버튼 비활성")
	await process_frame
	check(screen.find_child("SaveSettingsButton",true,false).has_focus(), "설정 실제 키보드 포커스")
	screen.configure({"control_mode":"tilt", "sensitivity":-5, "sfx_volume":9, "bgm_volume":-1}, true)
	await process_frame
	check(not screen.find_child("CalibrateButton",true,false).disabled, "센서 가능시 영점 버튼 활성")
	var calibrations := []
	screen.calibrate_requested.connect(func(): calibrations.append(true))
	screen.find_child("CalibrateButton",true,false).pressed.emit()
	check(calibrations.size() == 1, "영점 요청 실제 신호")
	screen.find_child("SaveSettingsButton",true,false).pressed.emit()
	check(saves[1].sensitivity == 0.5 and saves[1].sfx_volume == 1.0 and saves[1].bgm_volume == 0.0 and saves[1].control_mode == "tilt", "화면 입력 클램프·기울이기 유지")
	for button_name in ["SaveSettingsButton","BackSettingsButton","CalibrateButton"]:
		check(screen.find_child(button_name,true,false).custom_minimum_size.y >= 50, "버튼 최소 50px: "+button_name)
	check(screen.find_child("SettingsScroll",true,false) is ScrollContainer, "설정 반응형 스크롤")
	for viewport_size in [Vector2i(1280,720),Vector2i(640,360)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		var scroll: ScrollContainer = screen.find_child("SettingsScroll",true,false)
		check(scroll.get_child(0).size.x <= scroll.size.x + 1, "설정 가로 넘침 없음: "+str(viewport_size))
	screen.find_child("SaveSettingsButton",true,false).grab_focus()
	var key := InputEventAction.new()
	key.action = "ui_accept"
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key = InputEventAction.new()
	key.action = "ui_accept"
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	check(saves.size() == 3, "설정 키보드 수락 입력 실제 저장 버튼 실행")
	screen.queue_free()
	await process_frame

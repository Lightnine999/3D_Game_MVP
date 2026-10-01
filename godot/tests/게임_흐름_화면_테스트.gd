extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, text: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + text)
	if not ok: failures += 1
func _run() -> void:
	var path := "res://scripts/ui/게임_흐름_화면.gd"
	if not ResourceLoader.exists(path):
		check(false, "스테이지 화면 구현 존재")
		quit(1)
		return
	var screen = load(path).new()
	screen.configure("stage", {"target_distance":750, "completed_missions":["M1","M3"], "best_distance_m":612.5})
	root.add_child(screen)
	await process_frame
	check(screen.name == "StageCardScreen", "configure-before-add 모드 이름")
	check(screen.find_child("TargetDistance",true,false).text == "목표 거리  750 m", "실제 750m 목표 거리")
	check(screen.find_child("BestDistance",true,false).text == "최고 기록  612.5 m", "최고 거리 실제 값")
	check(screen.find_child("MissionM1",true,false).text.begins_with("★") and screen.find_child("MissionM3",true,false).text.begins_with("★") and screen.find_child("MissionM2",true,false).text.begins_with("☆"), "미션 3개 실제 누적 달성")
	var plays := []
	screen.play_requested.connect(func(): plays.append(true))
	var play: Button = screen.find_child("PlayButton",true,false)
	play.pressed.emit()
	check(plays.size() == 1 and play.custom_minimum_size.y >= 50, "실제 시작 버튼 신호·최소 터치 크기")
	await process_frame
	check(play.has_focus(), "시작 버튼 실제 키보드 포커스")
	check(screen.find_child("ScreenScroll",true,false) is ScrollContainer, "반응형 세로 스크롤")
	if not screen.has_method("_tutorial"):
		check(false, "짧은 세 부분 튜토리얼 구현")
		screen.queue_free()
		await process_frame
		quit(1)
		return
	screen.configure("tutorial")
	await process_frame
	check(screen.name == "TutorialScreen" and screen.find_children("TutorialSection*","Label",true,false).size() == 3, "튜토리얼 한 화면 세 부분")
	var content := ""
	for label in screen.find_children("TutorialSection*","Label",true,false): content += label.text
	check("A/D" in content and "드래그" in content and "Space" in content and "오른쪽" in content and "자동 재장전" in content and "1회" in content and "Esc / P" in content, "실제 조작·보급·칼·일시정지 안내")
	var completed := []
	screen.tutorial_finished.connect(func(): completed.append(true))
	screen.find_child("PlayButton",true,false).pressed.emit()
	check(completed.size() == 1 and plays.size() == 2, "튜토리얼 완료 후 시작 신호")
	if not screen.has_method("_result"):
		check(false, "결과 화면 구현")
		screen.queue_free()
		await process_frame
		quit(1)
		return
	screen.configure("result", {"cleared":false, "distance_m":432.75, "kills":17, "duration_s":91.25, "knife_used":true, "death_reason":"좀비에게 물림", "mission_ids":["M2"], "test_mode":true, "save_status":"동기화 대기"})
	await process_frame
	check(screen.name == "ResultScreen" and screen.find_child("ScreenHeading",true,false).text == "탈출 실패", "사망 결과 모드")
	for entry in [["ResultDistance","달린 거리  432.75 m"],["ResultKills","처치 수  17"],["ResultDuration","플레이 시간  91.25 초"],["ResultKnife","칼 사용  사용함"],["ResultReason","사망 원인  좀비에게 물림"],["SaveStatus","저장 상태  동기화 대기"]]:
		check(screen.find_child(entry[0],true,false).text == entry[1], "결과 실제 값: "+entry[0])
	check("TEST MODE" in screen.find_child("TestModeNotice",true,false).text and "제외" in screen.find_child("TestModeNotice",true,false).text, "테스트 결과 일반 기록 제외 안내")
	check(screen.find_child("MissionM2",true,false).text.begins_with("★") and screen.find_child("MissionM3",true,false).text.begins_with("☆"), "결과 미션을 전달값으로 표시")
	var actions := []
	screen.retry_requested.connect(func(): actions.append("retry"))
	screen.back_requested.connect(func(): actions.append("title"))
	screen.support_requested.connect(func(): actions.append("support"))
	for button_name in ["RetryButton","TitleButton","ResultSupportButton"]: screen.find_child(button_name,true,false).pressed.emit()
	check(actions == ["retry","title","support"], "결과 실제 버튼 신호")
	screen.configure("result", {"cleared":true, "knife_used":false})
	await process_frame
	check(screen.find_child("ScreenHeading",true,false).text == "탈출 성공" and screen.find_child("ResultKnife",true,false).text == "칼 사용  사용하지 않음", "성공·칼 미사용 결과")
	screen.configure("stage", {"target_distance":750, "completed_missions":[], "missions":[{"id":"M2", "title":"현재 처치 목표"}]})
	root.size = Vector2i(1280,720)
	await process_frame
	await process_frame
	check("현재 처치 목표" in screen.find_child("MissionM2",true,false).text, "전달한 실제 미션 설명 사용")
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
	check(plays.size() == 3, "키보드 수락 입력으로 실제 버튼 실행")
	for viewport_size in [Vector2i(1280,720), Vector2i(640,360)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		var scroll: ScrollContainer = screen.find_child("ScreenScroll",true,false)
		check(scroll.size.x > 0 and scroll.get_child(0).size.x <= scroll.size.x + 1, "가로 넘침 없는 반응형: "+str(viewport_size))
	screen.queue_free()
	await process_frame
	print("GAME_FLOW_SCREEN_TESTS: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

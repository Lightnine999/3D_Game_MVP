extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := "res://scripts/ui/게임_테스트_패널.gd"
	if not ResourceLoader.exists(path):
		printerr("FAIL: 사람이 조작할 게임 테스트 패널 없음")
		quit(1)
		return
	var panel: Control = load(path).new()
	panel.configure(true)
	root.add_child(panel)
	await process_frame
	var calls: Array = []
	panel.command_requested.connect(func(command: String, value: Variant) -> void: calls.append([command, value]))
	(panel.find_child("Skip200Button", true, false) as Button).pressed.emit()
	(panel.find_child("GrantAmmoButton", true, false) as Button).pressed.emit()
	(panel.find_child("GrantKnifeButton", true, false) as Button).pressed.emit()
	var kinds: OptionButton = panel.find_child("ZombieKind", true, false)
	kinds.select(2)
	(panel.find_child("SpawnZombieButton", true, false) as Button).pressed.emit()
	panel.update_snapshot({"distance_m": 120.0, "kills": 2, "ammo": 4, "reserve": 12})
	var text := (panel.find_child("DebugRunStats", true, false) as Label).text
	var passed: bool = calls.size() == 4 and calls[0][0] == "skip" and calls[1][0] == "ammo" and calls[2][0] == "knife" and calls[3] == ["spawn", "tank"] and text.contains("120") and text.contains("2")
	var scroll: ScrollContainer = panel.find_child("TestPanelScroll", true, false)
	if scroll == null:
		printerr("FAIL: 작은 창에서도 테스트 패널의 닫기·소환 버튼에 도달할 스크롤이 필요함")
		passed = false
	else:
		for viewport_size in [Vector2i(1280, 720), Vector2i(640, 360)]:
			root.size = viewport_size
			root.content_scale_size = viewport_size
			panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			await process_frame
			await process_frame
			print("PANEL_LAYOUT ", viewport_size, " canvas=", root.get_visible_rect().size, " panel=", panel.size, " scroll=", scroll.size, " content=", scroll.get_child(0).size)
			passed = passed and panel.size.y <= viewport_size.y + 1
			passed = passed and scroll.get_child(0).size.x <= scroll.size.x + 1
	panel.configure(false)
	passed = passed and not panel.visible
	panel.queue_free()
	await process_frame
	print("PLAYABLE_TEST_PANEL: ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)

extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var user_path := ProjectSettings.globalize_path("user://").replace("\\", "/")
	var isolated_root := OS.get_environment("APPDATA").replace("\\", "/")
	if not isolated_root.contains("/build/충돌검증/") or not user_path.begins_with(isolated_root + "/"):
		printerr("FAIL: isolated test user directory required")
		quit(1)
		return
	var stage = load("res://scenes/stage/stage_preview.tscn").instantiate()
	stage.service_managed = true
	root.add_child(stage)
	stage.set_process(false)
	stage._ui.confirm()
	var results: Array = []
	stage.service_finished.connect(func(value): results.append(value))
	stage._dead = true
	stage._dead_t = 10.0
	stage._process(0.0)
	check(results.is_empty(), "death offer waits for choice beyond four seconds")
	check(stage._retry.text == "결과 보기", "managed retry is result action")
	Inventory.add("revive")
	stage._setup_offer()
	stage._on_offer()
	check(stage._dead and stage._revive_pick and Inventory.count("revive") == 1, "team selection waits for RETRY without consuming")
	check(stage._retry.text == "RETRY", "selected revival shows the team RETRY action")
	stage._retry.pressed.emit()
	check(not stage._dead and stage._showcase._grace_t == 2.0, "team revival and two second grace preserved")
	check(stage.service_snapshot().test_mode, "local test revive excludes normal records")
	stage._dead = true
	stage._retry.pressed.emit()
	stage._retry.pressed.emit()
	check(results.size() == 1, "result delivered once only after choice")
	stage.queue_free()
	await process_frame
	print("TEAM_SERVICE_REVIVE: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

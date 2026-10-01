extends SceneTree

var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var initial_orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var packed: PackedScene = load("res://scenes/stage/stage_preview.tscn")
	var stage: Node = packed.instantiate()
	var implemented: bool = stage.has_method("service_snapshot") and stage.has_signal("service_finished") and stage.has_method("service_debug_command")
	_check(implemented, "기존 게임에 결과·측정·디버그 서비스 접점이 있어야 함")
	if not implemented:
		stage.free()
		_finish()
		return
	stage.set("service_managed", true)
	root.add_child(stage)
	await process_frame
	stage.set_process(false)
	stage._ui.confirm()
	var snap: Dictionary = stage.call("service_snapshot")
	_check(snap.get("target_distance") == 750.0, "현재 750m 수치 보존")
	_check(snap.get("ammo") == 7 and snap.get("kills") == 0, "시작 탄약 7발·실제 권총 처치 수 보존")
	var accepted: bool = stage.call("service_debug_command", "ammo", 12)
	_check(not accepted and stage.call("service_snapshot").get("ammo") == 7, "디버그 허용 전에는 탄약 조작 거부")
	stage.set("service_debug_enabled", true)
	_check(stage.call("service_debug_command", "ammo", 12), "디버그 빌드의 탄약 지급")
	_check(stage.call("service_snapshot").get("test_mode") == true, "치트 사용 판은 테스트 기록으로 표기")
	_check(stage.call("service_debug_command", "invulnerable", true), "무적 테스트 명령")
	_check(stage.call("service_debug_command", "spawn", "walker"), "종류별 실제 좀비 소환")
	var director: Node = stage.get("_showcase")
	var zombies: Array = director.get("_zombies")
	var last: Dictionary = zombies.back()
	director.call("_shoot", last)
	_check(stage.call("service_snapshot").get("kills") == 1, "실제 권총 사망만 처치 수에 반영")
	var finished: Array[Dictionary] = []
	stage.connect("service_finished", func(result: Dictionary) -> void: finished.append(result))
	stage.set("_dist", 750.0)
	(stage.get("_body") as Node3D).position.z = -750.0
	stage.call("_process", 0.0)
	stage.call("_process", 0.0)
	_check(finished.size() == 1 and finished[0].get("cleared", false), "완주 시 장면 재시작 대신 결과를 정확히 1회 전달")
	_check(finished.size() == 1 and finished[0].get("test_mode", false), "결과에 테스트 모드 유지")
	last.clear()
	zombies.clear()
	stage.queue_free()
	await process_frame
	_check(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) <= initial_orphans, "반복 플레이 뒤 애니메이션 원본의 고아 노드를 남기지 않음")
	call_deferred("_finish")

func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		_failures += 1
		printerr("FAIL: ", message)

func _finish() -> void:
	print("PLAYABLE_STAGE_ADAPTER: ", "PASS" if _failures == 0 else "FAIL")
	quit(0 if _failures == 0 else 1)

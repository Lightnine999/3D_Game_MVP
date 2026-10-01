extends SceneTree

var _failures := 0
var _path := "res://tests/동기화_임시자료_%d.json" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var api := ServiceAPI.new()
	var outbox := ServiceOutbox.new()
	_check(api.has_method("fetch_progress"), "본인 서버 진행 읽기 접점")
	_check(outbox.has_method("queue_event_once"), "플레이 ID로 재시도 중복 방지")
	_check(outbox.has_method("clear_owner"), "탈퇴한 본인의 전송 대기 기록만 정리")
	if _failures:
		api.free()
		outbox.free()
		_finish()
		return
	outbox.storage_path = _path
	_check(outbox.load_queue(), "별도 파일의 새 발신함")
	var body := {"stage_id": "field_01", "mission_id": "M1"}
	_check(outbox.call("queue_event_once", "owner-A", "run_test_M1", "mission", body).get("ok", false), "첫 이벤트 저장")
	_check(outbox.call("queue_event_once", "owner-A", "run_test_M1", "mission", body).get("ok", false), "같은 ID·내용 재시도 허용")
	_check(outbox.pending_for("owner-A").size() == 1, "같은 플레이를 두 번 저장하지 않음")
	_check(not outbox.call("queue_event_once", "owner-A", "run_test_M1", "distance", {"distance_m": 12}).get("ok", true), "같은 ID·다른 내용은 거부")
	outbox.queue_event("owner-B", "distance", {"distance_m": 42})
	_check(outbox.call("clear_owner", "owner-A").get("ok", false), "A의 기록 정리")
	_check(outbox.pending_for("owner-A").is_empty() and outbox.pending_for("owner-B").size() == 1, "타인의 기록 보존")
	var auth := ServiceAuth.new()
	auth._user_id = "owner-B"
	auth._access_token = "test-access"
	auth._refresh_token = "test-refresh"
	auth._expires_at = int(Time.get_unix_time_from_system()) + 3600
	root.add_child(auth)
	root.add_child(api)
	api.configure(auth, "https://project.supabase.co", "sb_publishable_dummy")
	var calls: Array[String] = []
	api.transport_override = func(_method: int, path: String, _payload: String, _token: String) -> Dictionary:
		calls.append(path)
		if path.begins_with("/rest/v1/mission_progress?"):
			return {"ok": true, "status": 200, "data": [{"stage_id": "field_01", "mission_id": "M2"}]}
		return {"ok": true, "status": 200, "data": [{"payload": {"distance_m": 19}}, {"payload": {"distance_m": 105}}, {"payload": {"distance_m": 70}}]}
	var restored: Dictionary = await api.call("fetch_progress")
	_check(restored.get("ok", false) and restored.get("best_distance_m") == 105.0 and restored.get("missions", []).size() == 1, "실제 응답 구조에서 미션·최고 거리 복원")
	for path in calls:
		_check(path.contains("user_id=eq.owner-B"), "조회는 현재 계정으로 제한")
	api.transport_override = func(_method: int, _path: String, _payload: String, _token: String) -> Dictionary:
		return {"ok": true, "status": 200, "data": [{"stage_id": "field_01"}]}
	_check(not (await api.call("fetch_progress")).get("ok", true), "손상된 미션 응답은 복원 성공으로 처리하지 않음")
	outbox.free()
	api.queue_free()
	auth.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	_finish()

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", message)

func _finish() -> void:
	print("PLAYABLE_SYNC_BOUNDARY: ", "PASS" if _failures == 0 else "FAIL")
	quit(0 if _failures == 0 else 1)

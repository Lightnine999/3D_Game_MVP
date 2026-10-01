extends SceneTree

const OUTBOX_PATH := "res://scripts/services/서비스_발신함.gd"
var failures := 0
var _path := "user://service_outbox_test_%d.json" % Time.get_ticks_usec()


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)


func _run() -> void:
	if not ResourceLoader.exists(OUTBOX_PATH):
		printerr("FAIL: 발신함 서비스가 아직 없음")
		quit(1)
		return
	var outbox: Node = load(OUTBOX_PATH).new()
	outbox.storage_path = _path
	_check(outbox.load_queue(), "빈 발신함 로드")
	var first: Dictionary = outbox.queue_event("local-guest-A", "mission", {"stage_id": "field_01", "mission_id": "M1"})
	_check(first.get("ok", false), "미션 이벤트 로컬 저장")
	var id := str(first.get("id", ""))
	_check(id.begins_with("evt_") and id.length() <= 80, "서버 허용 형식의 고유 ID")
	_check(FileAccess.file_exists(_path), "종료 전 디스크에 저장")
	_check(not outbox.queue_event("local-guest-A", "purchase", {"item": "badge"}).get("ok", false), "구매 이벤트는 발신함에서 금지")
	var restarted: Node = load(OUTBOX_PATH).new()
	restarted.storage_path = _path
	_check(restarted.load_queue(), "재시작 후 로드")
	var pending: Array = restarted.pending_for("local-guest-A")
	_check(pending.size() == 1 and pending[0].get("id") == id, "재시작 시 ID·본문 보존")
	_check(restarted.pending_for("account-B").is_empty(), "다른 계정에 노출 금지")
	var remote: Dictionary = restarted.queue_event("account-B", "distance", {"distance_m": 12})
	_check(remote.get("ok", false), "다른 계정 이벤트도 별도로 보관")
	var auth := ServiceAuth.new()
	auth.session_path = _path + ".auth"
	if auth.session_path == ServiceAuth.SESSION_PATH:
		printerr("FAIL: 발신함 회귀의 인증 저장 경로가 실제 사용자 세션과 격리되지 않음")
		auth.free()
		outbox.free()
		restarted.free()
		DirAccess.remove_absolute(_path)
		DirAccess.remove_absolute(_path + ".tmp")
		quit(1)
		return
	auth._user_id = "account-B"
	auth._access_token = "test-access"
	auth._refresh_token = "test-refresh"
	auth._expires_at = int(Time.get_unix_time_from_system()) + 3600
	root.add_child(auth)
	var api := ServiceAPI.new()
	root.add_child(api)
	api.configure(auth, "https://project.supabase.co", "sb_publishable_dummy")
	var calls: Array[Dictionary] = []
	var responses: Array[Dictionary] = [
		{"ok": false, "status": 503, "error": "server_unavailable"},
		{"ok": true, "status": 200, "data": {"received": 0, "inserted": 0}},
		{"ok": true, "status": 200, "data": {"received": 1, "inserted": 0}},
	]
	api.transport_override = func(method: int, path: String, payload: String, token: String) -> Dictionary:
		calls.append({"method": method, "path": path, "body": JSON.parse_string(payload), "token": token})
		return responses.pop_front()
	var failed: Dictionary = await restarted.flush_for(auth, api)
	_check(not failed.get("ok", true) and restarted.pending_for("account-B").size() == 1, "서버 오류 후 ID 유지")
	var invalid_ack: Dictionary = await restarted.flush_for(auth, api)
	_check(not invalid_ack.get("ok", true) and restarted.pending_for("account-B").size() == 1, "수신 건수 불일치 시 삭제 금지")
	var acknowledged: Dictionary = await restarted.flush_for(auth, api)
	_check(acknowledged.get("ok", false) and calls.size() == 3, "중복 재전송의 inserted=0도 정상 수신")
	_check(calls[0].path == "/functions/v1/sync-progress" and calls[0].method == HTTPClient.METHOD_POST and calls[0].token == "test-access", "인증된 동기화 함수만 호출")
	_check(calls[0].body.get("events", []).size() == 1 and calls[0].body.events[0].id == remote.id and calls[1].body.events[0].id == remote.id, "재시도 때 ID 고정, 타인 이벤트 제외")
	_check(restarted.pending_for("account-B").is_empty() and restarted.pending_for("local-guest-A").size() == 1, "성공한 계정 이벤트만 정리")
	var verified: Node = load(OUTBOX_PATH).new()
	verified.storage_path = _path
	_check(verified.load_queue() and verified.pending_for("local-guest-A").size() == 1 and verified.pending_for("account-B").is_empty(), "디스크에서도 ACK 반영")
	verified.free()
	if not restarted.has_method("adopt_offline_guest"):
		printerr("FAIL: 오프라인 게스트 기록을 익명 서버 계정으로 인계하는 경로 없음")
		api.queue_free(); auth.queue_free(); outbox.free(); restarted.free()
		DirAccess.remove_absolute(_path)
		quit(1)
		return
	auth._pending_offline_guest_id = "local-guest-A"
	_check(not restarted.adopt_offline_guest(auth).get("ok", false), "이메일 계정으로 오프라인 기록 자동 합치기 금지")
	auth._guest = true
	var adopted: Dictionary = restarted.adopt_offline_guest(auth)
	_check(adopted.get("ok", false) and adopted.get("moved") == 1, "익명 서버 계정에 기록 인계")
	_check(restarted.pending_for("local-guest-A").is_empty() and restarted.pending_for("account-B").size() == 1, "인계 후 소유자만 변경, ID 보존")
	_check(restarted.pending_for("account-B")[0].id == id, "인계 전 이벤트 ID를 재발급하지 않음")
	auth.acknowledge_offline_adoption()
	api.queue_free()
	auth.queue_free()
	outbox.free()
	restarted.free()
	await process_frame
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")
	DirAccess.remove_absolute(_path + ".auth")
	DirAccess.remove_absolute(_path + ".auth.tmp")
	print("SERVICE_OUTBOX_PERSISTENCE: ", "PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)

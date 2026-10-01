extends SceneTree

const ENTRY_SCENE := preload("res://scenes/ui/서비스_진입.tscn")
var _queue_path := "user://service_reconnect_queue_%d.json" % Time.get_ticks_usec()
var _session_path := "user://service_reconnect_auth_%d.json" % Time.get_ticks_usec()

class FakeAuth extends "res://scripts/services/서비스_인증.gd":
	var calls := 0

	func _transport(method: String, path: String, _body: Dictionary, _bearer: String = "") -> Dictionary:
		if method != "POST" or path != "/signup":
			return {"ok": false, "error": "network_unavailable"}
		calls += 1
		return {"ok": true, "data": {"access_token": "test-access", "refresh_token": "test-refresh", "expires_in": 3600, "user": {"id": "remote-recovered", "is_anonymous": true}}}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fake := FakeAuth.new()
	fake.session_path = _session_path
	fake.start_offline_guest()
	var old_id := fake.get_user_id()
	var entry := ENTRY_SCENE.instantiate() as Control
	entry.set("auth_override", fake)
	entry.set("outbox_storage_path_override", _queue_path)
	root.add_child(entry)
	var queue := entry.get_child(2)
	var queued: Dictionary = queue.queue_event(old_id, "mission", {"stage_id": "field_01", "mission_id": "M1"})
	var api := entry.get_child(1) as ServiceAPI
	var sync_ids: Array[String] = []
	api.transport_override = func(_method: int, path: String, body: String, _token: String) -> Dictionary:
		if path.ends_with("/sync-progress"):
			var parsed: Dictionary = JSON.parse_string(body)
			sync_ids.append(str(parsed.events[0].id))
			return {"ok": true, "status": 200, "data": {"received": 1, "inserted": 1}}
		return {"ok": true, "status": 200, "data": {"profile": {"user_id": "remote-recovered"}}}
	await entry.call("_sync_pending")
	var ok: bool = queued.get("ok", false) and fake.calls == 1 and fake.get_user_id() == "remote-recovered" and sync_ids == [str(queued.get("id"))] and queue.pending_for("remote-recovered").is_empty() and fake.pending_offline_guest_id().is_empty()
	if not ok:
		printerr("FAIL: 네트워크 복귀 시 같은 이벤트 ID의 게스트 계정 생성·자동 전송")
	entry.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_queue_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_queue_path + ".tmp"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_session_path))
	print("SERVICE_OFFLINE_RECONNECT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

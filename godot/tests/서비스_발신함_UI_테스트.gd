extends SceneTree

const ENTRY_SCENE := preload("res://scenes/ui/서비스_진입.tscn")
const OUTBOX_SCRIPT := preload("res://scripts/services/서비스_발신함.gd")
var _test_path := "user://service_outbox_ui_test_%d.json" % Time.get_ticks_usec()
var _session_path := "user://service_outbox_ui_auth_%d.json" % Time.get_ticks_usec()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var entry := ENTRY_SCENE.instantiate() as Control
	entry.set("outbox_storage_path_override", _test_path)
	root.add_child(entry)
	if entry.get_child_count() < 4 or entry.get_child(2).get_script() != OUTBOX_SCRIPT:
		printerr("FAIL: 서비스 진입에서 발신함 초기화 누락")
		entry.queue_free()
		await process_frame
		quit(1)
		return
	var outbox: Node = entry.get_child(2)
	var auth := entry.get_child(0) as ServiceAuth
	auth.session_path = _session_path
	auth._user_id = "remote-guest-1"
	auth._guest = true
	auth._access_token = "test-access"
	auth._refresh_token = "test-refresh"
	auth._expires_at = int(Time.get_unix_time_from_system()) + 3600
	auth._pending_offline_guest_id = "local-guest-1"
	var queued: Dictionary = outbox.queue_event("local-guest-1", "mission", {"stage_id": "field_01", "mission_id": "M1"})
	var api := entry.get_child(1) as ServiceAPI
	var calls: Array[String] = []
	api.transport_override = func(_method: int, path: String, payload: String, _token: String) -> Dictionary:
		calls.append(path)
		if path.ends_with("/sync-progress"):
			var body: Dictionary = JSON.parse_string(payload)
			return {"ok": true, "status": 200, "data": {"received": body.events.size(), "inserted": body.events.size()}}
		return {"ok": true, "status": 200, "data": {"profile": {"user_id": auth.get_user_id()}}}
	entry.call("_show_title")
	await create_timer(0.25).timeout
	var ok: bool = queued.get("ok", false) and calls.has("/functions/v1/sync-progress") and outbox.pending_for("remote-guest-1").is_empty() and auth.pending_offline_guest_id().is_empty()
	if not ok:
		printerr("FAIL: 타이틀에서 오프라인 게스트 기록 인계·서버 ACK 반영")
	entry.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_test_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_test_path + ".tmp"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_session_path))
	print("SERVICE_OUTBOX_UI: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

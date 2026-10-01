extends SceneTree

const Auth = preload("res://scripts/services/서비스_인증.gd")
var failures := 0
var _session_test_path := "user://service_auth_test_%d.json" % Time.get_ticks_usec()

class FakeAuth extends "res://scripts/services/서비스_인증.gd":
	var calls: Array[Dictionary] = []
	var replies: Array[Dictionary] = []

	func _transport(method: String, path: String, body: Dictionary, bearer: String = "") -> Dictionary:
		calls.append({"method": method, "path": path, "body": body.duplicate(true), "bearer": bearer})
		if replies.is_empty():
			return {"ok": false, "error": "network_unavailable"}
		return replies.pop_front()

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)

var _instances: Array[Node] = []

func _spawn() -> FakeAuth:
	var instance := FakeAuth.new()
	instance.session_path = _session_test_path
	_instances.append(instance)
	return instance

func _run() -> void:
	var auth := _spawn()
	_check(not auth.is_configured(), "default unconfigured")
	_check((await auth.sign_in_anonymous()).get("error") == "not_configured", "unconfigured no request")
	_check(auth.calls.is_empty(), "unconfigured transport untouched")
	auth.start_offline_guest()
	var local_id := auth.get_user_id()
	_check(auth.is_logged_in() and auth.is_guest() and not auth.has_remote_session(), "offline guest")
	_check(local_id != "", "offline id")
	var restored := _spawn()
	_check(restored.restore_local_session() and restored.get_user_id() == local_id, "offline guest persisted")
	auth.set_public_config("https://example.test/", "public-test-key")
	auth.replies.append({"ok": true, "data": {"access_token": "access-one", "refresh_token": "refresh-one", "expires_in": 3600, "user": {"id": "remote-one", "is_anonymous": true}}})
	_check((await auth.sign_in_anonymous()).get("ok", false), "anonymous session")
	_check(auth.get_user_id() == "remote-one" and auth.is_guest() and auth.has_remote_session(), "remote guest state")
	if not auth.has_method("pending_offline_guest_id") or not auth.has_method("acknowledge_offline_adoption"):
		printerr("FAIL: offline owner adoption marker missing")
		quit(1)
		return
	_check(auth.pending_offline_guest_id() == local_id, "offline owner retained until outbox adoption")
	_check(auth.calls[0].path == "/signup" and auth.calls[0].body == {"data": {}}, "anonymous endpoint")
	var restarted := _spawn()
	_check(restarted.restore_local_session() and restarted.has_remote_session() and restarted.get_user_id() == "remote-one", "remote persisted")
	_check(restarted.pending_offline_guest_id() == local_id, "pending adoption survives restart")
	auth.acknowledge_offline_adoption()
	_check(auth.pending_offline_guest_id().is_empty(), "offline adoption marker cleared only after explicit ACK")
	_check((await restarted.request_guest_email("a@example.test")).get("error") == "not_configured", "restoration does not store config")
	auth.replies.append({"ok": true, "data": {"id": "remote-one", "is_anonymous": true, "new_email": "a@example.test"}})
	_check((await auth.request_guest_email("a@example.test")).get("ok", false), "email linking request")
	_check(auth.calls[-1].method == "PUT" and auth.calls[-1].path == "/user" and auth.calls[-1].body == {"email": "a@example.test"}, "link uses updateUser")
	auth.replies.append({"ok": true, "data": {"id": "remote-one", "is_anonymous": true, "email": "a@example.test", "email_confirmed_at": ""}})
	_check((await auth.confirm_guest_email_and_password("password123")).get("error") == "email_not_confirmed", "confirmation required")
	_check(auth.calls.size() == 3 and auth.calls[-1].method == "GET", "no premature password update")
	auth.replies.append({"ok": true, "data": {"id": "remote-one", "is_anonymous": false, "email": "a@example.test", "email_confirmed_at": "2026-01-01T00:00:00Z"}})
	auth.replies.append({"ok": true, "data": {"id": "remote-one", "is_anonymous": false, "email": "a@example.test"}})
	_check((await auth.confirm_guest_email_and_password("password123")).get("ok", false), "confirmed password")
	_check(auth.get_user_id() == "remote-one" and not auth.is_guest(), "linked identity stable")
	_check(auth.calls[-2].method == "GET" and auth.calls[-2].path == "/user" and auth.calls[-1].body == {"password": "password123"}, "confirmation read then password write")
	var session_text := ""
	var file := FileAccess.open(_session_test_path, FileAccess.READ)
	if file != null:
		session_text = file.get_as_text()
		file = null # release the handle now; Windows keeps the file locked otherwise and the later sign_out() delete would silently fail
	_check(not session_text.is_empty() and not session_text.contains("password123") and session_text.contains("refresh-one"), "password not persisted; refresh persisted")
	auth.replies.append({"ok": true, "data": {"access_token": "access-two", "refresh_token": "refresh-two", "expires_in": 3600, "user": {"id": "account-two", "email": "b@example.test", "is_anonymous": false}}})
	_check((await auth.sign_in_password("b@example.test", "password456")).get("ok", false), "password login")
	_check(auth.calls[-1].path == "/token?grant_type=password" and auth.get_user_id() == "account-two", "password endpoint")
	_check((await auth.sign_in_password("bad", "short")).get("error") == "invalid_email", "input validation")
	auth.replies.append({"ok": true, "data": {"access_token": "access-three", "refresh_token": "refresh-three", "expires_in": 3600, "user": {"id": "account-two", "email": "b@example.test", "is_anonymous": false}}})
	auth.replies.append({"ok": true, "data": {}})
	auth._expires_at = 1
	_check((await auth.request_guest_email("c@example.test")).get("error") == "not_guest", "email linking only for guest")
	_check((await auth.request_password_reset("b@example.test")).get("ok", false), "recovery request")
	_check(auth.calls[-1].path == "/recover", "recovery endpoint")
	auth.sign_out()
	_check(not auth.is_logged_in() and not auth.has_remote_session(), "signout clears local session")
	_check(not _spawn().restore_local_session(), "signout persisted")
	_check(not FileAccess.file_exists(_session_test_path), "isolated test session removed")
	for instance in _instances:
		if is_instance_valid(instance):
			instance.free()
	print("ServiceAuth tests: %d failed" % failures)
	quit(1 if failures else 0)

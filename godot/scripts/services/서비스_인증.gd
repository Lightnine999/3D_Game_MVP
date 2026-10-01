class_name ServiceAuth
extends Node

# Supabase Auth REST only. Supply the public URL/key at runtime; never ship a service-role key.
# Email confirmation and recovery deep links require separate Android integration/real-device verification.
const SESSION_PATH := "user://service_auth_session.json"
const EXPIRY_MARGIN_SECONDS := 60

var session_path := SESSION_PATH # Tests inject an isolated path; production uses SESSION_PATH.
var _url := ""
var _public_key := ""
var _user_id := ""
var _email := ""
var _guest := false
var _offline := false
var _access_token := ""
var _refresh_token := ""
var _expires_at := 0
var _pending_email := ""
var _pending_offline_guest_id := ""
var _session_epoch := 0
var _session_error := "invalid_response"

func set_public_config(url: String, key: String) -> void:
	var clean := url.strip_edges().trim_suffix("/")
	_url = clean if clean.begins_with("https://") and not clean.contains("?") and not clean.contains("#") else ""
	_public_key = key.strip_edges() if not _url.is_empty() else ""

func is_configured() -> bool:
	return not _url.is_empty() and not _public_key.is_empty()

func is_logged_in() -> bool:
	return not _user_id.is_empty()

func is_guest() -> bool:
	return is_logged_in() and _guest

func has_remote_session() -> bool:
	return not _user_id.is_empty() and not _access_token.is_empty() and not _refresh_token.is_empty()

func get_user_id() -> String:
	return _user_id

func pending_offline_guest_id() -> String:
	return _pending_offline_guest_id

func acknowledge_offline_adoption() -> void:
	var previous := _snapshot()
	_pending_offline_guest_id = ""
	if not _save():
		_restore_snapshot(previous)

func display_name() -> String:
	if not is_logged_in():
		return "로그인 전"
	return "게스트" if _guest else (_email if not _email.is_empty() else "회원")

func restore_local_session() -> bool:
	if not FileAccess.file_exists(session_path):
		return false
	var file := FileAccess.open(session_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("version") != 1:
		return false
	var id := str(parsed.get("user_id", ""))
	if id.is_empty():
		return false
	var offline: bool = parsed.get("offline", false) == true
	var access := str(parsed.get("access_token", ""))
	var refresh := str(parsed.get("refresh_token", ""))
	if not offline and (access.is_empty() or refresh.is_empty()):
		return false
	if offline and (not access.is_empty() or not refresh.is_empty()):
		return false
	_session_epoch += 1
	_user_id = id
	_offline = offline
	_guest = parsed.get("guest", false) == true
	_email = str(parsed.get("email", ""))
	_access_token = access
	_refresh_token = refresh
	_expires_at = int(parsed.get("expires_at", 0))
	_pending_email = str(parsed.get("pending_email", ""))
	var pending_id := str(parsed.get("pending_offline_guest_id", ""))
	_pending_offline_guest_id = pending_id if pending_id.begins_with("local-") else ""
	return true

func start_offline_guest() -> bool:
	if has_remote_session():
		return false # Never replace a server identity with a local-only identity implicitly.
	if _offline and is_guest():
		return true
	_session_epoch += 1
	var previous := _snapshot()
	_user_id = "local-" + str(ResourceUID.create_id())
	_guest = true
	_offline = true
	_email = ""
	_access_token = ""
	_refresh_token = ""
	_expires_at = 0
	_pending_email = ""
	_pending_offline_guest_id = ""
	if not _save():
		_restore_snapshot(previous)
		return false
	return true

func sign_out() -> bool:
	_session_epoch += 1
	# Local logout only. Keep memory consistent if Windows cannot remove the session.
	if FileAccess.file_exists(session_path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(session_path)) != OK:
		return false
	_user_id = ""
	_email = ""
	_guest = false
	_offline = false
	_access_token = ""
	_refresh_token = ""
	_expires_at = 0
	_pending_email = ""
	_pending_offline_guest_id = ""

	return true

func sign_in_anonymous() -> Dictionary:
	if not is_configured():
		return _fail("not_configured")
	if has_remote_session():
		return {"ok": true} if _guest else _fail("not_guest")
	_session_epoch += 1
	var epoch := _session_epoch
	var local_id := _user_id if _offline and _guest else ""
	var result: Dictionary = await _transport("POST", "/signup", {"data": {}})
	if epoch != _session_epoch:
		return _fail("identity_changed")
	if not result.get("ok", false):
		return _fail(str(result.get("error", "network_unavailable")))
	if not _accept_session(result.get("data", {}), "", local_id):
		return _fail(_session_error)
	return {"ok": true}

func sign_in_password(email: String, password: String) -> Dictionary:
	if not is_configured():
		return _fail("not_configured")
	if not _valid_email(email):
		return _fail("invalid_email")
	if password.length() < 8:
		return _fail("weak_password")
	_session_epoch += 1
	var epoch := _session_epoch
	var result: Dictionary = await _transport("POST", "/token?grant_type=password", {"email": email.strip_edges(), "password": password})
	if epoch != _session_epoch:
		return _fail("identity_changed")
	if not result.get("ok", false):
		return _fail(str(result.get("error", "network_unavailable")))
	# Never attach local guest events to a different email account.
	if not _accept_session(result.get("data", {}), "", ""):
		return _fail(_session_error)
	return {"ok": true}

func request_guest_email(email: String) -> Dictionary:
	var epoch := _session_epoch
	var owner := _user_id
	if not is_configured():
		return _fail("not_configured")
	if not _valid_email(email):
		return _fail("invalid_email")
	if not has_remote_session():
		return _fail("remote_guest_required")
	if not _guest:
		return _fail("not_guest")
	var ready: Dictionary = await _ensure_access()
	if epoch != _session_epoch or owner != _user_id:
		return _fail("identity_changed")
	if not ready.get("ok", false):
		return ready
	var result: Dictionary = await _transport("PUT", "/user", {"email": email.strip_edges()}, _access_token)
	if epoch != _session_epoch or owner != _user_id:
		return _fail("identity_changed")
	if not result.get("ok", false):
		return _fail(str(result.get("error", "network_unavailable")))
	var user: Variant = result.get("data", {})
	if not user is Dictionary or str(user.get("id", "")) != _user_id:
		return _fail("identity_mismatch")
	var previous := _snapshot()
	_pending_email = email.strip_edges()
	if not _save():
		_restore_snapshot(previous)
		return _fail("storage_unavailable")
	return {"ok": true}

func confirm_guest_email_and_password(password: String) -> Dictionary:
	var epoch := _session_epoch
	var owner := _user_id
	if not is_configured():
		return _fail("not_configured")
	if password.length() < 8:
		return _fail("weak_password")
	if not has_remote_session() or not _guest or _pending_email.is_empty():
		return _fail("email_not_requested")
	var ready: Dictionary = await _ensure_access()
	if epoch != _session_epoch or owner != _user_id:
		return _fail("identity_changed")
	if not ready.get("ok", false):
		return ready
	var check: Dictionary = await _transport("GET", "/user", {}, _access_token)
	if epoch != _session_epoch or owner != _user_id:
		return _fail("identity_changed")
	if not check.get("ok", false):
		return _fail(str(check.get("error", "network_unavailable")))
	var user: Variant = check.get("data", {})
	if not user is Dictionary or str(user.get("id", "")) != _user_id:
		return _fail("identity_mismatch")
	# No password write until the provider confirms the requested email on THIS user.
	if str(user.get("email", "")).to_lower() != _pending_email.to_lower() or str(user.get("email_confirmed_at", "")).is_empty():
		return _fail("email_not_confirmed")
	var update: Dictionary = await _transport("PUT", "/user", {"password": password}, _access_token)
	if epoch != _session_epoch or owner != _user_id:
		return _fail("identity_changed")
	if not update.get("ok", false):
		return _fail(str(update.get("error", "network_unavailable")))
	var updated: Variant = update.get("data", {})
	if not updated is Dictionary or str(updated.get("id", "")) != _user_id:
		return _fail("identity_mismatch")
	var previous := _snapshot()
	_email = _pending_email
	_pending_email = ""
	_guest = false
	if not _save():
		_restore_snapshot(previous)
		return _fail("storage_unavailable")
	return {"ok": true}

func request_password_reset(email: String) -> Dictionary:
	if not is_configured():
		return _fail("not_configured")
	if not _valid_email(email):
		return _fail("invalid_email")
	var result: Dictionary = await _transport("POST", "/recover", {"email": email.strip_edges()})
	if not result.get("ok", false):
		return _fail(str(result.get("error", "network_unavailable")))
	return {"ok": true}

func access_token_for_request() -> Dictionary:
	var epoch := _session_epoch
	var owner := _user_id
	var ready: Dictionary = await _ensure_access()
	if epoch != _session_epoch or owner != _user_id:
		return _fail("identity_changed")
	if not ready.get("ok", false):
		return ready
	return {"ok": true, "token": _access_token}

func _ensure_access() -> Dictionary:
	if not has_remote_session():
		return _fail("remote_guest_required")
	if _expires_at > int(Time.get_unix_time_from_system()) + EXPIRY_MARGIN_SECONDS:
		return {"ok": true}
	if not is_configured():
		return _fail("not_configured")
	var epoch := _session_epoch
	var owner := _user_id
	var result: Dictionary = await _transport("POST", "/token?grant_type=refresh_token", {"refresh_token": _refresh_token})
	if epoch != _session_epoch or owner != _user_id:
		return _fail("identity_changed")
	if not result.get("ok", false):
		return _fail(str(result.get("error", "network_unavailable")))
	if not _accept_session(result.get("data", {}), owner):
		return _fail(_session_error)
	return {"ok": true}

func _accept_session(value: Variant, expected_id: String, adoption_marker: Variant = null) -> bool:
	_session_error = "invalid_response" if expected_id.is_empty() else "identity_mismatch"
	if not value is Dictionary:
		return false
	var user: Variant = value.get("user", {})
	if not user is Dictionary:
		return false
	var id := str(user.get("id", ""))
	var access := str(value.get("access_token", ""))
	var refresh := str(value.get("refresh_token", ""))
	var duration := int(value.get("expires_in", 0))
	if id.is_empty() or access.is_empty() or refresh.is_empty() or duration <= 0:
		return false
	if not expected_id.is_empty() and id != expected_id:
		return false
	var previous := _snapshot()
	if adoption_marker != null:
		_pending_offline_guest_id = str(adoption_marker)
	_user_id = id
	_access_token = access
	_refresh_token = refresh
	_expires_at = int(Time.get_unix_time_from_system()) + duration
	_email = str(user.get("email", ""))
	_guest = user.get("is_anonymous", false) == true
	_offline = false
	_pending_email = "" if expected_id.is_empty() else _pending_email
	if not _save():
		_restore_snapshot(previous)
		_session_error = "storage_unavailable"
		return false
	return true

func _snapshot() -> Dictionary:
	return {"version": 1, "user_id": _user_id, "email": _email, "guest": _guest, "offline": _offline, "access_token": _access_token, "refresh_token": _refresh_token, "expires_at": _expires_at, "pending_email": _pending_email, "pending_offline_guest_id": _pending_offline_guest_id}

func _restore_snapshot(state: Dictionary) -> void:
	for key in state:
		if key != "version":
			set("_" + key, state[key])

func _save() -> bool:
	var temp_path := session_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	var stored := file.store_string(JSON.stringify(_snapshot()))
	file.flush()
	var write_ok := stored and file.get_error() == OK
	file = null # Close Windows handle before atomic replacement.
	if not write_ok:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false
	var moved := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(session_path))
	if moved != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false
	return true

func _valid_email(value: String) -> bool:
	var trimmed := value.strip_edges()
	return trimmed.contains("@") and not trimmed.begins_with("@") and not trimmed.ends_with("@") and not trimmed.contains(" ")

func _fail(code: String) -> Dictionary:
	return {"ok": false, "error": code}

func _safe_provider_error(code: String, status: int) -> String:
	match code:
		"invalid_credentials", "email_not_confirmed", "weak_password", "email_exists", "user_already_exists", "over_email_send_rate_limit":
			return code
	if status == 429:
		return "rate_limited"
	if status == 401 or status == 403:
		return "invalid_credentials"
	return "server_unavailable"

func _transport(method: String, path: String, body: Dictionary, bearer: String = "") -> Dictionary:
	if not is_configured() or not is_inside_tree():
		return _fail("not_configured")
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	var headers := PackedStringArray(["apikey: " + _public_key, "Content-Type: application/json"])
	if not bearer.is_empty():
		headers.append("Authorization: Bearer " + bearer)
	var payload := "" if method == "GET" else JSON.stringify(body)
	var err := request.request(_url + "/auth/v1" + path, headers, HTTPClient.METHOD_GET if method == "GET" else (HTTPClient.METHOD_PUT if method == "PUT" else HTTPClient.METHOD_POST), payload)
	if err != OK:
		request.queue_free()
		return _fail("network_unavailable")
	var reply: Array = await request.request_completed
	request.queue_free()
	if reply[0] != HTTPRequest.RESULT_SUCCESS:
		return _fail("network_unavailable")
	var parsed: Variant = JSON.parse_string((reply[3] as PackedByteArray).get_string_from_utf8())
	if reply[1] < 200 or reply[1] >= 300:
		var code := str(parsed.get("code", "")) if parsed is Dictionary else ""
		return _fail(_safe_provider_error(code, reply[1]))
	if not parsed is Dictionary:
		return _fail("invalid_response")
	return {"ok": true, "data": parsed}

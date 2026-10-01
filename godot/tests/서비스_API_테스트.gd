extends SceneTree

const API_PATH := "res://scripts/services/서비스_API.gd"

class FakeAuth extends ServiceAuth:
	func access_token_for_request() -> Dictionary:
		return {"ok": true, "token": "test-access"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not FileAccess.file_exists(API_PATH):
		printerr("FAIL: 공통 서비스 API 클라이언트가 아직 없음")
		quit(1)
		return
	var api_script := load(API_PATH) as GDScript
	var api: Variant = api_script.new()
	var auth := FakeAuth.new()
	auth._user_id = "test-user"
	auth._access_token = "test-access"
	auth._refresh_token = "test-refresh"
	auth._expires_at = int(Time.get_unix_time_from_system()) + 3600
	root.add_child(auth)
	root.add_child(api)
	if not api.has_method("configure") or not api.has_method("post_function"):
		printerr("FAIL: 인증된 Edge Function 호출 계약 없음")
		auth.queue_free()
		api.queue_free()
		quit(1)
		return
	api.configure(auth, "https://project.supabase.co", "sb_publishable_dummy")
	var calls: Array[Dictionary] = []
	api.transport_override = func(method: int, path: String, payload: String, token: String) -> Dictionary:
		calls.append({"method": method, "path": path, "payload": payload, "token": token})
		if path.begins_with("/rest/v1/profiles?") and method == HTTPClient.METHOD_GET:
			return {"ok": true, "status": 200, "data": [{"nickname": "생존자", "is_guest": true, "role": "user"}]}
		if path.begins_with("/rest/v1/profiles?") and method == HTTPClient.METHOD_PATCH:
			return {"ok": true, "status": 204, "data": {}}
		return {"ok": true, "status": 200, "data": {"profile": {"user_id": "test-user", "is_guest": true}}}
	var response: Dictionary = await api.post_function("ensure-profile", {})
	var ok: bool = response.get("ok", false) and calls.size() == 1 and calls[0].path == "/functions/v1/ensure-profile" and calls[0].method == HTTPClient.METHOD_POST and calls[0].token == "test-access" and calls[0].payload == "{}"
	if not ok:
		printerr("FAIL: 사용자 JWT로 ensure-profile을 정확히 호출하지 않음")
	if not api.has_method("fetch_profile"):
		printerr("FAIL: 본인 프로필 조회 기능이 없음")
		ok = false
	else:
		var profile: Dictionary = await api.fetch_profile()
		ok = ok and profile.get("ok", false) and profile.get("profile", {}).get("nickname", "") == "생존자" and calls.size() == 2 and calls[-1].method == HTTPClient.METHOD_GET and calls[-1].path == "/rest/v1/profiles?id=eq.test-user&select=nickname,is_guest,role"
		if not ok:
			printerr("FAIL: 사용자 본인 프로필을 조회하지 않음")
	if not api.has_method("update_nickname"):
		printerr("FAIL: 닉네임만 수정하는 기능이 없음")
		ok = false
	else:
		var changed: Dictionary = await api.update_nickname(" 생존자2 ")
		ok = ok and changed.get("ok", false) and calls[-1].method == HTTPClient.METHOD_PATCH and calls[-1].path == "/rest/v1/profiles?id=eq.test-user" and calls[-1].payload == '{"nickname":"생존자2"}'
		var before_invalid := calls.size()
		var invalid: Dictionary = await api.update_nickname(" ")
		ok = ok and not invalid.get("ok", true) and calls.size() == before_invalid
		if not ok:
			printerr("FAIL: 본인 닉네임 한 열만 수정하거나 빈 입력을 차단하지 않음")
	if ok:
		print("SERVICE_API_TEST: PASS (token value omitted)")
	api.queue_free()
	auth.queue_free()
	await process_frame
	quit(0 if ok else 1)

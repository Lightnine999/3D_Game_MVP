extends SceneTree

const Auth := preload("res://scripts/services/서비스_인증.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var auth := Auth.new()
	auth.session_path = "user://service_token_test_%d.json" % Time.get_ticks_usec()
	auth._user_id = "test-user"
	auth._access_token = "test-access"
	auth._refresh_token = "test-refresh"
	auth._expires_at = int(Time.get_unix_time_from_system()) + 3600
	if not auth.has_method("access_token_for_request"):
		printerr("FAIL: 앱 서비스 호출용 세션 토큰 접근 메서드가 없음")
		auth.free()
		quit(1)
		return
	var result: Dictionary = await auth.call("access_token_for_request")
	if not result.get("ok", false) or result.get("token", "") != "test-access":
		printerr("FAIL: 유효한 액세스 토큰을 안전하게 반환하지 않음")
		auth.free()
		quit(1)
		return
	print("SERVICE_AUTH_TOKEN_TEST: PASS (token value omitted)")
	auth.free()
	quit(0)

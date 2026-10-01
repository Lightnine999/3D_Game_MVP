extends SceneTree

# One temporary anonymous user, two model questions maximum, one bug report (no model).
const REF := "ecqfmaivywgzlbnqxymb"
const CONFIG_PATH := "res://config/서비스_공개설정.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_environment("SERVICE_SUPPORT_CLOUD_TEST_APPROVED") != REF:
		print("SERVICE_SUPPORT_CLOUD_GUARD_PASS: no remote call")
		quit(2)
		return
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not config is Dictionary or str(config.get("supabase_url", "")) != "https://" + REF + ".supabase.co":
		printerr("SERVICE_SUPPORT_CLOUD_FAIL: wrong_project")
		quit(1)
		return
	var url := str(config.get("supabase_url", ""))
	var key := str(config.get("supabase_publishable_key", ""))
	if not key.begins_with("sb_publishable_"):
		printerr("SERVICE_SUPPORT_CLOUD_FAIL: wrong_key_type")
		quit(1)
		return
	var auth := ServiceAuth.new()
	auth.session_path = "user://service_support_cloud_test_%d.json" % Time.get_ticks_usec()
	root.add_child(auth)
	auth.set_public_config(url, key)
	var signed_in: Dictionary = await auth.sign_in_anonymous()
	if not signed_in.get("ok", false):
		printerr("SERVICE_SUPPORT_CLOUD_FAIL: anonymous_auth")
		auth.sign_out(); auth.queue_free(); quit(1); return
	var api := ServiceAPI.new()
	root.add_child(api)
	api.configure(auth, url, key)
	var profile: Dictionary = await api.post_function("ensure-profile", {})
	var profile_ok: bool = profile.get("ok", false) and profile.get("data", {}).get("profile", {}).get("user_id", "") == auth.get_user_id()
	var known: Dictionary = await api.post_function("support-chat", {"kind": "question", "message": "시연 화면에서 탄약은 어디서 얻나요?"}) if profile_ok else {"ok": false}
	var known_body: Variant = known.get("data", {})
	var known_ok: bool = known.get("ok", false) and known_body is Dictionary and known_body.get("status", "") == "ai_answered" and "보급" in str(known_body.get("reply", ""))
	print("SERVICE_SUPPORT_CLOUD: known_question_%s (HTTP %s)" % ["pass" if known_ok else "fail", known.get("status", 0)])
	var unknown: Dictionary = await api.post_function("support-chat", {"kind": "question", "message": "정식 게임의 미확정 목표 거리는 정확히 몇 미터인가요?"}) if profile_ok else {"ok": false}
	var unknown_body: Variant = unknown.get("data", {})
	var unknown_ok: bool = unknown.get("ok", false) and unknown_body is Dictionary and unknown_body.get("status", "") == "needs_human"
	print("SERVICE_SUPPORT_CLOUD: unknown_question_%s (HTTP %s)" % ["pass" if unknown_ok else "fail", unknown.get("status", 0)])
	var bug: Dictionary = await api.post_function("support-chat", {"kind": "bug", "message": "테스트 전용 버그 제보입니다", "bug_context": {"app_version": "0.0.1", "platform": "Windows", "last_run": {}}}) if profile_ok else {"ok": false}
	var bug_body: Variant = bug.get("data", {})
	var bug_ok: bool = bug.get("ok", false) and bug_body is Dictionary and bug_body.get("status", "") == "needs_human"
	print("SERVICE_SUPPORT_CLOUD: bug_human_route_%s (HTTP %s)" % ["pass" if bug_ok else "fail", bug.get("status", 0)])
	var deleted: Dictionary = await api.post_function("delete-account", {"confirm": true})
	var deleted_ok: bool = deleted.get("ok", false) and deleted.get("data", {}).get("status", "") == "deleted"
	print("SERVICE_SUPPORT_CLOUD: cleanup_%s (HTTP %s)" % ["pass" if deleted_ok else "fail", deleted.get("status", 0)])
	auth.sign_out()
	var local_clean := not FileAccess.file_exists(auth.session_path)
	api.queue_free(); auth.queue_free()
	if profile_ok and known_ok and unknown_ok and bug_ok and deleted_ok and local_clean:
		print("SERVICE_SUPPORT_CLOUD_SLICE_PASS (provider-side request count not independently verified)")
		quit(0)
	else:
		printerr("SERVICE_SUPPORT_CLOUD_SLICE_PARTIAL: inspect cleanup; no automatic retry")
		quit(1)

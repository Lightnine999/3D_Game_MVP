extends SceneTree

# This script creates exactly one temporary anonymous user in Server 1.
# It refuses to run unless the exact project-specific approval flag is present.
const PROJECT_REF := "ecqfmaivywgzlbnqxymb"
const CONFIG_PATH := "res://config/서비스_공개설정.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_environment("SERVICE_AUTH_CLOUD_TEST_APPROVED") != PROJECT_REF:
		print("SERVICE_AUTH_CLOUD_GUARD_PASS: no remote call")
		quit(2)
		return
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not config is Dictionary:
		printerr("SERVICE_AUTH_CLOUD_FAIL: invalid_public_config")
		quit(1)
		return
	var url := str(config.get("supabase_url", ""))
	var public_key := str(config.get("supabase_publishable_key", ""))
	if url != "https://" + PROJECT_REF + ".supabase.co" or not public_key.begins_with("sb_publishable_"):
		printerr("SERVICE_AUTH_CLOUD_FAIL: wrong_project_or_key_type")
		quit(1)
		return

	var auth := ServiceAuth.new()
	auth.session_path = "user://service_auth_cloud_test_%d.json" % Time.get_ticks_usec()
	root.add_child(auth)
	auth.set_public_config(url, public_key)
	var signed_in: Dictionary = await auth.sign_in_anonymous()
	if not signed_in.get("ok", false):
		printerr("SERVICE_AUTH_CLOUD_FAIL: guest_auth_" + str(signed_in.get("error", "unknown")))
		auth.sign_out()
		auth.queue_free()
		quit(1)
		return
	print("SERVICE_AUTH_CLOUD: anonymous_user_created (id omitted)")
	var token_result: Dictionary = await auth.access_token_for_request()
	if not token_result.get("ok", false):
		printerr("SERVICE_AUTH_CLOUD_FAIL: access_token_unavailable")
		auth.sign_out()
		auth.queue_free()
		quit(1)
		return
	var token := str(token_result.get("token", ""))
	var profile: Dictionary = await _call(url + "/functions/v1/ensure-profile", public_key, token, HTTPClient.METHOD_POST, "{}")
	var profile_body: Variant = profile.get("data", {})
	var profile_record: Variant = profile_body.get("profile", {}) if profile_body is Dictionary else {}
	var profile_ok: bool = profile.get("http", 0) == 200 and profile_record is Dictionary and str(profile_record.get("user_id", "")) == auth.get_user_id() and profile_record.get("is_guest", false) == true
	print("SERVICE_AUTH_CLOUD: ensure_profile_%s (HTTP %s)" % ["pass" if profile_ok else "fail", profile.get("http", 0)])

	# Always attempt cleanup of this JWT owner even when the profile check failed.
	var deletion: Dictionary = await _call(url + "/functions/v1/delete-account", public_key, token, HTTPClient.METHOD_POST, '{"confirm":true}')
	var deletion_body: Variant = deletion.get("data", {})
	var deleted: bool = deletion.get("http", 0) == 200 and deletion_body is Dictionary and str(deletion_body.get("status", "")) == "deleted"
	print("SERVICE_AUTH_CLOUD: self_delete_%s (HTTP %s)" % ["pass" if deleted else "fail", deletion.get("http", 0)])
	var stale: Dictionary = await _call(url + "/auth/v1/user", public_key, token, HTTPClient.METHOD_GET, "") if deleted else {"http": 0}
	# Supabase may deny an old JWT with either 401 or 403 after Auth user deletion.
	var revoked: bool = deleted and int(stale.get("http", 0)) in [401, 403]
	if deleted:
		print("SERVICE_AUTH_CLOUD: stale_user_lookup_%s (HTTP %s)" % ["pass" if revoked else "fail", stale.get("http", 0)])
	auth.sign_out()
	var local_clean := not FileAccess.file_exists(auth.session_path)
	auth.queue_free()
	if profile_ok and deleted and revoked and local_clean:
		print("SERVICE_AUTH_CLOUD_SLICE_PASS: one test user, no paid provider calls")
		quit(0)
	else:
		printerr("SERVICE_AUTH_CLOUD_SLICE_FAIL: inspect exact temporary account cleanup; no automatic retry")
		quit(1)


func _call(url: String, public_key: String, token: String, method: int, payload: String) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 15.0
	root.add_child(request)
	var headers := PackedStringArray(["apikey: " + public_key, "Authorization: Bearer " + token, "Content-Type: application/json"])
	var start := request.request(url, headers, method, payload)
	if start != OK:
		request.queue_free()
		return {"http": 0, "data": {}}
	var reply: Array = await request.request_completed
	request.queue_free()
	if reply[0] != HTTPRequest.RESULT_SUCCESS:
		return {"http": 0, "data": {}}
	return {"http": reply[1], "data": JSON.parse_string((reply[3] as PackedByteArray).get_string_from_utf8())}

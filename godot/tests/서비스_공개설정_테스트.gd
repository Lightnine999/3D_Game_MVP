extends SceneTree

const CONFIG_PATH := "res://config/서비스_공개설정.json"
const EXPECTED_URL := "https://ecqfmaivywgzlbnqxymb.supabase.co"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary:
		printerr("FAIL: 서비스 공개 설정 형식")
		quit(1)
		return
	var url := str(parsed.get("supabase_url", ""))
	var key := str(parsed.get("supabase_publishable_key", ""))
	if url != EXPECTED_URL or not key.begins_with("sb_publishable_"):
		printerr("FAIL: Server 1 공개 URL/키가 아직 설정되지 않음")
		quit(1)
		return
	if parsed.has("service_role") or parsed.has("secret_key"):
		printerr("FAIL: 공개 설정에 서버 전용 필드 포함")
		quit(1)
		return
	print("SERVICE_PUBLIC_CONFIG_TEST: PASS (public key value omitted)")
	quit(0)

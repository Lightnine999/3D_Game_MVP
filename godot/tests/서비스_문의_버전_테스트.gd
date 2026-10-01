extends SceneTree

const SCREEN := preload("res://scenes/ui/문의_화면.tscn")
const THREAD_ID := "11111111-1111-4111-8111-111111111111"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var auth := ServiceAuth.new()
	auth._user_id = "test-user"
	auth._access_token = "test-access"
	auth._refresh_token = "test-refresh"
	auth._expires_at = int(Time.get_unix_time_from_system()) + 3600
	root.add_child(auth)
	var api := ServiceAPI.new()
	root.add_child(api)
	api.configure(auth, "https://project.supabase.co", "sb_publishable_dummy")
	var sent: Array[Dictionary] = []
	api.transport_override = func(method: int, path: String, payload: String, _token: String) -> Dictionary:
		if method == HTTPClient.METHOD_GET:
			return {"ok": true, "status": 200, "data": []}
		sent.append(JSON.parse_string(payload))
		return {"ok": true, "status": 200, "data": {"threadId": THREAD_ID, "status": "ai_answered", "reply": "첫 답변"}}
	var screen := SCREEN.instantiate() as Control
	screen.setup(auth, api) # Production default: remote v7 has no multi-turn.
	root.add_child(screen)
	await process_frame
	var field := screen.find_child("MessageField", true, false) as TextEdit
	var status := screen.find_child("SupportStatus", true, false) as Label
	field.text = "첫 질문"
	await screen.call("_send_message")
	field.text = "후속 질문"
	await screen.call("_send_message")
	var ok: bool = sent.size() == 1 and field.text == "후속 질문" and status.text.contains("서버 업데이트")
	if not ok:
		printerr("FAIL: 미배포 서버에 후속 threadId를 전송해 유료 요청을 만들면 안 됨")
	screen.queue_free(); api.queue_free(); auth.queue_free()
	await process_frame
	print("SERVICE_CHAT_VERSION_GUARD: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

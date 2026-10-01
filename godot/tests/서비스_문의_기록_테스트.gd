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
	var paths: Array[String] = []
	var sent: Array[Dictionary] = []
	api.transport_override = func(_method: int, path: String, payload: String, _token: String) -> Dictionary:
		paths.append(path)
		if path.begins_with("/rest/v1/support_threads?"):
			return {"ok": true, "status": 200, "data": [{"id": THREAD_ID, "status": "ai_answered"}]}
		if path.begins_with("/rest/v1/support_messages?"):
			return {"ok": true, "status": 200, "data": [{"role": "user", "content": "첫 질문"}, {"role": "assistant", "content": "첫 답변"}]}
		sent.append(JSON.parse_string(payload))
		return {"ok": true, "status": 200, "data": {"threadId": THREAD_ID, "status": "ai_answered", "reply": "두 번째 답변"}}
	var screen := SCREEN.instantiate() as Control
	screen.setup(auth, api, true)
	root.add_child(screen)
	await create_timer(0.1).timeout
	var messages := screen.find_child("ChatMessages", true, false) as VBoxContainer
	var field := screen.find_child("MessageField", true, false) as TextEdit
	var ok: bool = messages != null and messages.get_child_count() == 2 and paths.size() == 2
	if ok:
		ok = str(messages.get_child(0).get_child(0).text).contains("첫 질문") and str(messages.get_child(1).get_child(0).text).contains("첫 답변")
	field.text = "두 번째 질문"
	await screen.call("_send_message")
	ok = ok and sent.size() == 1 and sent[0].get("threadId") == THREAD_ID and messages.get_child_count() == 4
	if not ok:
		printerr("FAIL: 재진입 시 서버 대화 복구 또는 같은 스레드 이어쓰기 누락")
	screen.queue_free(); api.queue_free(); auth.queue_free()
	await process_frame
	print("SERVICE_CHAT_RESTORE: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

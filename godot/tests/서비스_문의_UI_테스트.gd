extends SceneTree

const SUPPORT_SCENE := "res://scenes/ui/문의_화면.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists(SUPPORT_SCENE):
		printerr("FAIL: 앱 문의·제보 장면이 없음")
		quit(1)
		return
	var auth := ServiceAuth.new()
	auth._user_id = "test-user"
	auth._access_token = "test-access"
	auth._refresh_token = "test-refresh"
	auth._expires_at = int(Time.get_unix_time_from_system()) + 3600
	root.add_child(auth)
	var api := ServiceAPI.new()
	root.add_child(api)
	api.configure(auth,"https://project.supabase.co","sb_publishable_dummy")
	var calls: Array[Dictionary] = []
	api.transport_override = func(method: int, path: String, payload: String, _token: String) -> Dictionary:
		if method == HTTPClient.METHOD_GET and path.begins_with("/rest/v1/support_threads?"):
			return {"ok": true, "status": 200, "data": []}
		calls.append({"method": method, "path": path, "payload": JSON.parse_string(payload)})
		return {"ok": true, "status": 202, "data": {"threadId": "11111111-1111-4111-8111-111111111111", "status": "needs_human", "reply": "팀에 전달했어요"}} if calls.size() == 1 else {"ok": true, "status": 200, "data": {"threadId": "11111111-1111-4111-8111-111111111111", "status": "ai_answered", "reply": "보급 상자를 주우세요"}}
	var screen := load(SUPPORT_SCENE).instantiate() as Control
	screen.setup(auth,api,true)
	root.add_child(screen)
	await process_frame
	var field := screen.find_child("MessageField",true,false) as TextEdit
	var messages := screen.find_child("ChatMessages",true,false) as VBoxContainer
	var warning := screen.find_child("PrivacyWarning",true,false) as Label
	if field == null or messages == null or warning == null or not warning.text.contains("개인정보"):
		printerr("FAIL: 여러 메시지가 쌓이는 채팅 화면·개인정보 안내 구성 부족")
		screen.queue_free(); api.queue_free(); auth.queue_free(); quit(1); return
	field.text = "게임에 대해 알려주세요"
	await screen.call("_send_message")
	field.text = "탄약은 어디서 얻나요?"
	await screen.call("_send_message")
	var rows := messages.get_children()
	var ok: bool = calls.size()==2 and calls[0].path=="/functions/v1/support-chat" and calls[0].method==HTTPClient.METHOD_POST and calls[0].payload.get("kind")=="question" and not calls[0].payload.has("threadId") and calls[1].payload.get("threadId")=="11111111-1111-4111-8111-111111111111" and rows.size()==4
	if ok:
		ok = rows[0].get_meta("role", "") == "user" and rows[1].get_meta("role", "") == "assistant" and rows[2].get_meta("role", "") == "user" and rows[3].get_meta("role", "") == "assistant"
		ok = ok and str((rows[0] as Control).get_child(0).text).contains("게임에 대해") and str((rows[1] as Control).get_child(0).text).contains("팀에 전달했어요") and str((rows[3] as Control).get_child(0).text).contains("보급 상자")
	if not ok:
		printerr("FAIL: 두 차례 질문·답변이 순서대로 채팅에 표시되지 않음")
	else:
		print("SERVICE_SUPPORT_UI_TEST: PASS (two visible exchanges)")
	screen.queue_free(); api.queue_free(); auth.queue_free()
	await process_frame
	quit(0 if ok else 1)

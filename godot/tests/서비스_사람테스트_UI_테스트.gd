extends SceneTree

const SUPPORT := preload("res://scenes/ui/문의_화면.tscn")
const ACCOUNT := preload("res://scenes/ui/계정_화면.tscn")
const SHOP := preload("res://scenes/ui/상점_화면.tscn")
const AUTH := preload("res://scenes/ui/인증_화면.tscn")
var failures := 0

# Dependency injection only: no HTTP, saved users or payment gateway.
class FakeAuth extends ServiceAuth:
	var remote := true
	var guest := true
	var logout_calls := 0
	func has_remote_session() -> bool: return remote
	func get_user_id() -> String: return "manual-ui-test"
	func is_guest() -> bool: return guest
	func is_logged_in() -> bool: return true
	func is_configured() -> bool: return false
	func display_name() -> String: return "게스트" if guest else "user@example.test"
	func sign_out() -> bool:
		logout_calls += 1
		return true
	func _transport(_method: String, _path: String, _body: Dictionary, _bearer: String = "") -> Dictionary:
		return {"ok": false, "error": "test_network_forbidden"}

class FakeAPI extends ServiceAPI:
	var sent: Array[Dictionary] = []
	var latest := {"ok": true, "thread_id": "previous-thread", "status": "ai_answered"}
	var history := {"ok": true, "messages": [{"role": "user", "content": "이전 질문"}, {"role": "assistant", "content": "이전 답변"}]}
	var response := {"ok": true, "data": {"threadId": "new-thread", "status": "ai_answered", "reply": "새 답변"}}
	var inventory_response := {"ok": false, "error": "inventory_unavailable"}
	var nickname_calls := 0
	var profile_response := {"ok": true, "profile": {"nickname": "생존자"}}
	var delay_support := false
	func fetch_latest_support_thread() -> Dictionary: return latest.duplicate(true)
	func fetch_support_messages(_id: String) -> Dictionary: return history.duplicate(true)
	func post_function(name: String, payload: Dictionary) -> Dictionary:
		sent.append({"name": name, "body": payload.duplicate(true)})
		if delay_support and name == "support-chat": await get_tree().process_frame
		return response.duplicate(true)
	func fetch_inventory_item(_id: String) -> Dictionary: return inventory_response.duplicate(true)
	func fetch_profile() -> Dictionary: return profile_response.duplicate(true)
	func update_nickname(_name: String) -> Dictionary:
		nickname_calls += 1
		return {"ok": false, "error": "invalid_nickname"}
	func _send(_method: int, _path: String, _payload: String, _token: String) -> Dictionary:
		return {"ok": false, "error": "test_network_forbidden"}

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if value:
		print("PASS: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)

func _dispose(nodes: Array) -> void:
	for node in nodes: node.queue_free()
	await process_frame

func _run() -> void:
	await _test_guest_save_failure()
	await _test_locked_logout()
	await _test_new_chat()
	await _test_unsent_query()
	await _test_bug_snapshot()
	await _test_shop_truth()
	await _test_account_guidance()
	await _test_delete_notification()
	await _test_auth_errors()
	await _test_keyboard_usability()
	await _test_closed_history()
	await _test_pending_actions()
	print("SERVICE_MANUAL_UI: ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)

func _test_guest_save_failure() -> void:
	var auth := ServiceAuth.new()
	auth.session_path = "user://blocked_guest.json"
	root.add_child(auth)
	var login := AUTH.instantiate() as Control
	login.setup(auth)
	root.add_child(login)
	var events: Array[String] = []
	login.authenticated.connect(func(): events.append(auth.get_user_id()))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(auth.session_path + ".tmp"))
	login.call("_on_guest")
	_check(events.is_empty() and not auth.is_logged_in() and not FileAccess.file_exists(auth.session_path), "failed durable guest write blocks empty-owner navigation")
	_check(login.get("_status").text.contains("저장"), "guest save failure has actionable storage message")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(auth.session_path + ".tmp"))
	login.call("_on_guest")
	_check(events.size() == 1 and auth.is_guest() and FileAccess.file_exists(auth.session_path), "guest retry enters only after durable save")
	auth.sign_out()
	await _dispose([login, auth])

func _test_locked_logout() -> void:
	var auth := ServiceAuth.new()
	auth.session_path = "user://locked_logout.json"
	_check(auth._accept_session({"access_token": "test", "refresh_token": "test", "expires_in": 3600, "user": {"id": "locked-owner"}}, ""), "seed durable member")
	var api := FakeAPI.new()
	root.add_child(auth); root.add_child(api)
	var account := ACCOUNT.instantiate() as Control
	account.setup(auth, api)
	root.add_child(account)
	var login := AUTH.instantiate() as Control
	login.setup(auth, true)
	root.add_child(login)
	var events: Array[String] = []
	account.signed_out.connect(func(): events.append("out"))
	account.account_deleted.connect(func(owner: String): events.append("deleted:" + owner))
	login.authenticated.connect(func(): events.append("entered"))
	var locked := FileAccess.open(auth.session_path, FileAccess.READ)
	account.call("_logout")
	_check(events.is_empty() and account.get("_status").text.contains("실패"), "locked logout does not navigate and reports failure")
	login.call("_on_logout")
	_check(login.get("_account_mode") and not login.get("_status").text.contains("로그아웃했습니다"), "auth logout failure preserves account mode")
	login.call("_on_guest")
	_check(events.is_empty() and auth.get_user_id() == "locked-owner", "guest cannot enter as retained member after failed logout")
	api.response = {"ok": true, "data": {"status": "deleted"}}
	await account.call("_delete_account")
	_check(events == ["deleted:locked-owner"] and account.get("_status").text.contains("서버 계정은 삭제") and account.get("_status").text.contains("실패"), "server deletion plus locked session reports local cleanup failure without navigation")
	_check(auth.get_user_id() == "locked-owner" and auth.has_remote_session(), "locked logout preserves identity and tokens")
	api.response = {"ok": false, "error": "invalid_credentials"}
	var sent_before := api.sent.size()
	await account.call("_delete_account")
	_check(api.sent.size() == sent_before and account.get("_status").text.contains("서버 계정은 삭제"), "delete retry only retries local cleanup after confirmed server deletion")
	locked.close()
	auth.sign_out()
	await _dispose([login, account, api, auth])

func _test_new_chat() -> void:
	var auth := FakeAuth.new()
	var api := FakeAPI.new()
	root.add_child(auth); root.add_child(api)
	var screen := SUPPORT.instantiate() as Control
	screen.setup(auth, api)
	root.add_child(screen)
	await process_frame
	var messages := screen.find_child("ChatMessages", true, false) as VBoxContainer
	var field := screen.find_child("MessageField", true, false) as TextEdit
	_check(messages.get_child_count() == 2 and api.sent.is_empty(), "복구는 기록만 읽고 자동 전송하지 않음")
	field.text = "후속 질문"
	await screen.call("_send_message")
	_check(api.sent.is_empty() and messages.get_child_count() == 2 and field.text == "후속 질문", "단발 서버에서 후속 질문 차단·기존 기록 보존")
	var notice := screen.find_child("ConversationNotice", true, false) as Label
	_check(notice != null and notice.text.contains("단발") and notice.text.contains("새 대화"), "단발 문의와 새 대화 사용 안내")
	var reset := screen.find_child("NewChatButton", true, false) as Button
	_check(reset != null and reset.text == "새 대화", "사용자가 누르는 새 대화 버튼")
	if reset != null:
		reset.emit_signal("pressed")
		_check(messages.get_child_count() == 0 and screen.get("_thread_id") == "" and api.sent.is_empty(), "명시적 새 대화만 현재 스레드와 화면 기록 초기화")
		field.text = "새 질문"
		await screen.call("_send_message")
		_check(api.sent.size() == 1 and not api.sent[0].body.has("threadId") and messages.get_child_count() == 2, "새 질문은 새 스레드로 한 번 전송")
	await _dispose([screen, api, auth])

func _test_unsent_query() -> void:
	var auth := FakeAuth.new()
	auth.remote = false
	var api := FakeAPI.new()
	root.add_child(auth); root.add_child(api)
	var screen := SUPPORT.instantiate() as Control
	screen.setup(auth, api)
	root.add_child(screen)
	await process_frame
	var field := screen.find_child("MessageField", true, false) as TextEdit
	var messages := screen.find_child("ChatMessages", true, false) as VBoxContainer
	var status := screen.find_child("SupportStatus", true, false) as Label
	field.text = "오프라인 질문"
	await screen.call("_send_message")
	_check(api.sent.is_empty() and messages.get_child_count() == 0 and field.text == "오프라인 질문" and status.text.contains("전송하지 않았"), "오프라인 문의는 호출·가짜 답변 없이 초안 보존")
	auth.remote = true
	api.response = {"ok": false, "error": "network_unavailable"}
	await screen.call("_send_message")
	_check(api.sent.size() == 1 and messages.get_child_count() == 0 and field.text == "오프라인 질문" and status.text.contains("전송"), "실패한 전송을 AI 답변이나 전달된 질문으로 표시하지 않음")
	await _dispose([screen, api, auth])

func _test_bug_snapshot() -> void:
	var auth := FakeAuth.new()
	var api := FakeAPI.new()
	root.add_child(auth); root.add_child(api)
	var screen := SUPPORT.instantiate() as Control
	var accepts_snapshot := false
	for method in screen.get_method_list():
		if method.name == "setup": accepts_snapshot = method.args.size() == 4
	_check(accepts_snapshot, "문의 setup은 최근 플레이 스냅샷을 선택 인자로 받음")
	if accepts_snapshot:
		var snapshot := {"distance_m": 73.5, "kills": 2, "stage_id": "actual-stage", "nested": {"knife_used": true}}
		screen.call("setup", auth, api, false, snapshot)
		snapshot.nested.knife_used = false
		root.add_child(screen)
		await process_frame
		var first: Dictionary = screen.call("_bug_context")
		_check(first.last_run.nested.knife_used and first.last_run.distance_m == 73.5, "setup 시점 최근 플레이 원본을 깊은 복사로 보존")
		first.last_run.kills = 999
		var second: Dictionary = screen.call("_bug_context")
		_check(second.last_run.kills == 2 and api.sent.is_empty(), "제보 스냅샷 조회는 내부 값 변경·자동 첨부 전송 없음")
		screen.call("_select_kind", "bug")
		(screen.find_child("MessageField", true, false) as TextEdit).text = "게임이 멈췄습니다"
		await screen.call("_send_message")
		_check(api.sent.size() == 1 and api.sent[0].body.bug_context.last_run == second.last_run, "사용자가 버그 보내기를 누를 때만 실제 스냅샷 첨부")
		await _dispose([screen, api, auth])
	else:
		screen.free()
		await _dispose([api, auth])

func _test_shop_truth() -> void:
	var auth := FakeAuth.new()
	var api := FakeAPI.new()
	var payment := ServicePayment.new()
	payment.configure(auth, api, "")
	root.add_child(auth); root.add_child(api); root.add_child(payment)
	var screen := SHOP.instantiate() as Control
	screen.setup(auth, api, payment)
	root.add_child(screen)
	await process_frame
	var honest_button := false
	for button in screen.find_children("*", "Button", true, false):
		if button.text == "보유 수량 확인": honest_button = true
	_check(honest_button, "인벤토리 조회 버튼은 구매 내역이 아닌 보유 수량 확인")
	var status := screen.find_child("ShopStatus", true, false) as Label
	var checkout := screen.find_child("BuySelected", true, false) as Button
	_check(checkout.disabled and status.text.contains("PC") and status.text.contains("Android") and status.text.contains("테스트 키가 설정되지"), "PC 결제 불가·Android 전용·누락된 테스트 키 이유 표시")
	var inventory := screen.find_child("InventoryStatus", true, false) as Label
	_check(inventory.text.contains("조회 실패") and not inventory.text.contains("0개"), "미보유 또는 조회 실패를 임의 0개로 만들지 않음")
	api.inventory_response = {"ok": true, "item": {"item_id": "ammo_start_pack", "quantity": 0}}
	await screen.call("_refresh_inventory")
	_check(inventory.text.contains("0개"), "API가 확인한 0 수량만 0개 표시")
	api.inventory_response = {"ok": true, "item": {}}
	await screen.call("_refresh_inventory")
	_check(inventory.text.contains("조회 실패") and not inventory.text.contains("0개"), "누락된 수량은 조회 실패이며 크래시 없음")
	await _dispose([screen, payment, api, auth])

func _test_account_guidance() -> void:
	var auth := FakeAuth.new()
	var api := FakeAPI.new()
	api.profile_response = {"ok": true, "profile": {"nickname": ""}}
	root.add_child(auth); root.add_child(api)
	var screen := ACCOUNT.instantiate() as Control
	screen.setup(auth, api)
	root.add_child(screen)
	await process_frame
	var status := screen.find_child("AccountStatus", true, false) as Label
	_check(status.text.contains("닉네임") and status.text.contains("설정"), "미설정 닉네임은 빈 성공 화면 대신 설정 안내")
	api.profile_response.profile.nickname = null
	await screen.call("_load_profile")
	_check((screen.find_child("NicknameField", true, false) as LineEdit).text.is_empty() and status.text.contains("설정"), "서버의 null 닉네임을 가짜 이름 문자열로 표시하지 않음")
	var caution := screen.find_child("GuestRecoveryWarning", true, false) as Label
	_check(caution != null and caution.text.contains("복구할 수 없") and caution.text.contains("이메일"), "게스트 삭제·기기 변경 전 이메일 연결과 복구 불가 안내")
	var nickname := screen.find_child("NicknameField", true, false) as LineEdit
	nickname.text = " "
	await screen.call("_save_nickname")
	_check(api.nickname_calls == 0 and status.text.contains("2~24자"), "빈 닉네임은 서버 요청 전 길이 안내")
	auth.remote = false
	nickname.text = "생존자"
	await screen.call("_save_nickname")
	_check(api.nickname_calls == 0 and status.text.contains("온라인"), "오프라인 닉네임 변경은 호출 전 안내")
	var dialog: ConfirmationDialog = screen.get("_delete_dialog")
	_check(dialog.dialog_text.contains("복구할 수 없") and dialog.dialog_text.contains("게스트"), "탈퇴 확인에서 게스트 데이터 복구 불가 경고")
	await _dispose([screen, api, auth])

func _test_delete_notification() -> void:
	var auth := FakeAuth.new()
	var api := FakeAPI.new()
	root.add_child(auth); root.add_child(api)
	var screen := ACCOUNT.instantiate() as Control
	screen.setup(auth, api)
	root.add_child(screen)
	await process_frame
	_check(screen.has_signal("account_deleted"), "탈퇴 완료 시 상위 화면이 로컬 데이터 정리할 신호")
	if screen.has_signal("account_deleted"):
		var events: Array[String] = []
		screen.connect("account_deleted", func(owner: String) -> void: events.append("deleted:%s:logout%d" % [owner, auth.logout_calls]))
		screen.connect("signed_out", func() -> void: events.append("signed_out"))
		api.sent.clear()
		api.response = {"ok": false, "error": "network_unavailable"}
		await screen.call("_delete_account")
		_check(events.is_empty() and auth.logout_calls == 0, "탈퇴 미확인 시 정리 신호·로그아웃 없음")
		api.response = {"ok": true, "data": {"status": "deleted"}}
		await screen.call("_delete_account")
		_check(events == ["deleted:manual-ui-test:logout0", "signed_out"] and api.sent[-1].body == {"confirm": true}, "서버 탈퇴 확인 후 원래 소유자 ID로 알리고 로그아웃")
	await _dispose([screen, api, auth])

func _test_auth_errors() -> void:
	var auth := FakeAuth.new()
	root.add_child(auth)
	var screen := AUTH.instantiate() as Control
	screen.setup(auth)
	root.add_child(screen)
	await process_frame
	var errors := {"invalid_email": "이메일", "email_exists": "이미", "user_already_exists": "이미", "rate_limited": "잠시", "over_email_send_rate_limit": "잠시", "identity_mismatch": "계정", "email_not_requested": "인증 메일", "remote_guest_required": "온라인", "server_unavailable": "서버", "invalid_response": "응답"}
	for code in errors:
		var text := str(screen.call("_error_text", {"error": code}))
		_check(text != code and text.contains(errors[code]), "인증 오류 한국어 안내: " + code)
	await _dispose([screen, auth])

func _test_keyboard_usability() -> void:
	var auth := FakeAuth.new()
	var api := FakeAPI.new()
	root.add_child(auth); root.add_child(api)
	var login := AUTH.instantiate() as Control
	login.setup(auth)
	root.add_child(login)
	await process_frame
	var email := login.find_child("EmailField", true, false) as LineEdit
	var password := login.find_child("PasswordField", true, false) as LineEdit
	email.emit_signal("text_submitted", "user@example.test")
	_check(password.has_focus(), "로그인 이메일 Enter로 비밀번호에 포커스")
	password.emit_signal("text_submitted", "")
	_check((login.find_child("StatusMessage", true, false) as Label).text.contains("로그인할 수 없"), "비밀번호 Enter로 실제 로그인 검증 실행")
	login.call("_set_busy", true)
	login.call("_on_signup_tab")
	_check(login.get("_mode") == "login" and (login.find_child("SignupTab", true, false) as Button).disabled, "인증 요청 중 탭 전환으로 중복 요청하지 않음")
	login.call("_set_busy", false)
	var account := ACCOUNT.instantiate() as Control
	account.setup(auth, api)
	root.add_child(account)
	await process_frame
	var nickname := account.find_child("NicknameField", true, false) as LineEdit
	nickname.text = " "
	nickname.emit_signal("text_submitted", " ")
	_check((account.find_child("AccountStatus", true, false) as Label).text.contains("2~24자"), "닉네임 Enter로 로컬 입력 검증")
	var shop := SHOP.instantiate() as Control
	shop.setup(auth, api, null)
	root.add_child(shop)
	var support := SUPPORT.instantiate() as Control
	support.setup(auth, api)
	root.add_child(support)
	await process_frame
	for screen in [login, account, shop, support]:
		var follows := true
		for scroll in screen.find_children("*", "ScrollContainer", true, false):
			follows = follows and scroll.follow_focus
		_check(follows, "스크롤은 키보드 포커스를 따라 입력·버튼 잘림 방지: " + screen.get_script().resource_path.get_file())
	await _dispose([login, account, shop, support, api, auth])

func _test_closed_history() -> void:
	var auth := FakeAuth.new()
	var api := FakeAPI.new()
	api.latest.status = "closed"
	api.history.messages.append({"role": "team", "content": "담당자가 확인했습니다"})
	root.add_child(auth); root.add_child(api)
	var screen := SUPPORT.instantiate() as Control
	screen.setup(auth, api, true)
	root.add_child(screen)
	await process_frame
	var rows := screen.find_child("ChatMessages", true, false) as VBoxContainer
	_check(rows.get_child(2).get_meta("role") == "team" and str(rows.get_child(2).get_child(0).text).contains("팀 CS"), "복구된 담당자 답변은 AI 답변으로 위장하지 않음")
	(screen.find_child("MessageField", true, false) as TextEdit).text = "새 질문"
	await screen.call("_send_message")
	_check(api.sent.is_empty() and rows.get_child_count() == 3 and (screen.find_child("SupportStatus", true, false) as Label).text.contains("새 대화"), "종료된 문의는 기록 유지하며 명시적 새 대화 전 전송 차단")
	await _dispose([screen, api, auth])

func _test_pending_actions() -> void:
	var auth := FakeAuth.new()
	var api := FakeAPI.new()
	api.latest.thread_id = ""
	root.add_child(auth); root.add_child(api)
	var screen := SUPPORT.instantiate() as Control
	screen.setup(auth, api)
	root.add_child(screen)
	await process_frame
	api.delay_support = true
	var field := screen.find_child("MessageField", true, false) as TextEdit
	field.text = "첫 질문"
	screen.call("_send_message")
	screen.call("_select_kind", "bug")
	_check(screen.get("_kind") == "question" and (screen.find_child("NewChatButton", true, false) as Button).disabled and not field.editable, "전송 중 문의 종류·새 대화·초안 변경을 잠금")
	await process_frame
	_check(screen.get("_thread_id") == "new-thread" and field.editable, "대기 응답도 원래 질문 스레드에만 반영하고 잠금 해제")
	await _dispose([screen, api, auth])
	var login := AUTH.instantiate() as Control
	var login_auth := FakeAuth.new()
	root.add_child(login_auth)
	login.setup(login_auth)
	root.add_child(login)
	await process_frame
	login.call("_set_busy", true)
	login.call("_on_forgot")
	login.call("_on_back")
	login.call("_on_logout")
	_check(login.get("_mode") == "login" and login.get("_busy") and login_auth.logout_calls == 0, "인증 요청 중 복구·뒤로·로그아웃으로 계정 흐름을 바꾸지 않음")
	await _dispose([login, login_auth])

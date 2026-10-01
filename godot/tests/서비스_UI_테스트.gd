extends SceneTree

const AUTH_SCENE := preload("res://scenes/ui/인증_화면.tscn")
const TITLE_SCENE := preload("res://scenes/ui/서비스_타이틀.tscn")
const ENTRY_SCENE := preload("res://scenes/ui/서비스_진입.tscn")

var _failures := 0

class FakeSignupAuth extends "res://scripts/services/서비스_인증.gd":
	var guest_calls := 0
	var email_calls := 0

	func is_configured() -> bool:
		return true

	func has_remote_session() -> bool:
		return guest_calls > 0

	func sign_in_anonymous() -> Dictionary:
		guest_calls += 1
		return {"ok": true}

	func request_guest_email(_email: String) -> Dictionary:
		email_calls += 1
		return {"ok": true}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var logo := load("res://assets/ui/좀비탈출_로고.png") as Texture2D
	var background := load("res://assets/ui/로그인_배경.png") as Texture2D
	_check(logo != null and logo.get_width() > 0, "제공된 로고 이미지 로드")
	_check(background != null and background.get_width() > 0, "제공된 로그인 배경 로드")

	var auth_client := ServiceAuth.new()
	root.add_child(auth_client)
	var auth := AUTH_SCENE.instantiate() as Control
	auth.setup(auth_client)
	root.add_child(auth)
	await process_frame
	var bg := auth.find_child("AuthBackground", true, false) as TextureRect
	var email := auth.find_child("EmailField", true, false) as LineEdit
	var password := auth.find_child("PasswordField", true, false) as LineEdit
	var guest := auth.find_child("GuestAction", true, false) as Button
	_check(bg != null and bg.texture != null, "인증 화면 배경 이미지 적용")
	_check(email != null and email.visible, "새 사용자 이메일 입력")
	_check(password != null and password.visible and password.secret, "로그인 비밀번호 숨김")
	_check(guest != null and guest.visible, "게스트 진입 경로")
	auth.call("_set_mode", "signup")
	_check(not password.visible, "회원가입 첫 단계는 이메일 확인")
	auth.call("_set_mode", "signup_wait")
	_check(password.visible, "이메일 확인 뒤 비밀번호 설정")
	auth.queue_free()
	await process_frame

	var title := TITLE_SCENE.instantiate() as Control
	title.setup(auth_client)
	root.add_child(title)
	await process_frame
	var english_found := false
	for label in title.find_children("*", "Label", true, false):
		if (label as Label).text == "ZOMBIE ESCAPE":
			english_found = true
	_check(english_found, "로고 아래 영문명 표시")
	_check(title.has_method("show_service_notice"), "계정 프로필 오류를 타이틀에서 안내")
	var support_corner := title.find_child("SupportCornerButton", true, false) as Button
	_check(support_corner != null and support_corner.anchor_left == 1.0 and support_corner.anchor_top == 1.0 and support_corner.offset_right < 0 and support_corner.offset_bottom < 0, "메인 화면 우측 하단 문의 버튼")
	title.queue_free()
	await process_frame

	var fake := FakeSignupAuth.new()
	root.add_child(fake)
	var signup := AUTH_SCENE.instantiate() as Control
	signup.setup(fake)
	root.add_child(signup)
	await process_frame
	signup.call("_set_mode", "signup")
	var signup_email := signup.find_child("EmailField", true, false) as LineEdit
	signup_email.text = "user@example.test"
	await signup.call("_submit_signup")
	_check(fake.guest_calls == 1 and fake.email_calls == 1, "새 사용자 가입 전 게스트 ID 준비")
	_check(signup.find_child("PasswordField", true, false).visible, "가입 메일 요청 후 비밀번호 단계 전환")
	signup.queue_free()
	fake.queue_free()
	await process_frame

	await _test_entry_transitions()
	print("SERVICE_UI_TESTS: %s" % ("PASS" if _failures == 0 else "FAIL %d" % _failures))
	quit(0 if _failures == 0 else 1)


func _test_entry_transitions() -> void:
	var first := ENTRY_SCENE.instantiate() as Control
	var start_ms := Time.get_ticks_msec()
	first.set("outbox_storage_path_override", "user://service_ui_outbox_first_%d.json" % start_ms)
	root.add_child(first)
	(first.get_child(0) as ServiceAuth).session_path = "user://service_ui_no_session_%d.json" % start_ms
	_check(first.get_child_count() >= 3 and first.get_child(1) is ServiceAPI, "진입 장면에 앱 서비스 API 연결")
	var splash_logo := first.find_child("SplashLogo", true, false) as TextureRect
	var splash_title := first.find_child("SplashEnglishTitle", true, false) as Label
	_check(splash_logo != null and splash_logo.texture != null, "첫 장면에 제공 로고 이미지")
	_check(splash_title != null and splash_title.text == "ZOMBIE ESCAPE", "로고 아래 작은 영문명")
	await create_timer(3.1).timeout
	_check(first.find_child("AuthScreen", true, false) != null, "약 3초 뒤 신규 사용자는 인증 화면")
	_check(Time.get_ticks_msec() - start_ms >= 2900, "인트로 노출 시간 약 3초")
	if not ResourceLoader.exists("res://scenes/ui/계정_화면.tscn"):
		_check(false, "계정 관리 장면이 있어야 함")
	else:
		first.call("_show_title")
		var title_screen := first.find_child("ServiceTitle", true, false)
		title_screen.emit_signal("account_requested")
		await process_frame
		_check(first.find_child("AccountScreen", true, false) != null, "타이틀 계정 버튼이 계정 관리 화면으로 이동")
		first.call("_show_title")
		var support_title := first.find_child("ServiceTitle", true, false)
		if not support_title.has_signal("support_requested"):
			_check(false, "타이틀에 문의·제보 진입 경로")
		else:
			support_title.emit_signal("support_requested")
			await process_frame
			_check(first.find_child("SupportScreen", true, false) != null, "타이틀 문의 버튼이 문의 화면으로 이동")
	first.queue_free()
	await process_frame

	var saved_path := "user://service_ui_saved_test_%d.json" % Time.get_ticks_usec()
	var saved := FileAccess.open(saved_path, FileAccess.WRITE)
	saved.store_string(JSON.stringify({"version": 1, "user_id": "test-user", "guest": false, "offline": false, "access_token": "dummy-access", "refresh_token": "dummy-refresh", "expires_at": int(Time.get_unix_time_from_system()) + 3600}))
	saved = null
	var returning := ENTRY_SCENE.instantiate() as Control
	returning.set("outbox_storage_path_override", "user://service_ui_outbox_returning_%d.json" % start_ms)
	root.add_child(returning)
	(returning.get_child(0) as ServiceAuth).session_path = saved_path
	var profile_calls: Array[String] = []
	if returning.get_child_count() >= 3 and returning.get_child(1) is ServiceAPI:
		(returning.get_child(1) as ServiceAPI).transport_override = func(_method: int, path: String, _body: String, _token: String) -> Dictionary:
			profile_calls.append(path)
			return {"ok": true, "status": 200, "data": {"profile": {"user_id": "test-user", "is_guest": false}}}
	await create_timer(3.1).timeout
	_check(returning.find_child("ServiceTitle", true, false) != null, "저장된 세션은 인증 화면 건너뛰기")
	_check(profile_calls == ["/functions/v1/ensure-profile"], "저장된 서버 세션의 프로필 확인")
	returning.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path))
	_check(not FileAccess.file_exists(saved_path), "격리된 테스트 세션 정리")


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error("FAIL: " + description)

extends Control

signal authenticated
signal back_requested

var _auth: ServiceAuth
var _account_mode := false
var _mode := "login"
var _busy := false
var _email: LineEdit
var _password: LineEdit
var _status: Label
var _hint: Label
var _heading: Label
var _tabs: HBoxContainer
var _primary: Button
var _guest: Button
var _forgot: Button
var _back: Button
var _logout: Button
var _login_tab: Button
var _signup_tab: Button


func setup(auth_client: ServiceAuth, account_mode: bool = false) -> void:
	_auth = auth_client
	_account_mode = account_mode


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_form()
	_set_mode("account" if _account_mode else "login")
	if not _auth.is_configured():
		_set_status("서버 공개 설정이 아직 없어 로그인·가입은 사용할 수 없습니다. 오프라인 게스트로 게임 화면을 확인할 수 있습니다.")


func _build_background() -> void:
	var image := TextureRect.new()
	image.name = "AuthBackground"
	image.texture = preload("res://assets/ui/로그인_배경.png")
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(image)
	var veil := ColorRect.new()
	veil.color = Color(0.015, 0.024, 0.035, 0.38)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)


func _build_form() -> void:
	var panel := PanelContainer.new()
	panel.name = "AuthPanel"
	panel.anchor_left = 0.065
	panel.anchor_right = 0.445
	panel.anchor_top = 0.065
	panel.anchor_bottom = 0.935
	panel.custom_minimum_size.x = 450
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.07, 0.085, 0.94)
	panel_style.border_color = Color(0.58, 0.37, 0.33, 0.8)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var margins := MarginContainer.new()
	for side in ["left", "right"]:
		margins.add_theme_constant_override("margin_" + side, 34)
	for side in ["top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margins)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margins.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 15)
	scroll.add_child(column)

	var eyebrow := _label("좀비탈출  /  ZOMBIE ESCAPE", 20, Color("d5aba0"))
	column.add_child(eyebrow)
	_heading = _label("생존 기록을 이어가세요", 36, Color("f3e9df"))
	column.add_child(_heading)
	_hint = _label("이메일로 기록을 복구하거나 게스트로 바로 시작하세요.", 20, Color("c8c3bf"))
	column.add_child(_hint)
	column.add_spacer(false)

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 10)
	_login_tab = _button("로그인", _on_login_tab)
	_login_tab.name = "LoginTab"
	_signup_tab = _button("회원가입", _on_signup_tab)
	_signup_tab.name = "SignupTab"
	_login_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_signup_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_child(_login_tab)
	_tabs.add_child(_signup_tab)
	column.add_child(_tabs)

	_email = LineEdit.new()
	_email.name = "EmailField"
	_email.placeholder_text = "이메일 주소"
	_email.max_length = 254
	_email.custom_minimum_size.y = 54
	_email.add_theme_font_size_override("font_size", 21)
	column.add_child(_email)
	_password = LineEdit.new()
	_password.name = "PasswordField"
	_password.placeholder_text = "비밀번호 (8자 이상)"
	_password.secret = true
	_password.max_length = 128
	_password.custom_minimum_size.y = 54
	_password.add_theme_font_size_override("font_size", 21)
	column.add_child(_password)
	_email.text_submitted.connect(func(_text: String) -> void:
		if _busy:
			return
		if _password.visible:
			_password.grab_focus()
		else:
			_on_primary())
	_password.text_submitted.connect(func(_text: String) -> void: _on_primary())

	_status = _label("", 19, Color("dfb4a3"))
	_status.name = "StatusMessage"
	_status.custom_minimum_size.y = 55
	column.add_child(_status)
	_primary = _button("로그인", _on_primary, true)
	_primary.name = "PrimaryAction"
	column.add_child(_primary)
	_forgot = _button("비밀번호를 잊으셨나요?", _on_forgot)
	column.add_child(_forgot)
	_guest = _button("게스트로 시작", _on_guest)
	_guest.name = "GuestAction"
	column.add_child(_guest)
	_logout = _button("로그아웃", _on_logout)
	column.add_child(_logout)
	_back = _button("돌아가기", _on_back)
	column.add_child(_back)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 54
	button.add_theme_font_size_override("font_size", 21)
	if primary:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("ad5041")
		style.set_corner_radius_all(6)
		style.content_margin_left = 20
		style.content_margin_right = 20
		button.add_theme_stylebox_override("normal", style)
	button.pressed.connect(callback)
	return button


func _set_mode(next_mode: String) -> void:
	_mode = next_mode
	_busy = false
	_set_status("")
	_tabs.visible = next_mode == "login" or next_mode == "signup"
	_email.visible = next_mode != "account" and next_mode != "signup_wait"
	_password.visible = next_mode == "login" or next_mode == "signup_wait"
	_forgot.visible = next_mode == "login"
	_guest.visible = next_mode == "login" or next_mode == "signup"
	_logout.visible = next_mode == "account" and _auth.is_logged_in()
	_back.visible = next_mode == "reset" or next_mode == "signup_wait" or next_mode == "account"
	_login_tab.disabled = next_mode == "login"
	_signup_tab.disabled = next_mode == "signup"
	match next_mode:
		"signup":
			_heading.text = "게스트 기록을 이어받으세요"
			_hint.text = "이메일 인증 후 비밀번호를 설정합니다. 현재 게스트 기록은 같은 계정에 남습니다."
			_primary.text = "인증 메일 보내기"
		"signup_wait":
			_heading.text = "메일 확인 후 계속"
			_hint.text = "메일의 확인 링크를 열고 앱으로 돌아와 비밀번호를 설정하세요. 앱 복귀 연결은 이후 실기기 검증이 필요합니다."
			_primary.text = "비밀번호 설정"
		"reset":
			_heading.text = "비밀번호 재설정"
			_hint.text = "입력하신 이메일로 복구 메일을 보냅니다."
			_primary.text = "재설정 메일 보내기"
		"account":
			_heading.text = "내 계정"
			_hint.text = "현재 상태: %s" % _auth.display_name()
			_primary.text = "이어서 하기"
		_:
			_heading.text = "생존 기록을 이어가세요"
			_hint.text = "이메일로 기록을 복구하거나 게스트로 바로 시작하세요."
			_primary.text = "로그인"


func _set_status(text: String) -> void:
	_status.text = text


func _set_busy(value: bool) -> void:
	_busy = value
	_primary.disabled = value
	_guest.disabled = value
	_login_tab.disabled = value or _mode == "login"
	_signup_tab.disabled = value or _mode == "signup"
	_forgot.disabled = value
	_back.disabled = value
	_logout.disabled = value


func _on_login_tab() -> void:
	if _busy:
		return
	_set_mode("login")


func _on_signup_tab() -> void:
	if _busy:
		return
	_set_mode("signup")


func _on_forgot() -> void:
	if _busy:
		return
	_set_mode("reset")


func _on_back() -> void:
	if _busy:
		return
	if _account_mode and _mode == "account":
		back_requested.emit()
	else:
		_set_mode("account" if _account_mode else "login")


func _on_logout() -> void:
	if _busy:
		return
	if not _auth.sign_out():
		_set_status("로그아웃 실패: 기기의 세션 파일을 삭제하지 못했습니다. 다시 시도해 주세요.")
		return
	_account_mode = false
	_set_mode("login")
	_set_status("로그아웃했습니다. 새 게스트 또는 다른 계정으로 시작하세요.")


func _on_primary() -> void:
	if _busy:
		return
	match _mode:
		"account": authenticated.emit()
		"login": await _submit_login()
		"signup": await _submit_signup()
		"signup_wait": await _submit_new_password()
		"reset": await _submit_reset()


func _submit_login() -> void:
	if not _auth.is_configured():
		_set_status("서버 연결 설정이 없어 로그인할 수 없습니다. 게스트로 시작할 수 있습니다.")
		return
	if not _email.text.contains("@") or _password.text.is_empty():
		_set_status("이메일과 비밀번호를 확인해 주세요.")
		return
	_set_busy(true)
	_set_status("로그인 중입니다…")
	var result: Dictionary = await _auth.sign_in_password(_email.text.strip_edges(), _password.text)
	_password.clear()
	_set_busy(false)
	if result.get("ok", false):
		authenticated.emit()
	else:
		_set_status(_error_text(result))


func _submit_signup() -> void:
	if not _auth.is_configured():
		_set_status("서버 연결 설정이 없어 인증 메일을 보낼 수 없습니다.")
		return
	if not _email.text.contains("@"):
		_set_status("사용할 이메일 주소를 입력해 주세요.")
		return
	if _auth.is_guest() and not _auth.has_remote_session():
		_set_status("오프라인 게스트 기록은 먼저 서버에 동기화해야 합니다. 이 화면에서는 계정을 교체하지 않습니다.")
		return
	_set_busy(true)
	if not _auth.has_remote_session():
		_set_status("게스트 계정을 준비 중입니다…")
		var guest_result: Dictionary = await _auth.sign_in_anonymous()
		if not guest_result.get("ok", false):
			_set_busy(false)
			_set_status(_error_text(guest_result))
			return
	_set_status("인증 메일을 요청 중입니다…")
	var result: Dictionary = await _auth.request_guest_email(_email.text.strip_edges())
	_set_busy(false)
	if result.get("ok", false):
		_set_mode("signup_wait")
		_set_status("이메일을 확인한 뒤 이 화면으로 돌아오세요.")
	else:
		_set_status(_error_text(result))


func _submit_new_password() -> void:
	if _password.text.length() < 8:
		_set_status("비밀번호는 8자 이상으로 입력해 주세요.")
		return
	_set_busy(true)
	_set_status("이메일 확인과 비밀번호 설정을 확인 중입니다…")
	var result: Dictionary = await _auth.confirm_guest_email_and_password(_password.text)
	_password.clear()
	_set_busy(false)
	if result.get("ok", false):
		authenticated.emit()
	else:
		_set_status(_error_text(result))


func _submit_reset() -> void:
	if not _auth.is_configured():
		_set_status("서버 연결 설정이 없어 재설정 메일을 보낼 수 없습니다.")
		return
	if not _email.text.contains("@"):
		_set_status("이메일 주소를 입력해 주세요.")
		return
	_set_busy(true)
	var result: Dictionary = await _auth.request_password_reset(_email.text.strip_edges())
	_set_busy(false)
	_set_status("복구 메일 요청을 보냈습니다. 메일을 확인해 주세요." if result.get("ok", false) else _error_text(result))


func _on_guest() -> void:
	if _busy:
		return
	if _auth.has_remote_session() and not _auth.is_guest():
		_set_status("현재 회원 계정에서 로그아웃한 뒤 게스트로 시작해 주세요.")
		return
	if _auth.is_configured():
		_set_busy(true)
		_set_status("게스트 계정을 준비 중입니다…")
		var result: Dictionary = await _auth.sign_in_anonymous()
		_set_busy(false)
		if result.get("ok", false) and _auth.is_guest() and not _auth.get_user_id().is_empty():
			authenticated.emit()
			return
		if result.get("error", "") == "identity_changed":
			_set_status(_error_text(result))
			return
	if not _auth.start_offline_guest() or _auth.get_user_id().is_empty():
		_set_status("게스트 세션을 저장하지 못했습니다. 현재 계정과 기기 저장 공간을 확인한 뒤 다시 시도해 주세요.")
		return
	authenticated.emit()


func _error_text(result: Dictionary) -> String:
	var error := str(result.get("error", "잠시 후 다시 시도해 주세요."))
	match error:
		"not_configured", "server_not_configured": return "서버 연결 설정이 없습니다. 게스트로 시작할 수 있습니다."
		"invalid_credentials": return "이메일이나 비밀번호가 맞지 않습니다."
		"invalid_email": return "올바른 이메일 주소를 입력해 주세요."
		"email_exists", "user_already_exists": return "이미 사용 중인 이메일입니다. 로그인하거나 비밀번호 재설정 메일을 요청해 주세요."
		"rate_limited", "over_email_send_rate_limit": return "요청이 너무 많습니다. 잠시 기다린 뒤 다시 시도해 주세요."
		"identity_mismatch": return "계정 정보가 일치하지 않아 작업을 중단했습니다. 현재 계정을 확인한 뒤 다시 시도해 주세요."
		"email_not_requested": return "먼저 인증 메일을 요청하고 이메일을 확인해 주세요."
		"remote_guest_required": return "온라인 게스트 계정이 필요합니다. 인터넷 연결과 현재 계정을 확인해 주세요."
		"not_guest": return "게스트 계정에서만 이메일 연결을 사용할 수 있습니다."
		"server_unavailable": return "서버를 사용할 수 없습니다. 잠시 후 다시 시도해 주세요."
		"invalid_response": return "서버 응답을 확인하지 못했습니다. 다시 시도해 주세요."
		"email_not_confirmed": return "이메일의 확인 링크를 먼저 열어 주세요."
		"weak_password": return "비밀번호는 8자 이상이어야 합니다."
		"network_unavailable": return "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
		_: return "요청을 완료하지 못했습니다. 계정과 인터넷 연결을 확인한 뒤 다시 시도해 주세요."

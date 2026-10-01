extends Control

signal back_requested
signal signed_out
signal email_link_requested
# Parent clears this owner's local progress/outbox before session identity is erased.
signal account_deleted(owner_id: String)

var _auth: ServiceAuth
var _api: ServiceAPI
var _nickname: LineEdit
var _status: Label
var _busy := false
var _deleted_server_owner := ""
var _delete_dialog: ConfirmationDialog
var _logout_dialog: ConfirmationDialog


func setup(auth_client: ServiceAuth, service_api: ServiceAPI) -> void:
	_auth = auth_client
	_api = service_api


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	if _auth.has_remote_session():
		_load_profile()
	else:
		_status.text = "오프라인 게스트입니다. 계정 관리는 인터넷 연결 후 사용할 수 있습니다."


func _build_layout() -> void:
	var background := TextureRect.new()
	background.texture = preload("res://assets/ui/로그인_배경.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var darken := ColorRect.new()
	darken.color = Color(0.01, 0.02, 0.03, 0.55)
	darken.mouse_filter = Control.MOUSE_FILTER_IGNORE
	darken.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(darken)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.07
	panel.anchor_right = 0.45
	panel.anchor_top = 0.06
	panel.anchor_bottom = 0.94
	panel.custom_minimum_size.x = 460
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.07, 0.085, 0.95)
	style.border_color = Color(0.58, 0.37, 0.33, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	scroll.add_child(column)
	column.add_child(_label("내 계정", 36))
	column.add_child(_label("상태: " + _auth.display_name(), 20))
	if _auth.is_guest():
		var warning := _label("게스트는 이메일 계정을 연결하기 전 앱 삭제·기기 변경·로그아웃 또는 데이터 삭제 시 기록을 복구할 수 없습니다. 기록을 보존하려면 먼저 이메일 계정을 연결하세요.", 18)
		warning.name = "GuestRecoveryWarning"
		column.add_child(warning)
	_nickname = LineEdit.new()
	_nickname.name = "NicknameField"
	_nickname.placeholder_text = "닉네임 (2~24자)"
	_nickname.max_length = 24
	_nickname.custom_minimum_size.y = 52
	_nickname.editable = _auth.has_remote_session()
	_nickname.text_submitted.connect(func(_text: String) -> void: _save_nickname())
	column.add_child(_nickname)
	column.add_child(_button("닉네임 저장", _save_nickname, _auth.has_remote_session()))
	_status = _label("", 18)
	_status.name = "AccountStatus"
	_status.custom_minimum_size.y = 65
	column.add_child(_status)
	if _auth.is_guest():
		column.add_child(_button("이메일 계정 연결", _request_email_link, true))
	else:
		column.add_child(_button("비밀번호 재설정 메일", _reset_password, _auth.has_remote_session()))
	column.add_child(_button("로그아웃", _confirm_logout, true))
	column.add_child(_button("회원 탈퇴", _confirm_delete, true))
	column.add_child(_button("타이틀로", _request_back, true))

	_logout_dialog = ConfirmationDialog.new()
	_logout_dialog.title = "로그아웃"
	_logout_dialog.dialog_text = "로그아웃하면 이 기기의 미전송 게스트 기록을 복구하지 못할 수 있습니다. 계속할까요?"
	_logout_dialog.confirmed.connect(_logout)
	add_child(_logout_dialog)
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "회원 탈퇴"
	_delete_dialog.dialog_text = "이 계정과 본인 데이터를 삭제합니다. 게스트 기록을 포함해 삭제된 데이터는 복구할 수 없습니다. 정말 탈퇴할까요?"
	_delete_dialog.confirmed.connect(_delete_account)
	add_child(_delete_dialog)


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("eee3d7"))
	return label


func _button(text: String, callback: Callable, enabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not enabled
	button.custom_minimum_size.y = 52
	button.add_theme_font_size_override("font_size", 21)
	button.pressed.connect(callback)
	return button


func _load_profile() -> void:
	var result: Dictionary = await _api.post_function("ensure-profile", {})
	if not result.get("ok", false):
		_status.text = "계정 정보를 불러오지 못했습니다. 연결을 확인해 주세요."
		return
	var profile: Dictionary = await _api.fetch_profile()
	if profile.get("ok", false):
		var name: Variant = profile.get("profile", {}).get("nickname", "")
		_nickname.text = name if name is String else ""
		if _nickname.text.strip_edges().is_empty():
			_status.text = "닉네임이 아직 설정되지 않았습니다. 2~24자로 입력하고 저장해 주세요."
	else:
		_status.text = "닉네임을 불러오지 못했습니다."


func _save_nickname() -> void:
	if _busy:
		return
	if not _auth.has_remote_session():
		_status.text = "닉네임 변경에는 온라인 계정과 인터넷 연결이 필요합니다."
		return
	var candidate := _nickname.text.strip_edges()
	if candidate.length() < 2 or candidate.length() > 24 or candidate.contains("\n"):
		_status.text = "닉네임을 2~24자로 입력해 주세요."
		return
	_set_busy(true)
	_status.text = "닉네임 저장 중…"
	var result: Dictionary = await _api.update_nickname(candidate)
	if result.get("ok", false):
		var readback: Dictionary = await _api.fetch_profile()
		_status.text = "닉네임을 저장했습니다." if readback.get("ok", false) and str(readback.get("profile", {}).get("nickname", "")) == candidate else "저장 결과를 확인하지 못했습니다. 다시 조회해 주세요."
	else:
		_status.text = "닉네임을 저장하지 못했습니다. 2~24자와 인터넷 연결을 확인해 주세요."
	_set_busy(false)


func _reset_password() -> void:
	if _busy or _auth.is_guest() or not _auth.has_remote_session():
		return
	_set_busy(true)
	var result: Dictionary = await _auth.request_password_reset(_auth.display_name())
	_status.text = "재설정 메일을 요청했습니다. 메일을 확인해 주세요." if result.get("ok", false) else "재설정 메일을 요청하지 못했습니다. 연결을 확인해 주세요."
	_set_busy(false)


func _request_back() -> void:
	if not _busy:
		back_requested.emit()


func _request_email_link() -> void:
	if not _busy:
		email_link_requested.emit()


func _set_busy(value: bool) -> void:
	_busy = value
	for button in find_children("*", "Button", true, false):
		if value:
			button.set_meta("before_busy_disabled", button.disabled)
			button.disabled = true
		else:
			button.disabled = button.get_meta("before_busy_disabled", false)
	_nickname.editable = not value and _auth.has_remote_session()


func _confirm_logout() -> void:
	if _busy:
		return
	_logout_dialog.popup_centered()


func _logout() -> void:
	if _busy:
		return
	if not _auth.sign_out():
		_status.text = "로그아웃 실패: 기기의 세션 파일을 삭제하지 못했습니다. 다시 시도해 주세요."
		return
	signed_out.emit()


func _confirm_delete() -> void:
	if _busy:
		return
	_delete_dialog.popup_centered()


func _delete_account() -> void:
	if _busy:
		return
	var start_owner := _auth.get_user_id()
	if start_owner.is_empty():
		return
	_set_busy(true)
	if start_owner == _deleted_server_owner:
		_finish_account_delete(start_owner, true)
		return
	if not _auth.has_remote_session():
		_finish_account_delete(start_owner)
		return
	_status.text = "탈퇴를 요청 중입니다…"
	var result: Dictionary = await _api.post_function("delete-account", {"confirm": true})
	if _auth.get_user_id() != start_owner:
		_status.text = "계정이 변경되어 이전 탈퇴 응답을 적용하지 않았습니다."
		_set_busy(false)
		return
	var body: Variant = result.get("data", {})
	if result.get("ok", false) and body is Dictionary and body.get("status", "") == "deleted":
		_finish_account_delete(start_owner, true)
		return
	_status.text = "탈퇴를 확인하지 못했습니다. 계정은 그대로 유지됩니다."
	_set_busy(false)


func _finish_account_delete(start_owner: String, server_deleted: bool = false) -> void:
	if server_deleted:
		_deleted_server_owner = start_owner
	# Keep controls locked during synchronous signal handlers and after success.
	account_deleted.emit(start_owner)
	# A signal handler may replace the identity; never sign out that account.
	if _auth.get_user_id() != start_owner:
		_set_busy(false)
		return
	if not _auth.sign_out():
		_status.text = ("서버 계정은 삭제되었습니다. " if server_deleted else "") + "기기의 세션 정리에 실패했습니다. 로그아웃을 다시 시도해 주세요."
		_set_busy(false)
		return
	signed_out.emit()

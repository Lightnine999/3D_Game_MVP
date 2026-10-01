extends Control

signal back_requested

const MAX_MESSAGE_LENGTH := 2000
var _auth: ServiceAuth
var _api: ServiceAPI
var _kind := "question"
var _thread_id := ""
var _thread_closed := false
var _multiturn_enabled := false
var _last_run: Dictionary = {}
var _busy := false
var _message: TextEdit
var _chat_scroll: ScrollContainer
var _chat_messages: VBoxContainer
var _status: Label
var _mode_label: Label
var _send_button: Button
var _new_chat_button: Button


func setup(auth_client: ServiceAuth, service_api: ServiceAPI, multiturn_enabled: bool = false, last_run: Dictionary = {}) -> void:
	_auth = auth_client
	_api = service_api
	_multiturn_enabled = multiturn_enabled
	_last_run = last_run.duplicate(true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_screen()
	if not _auth.has_remote_session():
		_status.text = "문의·제보에는 인터넷 연결과 게스트 또는 회원 계정이 필요합니다."
	else:
		_restore_chat()


func _restore_chat() -> void:
	_busy = true
	_send_button.disabled = true
	_new_chat_button.disabled = true
	_status.text = "이전 대화를 불러오는 중입니다…"
	var owner_id := _auth.get_user_id()
	var recent: Dictionary = await _api.fetch_latest_support_thread()
	if not is_inside_tree() or _auth.get_user_id() != owner_id:
		return
	if recent.get("ok", false) and not str(recent.get("thread_id", "")).is_empty():
		var thread_id := str(recent["thread_id"])
		var history: Dictionary = await _api.fetch_support_messages(thread_id)
		if not is_inside_tree() or _auth.get_user_id() != owner_id:
			return
		if history.get("ok", false):
			for entry in history.get("messages", []):
				_append_message(str(entry["role"]), str(entry["content"]))
			_thread_id = thread_id
			_thread_closed = recent.get("status") == "closed"
	_status.text = "" if recent.get("ok", false) else "이전 대화를 불러오지 못했습니다. 새 문의는 보낼 수 있습니다."
	_busy = false
	_send_button.disabled = false
	_new_chat_button.disabled = false


func _build_screen() -> void:
	var background := TextureRect.new()
	background.texture = preload("res://assets/ui/로그인_배경.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var veil := ColorRect.new()
	veil.color = Color(0.012, 0.02, 0.03, 0.62)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.53
	panel.anchor_right = 0.97
	panel.anchor_top = 0.055
	panel.anchor_bottom = 0.945
	panel.custom_minimum_size.x = 500
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.07, 0.085, 0.95)
	style.border_color = Color(0.58, 0.37, 0.33, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	scroll.add_child(column)
	column.add_child(_label("AI 문의·제보", 36))
	var warning := _label("AI가 답변합니다. 개인정보(비밀번호·카드번호)는 입력하지 마세요.", 19)
	warning.name = "PrivacyWarning"
	column.add_child(warning)
	var conversation_notice := _label("연속 대화: 이전 질문·답변을 이어서 보냅니다." if _multiturn_enabled else "현재 서버는 단발 질문만 지원합니다. 이전 답변에 이어 질문하려면 서버 업데이트가 필요합니다. 독립된 질문은 ‘새 대화’를 누른 뒤 보내세요.", 18)
	conversation_notice.name = "ConversationNotice"
	column.add_child(conversation_notice)
	_new_chat_button = _button("새 대화", _new_chat)
	_new_chat_button.name = "NewChatButton"
	column.add_child(_new_chat_button)
	_mode_label = _label("질문", 21)
	column.add_child(_mode_label)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	modes.add_child(_button("게임 질문", func() -> void: _select_kind("question")))
	modes.add_child(_button("버그 제보", func() -> void: _select_kind("bug")))
	column.add_child(modes)
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.follow_focus = true
	_chat_scroll.name = "ChatScroll"
	_chat_scroll.custom_minimum_size.y = 300
	_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_chat_scroll)
	_chat_messages = VBoxContainer.new()
	_chat_messages.name = "ChatMessages"
	_chat_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_messages.add_theme_constant_override("separation", 12)
	_chat_scroll.add_child(_chat_messages)
	_message = TextEdit.new()
	_message.name = "MessageField"
	_message.custom_minimum_size.y = 90
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.placeholder_text = "메시지를 입력하세요 (Enter: 전송, Shift+Enter: 줄바꿈)"
	_message.gui_input.connect(_on_message_input)
	column.add_child(_message)
	_status = _label("", 18)
	_status.name = "SupportStatus"
	_status.custom_minimum_size.y = 32
	column.add_child(_status)
	_send_button = _button("보내기", _send_message)
	column.add_child(_send_button)
	column.add_child(_button("타이틀로", back_requested.emit))
	column.add_child(_label("버그 제보를 보내면 앱·기기 정보와 전달받은 최근 플레이 기록을 첨부합니다. 실제 게임 규칙 안내는 서버 검증 범위에 한정됩니다.", 16))


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("eee3d7"))
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.add_theme_font_size_override("font_size", 21)
	button.pressed.connect(callback)
	return button


func _select_kind(kind: String) -> void:
	if _busy:
		return
	_kind = kind
	_mode_label.text = "버그 제보" if kind == "bug" else "질문"


func _new_chat() -> void:
	if _busy:
		return
	_thread_id = ""
	_thread_closed = false
	for row in _chat_messages.get_children():
		_chat_messages.remove_child(row)
		row.queue_free()
	_status.text = "새 대화입니다. 이전 문의는 서버에 남으며, 다음 질문에는 이전 맥락을 보내지 않습니다."
	_message.grab_focus()


func _on_message_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER and not event.shift_pressed:
		_message.accept_event()
		_send_message()


func _append_message(role: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.set_meta("role", role)
	row.alignment = BoxContainer.ALIGNMENT_END if role == "user" else BoxContainer.ALIGNMENT_BEGIN
	var speaker := "나  ·  " if role == "user" else ("팀 CS  ·  " if role == "team" else "AI CS  ·  ")
	var bubble := _label(speaker + text, 20)
	bubble.custom_minimum_size.x = 300
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_END if role == "user" else Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color("465a63") if role == "user" else Color("243742")
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	bubble.add_theme_stylebox_override("normal", style)
	row.add_child(bubble)
	_chat_messages.add_child(row)
	call_deferred("_scroll_to_latest")


func _scroll_to_latest() -> void:
	if is_instance_valid(_chat_scroll):
		_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


func _send_message() -> void:
	if _busy:
		return
	if not _auth.has_remote_session():
		_status.text = "온라인 계정과 인터넷 연결이 필요합니다. 전송하지 않았으며 입력 내용은 그대로 남아 있습니다."
		return
	if _kind == "question" and _thread_closed:
		_status.text = "종료된 문의입니다. 기록은 그대로 보존됩니다. ‘새 대화’를 눌러 독립된 질문을 보내세요."
		return
	if _kind == "question" and not _thread_id.is_empty() and not _multiturn_enabled:
		_status.text = "연속 대화 서버 업데이트 전입니다. 후속 질문은 전송하지 않았습니다."
		return
	var message := _message.text.strip_edges()
	if message.is_empty() or message.length() > MAX_MESSAGE_LENGTH:
		_status.text = "내용을 1~2000자로 입력해 주세요."
		return
	_busy = true
	_send_button.disabled = true
	_status.text = "서버에 전달 중…"
	_new_chat_button.disabled = true
	_message.editable = false
	var payload := {"kind": _kind, "message": message}
	var continuing_thread := _thread_id if _kind == "question" else ""
	if not continuing_thread.is_empty():
		payload["threadId"] = continuing_thread
	if _kind == "bug":
		payload["bug_context"] = _bug_context()
	var result: Dictionary = await _api.post_function("support-chat", payload)
	_busy = false
	_send_button.disabled = false
	if not result.get("ok", false):
		_new_chat_button.disabled = false
		_message.editable = true
		_status.text = "오늘 문의 한도에 도달했습니다. 전송을 확인하지 못했습니다." if result.get("status", 0) == 429 else "전송을 확인하지 못했습니다. 인터넷 연결 또는 계정 상태를 확인한 뒤 다시 시도해 주세요."
		return
	var data: Variant = result.get("data", {})
	_new_chat_button.disabled = false
	_message.editable = true
	if not data is Dictionary or not data.get("status", "") in ["ai_answered", "needs_human"]:
		_status.text = "서버 응답을 확인하지 못했습니다."
		return
	if _kind == "question":
		var returned_thread := str(data.get("threadId", ""))
		if returned_thread.is_empty() or (not continuing_thread.is_empty() and returned_thread != continuing_thread):
			_status.text = "연속 대화가 서버에서 확인되지 않았습니다. 서버 업데이트가 필요합니다."
			return
		_thread_id = returned_thread
	_append_message("user", message)
	_append_message("assistant", str(data.get("reply", "")))
	_status.text = "팀 확인 대상으로 접수됐습니다." if data.get("status") == "needs_human" else "AI 답변이 도착했습니다."
	_message.clear()


func _bug_context() -> Dictionary:
	# Snapshot comes from the caller; never invent or mutate gameplay values.
	var model := str(OS.call("get_model_name")) if OS.has_method("get_model_name") else ""
	var os_version := str(OS.call("get_version")) if OS.has_method("get_version") else ""
	return {
		"app_version": str(ProjectSettings.get_setting("application/config/version", "0.0.1")),
		"platform": OS.get_name(),
		"device_model": model,
		"os_version": os_version,
		"last_run": _last_run.duplicate(true),
	}

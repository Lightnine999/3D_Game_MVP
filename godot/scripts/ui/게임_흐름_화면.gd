extends Control

signal play_requested
signal back_requested
signal retry_requested
signal support_requested
signal tutorial_finished

const INK := Color("ede2cd")
const COPPER := Color("d5a277")
const MUTED := Color("c4cab8")
var _mode := "stage"
var _data: Dictionary = {}
var _column: VBoxContainer

func configure(mode: String, data: Dictionary = {}) -> void:
	_mode = mode if mode in ["stage", "tutorial", "result"] else "stage"
	_data = data.duplicate(true)
	if is_node_ready(): _build()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	name = {"stage":"StageCardScreen", "tutorial":"TutorialScreen", "result":"ResultScreen"}[_mode]
	var ground := ColorRect.new()
	ground.color = Color("101c19")
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ground)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right"]: margin.add_theme_constant_override("margin_"+side, 32)
	for side in ["top","bottom"]: margin.add_theme_constant_override("margin_"+side, 24)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("192b24"), Color("80664f"), 1))
	margin.add_child(panel)
	var inset := MarginContainer.new()
	for side in ["left","right","top","bottom"]: inset.add_theme_constant_override("margin_"+side, 24)
	panel.add_child(inset)
	var scroll := ScrollContainer.new()
	scroll.name = "ScreenScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	inset.add_child(scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 12)
	scroll.add_child(_column)
	match _mode:
		"tutorial": _tutorial()
		"result": _result()
		_: _stage()

func _result() -> void:
	var cleared: bool = _data.get("cleared", false) == true
	_label("탈출 성공" if cleared else "탈출 실패", "ScreenHeading", 36)
	if _data.get("test_mode", false) == true:
		_label("TEST MODE · 이 결과는 일반 기록·미션 저장에서 제외됩니다.", "TestModeNotice", 22, COPPER)
	_label("달린 거리  %s m" % _number(_data.get("distance_m", 0)), "ResultDistance")
	_label("처치 수  %s" % _number(_data.get("kills", 0)), "ResultKills")
	_label("플레이 시간  %s 초" % _number(_data.get("duration_s", 0)), "ResultDuration")
	_label("칼 사용  " + ("사용함" if _data.get("knife_used", false) == true else "사용하지 않음"), "ResultKnife")
	if not cleared:
		_label("사망 원인  " + str(_data.get("death_reason", "확인되지 않음")), "ResultReason", 20, MUTED)
	_label("저장 상태  " + str(_data.get("save_status", "확인 대기")), "SaveStatus", 19, MUTED)
	_separator()
	_label("이번 도전의 미션", "MissionsHeading", 26)
	_missions(_data.get("mission_ids", []))
	_button("다시 도전", "RetryButton", retry_requested.emit, true)
	_button("타이틀로", "TitleButton", back_requested.emit)
	_button("AI 문의·제보", "ResultSupportButton", support_requested.emit)
	_focus("RetryButton")

func _tutorial() -> void:
	_label("달리기 전에, 이것만 기억하세요", "ScreenHeading", 34)
	_label("자동으로 전진합니다. 이동과 사격에 집중하세요.", "TutorialHint", 20, MUTED)
	_separator()
	_label("이동과 회피\nA/D 또는 ←/→ 방향키 · 화면 왼쪽을 좌우로 드래그\n좀비와 장애물 사이의 빈 길을 찾아 움직이세요.", "TutorialSection1")
	_separator()
	_label("사격과 보급\nPC: Space 사격 · R 재장전\n폰: 오른쪽을 누르고 있으면 사격 · 빈 탄창은 자동 재장전\n폰: 어느 손가락으로든 드래그 이동 · 왼쪽 터치로 이동 넘겨받기\n낙하산 보급 상자에 닿아 탄약을 확보하세요.", "TutorialSection2")
	_separator()
	_label("칼과 일시정지\n잡혔을 때 칼로 1회 탈출합니다. 칼 없이 잡히면 사망합니다.\nEsc / P로 일시정지할 수 있습니다.", "TutorialSection3")
	_button("확인했어요 · 도전 시작", "PlayButton", _finish_tutorial, true)
	_button("돌아가기", "TitleButton", back_requested.emit)
	_focus("PlayButton")

func _finish_tutorial() -> void:
	tutorial_finished.emit()
	play_requested.emit()

func _stage() -> void:
	_label("안개 낀 노을 들판", "ScreenHeading", 36)
	_label("요새 정문을 향해 달리세요. 피할지, 쏠지는 당신의 선택입니다.", "StageDescription")
	_label("목표 거리  %s m" % _number(_data.get("target_distance", 750)), "TargetDistance", 26, COPPER)
	_label("최고 기록  %s m" % _number(_data.get("best_distance_m", 0)), "BestDistance", 20, MUTED)
	_separator()
	_label("이번 도전의 미션", "MissionsHeading", 26)
	_missions(_data.get("completed_missions", []))
	_label("미션을 모두 달성하지 않아도 탈출하면 클리어입니다.", "MissionHint", 19, MUTED)
	_button("도전 시작", "PlayButton", play_requested.emit, true)
	_button("타이틀로", "TitleButton", back_requested.emit)
	_focus("PlayButton")

func _missions(ids: Array) -> void:
	var definitions: Array = _data.get("missions", [])
	var defaults := ["생존 · 탈출 지점에 도착", "좀비 15마리 처치", "부서진 다리 무사히 건너기"]
	for i in 3:
		var id := "M%d" % (i+1)
		var description: String = defaults[i]
		for entry in definitions:
			if entry is Dictionary and str(entry.get("id", "")) == id:
				description = str(entry.get("title", entry.get("name", description)))
		_label(("★  " if id in ids else "☆  ") + description + ("  · 달성" if id in ids else "  · 미달성"), "Mission"+id, 22, COPPER if id in ids else MUTED)

func _label(text: String, node_name: String, font_size: int = 22, color: Color = INK) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_column.add_child(label)
	return label

func _separator() -> void:
	var line := HSeparator.new()
	_column.add_child(line)

func _style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _button(text: String, node_name: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 54
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_stylebox_override("normal", _style(Color("385443") if primary else Color("223b30"), COPPER if primary else Color("6b7968"), 1))
	button.add_theme_stylebox_override("hover", _style(Color("47634d"), COPPER, 1))
	button.add_theme_stylebox_override("pressed", _style(Color("15261e"), COPPER, 1))
	var focus := _style(Color(0,0,0,0), INK, 2)
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(callback)
	_column.add_child(button)
	return button

func _focus(node_name: String) -> void:
	var button := find_child(node_name, true, false) as Control
	if button: button.call_deferred("grab_focus")

func _number(value: Variant) -> String:
	return str(value)

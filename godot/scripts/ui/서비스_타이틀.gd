extends Control

signal play_requested
signal account_requested
signal support_requested
signal shop_requested
signal settings_requested

var _auth: ServiceAuth
var _service_notice: Label


func setup(auth_client: ServiceAuth) -> void:
	_auth = auth_client


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var image := TextureRect.new()
	image.texture = preload("res://assets/ui/로그인_배경.png")
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	var veil := ColorRect.new()
	veil.color = Color(0.01, 0.02, 0.03, 0.57)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 480
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/ui/좀비탈출_로고.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(680, 180)
	column.add_child(logo)
	var english := _label("ZOMBIE ESCAPE", 23)
	english.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(english)
	var account := _label(_auth.display_name(), 23)
	account.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(account)
	_service_notice = _label("", 19)
	_service_notice.name = "ServiceNotice"
	_service_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_service_notice)
	var play := _button("스테이지 · 도전 시작", play_requested.emit)
	column.add_child(play)
	column.add_child(_button("게임 설정", settings_requested.emit))
	var manage := _button("계정", account_requested.emit)
	column.add_child(manage)
	var shop := _button("테스트 상점", shop_requested.emit)
	column.add_child(shop)
	var note := _label("구매는 서버 확인 후에만 반영됩니다.", 18)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(note)
	var support := _button("AI 문의·제보", support_requested.emit)
	support.name = "SupportCornerButton"
	support.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	support.offset_left = -260
	support.offset_right = -30
	support.offset_top = -100
	support.offset_bottom = -30
	add_child(support)


func show_service_notice(message: String) -> void:
	if is_instance_valid(_service_notice):
		_service_notice.text = message


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("e8ddd2"))
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 62
	button.add_theme_font_size_override("font_size", 25)
	button.pressed.connect(callback)
	return button

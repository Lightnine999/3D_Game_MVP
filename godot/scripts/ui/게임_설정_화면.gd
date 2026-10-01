extends Control

signal saved(values: Dictionary)
signal back_requested
signal calibrate_requested

const SETTINGS_PATH := "res://scripts/services/게임_설정.gd"
var _values: Dictionary = {}
var _tilt_available := false
var _column: VBoxContainer
var _mode: OptionButton
var _sliders: Dictionary = {}
var _calibrate: Button

func configure(values: Dictionary, tilt_available: bool = false) -> void:
	_values = load(SETTINGS_PATH).validated(values)
	_tilt_available = tilt_available
	if not _tilt_available: _values.control_mode = "drag"
	if is_node_ready(): _build()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _values.is_empty(): configure({})
	_build()

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_sliders.clear()
	name = "GameSettingsScreen"
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
	scroll.name = "SettingsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	inset.add_child(scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 10)
	scroll.add_child(_column)
	_label("게임 설정", "SettingsHeading", 34)
	_label("키보드 A/D · 방향키는 조작 방식과 관계없이 사용할 수 있습니다.", "KeyboardHint", 19)
	_label("조작 방식", "ControlModeLabel")
	_mode = OptionButton.new()
	_mode.name = "ControlMode"
	_mode.custom_minimum_size.y = 54
	_mode.add_theme_font_size_override("font_size", 22)
	_mode.add_item("드래그")
	_mode.add_item("기울이기")
	_mode.set_item_disabled(1, not _tilt_available)
	_mode.select(1 if _values.control_mode == "tilt" else 0)
	_column.add_child(_mode)
	_label("센서 사용 가능 · 기울이기 모드에서 현재 자세를 영점으로 맞추세요." if _tilt_available else "PC에는 기울이기 센서가 없어 기울이기 조작을 사용할 수 없습니다. 드래그 또는 키보드를 이용하세요.", "TiltAvailability", 19)
	_calibrate = _button("현재 자세로 영점 맞추기", "CalibrateButton", _request_calibration)
	_calibrate.disabled = not _tilt_available or _mode.selected != 1
	_mode.item_selected.connect(func(index: int): _calibrate.disabled = not _tilt_available or index != 1)
	_slider("sensitivity", "조작 감도", "Sensitivity", 0.5, 2.0, 0.05)
	_slider("sfx_volume", "효과음", "SFXVolume", 0.0, 1.0, 0.01)
	_slider("bgm_volume", "배경음", "BGMVolume", 0.0, 1.0, 0.01)
	_label("100%는 현재 게임의 기본 음량입니다. 저장 전 변경은 적용되지 않습니다.", "VolumeHint", 19)
	var save := _button("설정 저장", "SaveSettingsButton", _save, true)
	_button("취소 · 돌아가기", "BackSettingsButton", back_requested.emit)
	save.call_deferred("grab_focus")

func _slider(key: String, title: String, prefix: String, low: float, high: float, increment: float) -> void:
	var preview := _label("", prefix+"Value", 21)
	var slider := HSlider.new()
	slider.name = prefix+"Slider"
	slider.min_value = low
	slider.max_value = high
	slider.step = increment
	slider.value = _values[key]
	slider.custom_minimum_size.y = 50
	slider.focus_mode = Control.FOCUS_ALL
	slider.tooltip_text = title + " · 방향키로 조절"
	_column.add_child(slider)
	_sliders[key] = slider
	var update := func(value: float): preview.text = title + "  %.2f×" % value if key == "sensitivity" else title + "  %d%%" % roundi(value * 100)
	slider.value_changed.connect(update)
	update.call(slider.value)

func _save() -> void:
	var data := _values.duplicate(true)
	data.control_mode = "tilt" if _tilt_available and _mode.selected == 1 else "drag"
	for key in _sliders: data[key] = _sliders[key].value
	data = load(SETTINGS_PATH).validated(data)
	saved.emit(data)

func _request_calibration() -> void:
	if _tilt_available and _mode.selected == 1: calibrate_requested.emit()

func _label(text: String, node_name: String, size: int = 22) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("ede2cd"))
	_column.add_child(label)
	return label

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
	button.add_theme_font_size_override("font_size", 22)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]: button.add_theme_color_override(state, Color("ede2cd"))
	button.add_theme_stylebox_override("normal", _style(Color("385443") if primary else Color("223b30"), Color("d5a277") if primary else Color("6b7968"), 1))
	button.add_theme_stylebox_override("hover", _style(Color("47634d"), Color("d5a277"), 1))
	button.add_theme_stylebox_override("pressed", _style(Color("15261e"), Color("d5a277"), 1))
	button.add_theme_stylebox_override("disabled", _style(Color("223029"), Color("516051"), 1))
	button.add_theme_color_override("font_disabled_color", Color("a9b3a3"))
	button.add_theme_stylebox_override("focus", _style(Color(0,0,0,0), Color("ede2cd"), 2))
	button.pressed.connect(callback)
	_column.add_child(button)
	return button

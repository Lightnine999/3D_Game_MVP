extends PanelContainer

signal command_requested(command: String, value: Variant)
signal close_requested

const KINDS := ["walker", "runner", "tank", "ambusher"]
var _allowed := false
var _stats: Label
var _performance: Label
var _kinds: OptionButton
var _timer := 0.0

func configure(enabled: bool) -> void:
	_allowed = enabled and OS.is_debug_build()
	visible = _allowed

func _ready() -> void:
	name = "GameTestPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(430, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.065, 0.052, 0.97)
	style.border_color = Color("a97845")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.name = "TestPanelScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	scroll.add_child(stack)
	var title := Label.new()
	title.text = "TEST MODE · 게임 테스트"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("e2b678"))
	stack.add_child(title)
	var note := Label.new()
	note.text = "조작을 사용한 판은 일반 기록·미션에 반영되지 않습니다."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 19)
	stack.add_child(note)
	_stats = Label.new()
	_stats.name = "DebugRunStats"
	_stats.add_theme_font_size_override("font_size", 20)
	stack.add_child(_stats)
	_performance = Label.new()
	_performance.name = "DebugPerformance"
	_performance.add_theme_font_size_override("font_size", 18)
	stack.add_child(_performance)
	var invulnerable := CheckButton.new()
	invulnerable.name = "InvulnerableToggle"
	invulnerable.text = "무적"
	invulnerable.custom_minimum_size.y = 50
	invulnerable.toggled.connect(func(enabled: bool) -> void:
		if _allowed:
			command_requested.emit("invulnerable", enabled))
	stack.add_child(invulnerable)
	stack.add_child(_button("Skip200Button", "200m 건너뛰기", "skip", 200))
	stack.add_child(_button("GrantAmmoButton", "예비탄 12발 지급", "ammo", 12))
	stack.add_child(_button("GrantKnifeButton", "칼 1회 보충", "knife", 1))
	_kinds = OptionButton.new()
	_kinds.name = "ZombieKind"
	_kinds.custom_minimum_size.y = 50
	for kind_name in ["워커", "러너", "탱커", "매복"]:
		_kinds.add_item(kind_name)
	stack.add_child(_kinds)
	var spawn := Button.new()
	spawn.name = "SpawnZombieButton"
	spawn.text = "선택한 좀비 소환"
	spawn.custom_minimum_size.y = 50
	spawn.pressed.connect(func() -> void:
		if _allowed:
			command_requested.emit("spawn", KINDS[_kinds.selected]))
	stack.add_child(spawn)
	var close := Button.new()
	close.name = "CloseTestPanelButton"
	close.text = "닫기 [F8]"
	close.custom_minimum_size.y = 50
	close.pressed.connect(func() -> void: close_requested.emit())
	stack.add_child(close)
	visible = _allowed
	update_snapshot({})
	_update_performance()

func _button(node_name: String, text: String, command: String, value: Variant) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 50
	button.pressed.connect(func() -> void:
		if _allowed:
			command_requested.emit(command, value))
	return button

func update_snapshot(snapshot: Dictionary) -> void:
	if _stats != null:
		_stats.text = "거리 %.0fm · 처치 %d\n탄창 %d · 예비탄 %d" % [float(snapshot.get("distance_m", 0.0)), int(snapshot.get("kills", 0)), int(snapshot.get("ammo", 0)), int(snapshot.get("reserve", 0))]

func _process(delta: float) -> void:
	if not visible:
		return
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		_update_performance()

func _update_performance() -> void:
	if _performance != null:
		_performance.text = "FPS %d · draw calls %d\n렌더 메모리 %.1f MiB · 약 1초 갱신" % [Engine.get_frames_per_second(), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]

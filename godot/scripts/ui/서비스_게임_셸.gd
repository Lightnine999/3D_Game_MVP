extends Node3D
signal run_finished(result: Dictionary)
signal title_requested
var _stage: Node3D
var _values: Dictionary = {}
var _injected := false
var _tracker = preload("res://scripts/services/게임_미션_추적.gd").new()
var _test_panel: Control
var _test_mark: Label
var _finished := false
var _input_state: Array[Dictionary] = []

func configure(auth: ServiceAuth, api: ServiceAPI, values: Dictionary, multiturn: bool = false) -> void:
	_auth = auth
	_api = api
	_values = values.duplicate(true)
	_support_multiturn_enabled = multiturn
	_injected = true

const STAGE_PREVIEW := preload("res://scenes/stage/stage_preview.tscn")
const SUPPORT_SCREEN := preload("res://scenes/ui/문의_화면.tscn")
const SERVICE_ENTRY := "res://scenes/ui/서비스_진입.tscn"
const PUBLIC_CONFIG := "res://config/서비스_공개설정.json"

var stage_override: Node3D # Test-only stand-in; production instantiates the team's scene.
var auth_session_path_override := "" # Isolated test session file.
var _auth: ServiceAuth
var _api: ServiceAPI
var _support_multiturn_enabled := false
var _layer: CanvasLayer
var _pause_support: Button
var _pause_title: Button
var _chat: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stage = stage_override if stage_override != null else STAGE_PREVIEW.instantiate()
	if _stage.has_signal("service_finished"):
		_stage.set("service_managed", true)
		_stage.connect("service_finished", _finish_stage)
	add_child(_stage)
	_tracker.configure("field_01", StageBuilderV2.STAGE_LENGTH, StageBuilderV2.RIVER_Z0, StageBuilderV2.RIVER_Z1)
	if _stage.has_method("service_apply_settings"):
		_stage.service_apply_settings(_values)
	_apply_audio(_stage)
	get_tree().node_added.connect(_audio_node_added)
	if not _injected:
		_auth = ServiceAuth.new()
		if not auth_session_path_override.is_empty():
			_auth.session_path = auth_session_path_override
		add_child(_auth)
		_api = ServiceAPI.new()
		add_child(_api)
		if auth_session_path_override.is_empty(): _load_public_config()
		_auth.restore_local_session()
	_layer = CanvasLayer.new()
	_layer.layer = 12
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	var overlay := Control.new()
	overlay.name = "ServicePauseOverlay"
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(overlay)
	_pause_support = Button.new()
	_pause_support.name = "PauseSupportButton"
	_pause_support.text = "AI 문의·제보"
	_pause_support.add_theme_font_size_override("font_size", 23)
	_pause_support.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_pause_support.offset_left = -260
	_pause_support.offset_right = -30
	_pause_support.offset_top = -100
	_pause_support.offset_bottom = -30
	_pause_support.pressed.connect(_open_chat)
	overlay.add_child(_pause_support)
	_pause_title = Button.new()
	_pause_title.name = "PauseTitleButton"
	_pause_title.text = "타이틀로"
	_pause_title.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_pause_title.offset_left = 30
	_pause_title.offset_right = 220
	_pause_title.offset_top = -100
	_pause_title.offset_bottom = -30
	_pause_title.pressed.connect(_return_to_title)
	overlay.add_child(_pause_title)
	if OS.is_debug_build():
		var debug_button := Button.new()
		debug_button.name = "OpenTestPanelButton"
		debug_button.text = "개발자 테스트 [F8]"
		debug_button.position = Vector2(16, 65)
		debug_button.pressed.connect(_toggle_test_panel)
		overlay.add_child(debug_button)
		_test_panel = preload("res://scripts/ui/게임_테스트_패널.gd").new()
		_test_panel.configure(false)
		_test_panel.command_requested.connect(_debug_command)
		_test_panel.close_requested.connect(_toggle_test_panel)
		_layer.add_child(_test_panel)
		_test_panel.position = Vector2(16, 110)
		_fit_test_panel()
		get_viewport().size_changed.connect(_fit_test_panel)
	_test_mark = Label.new()
	_test_mark.name = "TestModeMark"
	_test_mark.text = "TEST MODE · 일반 기록 저장 제외"
	_test_mark.position = Vector2(280, 65)
	_test_mark.add_theme_font_size_override("font_size", 24)
	_test_mark.visible = false
	overlay.add_child(_test_mark)
	_update_pause_ui()


func _load_public_config() -> void:
	if not FileAccess.file_exists(PUBLIC_CONFIG):
		return
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(PUBLIC_CONFIG))
	if config is Dictionary:
		var url := str(config.get("supabase_url", ""))
		var key := str(config.get("supabase_publishable_key", ""))
		_auth.set_public_config(url, key)
		_api.configure(_auth, url, key)
		_support_multiturn_enabled = config.get("support_multiturn_enabled", false) == true


func _process(_delta: float) -> void:
	_update_pause_ui()
	if is_instance_valid(_chat): get_tree().paused = true
	if not _finished and is_instance_valid(_stage) and _stage.has_method("service_snapshot"):
		var snapshot: Dictionary = _stage.service_snapshot()
		_tracker.sample(snapshot)
		if is_instance_valid(_test_panel) and _test_panel.visible: _test_panel.update_snapshot(snapshot)


func _update_pause_ui() -> void:
	if is_instance_valid(_pause_support):
		_pause_support.visible = get_tree().paused and not is_instance_valid(_chat)
	if is_instance_valid(_pause_title):
		_pause_title.visible = get_tree().paused and not is_instance_valid(_chat)


func _open_chat() -> void:
	if not get_tree().paused or is_instance_valid(_chat):
		return
	_lock_stage_input(_stage)
	_chat = SUPPORT_SCREEN.instantiate() as Control
	_chat.name = "SupportScreen"
	_chat.process_mode = Node.PROCESS_MODE_ALWAYS
	_chat.setup(_auth, _api, _support_multiturn_enabled, _stage.service_snapshot() if _stage.has_method("service_snapshot") else {})
	_chat.back_requested.connect(_close_chat)
	_layer.add_child(_chat)
	_chat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_pause_ui()


func _close_chat() -> void:
	if is_instance_valid(_chat):
		_chat.queue_free()
	_chat = null
	for state in _input_state:
		var node: Node = state.node
		if is_instance_valid(node):
			node.set_process_input(state.input)
			node.set_process_unhandled_input(state.unhandled)
			node.set_process_unhandled_key_input(state.key)
	_input_state.clear()
	get_tree().paused = true
	_update_pause_ui()


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_chat) and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_toggle_test_panel()
		get_viewport().set_input_as_handled()
	if is_instance_valid(_chat) and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close_chat()


func _return_to_title() -> void:
	if not get_tree().paused:
		return
	get_tree().paused = false
	if _injected:
		title_requested.emit()
	else:
		get_tree().change_scene_to_file(SERVICE_ENTRY)


func _lock_stage_input(node: Node) -> void:
	_input_state.append({"node": node, "input": node.is_processing_input(), "unhandled": node.is_processing_unhandled_input(), "key": node.is_processing_unhandled_key_input()})
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for child in node.get_children(): _lock_stage_input(child)

func _finish_stage(snapshot: Dictionary) -> void:
	if _finished: return
	_finished = true
	_tracker.sample(snapshot)
	var result: Dictionary = _tracker.finish(snapshot.get("cleared", false), str(snapshot.get("death_reason", "")), snapshot.get("test_mode", false))
	run_finished.emit(result)

func _toggle_test_panel() -> void:
	if not OS.is_debug_build() or not is_instance_valid(_test_panel) or is_instance_valid(_chat): return
	_test_panel.configure(not _test_panel.visible)
	_fit_test_panel()

func _fit_test_panel() -> void:
	if not is_instance_valid(_test_panel): return
	var viewport_size := get_viewport().get_visible_rect().size
	_test_panel.size = Vector2(minf(460.0, viewport_size.x - 32.0), maxf(160.0, minf(680.0, viewport_size.y - 126.0)))

func _debug_command(command: String, value: Variant) -> void:
	if not OS.is_debug_build() or not _stage.has_method("service_debug_command"): return
	_stage.set("service_debug_enabled", true)
	if _stage.service_debug_command(command, value): _test_mark.visible = true

func _audio_node_added(node: Node) -> void:
	if is_instance_valid(_stage) and _stage.is_ancestor_of(node): _apply_audio(node)

func _apply_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is AudioStreamPlayer2D:
		if not node.has_meta("service_base_db"): node.set_meta("service_base_db", node.volume_db)
		var stream_path: String = node.stream.resource_path.to_lower() if node.stream != null else ""
		var key := "bgm_volume" if "bgm" in stream_path or "music" in String(node.name).to_lower() or node.bus == "BGM" else "sfx_volume"
		var multiplier := float(_values.get(key, 1.0))
		node.volume_db = float(node.get_meta("service_base_db")) + linear_to_db(maxf(multiplier, 0.0001))
	for child in node.get_children(): _apply_audio(child)

func _exit_tree() -> void:
	if get_tree().paused:
		get_tree().paused = false

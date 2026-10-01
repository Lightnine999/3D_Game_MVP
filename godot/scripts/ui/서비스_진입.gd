extends Control

const SPLASH_SECONDS := 3.0
const AUTH_SCREEN := preload("res://scenes/ui/인증_화면.tscn")
const TITLE_SCREEN := preload("res://scenes/ui/서비스_타이틀.tscn")
const ACCOUNT_SCREEN := preload("res://scenes/ui/계정_화면.tscn")
const SUPPORT_SCREEN := preload("res://scenes/ui/문의_화면.tscn")
const SHOP_SCREEN := preload("res://scenes/ui/상점_화면.tscn")
const OUTBOX_SCRIPT := preload("res://scripts/services/서비스_발신함.gd")
const PAYMENT_SCRIPT := preload("res://scripts/services/서비스_결제.gd")
const PUBLIC_CONFIG := "res://config/서비스_공개설정.json"
const GAME_SHELL := "res://scenes/ui/서비스_게임_셸.tscn"
const SYNC_RETRY_SECONDS := 20.0

var outbox_storage_path_override := "" # Isolated path for local tests only.
var auth_override: ServiceAuth # Test-only injected transport; unset in the app.
var _auth: ServiceAuth
var _api: ServiceAPI
var _outbox: Node
var _payment: Node
var _support_multiturn_enabled := false
var _package_catalog_ready := false
var _outbox_ready := false
var _sync_active := false
var _screen: Control
var progress_storage_path_override := ""
var settings_storage_path_override := ""
var skip_splash_for_tests := false
var offline_test_mode := false
var _progress = preload("res://scripts/services/게임_진행_기록.gd").new()
var _settings = preload("res://scripts/services/게임_설정.gd").new()
var _game: Node3D
var _last_run: Dictionary = {}
var _last_run_owner := ""
const FLOW_SCREEN = preload("res://scripts/ui/게임_흐름_화면.gd")
const SETTINGS_SCREEN = preload("res://scripts/ui/게임_설정_화면.gd")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_auth = auth_override if auth_override != null else ServiceAuth.new()
	add_child(_auth)
	_api = ServiceAPI.new()
	add_child(_api)
	_outbox = OUTBOX_SCRIPT.new()
	if not outbox_storage_path_override.is_empty():
		_outbox.storage_path = outbox_storage_path_override
	add_child(_outbox)
	_outbox_ready = _outbox.load_queue()
	_payment = PAYMENT_SCRIPT.new()
	add_child(_payment)
	var retry_timer := Timer.new()
	retry_timer.wait_time = SYNC_RETRY_SECONDS
	retry_timer.timeout.connect(_sync_pending)
	add_child(retry_timer)
	retry_timer.start()
	offline_test_mode = offline_test_mode or "--offline-test" in OS.get_cmdline_user_args() or OS.has_feature("human_test")
	if not progress_storage_path_override.is_empty(): _progress.storage_path = progress_storage_path_override
	if not settings_storage_path_override.is_empty(): _settings.storage_path = settings_storage_path_override
	_progress.load_store()
	_settings.load_settings()
	if not offline_test_mode: _load_public_config()
	if skip_splash_for_tests:
		_show_auth()
		return
	_show_splash()
	await get_tree().create_timer(SPLASH_SECONDS).timeout
	if not is_inside_tree():
		return
	if _auth.restore_local_session():
		_show_title()
	else:
		_show_auth()


func _load_public_config() -> void:
	if not FileAccess.file_exists(PUBLIC_CONFIG):
		return
	var file := FileAccess.open(PUBLIC_CONFIG, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var url := str(parsed.get("supabase_url", ""))
		var key := str(parsed.get("supabase_publishable_key", ""))
		_auth.set_public_config(url, key)
		_api.configure(_auth, url, key)
		_payment.configure(_auth, _api, str(parsed.get("toss_test_client_key", "")))
		_support_multiturn_enabled = parsed.get("support_multiturn_enabled", false) == true
		var version: Variant = parsed.get("package_catalog_version")
		_package_catalog_ready = parsed.get("package_catalog_ready", false) == true and typeof(version) in [TYPE_INT, TYPE_FLOAT] and version == 2
		_payment.set_catalog_version(2 if _package_catalog_ready else 0)


func _replace_screen(next_screen: Control) -> void:
	if is_instance_valid(_screen):
		_screen.queue_free()
	_screen = next_screen
	add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _show_splash() -> void:
	var splash := Control.new()
	splash.name = "SplashScreen"
	var background := ColorRect.new()
	background.color = Color("0d1114")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash.add_child(center)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 24)
	center.add_child(stack)
	var logo := TextureRect.new()
	logo.name = "SplashLogo"
	logo.texture = preload("res://assets/ui/좀비탈출_로고.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(1000, 300)
	stack.add_child(logo)
	var subtitle := Label.new()
	subtitle.name = "SplashEnglishTitle"
	subtitle.text = "ZOMBIE ESCAPE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("d6c7bc"))
	subtitle.add_theme_font_size_override("font_size", 30)
	stack.add_child(subtitle)
	_replace_screen(splash)


func _show_auth(account_mode: bool = false) -> void:
	var screen := AUTH_SCREEN.instantiate() as Control
	screen.setup(_auth, account_mode)
	screen.authenticated.connect(_show_title)
	screen.back_requested.connect(_show_title)
	_replace_screen(screen)
	if offline_test_mode: screen.call("_set_status", "오프라인 사람 테스트 · 서버 연결 안 함 · 게스트로 시작해 주세요.")


func _show_title() -> void:
	var screen := TITLE_SCREEN.instantiate() as Control
	screen.setup(_auth)
	screen.play_requested.connect(_show_stage_card)
	screen.settings_requested.connect(_show_settings)
	screen.account_requested.connect(_show_account)
	screen.support_requested.connect(_show_support)
	screen.shop_requested.connect(_show_shop)
	_replace_screen(screen)
	if offline_test_mode:
		screen.show_service_notice("오프라인 사람 테스트 · 서버 연결 안 함")
	if not _outbox_ready:
		screen.show_service_notice("로컬 기록을 읽을 수 없어 동기화를 멈췄습니다. 기록 파일을 보존하고 확인해 주세요.")
	if not offline_test_mode and _auth.has_remote_session():
		_ensure_profile()
	_sync_pending()

func _sync_pending() -> void:
	if offline_test_mode or not _outbox_ready or _sync_active:
		return
	_sync_active = true
	if _auth.is_guest() and not _auth.has_remote_session() and _auth.is_configured():
		var signed_in: Dictionary = await _auth.sign_in_anonymous()
		if not signed_in.get("ok", false):
			_sync_active = false
			return
		await _ensure_profile()
	if not _auth.has_remote_session():
		_sync_active = false
		return
	if not _auth.pending_offline_guest_id().is_empty():
		var adoption: Dictionary = _outbox.adopt_offline_guest(_auth)
		if not adoption.get("ok", false):
			_sync_active = false
			return # Preserve the marker and queue for the next safe retry.
		var progress_adoption: Dictionary = _progress.adopt_owner(_auth.pending_offline_guest_id(), _auth.get_user_id())
		if not progress_adoption.get("ok", false):
			_sync_active = false
			return
		_auth.acknowledge_offline_adoption()
	while _auth.has_remote_session() and not _outbox.pending_for(_auth.get_user_id()).is_empty():
		var outcome: Dictionary = await _outbox.flush_for(_auth, _api)
		if not outcome.get("ok", false):
			break # No ACK: keep exactly the same IDs for the next connection.
	_sync_active = false


func _ensure_profile() -> void:
	var result: Dictionary = await _api.post_function("ensure-profile", {})
	if not result.get("ok", false) and is_instance_valid(_screen) and _screen.has_method("show_service_notice"):
		_screen.show_service_notice("계정 정보를 확인하지 못했습니다. 인터넷 연결을 확인해 주세요.")


func _show_account() -> void:
	var screen := ACCOUNT_SCREEN.instantiate() as Control
	screen.setup(_auth, _api)
	screen.back_requested.connect(_show_title)
	screen.signed_out.connect(_show_auth)
	screen.email_link_requested.connect(_show_signup_from_account)
	screen.account_deleted.connect(_clear_owner)
	_replace_screen(screen)


func _show_signup_from_account() -> void:
	_show_auth()
	_screen.call("_set_mode", "signup")


func _current_last_run() -> Dictionary:
	var owner := _auth.get_user_id()
	if owner != _last_run_owner or owner.is_empty():
		_last_run_owner = owner
		_last_run = {} if owner.is_empty() else _progress.snapshot(owner).get("last_run", {}).duplicate(true)
	return _last_run.duplicate(true)


func _show_support() -> void:
	var screen := SUPPORT_SCREEN.instantiate() as Control
	screen.setup(_auth, _api, _support_multiturn_enabled, _current_last_run())
	screen.back_requested.connect(_show_title)
	_replace_screen(screen)


func _show_shop() -> void:
	var screen := SHOP_SCREEN.instantiate() as Control
	screen.setup(_auth, _api, _payment)
	if screen.has_method("set_catalog_ready"):
		screen.set_catalog_ready(_package_catalog_ready)
	screen.back_requested.connect(_show_title)
	_replace_screen(screen)


func _enter_stage() -> void:
	_show_stage_card()

func _show_stage_card() -> void:
	var screen = FLOW_SCREEN.new()
	var data: Dictionary = _progress.snapshot(_auth.get_user_id())
	data["target_distance"] = StageBuilderV2.STAGE_LENGTH
	_current_last_run()
	screen.configure("stage", data)
	screen.play_requested.connect(_prepare_run)
	screen.back_requested.connect(_show_title)
	_replace_screen(screen)

func _prepare_run() -> void:
	if _progress.snapshot(_auth.get_user_id()).get("tutorial_seen", false):
		_start_run()
		return
	var screen = FLOW_SCREEN.new()
	screen.configure("tutorial")
	screen.tutorial_finished.connect(func():
		_progress.mark_tutorial_seen(_auth.get_user_id())
		_settings.set_tutorial_seen(true))
	screen.play_requested.connect(_start_run)
	screen.back_requested.connect(_show_stage_card)
	_replace_screen(screen)

func _show_settings() -> void:
	var screen = SETTINGS_SCREEN.new()
	screen.configure(_settings.values(), OS.get_name() == "Android")
	screen.saved.connect(func(values: Dictionary):
		if _settings.save_settings(values): _show_title())
	screen.calibrate_requested.connect(func():
		if OS.get_name() == "Android":
			screen._values.tilt_zero = Input.get_accelerometer().x)
	screen.back_requested.connect(_show_title)
	_replace_screen(screen)

func _start_run() -> void:
	if is_instance_valid(_game): return
	if is_instance_valid(_screen):
		_screen.queue_free()
		_screen = null
	_game = load(GAME_SHELL).instantiate()
	_game.configure(_auth, _api, _settings.values(), _support_multiturn_enabled)
	_game.run_finished.connect(_finish_run)
	_game.title_requested.connect(_leave_game)
	add_child(_game)

func _leave_game() -> void:
	get_tree().paused = false
	if is_instance_valid(_game):
		_game.queue_free()
	_game = null
	_show_title()

func _finish_run(result: Dictionary) -> void:
	_last_run_owner = _auth.get_user_id()
	_last_run = result.duplicate(true)
	var saved: Dictionary = {"ok": true}
	var queued := true
	if not result.get("test_mode", false):
		saved = _progress.record_run(_auth.get_user_id(), result)
		var payload := {"stage_id": result.stage_id, "distance_m": result.distance_m}
		queued = _outbox.queue_event_once(_auth.get_user_id(), result.run_id + "_distance", "distance", payload).get("ok", false)
		for mission in result.mission_ids:
			var event: Dictionary = _outbox.queue_event_once(_auth.get_user_id(), result.run_id + "_" + mission, "mission", {"stage_id": result.stage_id, "mission_id": mission})
			queued = queued and event.get("ok", false)
	_last_run["save_status"] = "TEST MODE · 일반 기록 제외" if result.get("test_mode", false) else ("단말 자동 저장 · 서버 전송 대기" if saved.get("ok", false) and queued else "저장 또는 전송 대기열 오류 · 기록 확인 필요")
	if is_instance_valid(_game):
		_game.queue_free()
	_game = null
	get_tree().paused = false
	_show_result()
	_sync_pending()

func _show_result() -> void:
	var screen = FLOW_SCREEN.new()
	screen.configure("result", _current_last_run())
	screen.retry_requested.connect(_start_run)
	screen.back_requested.connect(_show_title)
	screen.support_requested.connect(_show_result_support)
	_replace_screen(screen)

func _show_result_support() -> void:
	var screen := SUPPORT_SCREEN.instantiate() as Control
	screen.setup(_auth, _api, _support_multiturn_enabled, _current_last_run())
	screen.back_requested.connect(_show_result)
	_replace_screen(screen)

func _clear_owner(owner_id: String) -> void:
	_progress.clear_owner(owner_id)
	_outbox.clear_owner(owner_id)
	if _last_run_owner == owner_id:
		_last_run = {}
		_last_run_owner = ""

extends SceneTree
# Headless: committed Unicode events only, NOT Microsoft Korean IME verification.
# Optional user-run -- --native-probe: compare plain TextEdit with the actual
# offline support screen. Never sends requests, loads a session, or changes IME.

const SUPPORT = preload("res://scenes/ui/문의_화면.tscn")
const SAMPLE := "가나다라마바사아자차카타파하"
var failures := 0
var field: TextEdit
var plain: TextEdit
var native_probe := false

class OfflineAuth extends ServiceAuth:
	func has_remote_session() -> bool:
		return false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	native_probe = "--native-probe" in OS.get_cmdline_user_args()
	print("ENGINE: ", Engine.get_version_info().string, " DISPLAY: ", DisplayServer.get_name())
	var auth := OfflineAuth.new()
	root.add_child(auth)
	var screen := SUPPORT.instantiate()
	if not screen.has_method("setup"):
		printerr("SUPPORT_COMMITTED_UNICODE: BLOCKED (support script dependency did not load)")
		screen.free()
		auth.queue_free()
		quit(2)
		return
	# No ServiceAPI exists: an unintended send cannot reach the network.
	screen.setup(auth, null)
	root.add_child(screen)
	await process_frame
	field = screen.find_child("MessageField", true, false) as TextEdit
	var properties: Array[String] = []
	for property in field.get_property_list():
		if "ime" in str(property.name):
			properties.append(str(property.name))
	print("TextEdit IME-named properties: ", properties)
	if native_probe:
		if DisplayServer.get_name() == "headless":
			printerr("NATIVE_PROBE: requires a user-started graphical run; not verified")
			quit(2)
			return
		_build_native_probe()
		return
	field.grab_focus() # Headless Control focus only, never OS foreground focus.
	await process_frame
	for i in SAMPLE.length():
		_key(KEY_NONE, SAMPLE.unicode_at(i))
		_check(field.text == SAMPLE.substr(0, i + 1), "committed syllable %d accumulates without Space" % i)
	_key(KEY_BACKSPACE)
	_check(field.text == SAMPLE.substr(0, SAMPLE.length() - 1), "Backspace removes one committed syllable")
	var before := field.text
	_key(KEY_ENTER)
	_check(field.text == before, "offline Enter keeps draft; no send/clear")
	_key(KEY_ENTER, 0, true)
	_check(field.text == before + "\n", "Shift+Enter remains newline")
	_check(field.editable, "offline draft stays editable")
	print("SUPPORT_COMMITTED_UNICODE: ", "PASS" if failures == 0 else "FAIL", "; failures=", failures)
	print("NATIVE_KOREAN_IME: NOT_TESTED (no WM_IME composition/commit events in headless)")
	screen.queue_free()
	auth.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _key(code: Key, unicode_value: int = 0, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode_value
	event.shift_pressed = shift
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label, " actual=", JSON.stringify(field.text))
	else:
		print("PASS: ", label)

func _build_native_probe() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 20)
	box.size = Vector2(480, 400)
	root.add_child(box)
	var instructions := Label.new()
	instructions.text = "수동 IME 비교 (계정·네트워크 없음)\n왼쪽: 기본 TextEdit / 오른쪽: 실제 문의 화면\n각 칸에 붙여넣기 없이 '가나다라마바사' 연속 입력.\n음절 사이 Space/Enter 금지. 마지막에 방향키로 확정.\n기본도 실패: 엔진/Windows IME 경로 의심.\n문의만 실패: 문의 UI 경로 조사.\n실제 게임에서만 실패: 셸·실행 빌드 비교 필요.\n콘솔은 길이/캐럿/조합 상태만 기록합니다."
	box.add_child(instructions)
	plain = TextEdit.new()
	plain.custom_minimum_size = Vector2(460, 140)
	box.add_child(plain)
	for editor in [plain, field]:
		var tag := "plain" if editor == plain else "support"
		editor.text_changed.connect(func() -> void: _trace(tag, editor))
		editor.focus_entered.connect(func() -> void: print("FOCUS_ENTER ", tag))
		editor.focus_exited.connect(func() -> void: print("FOCUS_EXIT ", tag))
	print("NATIVE_PROBE: waiting for human typing; NO automatic native-pass assertion")

func _trace(tag: String, editor: TextEdit) -> void:
	print("COMMITTED ", tag, " length=", editor.text.length(), " caret=", editor.get_caret_column(), " composing=", editor.has_ime_text())

extends SceneTree

const SHELL_SCENE := "res://scenes/ui/서비스_게임_셸.tscn"
var _session_path := "user://service_pause_test_%d.json" % Time.get_ticks_usec()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists(SHELL_SCENE):
		printerr("FAIL: 서비스 게임 셸 미구현")
		quit(1)
		return
	var shell := load(SHELL_SCENE).instantiate() as Node3D
	shell.set("stage_override", Node3D.new())
	shell.set("auth_session_path_override", _session_path)
	root.add_child(shell)
	await process_frame
	var support := shell.find_child("PauseSupportButton", true, false) as Button
	if support == null:
		printerr("FAIL: ESC 일시정지용 문의 버튼 없음")
		shell.queue_free(); await process_frame; quit(1); return
	var ok := not support.visible and support.anchor_left == 1.0 and support.anchor_top == 1.0 and support.offset_right < 0 and support.offset_bottom < 0
	paused = true
	shell.call("_update_pause_ui")
	ok = ok and support.visible
	support.emit_signal("pressed")
	await process_frame
	var chat := shell.find_child("SupportScreen", true, false)
	ok = ok and chat != null and paused and not support.visible
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	shell.call("_input", escape)
	await process_frame
	ok = ok and shell.find_child("SupportScreen", true, false) == null and paused and support.visible
	paused = false
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_session_path))
	print("SERVICE_PAUSE_SUPPORT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

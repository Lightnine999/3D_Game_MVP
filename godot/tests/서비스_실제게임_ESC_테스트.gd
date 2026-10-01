extends SceneTree

const GAME_SHELL := preload("res://scenes/ui/서비스_게임_셸.tscn")
var _session_path := "user://service_real_stage_test_%d.json" % Time.get_ticks_usec()


func _initialize() -> void:
	call_deferred("_run")


func _escape() -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(event)


func _wait_for_state(button: Button, expected_pause: bool, expected_visibility: bool) -> void:
	for _attempt in range(8):
		if paused == expected_pause and button.visible == expected_visibility:
			return
		await process_frame


func _wait_for_chat_closed(shell: Node3D, button: Button) -> void:
	for _attempt in range(8):
		if shell.find_child("SupportScreen", true, false) == null and paused and button.visible:
			return
		await process_frame


func _run() -> void:
	var shell := GAME_SHELL.instantiate() as Node3D
	shell.set("auth_session_path_override", _session_path)
	root.add_child(shell)
	await process_frame
	var stage := shell.find_child("StagePreview", true, false)
	var support := shell.find_child("PauseSupportButton", true, false) as Button
	var ok: bool = stage != null and support != null and not paused
	var checks: Array[Dictionary] = [{"point": "initial", "paused": paused, "visible": support.visible}]
	_escape()
	await _wait_for_state(support, true, true)
	checks.append({"point": "first_escape", "paused": paused, "visible": support.visible})
	ok = ok and paused and support.visible
	if paused:
		support.emit_signal("pressed")
		await process_frame
		checks.append({"point": "open", "paused": paused, "chat": shell.find_child("SupportScreen", true, false) != null, "visible": support.visible})
		ok = ok and shell.find_child("SupportScreen", true, false) != null and paused
		var p_key := InputEventKey.new()
		p_key.pressed = true
		p_key.keycode = KEY_P
		p_key.physical_keycode = KEY_P
		Input.parse_input_event(p_key)
		await process_frame
		ok = ok and paused and not stage.is_processing_unhandled_input()
		var editor := shell.find_child("SupportInput", true, false) as TextEdit
		if editor == null:
			for node in shell.find_children("*", "TextEdit", true, false):
				editor = node
				break
		if editor != null:
			editor.grab_focus()
			p_key.unicode = 112
			Input.parse_input_event(p_key)
			await process_frame
			ok = ok and editor.text.contains("p") and paused
		_escape()
		await _wait_for_chat_closed(shell, support)
		checks.append({"point": "chat_escape", "paused": paused, "chat": shell.find_child("SupportScreen", true, false) != null, "visible": support.visible})
		ok = ok and shell.find_child("SupportScreen", true, false) == null and paused and support.visible
		_escape()
		await _wait_for_state(support, false, false)
		checks.append({"point": "last_escape", "paused": paused, "visible": support.visible})
		ok = ok and not paused and not support.visible
	paused = false
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_session_path))
	if not ok:
		printerr("REAL_STAGE_ESC_CHECKPOINTS: ", checks)
	print("SERVICE_REAL_STAGE_ESC: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

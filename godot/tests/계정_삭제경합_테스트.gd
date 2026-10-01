extends SceneTree

const SCREEN := preload("res://scripts/ui/계정_화면.gd")
var failures := 0

class FakeAuth extends ServiceAuth:
	var owner_id := "owner_id-a"
	var logout_calls := 0
	var remote := true
	func _init() -> void:
		session_path = "user://account_delete_race_unused_%d.json" % Time.get_ticks_usec()
	func get_user_id() -> String:
		return owner_id
	func has_remote_session() -> bool:
		return remote
	func is_guest() -> bool:
		return true
	func display_name() -> String:
		return "test guest"
	func sign_out() -> bool:
		logout_calls += 1
		owner_id = ""
		return true

class FakeAPI extends ServiceAPI:
	signal completed(result: Dictionary)
	var delete_calls := 0
	func post_function(function: String, _payload: Dictionary) -> Dictionary:
		if function != "delete-account":
			return {"ok": true}
		delete_calls += 1
		return await completed
	func fetch_profile() -> Dictionary:
		return {"ok": true, "profile": {"nickname": "tester"}}

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _run() -> void:
	var auth := FakeAuth.new()
	var api := FakeAPI.new()
	var screen := SCREEN.new()
	screen.setup(auth, api)
	root.add_child(screen)
	var events: Array[String] = []
	screen.back_requested.connect(func(): events.append("back"))
	screen.email_link_requested.connect(func(): events.append("link"))
	screen.signed_out.connect(func(): events.append("out"))
	screen.account_deleted.connect(func(owner_id: String): events.append("deleted:" + owner_id))
	screen.call("_delete_account")
	check(api.delete_calls == 1 and screen.get("_busy"), "delete starts exactly once")
	for button in screen.find_children("*", "Button", true, false):
		check(button.disabled, "busy disables " + button.text)
		button.pressed.emit()
	screen.call("_confirm_logout")
	screen.call("_confirm_delete")
	screen.call("_logout")
	screen.call("_request_back")
	screen.call("_request_email_link")
	screen.call("_delete_account")
	check(events.is_empty() and auth.logout_calls == 0, "busy direct callbacks cannot navigate or sign out")
	check(api.delete_calls == 1, "busy duplicate delete is ignored")
	check(not screen.get("_logout_dialog").visible and not screen.get("_delete_dialog").visible, "busy confirmation callbacks ignored")
	api.completed.emit({"ok": false})
	check(not screen.get("_busy"), "failed delete releases busy")
	check(screen.get("_nickname").editable, "failed delete restores editing")
	for button in screen.find_children("*", "Button", true, false):
		check(not button.disabled, "failed delete restores buttons")
	events.clear()
	screen.call("_delete_account")
	auth.owner_id = "owner_id-b"
	api.completed.emit({"ok": true, "data": {"status": "deleted"}})
	check(events.is_empty() and auth.logout_calls == 0 and auth.owner_id == "owner_id-b", "late old-owner delete cannot clear or logout replacement account")
	check(not screen.get("_busy"), "owner mismatch releases busy")
	auth.owner_id = "owner_id-a"
	screen.call("_delete_account")
	api.completed.emit({"ok": true, "data": {"status": "pending"}})
	check(events.is_empty() and auth.logout_calls == 0, "unconfirmed response preserves account")
	screen.call("_delete_account")
	api.completed.emit({"ok": true, "data": {"status": "deleted"}})
	check(events == ["deleted:owner_id-a", "out"] and auth.logout_calls == 1, "confirmed deletion emits captured owner before logout")
	screen.call("_delete_account")
	screen.call("_logout")
	check(auth.logout_calls == 1, "successful delete stays terminal against repeated callbacks")
	screen.free()
	auth.free()
	api.free()
	_test_signal_identity_replacement()
	_test_offline_delete()
	print("ACCOUNT_DELETE_RACE_TESTS: %s" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	quit(0 if failures == 0 else 1)

func _test_signal_identity_replacement() -> void:
	var auth := FakeAuth.new()
	var api := FakeAPI.new()
	var screen := SCREEN.new()
	screen.setup(auth, api)
	root.add_child(screen)
	var deleted: Array[String] = []
	screen.account_deleted.connect(func(owner_id: String):
		deleted.append(owner_id)
		screen.call("_logout")
		screen.call("_delete_account")
		auth.owner_id = "replacement"
	)
	screen.call("_delete_account")
	api.completed.emit({"ok": true, "data": {"status": "deleted"}})
	check(deleted == ["owner_id-a"] and api.delete_calls == 1, "deletion signal reentry remains locked")
	check(auth.owner_id == "replacement" and auth.logout_calls == 0, "signal handler replacement is never signed out")
	screen.free()
	auth.free()
	api.free()

func _test_offline_delete() -> void:
	var auth := FakeAuth.new()
	auth.remote = false
	var api := FakeAPI.new()
	var screen := SCREEN.new()
	screen.setup(auth, api)
	root.add_child(screen)
	var events: Array[String] = []
	screen.account_deleted.connect(func(owner_id: String):
		events.append(owner_id)
		check(auth.get_user_id() == owner_id, "offline deletion signal precedes logout")
		screen.call("_delete_account")
	)
	screen.call("_delete_account")
	check(events == ["owner_id-a"] and auth.logout_calls == 1 and api.delete_calls == 0, "offline deletion is local, single-shot and reentry-safe")
	screen.free()
	auth.free()
	api.free()

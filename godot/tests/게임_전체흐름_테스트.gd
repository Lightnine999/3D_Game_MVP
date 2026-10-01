extends SceneTree
var failures := 0
var prefix := "user://full_flow_%d" % Time.get_ticks_usec()
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok: failures += 1
func _run() -> void:
	var entry: Node = load("res://scenes/ui/서비스_진입.tscn").instantiate()
	var auth := ServiceAuth.new()
	auth.session_path = prefix + "_auth.json"
	entry.auth_override = auth
	entry.outbox_storage_path_override = prefix + "_queue.json"
	entry.progress_storage_path_override = prefix + "_progress.json"
	entry.settings_storage_path_override = prefix + "_settings.cfg"
	entry.offline_test_mode = true
	entry.skip_splash_for_tests = true
	root.add_child(entry)
	entry._screen._on_guest()
	check(auth.is_guest() and auth.get_user_id().begins_with("local-"), "real guest button creates only local identity")
	check(not auth.is_configured(), "offline human test cannot reach Cloud")
	entry._screen.play_requested.emit()
	check(entry._screen.name == "StageCardScreen", "title to stage card")
	entry._screen.play_requested.emit()
	check(entry._screen.name == "TutorialScreen", "first run tutorial")
	entry._settings.save_settings({"sfx_volume": 0.5, "bgm_volume": 0.25})
	entry._screen._finish_tutorial()
	await process_frame
	var shell: Node = entry._game
	if shell == null or not shell.has_signal("run_finished"):
		check(false, "persistent shell with actual stage")
	else:
		check(shell._auth == auth and is_instance_valid(entry._outbox), "same auth/outbox retained during gameplay")
		var stage: Node = shell.get("_stage")
		check(stage != null and stage.service_managed, "actual service managed stage")
		stage.set_process(false)
		var sound := AudioStreamPlayer.new()
		sound.volume_db = -6.0
		stage.add_child(sound)
		await process_frame
		check(is_equal_approx(sound.volume_db, -6.0 + linear_to_db(0.5)), "new sound preserves base dB and settings multiplier")
		stage._dist = 750.0
		stage._body.position.z = -750.0
		stage._process(0.0)
		await process_frame
		check(entry._screen.name == "ResultScreen" and entry._last_run.cleared, "real 750m stage completion to result")
		check(entry._progress.snapshot(auth.get_user_id()).runs_count == 1, "automatic local record without ACK")
		check(entry._outbox.pending_for(auth.get_user_id()).size() >= 2, "stable distance and mission queued")
		check(entry._outbox.pending_for(auth.get_user_id())[0].payload.get("distance_m") == 750.0, "distance uses backend restore contract distance_m")
		var restored = load("res://scripts/services/게임_진행_기록.gd").new()
		restored.storage_path = prefix + "_progress.json"
		check(restored.load_store() and restored.snapshot(auth.get_user_id()).best_distance_m == 750.0, "prior record reloads from actual disk")
		entry._screen.support_requested.emit()
		check(entry._screen.get("_last_run").get("distance_m") == 750.0, "result support receives snapshot")
		entry._screen.back_requested.emit()
		entry._screen.retry_requested.emit()
		await process_frame
		shell = entry._game
		stage = shell._stage
		stage.set_process(false)
		shell._toggle_test_panel()
		await process_frame
		check(shell._test_panel.size.y >= 250, "test panel has an actual visible scroll viewport")
		shell._debug_command("invulnerable", true)
		stage._dist = 750.0
		stage._body.position.z = -750.0
		stage._process(0.0)
		await process_frame
		check(entry._last_run.test_mode and entry._progress.snapshot(auth.get_user_id()).runs_count == 1, "test commands never accrue normal records")
		entry._screen.back_requested.emit()
		entry._show_support()
		check(entry._screen.get("_last_run").get("test_mode", false), "same owner title support retains latest test result")
		var owner_a := auth.get_user_id()
		auth.sign_out()
		entry._show_support()
		check(entry._screen.get("_last_run").is_empty(), "empty owner never receives previous run attachment")
		auth.start_offline_guest()
		entry._show_title()
		entry._show_support()
		check(entry._screen.get("_last_run").is_empty(), "new owner title support never attaches previous owner run")
		entry._show_result_support()
		check(entry._screen.get("_last_run").is_empty(), "new owner result support never attaches previous owner run")
		entry._show_result()
		check(entry._screen._data.is_empty(), "new owner result never displays previous owner run")
		auth._user_id = owner_a
		entry._show_support()
		check(entry._screen.get("_last_run").get("distance_m") == 750.0, "returning owner loads own durable progress without stage card")
		entry._show_stage_card()
		check(entry._screen._data.best_distance_m == 750.0, "stage card displays saved prior record")
		entry._screen.play_requested.emit()
		await process_frame
		check(entry._game != null, "second attempt bypasses tutorial")
		stage = entry._game._stage
		stage.set_process(false)
		stage._dead = true
		stage._dead_t = 4.0
		stage._process(0.0)
		await process_frame
		check(entry._screen.name == "ResultScreen" and not entry._last_run.cleared, "real death path to result")
		check(entry._progress.snapshot(auth.get_user_id()).runs_count == 2, "death saves once")
		entry._show_settings()
		check(entry._screen.find_child("TiltAvailability", true, false).text.contains("PC"), "PC tilt explicitly unavailable")
		entry._screen.saved.emit({"sensitivity": 1.5})
		check(entry._settings.values().sensitivity == 1.5, "settings save persisted")
		entry._show_account()
		entry._screen.account_deleted.emit(auth.get_user_id())
		check(entry._progress.snapshot(auth.get_user_id()).runs_count == 0 and entry._outbox.pending_for(auth.get_user_id()).is_empty(), "account deletion clears owner local progress and queue")
	entry.queue_free()
	await process_frame
	for suffix in ["_auth.json", "_queue.json", "_progress.json", "_settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefix + suffix))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefix + suffix + ".tmp"))
	print("FULL_GAME_FLOW: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

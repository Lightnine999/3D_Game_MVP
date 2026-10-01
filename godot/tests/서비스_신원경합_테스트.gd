extends SceneTree

class DelayedAuth extends "res://scripts/services/서비스_인증.gd":
	signal release
	var reply: Dictionary
	func _transport(_method: String, _path: String, _body: Dictionary, _bearer: String = "") -> Dictionary:
		await release
		return {"ok": true, "data": reply}

var failures := 0
var result: Dictionary = {}
var path := "user://identity_race_%d.json" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func session(id: String) -> Dictionary:
	return {"access_token": "test-access", "refresh_token": "test-refresh", "expires_in": 3600, "user": {"id": id, "is_anonymous": true}}

func refresh(auth: ServiceAuth) -> void:
	result = await auth.access_token_for_request()

func login_anonymous(auth: ServiceAuth) -> void:
	result = await auth.sign_in_anonymous()

func login_password(auth: ServiceAuth) -> void:
	result = await auth.sign_in_password("test@example.test", "password123")

func _run() -> void:
	var auth := DelayedAuth.new()
	auth.session_path = path
	auth.set_public_config("https://example.test", "public-test")
	check(auth._accept_session(session("owner-A"), ""), "seed isolated session")
	auth._expires_at = 1
	auth.reply = session("owner-A")
	refresh(auth)
	auth.sign_out()
	auth.release.emit()
	check(not result.get("ok", false) and not auth.is_logged_in(), "late refresh must not resurrect logout")
	check(not FileAccess.file_exists(path), "late refresh must not recreate logout file")
	login_password(auth)
	auth.sign_out()
	auth.release.emit()
	check(result.get("error") == "identity_changed" and not auth.is_logged_in(), "late password login cancelled by logout")
	login_anonymous(auth)
	auth.start_offline_guest()
	var race_guest := auth.get_user_id()
	auth.release.emit()
	check(result.get("error") == "identity_changed" and auth.get_user_id() == race_guest, "late anonymous login cannot replace new local guest")
	auth.sign_out()
	check(auth._accept_session(session("owner-A"), ""), "seed next race")
	auth._expires_at = 1
	refresh(auth)
	auth.sign_out()
	check(auth._accept_session(session("owner-B"), ""), "switch account")
	auth.release.emit()
	check(not result.get("ok", false) and auth.get_user_id() == "owner-B", "old refresh cannot replace new account")
	auth.sign_out()
	auth.start_offline_guest()
	var local_id := auth.get_user_id()
	var before := FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	auth.reply = session("remote-durable")
	login_anonymous(auth)
	auth.release.emit()
	check(result.get("error") == "storage_unavailable", "anonymous login reports durable save failure")
	check(auth.get_user_id() == local_id and not auth.has_remote_session(), "failed save preserves old identity")
	check(FileAccess.get_file_as_string(path) == before, "failed save preserves original bytes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	login_anonymous(auth)
	auth.release.emit()
	check(result.get("ok", false) and auth.pending_offline_guest_id() == local_id, "durable login carries adoption marker")
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	auth.acknowledge_offline_adoption()
	check(auth.pending_offline_guest_id() == local_id, "failed adoption ACK save retains marker")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	var locked := FileAccess.open(path, FileAccess.READ)
	var old_remote := auth.get_user_id()
	check(not auth.start_offline_guest() and auth.get_user_id() == old_remote, "offline guest refuses implicit remote identity replacement")
	check(not auth._accept_session(session("cannot-replace"), ""), "locked destination rejects atomic replacement")
	check(auth.get_user_id() == old_remote and auth.pending_offline_guest_id() == local_id, "rename failure restores session and marker")
	check(JSON.parse_string(locked.get_as_text()).get("user_id") == old_remote, "rename failure preserves original session file")
	check(not auth.sign_out(), "locked logout explicitly returns false")
	check(auth.has_remote_session(), "failed logout deletion preserves matching memory and file")
	locked.close()
	check(auth.sign_out(), "unlocked logout explicitly returns true")
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	check(not auth.start_offline_guest(), "blocked guest save explicitly returns false")
	check(not auth.is_logged_in() and not FileAccess.file_exists(path), "offline identity needs durable save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	var login := load("res://scenes/ui/인증_화면.tscn").instantiate() as Control
	login.setup(auth)
	root.add_child(login)
	var entered: Array[String] = []
	login.authenticated.connect(func(): entered.append(auth.get_user_id()))
	login.call("_on_guest")
	auth.sign_out()
	check(auth._accept_session(session("replacement-owner"), ""), "seed identity while guest network request waits")
	auth.release.emit()
	check(entered.is_empty() and auth.get_user_id() == "replacement-owner", "late guest UI response cannot navigate or replace switched identity")
	login.free()
	auth.sign_out()
	auth.free()
	var queue := ServiceOutbox.new()
	queue.storage_path = path + ".queue"
	check(queue.load_queue(), "isolated queue")
	check(queue.queue_event("owner-A", "distance", {"distance_m": 1}, "same-id").get("ok", false), "first event")
	check(queue.queue_event("owner-A", "distance", {"distance_m": 1}, "same-id").get("ok", false) and queue.pending_for("owner-A").size() == 1, "same ID same payload idempotent")
	check(queue.queue_event("owner-A", "distance", {"distance_m": 2}, "same-id").get("error") == "conflicting_event", "same ID changed payload rejected")
	var corrupt := JSON.stringify({"version": 1, "entries": [{"owner_id": "owner-A", "event": {"id": "dup", "kind": "distance", "payload": {"distance_m": 1}}}, {"owner_id": "owner-A", "event": {"id": "dup", "kind": "distance", "payload": {"distance_m": 2}}}]})
	var file := FileAccess.open(queue.storage_path, FileAccess.WRITE)
	file.store_string(corrupt)
	file.close()
	check(not queue.load_queue(), "conflicting IDs rejected on load")
	check(not queue.queue_event("owner-A", "distance", {"distance_m": 3}).get("ok", false), "failed reload closes writes")
	check(FileAccess.get_file_as_string(queue.storage_path) == corrupt, "corrupt original never overwritten")
	var event := {"id": "dup", "kind": "distance", "payload": {"distance_m": 1}}
	file = FileAccess.open(queue.storage_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "entries": [{"owner_id": "owner-A", "event": event}, {"owner_id": "owner-A", "event": event}, {"owner_id": "owner-B", "event": event}]}))
	file.close()
	check(queue.load_queue() and queue.pending_for("owner-A").size() == 1 and queue.pending_for("owner-B").size() == 1, "loaded identical duplicates coalesce within owner only")
	var sender := ServiceAuth.new()
	sender.session_path = path + ".sender"
	sender._user_id = "owner-A"
	sender._access_token = "test-access"
	sender._refresh_token = "test-refresh"
	sender._expires_at = int(Time.get_unix_time_from_system()) + 3600
	var api := ServiceAPI.new()
	root.add_child(api)
	api.configure(sender, "https://example.test", "sb_publishable_dummy")
	api.transport_override = func(_method: int, _url: String, _body: String, _token: String) -> Dictionary:
		# Simulate an unsent conflicting legacy entry arriving while request is in flight.
		queue._entries.append({"owner_id": "owner-A", "event": {"id": "dup", "kind": "distance", "payload": {"distance_m": 99}}})
		return {"ok": true, "status": 200, "data": {"received": 1, "inserted": 1}}
	var flushed: Dictionary = await queue.flush_for(sender, api)
	check(flushed.get("ok", false) and queue.pending_for("owner-A").size() == 1 and queue.pending_for("owner-A")[0].payload.distance_m == 99, "ACK removes only exact sent payload")
	check(queue.pending_for("owner-B").size() == 1, "ACK preserves other owner with same ID")
	api.free()
	sender.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(queue.storage_path))
	queue.free()
	print("SERVICE_IDENTITY_RACE: %d failed" % failures)
	quit(1 if failures else 0)

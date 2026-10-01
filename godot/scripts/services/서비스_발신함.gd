class_name ServiceOutbox
extends Node

# Offline game progress only. Purchases and server-owned inventory never enter this queue.
const MAX_EVENTS := 1000
const MAX_PAYLOAD_BYTES := 8192
const BATCH_SIZE := 100
const EVENT_ID_PATTERN := "^[A-Za-z0-9_-]{1,80}$"
const STORAGE_PATH := "user://service_progress_outbox.json"

var storage_path := STORAGE_PATH
var _entries: Array = []
var _loaded := false
var _syncing := false


func load_queue() -> bool:
	if _syncing:
		return false
	_loaded = false
	if not FileAccess.file_exists(storage_path):
		_entries = []
		_loaded = true
		return true
	var file := FileAccess.open(storage_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file = null
	if not parsed is Dictionary or parsed.get("version") != 1 or not parsed.get("entries") is Array:
		return false # Do not overwrite unknown/corrupt progress.
	var items: Array = parsed["entries"]
	if items.size() > MAX_EVENTS:
		return false
	for item in items:
		if not item is Dictionary or not _valid_owner(str(item.get("owner_id", ""))) or not _valid_event(item.get("event")):
			return false
	var unique := _unique_entries(items)
	if not unique.get("ok", false):
		return false
	_entries = unique["entries"]
	_loaded = true
	return true


func queue_event(owner_id: String, kind: String, payload: Dictionary, event_id: String = "") -> Dictionary:
	if not _loaded:
		return _fail("not_loaded")
	if not _valid_owner(owner_id):
		return _fail("invalid_owner_or_queue_full")
	if kind not in ["mission", "distance"] or JSON.stringify(payload).to_utf8_buffer().size() > MAX_PAYLOAD_BYTES:
		return _fail("invalid_event")
	if kind == "mission" and (not _valid_identifier(str(payload.get("stage_id", ""))) or not _valid_identifier(str(payload.get("mission_id", "")))):
		return _fail("invalid_event")
	if event_id.is_empty():
		event_id = "evt_" + Crypto.new().generate_random_bytes(16).hex_encode()
	if not _valid_identifier(event_id):
		return _fail("invalid_event")
	var event := {"id": event_id, "kind": kind, "payload": payload.duplicate(true)}
	for item in _entries:
		if item["owner_id"] == owner_id and item["event"]["id"] == event_id:
			if item["event"] != event:
				return _fail("conflicting_event")
			return {"ok": true, "id": event_id, "duplicate": true}
	if _entries.size() >= MAX_EVENTS:
		return _fail("invalid_owner_or_queue_full")
	var next := _entries.duplicate(true)
	next.append({"owner_id": owner_id, "event": event})
	if not _persist(next):
		return _fail("storage_unavailable")
	_entries = next
	return {"ok": true, "id": event["id"]}


func queue_event_once(owner_id: String, event_id: String, kind: String, payload: Dictionary) -> Dictionary:
	if not _valid_identifier(event_id):
		return _fail("invalid_event")
	return queue_event(owner_id, kind, payload, event_id)


func clear_owner(owner_id: String) -> Dictionary:
	if not _loaded or _syncing or not _valid_owner(owner_id):
		return _fail("not_ready")
	var next := _entries.filter(func(item: Dictionary) -> bool: return item["owner_id"] != owner_id)
	var removed := _entries.size() - next.size()
	if not _persist(next):
		return _fail("storage_unavailable")
	_entries = next
	return {"ok": true, "removed": removed}


func pending_for(owner_id: String) -> Array:
	var events: Array = []
	if not _loaded or not _valid_owner(owner_id):
		return events
	for item in _entries:
		if item["owner_id"] == owner_id:
			events.append(item["event"].duplicate(true))
	return events


func adopt_offline_guest(auth: ServiceAuth) -> Dictionary:
	if not _loaded or _syncing or auth == null or not auth.has_remote_session() or not auth.is_guest():
		return _fail("remote_guest_required")
	var previous_id := auth.pending_offline_guest_id()
	var remote_id := auth.get_user_id()
	if not previous_id.begins_with("local-") or not _valid_owner(previous_id) or not _valid_owner(remote_id) or previous_id == remote_id:
		return _fail("no_verified_transition")
	var next := _entries.duplicate(true)
	var moved := 0
	for item in next:
		if item["owner_id"] == previous_id:
			item["owner_id"] = remote_id
			moved += 1
	var unique := _unique_entries(next)
	if not unique.get("ok", false):
		return _fail("conflicting_event")
	next = unique["entries"]
	if moved > 0:
		if not _persist(next):
			return _fail("storage_unavailable")
		_entries = next
	return {"ok": true, "moved": moved}


func flush_for(auth: ServiceAuth, api: ServiceAPI) -> Dictionary:
	if not _loaded or _syncing:
		return _fail("not_ready")
	if auth == null or not auth.has_remote_session():
		return _fail("remote_session_required")
	var owner_id := auth.get_user_id()
	var events := pending_for(owner_id)
	if events.is_empty():
		return {"ok": true, "sent": 0}
	var batch := events.slice(0, BATCH_SIZE)
	_syncing = true
	var response: Dictionary = await api.post_function("sync-progress", {"events": batch})
	_syncing = false
	if auth.get_user_id() != owner_id or not auth.has_remote_session():
		return _fail("identity_changed")
	if not response.get("ok", false) or response.get("status") != 200:
		return _fail("sync_unconfirmed")
	var data: Variant = response.get("data")
	if not data is Dictionary or not _valid_ack(data, batch.size()):
		return _fail("sync_unconfirmed")
	var remaining := _entries.duplicate(true)
	# Remove only the exact transmitted entry, once; never every matching ID.
	for event in batch:
		for index in range(remaining.size()):
			if remaining[index]["owner_id"] == owner_id and remaining[index]["event"] == event:
				remaining.remove_at(index)
				break
	if not _persist(remaining):
		return _fail("storage_unavailable")
	_entries = remaining
	return {"ok": true, "sent": batch.size()}


func _unique_entries(items: Array) -> Dictionary:
	var owners := {}
	var unique: Array = []
	for item in items:
		var owner: String = item["owner_id"]
		var event: Dictionary = item["event"]
		if not owners.has(owner):
			owners[owner] = {}
		if owners[owner].has(event["id"]):
			if owners[owner][event["id"]] != event:
				return _fail("conflicting_event")
			continue
		owners[owner][event["id"]] = event
		unique.append(item.duplicate(true))
	return {"ok": true, "entries": unique}


func _valid_ack(data: Dictionary, count: int) -> bool:
	var received: Variant = data.get("received")
	var inserted: Variant = data.get("inserted")
	if typeof(received) not in [TYPE_INT, TYPE_FLOAT] or typeof(inserted) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return received == count and inserted >= 0 and inserted <= count and inserted == int(inserted)


func _valid_owner(value: String) -> bool:
	return not value.is_empty() and value.length() <= 100 and not value.contains("\n")


func _valid_identifier(value: String) -> bool:
	var expression := RegEx.new()
	if expression.compile(EVENT_ID_PATTERN) != OK:
		return false
	return expression.search(value) != null


func _valid_event(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if not _valid_identifier(str(value.get("id", ""))) or value.get("kind") not in ["mission", "distance"]:
		return false
	var payload: Variant = value.get("payload")
	if not payload is Dictionary or JSON.stringify(payload).to_utf8_buffer().size() > MAX_PAYLOAD_BYTES:
		return false
	if value["kind"] == "mission":
		return _valid_identifier(str(payload.get("stage_id", ""))) and _valid_identifier(str(payload.get("mission_id", "")))
	return true


func _persist(entries: Array) -> bool:
	var temp_path := storage_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	var stored := file.store_string(JSON.stringify({"version": 1, "entries": entries}))
	file.flush()
	var write_ok := stored and file.get_error() == OK
	file = null # Release the Windows file handle before renaming.
	if not write_ok:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false
	var moved := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(storage_path))
	if moved != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false
	return true


func _fail(code: String) -> Dictionary:
	return {"ok": false, "error": code}

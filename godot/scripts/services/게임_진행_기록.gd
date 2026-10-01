extends RefCounted

# Independent of outbox delivery/ACK: these are durable local achievements.
const MAX_OWNERS := 64
const MAX_RUN_IDS := 4096
const MAX_FILE_BYTES := 8 * 1024 * 1024
const MAX_VALUE := 1000000000.0
const MISSIONS := ["M1", "M2", "M3"]
var storage_path := "user://service_game_progress.json"
var _owners: Dictionary = {}
var _loaded := false

func load_store() -> bool:
	_loaded = false
	_owners = {}
	if not FileAccess.file_exists(storage_path):
		_loaded = true
		return true
	var file := FileAccess.open(storage_path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return false
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file = null
	if parse_error != OK:
		return false
	var parsed: Variant = parser.data
	if not parsed is Dictionary or parsed.size() != 2 or parsed.get("version") != 1 or not parsed.get("owners") is Dictionary:
		return false
	if not _valid_owners(parsed.owners):
		return false
	_owners = parsed.owners.duplicate(true)
	for entry in _owners.values():
		entry.runs_count = int(entry.runs_count)
		entry.best_distance_m = float(entry.best_distance_m)
		if not entry.last_run.is_empty():
			entry.last_run = _clean_run(entry.last_run)
	_loaded = true
	return true

func snapshot(owner_id: String) -> Dictionary:
	var state: Dictionary = _owners.get(owner_id, _empty()).duplicate(true)
	state.erase("run_ids")
	return state

func record_run(owner_id: String, result: Dictionary) -> Dictionary:
	if not _ready(owner_id):
		return _fail("not_loaded_or_invalid_owner")
	var run := _clean_run(result)
	if run.is_empty():
		return _fail("invalid_run")
	var next := _owners.duplicate(true)
	var entry: Dictionary = next.get(owner_id, _empty())
	if entry.run_ids.has(run.run_id):
		return {"ok": true, "duplicate": true}
	# Never evict accepted IDs: capacity exhaustion is explicit, not silent replay.
	if entry.run_ids.size() >= MAX_RUN_IDS:
		return _fail("history_full")
	entry.run_ids[run.run_id] = run.test_mode
	if not run.test_mode:
		entry.runs_count += 1
		entry.best_distance_m = maxf(entry.best_distance_m, run.distance_m)
		entry.completed_missions = _union(entry.completed_missions, run.mission_ids)
	entry.last_run = run
	next[owner_id] = entry
	return _commit(next)

func merge_remote_missions(owner_id: String, rows: Array) -> Dictionary:
	if not _ready(owner_id) or rows.size() > MAX_RUN_IDS:
		return _fail("invalid_remote_missions")
	var missions: Array = []
	for row in rows:
		if not row is Dictionary or not _identifier(row.get("stage_id")) or row.get("mission_id") not in MISSIONS:
			return _fail("invalid_remote_missions")
		if row.has("user_id") and row.user_id != owner_id:
			return _fail("identity_mismatch")
		if row.get("test_mode", false) == true:
			continue
		missions.append(row.mission_id)
	var next := _owners.duplicate(true)
	var entry: Dictionary = next.get(owner_id, _empty())
	entry.completed_missions = _union(entry.completed_missions, missions)
	next[owner_id] = entry
	return _commit(next)

func adopt_owner(old_local_id: String, new_id: String) -> Dictionary:
	if not _ready(old_local_id) or not _identifier(new_id) or not old_local_id.begins_with("local-") or new_id.begins_with("local-") or old_local_id == new_id:
		return _fail("local_identity_required")
	if not _owners.has(old_local_id):
		return {"ok": true, "moved": false}
	var next := _owners.duplicate(true)
	var source: Dictionary = next[old_local_id]
	var target: Dictionary = next.get(new_id, _empty())
	for id in source.run_ids:
		if target.run_ids.has(id) and target.run_ids[id] != source.run_ids[id]:
			return _fail("run_identity_conflict")
		target.run_ids[id] = source.run_ids[id]
	if target.run_ids.size() > MAX_RUN_IDS:
		return _fail("history_full")
	target.runs_count = 0
	for is_test in target.run_ids.values():
		if not is_test:
			target.runs_count += 1
	target.completed_missions = _union(target.completed_missions, source.completed_missions)
	target.best_distance_m = maxf(target.best_distance_m, source.best_distance_m)
	target.tutorial_seen = target.tutorial_seen or source.tutorial_seen
	if not source.last_run.is_empty():
		target.last_run = source.last_run.duplicate(true)
	next.erase(old_local_id)
	next[new_id] = target
	return _commit(next)

func clear_owner(owner_id: String) -> Dictionary:
	if not _ready(owner_id):
		return _fail("not_loaded_or_invalid_owner")
	var next := _owners.duplicate(true)
	next.erase(owner_id)
	return _commit(next)

func mark_tutorial_seen(owner_id: String) -> Dictionary:
	if not _ready(owner_id):
		return _fail("not_loaded_or_invalid_owner")
	var next := _owners.duplicate(true)
	var entry: Dictionary = next.get(owner_id, _empty())
	entry.tutorial_seen = true
	next[owner_id] = entry
	return _commit(next)

func _empty() -> Dictionary:
	return {"completed_missions": [], "best_distance_m": 0.0, "runs_count": 0, "last_run": {}, "tutorial_seen": false, "run_ids": {}}

func _ready(owner_id: String) -> bool:
	return _loaded and _identifier(owner_id)

func _identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 80:
		return false
	for c in value:
		if not (c >= "a" and c <= "z" or c >= "A" and c <= "Z" or c >= "0" and c <= "9" or c in ["_", "-"]):
			return false
	return true

func _number(value: Variant, integral: bool = false) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= 0 and value <= MAX_VALUE and (not integral or value == floor(value))

func _union(first: Array, second: Array) -> Array:
	var result := first.duplicate()
	for item in second:
		if not result.has(item):
			result.append(item)
	result.sort()
	return result

func _clean_run(raw: Dictionary) -> Dictionary:
	if not _identifier(raw.get("run_id")) or not _identifier(raw.get("stage_id")):
		return {}
	if not _number(raw.get("distance_m")) or not _number(raw.get("kills"), true) or not _number(raw.get("duration_s")):
		return {}
	if not raw.get("knife_used") is bool or not raw.get("cleared") is bool or not raw.get("test_mode", false) is bool:
		return {}
	var reason: Variant = raw.get("death_reason", "")
	var missions: Variant = raw.get("mission_ids", [])
	if not reason is String or reason.length() > 160 or reason.contains("@") or not missions is Array or missions.size() > 3:
		return {}
	for mission in missions:
		if mission not in MISSIONS:
			return {}
	var is_test: bool = raw.get("test_mode", false)
	return {"run_id": raw.run_id, "stage_id": raw.stage_id, "distance_m": float(raw.distance_m), "kills": int(raw.kills), "duration_s": float(raw.duration_s), "knife_used": raw.knife_used, "cleared": raw.cleared, "death_reason": reason, "mission_ids": [] if is_test else _union([], missions), "test_mode": is_test}

func _valid_owners(owners: Dictionary) -> bool:
	if owners.size() > MAX_OWNERS:
		return false
	for id in owners:
		var entry: Variant = owners[id]
		if not _identifier(id) or not entry is Dictionary or entry.size() != _empty().size():
			return false
		for key in _empty():
			if not entry.has(key):
				return false
		if not entry.completed_missions is Array or entry.completed_missions.size() > 3 or not _number(entry.best_distance_m) or not _number(entry.runs_count, true) or not entry.tutorial_seen is bool or not entry.last_run is Dictionary or not entry.run_ids is Dictionary or entry.run_ids.size() > MAX_RUN_IDS:
			return false
		for mission in entry.completed_missions:
			if mission not in MISSIONS:
				return false
		var normal_count := 0
		for run_id in entry.run_ids:
			if not _identifier(run_id) or not entry.run_ids[run_id] is bool:
				return false
			if not entry.run_ids[run_id]:
				normal_count += 1
		if entry.runs_count != normal_count:
			return false
		if not entry.last_run.is_empty():
			var cleaned := _clean_run(entry.last_run)
			if cleaned.is_empty() or cleaned.size() != entry.last_run.size() or not entry.run_ids.has(cleaned.run_id) or entry.run_ids[cleaned.run_id] != cleaned.test_mode:
				return false
			for key in cleaned:
				if not entry.last_run.has(key) or cleaned[key] != entry.last_run[key]:
					return false
	return true

func _commit(next: Dictionary) -> Dictionary:
	if not _loaded or not _valid_owners(next):
		return _fail("invalid_store_or_capacity")
	var text := JSON.stringify({"version": 1, "owners": next})
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return _fail("store_full")
	var temp := storage_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _fail("storage_unavailable")
	var written := file.store_string(text)
	file.flush()
	var success := written and file.get_error() == OK
	file = null # Release the Windows handle before atomic replace.
	if not success or DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(storage_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return _fail("storage_unavailable")
	_owners = next
	return {"ok": true}

func _fail(code: String) -> Dictionary:
	return {"ok": false, "error": code}

extends SceneTree
const PATH := "res://scripts/services/게임_진행_기록.gd"
var failures := 0
var test_path := "user://game_progress_test_" + Crypto.new().generate_random_bytes(12).hex_encode() + ".json"
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _run() -> void:
	if not ResourceLoader.exists(PATH):
		printerr("FAIL: 게임_진행_기록 구현 없음")
		quit(1)
		return
	var store = load(PATH).new()
	store.storage_path = test_path
	check(store.load_store(), "새 저장소 로드")
	var run := {"run_id": "run_one", "stage_id": "field_01", "distance_m": 100.0, "kills": 15, "duration_s": 10.0, "knife_used": false, "cleared": false, "death_reason": "grabbed", "mission_ids": ["M2"], "test_mode": false}
	check(store.record_run("local-A", run).get("ok", false), "로컬 기록 저장")
	var restarted = load(PATH).new()
	restarted.storage_path = test_path
	check(restarted.load_store(), "디스크 재로드")
	check(restarted.snapshot("local-A").runs_count == 1, "실제 파일 기록 복원")
	check(restarted.snapshot("account-B").runs_count == 0, "계정 격리")
	check(restarted.record_run("local-A", run).get("duplicate", false), "동일 run_id 멱등")
	check(restarted.snapshot("local-A").runs_count == 1, "재전송은 판 수 안 늘림")
	var second := run.duplicate(true)
	second.run_id = "run_two"
	second.mission_ids = ["M3"]
	second.distance_m = 40.0
	check(restarted.record_run("local-A", second).get("ok", false), "두 번째 판 저장")
	check(restarted.snapshot("local-A").completed_missions == ["M2", "M3"], "미션 합집합")
	var debug := run.duplicate(true)
	debug.run_id = "run_debug"
	debug.test_mode = true
	debug.distance_m = 9999.0
	debug.mission_ids = ["M1"]
	check(restarted.record_run("local-A", debug).get("ok", false), "디버그 문맥 저장")
	var state: Dictionary = restarted.snapshot("local-A")
	check(state.runs_count == 2 and state.best_distance_m == 100.0 and state.completed_missions == ["M2", "M3"], "테스트 판 정상 기록 제외")
	check(state.last_run.get("test_mode") == true, "버그 문맥에 테스트 표시")
	state.last_run.clear()
	check(not restarted.snapshot("local-A").last_run.is_empty(), "스냅샷 독립 복사")
	for method in ["merge_remote_missions", "adopt_owner", "clear_owner", "mark_tutorial_seen"]:
		if not restarted.has_method(method):
			check(false, "필수 메서드 없음: " + method)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
			print("GAME_PROGRESS_STORE: FAIL")
			quit(1)
			return
	check(restarted.mark_tutorial_seen("local-A").get("ok", false), "안내 완료 저장")
	check(restarted.snapshot("local-A").tutorial_seen, "안내 완료 조회")
	check(restarted.merge_remote_missions("account-B", [{"stage_id": "field_01", "mission_id": "M1", "completed_at": "2026-10-01", "email": "do-not-save@example.invalid"}]).get("ok", false), "원격 미션 복원")
	check(not restarted.adopt_owner("account-B", "account-C").get("ok", false), "영구 계정 이동 거부")
	check(restarted.adopt_owner("local-A", "account-B").get("ok", false), "명시적 local 인계")
	check(restarted.snapshot("local-A").runs_count == 0, "이전 소유자 제거")
	state = restarted.snapshot("account-B")
	check(state.completed_missions == ["M1", "M2", "M3"] and state.runs_count == 2 and state.tutorial_seen, "인계 합집합 및 안내 보존")
	check(restarted.record_run("account-B", run).get("duplicate", false), "인계 뒤 run_id 멱등 보존")
	var loaded = load(PATH).new()
	loaded.storage_path = test_path
	check(loaded.load_store() and loaded.snapshot("account-B") == state, "모든 값 디스크 복원")
	var injected := second.duplicate(true)
	injected.run_id = "run_sanitized"
	injected.access_token = "do-not-save-token"
	injected.email = "do-not-save@example.invalid"
	check(loaded.record_run("account-B", injected).get("ok", false), "부가 필드 제외 후 기록")
	var disk := FileAccess.get_file_as_string(test_path)
	check(not disk.contains("do-not-save") and not disk.contains("access_token") and not disk.contains("email"), "토큰 이메일 저장 제외")
	var invalid := run.duplicate(true)
	invalid.run_id = "invalid_finite"
	invalid.distance_m = INF
	check(not loaded.record_run("account-B", invalid).get("ok", false), "무한대 거부")
	invalid.distance_m = -1.0
	check(not loaded.record_run("account-B", invalid).get("ok", false), "음수 거부")
	check(not loaded.record_run("person@example.invalid", run).get("ok", false), "이메일 소유자 거부")
	check(loaded.clear_owner("account-B").get("ok", false), "탈퇴 로컬 정리")
	check(loaded.snapshot("account-B").runs_count == 0, "해당 소유자만 제거")
	var corrupt := FileAccess.open(test_path, FileAccess.WRITE)
	corrupt.store_string("{broken progress")
	corrupt = null
	var broken = load(PATH).new()
	broken.storage_path = test_path
	check(not broken.load_store(), "손상 파일 로드 실패")
	check(not broken.record_run("local-X", run).get("ok", false), "손상 파일 덮어쓰기 차단")
	check(FileAccess.get_file_as_string(test_path) == "{broken progress", "손상 원본 보존")
	var malformed := FileAccess.open(test_path, FileAccess.WRITE)
	malformed.store_string(JSON.stringify({"version": 1, "owners": {"account-B": {"runs_count": 5}}}))
	malformed = null
	check(not broken.load_store(), "구조 손상 거부")
	var full_entry := {"completed_missions": [], "best_distance_m": 0.0, "runs_count": 4096, "last_run": {}, "tutorial_seen": false, "run_ids": {}}
	for i in 4096:
		full_entry.run_ids["saved_%d" % i] = false
	var capacity_file := FileAccess.open(test_path, FileAccess.WRITE)
	capacity_file.store_string(JSON.stringify({"version": 1, "owners": {"account-full": full_entry}}))
	capacity_file = null
	check(broken.load_store(), "허용 상한 히스토리 로드")
	var before_capacity := FileAccess.get_file_as_string(test_path)
	check(not broken.record_run("account-full", run).get("ok", false), "히스토리 상한 거부·기존 ID 유지")
	check(FileAccess.get_file_as_string(test_path) == before_capacity, "상한 실패 시 디스크 변경 없음")
	var duplicate := run.duplicate(true)
	duplicate.run_id = "saved_0"
	check(broken.record_run("account-full", duplicate).get("duplicate", false), "상한에서도 오래된 ID 멱등")
	check(not broken.merge_remote_missions("account-full", [{"user_id": "someone-else", "stage_id": "field_01", "mission_id": "M1"}]).get("ok", false), "원격 타인 행 거부")
	check(not broken.merge_remote_missions("account-full", [{"stage_id": "field_01", "mission_id": "M1"}, {"stage_id": "field_01", "mission_id": "UNKNOWN"}]).get("ok", false), "잘못된 배치는 부분 반영 없음")
	check(broken.snapshot("account-full").completed_missions.is_empty(), "원격 검증 실패 후 미션 보존")
	check(broken.clear_owner("account-full").get("ok", false), "상한 계정 명시적 정리")
	check(broken.record_run("account-C", run).get("ok", false), "다른 계정 실제 저장")
	check(broken.record_run("account-D", run).get("ok", false), "같은 run_id 다른 계정 격리")
	check(broken.clear_owner("account-C").get("ok", false) and broken.snapshot("account-D").runs_count == 1, "한 계정 삭제 타인 보존")
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(test_path + ".tmp"))
	var before_failed_write := FileAccess.get_file_as_string(test_path)
	check(not broken.mark_tutorial_seen("account-D").get("ok", false), "임시파일 생성 실패 반환")
	check(not broken.snapshot("account-D").tutorial_seen and FileAccess.get_file_as_string(test_path) == before_failed_write, "쓰기 실패 메모리·원본 불변")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path + ".tmp"))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path + ".tmp"))
	print("GAME_PROGRESS_STORE: ", "PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)

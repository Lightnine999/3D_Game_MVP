extends SceneTree
const PATH := "res://scripts/services/게임_미션_추적.gd"
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _run() -> void:
	if not ResourceLoader.exists(PATH):
		printerr("FAIL: 게임_미션_추적 구현 없음")
		quit(1)
		return
	var tracker = load(PATH).new()
	tracker.configure("field_01", 750.0, 510.0, 530.0)
	check(tracker.sample({"kills": 14}).is_empty(), "14 처치는 M2 아님")
	check(tracker.sample({"kills": 15}) == ["M2"], "15 권총 처치 M2")
	check(tracker.sample({"kills": 16}).is_empty(), "미션 알림 중복 없음")
	check(not tracker.finish(false).mission_ids.has("M1"), "실패는 M1 아님")
	var clean = load(PATH).new()
	clean.configure("field_01", 750.0, 510.0, 530.0)
	clean.sample({"distance_m": 500.0, "bumps": 2, "grabs": 1})
	check(clean.sample({"distance_m": 510.0, "bumps": 2, "grabs": 1}).is_empty(), "진입은 달성 아님")
	check(clean.sample({"distance_m": 530.0, "bumps": 2, "grabs": 1}) == ["M3"], "실제 범위 무사 통과")
	check(clean.finish(true).mission_ids.has("M1"), "클리어만 M1")
	var frozen: Dictionary = clean.finish(true)
	clean.sample({"kills": 999})
	var changed: Dictionary = clean.finish(false, "changed", true)
	check(changed == frozen, "종료 이후 동결")
	changed.mission_ids.clear()
	check(not clean.finish(false).mission_ids.is_empty(), "반환값 변조 불가")
	check(tracker.finish(false).run_id != frozen.run_id, "Crypto run ID 고유")
	for counter in ["bumps", "grabs"]:
		var failed = load(PATH).new()
		failed.configure("field_01", 750.0, 510.0, 530.0)
		failed.sample({"distance_m": 510.0})
		var event := {"distance_m": 520.0}
		event[counter] = 1
		failed.sample(event)
		event.distance_m = 540.0
		check(failed.sample(event).is_empty() and not failed.finish(false).mission_ids.has("M3"), "다리 안 " + counter + " 실패")
	var skipped = load(PATH).new()
	skipped.configure("field_01", 750.0, 510.0, 530.0)
	skipped.sample({"distance_m": 500.0})
	check(skipped.sample({"distance_m": 540.0}).is_empty(), "구역 건너뛰기 M3 금지")
	var exit_hit = load(PATH).new()
	exit_hit.configure("field_01", 750.0, 510.0, 530.0)
	exit_hit.sample({"distance_m": 510.0})
	check(exit_hit.sample({"distance_m": 531.0, "grabs": 1}).is_empty(), "출구 프레임 잡힘도 실패")
	var finite = load(PATH).new()
	finite.configure("field_01", 750.0, 510.0, 530.0)
	finite.sample({"distance_m": INF, "duration_s": NAN, "kills": -10})
	var safe: Dictionary = finite.finish(false, "grabbed", true)
	check(is_finite(safe.distance_m) and is_finite(safe.duration_s) and safe.kills == 0, "비유한 입력 제외")
	check(safe.mission_ids.is_empty() and safe.test_mode, "테스트 종료는 깨끗한 미션 없음")
	var debug_tracker = load(PATH).new()
	debug_tracker.configure("field_01", 750.0, 510.0, 530.0)
	debug_tracker.sample({"kills": 15, "distance_m": 510.0})
	debug_tracker.sample({"distance_m": 530.0})
	check(debug_tracker.finish(true, "", true).mission_ids.is_empty(), "테스트 클리어 미션 정상 기록 금지")
	check(safe.mission_ids is Array[String], "종료 mission_ids는 형식 지정 배열")
	var counters = load(PATH).new()
	counters.configure("field_01", 750.0, 510.0, 530.0)
	counters.sample({"distance_m": 80.0, "kills": 4, "duration_s": 8.0, "knife_used": true})
	counters.sample({"distance_m": 20.0, "kills": 2, "duration_s": 4.0, "knife_used": false})
	var summary: Dictionary = counters.finish(false, "grabbed")
	check(summary.distance_m == 80.0 and summary.kills == 4 and summary.duration_s == 8.0 and summary.knife_used, "단조 카운터·칼 상태 보존")
	counters.configure("field_02", 100.0, 20.0, 30.0, 2)
	check(counters.sample({"kills": 2}) == ["M2"], "configure 목표와 판 초기화")
	check(counters.finish(false).stage_id == "field_02", "스테이지 식별자 전달")
	print("GAME_MISSION_TRACKER: ", "PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)

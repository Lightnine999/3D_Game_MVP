extends RefCounted

var _stage := ""
var _kills := 0
var _distance := 0.0
var _target_distance := 0.0
var _duration := 0.0
var _knife := false
var _kill_target := 15
var _missions: Array[String] = []
var _final: Dictionary = {}
var _bridge_start := 0.0
var _bridge_end := 0.0
var _entered := false
var _bridge_failed := false
var _bumps := 0
var _grabs := 0

# The stage owns clear/death decisions; this tracker does not change map values.
func configure(stage_id: String, target_distance: float, bridge_start: float, bridge_end: float, kill_target: int = 15) -> void:
	_stage = stage_id
	_target_distance = target_distance
	_kill_target = maxi(1, kill_target)
	_kills = 0
	_distance = 0.0
	_duration = 0.0
	_knife = false
	_missions.clear()
	_final.clear()
	_bridge_start = bridge_start
	_bridge_end = bridge_end
	_entered = false
	_bridge_failed = false
	_bumps = 0
	_grabs = 0


func sample(snapshot: Dictionary) -> Array[String]:
	var reached: Array[String] = []
	if not _final.is_empty():
		return reached
	var distance := _counter(snapshot.get("distance_m", _distance), _distance)
	var bumps := maxi(_bumps, int(_counter(snapshot.get("bumps", _bumps), _bumps)))
	var grabs := maxi(_grabs, int(_counter(snapshot.get("grabs", _grabs), _grabs)))
	var inside := distance >= _bridge_start and distance < _bridge_end
	if _bridge_end > _bridge_start and inside:
		_entered = true
	if _entered and not _missions.has("M3"):
		if bumps > _bumps or grabs > _grabs or snapshot.get("dead", false) == true:
			_bridge_failed = true
		if distance >= _bridge_end and not _bridge_failed:
			_missions.append("M3")
			reached.append("M3")
	_bumps = bumps
	_grabs = grabs
	_kills = maxi(_kills, int(_counter(snapshot.get("kills", _kills), _kills)))
	_distance = maxf(_distance, distance)
	_duration = maxf(_duration, _counter(snapshot.get("duration_s", _duration), _duration))
	_knife = _knife or snapshot.get("knife_used", false) == true
	if _kills >= _kill_target and not _missions.has("M2"):
		_missions.append("M2")
		reached.append("M2")
	return reached

func finish(cleared: bool, death_reason: String = "", test_mode: bool = false) -> Dictionary:
	if _final.is_empty():
		if cleared:
			_missions.append("M1")
		var final_missions: Array[String] = []
		if not test_mode:
			final_missions.assign(_missions)
		_final = {"run_id": "run_" + Crypto.new().generate_random_bytes(16).hex_encode(), "stage_id": _stage, "distance_m": _distance, "kills": _kills, "duration_s": _duration, "knife_used": _knife, "cleared": cleared, "death_reason": death_reason, "mission_ids": final_missions, "test_mode": test_mode}
	return _final.duplicate(true)

func _counter(value: Variant, fallback: float) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or value < 0 or value > 1000000000.0:
		return fallback
	return maxf(fallback, float(value))

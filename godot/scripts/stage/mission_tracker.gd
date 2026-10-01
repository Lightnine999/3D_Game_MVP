class_name MissionTracker
extends RefCounted
## 스테이지 미션 (2026-10-01, PRD 4.10 F-90~96) — 주인 A·B (사용자 관장)
## 비유: 판마다 들고 다니는 점수표. 게임이 "좀비 쓰러뜨림·피함·쏨·부딪힘·잡힘·완주"를 알려 주면 표에 적고,
## 목표에 닿는 순간 달성 → 코인·아이템 보상. 한 번 달성한 미션은 저장되고, 3개가 다 모이면 다음 스테이지가 열린다.
##
## 맵·난이도는 스테이지와 상관없이 그대로. 스테이지마다 미션만 다르다.
## 진행(스테이지·코인·권총 단계·달성 미션)은 user://progress.json 에 남는다 — 아이템 가방과 달리 껐다 켜도 리셋하지 않는다

const PATH := "user://progress.json"

# 미션 종류
#   escape        끝까지 탈출
#   kill          좀비 N마리 처치 (kind 가 있으면 그 종류만, knife 면 칼로만)
#   bridge_clean  다리 구간을 장애물·좀비 스침·잡힘 없이 건너기
#   dodge_streak  총을 쏘지 않고 좀비 N마리를 연속으로 피하기 (쏘면 0부터)
#   no_item       아이템을 하나도 쓰지 않고 탈출 (출발 준비·달리는 중·부활 모두)
# 목표치 (2026-10-01 "미션이 너무 쉽다" → 난도 올림): 한 판 탄약은 시작 탄창 + 보급 6개로 약 70발, 탱커는 2발
#   좀비 15 → 40 · 러너 15 → 25 · 탱커 8 → 12 · 연속 피하기 10 → 25 · 매복 5 → 15
#   칼은 한 판에 기본 1자루 + 예비 칼 1 = 최대 2자루라서 "칼로 3마리"는 불가능 → 2마리 (예비 칼을 챙겨야 한다)
const STAGES := [
	{"name": "STAGE 1  ·  노을 들판", "missions": [
		{"id": "s1_escape", "type": "escape", "text": "끝까지 탈출", "coins": 100, "item": "revive"},
		{"id": "s1_kill40", "type": "kill", "n": 40, "text": "좀비 40마리 처치", "coins": 100, "item": "knife_plus"},
		{"id": "s1_bridge", "type": "bridge_clean", "text": "다리를 무사히 건너기", "coins": 150, "item": "frenzy_30"},
	]},
	{"name": "STAGE 2  ·  사냥", "missions": [
		{"id": "s2_runner25", "type": "kill", "kind": "runner", "n": 25, "text": "러너 25마리 처치", "coins": 150, "item": "ammo_start_pack"},
		{"id": "s2_tank12", "type": "kill", "kind": "tank", "n": 12, "text": "탱커 12마리 처치", "coins": 200, "item": "frenzy_30"},
		{"id": "s2_dodge25", "type": "dodge_streak", "n": 25, "text": "총 없이 좀비 25마리 연속 피하기", "coins": 200, "item": "danger_sense"},
	]},
	{"name": "STAGE 3  ·  마지막 생존자", "missions": [
		{"id": "s3_ambush15", "type": "kill", "kind": "ambusher", "n": 15, "text": "매복 좀비 15마리 처치", "coins": 200, "item": "flare_supply"},
		{"id": "s3_knife2", "type": "kill", "knife": true, "n": 2, "text": "칼로 2마리 처치 (예비 칼 필요)", "coins": 250, "item": "revive"},
		{"id": "s3_noitem", "type": "no_item", "text": "아이템 없이 탈출", "coins": 300, "item": "adrenaline"},
	]},
]

# 권총 강화 (코인으로 시작 권총 탄창을 한 단계씩) — 모델·동작은 그대로, 탄창 크기만 (showcase.PISTOLS 와 같은 이름)
const PISTOL_LEVELS := [["소형 권총", 7, 0], ["컴팩트 권총", 9, 200], ["표준 권총", 12, 400], ["풀사이즈 권총", 15, 700]]

# ── 저장되는 진행 ─────────────────────────────────────────────
static var _p := {}
static var _loaded := false
static var last_run: Array = []                             # 지난 판에 달성한 미션 문구 — 탈출하면 바로 처음으로 돌아가서 알림을 못 보니 출발 준비에 다시 보여 준다


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_p = {"stage": 0, "coins": 0, "pistol": 0, "done": []}
	if FileAccess.file_exists(PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary:
			_p["stage"] = clampi(int(data.get("stage", 0)), 0, STAGES.size() - 1)
			_p["coins"] = maxi(int(data.get("coins", 0)), 0)
			_p["pistol"] = clampi(int(data.get("pistol", 0)), 0, PISTOL_LEVELS.size() - 1)
			if data.get("done") is Array:
				_p["done"] = data["done"]


static func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_p))


static func stage() -> int:
	_load()
	return _p["stage"]


static func stage_info() -> Dictionary:
	return STAGES[stage()]


static func coins() -> int:
	_load()
	return _p["coins"]


static func is_done(id: String) -> bool:
	_load()
	return id in _p["done"]


static func pistol() -> Array:                             # [이름, 탄창, 값]
	_load()
	return PISTOL_LEVELS[_p["pistol"]]


static func next_pistol() -> Array:                        # 다음 단계 (없으면 [])
	_load()
	return PISTOL_LEVELS[_p["pistol"] + 1] if _p["pistol"] + 1 < PISTOL_LEVELS.size() else []


static func buy_pistol() -> bool:
	var nx := next_pistol()
	if nx.is_empty() or coins() < nx[2]:
		return false
	_p["coins"] -= nx[2]
	_p["pistol"] += 1
	_save()
	print("[mission] 권총 강화 → %s %d발 (남은 코인 %d)" % [nx[0], nx[1], _p["coins"]])
	return true


# ── 이번 판 ───────────────────────────────────────────────────
signal achieved(text: String)                              # 알림 문구 ("미션 달성: … +100코인 · 부활 1")

var _stage := MissionTracker.stage()                       # 이번 판 스테이지 — 판 중간에 다음 스테이지가 열려도 이번 판은 이 스테이지 미션만 센다
var _kills := 0
var _kills_by := {}                                        # 종류 → 마릿수
var _knife_kills := 0
var _streak := 0
var _bridge_dirty := false
var _bridge_seen := false
var _item_used := false
var _over := false


# 출발: 지난 판 기록을 지운다 (출발 준비 창이 이미 보여 줬다)
func on_start() -> void:
	last_run = []


func on_kill(kind: String, by_knife: bool) -> void:
	_kills += 1
	_kills_by[kind] = _kills_by.get(kind, 0) + 1
	if by_knife:
		_knife_kills += 1
	_check()


func on_dodge() -> void:
	_streak += 1
	_check()


func on_shot() -> void:
	_streak = 0                                            # 쏘면 연속 피하기는 처음부터


# 다리 구간에서 부딪힘·스침·잡힘 → 이번 판 다리 미션 실패
func on_trouble(dist: float) -> void:
	if _on_bridge(dist):
		_bridge_dirty = true


func on_item_used() -> void:
	_item_used = true


# 달리는 거리 — 다리를 다 건너는 순간 다리 미션을 판정한다
func on_distance(dist: float) -> void:
	if _on_bridge(dist):
		_bridge_seen = true
	elif _bridge_seen and dist > StageBuilderV2.RIVER_Z1 + 2.0:
		_bridge_seen = false
		if not _bridge_dirty:
			_complete_type("bridge_clean")


func on_escape() -> void:
	_complete_type("escape")
	if not _item_used:
		_complete_type("no_item")
	_over = true


# 지금 스테이지 미션 진행 문구 (출발 준비 창·HUD 용): [[문구, 달성?], ...]
static func mission_lines() -> Array:
	var out := []
	for m in stage_info()["missions"]:
		out.append([m["text"], is_done(m["id"])])
	return out


func _on_bridge(dist: float) -> bool:
	return dist >= StageBuilderV2.RIVER_Z0 - 4.0 and dist <= StageBuilderV2.RIVER_Z1 + 2.0


func _check() -> void:
	for m in STAGES[_stage]["missions"]:
		if is_done(m["id"]):
			continue
		var ok := false
		match m["type"]:
			"kill":
				if m.get("knife", false):
					ok = _knife_kills >= m["n"]
				elif m.has("kind"):
					ok = _kills_by.get(m["kind"], 0) >= m["n"]
				else:
					ok = _kills >= m["n"]
			"dodge_streak":
				ok = _streak >= m["n"]
		if ok:
			_complete(m)


func _complete_type(type: String) -> void:
	for m in STAGES[_stage]["missions"]:
		if m["type"] == type and not is_done(m["id"]):
			_complete(m)


# 처음 달성: 저장 + 코인·아이템 보상 + 알림. 3개가 다 모이면 다음 스테이지 (다음 판부터)
func _complete(m: Dictionary) -> void:
	_load()
	_p["done"].append(m["id"])
	_p["coins"] += m["coins"]
	Inventory.add(m["item"], 1)
	var text := "미션 달성: %s   +%d코인 · %s 1" % [m["text"], m["coins"], Inventory.item_name(m["item"])]
	var all_done := true
	for x in STAGES[_stage]["missions"]:
		if not is_done(x["id"]):
			all_done = false
	if all_done and _stage == _p["stage"] and _p["stage"] + 1 < STAGES.size():
		_p["stage"] += 1
		text += "   ·   다음 판부터 %s" % STAGES[_p["stage"]]["name"]
	_save()
	last_run.append(m["text"])
	print("[mission] " + text)
	achieved.emit(text)

class_name Inventory
extends RefCounted
## 아이템 인벤토리 (2026-09-30 테스트 결제 팩) — 주인 A
## 비유: 가방 하나. 아이템 ID 마다 몇 개 있는지 적어 둔다. 지금은 기기 안(user://inventory.json)에 저장하고,
## 서버 결제가 연결되면 같은 모양(item_id → 수량)으로 서버 inventory 를 읽어 이 가방을 채우기만 하면 된다 (backend 📖백엔드 연동 계약)
##
##   Inventory.count("revive")        몇 개 있나
##   Inventory.use("revive")          1개 쓰기 (없으면 false)
##   Inventory.grant_pack("pack_one_more")   팩 구성대로 넣기 (테스트 지급 — 결제 연결 전)

const PATH := "user://inventory.json"
# 테스트 버전 (2026-10-01): 게임을 껐다 켜면 가방을 통째로 비운다. RETRY(장면 다시 읽기)로는 비우지 않는다 — 앱을 새로 켤 때만
# 정식 버전에서는 false 로 두고 서버 인벤토리를 정본으로 쓴다 (서버를 내렸다 켤 때의 리셋은 서버 쪽에서 — 백엔드 담당)
const RESET_ON_LAUNCH := true
const TIMED_DAYS := 14                        # 기간제 아이템 기간 (일)

# 아이템 (소모 = 쓰면 줄어든다 / 기간제 = 받은 날부터 14일 동안 계속, 다시 받으면 그날부터 14일)
# 황금 권총·서포터 배지는 영구였다가 2026-10-01 "영구를 빼줘" → 14일 기간제
const ITEMS := {
	"revive": {"name": "부활", "kind": "consumable"},
	"knife_plus": {"name": "예비 칼", "kind": "consumable"},
	"frenzy_30": {"name": "광란의 15초", "kind": "consumable"},
	"ammo_start_pack": {"name": "시작 탄약 팩", "kind": "consumable"},
	"flare_supply": {"name": "보급 신호탄", "kind": "consumable"},
	"bonfire": {"name": "모닥불", "kind": "consumable"},
	"danger_sense": {"name": "위험 감지", "kind": "consumable"},
	"adrenaline": {"name": "아드레날린", "kind": "consumable"},   # 2026-10-01 생존 키트에 추가
	"gold_pistol": {"name": "황금 권총", "kind": "timed"},
	"supporter_badge": {"name": "서포터 배지", "kind": "timed"},
}

# 팩 3종 (노션 "좀비탈출 — 테스트 결제 요금 패키지 (3종)", art/shop/*.png) — 가격은 서버가 정본
const PACKS := {
	"pack_survival_kit": {"name": "생존 키트", "price": 1100, "items": {"knife_plus": 1, "ammo_start_pack": 1, "flare_supply": 1, "adrenaline": 1}},
	"pack_one_more": {"name": "한 번 더", "price": 3300, "items": {"revive": 1, "frenzy_30": 1, "bonfire": 1}},
	"pack_legend": {"name": "전설의 생존자", "price": 5500, "items": {"revive": 2, "knife_plus": 2, "frenzy_30": 2, "danger_sense": 2, "gold_pistol": 1, "supporter_badge": 1}},
}

static var _items := {}
static var _expires := {}                      # 기간제 아이템 → 끝나는 시각 (유닉스 초)
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_items = {}
	_expires = {}
	if RESET_ON_LAUNCH:
		_save()                                               # 켤 때 한 번 비운다 (테스트 버전)
		print("[inventory] 테스트 버전 — 켤 때 가방 리셋")
		return
	if FileAccess.file_exists(PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary:
			for k in data:
				if ITEMS.has(k):
					_items[k] = int(data[k])
			var ex = data.get("_expires", {})
			if ex is Dictionary:
				for k in ex:
					_expires[k] = int(ex[k])


static func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		var data := _items.duplicate()
		data["_expires"] = _expires
		f.store_string(JSON.stringify(data))


static func count(item: String) -> int:
	_load()
	if ITEMS.get(item, {}).get("kind", "") == "timed" and int(_expires.get(item, 0)) <= int(Time.get_unix_time_from_system()):
		return 0                                              # 기간이 끝났다
	return int(_items.get(item, 0))


# 기간제 아이템이 남은 날 (없으면 0)
static func days_left(item: String) -> int:
	if count(item) <= 0:
		return 0
	return ceili((int(_expires.get(item, 0)) - Time.get_unix_time_from_system()) / 86400.0)


static func has(item: String) -> bool:
	return count(item) > 0


static func use(item: String) -> bool:
	_load()
	if not has(item):
		return false
	if ITEMS[item]["kind"] == "timed":
		return true                                           # 기간제 아이템은 써도 줄지 않는다 (기간이 끝나면 사라진다)
	_items[item] = count(item) - 1
	_save()
	return true


static func add(item: String, n := 1) -> void:
	_load()
	if not ITEMS.has(item):
		return
	if ITEMS[item]["kind"] == "timed":
		_items[item] = 1
		_expires[item] = int(Time.get_unix_time_from_system()) + TIMED_DAYS * 86400   # 받은 날부터 14일
	else:
		_items[item] = count(item) + n
	_save()


static func grant_pack(pack: String) -> void:
	for item in PACKS[pack]["items"]:
		add(item, PACKS[pack]["items"][item])
	print("[inventory] %s 지급 (테스트) → %s" % [PACKS[pack]["name"], JSON.stringify(_items)])


static func item_name(item: String) -> String:
	return ITEMS.get(item, {}).get("name", item)

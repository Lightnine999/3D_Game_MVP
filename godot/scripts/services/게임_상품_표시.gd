extends RefCounted

# Display only: not a server catalog, grant table, or ownership lookup.
const ITEM_NAMES := {"revive": "부활", "spare_knife": "예비 칼", "frenzy_30s": "광란의30초", "ammo_start_pack": "시작탄약팩", "supply_flare": "보급신호탄", "campfire": "모닥불", "danger_sense": "위험감지", "golden_pistol_skin": "황금권총스킨", "supporter_badge": "서포터배지"}
# Verification/display recipes only. Never used to grant inventory locally.
const COMPONENTS := {
	"pack_survival_kit": {"spare_knife": 1, "ammo_start_pack": 1, "supply_flare": 1},
	"pack_one_more": {"revive": 2, "frenzy_30s": 1, "campfire": 1},
	"pack_legend": {"revive": 3, "spare_knife": 2, "frenzy_30s": 2, "danger_sense": 2, "golden_pistol_skin": 1, "supporter_badge": 1},
}
const PRODUCTS := [
	{"id": "pack_survival_kit", "name": "생존 키트", "price": 1100, "price_text": "1,100원", "button": "BuySurvivalKit", "art": "res://assets/ui/상품_생존키트.png", "contents": "예비 칼 ×1\n시작 탄약 팩 ×1\n보급 신호탄 ×1", "featured": false},
	{"id": "pack_one_more", "name": "한 번 더 패키지", "price": 3300, "price_text": "3,300원", "button": "BuyOneMore", "art": "res://assets/ui/상품_한번더.png", "contents": "부활 ×2\n광란의 30초 ×1\n모닥불 ×1", "featured": true},
	{"id": "pack_legend", "name": "전설의 생존자", "price": 5500, "price_text": "5,500원", "button": "BuyLegend", "art": "res://assets/ui/상품_전설의생존자.png", "contents": "부활 ×3 · 예비 칼 ×2\n광란의 30초 ×2 · 위험 감지 ×2\n황금 권총 스킨 (영구)\n서포터 배지 (영구)", "featured": false},
]

static func product(product_id: String) -> Dictionary:
	for entry in PRODUCTS:
		if entry.id == product_id:
			return entry.duplicate(true)
	return {}

static func texture(path: String) -> Texture2D:
	# Existing imports work in exports; raw PNG fallback supports pre-import tests.
	if ResourceLoader.exists(path):
		var imported = load(path)
		if imported is Texture2D:
			return imported
	var image := Image.load_from_file(path)
	return null if image == null or image.is_empty() else ImageTexture.create_from_image(image)

static func purchase_blockers(platform: String, sdk_available: bool, test_key_available: bool, online: bool, catalog_ready: bool = false) -> String:
	var reasons: Array[String] = []
	if not catalog_ready:
		reasons.append("패키지 서버 배포 대기: 주문·구성품 지급은 아직 연결되지 않았습니다.")
	if platform != "Android":
		reasons.append("PC에서는 상품·보유 수량 확인만 가능합니다. Windows 결제는 지원하지 않습니다. 결제창은 Android 앱의 SDK 전용입니다.")
		if not test_key_available:
			reasons.append("현재 유효한 테스트 키가 설정되지 않았습니다.")
	else:
		if not sdk_available:
			reasons.append("Android 결제 SDK 플러그인이 없어 결제창을 열 수 없습니다.")
		if not test_key_available:
			reasons.append("Android SDK의 유효한 테스트 키가 설정되지 않았습니다.")
		if sdk_available and test_key_available and not catalog_ready:
			reasons.append("Android SDK 준비 여부와 별개로 패키지 주문은 서버 연동 전까지 차단됩니다.")
	if not online:
		reasons.append("보유 수량 확인과 향후 테스트 결제에는 온라인 계정이 필요합니다.")
	return "\n".join(reasons)

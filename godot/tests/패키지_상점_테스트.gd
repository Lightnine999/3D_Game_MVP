extends SceneTree

const SHOP = preload("res://scripts/ui/상점_화면.gd")
var failures: Array[String] = []

class FakeAuth extends ServiceAuth:
	var online := false
	func has_remote_session() -> bool:
		return online

class FakeAPI extends ServiceAPI:
	var queries: Array[String] = []
	var reply: Dictionary = {"ok": false}
	var epoch_auth: ServiceAuth
	func fetch_inventory_item(item_id: String) -> Dictionary:
		queries.append(item_id)
		if epoch_auth != null: epoch_auth._session_epoch += 1
		var result := reply.duplicate(true)
		if result.get("item") is Dictionary and not result.item.has("item_id"):
			result.item.item_id = item_id
		return result

class FakePayment extends Node:
	var calls := 0
	func can_purchase() -> bool:
		return true
	func start_purchase(_id: String) -> Dictionary:
		calls += 1
		return {"ok": true, "status": "paid"}

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)

func _run() -> void:
	var auth := FakeAuth.new()
	var api := FakeAPI.new()
	var payment := FakePayment.new()
	root.add_child(auth); root.add_child(api); root.add_child(payment)
	var shop := SHOP.new()
	shop.setup(auth, api, payment)
	root.add_child(shop)
	await process_frame
	var names := ["BuySurvivalKit", "BuyOneMore", "BuyLegend"]
	for name in names:
		check(shop.find_child(name, true, false) is Button, "패키지 선택 버튼: " + name)
	check(shop.find_child("TestPaymentNotice", true, false).text == "테스트 결제입니다. 실제 돈이 나가지 않습니다", "정확한 테스트 안내")
	check(shop.find_child("BuySelected", true, false).disabled, "준비 전 결제 차단")
	shop.call("_buy_selected")
	check(payment.calls == 0, "준비 전 주문/지급 호출 금지")
	var catalog = load("res://scripts/services/게임_상품_표시.gd")
	var expected := [
		["pack_survival_kit", 1100, "예비 칼 ×1\n시작 탄약 팩 ×1\n보급 신호탄 ×1"],
		["pack_one_more", 3300, "부활 ×2\n광란의 30초 ×1\n모닥불 ×1"],
		["pack_legend", 5500, "부활 ×3 · 예비 칼 ×2\n광란의 30초 ×2 · 위험 감지 ×2\n황금 권총 스킨 (영구)\n서포터 배지 (영구)"],
	]
	check(catalog.PRODUCTS.size() == 3, "패키지 세 개만 판매 표시")
	var cards := shop.find_child("PackageCards", true, false) as GridContainer
	for i in range(3):
		var product: Dictionary = catalog.PRODUCTS[i]
		check(product.id == expected[i][0] and product.price == expected[i][1] and product.contents == expected[i][2], "정확한 가격순/구성 " + str(i))
		check(product.featured == (i == 1), "중앙 메인 패키지 강조")
		var card := cards.get_child(i)
		var art := card.find_child("PackageArt", true, false) as TextureRect
		check(art.texture != null and art.texture.get_width() > 0, "실제 PNG 텍스처 로드")
		shop.find_child(names[i], true, false).emit_signal("pressed")
		check(shop.get("_selected_product") == product.id, "패키지 선택")
		check(shop.find_child("ProductDetail", true, false).text.contains(product.contents), "선택된 구성 표시")
	check(catalog.purchase_blockers("Windows", true, true, true).contains("Windows 결제는 지원하지 않습니다"), "PC는 SDK mock이 있어도 차단")
	var android: String = catalog.purchase_blockers("Android", false, false, false)
	check(android.contains("플러그인이 없어") and android.contains("테스트 키") and android.contains("온라인 계정"), "Android 준비 실패 이유")
	android = catalog.purchase_blockers("Android", true, true, true)
	check(android.contains("서버 연동 전까지 차단") and not android.contains("PC에서는"), "Android 서버 대기 이유")
	check(api.queries.is_empty(), "오프라인 조회 호출 금지")
	check(shop.has_method("set_catalog_ready"), "배포 검증 후에만 명시적 카탈로그 준비 설정")
	check(catalog.purchase_blockers("Android", true, true, true, true).is_empty(), "준비된 Android는 서버 대기 제거")
	if shop.has_method("set_catalog_ready"):
		shop.call("set_catalog_ready", true)
		shop.call("_buy_selected")
		check(payment.calls == 0 and shop.find_child("BuySelected", true, false).disabled, "배포 후에도 Windows 결제 차단")
	auth.online = true
	for invalid in [{"ok": false}, {"ok": true}, {"ok": true, "item": {"quantity": -1}}, {"ok": true, "item": {"quantity": 0.5}}, {"ok": true, "item": {"quantity": "0"}}, {"ok": true, "item": {"quantity": 0, "item_id": "pack_one_more"}}]:
		api.reply = invalid
		await shop.call("_refresh_inventory")
		var text: String = shop.find_child("InventoryStatus", true, false).text
		check(text.contains("미확인") and not text.contains(": 0개"), "실패/잘못된 응답을 0으로 표시하지 않음")
	for quantity in [0, 2]:
		api.reply = {"ok": true, "item": {"quantity": quantity}}
		await shop.call("_refresh_inventory")
		check(shop.find_child("InventoryStatus", true, false).text.contains(": %d개" % quantity), "확인된 실제 수량 표시")
	check(api.queries.size() == 72, "온라인 조회마다 구성품 9개 읽기")
	for query in api.queries:
		check(query in catalog.ITEM_NAMES, "패키지 ID를 보유 수량 키로 조회하지 않음")
	api.epoch_auth = auth
	await shop.call("_refresh_inventory")
	check(shop.find_child("InventoryStatus", true, false).text.contains("계정이 변경"), "같은 사용자 재로그인도 오래된 보유 응답 표시 차단")
	api.epoch_auth = null
	for dimensions in [Vector2i(1280, 720), Vector2i(640, 360)]:
		root.size = dimensions
		shop.size = Vector2(dimensions)
		await process_frame
		await process_frame
		await process_frame
		check(cards.columns == (3 if dimensions.x == 1280 else 1), "반응형 열 수 " + str(dimensions))
		var scroll := shop.find_child("ShopScroll", true, false) as ScrollContainer
		check(scroll.get_child(0).size.x <= scroll.size.x, "가로 넘침 없음 " + str(dimensions))
		var back := shop.find_child("BackToTitle", true, false) as Button
		check(back.get_global_rect().end.y <= dimensions.y and back.get_global_rect().end.x <= dimensions.x, "복귀 버튼 화면 안 유지")
		if dimensions.x == 640:
			check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "작은 화면 세로 스크롤")
		print("LAYOUT: ", dimensions, " columns=", cards.columns, " content=", scroll.get_child(0).size, " viewport=", scroll.size)
	shop.queue_free(); auth.queue_free(); api.queue_free(); payment.queue_free()
	await process_frame
	print("PACKAGE_SHOP: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

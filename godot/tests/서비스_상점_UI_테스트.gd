extends SceneTree

const ENTRY_SCENE := preload("res://scenes/ui/서비스_진입.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists("res://scenes/ui/상점_화면.tscn"):
		printerr("FAIL: 테스트 상점 장면 없음")
		quit(1)
		return
	var entry := ENTRY_SCENE.instantiate() as Control
	var isolated := "user://service_shop_ui_test_%d" % Time.get_ticks_usec()
	entry.set("outbox_storage_path_override", isolated + "_outbox.json")
	entry.set("progress_storage_path_override", isolated + "_progress.json")
	entry.set("settings_storage_path_override", isolated + "_settings.json")
	entry.set("offline_test_mode", true)
	entry.set("skip_splash_for_tests", true)
	var auth := ServiceAuth.new()
	auth.session_path = isolated + "_auth.json"
	entry.set("auth_override", auth)
	root.add_child(entry)
	entry.call("_show_title")
	var title := entry.find_child("ServiceTitle", true, false)
	if title == null or not title.has_signal("shop_requested"):
		printerr("FAIL: 서비스 타이틀에서 상점 진입 불가")
		entry.queue_free(); await process_frame; quit(1); return
	title.emit_signal("shop_requested")
	await process_frame
	var shop := entry.find_child("ShopScreen", true, false)
	if shop == null:
		printerr("FAIL: 상점 화면 미연결")
		entry.queue_free(); await process_frame; quit(1); return
	var notice := shop.find_child("TestPaymentNotice", true, false) as Label
	var button := shop.find_child("BuySurvivalKit", true, false) as Button
	var checkout := shop.find_child("BuySelected", true, false) as Button
	var detail := shop.find_child("ProductDetail", true, false) as Label
	var inventory := shop.find_child("InventoryStatus", true, false) as Label
	var ok := notice != null and notice.text.contains("테스트 결제") and notice.text.contains("실제 돈") and button != null and not button.disabled and checkout != null and checkout.disabled and detail != null and inventory != null
	if ok:
		button.emit_signal("pressed")
		await process_frame
		ok = detail.text.contains("생존 키트") and detail.text.contains("시작 탄약 팩 ×1") and detail.text.contains("보급 신호탄 ×1")
	if not ok:
		printerr("FAIL: 상품 선택은 가능해야 하고 실제 결제는 준비 전 차단되어야 함")
	shop.emit_signal("back_requested")
	await process_frame
	ok = ok and entry.find_child("ServiceTitle", true, false) != null
	entry.queue_free()
	await process_frame
	print("SERVICE_SHOP_UI: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

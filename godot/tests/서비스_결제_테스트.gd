extends SceneTree

const PAYMENT_PATH := "res://scripts/services/서비스_결제.gd"

class FakeAuth extends ServiceAuth:
	func access_token_for_request() -> Dictionary:
		return {"ok": true, "token": "test-access"}

class FakeNative extends Node:
	signal payment_result(status: String, payment_key: String, order_id: String, amount: int)
	var opens := 0
	var customer_key := ""
	var next_status := "authorized"
	var amount_delta := 0

	func open_test_widget(client_key: String, customer: String, order_id: String, _name: String, amount: int) -> bool:
		if not client_key.begins_with("test_gck_"):
			return false
		opens += 1
		customer_key = customer
		call_deferred("_finish", order_id, amount)
		return true

	func _finish(order_id: String, amount: int) -> void:
		payment_result.emit(next_status, "mock-payment-key" if next_status == "authorized" else "", order_id, amount + amount_delta)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists(PAYMENT_PATH):
		printerr("FAIL: 결제 앱 서비스 미구현")
		quit(1)
		return
	var auth := FakeAuth.new()
	auth._user_id = "test-user"
	auth._guest = true
	auth._access_token = "test-access"
	auth._refresh_token = "test-refresh"
	auth._expires_at = int(Time.get_unix_time_from_system()) + 3600
	root.add_child(auth)
	var api := ServiceAPI.new()
	root.add_child(api)
	api.configure(auth, "https://project.supabase.co", "sb_publishable_dummy")
	var calls: Array[Dictionary] = []
	var switch_at := {"path": ""}
	api.transport_override = func(method: int, path: String, payload: String, _token: String) -> Dictionary:
		calls.append({"method": method, "path": path, "body": JSON.parse_string(payload) if not payload.is_empty() else {}})
		if not str(switch_at.path).is_empty() and path.contains(switch_at.path):
			auth._user_id = "other-owner"
		if path.ends_with("/create-toss-order"):
			return {"ok": true, "status": 201, "data": {"orderId": "order-one", "productId": "pack_survival_kit", "amount": 1100, "orderName": "시작 탄약 팩", "status": "ready", "catalogVersion": 2}}
		if path.ends_with("/confirm-toss-payment"):
			return {"ok": true, "status": 200, "data": {"orderId": "order-one", "status": "paid"}}
		if path.begins_with("/rest/v1/toss_orders?"):
			return {"ok": true, "status": 200, "data": [{"order_id": "order-one", "status": "paid", "product_id": "pack_survival_kit", "amount": 1100}]}
		if path.begins_with("/rest/v1/inventory?"):
			var item_id := path.get_slice("item_id=", 1).trim_prefix("eq.").trim_prefix("in.(").get_slice(",", 0).get_slice("&", 0)
			return {"ok": true, "status": 200, "data": [{"item_id": item_id, "quantity": 1}]}
		return {"ok": false, "status": 404}
	var native := FakeNative.new()
	root.add_child(native)
	var payment: Node = load(PAYMENT_PATH).new()
	root.add_child(payment)
	if not payment.has_method("configure") or not payment.has_method("start_purchase"):
		printerr("FAIL: 주문→SDK→서버 승인→주문·인벤토리 재조회 경로 없음")
		payment.queue_free(); native.queue_free(); api.queue_free(); auth.queue_free(); quit(1); return
	payment.configure(auth, api, "test_gck_dummy", native)
	var blocked: Dictionary = await payment.start_purchase("pack_survival_kit")
	if blocked.get("error") != "catalog_not_ready" or not calls.is_empty():
		printerr("FAIL: default catalog gate")
		payment.queue_free(); native.queue_free(); api.queue_free(); auth.queue_free(); quit(1); return
	if not payment.has_method("set_catalog_ready"):
		printerr("FAIL: catalog setter missing")
		payment.queue_free(); native.queue_free(); api.queue_free(); auth.queue_free(); quit(1); return
	payment.set_catalog_ready(true)
	payment.set_catalog_version(2)
	var result: Dictionary = await payment.start_purchase("pack_survival_kit")
	var paths := calls.map(func(item: Dictionary) -> String: return item["path"])
	var ok: bool = result.get("ok", false) and result.get("status", "") == "paid" and native.opens == 1 and native.customer_key.begins_with("customer-") and paths.size() == 7 and paths[0].ends_with("/create-toss-order") and paths[1].ends_with("/confirm-toss-payment") and paths[2].begins_with("/rest/v1/toss_orders?") and paths[3].begins_with("/rest/v1/inventory?") and calls[0].body == {"product_id": "pack_survival_kit"} and calls[1].body.get("paymentKey") == "mock-payment-key" and calls[1].body.get("orderId") == "order-one" and calls[1].body.get("amount") == 1100 and calls[1].body.size() == 3
	if not ok:
		printerr("FAIL: 서버 주문·승인·재조회 흐름 불일치: outcome=%s, paths=%s" % [str(result.get("status", result.get("error", "none"))), str(paths)])
	for stage in ["confirm-toss-payment", "/rest/v1/toss_orders?", "/rest/v1/inventory?"]:
		auth._user_id = "test-user"
		switch_at.path = stage
		var switched: Dictionary = await payment.start_purchase("pack_survival_kit")
		if switched.get("error") != "identity_changed":
			printerr("FAIL: payment account switch after ", stage)
			ok = false
	switch_at.path = ""
	auth._user_id = "test-user"
	calls.clear()
	native.next_status = "cancelled"
	var cancelled: Dictionary = await payment.start_purchase("pack_survival_kit")
	ok = ok and cancelled.get("error") == "payment_cancelled" and calls.size() == 1 and calls[0].path.ends_with("/create-toss-order")
	calls.clear()
	native.next_status = "authorized"
	native.amount_delta = 1
	var mismatched: Dictionary = await payment.start_purchase("pack_survival_kit")
	ok = ok and mismatched.get("error") == "invalid_payment_result" and calls.size() == 1
	calls.clear()
	payment.configure(auth, api, "live_gck_dummy", native)
	var live_key: Dictionary = await payment.start_purchase("pack_survival_kit")
	ok = ok and live_key.get("error") == "test_key_or_online_account_required" and calls.is_empty()
	if not ok:
		printerr("FAIL: 취소·금액 불일치·라이브 키가 서버 승인으로 전송됨")
	payment.queue_free(); native.queue_free(); api.queue_free(); auth.queue_free()
	await process_frame
	print("SERVICE_PAYMENT_FLOW: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

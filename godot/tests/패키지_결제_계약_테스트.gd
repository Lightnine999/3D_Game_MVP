extends SceneTree

const Catalog = preload("res://scripts/services/게임_상품_표시.gd")
const FlowTest = preload("res://tests/서비스_결제_테스트.gd")
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)

func _run() -> void:
	check(Catalog.COMPONENTS == {
		"pack_survival_kit": {"spare_knife": 1, "ammo_start_pack": 1, "supply_flare": 1},
		"pack_one_more": {"revive": 2, "frenzy_30s": 1, "campfire": 1},
		"pack_legend": {"revive": 3, "spare_knife": 2, "frenzy_30s": 2, "danger_sense": 2, "golden_pistol_skin": 1, "supporter_badge": 1},
	}, "exact component recipes (display/verification only)")
	check(Catalog.ITEM_NAMES.size() == 9, "nine inventory components")
	var auth := FlowTest.FakeAuth.new()
	auth._user_id = "mock-owner"
	auth._access_token = "mock-access"
	auth._refresh_token = "mock-refresh"
	var api := ServiceAPI.new()
	var native := FlowTest.FakeNative.new()
	var payment := ServicePayment.new()
	root.add_child(auth); root.add_child(api); root.add_child(native); root.add_child(payment)
	api.configure(auth, "https://example.invalid", "sb_publishable_mock")
	payment.configure(auth, api, "test_gck_mock", native)
	payment.set_catalog_ready(true)
	var state := {"product": "", "amount": 7777, "confirmation": "paid", "order_status": "paid", "quantity": 4, "wrong_item": false, "failure_item": "", "switch_path": "", "order_amount": 7777}
	var calls: Array[String] = []
	api.transport_override = func(_method: int, path: String, payload: String, _token: String) -> Dictionary:
		calls.append(path)
		if not str(state.switch_path).is_empty() and path.contains(state.switch_path): auth._session_epoch += 1
		if path.ends_with("/create-toss-order"):
			check(JSON.parse_string(payload) == {"product_id": state.product}, "only selected package sent")
			return {"ok": true, "status": 201, "data": {"orderId": "mock-order", "productId": state.product, "orderName": "서버 상품명", "amount": state.amount, "status": "ready"}}
		if path.ends_with("/confirm-toss-payment"):
			check(JSON.parse_string(payload).amount == state.amount, "server order amount authoritative")
			return {"ok": true, "status": 200, "data": {"orderId": "mock-order", "status": state.confirmation}}
		if path.begins_with("/rest/v1/toss_orders?"):
			return {"ok": true, "status": 200, "data": [{"order_id": "mock-order", "status": state.order_status, "amount": state.order_amount, "product_id": state.product}]}
		var id := path.get_slice("item_id=eq.", 1).get_slice("&", 0)
		if id == state.failure_item: return {"ok": false, "error": "network_unavailable"}
		return {"ok": true, "status": 200, "data": [{"item_id": state.product if state.wrong_item else id, "quantity": state.quantity}]}
	for id in Catalog.COMPONENTS:
		state.product = id
		calls.clear()
		var result: Dictionary = await payment.start_purchase(id)
		check(result.get("ok", false), "complete package " + id)
		var expected: Array[String] = ["/functions/v1/create-toss-order", "/functions/v1/confirm-toss-payment", "/rest/v1/toss_orders?order_id=eq.mock-order&select=order_id,status,product_id,amount"]
		for item in Catalog.COMPONENTS[id]: expected.append("/rest/v1/inventory?item_id=eq.%s&select=item_id,quantity" % item)
		check(calls == expected, "exact ordered component reads, no package inventory: " + id)
	state.product = "pack_legend"
	state.confirmation = "already_paid"
	state.quantity = 0
	check((await payment.start_purchase(state.product)).get("ok", false), "already_paid and valid zero inventory do not fabricate a grant")
	for stage in ["create-toss-order", "confirm-toss-payment", "toss_orders?", "item_id=eq.golden_pistol_skin"]:
		state.switch_path = stage
		check((await payment.start_purchase(state.product)).get("error") == "identity_changed", "same-owner epoch invalidation: " + stage)
	state.switch_path = ""
	state.wrong_item = true
	check((await payment.start_purchase(state.product)).get("error") == "server_inventory_unconfirmed", "wrong inventory ID rejected")
	state.wrong_item = false
	for quantity in [-1, 0.5, "4", null, INF, NAN]:
		state.quantity = quantity
		check((await payment.start_purchase(state.product)).get("error") == "server_inventory_unconfirmed", "invalid component quantity " + str(quantity))
	state.quantity = 4
	state.failure_item = "supporter_badge"
	check((await payment.start_purchase(state.product)).get("error") == "server_inventory_unconfirmed", "last component network failure remains unconfirmed")
	state.failure_item = ""
	state.order_status = "ready"
	calls.clear()
	check((await payment.start_purchase(state.product)).get("error") == "server_order_unconfirmed" and calls.size() == 3, "no inventory check until order paid")
	state.order_status = "paid"
	state.order_amount = 1100
	check((await payment.start_purchase(state.product)).get("error") == "server_order_unconfirmed", "read-back amount mismatch rejected")
	state.order_amount = 7777
	state.confirmation = "ready"
	check((await payment.start_purchase(state.product)).get("error") == "server_confirmation_failed", "confirm ready not paid")
	state.confirmation = "paid"
	for amount in [INF, NAN, -1, 0.5, "7777"]:
		state.amount = amount
		check((await payment.start_purchase(state.product)).get("error") == "invalid_order", "invalid server amount rejected")
	calls.clear()
	for id in Catalog.ITEM_NAMES:
		check((await payment.start_purchase(id)).get("error") == "invalid_product", "single item cannot be purchased")
	check(calls.is_empty(), "singles cannot create orders")
	payment.configure(auth, api, "test_gck_mock")
	check(not payment.can_purchase(), "Windows cannot actually pay without injected test gateway")
	check((await payment.start_purchase("pack_legend")).get("error") == "android_payment_unavailable" and calls.is_empty(), "Windows makes no order or external browser fallback")
	payment.queue_free(); native.queue_free(); api.queue_free(); auth.queue_free()
	await process_frame
	print("PACKAGE_PAYMENT_CONTRACT: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

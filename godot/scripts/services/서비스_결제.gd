class_name ServicePayment
extends Node

# Native callback authorizes a payment attempt; only the server confirms the purchase.
const TEST_PLUGIN_NAME := "TossGamePayments"
const Catalog = preload("res://scripts/services/게임_상품_표시.gd")
const ALLOWED_PRODUCTS := ["pack_survival_kit", "pack_one_more", "pack_legend"]

var _auth: ServiceAuth
var _api: ServiceAPI
var _client_key := ""
var _native: Object
var _busy := false
var _catalog_ready := false
var _catalog_version := 0


func configure(auth_client: ServiceAuth, api_client: ServiceAPI, test_client_key: String, native_override: Object = null) -> void:
	_auth = auth_client
	_api = api_client
	_client_key = test_client_key.strip_edges() if test_client_key.begins_with("test_gck_") else ""
	_native = native_override


func set_catalog_ready(ready: bool) -> void:
	_catalog_ready = ready


func set_catalog_version(version: int) -> void:
	_catalog_version = version


func can_purchase() -> bool:
	return _catalog_ready and _catalog_version == 2 and _api != null and not _client_key.is_empty() and _auth != null and _auth.has_remote_session() and (_native != null or (OS.get_name() == "Android" and Engine.has_singleton(TEST_PLUGIN_NAME)))


func start_purchase(product_id: String) -> Dictionary:
	if not _catalog_ready or _catalog_version != 2:
		return _fail("catalog_not_ready")
	if _busy:
		return _fail("payment_in_progress")
	if product_id not in ALLOWED_PRODUCTS or _auth == null or _api == null:
		return _fail("invalid_product")
	if _client_key.is_empty() or not _auth.has_remote_session():
		return _fail("test_key_or_online_account_required")
	var gateway: Object = _native
	if gateway == null:
		if OS.get_name() != "Android" or not Engine.has_singleton(TEST_PLUGIN_NAME):
			return _fail("android_payment_unavailable")
		gateway = Engine.get_singleton(TEST_PLUGIN_NAME)
	# JNI plugin methods are not listed by Object.has_method() on Android.
	if _native != null and (not gateway.has_method("open_test_widget") or not gateway.has_signal("payment_result")):
		return _fail("android_payment_unavailable")
	_busy = true
	var owner_id := _auth.get_user_id()
	var owner_epoch := _auth._session_epoch
	var created: Dictionary = await _api.post_function("create-toss-order", {"product_id": product_id})
	if _auth.get_user_id() != owner_id or _auth._session_epoch != owner_epoch or not _auth.has_remote_session():
		return _finish(_fail("identity_changed"))
	if not created.get("ok", false) or created.get("status") != 201:
		return _finish(_fail("order_unavailable"))
	var order: Variant = created.get("data")
	if not order is Dictionary or order.get("productId") != product_id or order.get("status") != "ready" or str(order.get("orderId", "")).is_empty() or str(order.get("orderName", "")).is_empty() or typeof(order.get("amount")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(order.get("amount"))) or order.get("amount") <= 0 or order.get("amount") != int(order.get("amount")):
		return _finish(_fail("invalid_order"))
	if _auth.get_user_id() != owner_id or _auth._session_epoch != owner_epoch or not _auth.has_remote_session():
		return _finish(_fail("identity_changed"))
	if typeof(order.get("catalogVersion")) not in [TYPE_INT, TYPE_FLOAT] or order.get("catalogVersion") != 2:
		return _finish(_fail("catalog_version_mismatch"))
	var order_id := str(order["orderId"])
	var amount := int(order["amount"])
	var customer_key := "customer-" + Crypto.new().generate_random_bytes(16).hex_encode()
	if not gateway.open_test_widget(_client_key, customer_key, order_id, str(order["orderName"]), amount):
		return _finish(_fail("payment_ui_unavailable"))
	var callback: Array = await gateway.payment_result
	if _auth.get_user_id() != owner_id or _auth._session_epoch != owner_epoch or not _auth.has_remote_session():
		return _finish(_fail("identity_changed"))
	var status := str(callback[0])
	if status != "authorized":
		return _finish(_fail("payment_cancelled" if status == "cancelled" else "payment_failed"))
	var payment_key := str(callback[1])
	if payment_key.is_empty() or str(callback[2]) != order_id or callback[3] != amount:
		return _finish(_fail("invalid_payment_result"))
	var confirmed: Dictionary = await _api.post_function("confirm-toss-payment", {"paymentKey": payment_key, "orderId": order_id, "amount": amount})
	if _auth.get_user_id() != owner_id or _auth._session_epoch != owner_epoch or not _auth.has_remote_session():
		return _finish(_fail("identity_changed"))
	# Never log or store the SDK authorization key. The server owns approval.
	payment_key = ""
	if not confirmed.get("ok", false) or confirmed.get("status") != 200:
		return _finish(_fail("server_confirmation_failed"))
	var confirmation: Variant = confirmed.get("data")
	if not confirmation is Dictionary or confirmation.get("status") not in ["paid", "already_paid"] or confirmation.get("orderId") != order_id:
		return _finish(_fail("server_confirmation_failed"))
	var checked: Dictionary = await _api.fetch_order_status(order_id)
	if _auth.get_user_id() != owner_id or _auth._session_epoch != owner_epoch or not _auth.has_remote_session():
		return _finish(_fail("identity_changed"))
	if not checked.get("ok", false) or checked.get("order", {}).get("status") != "paid" or checked.get("order", {}).get("product_id") != product_id or checked.get("order", {}).get("amount") != amount:
		return _finish(_fail("server_order_unconfirmed"))
	for item_id in Catalog.COMPONENTS[product_id]:
			var inventory: Dictionary = await _api.fetch_inventory_item(item_id)
			if _auth.get_user_id() != owner_id or _auth._session_epoch != owner_epoch or not _auth.has_remote_session():
				return _finish(_fail("identity_changed"))
			var item: Variant = inventory.get("item")
			var quantity: Variant = item.get("quantity") if item is Dictionary else null
			if not inventory.get("ok", false) or not item is Dictionary or item.get("item_id") != item_id or typeof(quantity) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(quantity)) or quantity < 0 or quantity != int(quantity):
				return _finish(_fail("server_inventory_unconfirmed"))
	return _finish({"ok": true, "status": "paid", "order_id": order_id})


func _finish(result: Dictionary) -> Dictionary:
	_busy = false
	return result


func _fail(code: String) -> Dictionary:
	return {"ok": false, "error": code}

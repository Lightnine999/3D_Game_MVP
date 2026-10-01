extends SceneTree
const Flow = preload("res://tests/서비스_결제_테스트.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func run() -> void:
	var auth := Flow.FakeAuth.new()
	auth._user_id = "mock-owner"
	auth._access_token = "mock"
	auth._refresh_token = "mock"
	var api := ServiceAPI.new()
	var native := Flow.FakeNative.new()
	var payment := ServicePayment.new()
	for node in [auth, api, native, payment]: root.add_child(node)
	api.configure(auth, "https://example.invalid", "sb_publishable_mock")
	payment.configure(auth, api, "test_gck_mock", native)
	var state := {"version": null, "calls": 0}
	api.transport_override = func(_method, _path, _body, _token):
		state.calls += 1
		return {"ok": true, "status": 201, "data": {"orderId": "mock", "orderName": "mock", "productId": "pack_survival_kit", "amount": 1100, "status": "ready", "catalogVersion": state.version}}
	payment.set_catalog_ready(true)
	check(not payment.can_purchase(), "ready flag without version cannot enable ordering")
	var result: Dictionary = await payment.start_purchase("pack_survival_kit")
	check(result.get("error") == "catalog_not_ready" and state.calls == 0, "missing config version sends no order")
	if payment.has_method("set_catalog_version"):
		payment.call("set_catalog_version", 2)
		for version in [null, 1, "2", true, 3]:
			state.version = version
			result = await payment.start_purchase("pack_survival_kit")
			check(result.get("error") == "catalog_version_mismatch" and native.opens == 0, "old/malformed server blocked before SDK")
	else:
		check(false, "version setter required")
	for node in [payment, native, api, auth]: node.queue_free()
	await process_frame
	print("CATALOG_VERSION_GATE: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

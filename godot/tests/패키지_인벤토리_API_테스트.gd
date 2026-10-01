extends SceneTree

const Catalog = preload("res://scripts/services/게임_상품_표시.gd")
var failures: Array[String] = []

class FakeAuth extends ServiceAuth:
	func has_remote_session() -> bool: return true
	func access_token_for_request() -> Dictionary: return {"ok": true, "token": "mock-token"}

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _run() -> void:
	var auth := FakeAuth.new()
	auth._user_id = "inventory-owner"
	var api := ServiceAPI.new()
	root.add_child(auth); root.add_child(api)
	api.configure(auth, "https://example.invalid", "sb_publishable_mock")
	var state := {"response": {"ok": true, "status": 200, "data": []}, "epoch_change": false}
	var calls: Array[String] = []
	api.transport_override = func(method: int, path: String, payload: String, token: String) -> Dictionary:
		check(method == HTTPClient.METHOD_GET and payload.is_empty() and token == "mock-token", "authenticated read only")
		calls.append(path)
		if state.epoch_change: auth._session_epoch += 1
		return state.response.duplicate(true)
	for id in Catalog.ITEM_NAMES:
		var result: Dictionary = await api.fetch_inventory_item(id)
		check(result.get("ok", false) and result.get("item", {}) == {"item_id": id, "quantity": 0} and result.get("missing", false), "confirmed empty = zero: " + id)
		check(calls[-1] == "/rest/v1/inventory?item_id=eq.%s&select=item_id,quantity" % id, "component path " + id)
	for response in [{"ok": false, "error": "network_unavailable"}, {"ok": false, "status": 401}, {"ok": true, "status": 204, "data": []}, {"ok": true, "status": 200, "data": {}}, {"ok": true, "status": 200, "data": [{"item_id": "pack_legend", "quantity": 0}]}]:
		state.response = response
		check(not (await api.fetch_inventory_item("revive")).get("ok", false), "errors never zero")
	for quantity in [-1, 0.5, "1", null, INF, NAN]:
		state.response = {"ok": true, "status": 200, "data": [{"item_id": "revive", "quantity": quantity}]}
		check(not (await api.fetch_inventory_item("revive")).get("ok", false), "reject malformed quantity " + str(quantity))
	for quantity in [0, 2, 3.0]:
		state.response = {"ok": true, "status": 200, "data": [{"item_id": "revive", "quantity": quantity}]}
		check((await api.fetch_inventory_item("revive")).get("ok", false), "accept integer quantity")
	var before := calls.size()
	for id in Catalog.COMPONENTS:
		check(not (await api.fetch_inventory_item(id)).get("ok", false), "package is not inventory " + id)
	check(calls.size() == before, "invalid IDs never reach transport")
	state.epoch_change = true
	check((await api.fetch_inventory_item("revive")).get("error") == "identity_changed", "same-owner epoch change invalidates response")
	api.queue_free(); auth.queue_free()
	await process_frame
	print("PACKAGE_INVENTORY_API: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

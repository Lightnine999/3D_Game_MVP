extends SceneTree
const Base = preload("res://tests/패키지_인벤토리_API_테스트.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, msg: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", msg)
func run() -> void:
	var auth := Base.FakeAuth.new()
	auth._user_id = "mock"
	var api := ServiceAPI.new()
	root.add_child(auth); root.add_child(api)
	api.configure(auth, "https://example.invalid", "sb_publishable_mock")
	var state := {"rows": [{"item_id": "knife_plus", "quantity": 2}, {"item_id": "spare_knife", "quantity": 3}], "path": ""}
	api.transport_override = func(method, path, _body, _token):
		check(method == HTTPClient.METHOD_GET, "read only")
		state.path = path
		return {"ok": true, "status": 200, "data": state.rows}
	var result: Dictionary = await api.fetch_inventory_item("knife_plus")
	check(result.get("item", {}).get("quantity") == 5, "canonical + legacy consumables summed")
	check(state.path.contains("item_id=in.(knife_plus,spare_knife)"), "both IDs fetched")
	state.rows = [{"item_id": "gold_pistol", "quantity": 2}, {"item_id": "golden_pistol_skin", "quantity": 3}]
	result = await api.fetch_inventory_item("gold_pistol")
	check(result.get("item", {}).get("quantity") == 1, "permanents capped at one")
	for rows in [[{"item_id": "spare_knife", "quantity": true}], [{"item_id": "spare_knife", "quantity": "3"}], [{"item_id": "revive", "quantity": 3}], [{"item_id": "spare_knife", "quantity": 1}, {"item_id": "spare_knife", "quantity": 1}]]:
		state.rows = rows
		check(not (await api.fetch_inventory_item("knife_plus")).get("ok", false), "bad types, IDs and duplicate rows rejected")
	auth.queue_free(); api.queue_free()
	await process_frame
	print("INVENTORY_ALIASES: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

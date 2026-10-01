class_name ServiceAPI
extends Node

const ALLOWED_FUNCTIONS := [
	"ensure-profile", "sync-progress", "create-toss-order", "confirm-toss-payment",
	"support-chat", "delete-account", "admin-overview", "admin-support-reply",
]

var transport_override: Callable # Test-only transport; leave unset in the app.
var _auth: ServiceAuth
var _url := ""
var _public_key := ""


func configure(auth: ServiceAuth, url: String, publishable_key: String) -> void:
	_auth = auth
	_url = url.strip_edges().trim_suffix("/") if url.begins_with("https://") else ""
	_public_key = publishable_key.strip_edges() if publishable_key.begins_with("sb_publishable_") else ""


func post_function(name: String, payload: Dictionary) -> Dictionary:
	if not name in ALLOWED_FUNCTIONS:
		return _failure("invalid_function")
	if _url.is_empty() or _public_key.is_empty() or _auth == null:
		return _failure("not_configured")
	var session: Dictionary = await _auth.access_token_for_request()
	if not session.get("ok", false):
		return _failure(str(session.get("error", "unauthorized")))
	return await _send(HTTPClient.METHOD_POST, "/functions/v1/" + name, JSON.stringify(payload), str(session.get("token", "")))

func fetch_profile() -> Dictionary:
	if _url.is_empty() or _public_key.is_empty() or _auth == null:
		return _failure("not_configured")
	var session: Dictionary = await _auth.access_token_for_request()
	if not session.get("ok", false):
		return _failure(str(session.get("error", "unauthorized")))
	var path := "/rest/v1/profiles?id=eq.%s&select=nickname,is_guest,role" % _auth.get_user_id().uri_encode()
	var response: Dictionary = await _send(HTTPClient.METHOD_GET, path, "", str(session.get("token", "")))
	if not response.get("ok", false):
		return response
	var rows: Variant = response.get("data", [])
	if not rows is Array or rows.size() != 1 or not rows[0] is Dictionary:
		return _failure("profile_unavailable")
	return {"ok": true, "profile": rows[0]}

func update_nickname(name: String) -> Dictionary:
	var nickname := name.strip_edges()
	if nickname.length() < 2 or nickname.length() > 24 or nickname.contains("\n"):
		return _failure("invalid_nickname")
	if _url.is_empty() or _public_key.is_empty() or _auth == null:
		return _failure("not_configured")
	var session: Dictionary = await _auth.access_token_for_request()
	if not session.get("ok", false):
		return _failure(str(session.get("error", "unauthorized")))
	var path := "/rest/v1/profiles?id=eq.%s" % _auth.get_user_id().uri_encode()
	return await _send(HTTPClient.METHOD_PATCH, path, JSON.stringify({"nickname": nickname}), str(session.get("token", "")))


func fetch_order_status(order_id: String) -> Dictionary:
	if order_id.is_empty() or order_id.length() > 80:
		return _failure("invalid_order")
	var response: Dictionary = await _get_own_rows("/rest/v1/toss_orders?order_id=eq.%s&select=order_id,status,product_id,amount" % order_id.uri_encode())
	if not response.get("ok", false):
		return response
	var rows: Variant = response.get("data")
	if not rows is Array or rows.size() != 1 or not rows[0] is Dictionary or rows[0].get("order_id") != order_id:
		return _failure("order_unavailable")
	return {"ok": true, "order": rows[0]}


func fetch_inventory_item(item_id: String) -> Dictionary:
	if item_id not in preload("res://scripts/services/게임_상품_표시.gd").ITEM_NAMES:
		return _failure("invalid_product")
	if _auth == null or not _auth.has_remote_session():
		return _failure("remote_session_required")
	var owner := _auth.get_user_id()
	var epoch := _auth._session_epoch
	var catalog = preload("res://scripts/services/게임_상품_표시.gd")
	var ids: Array[String] = [item_id]
	if catalog.LEGACY_ALIASES.has(item_id):
		ids.append(catalog.LEGACY_ALIASES[item_id])
	var filter := "eq." + item_id if ids.size() == 1 else "in.(%s)" % ",".join(ids)
	var response: Dictionary = await _get_own_rows("/rest/v1/inventory?item_id=%s&select=item_id,quantity" % filter)
	if owner != _auth.get_user_id() or epoch != _auth._session_epoch or not _auth.has_remote_session():
		return _failure("identity_changed")
	if not response.get("ok", false):
		return response
	var rows: Variant = response.get("data")
	if response.get("status") != 200:
		return _failure("inventory_unavailable")
	if rows is Array and rows.is_empty():
		return {"ok": true, "item": {"item_id": item_id, "quantity": 0}, "missing": true}
	if not rows is Array or rows.size() > ids.size():
		return _failure("inventory_unavailable")
	var total := 0
	var seen := {}
	for row in rows:
		if not row is Dictionary or not row.get("item_id") is String or row.get("item_id") not in ids or seen.has(row.get("item_id")):
			return _failure("inventory_unavailable")
		seen[row.item_id] = true
		var quantity: Variant = row.get("quantity")
		if typeof(quantity) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(quantity)) or quantity < 0 or quantity >= 9223372036854775807 or quantity != int(quantity):
			return _failure("inventory_unavailable")
		if int(quantity) > 9223372036854775807 - total:
			return _failure("inventory_unavailable")
		total += int(quantity)
	if item_id in catalog.PERMANENT_ITEMS:
		total = mini(total, 1)
	return {"ok": true, "item": {"item_id": item_id, "quantity": total}}


func fetch_latest_support_thread() -> Dictionary:
	if _auth == null or not _auth.has_remote_session():
		return _failure("remote_session_required")
	var path := "/rest/v1/support_threads?user_id=eq.%s&kind=eq.question&select=id,status&order=created_at.desc&limit=1" % _auth.get_user_id().uri_encode()
	var response: Dictionary = await _get_own_rows(path)
	if not response.get("ok", false):
		return response
	var rows: Variant = response.get("data")
	if not rows is Array or rows.size() > 1:
		return _failure("invalid_response")
	if rows.is_empty():
		return {"ok": true, "thread_id": "", "status": ""}
	if not rows[0] is Dictionary or str(rows[0].get("id", "")).is_empty():
		return _failure("invalid_response")
	return {"ok": true, "thread_id": str(rows[0]["id"]), "status": str(rows[0].get("status", ""))}


func fetch_support_messages(thread_id: String) -> Dictionary:
	if thread_id.is_empty() or thread_id.length() > 80:
		return _failure("invalid_thread")
	var path := "/rest/v1/support_messages?thread_id=eq.%s&select=role,content&order=id.asc&limit=100" % thread_id.uri_encode()
	var response: Dictionary = await _get_own_rows(path)
	if not response.get("ok", false):
		return response
	var rows: Variant = response.get("data")
	if not rows is Array:
		return _failure("invalid_response")
	for row in rows:
		if not row is Dictionary or row.get("role") not in ["user", "assistant", "team"] or not row.get("content") is String:
			return _failure("invalid_response")
	return {"ok": true, "messages": rows}


func _get_own_rows(path: String) -> Dictionary:
	if _url.is_empty() or _public_key.is_empty() or _auth == null:
		return _failure("not_configured")
	var session: Dictionary = await _auth.access_token_for_request()
	if not session.get("ok", false):
		return _failure(str(session.get("error", "unauthorized")))
	return await _send(HTTPClient.METHOD_GET, path, "", str(session.get("token", "")))


func fetch_progress() -> Dictionary:
	if _auth == null or not _auth.has_remote_session():
		return _failure("remote_session_required")
	var owner := _auth.get_user_id()
	var encoded := owner.uri_encode()
	var response: Dictionary = await _get_own_rows("/rest/v1/mission_progress?user_id=eq.%s&select=stage_id,mission_id" % encoded)
	if not response.get("ok", false):
		return response
	if _auth.get_user_id() != owner:
		return _failure("identity_changed")
	var missions: Variant = response.get("data")
	if not missions is Array:
		return _failure("invalid_response")
	for mission in missions:
		if not mission is Dictionary or not mission.get("stage_id") is String or not mission.get("mission_id") is String:
			return _failure("invalid_response")
	# Read every page: taking the maximum of just recent runs loses older best records.
	var best := 0.0
	var run_count := 0
	for page in 100:
		var path := "/rest/v1/sync_events?user_id=eq.%s&kind=eq.distance&select=payload&order=id.asc&limit=1000&offset=%d" % [encoded, page * 1000]
		var distances: Dictionary = await _get_own_rows(path)
		if not distances.get("ok", false):
			return distances
		if _auth.get_user_id() != owner:
			return _failure("identity_changed")
		var rows: Variant = distances.get("data")
		if not rows is Array or rows.size() > 1000:
			return _failure("invalid_response")
		for row in rows:
			if not row is Dictionary or not row.get("payload") is Dictionary:
				return _failure("invalid_response")
			var distance: Variant = row["payload"].get("distance_m")
			if typeof(distance) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(distance)) or float(distance) < 0.0:
				return _failure("invalid_response")
			best = maxf(best, float(distance))
			run_count += 1
		if rows.size() < 1000:
			return {"ok": true, "missions": missions, "best_distance_m": best, "runs_count": run_count}
	return _failure("progress_too_large") # Preserve local records rather than pretending a partial restore is complete.


func _send(method: int, path: String, payload: String, token: String) -> Dictionary:
	if transport_override.is_valid():
		return await transport_override.call(method, path, payload, token)
	if not is_inside_tree() or token.is_empty():
		return _failure("unauthorized")
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	var headers := PackedStringArray([
		"apikey: " + _public_key,
		"Authorization: Bearer " + token,
		"Content-Type: application/json",
	])
	var err := request.request(_url + path, headers, method, payload)
	if err != OK:
		request.queue_free()
		return _failure("network_unavailable")
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return _failure("network_unavailable")
	var status: int = response[1]
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if status < 200 or status >= 300:
		return {"ok": false, "status": status, "error": _safe_error(parsed, status)}
	if status == 204:
		return {"ok": true, "status": status, "data": {}}
	if not parsed is Dictionary and not parsed is Array:
		return _failure("invalid_response")
	return {"ok": true, "status": status, "data": parsed}


func _safe_error(parsed: Variant, status: int) -> String:
	var code := str(parsed.get("error", "")) if parsed is Dictionary else ""
	if code in ["unauthorized", "invalid_event", "amount_mismatch", "invalid_product", "daily_limit_reached", "confirmation_required"]:
		return code
	if status == 401 or status == 403:
		return "unauthorized"
	if status == 429:
		return "rate_limited"
	return "server_unavailable"


func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code}

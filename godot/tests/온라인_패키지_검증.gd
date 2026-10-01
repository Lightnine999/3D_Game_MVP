extends SceneTree

# Read the actual exported pack without restoring a user session or making requests.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/서비스_공개설정.json"))
	var passed: bool = config is Dictionary
	if passed:
		passed = config.get("supabase_url", "") == "https://ecqfmaivywgzlbnqxymb.supabase.co"
		passed = passed and str(config.get("supabase_publishable_key", "")).begins_with("sb_publishable_")
		passed = passed and config.get("package_catalog_ready", false) == true
		passed = passed and config.get("support_multiturn_enabled", false) == true
	passed = passed and not OS.has_feature("human_test") and OS.has_feature("online_test")
	var director: Node = load("res://scripts/stage/showcase.gd").new()
	for icon_name in ["icon_pistol.png", "icon_knife.png"]:
		var texture: Texture2D = director._white_icon(icon_name)
		passed = passed and texture != null and texture.get_width() > 0
	director.free()
	print("ONLINE_EXPORTED_PACK: ", "PASS" if passed else "FAIL")
	print("PUBLIC_CONFIG_VALUES_NOT_PRINTED; AUTH_AND_NETWORK_NOT_INVOKED")
	quit(0 if passed else 1)

extends RefCounted

# Independent of account/session storage. Volume values are multipliers, not dB.
const DEFAULTS := {"control_mode":"drag", "sensitivity":1.0, "sfx_volume":1.0, "bgm_volume":1.0, "tilt_zero":0.0, "tutorial_seen":false}
var storage_path := "user://service_game_settings.cfg"
var _values: Dictionary = DEFAULTS.duplicate(true)

func values() -> Dictionary:
	return _values.duplicate(true)

static func validated(input: Dictionary, base: Dictionary = DEFAULTS) -> Dictionary:
	var result := base.duplicate(true)
	if input.get("control_mode") in ["drag", "tilt"]:
		result.control_mode = input.control_mode
	for key in ["sensitivity", "sfx_volume", "bgm_volume", "tilt_zero"]:
		var value: Variant = input.get(key)
		if (value is float or value is int) and is_finite(float(value)):
			result[key] = clampf(float(value), 0.5, 2.0) if key == "sensitivity" else (float(value) if key == "tilt_zero" else clampf(float(value), 0.0, 1.0))
	if input.get("tutorial_seen") is bool:
		result.tutorial_seen = input.tutorial_seen
	return result

func load_settings() -> bool:
	if not FileAccess.file_exists(storage_path):
		return true
	var config := ConfigFile.new()
	if config.load(storage_path) != OK or not config.has_section("game"):
		return false
	var data := {}
	for key in DEFAULTS:
		data[key] = config.get_value("game", key, _values[key])
	_values = validated(data, _values)
	return true

func save_settings(input: Dictionary) -> bool:
	var next := validated(input, _values)
	var config := ConfigFile.new()
	for key in DEFAULTS:
		config.set_value("game", key, next[key])
	var temporary := storage_path + ".tmp"
	if config.save(temporary) != OK:
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(storage_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return false
	_values = next
	return true

func set_tutorial_seen(seen: bool) -> bool:
	return save_settings({"tutorial_seen":seen})

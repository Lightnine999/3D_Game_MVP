extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var project := ConfigFile.new()
	var preset := ConfigFile.new()
	var ok: bool = project.load("res://project.godot") == OK and preset.load("res://export_presets.cfg") == OK
	if ok:
		var enabled: PackedStringArray = project.get_value("editor_plugins", "enabled", PackedStringArray())
		ok = enabled.has("res://addons/TossGamePayments/plugin.cfg")
		ok = ok and preset.get_value("preset.0.options", "gradle_build/use_gradle_build", false) == true
		ok = ok and FileAccess.file_exists("res://addons/TossGamePayments/bin/debug/TossGamePayments-debug.aar")
		ok = ok and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://android/build"))
	if not ok:
		printerr("FAIL: Android 플러그인 등록·Gradle 내보내기·빌드 템플릿 구성 누락")
	print("SERVICE_ANDROID_PLUGIN_CONFIG: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

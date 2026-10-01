extends SceneTree

# The same probe also runs with the exported exe and this external script.
const ICONS := {
	"icon_pistol.png": "아이콘_권총.png",
	"icon_pistol_empty.png": "아이콘_빈권총.png",
	"icon_knife.png": "아이콘_칼.png",
	"icon_supply.png": "아이콘_보급.png",
	"icon_ammo.png": "아이콘_탄약.png",
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failed := false
	for filename in ICONS:
		var path: String = "res://assets/ui/icons/" + filename
		if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
			printerr("FAIL: exported HUD icon missing: ", path)
			failed = true
	if failed:
		quit(1)
		return
	var director: Node = load("res://scripts/stage/showcase.gd").new()
	for logical_name in ICONS:
		var texture: Texture2D = director._icon(logical_name)
		var white: Texture2D = director._white_icon(logical_name)
		if texture == null or white == null or texture.get_width() <= 0 or white.get_width() <= 0:
			printerr("FAIL: HUD icon load/white conversion: ", logical_name)
			failed = true
	director.free()
	print("PACKAGED_HUD_ICONS: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

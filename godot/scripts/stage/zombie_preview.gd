# 좀비 확인용 장면 — 스테이지(안개·노을) 위에 좀비 4종을 세우고 동작을 재생 (A 확인용, 게임 코드 아님)
#
# 실행: godot --path godot res://scenes/stage/zombie_preview.tscn
# 스크린샷: ... -- --shots=<폴더>  (동작마다 한 장씩 저장하고 끝남)
extends Node3D

const ZOMBIES := [["zombie_walker", "워커"], ["zombie_runner", "러너"], ["zombie_tank", "탱커"], ["zombie_ambusher", "매복"]]
const ANIMS := ["idle", "walk", "attack", "hit", "death", "getup", "scream", "run"]
const BASE_D := 200.0             # 스테이지의 이 거리(달린 거리)에서 본다

var _players: Array[AnimationPlayer] = []
var _shots_dir := ""
var _label: Label


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots_dir = a.trim_prefix("--shots=")
	var stage := StageBuilderV2.new()
	add_child(stage)
	stage.build()
	stage.update_atmosphere(BASE_D)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.15
	cam.far = 400.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3(0, 1.6, -BASE_D)
	add_child(cam)
	cam.make_current()
	for i in ZOMBIES.size():
		var z: Node3D = load("res://assets/models/%s.glb" % ZOMBIES[i][0]).instantiate()
		z.position = Vector3(-4.5 + i * 3.0, 0, -(BASE_D + 7.0 + (i % 2) * 1.5))
		z.rotation_degrees.y = 180.0 - (-4.5 + i * 3.0) * 4.0       # 카메라 쪽(+Z)을 보게
		add_child(z)
		var ap: AnimationPlayer = z.find_children("*", "AnimationPlayer", true, false)[0]
		_players.append(ap)
		print("[zombie] %s anims=%s" % [ZOMBIES[i][0], ap.get_animation_list()])
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(40, 30)
	_label.add_theme_font_size_override("font_size", 40)
	layer.add_child(_label)
	_run()


func _play(anim: String) -> void:
	var names := []
	for i in _players.size():
		var ap := _players[i]
		var pick := anim if ap.has_animation(anim) else "idle"
		ap.play(pick)
		names.append("%s:%s" % [ZOMBIES[i][1], pick])
	_label.text = "  ".join(names)


func _run() -> void:
	for anim in ANIMS:
		_play(anim)
		for i in 20:                     # 동작이 조금 진행된 뒤 찍는다
			await RenderingServer.frame_post_draw
		if not _shots_dir.is_empty():
			DirAccess.make_dir_recursive_absolute(_shots_dir)
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots_dir, anim])
		else:
			await get_tree().create_timer(3.0).timeout
	if not _shots_dir.is_empty():
		get_tree().quit()
	else:
		_run()

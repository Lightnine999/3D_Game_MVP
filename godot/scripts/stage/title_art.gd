# 타이틀 배경 그림 찍기 — 주인: A (타이틀 화면 F-70 은 C, 이 장면은 그림만 만든다)
# 탈출 지점(요새 정문·투광등) 앞, 안개 속에서 좀비들이 이쪽으로 걸어오는 장면을 한 장 찍어 저장한다.
#
# 실행: godot --path godot --resolution 1920x1080 res://scenes/stage/title_art.tscn -- --out=<png> [--dist=975] [--yaw=0] [--zombies=5]
#   --dist 달린 거리(m)에서 찍음, --yaw 좌우로 돌림(도), --zombies 좀비 수 (0 - 5) — 로그인·가입 화면 배경도 같은 장면으로 찍는다
extends Node3D

const CAM_DIST := 975.0
const ZOMBIES := [
	["zombie_tank", Vector3(-2.3, 0, -7.2), 0.35, 30],
	["zombie_walker", Vector3(1.5, 0, -4.6), 0.15, 12],
	["zombie_runner", Vector3(-0.2, 0, -9.5), 0.0, 5],
	["zombie_ambusher", Vector3(3.6, 0, -8.0), -0.3, 40],
	["zombie_walker", Vector3(-4.6, 0, -11.5), 0.4, 55],
]

var _out := ""
var _dist := CAM_DIST
var _yaw := 0.0
var _count := 5
var _frames := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--dist="):
			_dist = float(a.trim_prefix("--dist="))
		elif a.begins_with("--yaw="):
			_yaw = float(a.trim_prefix("--yaw="))
		elif a.begins_with("--zombies="):
			_count = int(a.trim_prefix("--zombies="))
	var b := StageBuilderV2.new()
	add_child(b)
	b.build()
	b.update_atmosphere(_dist)
	var cam := Camera3D.new()
	cam.fov = 55
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.far = 400
	cam.position = Vector3(0.4, 1.55, -_dist)
	cam.rotation_degrees = Vector3(3, _yaw, 0)            # 살짝 올려다봄 → 좀비가 커 보이게
	add_child(cam)
	cam.make_current()
	for z in ZOMBIES.slice(0, _count):
		var n: Node3D = (load("res://assets/models/%s.glb" % z[0]) as PackedScene).instantiate()
		add_child(n)
		n.position = cam.position * Vector3(1, 0, 1) + z[1].rotated(Vector3.UP, deg_to_rad(_yaw))
		n.rotation.y = z[2]                             # 대략 카메라 쪽을 봄 (앞 = -Z 를 돌린 값)
		n.rotation.y = atan2(-(cam.position.x - n.position.x), -(cam.position.z - n.position.z)) + z[2] * 0.3
		var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
		ap.play("walk")
		ap.seek(float(z[3]) / 30.0, true)
		ap.pause()


func _process(_d: float) -> void:
	_frames += 1
	if _frames == 30:
		var img := get_viewport().get_texture().get_image()
		if _out != "":
			img.save_png(_out)
			print("TITLE_ART saved ", _out, " ", img.get_size())
		get_tree().quit()

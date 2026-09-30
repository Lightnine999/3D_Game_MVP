# 스테이지 v2 (500m) — 새 콘셉트: 분홍 노을 + 청회색 안개 + 앙상한 숲 + 듬성듬성한 폐허 — 주인: A
#
# 비유: 500m 세트장을 짓지 않고 부품(Blender 소품 34종) + 배치 규칙 + 하늘 그림으로 "눈앞 50m만 진짜처럼".
#
# 길은 없다. 광활한 대지에 수풀 덩어리·숲·폐허가 흩어져 있고, 달리는 폭(±6m) 안에 장애물 "카드"가 놓인다.
# 거리는 "남은 거리"로 표시한다: 500m에서 출발 → 목표(요새 정문)에서 0m.
# 2026-09-30 레벨 디자인: 1000m → 500m 압축. 나무·차 수는 그대로(밀도 2배), 차는 달리는 폭 안 장애물로 재배치 + 충돌.
#
# 구간 (표지판 = 남은 거리)
#   500m START              출발 모닥불, 외곽 폐가 몇 채, 사고 현장
#   400m DENSE WOODS        빽빽한 앙상한 숲, 스쿨버스
#   300m VILLAGE CENTER     폐가 몇 채가 모인 공터, 급수탑, 노점
#   200m BROKEN BRIDGE      강 20m + 짧은 부서진 다리, 물에 잠긴 차
#   100m PATH TO OBJECTIVE  철조망, 철탑, 방어벽, 0m 요새 성벽·투광등
#
# 좌표: 카메라는 -Z 방향으로 달린다. x = 0 이 달리는 폭 가운데. 달린 거리 d(양수) → z = -d
class_name StageBuilderV2
extends Node3D

const STAGE_LENGTH := 500.0           # 1000 → 500 (2026-09-30 레벨 디자인: 좀비 100마리가 루즈해서 절반으로 압축)
const DS := STAGE_LENGTH / 1000.0     # 1000m 시절 지점 → 지금 지점 (구간·랜드마크 위치는 비율 그대로)
const LANE_HALF := 6.0                # 이동 가능 폭 ±6m (PRD F-07)
const WORLD_HALF := 48.0
const CHUNK := 50.0
const DRAW_RANGE := 68.0              # 이보다 먼 것은 그리지 않음 (안개가 이미 가림)
const RIVER_Z0 := 340.0               # 강 (달린 거리 기준 → 남은 거리 160-140m)
const RIVER_Z1 := 360.0               # 강 폭 20m (다리가 짧아야 긴장감)
const TREE_PACK := 2                  # 500m 압축: 나무 수는 1000m 때 그대로 → 50m 조각마다 2배

# 안개·하늘: 앞쪽(분홍 노을) → 뒤쪽(무거운 회색)으로 점점 바뀐다
const FOG_NEAR := Color8(59, 71, 82)      # 짙은 청회색 안개 (FOREST TOUR 톤, 사용자 선택 2026-09-29)
const FOG_FAR := Color8(66, 72, 80)
# [달린 거리, 표지판 글자(남은 거리)]
const SIGNS := [[0.0, "500m\nSTART"], [100.0, "400m ->\nDENSE\nWOODS"], [200.0, "300m ->\nVILLAGE\nCENTER"],
	[300.0, "200m ->\nBROKEN\nBRIDGE"], [400.0, "100m ->\nPATH TO\nOBJECTIVE"]]

var obstacles: Array[Dictionary] = []   # 미리보기 카메라 회피용: {z(양수 거리), x, half_width}
var _rng := RandomNumberGenerator.new()
var _scenes := {}
var _mats := StageMaterials.new()
var _card_props := CardProps.new()     # 그림 카드 소품 (폐차·나무) — 테스트 중
var _env: Environment
var _fires: Array[OmniLight3D] = []
var _t := 0.0


# 성능 측정용: 실행 인자 --perf-off=shadow,trees,wrecks,cards,grass 로 항목을 꺼 보고
# 미리보기 --shots 로그의 [stats](면 수·그리기 호출)를 비교한다 (2026-09-29 최적화 때 사용)
var _perf_off := ""


func build(seed_value: int = 20260929) -> void:
	_rng.seed = seed_value
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():   # 폰에서는 adb 인텐트로 받은 인자가 앞쪽 목록에 온다
		if a.begins_with("--perf-off="):
			_perf_off = a.trim_prefix("--perf-off=")
	get_viewport().mesh_lod_threshold = 4.0   # 멀리 있는 모델은 가져올 때 만든 간단한 버전(LOD)으로 일찍 바꾼다
	_build_environment()
	_build_ground_and_river()
	for i in int(STAGE_LENGTH / CHUNK) + 1:
		_build_vegetation_chunk(i * CHUNK)
	_build_zone_start()
	_build_zone_woods()
	_build_zone_village()
	_build_zone_bridge()
	_build_zone_objective()
	_build_signs()
	_build_obstacles()
	_build_wrecks_3d()
	_build_card_props()
	_build_mist()
	_build_backdrop()
	_build_colliders()
	print("[stage v2] obstacles=%d fires=%d cars=%d colliders=%d" % [obstacles.size(), _fires.size(), _cars_placed, _colliders])


# 달린 거리 → 화면에 보일 남은 거리 (500 → 0)
static func remaining(dist: float) -> int:
	return int(ceil(maxf(STAGE_LENGTH - dist, 0.0)))


func _process(delta: float) -> void:
	_t += delta
	for i in _fires.size():            # 불빛 깜빡임
		_fires[i].light_energy = 2.0 + sin(_t * 13.0 + i) * 0.35 + sin(_t * 23.0 + i * 2.0) * 0.25


# 달린 거리에 따라 안개·하늘을 바꾼다 (남은 400m부터 회색으로 무거워짐 — 콘셉트 4·5번째 장면)
func update_atmosphere(dist: float) -> void:
	if _backdrop:
		_backdrop.position.z = -dist                       # 배경막은 카메라와 함께 움직인다 (산이 멀리 그대로 있는 느낌)
	var t := smoothstep(480.0 * DS, 760.0 * DS, dist)
	_env.fog_light_color = FOG_NEAR.lerp(FOG_FAR, t)
	_env.fog_sky_affect = lerpf(0.12, 0.35, t)   # 그림 하늘이 보이도록 약하게
	_env.fog_depth_end = lerpf(80.0, 70.0, t)


# ── 환경 ──────────────────────────────────────────────────────────
func _build_environment() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/textures/v2/sky_pano.png")   # OpenAI 파노라마 (make_sky_from_panorama.py)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color8(96, 98, 110)
	_env.ambient_light_energy = 0.85            # 너무 어두워 나무 색이 뭉개지던 것을 한 단계 밝게
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.tonemap_exposure = 1.12
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_light_color = FOG_NEAR
	_env.fog_depth_begin = 4.0
	_env.fog_depth_end = 80.0
	_env.fog_depth_curve = 0.9             # 가까운 곳은 맑게, 20m부터 옅은 청회색이 끼기 시작해 멀수록 겹겹이 짙어진다
	_env.fog_aerial_perspective = 0.55      # 먼 물체일수록 하늘(노을)색이 섞인다 (대기 원근)
	_env.fog_sun_scatter = 0.0                # 해 방향 산란 끔: 폰(Vulkan)에서 해 쪽 풀이 검은 쐐기로 나왔다
	_env.fog_sky_affect = 0.12
	_env.fog_height = 1.6                   # 땅에 깔리는 안개 (무릎-허리 높이까지 조금 더 짙게)
	_env.fog_height_density = 0.22
	_env.glow_enabled = true                # 불빛·투광등 번짐
	_env.glow_intensity = 0.8
	_env.glow_bloom = 0.12
	_env.glow_hdr_threshold = 0.9
	_env.adjustment_enabled = false          # 색은 안개·조명·카드 셰이더로만 맞춘다
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	var sun := DirectionalLight3D.new()    # 먼 앞쪽의 낮은 노을빛 → 물체가 역광 실루엣
	sun.light_color = Color(0.88, 0.76, 0.76)  # 정면 노을에서 오는 은은한 역광 → 나무 가장자리에 색이 실린다
	sun.light_energy = 0.5
	sun.rotation_degrees = Vector3(-12, 180, 0)
	# 그림자 끔: 해가 정면 낮은 곳(12°)이라 그림자가 카메라 쪽으로 5배 길게 늘어지고, 모바일 렌더러에서는
	# 정밀도가 낮아 화면 가운데에 삼각형 얼룩으로 뭉개졌다 (S24 Ultra 2026-09-29). 역광이라 그림자 효과도 거의 없다
	sun.shadow_enabled = false
	sun.directional_shadow_max_distance = 25.0   # 그림자는 가까운 폐차·소품에만
	add_child(sun)


func _build_ground_and_river() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/stage/ground_v2.gdshader")
	mat.set_shader_parameter("river_z0", RIVER_Z0)
	mat.set_shader_parameter("river_z1", RIVER_Z1)
	var ph := "res://assets/textures/polyhaven/brown_mud_leaves_01_"   # Poly Haven CC0 진흙 질감
	mat.set_shader_parameter("mud_tex", load(ph + "diff_1k.jpg"))
	mat.set_shader_parameter("mud_nrm", load(ph + "nor_gl_1k.jpg"))
	mat.set_shader_parameter("mud_rgh", load(ph + "rough_1k.jpg"))
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_HALF * 2.0 + 60.0, STAGE_LENGTH + 160.0)
	plane.material = mat
	var ground := _mesh_node(plane, Vector3(0, 0, -STAGE_LENGTH / 2.0), false)
	ground.visibility_range_end = 0.0
	# 강물 + 둑
	var water_mat := ShaderMaterial.new()
	water_mat.shader = load("res://scripts/stage/water.gdshader")
	var water := PlaneMesh.new()
	water.size = Vector2(WORLD_HALF * 2.0 + 60.0, RIVER_Z1 - RIVER_Z0 + 2.0)
	water.material = water_mat
	_mesh_node(water, Vector3(0, -1.5, -(RIVER_Z0 + RIVER_Z1) / 2.0), false)
	for d in [RIVER_Z0, RIVER_Z1]:
		var bank := BoxMesh.new()
		bank.size = Vector3(WORLD_HALF * 2.0 + 60.0, 3.0, 1.5)
		bank.material = _mats._material_for(_named_mat("dark_mud", Color(0.07, 0.065, 0.06)))
		var z: float = -d - (0.75 if d == RIVER_Z0 else -0.75)
		_mesh_node(bank, Vector3(0, -1.7, z), false)   # 윗면을 바닥보다 20cm 아래로: 2cm 차이일 땐 먼 거리에서 두 면이 번갈아 보이며 깜빡였다


# ── 풀·덤불·나무 (50m 조각마다) ──────────────────────────────────────
# 비유: 씨앗을 고르게 뿌리지 않고 "한 줌씩" 던진다 → 수풀 덩어리와 빈터가 자연스럽게 생긴다.
func _build_vegetation_chunk(d0: float) -> void:
	var zone := _zone(d0 + CHUNK * 0.5)
	_grass_multimesh(d0, 12000, "grass_v2.png", Vector2(2.4, 1.0), 30, false, true)    # 바닥 카펫: 넓게 흙을 덮는다 (0.55-0.95m)
	# 포기 6종 (기존 + Blender로 구운 5종: art/blender/make_grass_cards.py) — 높이는 _veg_scale 에서 랜덤
	for g in GRASS_TUFTS:
		_grass_multimesh(d0, g[1], g[0], g[2], 46, false, false, g[3])
	_grass_multimesh(d0, [520, 700, 420, 380, 360][zone], "bush_v2.png", Vector2(1.8, 1.6), 14, true)
	_trees_chunk(d0, zone)


# 나무: 숲 덩어리(grove) + 홀로 선 나무 (누운 나무는 두지 않는다). 달리는 폭 안의 나무는 장애물에서 따로 둔다.
# [질감, 50m당 개수, 카드 크기(폭, 높이), 달리는 폭 안에 둘지] — 합계는 이전 포기 16,000 과 비슷하게 (폰 60fps 유지)
# 곧은 줄기류(이삭·갈대·들꽃)는 카메라 코앞에서 커다란 막대처럼 보여 달리는 폭 밖에만 둔다
const GRASS_TUFTS := [
	["grass_v2.png", 7000, Vector2(1.3, 1.0), true], ["grass_wild.png", 4000, Vector2(1.2, 1.0), true],
	["grass_seed.png", 2000, Vector2(1.0, 1.1), false], ["grass_reed.png", 1500, Vector2(0.9, 1.2), false],
	["grass_weed.png", 1200, Vector2(0.9, 0.7), true], ["grass_thistle.png", 800, Vector2(1.0, 1.1), false],
]


# 구해 온 3D 에셋 (art/blender/optimize_glb.py 로 줄인 것) — 가까운 곳(7-22m)은 3D, 그 너머는 카드가 채운다
# 가지가 조각나거나 삼각형 판자처럼 깎인 모델(tree_dead_01·04, tree_old_02, tree_dead_real)은 뺐다 (2026-09-29 확대 점검)
# tree_fantasy_dead: 줄기가 공중에서 끝나고 가는 가지만 땅까지 늘어져, 세우면 떠 보이고 묻으면 잘려 보여서 뺐다
const TREES_3D := ["tree_dead_02", "tree_dead_03", "tree_dead_small", "tree_dry_01", "tree_old_01"]
const WRECKS_3D := ["car_junk_01", "car_abandoned_01", "car_thunderbird_1957", "car_scan_01", "car_scan_02", "car_scan_03",
	"car_scan_06", "car_scan_07", "car_scan_red", "car_scan_barricade"]
const WRECKS_LIGHT := ["car_junk_01", "car_abandoned_01", "car_thunderbird_1957"]   # 5천-9천 면 (길옆용)
const WRECKS_SCAN := ["car_scan_01", "car_scan_02", "car_scan_03", "car_scan_06", "car_scan_07", "car_scan_red", "car_scan_barricade"]   # 3만-5만 면
const HOUSES_3D := ["house_abandoned_01", "house_abandoned_02", "house_shack_01", "house_slum_01"]
const TREE_3D_NEAR := 16.0     # 3D 나무는 이 거리 안에만 (1그루 약 1만 면 — 폰 성능). 22 → 16: 양옆이 너무 벌어져 보여 가운데 쪽으로
const TREE_3D_RANGE := 60.0    # 3D 나무를 그리는 거리
const GRASS_RANGE := 85.0      # 풀 조각(50m)을 그리는 거리 — 안개가 68m에서 꽉 차서 그 너머는 안 보인다


func _trees_chunk(d0: float, zone: int) -> void:
	var groves: int = [3, 4, 3, 3, 2][zone] * TREE_PACK
	var singles: int = [7, 8, 6, 6, 6][zone] * TREE_PACK
	for g in groves:
		var cx := _side() * _rng.randf_range(LANE_HALF + 2.0, TREE_3D_NEAR - 1.0)
		var cd := d0 + _rng.randf() * CHUNK
		var radius := _rng.randf_range(2.5, 5.5)
		for i in _rng.randi_range(2, 4):
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * radius
			_tree(Vector3(cx + cos(a) * r, 0, -(cd + sin(a) * r)))
	for i in singles:
		_tree(Vector3(_side() * _rng.randf_range(LANE_HALF + 1.5, TREE_3D_NEAR), 0, -(d0 + _rng.randf() * CHUNK)))
	for k in TREE_PACK:
		if _rng.randf() < 0.5:                            # 오래된 그루터기
			var sx := _side() * _rng.randf_range(LANE_HALF + 1.0, 11.0)
			_spawn("stump_old_01", Vector3(sx, 0, -(d0 + _rng.randf() * CHUNK)), _rng.randf() * 360.0, _rng.randf_range(0.8, 1.3), true, TREE_3D_RANGE)


func _tree(pos: Vector3) -> Node3D:
	if "trees" in _perf_off: return null
	var d := -pos.z
	if d > RIVER_Z0 - 4.0 and d < RIVER_Z1 + 4.0:
		return null
	if absf(pos.x) < LANE_HALF + 1.0:                      # 달리는 폭은 장애물 배치가 맡는다
		pos.x = signf(pos.x if pos.x != 0.0 else 1.0) * (LANE_HALF + 1.0 + _rng.randf() * 2.0)
	var tree := _pick_distinct(TREES_3D, pos.x, d)
	var node := _spawn(tree, pos, _rng.randf() * 360.0, _rng.randf_range(0.6, 1.25), true, TREE_3D_RANGE)
	node.rotation_degrees.x = _rng.randf_range(-3.0, 3.0)    # 살짝 기운 나무 (많이 기울면 밑동 한쪽이 들린다)
	node.rotation_degrees.z = _rng.randf_range(-3.0, 3.0)
	_plant(node, tree)
	return node


# 나무를 땅에 박는다: 원점(가장 낮은 점)이 늘어진 가지·퍼진 뿌리 끝이라 줄기 밑동이 떠 보이는 모델이 있다
# 비율 = 모델 높이 대비 줄기 밑동 높이 (Blender 로 줄기 가운데 점이 촘촘해지는 높이를 잰 값, 2026-09-29)
# 라이선스 교체 (2026-09-29): 비상업(CC BY-NC) 모델은 파일을 지우고, 놓는 순간 허용 모델로 바꿔 끼운다.
# 목록 이름은 그대로 둬서 난수 흐름(=나무·폐차 위치)이 이전과 똑같이 유지된다. 출처: ASSETS_LICENSE.md
const LICENSE_SWAP := {"tree_dry_01": "tree_dead_03", "car_scan_barricade": "car_scan_02"}
const TREE_SINK := {"tree_old_01": 0.12, "tree_dead_02": 0.05,
	"tree_dead_03": 0.05, "tree_dead_04": 0.05, "tree_dead_small": 0.04}


func _plant(node: Node3D, model: String) -> void:
	model = LICENSE_SWAP.get(model, model)
	var height := _local_aabb(node).size.y * node.scale.y
	node.position.y -= height * float(TREE_SINK.get(model, 0.0)) + 0.15
	_no_shadow(node)                                          # 나무 그림자는 역광·약한 빛이라 거의 안 보이는데 가장 비싸다 (면 수 -60%)
	_matte_bark(node, model)


# 나무 재질 손보기: ① 가는 잔가지 면이 역광에 하얗게 반짝이던 반사(specular)를 끈다
# ② 같은 모델도 3가지 색조(따뜻한 갈색·잿빛·짙은 먹색) 중 하나로 칠해 단조롭지 않게
const BARK_TINTS := [Color(1.12, 0.98, 0.88), Color(0.92, 0.95, 1.0), Color(0.72, 0.7, 0.72)]
var _bark_mats := {}


func _matte_bark(node: Node3D, model: String) -> void:
	var tint_i := _rng.randi() % BARK_TINTS.size()
	for g in node.find_children("*", "MeshInstance3D", true, false):
		var mi := g as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			var key := "%s_%s_%d" % [model, src.resource_name, tint_i]
			if not _bark_mats.has(key):
				var m := src.duplicate() as BaseMaterial3D
				m.metallic = 0.0
				m.roughness = 1.0
				m.metallic_specular = 0.0                        # 반짝임 원인
				m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				m.albedo_color = src.albedo_color * BARK_TINTS[tint_i]
				_bark_mats[key] = m
			mi.set_surface_override_material(i, _bark_mats[key])


func _no_shadow(node: Node) -> void:
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# 수풀: clusters 개의 "한 줌" 중심 주변에 70%, 나머지 30%는 아무 데나. 한 줌마다 색(마른 풀·짙은 풀·잿빛)이 다르다.
func _grass_multimesh(d0: float, count: int, tex: String, size: Vector2, clusters: int, is_bush: bool, carpet := false, in_lane := true) -> void:
	if "grass" in _perf_off: return
	if "carpet" in _perf_off and carpet: return
	if "tufts" in _perf_off and not carpet and not is_bush: return
	if "bush" in _perf_off and is_bush: return
	var tints := [Color(0.9, 0.86, 0.74), Color(0.62, 0.68, 0.58), Color(0.78, 0.78, 0.78), Color(0.84, 0.78, 0.68)]   # 회갈색·잿빛 올리브
	var centers: Array = []
	for c in clusters:
		centers.append([_rng.randf_range(-WORLD_HALF, WORLD_HALF), d0 + _rng.randf() * CHUNK,
			_rng.randf_range(2.0, 8.0), tints[_rng.randi() % tints.size()], _rng.randf_range(0.8, 1.25)])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _card_mesh(tex, size)
	# 숨길 풀(강·다리 위, 달리는 폭 덤불)은 크기 0.0001로 줄여 두지 않고 목록에서 아예 뺀다.
	# 초소형 인스턴스는 폰(Vulkan·Adreno)에서 빛 계산이 망가져 가운데 길을 따라 검은 쐐기로 보였다 (2026-09-29)
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in count:
		var x: float
		var d: float
		var tint := Color(0.9, 0.86, 0.8)
		var boost := 1.0
		if _rng.randf() < 0.5:
			var c: Array = centers[_rng.randi() % centers.size()]
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * float(c[2])
			x = c[0] + cos(a) * r
			d = c[1] + sin(a) * r
			tint = c[3]
			boost = c[4]
		else:
			x = _rng.randf_range(-WORLD_HALF, WORLD_HALF)
			d = d0 + _rng.randf() * CHUNK
		var s := (_rng.randf_range(0.55, 0.95) if carpet else _veg_scale(absf(x), is_bush)) * boost
		if not in_lane and absf(x) < LANE_HALF:
			x = signf(x if x != 0.0 else 1.0) * (LANE_HALF + _rng.randf() * (WORLD_HALF - LANE_HALF))
		if d > RIVER_Z0 - 1.0 and d < RIVER_Z1 + 1.0:
			s = 0.0001                                             # 강 위에는 풀 없음
		elif d > RIVER_Z0 - 11.0 and d < RIVER_Z1 + 1.0 and absf(x) < 3.6:
			s = 0.0001                                             # 다리 상판 위에도 없음
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.75, 1.3), s))
		var shade := _rng.randf_range(0.6, 1.0)                  # (난수 순서를 지키려고 건너뛰기 전에 뽑는다)
		if s < 0.01:
			continue
		xforms.append(Transform3D(basis, Vector3(x, 0, -d)))
		colors.append(Color(tint.r * shade, tint.g * shade, tint.b * shade))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = GRASS_RANGE
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# 길은 없다: 풀은 어디든 바닥을 채운다. 높이는 층을 섞어 랜덤하게 (카드 높이 × 배율)
#   15% 낮게 0.4-0.6 / 65% 보통 0.6-1.05 / 20% 높게 1.05-1.4 — 덩어리마다 0.8-1.25배를 한 번 더 곱한다
# 매복 좀비가 풀 속에 누워 있다가 일어나고, 폐차·카드 밑동도 풀에 묻혀 떠 보이지 않는다
func _veg_scale(ax: float, is_bush: bool) -> float:
	if is_bush:
		if ax < LANE_HALF:
			return _rng.randf_range(0.4, 0.6) if _rng.randf() < 0.35 else 0.0001
		return _rng.randf_range(0.5, 1.1)
	var r := _rng.randf()
	if r < 0.15:
		return _rng.randf_range(0.4, 0.6)
	if r < 0.8:
		return _rng.randf_range(0.6, 1.05)
	return _rng.randf_range(1.05, 1.4)


const GRASS_LIT := Color(0.46, 0.46, 0.5)   # 조명을 받던 풀 밝기에 맞춘 값 (미리보기 캡처로 비교)
var _cards := {}
func _card_mesh(tex: String, size: Vector2) -> ArrayMesh:
	var key := "%s_%.2f_%.2f" % [tex, size.x, size.y]
	if _cards.has(key):
		return _cards[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in [0.0, PI / 2.0]:
		var dx := cos(a) * size.x * 0.5
		var dz := sin(a) * size.x * 0.5
		var q := [Vector3(-dx, 0, -dz), Vector3(dx, 0, dz), Vector3(dx, size.y, dz), Vector3(-dx, size.y, -dz)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[idx])
			st.add_vertex(q[idx])
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/v2/" + tex)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	# ALPHA_TO_COVERAGE 는 뺐다: MSAA 가 꺼진 폰에서는 효과가 없고 드라이버마다 결과가 달라진다
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	# 조명 계산 없이(unshaded) 그린다: 폰(Vulkan·Adreno)에서 풀 조명이 화면 가운데 삼각형 영역만 검게 망가졌다.
	# 밝기는 조명을 받던 때와 맞춰 미리 곱해 두고(GRASS_LIT), 안개는 그대로 적용된다. 수만 포기 조명 계산이 빠져 더 가볍다
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = GRASS_LIT
	st.set_material(mat)
	_cards[key] = st.commit()
	return _cards[key]


# ── 구간별 큰 배치 (폐허는 듬성듬성, 대지는 수풀·나무가 주인공) ──────────
func _ruin(model: String, d: float, x_min: float, x_max: float) -> void:
	if model.begins_with("v2_house") or model == "v2_shack":   # 박스 집 → 구해 온 폐허 모델 (같은 모델은 멀리 떨어지게)
		model = _pick_distinct(HOUSES_3D, 0.0, d, 120.0)
	_spawn(model, Vector3(_side() * _rng.randf_range(x_min, x_max), 0, -d), _rng.randf() * 360.0, 1.0, true, 110.0)


# 아래 거리 숫자는 1000m 시절 값 × DS (500m 압축 — 순서·비율은 그대로)
func _build_zone_start() -> void:
	_ruin("v2_house_a", 70.0 * DS, 16.5, 25.5)
	_ruin("v2_shack", 125.0 * DS, 12.0, 19.5)
	_ruin("v2_house_c", 180.0 * DS, 18.0, 27.0)
	_burning_drums(Vector3(-7.5, 0, -10.0), 3)           # 출발 지점의 모닥불


func _build_zone_woods() -> void:
	_ruin("v2_shack", 330.0 * DS, 13.5, 22.5)
	for i in 8:                                           # 숲 속에 쓰러져 가는 나무 울타리
		if _rng.randf() < 0.6:
			_spawn("v2_fence", Vector3(-9.5, 0, -(232.0 * DS + i * 3.1)), 90.0 + _rng.randf_range(-15, 15))


func _build_zone_village() -> void:
	# "마을 중심"도 거리가 아니라 폐가 몇 채가 모인 공터 (콘셉트 3번째 장면)
	var houses := [["v2_house_b", 468.0, -16.0], ["v2_house_a", 486.0, 21.0], ["v2_house_c", 507.0, -24.0], ["v2_house_b", 530.0, 17.0]]
	for n in houses.size():
		var h: Array = houses[n]
		_spawn(HOUSES_3D[n % HOUSES_3D.size()], Vector3(h[2] * 0.9 + signf(h[2]) * 2.0 + _rng.randf_range(-2, 2), 0, -h[1] * DS), _rng.randf_range(0, 360), 1.0, true, 110.0)   # 폭 10m 폐허가 달리는 폭에 붙지 않게
	_spawn("v2_water_tower", Vector3(30.0, 0, -500 * DS), 15.0)
	_spawn("v2_stall", Vector3(-9.0, 0, -480 * DS), 100.0)
	_spawn("v2_stall", Vector3(8.5, 0, -522 * DS), -70.0)
	_ruin("v2_shack", 420.0 * DS, 15.0, 24.0)
	_ruin("v2_shack", 585.0 * DS, 15.0, 24.0)


func _build_zone_bridge() -> void:
	# 다리: 상판 3칸(10m씩, 가운데 칸 오른쪽이 부서짐) — 강 폭 20m, 짧고 좁게
	for k in 3:
		var d := RIVER_Z0 - 5.0 + k * 10.0                  # 상판 가운데 위치
		_spawn("v2_bridge_deck_broken" if k == 1 else "v2_bridge_deck", Vector3(0, 0, -d), 0.0, 1.0, false)
	for k in 2:
		_spawn("v2_bridge_pillar", Vector3(0, 0, -(RIVER_Z0 + 5.0 + k * 10.0)), 0.0, 1.0, false)
	# 옆의 옛 다리: 무너져 강에 처박힌 상판 + 물에 잠긴 차 (콘셉트 4번째 장면)
	_spawn("v2_bridge_pillar", Vector3(16.0, 0, -(RIVER_Z0 + 6.0)), 0.0, 1.0, false)
	_spawn("v2_bridge_slab", Vector3(15.0, -1.6, -(RIVER_Z0 + 12.0)), 180.0, 1.0, false)
	_spawn("v2_truck", Vector3(-12.0, -1.7, -(RIVER_Z0 + 8.0)), 70.0, 1.0, false)
	_spawn("car_scan_red", Vector3(9.0, -1.0, -(RIVER_Z0 + 15.0)), 30.0, 1.0, false)
	_cars_placed += 2                                     # 강 속 트럭·빨간 차 (차 수 세기)
	_burning_drums(Vector3(-7.0, 0, -(RIVER_Z0 - 8.0)), 3)
	_ruin("v2_house_c", RIVER_Z0 - 40.0 * DS, 16.5, 24.0)
	for side in [-1.0, 1.0]:                              # 다리 밖으로는 강에 못 들어간다 (보이지 않는 벽)
		_wall_box(Vector3(side * (BRIDGE_HALF + 2.0), 1.5, -(RIVER_Z0 + RIVER_Z1) / 2.0), Vector3(4.0, 3.0, RIVER_Z1 - RIVER_Z0 + 1.0))
	_mission_zone("ZoneBridge", "bridge", Vector3(0, 1.5, -(RIVER_Z0 + RIVER_Z1 - 10.0) / 2.0), Vector3(7.0, 3.0, RIVER_Z1 - RIVER_Z0 + 10.0))


# 미션 구역 (TECH_SPEC 13.3.1 ①-3): B의 mission_system 이 그룹·메타로 찾는다
func _mission_zone(node_name: String, zone_id: String, center: Vector3, size: Vector3) -> void:
	var area := Area3D.new()
	area.name = node_name
	area.position = center
	area.add_to_group("mission_zone")
	area.set_meta("zone_id", zone_id)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	add_child(area)


func _build_zone_objective() -> void:
	for side in [-1.0, 1.0]:                              # 철조망 (양옆, 일부 쓰러짐·끊김) — 장수 유지: 간격 3.2 × DS
		var d := 845.0 * DS
		while d < 995.0 * DS:
			if _rng.randf() < 0.75:
				_chainlink_panel(Vector3(side * _rng.randf_range(8.0, 9.5), 0, -d), _rng.randf_range(-8, 8) + (_rng.randf_range(-25, 25) if _rng.randf() < 0.2 else 0.0))
			d += 3.2 * DS
	var pylons := [[-24.0, 840.0, 0.0], [26.0, 900.0, 11.0], [-28.0, 960.0, 0.0]]
	for p in pylons:
		var node := _spawn("v2_pylon", Vector3(p[0], 0, -p[1] * DS), 90.0, 1.0, true, 140.0)
		node.rotation_degrees.z = p[2]
	# 목표(남은 거리 0m): 요새 성벽 + 문 + 투광등 (문 너머가 탈출 지점)
	var wall_d := STAGE_LENGTH + 18.0
	_spawn("v2_gate", Vector3(0, 0, -wall_d), 0.0, 1.0, true, 160.0)
	for i in range(1, 6):
		for side in [-1.0, 1.0]:
			_spawn("v2_wall", Vector3(side * (3.0 + i * 12.0), 0, -wall_d), 0.0, 1.0, true, 160.0)
	for x in [-14.0, 14.0]:                               # 바깥쪽(±34m) 투광등은 뺐다: 기둥이 안개에 묻혀 등만 나무 사이에 떠 보였다 (2026-09-30)
		_floodlight(Vector3(x, 0, -(wall_d - 3.0)))


func _build_signs() -> void:
	for s in SIGNS:
		var d: float = s[0] + (8.0 if s[0] == 0.0 else 0.0)
		var sign := _spawn("v2_sign", Vector3(LANE_HALF + 0.6, 0, -d), -8.0)
		var label := Label3D.new()
		label.text = s[1]
		label.font_size = 64
		label.pixel_size = 0.0028
		label.modulate = Color(0.1, 0.1, 0.1)
		label.outline_size = 0
		label.position = Vector3(0, 1.56, 0.1)
		label.visibility_range_end = DRAW_RANGE
		sign.add_child(label)


# ── 달리는 폭 안의 장애물 (2026-09-30 레벨 디자인: 500m 압축 + "피할 수밖에 없는" 차 배치) ──
# 비유: 장애물 코스를 "구간 카드" 여러 장으로 이어 붙인다. 카드마다 차가 몇 대씩 들어가고,
#       어느 카드든 빠져나갈 틈(GAP_MIN 이상)이 반드시 한 군데는 있다.
# 차 수는 1000m 시절과 같다(63대). 길옆에 흩어져 있던 차를 달리는 폭 안으로 끌어와 장애물로 쓴다.
# 모든 차·소품은 _build_colliders 에서 충돌 상자를 받는다 → 뚫고 지나갈 수 없다.
const CAR_TOTAL := 63             # 1000m 시절 3D 차 수 (길 안 26 + 길옆 37, 2026-09-30 세어 봄)
const CAR_FIXED := 4              # 스쿨버스·강에 빠진 트럭·강 속 빨간 차·다리 위 차
const CAR_ROADSIDE := 12          # 길 바로 옆에 남기는 차 (나머지는 전부 달리는 폭 안의 장애물)
const GAP_MIN := 2.4              # 빠져나갈 틈 최소 폭 (플레이어 폭 0.7m + 여유)
const BRIDGE_HALF := 3.8          # 다리 상판 반폭 (ground_v2.gdshader 의 bridge_half 와 같게)
const BUS_D := 300.0 * DS         # 스쿨버스 (숲 속)
# 구간별 카드 종류 (같은 이름이 여러 번 = 더 자주 나옴)
const BEATS := [
	["flipped", "crash", "slalom", "camp", "side", "jam"],                 # 500-400m 출발
	["jam", "wall", "rubble", "slalom", "flipped", "camp", "wall"],        # 400-300m 숲
	["wall", "jam", "crash", "side", "rubble", "slalom", "pileup"],        # 300-200m 마을
	["crash", "wall", "camp", "flipped", "pileup"],                        # 200-100m 다리
	["barricade", "wall", "jam", "barricade", "flipped", "pileup"],        # 100-0m 목표
]
const BEAT_CARS := {"flipped": 1, "side": 1, "crash": 2, "wall": 2, "slalom": 3, "jam": 3, "pileup": 3}

var _car_budget := 0
var _cars_placed := 0
var _colliders := 0


func _build_obstacles() -> void:
	_car_budget = CAR_TOTAL - CAR_FIXED - CAR_ROADSIDE
	_scene_bus(BUS_D)                                     # 숲 속 길을 가로막은 스쿨버스
	_obstacle("car_junk_01", -1.4, RIVER_Z0 + 10.0, 8.0, 1.2)      # 다리 위에는 버려진 차 한 대
	_cars_placed += 2                                     # 버스 + 다리 위 차 (강 속 2대는 _build_zone_bridge)
	var d := 22.0
	while d < STAGE_LENGTH - 20.0:
		if d > RIVER_Z0 - 16.0 and d < RIVER_Z1 + 8.0:    # 강·다리 앞뒤는 비워 둔다
			d = RIVER_Z1 + 8.0
			continue
		if absf(d - BUS_D) < 12.0:
			d = BUS_D + 12.0
			continue
		var pool: Array = BEATS[_zone(d)]
		var kind: String = pool[_rng.randi() % pool.size()]
		if BEAT_CARS.get(kind, 0) > _car_budget:          # 차가 떨어지면 소품 카드만
			kind = ["camp", "rubble", "barricade" if _zone(d) == 4 else "camp"][_rng.randi() % 3]
		var depth := _beat(kind, d)
		_roadside_litter(d)
		d += depth + _rng.randf_range(7.0, 11.0)             # 카드 사이 숨 돌릴 틈 (초속 5m → 약 2초)
	print("[stage v2] 남은 차 %d대 → 길옆으로" % _car_budget)


# 카드 하나를 놓고, 앞뒤로 차지한 길이(m)를 돌려준다
var _last_s := 1.0
var _clear_side := 0.0            # 이 카드에서 반드시 비워 둘 쪽 (-1 왼쪽 / +1 오른쪽 / 0 없음 — 벽 카드는 틈을 직접 만든다)
const CLEAR_W := GAP_MIN + 0.4    # 비워 둘 폭 (달리는 폭 가장자리에서)
const START_CLEAR := 40.0         # 출발 구간: 이 안의 뒤집힌 차는 가운데를 비운다
const START_GAP := 1.2            # 가운데에서 이만큼은 비운다 (좌우 각각)


# s = 장애물이 몰린 쪽 (빈 틈은 반대쪽). 70%는 직전 카드와 반대 → 좌우로 번갈아 파고들게 만든다
func _beat(kind: String, d: float) -> float:
	var s := -_last_s if _rng.randf() < 0.7 else _last_s
	_last_s = s
	_clear_side = 0.0 if kind == "wall" else -s
	match kind:
		"flipped":                                        # 뒤집힌 차 한 대가 가운데를 막는다 → 양옆 중 하나로
			var info := _car(_pick_distinct(WRECKS_3D, 0.0, d), _rng.randf_range(-1.5, 1.5), d, _rng.randf_range(-35, 35) + 90.0 * float(_rng.randi() % 2), "flipped")
			_spawn("v2_tire", Vector3(info["x"] + s * 2.4, 0, -(d + 2.0)), _rng.randf() * 360.0)
			if _rng.randf() < 0.5:
				_burning_drums(Vector3(info["x"] - s * 2.6, 0, -(d - 1.5)), 2)
			return 5.0
		"side":                                           # 옆으로 누운 차가 가로로 길을 반쯤 막는다
			_car(_pick_distinct(WRECKS_3D, 0.0, d), s * _rng.randf_range(0.6, 1.8), d, 90.0 + _rng.randf_range(-20, 20), "side")
			_spawn("v2_rubble_wood", Vector3(-s * _rng.randf_range(4.5, 5.5), 0, -(d + 1.0)), _rng.randf() * 360.0)
			return 4.0
		"crash":                                          # 두 대가 비스듬히 부딪힌 사고 + 흩어진 짐
			var cx := s * _rng.randf_range(0.3, 1.5)
			var yaw := _rng.randf_range(20, 70) * s
			_car(_pick_distinct(WRECKS_3D, cx, d), cx, d, yaw, "flat")
			_car(_pick_distinct(WRECKS_3D, cx, d + 4.2), cx + s * 1.8, d + 4.2, yaw + _rng.randf_range(60, 110), "flipped" if _rng.randf() < 0.3 else "flat")
			for k in _rng.randi_range(2, 3):
				_spawn(["v2_suitcase_red", "v2_suitcase_blue", "v2_tire"][_rng.randi() % 3], Vector3(cx - s * _rng.randf_range(0.5, 1.8), 0, -(d + _rng.randf_range(-2.5, 2.5))), _rng.randf() * 360.0)
			return 7.0
		"wall":                                           # 차 두 대가 가로로 벽을 쌓고 한 곳만 틈 → 그 틈으로 파고든다
			var g := -s * _rng.randf_range(1.5, 3.5)          # 틈 가운데 (s 반대쪽)
			var w := _rng.randf_range(GAP_MIN + 0.2, 3.2)
			var left := _car(_pick_distinct(WRECKS_3D, g - 3.0, d), 0.0, d, 90.0 + _rng.randf_range(-12, 12), "flat")
			_align(left, g - w * 0.5, -1.0)
			var right := _car(_pick_distinct(WRECKS_3D, g + 3.0, d + 0.6), 0.0, d + 0.6, 90.0 + _rng.randf_range(-12, 12), "flat" if _rng.randf() < 0.7 else "side")
			_align(right, g + w * 0.5, 1.0)
			# 벽 바깥 끝이 달리는 폭 가장자리까지 안 닿으면 드럼통·상자로 메운다 (두 번째 틈이 생기지 않게)
			if left["x0"] > -LANE_HALF + 0.9:
				_burning_drums(Vector3((left["x0"] - LANE_HALF) * 0.5, 0, -d), 2)
				obstacles.append({"z": d, "x": (left["x0"] - LANE_HALF) * 0.5, "half_width": 1.1, "half_depth": 1.0})
			if right["x1"] < LANE_HALF - 0.9:
				_crate_pile(Vector3((right["x1"] + LANE_HALF) * 0.5, 0, -(d + 0.6)))
				obstacles.append({"z": d + 0.6, "x": (right["x1"] + LANE_HALF) * 0.5, "half_width": 1.2, "half_depth": 1.0})
			return 5.0
		"slalom":                                         # 좌·우·좌로 엇갈린 차 → 지그재그로 빠져나간다
			for k in 3:
				var side := s * (1.0 if k % 2 == 0 else -1.0)
				_car(_pick_distinct(WRECKS_3D, side * 1.5, d + k * 8.0), side * _rng.randf_range(0.9, 2.0), d + k * 8.0, 90.0 + _rng.randf_range(-30, 30), "flipped" if _rng.randf() < 0.2 else "flat")
			return 18.0
		"jam":                                            # 정체된 차들이 한쪽 가장자리부터 대각선으로 늘어섬
			var n := mini(_rng.randi_range(3, 4), _car_budget)
			for k in n:
				var x := s * (4.6 - k * 2.3)
				_car(_pick_distinct(WRECKS_3D, x, d + k * 3.2), x, d + k * 3.2, _rng.randf_range(-25, 25) + (180.0 if _rng.randf() < 0.5 else 0.0), "flat")
			return 3.2 * (n - 1) + 5.0
		"pileup":                                         # 연쇄 추돌: 세 대가 엉켜 한쪽을 통째로 막고, 하나는 뒤집혔다
			var cx := s * _rng.randf_range(1.2, 2.2)
			_car(_pick_distinct(WRECKS_3D, cx, d), cx, d, 90.0 + _rng.randf_range(-25, 25), "flat")
			_car(_pick_distinct(WRECKS_3D, cx, d + 3.0), cx - s * 0.6, d + 3.0, _rng.randf_range(-40, 40), "flipped")
			_car(_pick_distinct(WRECKS_3D, cx, d + 6.5), cx + s * 0.4, d + 6.5, 90.0 + _rng.randf_range(-40, 40), "side")
			if _rng.randf() < 0.6:
				_burning_drums(Vector3(cx - s * 3.2, 0, -(d + 3.0)), 2)
			return 9.0
		"camp":
			_scene_camp(s * _rng.randf_range(0.3, 1.2), d)
			return 5.0
		"rubble":
			_scene_rubble(s * _rng.randf_range(0.3, 1.5), d)
			return 3.0
		"barricade":
			_scene_barricade(s * _rng.randf_range(0.2, 1.0), d)
			return 4.0
	return 3.0


# 차 한 대: pose = "flat"(바로 섬, 살짝 기움) / "flipped"(뒤집힘) / "side"(옆으로 누움)
# 모델마다 원점·축이 달라서, 돌린 뒤 실제 모양(AABB)의 바닥을 땅에 맞춘다 → 뜨거나 파묻히지 않는다
# yaw 는 "차 길이가 달리는 방향(Z)일 때 0, 90 이면 길을 가로막는 가로" 기준.
# 모델마다 길이 축이 X·Z 로 제각각이라(스캔 차 절반이 X) 여기서 맞춘다 (2026-09-30 배치도에서 발견)
func _car(model: String, x: float, d: float, yaw: float, pose: String) -> Dictionary:
	var node := _spawn(model, Vector3(x, 0, -d), yaw)
	var native := _local_aabb(node)
	var long_x := native.size.x > native.size.z
	if long_x:
		node.rotation_degrees.y -= 90.0
	match pose:
		"flat":
			_settle(node)
		"flipped":
			node.rotation_degrees.z = 180.0 + _rng.randf_range(-4, 4)
			_ground(node)
		"side":                                           # 길이 축을 중심으로 굴린다 (다른 축이면 차가 코를 박고 선다 — 2026-09-30 발견)
			var roll := 90.0 * _side() + _rng.randf_range(-6, 6)
			if long_x:
				node.rotation_degrees.x = roll
			else:
				node.rotation_degrees.z = roll
			_ground(node)
	_car_budget -= 1
	_cars_placed += 1
	var info := {"node": node}
	_measure(info)
	# 큰 차는 돌리면 5m가 넘어서, 비워 둘 쪽을 침범하면 밀어낸다 → 어떤 카드든 빠져나갈 틈이 남는다
	if _clear_side < 0.0 and info["x0"] < -LANE_HALF + CLEAR_W:
		_align(info, -LANE_HALF + CLEAR_W, 1.0)
	elif _clear_side > 0.0 and info["x1"] > LANE_HALF - CLEAR_W:
		_align(info, LANE_HALF - CLEAR_W, -1.0)
	# 출발 직후(40m 안) 뒤집힌 차는 정중앙을 막지 않게 옆으로 밀어낸다 (2026-09-30 피드백: 시작하자마자 정면에 뒤집힌 차)
	if pose == "flipped" and d < START_CLEAR and info["x0"] < START_GAP and info["x1"] > -START_GAP:
		var sd := signf(info["x"]) if absf(info["x"]) > 0.01 else _side()
		_align(info, sd * START_GAP, sd)
	obstacles.append(info["ob"])
	return info


# 실제 차지한 범위를 잰다: x0·x1(좌우 끝), 그리고 미리보기 회피용 기록
func _measure(info: Dictionary) -> void:
	var node: Node3D = info["node"]
	var box: AABB = node.transform * _local_aabb(node)
	info["x0"] = box.position.x
	info["x1"] = box.end.x
	info["x"] = box.get_center().x
	var ob: Dictionary = info.get("ob", {})
	ob["z"] = -box.get_center().z
	ob["x"] = box.get_center().x
	ob["half_width"] = box.size.x * 0.5
	ob["half_depth"] = box.size.z * 0.5
	info["ob"] = ob


# 차의 한쪽 끝을 edge 에 맞춘다: dir = -1 이면 차가 edge 왼쪽(오른쪽 끝 = edge), +1 이면 오른쪽(왼쪽 끝 = edge)
func _align(info: Dictionary, edge: float, dir: float) -> void:
	var node: Node3D = info["node"]
	node.position.x += (edge - info["x1"]) if dir < 0.0 else (edge - info["x0"])
	_measure(info)


# 모양의 가장 낮은 점을 땅(y = 0)에 맞춘다 (살짝 파묻어 틈이 안 보이게)
func _ground(node: Node3D) -> void:
	var box: AABB = node.transform * _local_aabb(node)
	node.position.y -= box.position.y + 0.04


func _scene_camp(cx: float, d: float) -> void:
	# 버려진 피난민 캠프: 상자·가방 더미 + 불타는 드럼통
	_crate_pile(Vector3(cx, 0, -d))
	obstacles.append({"z": d, "x": cx, "half_width": 1.4})
	_burning_drums(Vector3(cx + signf(cx) * 1.6, 0, -(d + 2.4)), _rng.randi_range(2, 3))
	obstacles.append({"z": d + 2.4, "x": cx + signf(cx) * 1.6, "half_width": 1.1})
	_spawn("v2_tire", Vector3(cx - signf(cx) * 1.2, 0, -(d - 1.8)), _rng.randf() * 360.0)
	_spawn("drum_pile_01", Vector3(cx - signf(cx) * 0.4, 0, -(d + 4.2)), _rng.randf() * 360.0)   # 드럼통 무더기
	obstacles.append({"z": d + 4.2, "x": cx - signf(cx) * 0.4, "half_width": 1.1})


func _scene_rubble(cx: float, d: float) -> void:
	# 무너진 잔해 더미 (돌·나무·쓰레기가 겹친 언덕)
	_obstacle("v2_rubble_stone", cx, d, _rng.randf() * 360.0, 1.6)
	_spawn("v2_rubble_wood", Vector3(cx + signf(cx) * 1.2, 0, -(d + 1.5)), _rng.randf() * 360.0)
	_spawn("v2_trash", Vector3(cx - signf(cx) * 0.8, 0, -(d - 1.6)), _rng.randf() * 360.0)


func _scene_barricade(cx: float, d: float) -> void:
	# 목표 근처 검문소 흔적: 방어벽 2-3개 + 철조망 한 장
	for k in _rng.randi_range(2, 3):
		var x := cx + signf(cx) * k * 1.3
		_spawn("v2_barrier", Vector3(x, 0, -(d + _rng.randf_range(-0.4, 0.4))), _rng.randf_range(-15, 15))
		obstacles.append({"z": d, "x": x, "half_width": 0.9})
	_chainlink_panel(Vector3(cx + signf(cx) * 2.0, 0, -(d + 3.0)), 90.0 + _rng.randf_range(-20, 20))


func _scene_bus(d: float) -> void:
	# 스쿨버스가 비스듬히 누워 왼쪽 절반을 막는다 (콘셉트 2번째 장면)
	_spawn("v2_bus", Vector3(-4.6, 0, -d), 72.0)
	obstacles.append({"z": d, "x": -4.0, "half_width": 3.6})
	_burning_drums(Vector3(1.8, 0, -(d - 6.0)), 2)
	obstacles.append({"z": d - 6.0, "x": 1.8, "half_width": 1.0})


# ── 충돌 (2026-09-30): 달리는 폭 근처의 차·소품은 전부 막힌다 ─────────────
# 비유: 보이는 물건마다 투명한 상자를 씌운다. 상자는 모델을 따라 돌아가서 비스듬한 차도 모양대로 막는다.
# 나무·그루터기는 달리는 폭(±6m) 밖에만 있어 플레이어가 닿지 않는다 → 상자를 씌우지 않는다 (성능)
const COLLIDE_X := LANE_HALF + 3.0


func _build_colliders() -> void:
	# 미리보기 자동 회피(obstacles)도 손대중 크기 대신 실제 충돌 상자로 다시 채운다
	# (잔해 더미가 기록보다 4m 넓어서, 없는 틈으로 파고들어 멈춘 일이 있었다 2026-09-30)
	obstacles.clear()
	for c in get_children():
		var node := c as Node3D
		if node == null or absf(node.position.x) > COLLIDE_X:
			continue
		if node.has_meta("chainlink"):                    # 철조망 한 장 (얇은 판)
			_box_collider(node, AABB(Vector3(-1.6, 0.0, -0.06), Vector3(3.3, 2.2, 0.12)))
			continue
		if node.scene_file_path.is_empty():
			continue
		var n := node.scene_file_path.get_file().get_basename()
		if n.begins_with("tree_") or n.begins_with("stump_") or n.begins_with("v2_bridge"):
			continue
		var box := _local_aabb(node)
		if box.size.y < 0.08:                             # 납작한 것(바닥 쓰레기)은 밟고 지나간다
			continue
		_box_collider(node, box)

	for w in _walls:
		_add_ob(w)


# 모델(node) 좌표계의 상자로 충돌을 만든다 → 모델이 돌아가 있으면 상자도 같이 돌아간다
func _box_collider(node: Node3D, box: AABB) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	shape.shape = bs
	shape.position = box.get_center()
	body.add_child(shape)
	node.add_child(body)
	_colliders += 1
	_add_ob(node.transform * box)


func _wall_box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.position = center
	add_child(body)
	_walls.append(AABB(center - size * 0.5, size))


var _walls: Array[AABB] = []


func _add_ob(box: AABB) -> void:
	if absf(box.get_center().x) - box.size.x * 0.5 > LANE_HALF:
		return                                            # 달리는 폭 밖이면 피할 필요 없다
	obstacles.append({"z": -box.get_center().z, "x": box.get_center().x, "half_width": box.size.x * 0.5, "half_depth": box.size.z * 0.5,
		"top": box.end.y})                                # 높이: 낮은 것(타이어·가방 등)은 자동 점프로 넘는다


# ── 먼 산 배경막 (반지름 180m 원통, 카메라를 따라감) ────────────────
var _backdrop: MeshInstance3D


func _build_backdrop() -> void:
	if "backdrop" in _perf_off: return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := 180.0
	var top := 150.0          # 원통 위·아래 높이: 그림의 산 능선이 지평선 위 약 6-12°에 오도록 맞춘 값
	var bottom := -70.0
	for i in 64:
		var a0 := -PI / 2.0 + TAU * i / 64.0
		var a1 := -PI / 2.0 + TAU * (i + 1) / 64.0
		var pts := [Vector3(sin(a0) * r, top, -cos(a0) * r), Vector3(sin(a1) * r, top, -cos(a1) * r),
			Vector3(sin(a1) * r, bottom, -cos(a1) * r), Vector3(sin(a0) * r, bottom, -cos(a0) * r)]
		var uvs := [Vector2(i / 64.0, 0), Vector2((i + 1) / 64.0, 0), Vector2((i + 1) / 64.0, 1), Vector2(i / 64.0, 1)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[k])
			st.add_vertex(pts[k])
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/stage/backdrop.gdshader")
	mat.set_shader_parameter("panorama", load("res://assets/textures/v2/backdrop_pano.png"))
	mat.set_shader_parameter("fog_color", FOG_NEAR)
	_backdrop = MeshInstance3D.new()
	_backdrop.mesh = st.commit()
	_backdrop.material_override = mat
	_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_backdrop)


# ── 나무 사이 안개 판 (대기감) ────────────────────────────────────
# 모바일 렌더러는 입체 안개가 없어서, 옅은 안개 그림을 크게 세워 숲 사이에 층을 만든다.
# 가까이 오면(5-16m) 스르르 사라지고 멀면(70-95m) 흐려져서 화면을 덮거나 튀어나오지 않는다 (mist.gdshader)
var _mist_mesh: QuadMesh


func _build_mist() -> void:
	if "mist" in _perf_off: return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/stage/mist.gdshader")
	mat.set_shader_parameter("mist_tex", load("res://assets/textures/v2/mist.png"))
	mat.set_shader_parameter("mist_color", FOG_NEAR.lightened(0.25))
	_mist_mesh = QuadMesh.new()
	_mist_mesh.size = Vector2(1.0, 1.0)
	_mist_mesh.center_offset = Vector3(0, 0.5, 0)
	_mist_mesh.material = mat
	# 안개 "줄": 달리는 방향을 가로질러 14-24m마다 한 줄씩 세운다.
	# 줄과 줄 사이에 나무가 끼어서 "나무 - 안개 - 나무 - 안개" 층이 생기고, 멀수록 겹쳐 짙어진다.
	# 줄마다 비는 틈을 두어 안개가 군데군데 벗겨진 곳으로 먼 숲·산이 보이게 한다.
	var d := 8.0
	while d < STAGE_LENGTH + 60.0:
		d += _rng.randf_range(14.0, 24.0)
		var gap := _rng.randf_range(-30.0, 30.0)              # 이 줄에서 안개가 벗겨진 곳
		var x := -46.0
		while x < 46.0:
			var w := _rng.randf_range(16.0, 28.0)
			var cx := x + w * 0.5
			x += w * _rng.randf_range(0.55, 0.8)                # 판끼리 조금씩 겹친다
			if absf(cx - gap) < 9.0:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = _mist_mesh
			mi.position = Vector3(cx, _rng.randf_range(-0.8, 0.2), -(d + _rng.randf_range(-2.0, 2.0)))
			mi.scale = Vector3(w, _rng.randf_range(2.5, 5.0), 1.0)   # 낮게: 높으면 나무 밑동을 덮어 잘려 보인다
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 95.0
			add_child(mi)


# 길옆(달리는 폭 바로 밖)의 3D 폐차: 장애물로 쓰고 남은 차를 고르게 둔다. 무거운 스캔 폐차는 15%만 (성능)
func _build_wrecks_3d() -> void:
	if "wrecks" in _perf_off: return
	var n := CAR_ROADSIDE + _car_budget
	_car_budget = 0
	for i in n:
		var wd := 25.0 + (STAGE_LENGTH - 45.0) * (i + _rng.randf_range(0.1, 0.9)) / n
		if wd > RIVER_Z0 - 14.0 and wd < RIVER_Z1 + 10.0:
			wd = RIVER_Z1 + 10.0 + _rng.randf() * 20.0
		var x := _side() * _rng.randf_range(LANE_HALF + 1.5, 11.0)
		var pool: Array = WRECKS_SCAN if _rng.randf() < 0.15 else WRECKS_LIGHT
		var node := _spawn(_pick_distinct(pool, x, wd), Vector3(x, 0, -wd), _rng.randf() * 360.0, 1.0, true, TREE_3D_RANGE)
		if _rng.randf() < 0.2:
			node.rotation_degrees.z = 180.0
			_ground(node)
		else:
			_settle(node)
		_cars_placed += 1


# 폐차를 땅에 앉힌다: 옆으로 눕히면 모델 축이 제각각이라 한쪽이 솟아 중력을 무시한 것처럼 보였다
# → 눕히지 않고 최대 2.5°만 기울이고, 기울어서 뜨는 만큼 땅에 묻는다
func _settle(node: Node3D) -> void:
	var tilt_x := _rng.randf_range(-2.5, 2.5)
	var tilt_z := _rng.randf_range(-2.5, 2.5)
	node.rotation_degrees.x = tilt_x
	node.rotation_degrees.z = tilt_z
	var box := _local_aabb(node)
	var lift := 0.5 * (box.size.z * absf(sin(deg_to_rad(tilt_x))) + box.size.x * absf(sin(deg_to_rad(tilt_z))))
	node.position.y -= lift + 0.05


func _local_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var t := node.global_transform.affine_inverse() * m.global_transform
		var b := t * m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _obstacle(model: String, x: float, d: float, yaw: float, hw: float) -> void:
	_spawn(model, Vector3(x, 0, -d), yaw)
	obstacles.append({"z": d, "x": x, "half_width": hw})


func _crate_pile(pos: Vector3) -> void:
	for k in _rng.randi_range(2, 4):
		var off := Vector3(_rng.randf_range(-0.8, 0.8), 0, _rng.randf_range(-0.6, 0.6))
		var c := _spawn("v2_crate", pos + off, _rng.randf() * 360.0)
		if k == 3:
			c.position.y = 0.7
	for k in _rng.randi_range(1, 2):
		_spawn(["v2_suitcase_red", "v2_suitcase_blue"][_rng.randi() % 2], pos + Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(0.8, 1.4)), _rng.randf() * 360.0)


func _roadside_litter(d: float) -> void:
	# 달리는 폭 가장자리 바깥의 작은 잡동사니 — 장애물은 아님 (드문드문)
	for k in _rng.randi_range(0, 2):
		var x := _side() * _rng.randf_range(LANE_HALF + 0.5, LANE_HALF + 5.0)
		var model: String = ["v2_tire", "v2_suitcase_red", "v2_suitcase_blue", "v2_crate", "v2_trash"][_rng.randi() % 5]
		_spawn(model, Vector3(x, 0, -(d + _rng.randf_range(-10, 10))), _rng.randf() * 360.0, _rng.randf_range(0.8, 1.1))


# ── 그림 카드 소품 (폐차 무더기·나무·그루터기) ─────────────────────
# 테스트 결과(2026-09-29): 12m 밖에서는 자연스럽고 5m 안에서는 떠 보이고 평면 티가 난다
# → 카드는 원거리(달리는 폭 중심에서 12m 밖) 전용. 근거리 폐차·나무는 3D 에셋으로 채운다
const CARD_MIN_X := 10.0      # 카드는 원거리 전용: 5m 안은 평면 티가 난다 (2026-09-29 근거리 테스트). 12 → 10: 가운데 쪽으로
const CARD_FAR_X := 60.0      # 카드 나무는 옆으로 60m까지 — 안개 너머 실루엣이 겹겹이 보여 깊이감(Z 뎁스)을 만든다
const CARD_RANGE := 105.0     # 카드는 가벼워서 3D 모델보다 멀리까지 그린다 (120 → 105: 폰 FPS)


func _build_card_props() -> void:
	if "cards" in _perf_off: return
	var d0 := 0.0
	while d0 < STAGE_LENGTH:
		for i in 72 * TREE_PACK:                          # 나무 카드 (500m 압축: 수 유지 → 조각마다 2배) (크기 랜덤) — 40%는 가까운 쪽, 나머지는 멀리 (96 → 72: 폰 FPS)
			var tx := _side() * (_rng.randf_range(CARD_MIN_X, 24.0) if _rng.randf() < 0.4 else lerpf(24.0, CARD_FAR_X, _rng.randf()))
			var td := d0 + _rng.randf() * CHUNK
			_card_at(_pick_card(CardProps.TREES, tx, td), tx, td, _rng.randf_range(0.5, 1.6), true)
		for i in 8 * TREE_PACK:                           # 그루터기·잔가지 더미·뿌리
			var gx := _side() * _rng.randf_range(CARD_MIN_X, 22.0)
			var gd := d0 + _rng.randf() * CHUNK
			_card_at(_pick_card(CardProps.GROUND, gx, gd), gx, gd, _rng.randf_range(0.8, 1.2), true)
		d0 += CHUNK
	var d := 30.0
	while d < STAGE_LENGTH - 10.0:                        # 폐차 무더기: 2-4대가 모여 있다
		var side := _side()
		var cx := side * _rng.randf_range(CARD_MIN_X + 3.0, 28.0)
		for k in _rng.randi_range(3, 6):
			var vx := cx + _rng.randf_range(-8, 8)
			var vd := d + _rng.randf_range(-7, 7)
			_card_at(_pick_card(CardProps.VEHICLES, vx, vd), vx, vd, _rng.randf_range(0.95, 1.05), false)
		d += _rng.randf_range(20.0, 35.0) * DS          # 500m 압축: 폐차 카드 수 유지
	var fd := 15.0
	while fd < STAGE_LENGTH:                              # 바깥쪽(28-58m) 폐차 카드: 멀리 흩어진 폐차장 느낌
		fd += _rng.randf_range(25.0, 45.0) * DS
		var fx := _side() * _rng.randf_range(28.0, CARD_FAR_X - 2.0)
		for k in _rng.randi_range(1, 3):
			var vx2 := fx + _rng.randf_range(-6, 6)
			var vd2 := fd + _rng.randf_range(-6, 6)
			_card_at(_pick_card(CardProps.VEHICLES, vx2, vd2), vx2, vd2, _rng.randf_range(0.95, 1.1), false)


# 같은 그림이 가까이(14m 안) 이미 있으면 다른 그림으로 다시 고른다 → 반복이 눈에 띄지 않게
const SAME_CARD_GAP := 14.0
var _placed_cards := {}          # 20m 칸 번호 → [[x, d, 이름], ...]


func _pick_card(pool: Array, x: float, d: float) -> String:
	return _pick_distinct(pool, x, d)


# 같은 이름(카드·3D 모델)이 gap 안에 있으면 다른 것으로 다시 고른다
func _pick_distinct(pool: Array, x: float, d: float, gap := SAME_CARD_GAP) -> String:
	var pick: String = pool[_rng.randi() % pool.size()]
	for attempt in 8:
		if not _card_nearby(pick, x, d, gap):
			break
		pick = pool[_rng.randi() % pool.size()]
	var key := int(d / 20.0)
	if not _placed_cards.has(key):
		_placed_cards[key] = []
	_placed_cards[key].append([x, d, pick])
	return pick


func _card_nearby(card_name: String, x: float, d: float, gap := SAME_CARD_GAP) -> bool:
	var key := int(d / 20.0)
	var reach := int(ceil(gap / 20.0))
	for k in range(key - reach, key + reach + 1):
		for e in _placed_cards.get(k, []):
			if e[2] == card_name and Vector2(e[0] - x, e[1] - d).length() < gap:
				return true
	return false


func _card_at(card_name: String, x: float, d: float, scale_f: float, may_flip: bool) -> void:
	if d > RIVER_Z0 - 12.0 and d < RIVER_Z1 + 4.0:
		return
	if d > STAGE_LENGTH + 5.0:
		return
	if absf(x) < CARD_MIN_X:                              # 원거리 전용
		x = signf(x if x != 0.0 else 1.0) * (CARD_MIN_X + _rng.randf() * 3.0)
	var mi := _card_props.make(card_name, scale_f)
	mi.position = Vector3(x, 0, -d)
	if may_flip and _rng.randf() < 0.5:
		mi.scale.x = -mi.scale.x                          # 좌우 뒤집어 같은 그림 반복을 숨긴다
	mi.visibility_range_end = CARD_RANGE
	mi.set_instance_shader_parameter("variation", [Vector3(1.1, 0.97, 0.88), Vector3(0.92, 0.96, 1.05), Vector3(0.8, 0.8, 0.84), Vector3(1.0, 1.0, 1.0)][_rng.randi() % 4]
		* (0.6 if card_name in CardProps.GROUND else 1.0))   # 그루터기·뿌리 카드는 원래 색이 밝은 베이지라 어둡게 (튀어 보였다)
	mi.visibility_range_end_margin = 0.0                  # 흩어짐은 셰이더 디더가 100-120m에서 처리
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ── 불타는 드럼통 (불꽃·연기 입자 + 깜빡이는 주황 조명) ─────────────
const DRUMS_3D := ["drum_oil_01", "drum_oil_02", "drum_old_01", "drum_explosive", "barrel_pack_01", "barrel_pack_02",
	"barrel_pack_03", "barrel_pack_04", "barrel_pack_05"]


func _burning_drums(pos: Vector3, count: int) -> void:
	for k in count:
		var off := Vector3(_rng.randf_range(-0.9, 0.9), 0, _rng.randf_range(-0.9, 0.9))
		var drum := _spawn(_pick_distinct(DRUMS_3D, pos.x + off.x, -(pos.z + off.z), 3.0), pos + off, _rng.randf() * 360.0)
		if k == count - 1 and count > 2:                 # 하나는 쓰러짐
			drum.rotation_degrees.z = 90.0
			drum.position.y = 0.3
		elif k == 0:
			_fire(drum.position + Vector3(0, 0.78, 0))


func _fire(at: Vector3) -> void:
	if "fire" in _perf_off: return
	var fire := GPUParticles3D.new()
	fire.amount = 26
	fire.lifetime = 0.7
	fire.position = at
	fire.process_material = _fire_process(Vector3(0, 1.4, 0), 0.25, Color(1.0, 0.75, 0.35), Color(0.9, 0.25, 0.05, 0.0), 0.35, 0.8)
	fire.draw_pass_1 = _particle_quad("fire.png", 0.55, true)
	fire.visibility_range_end = DRAW_RANGE
	add_child(fire)
	var smoke := GPUParticles3D.new()
	smoke.amount = 12
	smoke.lifetime = 3.2
	smoke.position = at + Vector3(0, 0.4, 0)
	smoke.process_material = _fire_process(Vector3(0.15, 0.6, 0), 0.15, Color(0.4, 0.42, 0.45, 0.45), Color(0.4, 0.42, 0.45, 0.0), 1.0, 3.2)
	smoke.draw_pass_1 = _particle_quad("smoke.png", 1.0, false)
	smoke.visibility_range_end = DRAW_RANGE
	add_child(smoke)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 2.0
	light.omni_range = 7.0
	light.position = at + Vector3(0, 0.6, 0)
	light.distance_fade_enabled = true
	light.distance_fade_begin = 40.0
	light.distance_fade_length = 10.0
	add_child(light)
	_fires.append(light)


func _fire_process(vel: Vector3, radius: float, c0: Color, c1: Color, s0: float, s1: float) -> ParticleProcessMaterial:
	var p := ParticleProcessMaterial.new()
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = vel.normalized()
	p.spread = 12.0
	p.initial_velocity_min = vel.length() * 0.7
	p.initial_velocity_max = vel.length() * 1.2
	p.gravity = Vector3.ZERO
	p.scale_min = s0
	p.scale_max = s0 * 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1, s1 / s0 if s1 > s0 else 0.3))
	var ct := CurveTexture.new()
	ct.curve = curve
	p.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, c0)
	grad.set_color(1, c1)
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	p.color_ramp = gt
	return p


func _particle_quad(tex: String, size: float, additive: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/v2/" + tex)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	if additive:
		mat.albedo_color = Color(2.2, 1.6, 1.2)      # 빛나 보이게 (글로우 문턱 넘김)
	q.material = mat
	return q


# ── 철조망·투광등 ────────────────────────────────────────────────
func _chainlink_panel(pos: Vector3, yaw: float) -> void:
	var node := Node3D.new()
	node.position = pos
	node.rotation_degrees.y = 90.0 + yaw
	node.set_meta("chainlink", true)                     # 충돌 상자 대상 (_build_colliders)
	add_child(node)
	var quad := QuadMesh.new()
	quad.size = Vector2(3.2, 2.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/v2/chainlink.png")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.uv1_scale = Vector3(3.2, 2.2, 1)
	quad.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.position.y = 1.1
	mesh.visibility_range_end = DRAW_RANGE
	node.add_child(mesh)
	var post := CylinderMesh.new()
	post.top_radius = 0.04
	post.bottom_radius = 0.04
	post.height = 2.4
	post.material = _mats._material_for(_named_mat("metal_dark", Color(0.06, 0.06, 0.07)))
	var pm := MeshInstance3D.new()
	pm.mesh = post
	pm.position = Vector3(1.6, 1.2, 0)
	pm.visibility_range_end = DRAW_RANGE
	node.add_child(pm)


func _floodlight(pos: Vector3) -> void:
	_spawn("v2_floodlight", pos, 0.0, 1.0, true, 160.0)
	var spot := SpotLight3D.new()
	spot.position = pos + Vector3(0, 14.3, 0.6)
	spot.rotation_degrees = Vector3(-35, 0, 0)          # 길 쪽(+Z)을 비스듬히 비춤
	spot.light_color = Color(0.9, 0.95, 1.0)
	spot.light_energy = 3.0
	spot.spot_range = 70.0
	spot.spot_angle = 32.0
	add_child(spot)


# ── 공통 도우미 ──────────────────────────────────────────────────
func _spawn(model: String, pos: Vector3, yaw_deg: float = 0.0, scale_f: float = 1.0, cull := true, range_end := DRAW_RANGE) -> Node3D:
	model = LICENSE_SWAP.get(model, model)
	if not _scenes.has(model):
		_scenes[model] = load(ModelLibrary.path(model))   # 카테고리 폴더에서 이름으로 찾는다
	var node: Node3D = _scenes[model].instantiate()
	node.position = pos
	node.rotation_degrees.y = yaw_deg
	node.scale = Vector3.ONE * scale_f
	add_child(node)
	if model.begins_with("v2_"):                          # 직접 만든 Blender 모델만 질감을 입힌다 (구해 온 에셋은 원래 텍스처 유지)
		_mats.apply(node)
	if cull:
		for child in node.find_children("*", "GeometryInstance3D", true, false):
			var g := child as GeometryInstance3D
			g.visibility_range_end = range_end
			g.visibility_range_end_margin = 8.0                     # 사라질 때 8m 동안 점점 흩어지며 (튀어나오지 않게)
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return node


func _mesh_node(mesh: Mesh, pos: Vector3, shadow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _named_mat(name: String, color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_color = color
	return m


func _zone(d: float) -> int:
	return clampi(int(d / (STAGE_LENGTH / 5.0)), 0, 4)


func _side() -> float:
	return -1.0 if _rng.randf() < 0.5 else 1.0

# 스테이지 v2 (1,000m) — 새 콘셉트: 분홍 노을 + 청회색 안개 + 앙상한 숲 + 폐허 마을 — 주인: A
#
# 비유: 1km 세트장을 짓지 않고 부품(Blender 소품 34종) + 배치 규칙 + 하늘 그림으로 "눈앞 50m만 진짜처럼".
#
# 구간 (콘셉트 표지판 그대로)
#   0m   START             폐차·불타는 드럼통·쓰레기, 외곽 주택
#   200m DENSE WOODS       빽빽한 앙상한 숲, 스쿨버스, 여행가방
#   400m VILLAGE CENTER    길 양옆 목조 주택가, 급수탑, 노점
#   600m BROKEN BRIDGE     강 + 부서진 다리 (길은 다리 위로), 물에 잠긴 차
#   800m PATH TO OBJECTIVE 철조망, 철탑, 모닥불 드럼통, 1,000m 요새 성벽·투광등
#
# 좌표: 카메라는 -Z 방향으로 달린다. x = 0 이 길 가운데. 거리 d(양수) → z = -d
class_name StageBuilderV2
extends Node3D

const STAGE_LENGTH := 1000.0
const LANE_HALF := 6.0                # 이동 가능 폭 ±6m (PRD F-07)
const ROAD_HALF := 2.2
const WORLD_HALF := 48.0
const CHUNK := 50.0
const DRAW_RANGE := 68.0              # 이보다 먼 것은 그리지 않음 (안개가 이미 가림)
const RIVER_Z0 := 680.0               # 강 (거리 기준)
const RIVER_Z1 := 720.0

# 안개·하늘: 앞쪽(분홍 노을) → 뒤쪽(무거운 회색)으로 점점 바뀐다
const FOG_NEAR := Color8(88, 96, 110)     # tools/assets/make_stage_textures_v2.py FOG 와 같은 값
const FOG_FAR := Color8(98, 102, 110)
const M := "res://assets/models/v2/"
const SIGNS := [[0.0, "0m ->\nSTART"], [200.0, "200m ->\nDENSE\nWOODS"], [400.0, "400m ->\nVILLAGE\nCENTER"],
	[600.0, "600m ->\nBROKEN\nBRIDGE"], [800.0, "800m ->\nPATH TO\nOBJECTIVE"]]

var obstacles: Array[Dictionary] = []   # 미리보기 카메라 회피용: {z(양수 거리), x, half_width}
var _rng := RandomNumberGenerator.new()
var _scenes := {}
var _mats := StageMaterials.new()
var _env: Environment
var _fires: Array[OmniLight3D] = []
var _t := 0.0


func build(seed_value: int = 20260929) -> void:
	_rng.seed = seed_value
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
	print("[stage v2] obstacles=%d fires=%d" % [obstacles.size(), _fires.size()])


func _process(delta: float) -> void:
	_t += delta
	for i in _fires.size():            # 불빛 깜빡임
		_fires[i].light_energy = 2.0 + sin(_t * 13.0 + i) * 0.35 + sin(_t * 23.0 + i * 2.0) * 0.25


# 달린 거리에 따라 안개·하늘을 바꾼다 (600m 이후 회색으로 무거워짐 — 콘셉트 4·5번째 장면)
func update_atmosphere(dist: float) -> void:
	var t := smoothstep(480.0, 760.0, dist)
	_env.fog_light_color = FOG_NEAR.lerp(FOG_FAR, t)
	_env.fog_sky_affect = lerpf(0.25, 0.6, t)
	_env.fog_depth_end = lerpf(66.0, 56.0, t)


# ── 환경 ──────────────────────────────────────────────────────────
func _build_environment() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/textures/v2/sky_ph.png")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color8(96, 104, 116)
	_env.ambient_light_energy = 0.75
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.1
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_light_color = FOG_NEAR
	_env.fog_depth_begin = 4.0
	_env.fog_depth_end = 66.0
	_env.fog_depth_curve = 1.7
	_env.fog_sun_scatter = 0.06
	_env.fog_sky_affect = 0.3
	_env.fog_height = 1.0                   # 땅에 깔리는 안개
	_env.fog_height_density = 0.12
	_env.glow_enabled = true                # 불빛·투광등 번짐
	_env.glow_intensity = 0.8
	_env.glow_bloom = 0.12
	_env.glow_hdr_threshold = 0.9
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.18
	_env.adjustment_saturation = 0.92
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	var sun := DirectionalLight3D.new()    # 먼 앞쪽의 낮은 노을빛 → 물체가 역광 실루엣
	sun.light_color = Color(1.0, 0.72, 0.66)
	sun.light_energy = 0.7
	sun.rotation_degrees = Vector3(-12, 180, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)


func _build_ground_and_river() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/stage/ground_v2.gdshader")
	mat.set_shader_parameter("road_half", ROAD_HALF)
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
		_mesh_node(bank, Vector3(0, -1.52, z), false)


# ── 풀·덤불·나무 (50m 조각마다) ──────────────────────────────────────
func _build_vegetation_chunk(d0: float) -> void:
	var zone := _zone(d0 + CHUNK * 0.5)
	_grass_multimesh(d0, 4200, "grass_v2.png", Vector2(1.1, 1.0))
	_grass_multimesh(d0, [260, 700, 120, 220, 160][zone], "bush_v2.png", Vector2(1.8, 1.6))
	var trees_per_side: int = [5, 16, 2, 5, 3][zone]
	var near: float = [14.0, 8.0, 20.0, 12.0, 16.0][zone]
	for side in [-1.0, 1.0]:
		for i in trees_per_side:
			var d := d0 + _rng.randf() * CHUNK
			if d > RIVER_Z0 - 4.0 and d < RIVER_Z1 + 4.0:
				continue
			var x: float = side * _rng.randf_range(near, WORLD_HALF)
			var tree: String = ["v2_tree_a", "v2_tree_b", "v2_tree_c", "v2_tree_d"][_rng.randi() % 4]
			_spawn(tree, Vector3(x, 0, -d), _rng.randf() * 360.0, _rng.randf_range(0.55, 0.95))


func _grass_multimesh(d0: float, count: int, tex: String, size: Vector2) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _card_mesh(tex, size)
	mm.instance_count = count
	for i in count:
		var x := _rng.randf_range(-WORLD_HALF, WORLD_HALF)
		var d := d0 + _rng.randf() * CHUNK
		var s := _grass_scale(absf(x))
		if d > RIVER_Z0 - 1.0 and d < RIVER_Z1 + 1.0:
			s = 0.0001                                             # 강 위에는 풀 없음
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.25), s))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, 0, -d)))
		var shade := _rng.randf_range(0.55, 1.0)
		mm.set_instance_color(i, Color(shade, shade, shade * 1.05))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = DRAW_RANGE + CHUNK
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _grass_scale(ax: float) -> float:
	if ax < ROAD_HALF:
		return 0.0001 if _rng.randf() < 0.9 else _rng.randf_range(0.25, 0.4)
	if ax < LANE_HALF:
		return _rng.randf_range(0.3, 0.6) if _rng.randf() < 0.7 else 0.0001
	if ax < LANE_HALF + 6.0:
		return _rng.randf_range(0.55, 1.0)
	return _rng.randf_range(0.75, 1.3)


var _cards := {}
func _card_mesh(tex: String, size: Vector2) -> ArrayMesh:
	if _cards.has(tex):
		return _cards[tex]
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
	mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	st.set_material(mat)
	_cards[tex] = st.commit()
	return _cards[tex]


# ── 구간별 큰 배치 ────────────────────────────────────────────────
func _build_zone_start() -> void:
	var d := 12.0
	while d < 200.0:
		var side := -1.0 if int(d / 30.0) % 2 == 0 else 1.0
		var house: String = ["v2_house_a", "v2_house_c", "v2_shack", "v2_house_b"][_rng.randi() % 4]
		_spawn(house, Vector3(side * _rng.randf_range(14.0, 24.0), 0, -d), 90.0 * side * -1.0 + _rng.randf_range(-20, 20))
		d += _rng.randf_range(24.0, 40.0)
	for d2 in [6.0, 40.0, 95.0, 150.0]:               # 길가 쓰레기 더미와 불타는 드럼통
		_burning_drums(Vector3(_side() * _rng.randf_range(6.5, 9.0), 0, -d2), _rng.randi_range(2, 3))


func _build_zone_woods() -> void:
	_spawn("v2_bus", Vector3(-10.5, 0, -305), 72.0)
	_spawn("v2_shack", Vector3(17.0, 0, -360), -110.0)
	_burning_drums(Vector3(7.5, 0, -312), 3)
	_burning_drums(Vector3(-7.0, 0, -250), 2)
	for i in 10:                                          # 부서진 나무 울타리 (길 왼쪽)
		if _rng.randf() < 0.65:
			_spawn("v2_fence", Vector3(-7.6, 0, -(215.0 + i * 3.1)), 90.0 + _rng.randf_range(-12, 12))


func _build_zone_village() -> void:
	for side in [-1.0, 1.0]:
		var d := 405.0 + _rng.randf_range(0, 6)
		while d < 595.0:
			var house: String = ["v2_house_a", "v2_house_b", "v2_house_c", "v2_house_b"][_rng.randi() % 4]
			# 정면(+Z)이 길을 보도록: 왼쪽 집은 +90°, 오른쪽 집은 -90°
			_spawn(house, Vector3(side * _rng.randf_range(11.0, 13.5), 0, -d), -90.0 * side + _rng.randf_range(-6, 6))
			d += _rng.randf_range(11.0, 15.0)
	_spawn("v2_water_tower", Vector3(22.0, 0, -470), 15.0)
	_spawn("v2_water_tower", Vector3(-26.0, 0, -575), 50.0)
	for d2 in [430.0, 470.0, 515.0, 560.0]:
		_spawn("v2_stall", Vector3(_side() * _rng.randf_range(6.8, 8.0), 0, -d2), _rng.randf_range(-30, 30) + 90.0)
		_spawn("v2_rubble_wood", Vector3(_side() * _rng.randf_range(7.0, 9.0), 0, -d2 - 12.0), _rng.randf() * 360.0)
	_burning_drums(Vector3(-6.8, 0, -500), 2)


func _build_zone_bridge() -> void:
	# 길이 이어지는 다리 (상판 윗면 = 땅 높이). 강 위 5칸 중 2칸은 오른쪽이 부서짐
	for k in 6:
		var d := RIVER_Z0 - 5.0 + k * 10.0
		var deck := "v2_bridge_deck_broken" if k == 2 or k == 3 else "v2_bridge_deck"
		_spawn(deck, Vector3(0, 0, -d), 0.0, 1.0, false)
	for k in 4:
		_spawn("v2_bridge_pillar", Vector3(0, 0, -(RIVER_Z0 + 5.0 + k * 10.0)), 0.0, 1.0, false)
	# 옆의 옛 다리: 무너져 강에 처박힌 상판 (콘셉트 4번째 장면)
	for k in 3:
		_spawn("v2_bridge_pillar", Vector3(16.0, 0, -(RIVER_Z0 + 8.0 + k * 12.0)), 0.0, 1.0, false)
	_spawn("v2_bridge_slab", Vector3(15.0, -1.6, -(RIVER_Z0 + 20.0)), 180.0, 1.0, false)
	_spawn("v2_truck", Vector3(-12.0, -1.7, -(RIVER_Z0 + 16.0)), 70.0, 1.0, false)
	_spawn("v2_car_sedan", Vector3(9.0, -1.2, -(RIVER_Z0 + 30.0)), 30.0, 1.0, false)
	for d2 in [RIVER_Z0 - 12.0, RIVER_Z1 + 10.0]:
		_burning_drums(Vector3(_side() * 7.0, 0, -d2), 3)
	for d3 in [610.0, 640.0, 760.0]:
		_spawn("v2_house_c", Vector3(_side() * _rng.randf_range(18.0, 26.0), 0, -d3), _rng.randf_range(0, 360))


func _build_zone_objective() -> void:
	for side in [-1.0, 1.0]:                              # 철조망 (길 양옆, 일부 쓰러짐)
		var d := 815.0
		while d < 995.0:
			if _rng.randf() < 0.8:
				_chainlink_panel(Vector3(side * 8.0, 0, -d), _rng.randf_range(-8, 8) + (_rng.randf_range(-25, 25) if _rng.randf() < 0.2 else 0.0))
			d += 3.2
	var pylons := [[-24.0, 840.0, 0.0], [26.0, 900.0, 11.0], [-28.0, 960.0, 0.0]]
	for p in pylons:
		var node := _spawn("v2_pylon", Vector3(p[0], 0, -p[1]), 90.0, 1.0, true, 140.0)
		node.rotation_degrees.z = p[2]
	for d2 in [830.0, 880.0, 935.0, 975.0]:
		_burning_drums(Vector3(_side() * _rng.randf_range(5.5, 7.0), 0, -d2), 3)
	# 1,000m 목표: 요새 성벽 + 문 + 투광등 (문 너머가 탈출 지점)
	var wall_d := STAGE_LENGTH + 18.0
	_spawn("v2_gate", Vector3(0, 0, -wall_d), 0.0, 1.0, true, 160.0)
	for i in range(1, 6):
		for side in [-1.0, 1.0]:
			_spawn("v2_wall", Vector3(side * (3.0 + i * 12.0), 0, -wall_d), 0.0, 1.0, true, 160.0)
	for x in [-14.0, 14.0, -34.0, 34.0]:
		_floodlight(Vector3(x, 0, -(wall_d - 3.0)))


func _build_signs() -> void:
	for s in SIGNS:
		var d: float = s[0] + (8.0 if s[0] == 0.0 else 0.0)
		var sign := _spawn("v2_sign", Vector3(3.4, 0, -d), -8.0)
		var label := Label3D.new()
		label.text = s[1]
		label.font_size = 64
		label.pixel_size = 0.0028
		label.modulate = Color(0.1, 0.1, 0.1)
		label.outline_size = 0
		label.position = Vector3(0, 1.56, 0.1)
		label.visibility_range_end = DRAW_RANGE
		sign.add_child(label)


# ── 길 위 장애물 (한쪽은 항상 비움) ─────────────────────────────────
func _build_obstacles() -> void:
	var d := 22.0
	while d < STAGE_LENGTH - 25.0:
		d += _rng.randf_range(16.0, 28.0)
		if d > RIVER_Z0 - 6.0 and d < RIVER_Z1 + 6.0:
			if absf(d - (RIVER_Z0 + RIVER_Z1) / 2.0) < 6.0:     # 다리 위에는 버려진 차 한 대만
				_obstacle("v2_car_sedan_b", -1.6, d, 8.0, 1.2)
			continue
		var x := _rng.randf_range(-4.0, 4.0)
		var zone := _zone(d)
		var roll := _rng.randf()
		if roll < [0.45, 0.2, 0.3, 0.35, 0.2][zone]:
			var car: String = ["v2_car_sedan", "v2_car_sedan_b", "v2_car_pickup"][_rng.randi() % 3]
			var yaw := _rng.randf_range(-60, 60) + (0.0 if _rng.randf() < 0.6 else 90.0)
			var node := _spawn(car, Vector3(x, 0, -d), yaw)
			if _rng.randf() < 0.2:                         # 옆으로 누운 차
				node.rotation_degrees.x = 88.0
				node.position.y = 0.9
			obstacles.append({"z": d, "x": x, "half_width": lerpf(1.0, 2.3, absf(sin(deg_to_rad(yaw))))})
		elif roll < 0.7:
			_spawn(["v2_trash", "v2_rubble_stone", "v2_rubble_wood"][_rng.randi() % 3], Vector3(x, 0, -d), _rng.randf() * 360.0)
			obstacles.append({"z": d, "x": x, "half_width": 1.6})
		else:
			_crate_pile(Vector3(x, 0, -d))
			obstacles.append({"z": d, "x": x, "half_width": 1.2})
		_roadside_litter(d)


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
	# 길가(달리는 폭 가장자리)의 작은 잡동사니 — 장애물은 아님
	for k in 3:
		var x := _side() * _rng.randf_range(5.8, 9.0)
		var model: String = ["v2_tire", "v2_suitcase_red", "v2_suitcase_blue", "v2_crate", "v2_trash"][_rng.randi() % 5]
		_spawn(model, Vector3(x, 0, -(d + _rng.randf_range(-8, 8))), _rng.randf() * 360.0, _rng.randf_range(0.8, 1.1))


# ── 불타는 드럼통 (불꽃·연기 입자 + 깜빡이는 주황 조명) ─────────────
func _burning_drums(pos: Vector3, count: int) -> void:
	for k in count:
		var off := Vector3(_rng.randf_range(-0.9, 0.9), 0, _rng.randf_range(-0.9, 0.9))
		var drum := _spawn("v2_drum", pos + off, _rng.randf() * 360.0)
		if k == count - 1 and count > 2:                 # 하나는 쓰러짐
			drum.rotation_degrees.z = 90.0
			drum.position.y = 0.3
		elif k == 0:
			_fire(drum.position + Vector3(0, 0.78, 0))


func _fire(at: Vector3) -> void:
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
	if not _scenes.has(model):
		_scenes[model] = load(M + model + ".glb")
	var node: Node3D = _scenes[model].instantiate()
	node.position = pos
	node.rotation_degrees.y = yaw_deg
	node.scale = Vector3.ONE * scale_f
	add_child(node)
	_mats.apply(node)
	if cull:
		for child in node.find_children("*", "GeometryInstance3D", true, false):
			(child as GeometryInstance3D).visibility_range_end = range_end
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
	return clampi(int(d / 200.0), 0, 4)


func _side() -> float:
	return -1.0 if _rng.randf() < 0.5 else 1.0

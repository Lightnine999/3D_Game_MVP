# 스테이지(들판 1,000m) 조립 — 주인: A (TECH_SPEC 13.1, 6.1.1 깊이감 층)
#
# 비유: 1km 세트장을 통째로 짓지 않고, 부품(Blender 소품) + 규칙(무작위 배치) + 그림(하늘 파노라마)으로
#       "눈앞 40m만 진짜처럼" 보이게 만든다. 나머지는 안개가 가려 준다.
#
# 층 구성 (TECH_SPEC 6.1.1)
#   근경 0-15m  : 3D 로우폴리 (장애물·나무·울타리·전봇대)
#   중경 15-40m : 풀 카드(MultiMesh) + 폐허, 안개로 흐려짐
#   원경 40m+  : 하늘 파노라마(2D 매트) — 폐허 도시·숲 실루엣
class_name StageBuilder
extends Node3D

const STAGE_LENGTH := 1000.0
const CHUNK_LENGTH := 50.0            # 풀·나무 배치 단위 (20조각)
const LANE_HALF := 6.0                # 이동 가능 폭 ±6m (PRD F-07)
const ROAD_HALF := 1.8                # 가운데 흙길 반폭
const SILHOUETTE_TINT := 0.45         # 외곽 폐허·나무를 어둡게 (안개 속 실루엣으로 보이게, 레퍼런스 톤)
const WORLD_HALF := 45.0              # 좌우로 보이는 세계 폭

const FOG_COLOR := Color8(122, 106, 88)   # 해질녘 세피아 안개 — tools/assets/make_stage_textures.py의 FOG와 같은 값
const FOG_BEGIN := 4.0
const FOG_END := 42.0                 # 시야 약 30-40m (PRD F-60)
const DRAW_RANGE := 48.0              # 이보다 먼 조각은 그리지 않음 (안개에 이미 가려짐)

const GRASS_PER_CHUNK := 5200

var obstacles: Array[Dictionary] = []   # 미리보기 카메라 회피용: {z, x, half_width} (z는 양수 거리)
var _rng := RandomNumberGenerator.new()
var _scenes := {}


func build(seed_value: int = 20260929) -> void:
	_rng.seed = seed_value
	_build_environment()
	_build_light()
	_build_ground()
	var grass_mesh := _make_grass_mesh()
	var grass_mat := _make_grass_material()
	for i in int(STAGE_LENGTH / CHUNK_LENGTH) + 1:
		_build_grass_chunk(i, grass_mesh, grass_mat)
	_place_obstacles()
	_place_outskirts()
	_place_power_line()
	_place_fence()


# ── 안개·하늘 ────────────────────────────────────────────────────
func _build_environment() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/textures/sky_panorama.png")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.53, 0.44)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = FOG_COLOR
	env.fog_depth_begin = FOG_BEGIN
	env.fog_depth_end = FOG_END
	env.fog_depth_curve = 1.6          # 가까운 곳은 선명, 먼 곳은 빨리 잠기게
	env.fog_sky_affect = 0.25          # 하늘 실루엣은 희미하게 보이도록
	env.fog_height = 0.6               # 지면 가까이 낮게 깔린 안개
	env.fog_height_density = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_light() -> void:
	# 지평선 너머(앞쪽)의 낮은 해질녘 빛 → 소품이 역광 실루엣으로 보이게 (레퍼런스 1·2)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(1.0, 0.76, 0.52)
	moon.light_energy = 0.9
	moon.rotation_degrees = Vector3(-14, 180, 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 35.0
	add_child(moon)


# ── 바닥 ─────────────────────────────────────────────────────────
func _build_ground() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/stage/ground.gdshader")
	mat.set_shader_parameter("road_half", ROAD_HALF)
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_HALF * 2.0 + 40.0, STAGE_LENGTH + 120.0)
	plane.material = mat
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.position = Vector3(0, 0, -STAGE_LENGTH / 2.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


# ── 풀 카드 (X자 사각형 2장, MultiMesh로 조각당 한 번에 그림) ──────
func _make_grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.7
	var h := 1.0
	for a in [0.0, PI / 2.0]:
		var dx := cos(a) * w
		var dz := sin(a) * w
		var quad := [Vector3(-dx, 0, -dz), Vector3(dx, 0, dz), Vector3(dx, h, dz), Vector3(-dx, h, -dz)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)   # 위쪽 법선: 앞뒤 면이 같은 밝기로 보이게
			st.set_uv(uvs[idx])
			st.add_vertex(quad[idx])
	return st.commit()


func _make_grass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/grass_card.png")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR   # 반투명 대신 잘라내기 (모바일 성능)
	mat.alpha_scissor_threshold = 0.5
	mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	return mat


func _build_grass_chunk(index: int, mesh: ArrayMesh, mat: StandardMaterial3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = GRASS_PER_CHUNK
	var z0 := -index * CHUNK_LENGTH
	for i in GRASS_PER_CHUNK:
		var x := _rng.randf_range(-WORLD_HALF, WORLD_HALF)
		var z := z0 - _rng.randf() * CHUNK_LENGTH
		var s := _grass_scale(absf(x))
		if s <= 0.0:
			x = signf(x + 0.001) * _rng.randf_range(LANE_HALF, WORLD_HALF)   # 흙길 위에서 뺀 풀은 바깥으로
			s = _grass_scale(absf(x))
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.3), s))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, 0, z)))
		var shade := _rng.randf_range(0.55, 1.0)
		mm.set_instance_color(i, Color(shade, shade * _rng.randf_range(0.85, 1.0), shade * 0.9))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_end = DRAW_RANGE + CHUNK_LENGTH   # 조각 중심 기준이라 조각 길이만큼 여유
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# 풀 높이: 흙길(|x|<1.8)은 비움, 달리는 폭(±6m)은 발목 높이, 바깥은 허리 높이 (시야를 가리지 않게)
func _grass_scale(ax: float) -> float:
	if ax < ROAD_HALF:
		return 0.0 if _rng.randf() < 0.9 else _rng.randf_range(0.25, 0.4)
	if ax < LANE_HALF:
		return _rng.randf_range(0.3, 0.6) if _rng.randf() < 0.7 else 0.0001
	if ax < LANE_HALF + 6.0:
		return _rng.randf_range(0.55, 0.95)
	return _rng.randf_range(0.75, 1.25)


# ── 배치 도우미 ───────────────────────────────────────────────────
func _spawn(model: String, pos: Vector3, yaw_deg: float = 0.0, scale: float = 1.0) -> Node3D:
	if not _scenes.has(model):
		_scenes[model] = load(ModelLibrary.path(model))   # 카테고리 폴더에서 이름으로 찾는다
	var node: Node3D = _scenes[model].instantiate()
	node.position = pos
	node.rotation_degrees.y = yaw_deg
	node.scale = Vector3.ONE * scale
	add_child(node)
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		(child as GeometryInstance3D).visibility_range_end = DRAW_RANGE
	if model.begins_with("prop_ruin") or model.begins_with("prop_tree") or model == "prop_power_pole":
		_tint(node, SILHOUETTE_TINT)
	elif model.begins_with("obs_"):
		_tint(node, 0.72)   # 장애물은 잘 보여야 하므로 조금만 어둡게
	return node


var _tinted := {}
func _tint(node: Node, factor: float) -> void:
	# 재질 색에 factor를 곱한 복사본으로 바꾼다 (같은 재질은 한 번만 복사)
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			if not _tinted.has(src):
				var dup := src.duplicate() as BaseMaterial3D
				dup.albedo_color = Color(src.albedo_color.r * factor, src.albedo_color.g * factor, src.albedo_color.b * factor)
				dup.roughness = 1.0
				dup.metallic = 0.0
				_tinted[src] = dup
			mi.set_surface_override_material(i, _tinted[src])


# ── 길 위: 폐차·쓰레기 더미·드럼통 (미리보기용 배치. 실제 게임은 B의 스포너가 배치) ─
func _place_obstacles() -> void:
	var z := 28.0
	while z < STAGE_LENGTH - 20.0:
		var x := _rng.randf_range(-LANE_HALF + 1.0, LANE_HALF - 1.0)
		var roll := _rng.randf()
		if roll < 0.42:
			var car := "obs_wreck_car" if _rng.randf() < 0.5 else "obs_wreck_car_b"
			var yaw := _rng.randf_range(-70, 70) + (0.0 if _rng.randf() < 0.6 else 90.0)
			_spawn(car, Vector3(x, 0, -z), yaw)
			# 차 길이 4.2m·폭 1.8m → 옆으로 누운 정도에 따라 길을 막는 반폭이 달라짐
			obstacles.append({"z": z, "x": x, "half_width": lerpf(0.9, 2.1, absf(sin(deg_to_rad(yaw))))})
		elif roll < 0.8:
			var trash := "obs_trash" if _rng.randf() < 0.5 else "obs_trash_b"
			var s := _rng.randf_range(0.9, 1.4)
			_spawn(trash, Vector3(x, 0, -z), _rng.randf() * 360.0, s)
			obstacles.append({"z": z, "x": x, "half_width": 0.8 * s})
		else:
			for k in _rng.randi_range(2, 3):
				_spawn("obs_drum", Vector3(x + _rng.randf_range(-0.8, 0.8), 0, -z + _rng.randf_range(-0.8, 0.8)), _rng.randf() * 360.0)
			obstacles.append({"z": z, "x": x, "half_width": 1.2})
		z += _rng.randf_range(16.0, 30.0)


# ── 좌우 외곽: 폐허 + 죽은 나무 ────────────────────────────────────
func _place_outskirts() -> void:
	var ruins := ["prop_ruin_a", "prop_ruin_b", "prop_ruin_c"]
	for side in [-1.0, 1.0]:
		var z := _rng.randf_range(0.0, 10.0)
		while z < STAGE_LENGTH + 30.0:
			var x: float = side * _rng.randf_range(14.0, 30.0)
			_spawn(ruins[_rng.randi() % ruins.size()], Vector3(x, 0, -z), _rng.randf_range(-25, 25) + (90.0 if side < 0 else -90.0), _rng.randf_range(0.8, 1.3))
			z += _rng.randf_range(11.0, 24.0)
		z = _rng.randf_range(0.0, 6.0)
		while z < STAGE_LENGTH + 30.0:
			var tx: float = side * _rng.randf_range(LANE_HALF + 2.5, 40.0)
			var tree := "prop_tree_dead" if _rng.randf() < 0.5 else "prop_tree_dead_b"
			_spawn(tree, Vector3(tx, 0, -z), _rng.randf() * 360.0, _rng.randf_range(0.8, 1.4))
			z += _rng.randf_range(5.0, 12.0)


# ── 전봇대 줄 + 처진 전선 (깊이 안내선, 레퍼런스 3) ──────────────────
func _place_power_line() -> void:
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.05, 0.05, 0.05)
	var x := LANE_HALF + 3.5
	var z := 5.0
	var prev := Vector3.INF
	while z < STAGE_LENGTH + 40.0:
		var tilt := _rng.randf_range(-4.0, 4.0)
		var pole := _spawn("prop_power_pole", Vector3(x, 0, -z), 90.0)
		pole.rotation_degrees.z = tilt
		var top := Vector3(x, 8.3, -z)
		if prev != Vector3.INF:
			for off in [-0.9, 0.9]:
				_wire(prev + Vector3(0, 0, off), top + Vector3(0, 0, off), wire_mat)
		prev = top
		z += 32.0


func _wire(a: Vector3, b: Vector3, mat: StandardMaterial3D) -> void:
	# 가운데가 1m 처진 전선을 두 토막으로 근사
	var mid := (a + b) / 2.0 + Vector3(0, -1.0, 0)
	for seg in [[a, mid], [mid, b]]:
		var p0: Vector3 = seg[0]
		var p1: Vector3 = seg[1]
		var box := BoxMesh.new()
		box.size = Vector3(0.03, 0.03, p0.distance_to(p1))
		box.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = DRAW_RANGE
		add_child(mi)
		mi.look_at_from_position((p0 + p1) / 2.0, p1, Vector3.UP)


# ── 왼쪽 부서진 울타리 ───────────────────────────────────────────────
func _place_fence() -> void:
	var z := 0.0
	while z < STAGE_LENGTH + 20.0:
		if _rng.randf() > 0.3:
			_spawn("prop_fence", Vector3(-LANE_HALF - 2.0, 0, -z), 90.0 + _rng.randf_range(-6, 6))
		z += 3.0

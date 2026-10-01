extends RefCounted

# This adapter reads the existing scene without changing its balance constants.
var stage: Node3D
var finished := false
var test_mode := false

func configure(game_stage: Node3D) -> void:
	stage = game_stage

func snapshot() -> Dictionary:
	var director: Node = stage.get("_showcase")
	return {
		"distance_m": minf(float(stage.get("_dist")), StageBuilderV2.STAGE_LENGTH),
		"target_distance": StageBuilderV2.STAGE_LENGTH,
		"duration_s": float(stage.get("_time")),
		"kills": int(director.get("service_gun_kills")) if director != null else 0,
		"knife_used": bool(director.get("service_knife_used")) if director != null else false,
		"bumps": int(stage.get("_bumps")),
		"grabs": int(director.get("service_grabs")) if director != null else 0,
		"ammo": int(director.get("_mag")) if director != null else 0,
		"reserve": int(director.get("_reserve")) if director != null else 0,
		"dead": bool(stage.get("_dead")),
		"test_mode": test_mode,
	}

func finish(cleared: bool, reason: String) -> Dictionary:
	if finished:
		return {}
	finished = true
	var result := snapshot()
	result["cleared"] = cleared
	result["death_reason"] = reason
	return result

func apply_settings(values: Dictionary) -> void:
	stage.set("_service_sensitivity", clampf(float(values.get("sensitivity", 1.0)), 0.5, 2.0))
	var mode := str(values.get("control_mode", "drag"))
	stage.set("_service_control_mode", "tilt" if mode == "tilt" and OS.get_name() == "Android" else "drag")
	stage.set("_service_tilt_zero", float(values.get("tilt_zero", 0.0)))

func debug_command(command: String, value: Variant) -> bool:
	if not stage.get("service_debug_enabled") or not OS.is_debug_build() or finished:
		return false
	var director: Node = stage.get("_showcase")
	if director == null or stage.get("_dead"):
		return false
	match command:
		"invulnerable":
			director.set("service_invulnerable", value == true)
		"skip":
			var distance := minf(float(stage.get("_dist")) + 200.0, StageBuilderV2.STAGE_LENGTH)
			stage.set("_dist", distance)
			var body: Node3D = stage.get("_body")
			body.position.z = -distance
			stage.call("_apply_camera", float(stage.get("_time")))
		"ammo":
			director.set("_reserve", int(director.get("_reserve")) + clampi(int(value), 1, 100))
			director.call("_refresh_ammo")
		"knife":
			director.set("_knife_left", 1)
			var icon: TextureRect = director.get("_hud_knife")
			if icon != null:
				icon.modulate = Color.WHITE
		"spawn":
			if str(value) not in ["walker", "runner", "tank", "ambusher"]:
				return false
			director.call("_spawn", str(value), "", 12.0, float(stage.get("_x")), float(stage.get("_dist")), float(stage.get("_x")))
		_:
			return false
	test_mode = true
	return true

extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, msg: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", msg)
func run() -> void:
	var stage = load("res://scenes/stage/stage_preview.tscn").instantiate()
	stage.service_managed = true
	root.add_child(stage)
	stage.set_process(false)
	stage._ui.confirm()
	stage.service_apply_settings({"sensitivity": 0.5, "control_mode": "tilt", "tilt_zero": 0.25})
	check(stage._service_sensitivity == 0.5 and stage._service_tilt_zero == 0.25 and stage._service_control_mode == "drag", "PC tilt fallback preserves sensitivity and zero")
	var width: float = root.get_visible_rect().size.x
	var touch := InputEventScreenTouch.new()
	touch.index = 3
	touch.pressed = true
	touch.position = Vector2(width * 0.75, 300)
	stage._unhandled_input(touch)
	check(stage._fire_held and stage._touch_id == 3, "right finger can fire and steer")
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = Vector2(width * 0.8, 300)
	stage._unhandled_input(drag)
	check(is_equal_approx(stage._steer_target, 0.05 * 24.0 * 0.5), "team 24m drag multiplied by service sensitivity")
	touch.index = 4
	touch.position.x = width * 0.25
	stage._unhandled_input(touch)
	check(stage._touch_id == 4 and stage._fire_held, "left finger takes movement without stopping right fire")
	touch.index = 3
	touch.pressed = false
	stage._unhandled_input(touch)
	check(not stage._fire_held and stage._touch_id == 4, "right release leaves left movement")
	var movements: Array[float] = []
	for boost in [false, true]:
		stage._body.position = Vector3.ZERO
		stage._x = 0.0
		stage._dist = 0.0
		stage._steer_target = 1.0
		stage._showcase._adren_t = 2.0 if boost else 0.0
		stage._step(0.01)
		movements.append(stage._x)
	check(is_equal_approx(movements[0], minf(8.0, stage.PLAY_STEER) * 0.5 * 0.01), "service sensitivity applies to motion")
	check(is_equal_approx(movements[1], movements[0] * stage.ADREN_SIDE), "adrenaline and sensitivity compose")
	stage.queue_free()
	await process_frame
	call_deferred("finish")

func finish() -> void:
	print("TEAM_MOBILE_SETTINGS: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

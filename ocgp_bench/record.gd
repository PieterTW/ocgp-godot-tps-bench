# OCGP route recorder.
#
# Runs the ORIGINAL TPS level (player, robots, normal input) and records at 20 Hz:
#   * the active camera's position / rotation / FOV, and
#   * the PLAYER: feet position, model facing, animation state, motion and aim,
# so bench.gd can replay the walkthrough with the character visible (third-person).
# Progress along the route is set by the frame index.
#
#   godot --path <tps-project> res://ocgp_bench/record.tscn
#
#   F9   start recording  /  stop and SAVE to res://ocgp_bench/route.ocgp
#   (closing the window while recording also saves)
#
# Tips for a good route: walk, don't shoot (shots add camera shake); keep moving at a
# steady pace; ~60-120 s covering the interesting spaces; avoid standing still or
# spinning on the spot; end near where you started if you want the loop to feel natural.
extends Node

const OUT_PATH := "res://ocgp_bench/route.ocgp"
const EVERY_N_TICKS := 3   # 60 Hz physics ticks -> 20 Hz samples

var recording := false
var samples: Array = []
var tick := 0
var label: Label
var player: Player = null
var selftest_secs := -1.0   # --selftest N: auto-record N seconds of "walk forward", save, quit (CI use)
var selftest_elapsed := 0.0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--selftest")
	if i >= 0 and i + 1 < a.size():
		selftest_secs = float(a[i + 1])

	add_child((load("res://level/level.tscn") as PackedScene).instantiate())

	var layer := CanvasLayer.new()
	label = Label.new()
	label.position = Vector2(14, 12)
	label.add_theme_font_size_override("font_size", 22)
	layer.add_child(label)
	add_child(layer)
	_update_label()

	if selftest_secs > 0.0:
		_toggle()
		Input.action_press("move_forward")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_toggle()


func _physics_process(delta: float) -> void:
	if not recording:
		return
	tick += 1
	if tick % EVERY_N_TICKS == 0:
		var cam := get_viewport().get_camera_3d()
		if player == null:
			for n in find_children("*", "CharacterBody3D", true, false):
				if n is Player:
					player = n
					break
		if cam and player:
			var t := cam.global_transform
			var q := t.basis.orthonormalized().get_rotation_quaternion()
			var f := player.global_position
			var mq := player.player_model.global_transform.basis.orthonormalized().get_rotation_quaternion()
			var aim: float = player.animation_tree.get("parameters/aim/add_amount")
			samples.append([_r(t.origin.x), _r(t.origin.y), _r(t.origin.z),
					_r(q.x), _r(q.y), _r(q.z), _r(q.w), _r(cam.fov),
					_r(f.x), _r(f.y), _r(f.z),
					_r(mq.x), _r(mq.y), _r(mq.z), _r(mq.w),
					int(player.current_animation), _r(player.motion.x), _r(player.motion.y), _r(aim)])
	_update_label()
	if selftest_secs > 0.0:
		selftest_elapsed += delta
		if selftest_elapsed >= selftest_secs:
			_toggle()
			get_tree().quit()


func _toggle() -> void:
	if recording:
		recording = false
		_save()
	else:
		samples.clear()
		tick = 0
		recording = true
	_update_label()


func _save() -> void:
	var data := {
		"version": 2,
		"hz": 60.0 / EVERY_N_TICKS,
		"fields": ["px", "py", "pz", "qx", "qy", "qz", "qw", "fov",
				"fx", "fy", "fz", "mqx", "mqy", "mqz", "mqw", "anim", "mx", "my", "aim"],
		"count": samples.size(),
		"samples": samples,
	}
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write %s (error %d). Run from the project folder, not an export." % [OUT_PATH, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(data))
	f.close()
	print("Saved %d samples (%.1f s) to %s" % [samples.size(), samples.size() / (60.0 / EVERY_N_TICKS), ProjectSettings.globalize_path(OUT_PATH)])


func _update_label() -> void:
	if recording:
		label.text = "REC  %.1f s  (%d samples)   F9 = stop & save" % [samples.size() / (60.0 / EVERY_N_TICKS), samples.size()]
		label.modulate = Color("#ff4444")
	else:
		label.text = "Not recording   F9 = start"
		label.modulate = Color("#ffffff")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and recording:
		_toggle()


func _r(v: float) -> float:
	return snappedf(v, 0.00001)

# OCGP activity baker — run ONCE after recording a route (path.json).
#
#   godot --headless --path <tps-project> res://ocgp_bench/bake.tscn -- [--robots 12] [--ahead 6.0] [--offset-min 3.5] [--route-clearance 3.0]
#
# Places red robots on open floor BESIDE the recorded route using physics ray casts against the
# level (floor under the spot, headroom, free space around, clearance from other robots), faces
# each one toward the oncoming camera, and measures how far its laser travels before hitting a wall.
# Result: res://ocgp_bench/activity.json — pure data (identical for every competitor), tied to the
# route by its sha256. bench.gd animates the robots from the frame index.
extends Node

const PATH_FILE := "res://ocgp_bench/route.ocgp"
const LEGACY_PATH_FILE := "res://ocgp_bench/path.json"
const OUT_FILE := "res://ocgp_bench/activity.ocgp"
const STATIC_LEVEL_SCRIPT := preload("res://ocgp_bench/level_static.gd")
const CYCLE_FRAMES := 600           # must match bench.gd
const MUZZLE_HEIGHT := 1.8
const MAX_LASER := 30.0
const MIN_SEPARATION := 4.0

var route_file := PATH_FILE
var robots_wanted := 12
var ahead_m := 6.0                   # robot stands this far ahead of the camera along the route
var offset_min := 3.5                # minimum sideways distance from the route (robots are big)
var route_clearance := 3.0           # robot must stay this far (horizontally) from EVERY route sample
var pos: PackedVector3Array          # ground route: the player's feet if recorded (v2), else the camera
var cam: PackedVector3Array          # camera route
var cum: PackedFloat32Array          # cumulative route length per sample
var space: PhysicsDirectSpaceState3D
var excluded: Array[RID] = []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--robots" and i + 1 < a.size():
			robots_wanted = int(a[i + 1])
		elif a[i] == "--ahead" and i + 1 < a.size():
			ahead_m = float(a[i + 1])
		elif a[i] == "--offset-min" and i + 1 < a.size():
			offset_min = float(a[i + 1])
		elif a[i] == "--route-clearance" and i + 1 < a.size():
			route_clearance = float(a[i + 1])

	if not _load_route():
		get_tree().quit(1)
		return

	var level := (load("res://level/level.tscn") as PackedScene).instantiate() as Node3D
	level.set_script(STATIC_LEVEL_SCRIPT)
	add_child(level)
	for body in level.get_node("FlyingForklifts").find_children("*", "CollisionObject3D", true, false):
		excluded.append((body as CollisionObject3D).get_rid())

	for _i in 4:
		await get_tree().physics_frame
	space = level.get_world_3d().direct_space_state
	_bake()
	get_tree().quit()


func _load_route() -> bool:
	if not FileAccess.file_exists(PATH_FILE) and FileAccess.file_exists(LEGACY_PATH_FILE):
		route_file = LEGACY_PATH_FILE
	if not FileAccess.file_exists(route_file):
		push_error("No route at %s — record one first (record.tscn)." % PATH_FILE)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(route_file))
	if typeof(parsed) != TYPE_DICTIONARY or parsed["samples"].size() < 2:
		push_error("Invalid route file.")
		return false
	var total := 0.0
	for s in parsed["samples"]:
		var c := Vector3(s[0], s[1], s[2])
		var p := Vector3(s[8], s[9], s[10]) if s.size() >= 19 else c
		if pos.size() > 0:
			total += pos[pos.size() - 1].distance_to(p)
		pos.append(p)
		cam.append(c)
		cum.append(total)
	print("Route: %d samples, %.1f m" % [pos.size(), total])
	return true


func _pos_at(u: float) -> Vector3:
	var x := clampf(u, 0.0, 1.0) * float(pos.size() - 1)
	var i := mini(int(x), pos.size() - 2)
	return pos[i].lerp(pos[i + 1], x - float(i))


func _cam_at(u: float) -> Vector3:
	var x := clampf(u, 0.0, 1.0) * float(cam.size() - 1)
	var i := mini(int(x), cam.size() - 2)
	return cam[i].lerp(cam[i + 1], x - float(i))


func _u_ahead(u: float, meters: float) -> float:
	var target := cum[clampi(int(u * float(pos.size() - 1)), 0, pos.size() - 1)] + meters
	for i in pos.size():
		if cum[i] >= target:
			return float(i) / float(pos.size() - 1)
	return 1.0


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = excluded
	return space.intersect_ray(q)


func _try_place(u: float) -> Dictionary:
	var cam_pos := _cam_at(u)
	var u_a := _u_ahead(u, ahead_m)
	var base := _pos_at(u_a)
	var tdir := _pos_at(minf(u_a + 0.004, 1.0)) - _pos_at(maxf(u_a - 0.004, 0.0))
	tdir.y = 0.0
	if tdir.length() < 0.01:
		return {}
	tdir = tdir.normalized()
	var right := Vector3(-tdir.z, 0.0, tdir.x)

	var floor_hit := _ray(base + Vector3.UP, base + Vector3.DOWN * 6.0)
	if floor_hit.is_empty():
		return {}
	var foot: Vector3 = floor_hit.position

	var best_side := 0.0
	var best_d := 0.0
	for side in [1.0, -1.0]:
		var o := foot + Vector3.UP
		var h := _ray(o, o + right * side * 8.0)
		var d := 8.0 if h.is_empty() else o.distance_to(h.position)
		if d > best_d:
			best_d = d
			best_side = side
	if best_d < offset_min + 1.5:   # need room for the robot AND some space behind it
		return {}

	var rp := foot + right * best_side * clampf(best_d * 0.55, offset_min, 6.0) + Vector3.UP
	var f2 := _ray(rp, rp + Vector3.DOWN * 3.0)
	if f2.is_empty() or absf(f2.position.y - foot.y) > 0.6:
		return {}
	rp = f2.position
	if not _ray(rp + Vector3.UP * 0.1, rp + Vector3.UP * 2.6).is_empty():
		return {}
	for k in 8:
		var ang := TAU * float(k) / 8.0
		var o := rp + Vector3.UP
		if not _ray(o, o + Vector3(sin(ang), 0.0, cos(ang)) * 0.8).is_empty():
			return {}

	# Never closer than route_clearance to the player's path OR the camera's path (the route may loop back).
	for arr in [pos, cam]:
		for p in arr:
			if Vector2(p.x - rp.x, p.z - rp.z).length() < route_clearance:
				return {}

	var to_cam := cam_pos - rp
	var yaw := atan2(to_cam.x, to_cam.z)     # the robot's front is +Z
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var muzzle := rp + Vector3.UP * MUZZLE_HEIGHT
	var lh := _ray(muzzle, muzzle + fwd * MAX_LASER)
	var laser := MAX_LASER
	var hit := Vector3.ZERO
	var has_hit := false
	if not lh.is_empty():
		laser = muzzle.distance_to(lh.position)
		hit = lh.position
		has_hit = true
	return {"pos": rp, "yaw": yaw, "laser": laser, "hit": hit, "has_hit": has_hit}


func _bake() -> void:
	var placed: Array = []
	var tries := 0
	for i in robots_wanted:
		var u0 := 0.05 + (float(i) + 0.5) / float(robots_wanted) * 0.9
		for attempt in 30:
			tries += 1
			var r := _try_place(clampf(u0 + 0.003 * float(attempt), 0.0, 1.0))
			if r.is_empty():
				continue
			var ok := true
			for q in placed:
				if (q["pos"] as Vector3).distance_to(r["pos"]) < MIN_SEPARATION:
					ok = false
					break
			if ok:
				r["phase"] = (placed.size() * 211) % CYCLE_FRAMES
				placed.append(r)
				break
	var out := []
	for r in placed:
		var p: Vector3 = r["pos"]
		var h: Vector3 = r["hit"]
		out.append({
			"pos": [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)],
			"yaw": snappedf(r["yaw"], 0.0001),
			"laser": snappedf(r["laser"], 0.01),
			"has_hit": r["has_hit"],
			"hit": [snappedf(h.x, 0.001), snappedf(h.y, 0.001), snappedf(h.z, 0.001)],
			"phase": r["phase"],
		})
	var f := FileAccess.open(OUT_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"version": 1,
		"path_sha256": FileAccess.get_sha256(route_file),
		"cycle_frames": CYCLE_FRAMES,
		"robots": out,
	}))
	f.close()
	print("Placed %d of %d robots (%d placement attempts) -> %s" % [out.size(), robots_wanted, tries, ProjectSettings.globalize_path(OUT_FILE)])

# OCGP "TPS" benchmark — FIXED number of frames, UNCAPPED frame rate.
#
# A faster GPU finishes the same N frames in less wall-clock time; the score is
# the summed sector time in ms (lower is better). Protocol mirrors 3dpoc.py:
#   {"event":"start", ...}
#   {"event":"sector","iter":1,"sector":n,"total_sectors":S,"sector_ms":x}
#   {"event":"complete","best_ms":sum,"sector_times":[...], ...}
#
# Launch (all three engine flags are REQUIRED — the run aborts if the fixed
# timestep is not in effect):
#
#   godot --path <tps-project> --disable-vsync --fixed-fps 60 --flush-stdout \
#         res://ocgp_bench/bench.tscn -- --frames 2000 --sectors 10 --warmup 300
#
# or by named preset, optionally also writing the events to a file:
#         ... -- --variant Medium --output result.txt
#
# DETERMINISM: the world state at frame k is a pure function of k.
#   * --fixed-fps 60 gives every frame the same 1/60 s delta (also drives the
#     TIME-based shaders and the CPU particles); verified at runtime.
#   * Camera pose is computed from the frame index (no input, no wall-clock).
#   * Forklift AnimationPlayer is stepped manually from the frame index.
#   * Forklift model choice and particle seeds are pinned; physics is disabled.
#   * Settings are pinned in code (the player's settings.ini is ignored).
extends Node

const LEVEL_SCENE := "res://level/level.tscn"
const STATIC_LEVEL_SCRIPT := preload("res://ocgp_bench/level_static.gd")

const RENDER_SIZE := Vector2i(1920, 1080)          # default (--res 1080p)
const RESOLUTIONS := {"720p": Vector2i(1280, 720), "1080p": Vector2i(1920, 1080), "4k": Vector2i(3840, 2160)}
# Named difficulty presets (keep in sync with "variants" in manifest.json). --variant selects one and cannot be
# combined with --frames / --sectors / --res, so a submittable run is always exactly one of these.
const VARIANTS := {
	"small": {"res": "720p", "frames": 25000, "sectors": 10},
	"medium": {"res": "1080p", "frames": 25000, "sectors": 10},
	"large": {"res": "4k", "frames": 25000, "sectors": 10},
}
const WINDOW_CAP := Vector2i(1920, 1080)            # on-screen window never exceeds this (a 4K run is shown downscaled)
const SIM_STEP := 1.0 / 60.0          # must match --fixed-fps 60
const DELTA_TOLERANCE := 1e-4
const FORKLIFT_ANIM := &"mawaru"
const FORKLIFT_ANIM_LENGTH := 30.0
const RNG_SEED := 20260101
const PARTICLE_SEED := 4242
const CAMERA_HEIGHT := 1.6            # metres above the spawn marker
# Data files use a NON-resource extension on purpose: Godot treats .json as a resource, and exported builds only
# copy non-resource files verbatim (include filter "ocgp_bench/*.ocgp"). Contents are plain JSON.
const PATH_FILE := "res://ocgp_bench/route.ocgp"   # recorded route (see record.gd); falls back to VANTAGES
const LEGACY_PATH_FILE := "res://ocgp_bench/path.json"   # older name, editor runs only

# Player character (third-person): replayed from the route file's player track.
const PLAYER_SCENE := "res://player/player.tscn"
const PLAYER_STRIP := ["ServerSynchronizer", "InputSynchronizer", "RootMotionView", "CameraBase",
		"Crosshair", "ColorRect", "FireCooldown", "BulletCache"]   # camera rig, UI overlays, multiplayer, bullets
const PLAYER_PARTICLE_SEED := 7000
const FrameStats := preload("res://ocgp_bench/frame_stats.gd")
const MAX_ANIM_RATIO := 3.0
const HUD_INTERVAL := 15      # frames between HUD text updates (keeps the overlay's own cost negligible)
const PLAYER_STATES := {0: "jump_up", 1: "jump_down", 2: "strafe", 3: "walk"}   # Player.Animations

# Activity layer: scripted red robots beside the route (placements baked by bake.gd).
const ACTIVITY_FILE := "res://ocgp_bench/activity.ocgp"
const LEGACY_ACTIVITY_FILE := "res://ocgp_bench/activity.json"
const ROBOT_SCENE := "res://enemies/red_robot/red_robot.tscn"
const BLAST_SCENE := "res://enemies/red_robot/laser/impact_effect/impact_effect.tscn"
const ROBOT_STUB := preload("res://ocgp_bench/robot_stub.gd")
const ROBOT_STRIP := ["MultiplayerSynchronizer", "RootMotionView", "PlayerDetectionArea", "Death"]  # SoundEffects stay (audio bus is muted)
const ROBOT_PARTICLE_SEED := 9000
const CYCLE_FRAMES := 600     # per-robot loop, must match bake.gd: idle -> aim up -> FIRE -> aim down
const AIM_UP_START := 150
const AIM_UP_END := 180
const SHOOT_AT := 240
const AIM_DOWN_START := 330
const AIM_DOWN_END := 360

# Camera path: one entry per sector (wraps if --sectors > entries).
# Each sector holds a vantage point and sweeps the yaw over its frames, so every
# sector samples the environment at a different place / angle.
# Positions are derived from the demo's own spawn markers (known free space).
# TODO(ocgp): replace with a hand-authored Path3D once the level is reviewed.
const VANTAGES := [
	{"name": "spawn_hall",   "pos": Vector3(64.82, -1.08 + CAMERA_HEIGHT, 78.76), "yaw": 0.0,   "sweep": 360.0, "pitch": -3.0},
	{"name": "ramp_east",    "pos": Vector3(71.59, -6.06 + CAMERA_HEIGHT, 46.27), "yaw": 90.0,  "sweep": 360.0, "pitch": 0.0},
	{"name": "mid_corridor", "pos": Vector3(53.21, -6.06 + CAMERA_HEIGHT, 15.93), "yaw": 200.0, "sweep": 360.0, "pitch": 2.0},
	{"name": "lower_west",   "pos": Vector3(-2.96, -11.69 + CAMERA_HEIGHT, 20.23), "yaw": 300.0, "sweep": 360.0, "pitch": 0.0},
	{"name": "lower_core",   "pos": Vector3(-9.16, -11.69 + CAMERA_HEIGHT, -16.92), "yaw": 45.0, "sweep": 360.0, "pitch": 4.0},
	{"name": "center_hall",  "pos": Vector3(-4.05, -1.13, 4.0),                   "yaw": 130.0, "sweep": 360.0, "pitch": 0.0},
	{"name": "mid_corridor_up", "pos": Vector3(53.21, -6.06 + CAMERA_HEIGHT, 15.93), "yaw": 20.0, "sweep": 360.0, "pitch": 12.0},
	{"name": "lower_west_dn", "pos": Vector3(-2.96, -11.69 + CAMERA_HEIGHT, 20.23), "yaw": 120.0, "sweep": 360.0, "pitch": -10.0},
	{"name": "spawn_hall_up", "pos": Vector3(64.82, -1.08 + CAMERA_HEIGHT, 78.76), "yaw": 180.0, "sweep": 360.0, "pitch": 10.0},
	{"name": "center_hall_up", "pos": Vector3(-4.05, -1.13, 4.0),                  "yaw": 310.0, "sweep": 360.0, "pitch": 8.0},
]

# In-universe sector titles, shown as a brief overlay card at the start of each sector.
# Index wraps the same way VANTAGES does. Purely cosmetic — no effect on timing or scoring.
const SECTOR_TITLES := [
	"Sector 1 : Entrance Hall",
	"Sector 2 : Eastern Ramp",
	"Sector 3 : Mid Corridor",
	"Sector 4 : Lower West Wing",
	"Sector 5 : Lower Core",
	"Sector 6 : Central Hall",
	"Sector 7 : Corridor Overlook",
	"Sector 8 : West Wing, Below",
	"Sector 9 : Entrance, Above",
	"Sector 10 : Central Hall, Above",
]
const SECTOR_TITLE_FRAMES := 90   # how long the title card stays fully visible (~1.5 s at 60 fps)
const SECTOR_TITLE_FADE_FRAMES := 30
const CREDIT_TEXT := "OCGP TPS Benchmark — © 2026 Pieter Plaisier — for benchmark use only, not for redistribution"

# ---- CLI (after the `--` separator) ----
var frames := 2000
var sectors := 10
var warmup := 300
var gi_name := "voxel"        # voxel | sdfgi | lightmap
var gi_quality_name := "high" # low | high
var only_sector := -1         # debug: 1-based
var hud_enabled := true
var probe := false            # debug: report free-space around each vantage, then quit
var shots_dir := ""           # debug: save a PNG mid-sector
var use_path := true           # --no-path forces the built-in vantage points
var use_activity := true       # --no-activity: no robots
var use_player := true         # --no-player: no player character
var res_name := "1080p"
var window_cap := WINDOW_CAP
var variant_name := ""        # --variant Small|Medium|Large
var output_path := ""         # --output FILE: every event is also written here, one JSON object per line
var output_file: FileAccess
var explicit_shape := false   # --frames / --sectors / --res given (conflicts with --variant)
var custom_size := false      # --debug-size used
var profile := false          # --profile: per-sector GPU / CPU timing breakdown (debug: perturbs timing slightly)
var robot_limit := -1         # --robot-limit N: spawn only the first N baked robots (debug)
var prof_rid: RID
var prof_gpu := 0.0
var prof_cpu := 0.0
var prof_proc := 0.0
var prof_draws := 0.0
var prof_n := 0
var prof_sectors: Array = []
var render_size := RENDER_SIZE
var debug_run := false        # any debug option => result is NOT submittable

var frames_per_sector := 0
var measure_target := 0
var frame_offset := 0

var level: Node3D
var cam: Camera3D
var anim: AnimationPlayer
var hud_label: Label
var hud_panel: Panel
var hud_header := ""
var frame_prev_us := 0
var frame_stats: RefCounted
var hud_win_start_us := 0
var hud_win_frames := 0
var hud_worst_us := 0
var run_start_us := 0
var credit_label: Label
var title_label: Label
var title_panel: Panel
var title_shown_sector := -1
var title_frame := 0

var total_frames := 0
var measured := 0
var current_sector := 0
var warmed := false
var aborted := false
var t_sector_us := 0
var sector_times: Array[float] = []
var shot_path := ""

# recorded camera route
var path_pos := PackedVector3Array()
var path_quat: Array[Quaternion] = []
var path_fov := PackedFloat32Array()
var path_sha := ""
var path_file := PATH_FILE
var activity_file := ACTIVITY_FILE

# player track (optional; present when the route was recorded with record.gd v2)
var path_hz := 20.0
var player_pos := PackedVector3Array()
var player_quat: Array[Quaternion] = []
var player_state := PackedInt32Array()
var player_motion := PackedVector2Array()
var player_aim := PackedFloat32Array()
var player_node: Node3D
var player_model: Node3D
var player_tree: AnimationTree
var player_last_state := -1

# activity layer
var activity_data: Array = []
var activity_sha := ""
var robots: Array = []


func _ready() -> void:
	# The demo enables physics interpolation. This benchmark poses the camera / player / animations
	# from the frame loop, so interpolating them against the physics tick would blend poses; turn it
	# off for everything under this node (children inherit).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_parse_args()
	if output_path != "" and not _open_output():
		return
	if variant_name != "":
		var key := variant_name.to_lower()
		if not VARIANTS.has(key):
			_abort("invalid_args", "--variant must be one of: Small, Medium, Large")
			return
		if explicit_shape:
			_abort("invalid_args", "--variant cannot be combined with --frames, --sectors or --res")
			return
		variant_name = key.capitalize()
		res_name = VARIANTS[key]["res"]
		frames = VARIANTS[key]["frames"]
		sectors = VARIANTS[key]["sectors"]
	if not RESOLUTIONS.has(res_name):
		_abort("invalid_args", "--res must be one of: %s" % ", ".join(RESOLUTIONS.keys()))
		return
	if gi_name == "lightmap" and not ResourceLoader.exists("res://level/level.lmbake"):
		_abort("gi_unavailable", "This build does not include the lightmap GI data (lean build); use --gi voxel or sdfgi.")
		return
	if not custom_size:
		render_size = RESOLUTIONS[res_name]
	if sectors < 1 or frames % sectors != 0:
		_abort("invalid_args", "frames must be divisible by sectors")
		return
	@warning_ignore("integer_division")
	frames_per_sector = frames / sectors
	if only_sector > 0:
		if only_sector > sectors:
			_abort("invalid_args", "--only-sector must be between 1 and %d" % sectors)
			return
		frame_offset = (only_sector - 1) * frames_per_sector
		current_sector = only_sector - 1
		measure_target = frames_per_sector
		debug_run = true
	else:
		measure_target = frames
	frame_stats = FrameStats.new(measure_target)

	seed(RNG_SEED)
	AudioServer.set_bus_mute(0, true)
	_pin_settings()
	_setup_window()
	_load_path()
	if aborted:
		return
	_load_activity()
	if aborted:
		return
	_load_level()
	_setup_hud()
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	if profile:
		prof_rid = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(prof_rid, true)

	if probe:
		_run_probe()
	else:
		# Nothing in the benchmark needs physics; keep it out of the timing.
		PhysicsServer3D.set_active(false)


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var arg: String = a[i]
		var val: String = a[i + 1] if i + 1 < a.size() else ""
		match arg:
			"--variant":
				variant_name = val
				i += 1
			"--output":
				output_path = val
				i += 1
			"--frames":
				frames = int(val)
				explicit_shape = true
				i += 1
			"--sectors":
				sectors = int(val)
				explicit_shape = true
				i += 1
			"--warmup":
				warmup = int(val)
				i += 1
			"--gi":
				gi_name = val
				i += 1
			"--gi-quality":
				gi_quality_name = val
				i += 1
			"--only-sector":
				only_sector = int(val)
				i += 1
			"--no-hud":
				hud_enabled = false
			"--no-path":
				use_path = false
			"--no-activity":
				use_activity = false
			"--no-player":
				use_player = false
			"--probe":
				probe = true
				debug_run = true
			"--debug-shots":
				shots_dir = val
				debug_run = true
				i += 1
			"--res":
				res_name = val.to_lower()
				explicit_shape = true
				i += 1
			"--profile":
				profile = true
				debug_run = true
			"--robot-limit":
				robot_limit = int(val)
				debug_run = true
				i += 1
			"--debug-window":
				var ww := val.split("x")
				window_cap = Vector2i(int(ww[0]), int(ww[1]))
				debug_run = true
				i += 1
			"--debug-size":
				var wh := val.split("x")
				render_size = Vector2i(int(wh[0]), int(wh[1]))
				custom_size = true
				debug_run = true
				i += 1
		i += 1
	var engine_args := OS.get_cmdline_args()
	for j in engine_args.size() - 1:
		if engine_args[j] == "--variant" and variant_name == "":
			variant_name = engine_args[j + 1]
		elif engine_args[j] == "--output" and output_path == "":
			output_path = engine_args[j + 1]


# Overwrite the demo's user settings with a fixed benchmark profile. Never saved.
func _pin_settings() -> void:
	var cfg: ConfigFile = Settings.config_file
	var gi_type: int = {"voxel": Settings.GIType.VOXEL_GI, "sdfgi": Settings.GIType.SDFGI,
			"lightmap": Settings.GIType.LIGHTMAP_GI}.get(gi_name, Settings.GIType.VOXEL_GI)
	var gi_quality: int = Settings.GIQuality.LOW if gi_quality_name == "low" else Settings.GIQuality.HIGH
	cfg.set_value("video", "display_mode", Window.MODE_WINDOWED)
	cfg.set_value("video", "vsync", DisplayServer.VSYNC_DISABLED)
	cfg.set_value("video", "max_fps", 0)
	cfg.set_value("video", "resolution_scale", 1.0)
	cfg.set_value("video", "scale_filter", Viewport.SCALING_3D_MODE_BILINEAR)  # no vendor upscaler
	cfg.set_value("rendering", "taa", false)
	cfg.set_value("rendering", "msaa", Viewport.MSAA_DISABLED)
	cfg.set_value("rendering", "screen_space_aa", Viewport.SCREEN_SPACE_AA_DISABLED)
	cfg.set_value("rendering", "shadow_mapping", true)
	cfg.set_value("rendering", "gi_type", gi_type)
	cfg.set_value("rendering", "gi_quality", gi_quality)
	cfg.set_value("rendering", "ssao_quality", RenderingServer.ENV_SSAO_QUALITY_MEDIUM)
	cfg.set_value("rendering", "ssil_quality", -1)
	cfg.set_value("rendering", "bloom", true)
	cfg.set_value("rendering", "volumetric_fog", true)


func _setup_window() -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED
	w.size = Vector2i(mini(render_size.x, window_cap.x), mini(render_size.y, window_cap.y))
	w.unresizable = true
	# Render at a FIXED internal resolution no matter what the OS does to the window
	# (decorations, DPI, snapping): "viewport" stretch renders at content_scale_size, then scales.
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	w.content_scale_size = render_size
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	if "hdr_output_requested" in w:
		w.hdr_output_requested = false  # project requests HDR; keep the pipeline identical everywhere
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _load_level() -> void:
	var packed := load(LEVEL_SCENE) as PackedScene
	level = packed.instantiate() as Node3D
	level.set_script(STATIC_LEVEL_SCRIPT)

	# Strip everything that is not part of the fixed workload.
	for n in ["Music", "Debug", "MultiplayerSpawner", "RobotSpawnpoints", "PlayerSpawnpoints", "SpawnedNodes"]:
		var node := level.get_node_or_null(n)
		if node:
			level.remove_child(node)
			node.free()

	# Pin particle randomness (set before entering the tree so emission starts seeded).
	var idx := 0
	for type_name in ["CPUParticles3D", "GPUParticles3D"]:
		for p in level.find_children("*", type_name, true, false):
			p.use_fixed_seed = true
			p.seed = PARTICLE_SEED + idx
			idx += 1

	add_child(level)

	cam = level.get_node("Camera3D") as Camera3D
	cam.current = true

	# Forklift models are randomised in their own _ready(); pin them, then re-seed.
	var forklifts := level.get_node_or_null("FlyingForklifts")
	if forklifts:
		var fi := 0
		for f in forklifts.get_children():
			if f is AnimationPlayer:
				anim = f
				continue
			var models := f.get_child(0).get_children()
			for j in models.size():
				models[j].visible = (j == fi % models.size())
			fi += 1
	seed(RNG_SEED)

	if anim:
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim.play(FORKLIFT_ANIM)
		anim.seek(0.0, true)

	_spawn_player()
	_spawn_robots()
	_warmup_pose(0)


func _mono_font() -> SystemFont:
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Menlo", "monospace"])
	return mono


func _setup_hud() -> void:
	if not hud_enabled:
		return
	var layer := CanvasLayer.new()
	var fs := maxi(14, int(render_size.y / 45.0))   # scales with the internal resolution (4K is shown downscaled)
	var mono := _mono_font()

	# Backing panel gives the readout a fixed, legible home instead of floating text over the scene.
	hud_panel = Panel.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.05, 0.05, 0.55)
	panel_style.set_corner_radius_all(maxi(4, int(fs / 3.0)))
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(0.0, 1.0, 0.6, 0.35)
	hud_panel.add_theme_stylebox_override("panel", panel_style)
	hud_panel.position = Vector2(fs * 0.6, fs * 0.5)
	hud_panel.size = Vector2(fs * 23.0, fs * 6.3)
	layer.add_child(hud_panel)

	hud_label = Label.new()
	hud_label.position = Vector2(fs * 0.55, fs * 0.35)
	hud_label.add_theme_font_size_override("font_size", fs)
	hud_label.add_theme_color_override("font_color", Color("#1fffa3"))
	hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hud_label.add_theme_constant_override("outline_size", maxi(2, int(fs / 6.0)))
	hud_label.add_theme_constant_override("line_spacing", int(fs * 0.25))
	hud_label.add_theme_font_override("font", mono)
	hud_header = "OCGP TPS BENCHMARK   %s   %s   %s" % [
		"custom" if custom_size else res_name,
		RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name()]
	hud_label.text = hud_header + "\nwarming up..."
	hud_panel.add_child(hud_label)
	add_child(layer)

	_setup_credit(layer, fs, mono)
	_setup_title_card(layer, fs, mono)


# Live readout. Window stats cover the frames since the last update; "worst" is the longest single frame in it.
func _update_hud(now_us: int) -> void:
	var win_ms := float(now_us - hud_win_start_us) / 1000.0 / float(maxi(hud_win_frames, 1))
	var avg_ms := float(now_us - run_start_us) / 1000.0 / float(maxi(measured, 1))
	hud_label.text = "%s\nframe %d / %d   sector %d/%d\n%.2f ms  %.0f fps   worst %.2f ms\navg %.2f ms   elapsed %.1f s\nlows  1%% %.0f   0.1%% %.0f   0.01%% %.0f   min %.0f fps" % [
		hud_header, measured, measure_target, current_sector + 1, sectors,
		win_ms, 1000.0 / maxf(win_ms, 0.001), float(hud_worst_us) / 1000.0,
		avg_ms, float(now_us - run_start_us) / 1.0e6,
		frame_stats.low_fps(0.01, measured), frame_stats.low_fps(0.001, measured),
		frame_stats.low_fps(0.0001, measured), frame_stats.min_fps()]
	hud_win_start_us = now_us
	hud_win_frames = 0
	hud_worst_us = 0


# ---------------------------------------------------------------- credit / sector title overlays

func _setup_credit(layer: CanvasLayer, fs: int, mono: SystemFont) -> void:
	var cfs := maxi(10, int(fs * 0.55))
	credit_label = Label.new()
	credit_label.text = CREDIT_TEXT
	credit_label.add_theme_font_size_override("font_size", cfs)
	credit_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	credit_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	credit_label.add_theme_constant_override("outline_size", maxi(2, int(cfs / 6.0)))
	credit_label.add_theme_font_override("font", mono)
	credit_label.size = Vector2(render_size.x, cfs * 2.0)
	credit_label.position = Vector2(0, render_size.y - cfs * 2.0)
	credit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(credit_label)


func _setup_title_card(layer: CanvasLayer, fs: int, mono: SystemFont) -> void:
	var tfs := maxi(16, int(render_size.y / 30.0))
	title_panel = Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.0)
	title_panel.add_theme_stylebox_override("panel", style)
	title_panel.size = Vector2(render_size.x, tfs * 2.4)
	title_panel.position = Vector2(0, render_size.y * 0.5 - tfs * 1.2)
	title_panel.modulate = Color(1, 1, 1, 0)
	layer.add_child(title_panel)

	title_label = Label.new()
	title_label.text = ""
	title_label.add_theme_font_size_override("font_size", tfs)
	title_label.add_theme_color_override("font_color", Color("#eafff5"))
	title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title_label.add_theme_constant_override("outline_size", maxi(3, int(tfs / 5.0)))
	title_label.add_theme_font_override("font", mono)
	title_label.size = title_panel.size
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_panel.add_child(title_label)


# Call once per measured frame: shows "Sector N : <name>" briefly whenever the sector changes,
# fading it out over SECTOR_TITLE_FADE_FRAMES. Purely visual bookkeeping, not part of scoring.
func _update_title_card() -> void:
	if title_label == null:
		return
	if current_sector != title_shown_sector:
		title_shown_sector = current_sector
		title_frame = 0
		var idx := current_sector % SECTOR_TITLES.size()
		title_label.text = SECTOR_TITLES[idx]
	if title_frame > SECTOR_TITLE_FRAMES + SECTOR_TITLE_FADE_FRAMES:
		return
	var alpha := 1.0
	if title_frame > SECTOR_TITLE_FRAMES:
		alpha = 1.0 - float(title_frame - SECTOR_TITLE_FRAMES) / float(SECTOR_TITLE_FADE_FRAMES)
	title_panel.modulate = Color(1, 1, 1, clampf(alpha, 0.0, 1.0))
	title_frame += 1


# ---------------------------------------------------------------- frame loop

func _process(delta: float) -> void:
	if aborted or probe:
		return
	if absf(delta - SIM_STEP) > DELTA_TOLERANCE:
		_abort("fixed_timestep_required",
				"Frame delta %.6f s != %.6f s. Launch with --fixed-fps 60 --disable-vsync." % [delta, SIM_STEP])
		return
	total_frames += 1

	# ---- Warmup: tour every vantage so pipelines / resources are resident ----
	if not warmed:
		_warmup_pose(total_frames - 1)
		if hud_label and total_frames % 10 == 0:
			# Show every glyph the live readout will use, so font setup / glyph rasterisation happens
			# here and not as a one-off hitch in the first timed frames.
			hud_label.text = "%s\nwarming up  %d / %d\n0123456789 . %% / : ms fps\nframe sector worst avg elapsed lows min" % [hud_header, total_frames, warmup]
		if total_frames >= warmup:
			if DisplayServer.get_name() == "headless":
				debug_run = true  # no real window/renderer: useful for logic tests only
			else:
				var internal := Vector2i(get_viewport().get_visible_rect().size)
				if internal != render_size:
					_abort("canvas_size_invalid", "Internal render size is %s, expected %s (window %s)" % [internal, render_size, DisplayServer.window_get_size()])
					return
			warmed = true
			_pose_for_frame(frame_offset)  # first timed frame is frame index 0 (of this run)
			t_sector_us = Time.get_ticks_usec()
			run_start_us = t_sector_us
			frame_prev_us = t_sector_us
			hud_win_start_us = t_sector_us
			_emit(_start_info())
		return

	# ---- Measurement ----
	measured += 1
	if profile:
		prof_gpu += RenderingServer.viewport_get_measured_render_time_gpu(prof_rid)
		prof_cpu += RenderingServer.viewport_get_measured_render_time_cpu(prof_rid)
		prof_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		prof_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prof_n += 1
	# Frame period = time between consecutive frame callbacks (CPU + GPU throughput).
	var frame_now := Time.get_ticks_usec()
	var frame_dt := frame_now - frame_prev_us
	frame_prev_us = frame_now
	frame_stats.add(frame_dt)
	if hud_label:
		hud_worst_us = maxi(hud_worst_us, frame_dt)
		hud_win_frames += 1
		if measured == 1 or measured % HUD_INTERVAL == 0:
			_update_hud(frame_now)
		_update_title_card()

	# ---- Sector boundary (same convention as 3dpoc.py) ----
	if measured % frames_per_sector == 0:
		var now := Time.get_ticks_usec()
		var sector_ms := snappedf((now - t_sector_us) / 1000.0, 0.01)
		current_sector += 1
		sector_times.append(sector_ms)
		var sector_ev := {
			"event": "sector", "iter": 1, "sector": current_sector,
			"total_sectors": sectors, "sector_ms": sector_ms,
		}
		if profile and prof_n > 0:
			var pn := float(prof_n)
			sector_ev["profile"] = {
				"frame_ms": snappedf(sector_ms / pn, 0.001),            # wall time per frame
				"gpu_ms": snappedf(prof_gpu / pn, 0.001),               # GPU time of the main viewport render
				"render_cpu_ms": snappedf(prof_cpu / pn, 0.001),        # CPU time spent submitting that render
				"process_ms": snappedf(prof_proc / pn, 0.001),          # node processing: scripts, animation, particles
				"draw_calls": int(prof_draws / pn),
			}
			prof_sectors.append(sector_ev["profile"])
			prof_gpu = 0.0
			prof_cpu = 0.0
			prof_proc = 0.0
			prof_draws = 0.0
			prof_n = 0
		_emit(sector_ev)
		t_sector_us = now

	# ---- Run complete ----
	if measured >= measure_target:
		var total_ms := 0.0
		for s in sector_times:
			total_ms += s
		var done := {
			"event": "complete",
			"best_ms": snappedf(total_ms, 0.01),
			"sector_times": sector_times,
			"total_sectors": sectors,
			"frames": measure_target,
			"frame_stats": {   # informational; the score is best_ms
				"avg_fps": snappedf(1.0e6 / (float(Time.get_ticks_usec() - run_start_us) / float(measure_target)), 0.1),
				"low_1_fps": snappedf(frame_stats.low_fps(0.01, measure_target), 0.1),
				"low_0_1_fps": snappedf(frame_stats.low_fps(0.001, measure_target), 0.1),
				"low_0_01_fps": snappedf(frame_stats.low_fps(0.0001, measure_target), 0.1),
				"min_fps": snappedf(frame_stats.min_fps(), 0.1),
				"worst_frame_ms": snappedf(frame_stats.worst_ms(), 0.01),
			},
		}
		if debug_run:
			done["debug_run"] = true
		_emit(done)
		aborted = true
		get_tree().quit()
		return

	# ---- Drive the world from the frame index (rendered after this callback) ----
	_pose_for_frame(frame_offset + measured)

	# Debug screenshots: every frame when sectors are tiny, else one per sector (mid-sector).
	if shots_dir != "" and (frames_per_sector <= 8 or measured % frames_per_sector == frames_per_sector / 2):
		shot_path = "%s/s%02d_k%04d.png" % [shots_dir, current_sector + 1, frame_offset + measured]


# ------------------------------------------------------------ deterministic pose

func _pose_for_frame(k: int) -> void:
	if anim:
		anim.seek(fmod(float(k) * SIM_STEP, FORKLIFT_ANIM_LENGTH), true)
	_update_robots(k, -1)
	if path_pos.size() >= 2:
		# Progress along the recorded route is a pure function of the frame index.
		var u := float(k) / float(frames)
		_set_camera_on_path(u)
		_update_player(u, _route_seconds() / (float(frames) * SIM_STEP))
		return
	@warning_ignore("integer_division")
	var sector_idx := k / frames_per_sector
	var t := float(k % frames_per_sector) / float(frames_per_sector)
	_set_camera(sector_idx % VANTAGES.size(), t)


func _warmup_pose(i: int) -> void:
	_update_robots(i - warmup, i)  # timeline continues seamlessly into frame 0
	if path_pos.size() >= 2:
		var uw := float(i) / float(maxi(warmup, 1))   # one quick pass over the whole route
		_set_camera_on_path(uw)
		_update_player(uw, _route_seconds() / (float(maxi(warmup, 1)) * SIM_STEP))
		return
	@warning_ignore("integer_division")
	var per := maxi(1, warmup / VANTAGES.size())
	@warning_ignore("integer_division")
	var v := mini(i / per, VANTAGES.size() - 1)
	_set_camera(v, float(i % per) / float(per))


func _load_path() -> void:
	if not FileAccess.file_exists(path_file):
		path_file = LEGACY_PATH_FILE
	if not use_path or not FileAccess.file_exists(path_file):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_file))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("samples"):
		_abort("invalid_path", "%s is not a valid route file" % path_file)
		return
	path_hz = float(parsed.get("hz", 20.0))
	var prev := Quaternion.IDENTITY
	var pprev := Quaternion.IDENTITY
	for smp in parsed["samples"]:
		if smp.size() >= 19:
			var pq := Quaternion(smp[11], smp[12], smp[13], smp[14]).normalized()
			if player_quat.size() > 0 and pprev.dot(pq) < 0.0:
				pq = Quaternion(-pq.x, -pq.y, -pq.z, -pq.w)
			player_pos.append(Vector3(smp[8], smp[9], smp[10]))
			player_quat.append(pq)
			player_state.append(int(smp[15]))
			player_motion.append(Vector2(smp[16], smp[17]))
			player_aim.append(smp[18])
			pprev = pq
		var q := Quaternion(smp[3], smp[4], smp[5], smp[6]).normalized()
		if path_quat.size() > 0 and prev.dot(q) < 0.0:
			q = Quaternion(-q.x, -q.y, -q.z, -q.w)  # keep neighbours on the same hemisphere
		path_pos.append(Vector3(smp[0], smp[1], smp[2]))
		path_quat.append(q)
		path_fov.append(smp[7])
		prev = q
	path_sha = FileAccess.get_sha256(path_file)
	if player_pos.size() != path_pos.size():   # old (v1) route: no player track
		player_pos.clear()
		player_quat.clear()
		player_state.clear()
		player_motion.clear()
		player_aim.clear()


func _route_seconds() -> float:
	return float(path_pos.size() - 1) / path_hz


func _spawn_player() -> void:
	if not use_player or player_pos.size() < 2:
		return
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate() as Node3D
	p.set_script(null)   # no input, no physics, no camera: pose and animation come from the route file
	for n in PLAYER_STRIP:
		var node := p.get_node_or_null(n)
		if node:
			p.remove_child(node)
			node.free()
	var pi := 0
	for ps in p.find_children("*", "CPUParticles3D", true, false):
		ps.use_fixed_seed = true
		ps.seed = PLAYER_PARTICLE_SEED + pi
		pi += 1
	level.add_child(p)
	player_node = p
	player_model = p.get_node("PlayerModel") as Node3D
	player_tree = p.get_node("AnimationTree") as AnimationTree
	# Manual stepping: the walk cycle advances in step with the route speed (see _update_player).
	player_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player_tree.active = true


# ratio = recorded route speed / playback route speed. Scaling the animation step by it keeps the feet
# matched to the ground speed whatever the frame count (variants are slow-motion / fast-forward).
func _update_player(u: float, ratio: float) -> void:
	if player_node == null:
		return
	var n := player_pos.size()
	var x := clampf(u, 0.0, 1.0) * float(n - 1)
	var i := mini(int(x), n - 2)
	var f := x - float(i)
	var p0 := player_pos[maxi(i - 1, 0)]
	var p1 := player_pos[i]
	var p2 := player_pos[i + 1]
	var p3 := player_pos[mini(i + 2, n - 1)]
	player_node.position = p1.cubic_interpolate(p2, p0, p3, f)
	player_model.global_transform.basis = Basis(player_quat[i].slerp(player_quat[i + 1], f))

	var state := player_state[i]
	var motion := player_motion[i].lerp(player_motion[i + 1], f)
	if state != player_last_state:
		player_tree["parameters/state/transition_request"] = PLAYER_STATES.get(state, "walk")
		player_last_state = state
	match state:
		2:  # strafe (aiming)
			player_tree["parameters/aim/add_amount"] = lerpf(player_aim[i], player_aim[i + 1], f)
			player_tree["parameters/strafe/blend_position"] = Vector2(motion.x, -motion.y)
		3:  # walk
			player_tree["parameters/aim/add_amount"] = 0.0
			player_tree["parameters/walk/blend_position"] = Vector2(motion.length(), 0.0)
	player_tree.advance(SIM_STEP * minf(ratio, MAX_ANIM_RATIO))   # cap: huge steps (fast warmup pass) make poses glitch


func _load_activity() -> void:
	if not FileAccess.file_exists(activity_file):
		activity_file = LEGACY_ACTIVITY_FILE
	if not use_activity or path_pos.size() < 2 or not FileAccess.file_exists(activity_file):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(activity_file))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("robots"):
		_abort("invalid_activity", "%s is not a valid activity file" % activity_file)
		return
	if parsed.get("path_sha256", "") != path_sha:
		_abort("activity_path_mismatch", "The activity file was baked for a different route; run bake.tscn again.")
		return
	activity_data = parsed["robots"]
	if robot_limit >= 0 and robot_limit < activity_data.size():
		activity_data = activity_data.slice(0, robot_limit)
	activity_sha = FileAccess.get_sha256(activity_file)


func _spawn_robots() -> void:
	if activity_data.is_empty():
		return
	var packed := load(ROBOT_SCENE) as PackedScene
	for ri in activity_data.size():
		var d: Dictionary = activity_data[ri]
		var r := packed.instantiate() as Node3D
		r.set_script(ROBOT_STUB)  # no AI, no physics, no multiplayer: behaviour comes from _update_robots()
		for n in ROBOT_STRIP:
			var node := r.get_node_or_null(n)
			if node:
				r.remove_child(node)
				node.free()
		var pi := 0
		for p in r.find_children("*", "CPUParticles3D", true, false):
			p.use_fixed_seed = true
			p.seed = ROBOT_PARTICLE_SEED + ri * 16 + pi
			pi += 1
		level.add_child(r)
		r.global_position = Vector3(d["pos"][0], d["pos"][1], d["pos"][2])
		r.rotation.y = d["yaw"]

		var tree := r.get_node("AnimationTree") as AnimationTree
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE  # per rendered frame (fixed delta)
		tree.active = true
		tree.set("parameters/state/transition_request", "idle")
		tree.set("parameters/aiming/blend_amount", 0.0)

		var ray_from := r.get_node("RedRobotModel/Armature/Skeleton3D/RayFrom")
		var ray_mesh := ray_from.get_node("RayMesh") as MeshInstance3D
		# The laser material is a shared sub-resource; give every robot its own copy.
		ray_mesh.set_surface_override_material(0, ray_mesh.get_surface_override_material(0).duplicate())
		robots.append({
			"data": d,
			"tree": tree,
			"shoot": r.get_node("ShootAnimation") as AnimationPlayer,
			"ray_mesh": ray_mesh,
			"ember": ray_from.get_node("LaserEmber") as CPUParticles3D,
			"blast_idx": 0,
		})


# Everything a robot does is a function of the frame index: no AI, no randomness, no wall-clock.
func _update_robots(k: int, warm_i: int) -> void:
	for ri in robots.size():
		var rb: Dictionary = robots[ri]
		var t := posmod(k + int(rb["data"]["phase"]), CYCLE_FRAMES)
		var blend := 0.0
		if t >= AIM_UP_START and t < AIM_UP_END:
			blend = float(t - AIM_UP_START) / float(AIM_UP_END - AIM_UP_START)
		elif t >= AIM_UP_END and t < AIM_DOWN_START:
			blend = 1.0
		elif t >= AIM_DOWN_START and t < AIM_DOWN_END:
			blend = 1.0 - float(t - AIM_DOWN_START) / float(AIM_DOWN_END - AIM_DOWN_START)
		(rb["tree"] as AnimationTree).set("parameters/aiming/blend_amount", blend)
		# One extra shot per robot early in warmup so laser / blast resources are warm.
		if t == SHOOT_AT or (warm_i >= 0 and warm_i == 5 + ri * 2):
			_fire(ri)


func _fire(ri: int) -> void:
	var rb: Dictionary = robots[ri]
	var d: Dictionary = rb["data"]
	var laser := float(d["laser"])
	var ray_mesh := rb["ray_mesh"] as MeshInstance3D
	var mesh_offset := ray_mesh.position.z
	(ray_mesh.get_surface_override_material(0) as ShaderMaterial).set_shader_parameter("clip", laser + mesh_offset)
	var ember := rb["ember"] as CPUParticles3D
	ember.position = Vector3(0.0, 0.0, -laser / 2.0 - mesh_offset)
	ember.emission_box_extents.z = (laser - absf(mesh_offset)) / 2.0
	(rb["shoot"] as AnimationPlayer).play(&"shoot")
	if d["has_hit"]:
		var blast := (load(BLAST_SCENE) as PackedScene).instantiate() as Node3D
		var bi := 0
		for p in blast.find_children("*", "CPUParticles3D", true, false):
			p.use_fixed_seed = true
			p.seed = ROBOT_PARTICLE_SEED + 5000 + ri * 64 + int(rb["blast_idx"]) * 4 + bi
			bi += 1
		rb["blast_idx"] = (int(rb["blast_idx"]) + 1) % 8
		level.add_child(blast)
		blast.global_position = Vector3(d["hit"][0], d["hit"][1], d["hit"][2])


func _set_camera_on_path(u: float) -> void:
	var n := path_pos.size()
	var x := clampf(u, 0.0, 1.0) * float(n - 1)
	var i := mini(int(x), n - 2)
	var f := x - float(i)
	var p0 := path_pos[maxi(i - 1, 0)]
	var p1 := path_pos[i]
	var p2 := path_pos[i + 1]
	var p3 := path_pos[mini(i + 2, n - 1)]
	cam.position = p1.cubic_interpolate(p2, p0, p3, f)
	cam.quaternion = path_quat[i].slerp(path_quat[i + 1], f)
	cam.fov = lerpf(path_fov[i], path_fov[i + 1], f)


func _set_camera(vantage: int, t: float) -> void:
	var v: Dictionary = VANTAGES[vantage]
	cam.position = v["pos"]
	cam.rotation = Vector3(deg_to_rad(v["pitch"]), deg_to_rad(v["yaw"] + v["sweep"] * t), 0.0)


# ------------------------------------------------------------------ reporting

func _start_info() -> Dictionary:
	return {
		"event": "start",
		"workload": "tps",
		"variant": variant_name,
		"total_sectors": sectors,
		"frames": measure_target,
		"warmup": warmup,
		"gi": gi_name,
		"gi_quality": gi_quality_name,
		"camera_path": "recorded" if path_pos.size() >= 2 else "vantages",
		"path_samples": path_pos.size(),
		"path_sha256": path_sha,
		"player": player_node != null,
		"activity_robots": robots.size(),
		"activity_sha256": activity_sha,
		"resolution": "custom" if custom_size else res_name,
		"render_size": [render_size.x, render_size.y],
		"window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"sim_step": SIM_STEP,
		"godot": Engine.get_version_info().string,
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"vsync": DisplayServer.window_get_vsync_mode(),
		"hdr_output": bool(get_window().hdr_output_requested) if "hdr_output_requested" in get_window() else false,
		"hdr_2d": bool(ProjectSettings.get_setting("rendering/viewport/hdr_2d", false)),
		"debug_run": debug_run,
	}


func _on_frame_post_draw() -> void:
	if shot_path == "":
		return
	get_viewport().get_texture().get_image().save_png(shot_path)
	shot_path = ""


func _abort(code: String, message: String) -> void:
	aborted = true
	_emit({"event": "complete", "error": code, "message": message})
	get_tree().quit(1)


# One event per line on stdout and, with --output, in the file too (flushed per line, so a crash keeps what was written).
func _emit(ev: Dictionary) -> void:
	var line := JSON.stringify(ev)
	print(line)
	if output_file != null:
		output_file.store_line(line)
		output_file.flush()


func _open_output() -> bool:
	output_file = FileAccess.open(output_path, FileAccess.WRITE)
	if output_file == null:
		aborted = true
		print(JSON.stringify({"event": "complete", "error": "output_unwritable",
				"message": "Cannot write --output file '%s' (error %d)" % [output_path, FileAccess.get_open_error()]}))
		get_tree().quit(1)
		return false
	return true


# Debug: how much free space surrounds each vantage? (needs physics active)
func _run_probe() -> void:
	for _i in 3:
		await get_tree().physics_frame
	var space := cam.get_world_3d().direct_space_state
	for vi in VANTAGES.size():
		var v: Dictionary = VANTAGES[vi]
		var pos: Vector3 = v["pos"]
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = pos
		var inside := space.intersect_point(pq, 1).size() > 0
		var dists: Array[float] = []
		for d in 16:
			var ang := TAU * float(d) / 16.0
			var rq := PhysicsRayQueryParameters3D.create(pos, pos + Vector3(sin(ang), 0, cos(ang)) * 200.0)
			var hit := space.intersect_ray(rq)
			dists.append(200.0 if hit.is_empty() else pos.distance_to(hit["position"]))
		dists.sort()
		print(JSON.stringify({"vantage": vi, "name": v["name"], "inside_collider": inside,
				"min_m": snappedf(dists[0], 0.1), "median_m": snappedf(dists[8], 0.1),
				"max_m": snappedf(dists[15], 0.1)}))
	get_tree().quit()

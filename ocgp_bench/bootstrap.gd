# Autoload (export-only, feature tag "ocgp" — never present in editor runs). Lets a packaged
# build be double-clicked directly: vsync is pinned via the .ocgp override in project.godot, but
# --fixed-fps and --rendering-driver have no such equivalent here. --fixed-fps is an engine debug
# flag with no project-setting counterpart at all. --rendering-driver DOES have a project setting
# (rendering_device/driver.windows), but Godot's feature-tag override can't stack onto a
# platform-suffixed key — rendering_device/driver.windows.ocgp is silently ignored, confirmed by a
# real run falling back to d3d12 despite that override being present in project.godot. So both
# flags are injected here instead. If either is missing, relaunch this same executable with both
# added, then quit this instance. A caller that already passes --fixed-fps (OCGP, tps_wrapper.py)
# is left alone — no extra process hop, no change to existing behaviour.
#
# Loop guard: an env var, not a CLI flag, marks "this process is the relaunched child" — it
# survives OS.create_process regardless of how the engine itself re-parses these flags, so a bug
# or quirk in that detection can never cause a second relaunch (observed: a naive "--fixed-fps" in
# OS.get_cmdline_args() check relaunched unboundedly on export).
extends Node

const REQUIRED_FIXED_FPS := "60"
const RELAUNCH_GUARD_ENV := "OCGP_TPS_RELAUNCHED"


func _ready() -> void:
	if OS.get_environment(RELAUNCH_GUARD_ENV) == "1":
		return  # this IS the relaunched child; never relaunch again no matter what
	var engine_args := OS.get_cmdline_args()
	if "--fixed-fps" in engine_args and "--rendering-driver" in engine_args:
		return  # caller already set up the engine; run in-process as normal

	var relaunch_args := ["--rendering-driver", "vulkan", "--fixed-fps", REQUIRED_FIXED_FPS, "--"]
	# Pass through anything after `--` (e.g. a double-click has none; an advanced user could still
	# pass `--variant Small` by hand without the engine flags). Default to Large when nothing else
	# was requested, so a bare double-click runs the highest-setting variant unattended.
	var user_args := OS.get_cmdline_user_args()
	if user_args.is_empty():
		relaunch_args.append_array(["--variant", "Large", "--output", "ocgp_tps_result_Large.txt"])
	else:
		relaunch_args.append_array(user_args)

	OS.set_environment(RELAUNCH_GUARD_ENV, "1")
	OS.create_process(OS.get_executable_path(), relaunch_args)
	get_tree().quit()

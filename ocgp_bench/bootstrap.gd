# Autoload (export-only, feature tag "ocgp" — never present in editor runs). Lets a packaged
# build be double-clicked directly: the rendering driver and vsync are already pinned via the
# .ocgp overrides in project.godot, but --fixed-fps has no project-setting equivalent (it's an
# engine debug flag), so it can only be supplied on the command line. If it's missing, relaunch
# this same executable with it added, then quit this instance. A caller that already passes
# --fixed-fps (OCGP, tps_wrapper.py, run_benchmark.bat) is left alone — no extra process hop, no
# change to existing behaviour.
#
# Loop guard: an env var, not a CLI flag, marks "this process is the relaunched child" — it
# survives OS.create_process regardless of how the engine itself re-parses --fixed-fps, so a
# bug or quirk in that detection can never cause a second relaunch (observed: a naive
# "--fixed-fps" in OS.get_cmdline_args() check relaunched unboundedly on export).
extends Node

const REQUIRED_FIXED_FPS := "60"
const RELAUNCH_GUARD_ENV := "OCGP_TPS_RELAUNCHED"


func _ready() -> void:
	if OS.get_environment(RELAUNCH_GUARD_ENV) == "1":
		return  # this IS the relaunched child; never relaunch again no matter what
	if "--fixed-fps" in OS.get_cmdline_args():
		return  # caller already set up the engine; run in-process as normal

	var relaunch_args := ["--fixed-fps", REQUIRED_FIXED_FPS, "--"]
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

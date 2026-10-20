# Regenerates export_presets.cfg for a single-file build.
#
#   godot --headless --path <tps-project> --script res://ocgp_bench/export_list.gd [-- --no-lightmap]
#
# The exporter does not follow every dependency (scripts that preload scripts, materials referenced by an
# imported .glb, project-setting resources), so this walks them with ResourceLoader.get_dependencies - the same
# walk used to size the build - and lists EVERY file the benchmark needs. Re-run it after changing the benchmark.
# Data files (route.ocgp / activity.ocgp) have a non-resource extension and are shipped via the include filter.
extends SceneTree

const ROOTS := [
	"res://ocgp_bench/bench.tscn", "res://ocgp_bench/bench.gd", "res://ocgp_bench/level_static.gd",
	"res://ocgp_bench/robot_stub.gd", "res://ocgp_bench/frame_stats.gd",
	"res://level/level.tscn", "res://level/level.lmbake",                 # level.lmbake: loaded by path (lightmap GI)
	"res://enemies/red_robot/red_robot.tscn", "res://enemies/red_robot/laser/impact_effect/impact_effect.tscn",
	"res://player/player.tscn", "res://menu/settings.gd",                # settings.gd is the Settings autoload
	"res://default_bus_layout.tres",                                     # audio bus layout (project setting)
]
var seen := {}
var skip := {}
var literal_re: RegEx


func walk(p: String) -> void:
	if seen.has(p) or skip.has(p) or not p.begins_with("res://"):
		return
	seen[p] = true
	for d in ResourceLoader.get_dependencies(p):
		var parts := d.split("::")
		walk(parts[parts.size() - 1])
	# ResourceLoader does not report what a script preload()s or load()s, so read the script text and follow
	# every "res://...<resource extension>" string literal in it.
	if p.ends_with(".gd") and FileAccess.file_exists(p):
		for m in literal_re.search_all(FileAccess.get_file_as_string(p)):
			var target := m.get_string(1)
			if FileAccess.file_exists(target):
				walk(target)


func _init() -> void:
	# --no-lightmap (after `--`): lean build. Drops the lightmap GI data (~98 MB: level.lmbake + its EXR atlas), which
	# only `--gi lightmap` uses. The benchmark then refuses that mode with a clear error.
	if "--no-lightmap" in OS.get_cmdline_user_args():
		skip["res://level/level.lmbake"] = true
	literal_re = RegEx.create_from_string("\"(res://[^\"]+\\.(?:tscn|tres|gd|res|scn|glb|mesh|material|png|jpg|svg|exr|wav|ogg|gdshader|lmbake))\"")
	for p in ROOTS:
		walk(p)
	var paths: Array = []
	for p in seen.keys():
		if FileAccess.file_exists(p):
			paths.append(p)
	paths.sort()
	var quoted := PackedStringArray()
	for p in paths:
		quoted.append('"%s"' % p)
	var files := "PackedStringArray(%s)" % ", ".join(quoted)
	var win := "debug/export_console_wrapper=0\nbinary_format/architecture=\"x86_64\"\ncodesign/enable=false\napplication/modify_resources=false\napplication/product_name=\"OCGP TPS Benchmark\"\napplication/file_description=\"OC Grand Prix - TPS benchmark\""
	var cfg := _preset(0, "Windows Desktop", "Windows Desktop", "build/OCGP-TPS.exe", win, files)
	var f := FileAccess.open("res://export_presets.cfg", FileAccess.WRITE)
	f.store_string(cfg)
	f.close()
	print("export_presets.cfg written: %d files listed" % paths.size())
	quit()


func _preset(i: int, pname: String, platform: String, out: String, opts: String, files: String) -> String:
	return """[preset.%d]

name="%s"
platform="%s"
runnable=true
advanced_options=false
dedicated_server=false
custom_features="ocgp"
export_filter="resources"
export_files=%s
include_filter="ocgp_bench/*.ocgp"
exclude_filter="ocgp_bench/record.*, ocgp_bench/bake.*, ocgp_bench/export_list.*"
export_path="%s"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.%d.options]

custom_template/debug=""
custom_template/release=""
binary_format/embed_pck=true
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
%s
""" % [i, pname, platform, files, out, i, opts]

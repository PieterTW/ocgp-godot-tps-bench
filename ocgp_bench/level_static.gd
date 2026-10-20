# OCGP benchmark variant of the TPS demo's level.gd.
#
# Derived from godotengine/tps-demo level/level.gd
#   Code (c) 2018-2021 Juan Linietsky, Godot Engine contributors — MIT license.
#
# KEPT:    graphics / global-illumination setup (driven by Settings.config_file,
#          which bench.gd pins before the level loads).
# REMOVED: player + robot spawning, multiplayer hooks, quit input — none of it
#          belongs in a fixed-workload benchmark. The camera is driven by bench.gd.
extends Node3D

var lightmap_gi: LightmapGI = null

@onready var world_environment: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	Settings.apply_graphics_settings(get_window(), world_environment.environment, self)

	if Settings.config_file.get_value("rendering", "gi_type") == Settings.GIType.SDFGI:
		setup_sdfgi()
	elif Settings.config_file.get_value("rendering", "gi_type") == Settings.GIType.VOXEL_GI:
		setup_voxelgi()
	else:
		setup_lightmapgi()


func setup_sdfgi() -> void:
	world_environment.environment.sdfgi_enabled = true
	$VoxelGI.hide()
	$ReflectionProbes.hide()
	# LightmapGI nodes override SDFGI (even when hidden)
	# so we need to free the LightmapGI node if it exists
	if lightmap_gi != null:
		lightmap_gi.queue_free()

	if Settings.config_file.get_value("rendering", "gi_quality") == Settings.GIQuality.HIGH:
		RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_96)
	elif Settings.config_file.get_value("rendering", "gi_quality") == Settings.GIQuality.LOW:
		RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_32)
	else:
		world_environment.environment.sdfgi_enabled = false


func setup_voxelgi() -> void:
	world_environment.environment.sdfgi_enabled = false
	$VoxelGI.show()
	$ReflectionProbes.hide()
	# LightmapGI nodes override VoxelGI (even when hidden)
	# so we need to free the LightmapGI node if it exists
	if lightmap_gi != null:
		lightmap_gi.queue_free()

	if Settings.config_file.get_value("rendering", "gi_quality") == Settings.GIQuality.HIGH:
		RenderingServer.voxel_gi_set_quality(RenderingServer.VOXEL_GI_QUALITY_HIGH)
	elif Settings.config_file.get_value("rendering", "gi_quality") == Settings.GIQuality.LOW:
		RenderingServer.voxel_gi_set_quality(RenderingServer.VOXEL_GI_QUALITY_LOW)
	else:
		$VoxelGI.hide()


func setup_lightmapgi() -> void:
	world_environment.environment.sdfgi_enabled = false
	$VoxelGI.hide()
	$ReflectionProbes.show()
	# If no LightmapGI node, create one
	if lightmap_gi == null:
		var new_gi := LightmapGI.new()
		new_gi.light_data = load("res://level/level.lmbake")
		new_gi.name = "LightmapGI"
		lightmap_gi = new_gi
		add_child(new_gi)

	if Settings.config_file.get_value("rendering", "gi_quality") == Settings.GIQuality.DISABLED:
		lightmap_gi.hide()
		$ReflectionProbes.hide()

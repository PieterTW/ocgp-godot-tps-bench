# Replaces red_robot.gd in the benchmark. The robot's animations contain method-call tracks that
# expect these functions on the root node; here they do nothing (behaviour is driven by bench.gd).
extends CharacterBody3D

func shoot_check() -> void:
	pass


func resume_approach() -> void:
	pass

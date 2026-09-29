# Runs the demo facility for a few seconds: robots load their clips, ride
# their rails, swing, and play actions.
extends SceneTree

var failures := 0


func _initialize() -> void:
	var demo: Node3D = (load("res://game/demo_facility.tscn") as PackedScene).instantiate()
	get_root().add_child(demo)
	await process_frame

	var tinker: RobotActor = demo.tinker
	var hauler: RobotActor = demo.hauler
	_check(tinker.tree != null and tinker.tree.active, "tinker has a live AnimationTree")
	_check(hauler.tree != null and hauler.tree.active, "hauler has a live AnimationTree")
	_check(tinker.idle_names.size() > 0 and tinker.action_names.size() > 0,
		"tinker clips found (idles %s, actions %s)" % [tinker.idle_names, tinker.action_names])

	var core: Node3D = tinker.rig.get_node("Core")
	var core_start := core.position
	var p0: float = demo.tinker_rider.progress
	_check(tinker.play_action(tinker.action_names[0]), "tinker plays an action on request")
	await create_timer(3.0).timeout
	_check(demo.tinker_rider.progress > p0 + 0.5, "tinker patrols its rail (%.2f m)" % (demo.tinker_rider.progress - p0))
	_check(core.position.distance_to(core_start) > 0.001, "tinker's baked animation moves its core")
	_check(demo.hauler_rider.progress > 0.3, "hauler drives toward its first station (%.2f m)" % demo.hauler_rider.progress)
	var swing: Node3D = demo.get_node("TinkerRail/Rider/Swing")
	_check(swing.rotation.length() > 0.0001, "tinker swings on the rail (%.4f rad)" % swing.rotation.length())

	demo.free()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

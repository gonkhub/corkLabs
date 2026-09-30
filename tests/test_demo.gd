# Runs the demo facility for a few seconds: robots load their clips, follow
# their facility-sim selves along the rails, swing, work, and take orders.
extends SceneTree

const SAVE := "user://test_demo_facility_save.json"

var failures := 0


func _initialize() -> void:
	var facility: Node = get_root().get_node("Facility")
	facility.wipe_save(SAVE)
	var demo: Node3D = (load("res://game/demo_facility.tscn") as PackedScene).instantiate()
	demo.save_path = SAVE
	get_root().add_child(demo)
	await process_frame
	await process_frame

	var tinker: RobotActor = demo.tinker
	var hauler: RobotActor = demo.hauler
	_check(tinker.tree != null and tinker.tree.active, "tinker has a live AnimationTree")
	_check(hauler.tree != null and hauler.tree.active, "hauler has a live AnimationTree")
	_check(tinker.idle_names.size() > 0 and tinker.action_names.size() > 0,
		"tinker clips found (idles %s, actions %s)" % [tinker.idle_names, tinker.action_names])
	_check(facility.running and facility.sim.get_system("robot_tinker") != null, "the demo runs the standard facility")

	var sim: FacilitySim = facility.sim
	var t_agent: RobotAgent = sim.get_system("robot_tinker")
	var h_agent: RobotAgent = sim.get_system("robot_hauler")
	_check(absf(demo.tinker_rider.progress - t_agent.pos) < 0.05, "tinker starts where the sim has it (%.2f m)" % t_agent.pos)

	# Real time alone changes nothing in the facility...
	var t0 := sim.time()
	await create_timer(1.0).timeout
	_check(sim.time() == t0, "facility time doesn't move on its own")
	# ...a player action does, and the 3D robots follow.
	var board: WorkBoard = sim.get_system("work")
	var job := board.post(sim, "Clear debris", "heavy", "bay_3", 300.0, 3, "test")
	facility.spend(12.0, "test: wait")
	_check(h_agent.activity_key() == "work:%d" % job, "hauler takes the critical job (%s)" % h_agent.doing_text(sim))
	var gap_before: float = absf(demo.hauler_rider.progress - h_agent.pos)
	await create_timer(3.0).timeout
	var gap_after: float = absf(demo.hauler_rider.progress - h_agent.pos)
	_check(gap_before > 1.0 and gap_after < gap_before - 0.5, "the 3D hauler glides to its sim position (%.2f -> %.2f m)" % [gap_before, gap_after])
	var swing: Node3D = demo.get_node("HaulerRail/Rider/Swing")
	_check(swing.rotation.length() > 0.0001, "hauler swings on the rail (%.4f rad)" % swing.rotation.length())
	var core: Node3D = tinker.rig.get_node("Core")
	var core_start := core.position
	await create_timer(0.5).timeout
	_check(core.position.distance_to(core_start) > 0.0001, "tinker's baked idle keeps playing")

	# Orders from the console spend facility time and get an answer.
	demo.selected = "hauler"
	var before := sim.time()
	demo._order(h_agent, "recharge", -1, "recharge")
	_check(sim.time() - before >= 119.9, "an order costs facility time (%.0f s)" % (sim.time() - before))
	_check(demo.last_reply.begins_with("Hauler:"), "the robot answers (%s)" % demo.last_reply)
	_check(demo._console_text().contains("HAULER"), "the console lists the robots")

	demo.free()
	facility.end_session()
	facility.wipe_save(SAVE)
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

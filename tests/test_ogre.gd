# Checks Ogre, the stationary crane core: the rig (crane IK with the knuckle
# up, the winch, the grab, the eye beam and blink), and the facility side
# (it never moves, works only within its crane's reach, stacks freight,
# charges where it hangs, turns down work out of reach, and doesn't get the
# rail robots' lines), plus its 3D view.
extends SceneTree

var failures := 0


func _initialize() -> void:
	_test_rig()
	_test_never_moves()
	_test_reach_and_orders()
	_test_freight()
	_test_speech()
	await _test_world()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _frame(rel_right := Vector3(0.22, -0.58, -0.22)) -> PerformanceFrame:
	var f := PerformanceFrame.new()
	f.head = Transform3D(Basis(), Vector3(0, 1.65, 0))
	f.left = Transform3D(Basis(), Vector3(-0.25, 1.05, -0.2))
	f.right = Transform3D(Basis(), f.head.origin + rel_right)
	return f


func _stiff_rig() -> RobotRig:
	var rig := RobotLibrary.instantiate("ogre")
	var p: RobotProfile = rig.profile.duplicate()
	for key in ["body", "head", "eye", "hand", "tool"]:
		p.set(key + "_frequency", SecondOrder.PASSTHROUGH_HZ)
	p.amplitude = 1.0
	rig.profile = p
	rig.set("hook_frequency", SecondOrder.PASSTHROUGH_HZ)
	rig.begin(1.65)
	return rig


func _drive(rig: RobotRig, f: PerformanceFrame, frames := 3) -> void:
	for i in frames:
		rig.drive(f, 1.0 / 30.0)


func _test_rig() -> void:
	_check(RobotLibrary.ids().has("ogre"), "robot library finds ogre (%s)" % str(RobotLibrary.ids()))
	var rig := _stiff_rig()
	var rel := Vector3(0.3, -0.6, -0.35)
	var f := _frame(rel)
	_drive(rig, f)
	var tip := rig.rig_xform(rig.get_node("Core/CraneBase/Boom/Jib/Tip")).origin
	var target: Vector3 = rig.get_node("Core").position + rig.tip_rest + (rel - rig.profile.performer_rest_hand) * rig.profile.reach_scale
	_check(tip.distance_to(target) < 0.002, "the crane's jib tip reaches its IK target (off by %.4f m)" % tip.distance_to(target))
	var shoulder := rig.rig_xform(rig.get_node("Core/CraneBase/Boom")).origin
	var knuckle := rig.rig_xform(rig.get_node("Core/CraneBase/Boom/Jib")).origin
	_check(knuckle.y > shoulder.y and knuckle.y > tip.y, "the knuckle points up, like a crane (not down, like a knee)")

	# The hook hangs straight below the tip (springs off), on the cable.
	var hook := rig.rig_xform(rig.get_node("Core/CraneBase/Boom/Jib/Tip/Hook")).origin
	_check(Vector2(hook.x - tip.x, hook.z - tip.z).length() < 0.01 and absf(tip.y - hook.y - rig.cable_rest) < 0.01,
		"the hook hangs straight down from the tip (%.2f below)" % (tip.y - hook.y))
	f.left_trigger = 1.0
	_drive(rig, f, 90)
	var lowered := rig.rig_xform(rig.get_node("Core/CraneBase/Boom/Jib/Tip/Hook")).origin
	_check(tip.y - lowered.y > rig.cable_max - 0.05, "the left trigger pays out cable (hook %.2f below the tip)" % (tip.y - lowered.y))

	var open: float = rig.get_node("Core/CraneBase/Boom/Jib/Tip/Hook/JawA").rotation.x
	f.right_trigger = 1.0
	_drive(rig, f)
	var closed: float = rig.get_node("Core/CraneBase/Boom/Jib/Tip/Hook/JawA").rotation.x
	_check(open > 0.6 and absf(closed) < 0.01, "the right trigger closes the grab (%.2f -> %.2f rad)" % [open, closed])

	var glow: SpotLight3D = rig.get_node("Core/Eye/Glow")
	_check(rig.get_node("Core/Eye/Beam") is MeshInstance3D and glow.spot_angle > 5.0, "the eye has a spotlight and a light cone")
	var lit := glow.light_energy
	f.right_buttons = PerformanceFrame.BTN_BY
	_drive(rig, f, 2)
	_check(glow.light_energy > lit * 1.5, "B/Y flashes the beam brighter (%.1f -> %.1f)" % [lit, glow.light_energy])
	f.right_buttons = 0
	_drive(rig, f, 60)
	f.left_buttons = PerformanceFrame.BTN_AX
	_drive(rig, f, 10)
	_check(glow.light_energy < lit * 0.3, "a blink shuts the eye and cuts the beam (%.1f -> %.1f)" % [lit, glow.light_energy])
	# The eye looks down a little at rest, so the beam lands on the floor.
	var eye_fwd := rig.rig_xform(rig.get_node("Core/Eye")).basis * Vector3.FORWARD
	_check(eye_fwd.y < -0.2, "at rest the eye angles down at the floor (%.2f)" % eye_fwd.y)
	rig.free()


func _facility(seed_value := 3) -> FacilitySim:
	var sim := FacilitySim.new()
	var systems := FacilitySetup.systems()
	for s in systems:
		sim.add_system(s)
	sim.new_game(seed_value)
	for s in systems:
		if s.has_method("sim_start"):
			s.sim_start(sim)
	return sim


func _test_never_moves() -> void:
	var sim := _facility()
	var ogre: RobotAgent = sim.get_system("robot_ogre")
	var l: FacilityLayout = sim.get_system("layout")
	_check(ogre != null and ogre.traits.stationary, "Ogre is in the facility, and stationary")
	_check(ogre.room(sim) == "hangar", "it lives in the hangar")
	var mount := l.world_pos(ogre.seg, ogre.off)
	var hangar: Rect2 = l.rooms.hangar.rect
	_check(Vector2(mount.x, mount.z).distance_to(hangar.get_center()) < 1.0, "hanging from the centre of its ceiling (%s)" % str(mount))
	var seg := ogre.seg
	var off := ogre.off
	var moved := false
	for i in 12:
		sim.advance(600.0)   # two hours, in steps
		moved = moved or ogre.seg != seg or absf(ogre.off - off) > 0.001 or ogre.moving
	_check(not moved, "after two busy hours it hasn't moved an inch")
	# Low on power: it charges where it hangs.
	ogre.power = 0.1
	sim.advance(30.0)
	var p0 := ogre.power
	sim.advance(120.0)
	_check(ogre.activity.kind == "recharge" and ogre.power > p0 and ogre.seg == seg, "it charges in place, from its mains coupling")
	# Rail robots can't use its mount, or the deep stacks.
	var hauler: RobotAgent = sim.get_system("robot_hauler")
	_check(not hauler.why_cant_reach(sim, "o_mains").is_empty() and not hauler.why_cant_reach(sim, "stacks").is_empty(),
		"rail robots can't get to Ogre's mount or the deep stacks")
	_check(hauler.why_cant_reach(sim, "loading").is_empty(), "but can reach the hangar loading bay (through the hangar door)")


func _test_reach_and_orders() -> void:
	var sim := _facility(4)
	var ogre: RobotAgent = sim.get_system("robot_ogre")
	var board: WorkBoard = sim.get_system("work")
	for j in board.open_jobs():
		board.cancel(sim, j.id, "test")
	var far := board.post(sim, "Clear debris", "heavy", "bay_2", 60.0, 3, "test")
	sim.advance(5.0)
	_check(ogre.activity_key() != "work:%d" % far and not ogre.scores.any(func(o): return o.key == "work:%d" % far),
		"heavy work in the main hall isn't even an option for it")
	var r := ogre.give_order(sim, "job", far)
	_check(not r.ok and r.reply.contains("out of my reach"), "ordered there, it says it's out of reach (%s)" % r.reply)
	var near := board.post(sim, "Lift crate", "heavy", "loading", 60.0, 3, "test")
	r = ogre.give_order(sim, "job", near)
	_check(r.ok and ogre.activity_key() == "work:%d" % near, "the loading bay is within reach: it takes it (%s)" % r.reply)
	sim.advance(120.0)
	_check(board.get_job(near).status == "done" and ogre.seg == "ogre_mount", "and does it without moving")


func _test_freight() -> void:
	var sim := _facility(5)
	var plant: FacilityPlant = sim.get_system("plant")
	var board: WorkBoard = sim.get_system("work")
	var ogre: RobotAgent = sim.get_system("robot_ogre")
	for j in board.open_jobs():
		board.cancel(sim, j.id, "test")
	sim.schedule_in(0.0, "plant_fault", {"device": "freight_stacks"})
	sim.step()
	var d := plant.device("freight_stacks")
	_check(int(d.job) >= 0 and not d.fault, "freight arrives in the deep stacks: a job, not a fault")
	var job := board.get_job(int(d.job))
	_check(job.skill == "heavy" and job.station == "stacks", "heavy work at the deep stacks (%s)" % job.title)
	sim.advance(1800.0)
	_check(board.get_job(job.id).status == "done" and str(board.get_job(job.id).claimed_by) == "robot_ogre",
		"Ogre stacks it (%s, by %s)" % [board.get_job(job.id).status, board.get_job(job.id).claimed_by])
	var lines := sim.journal.entries.map(func(e): return str(e.text))
	_check(lines.any(func(t: String): return t.contains("Freight at Deep stacks stacked by Ogre")), "the journal says so")
	_check(plant.device_text("freight_stacks").contains("clear"), "and the stacks are clear again")


func _test_speech() -> void:
	var lib := BarkLibrary.new()
	lib.load_text("""start_job | any !ogre |  | Heading to {station}.
start_job | ogre |  | Lowering.
idle | any |  | Standing by.""")
	var o := lib.candidates("start_job", "ogre", {}).map(func(c): return c.text)
	var t := lib.candidates("start_job", "tinker", {}).map(func(c): return c.text)
	_check(o == ["Lowering."], "Ogre doesn't get the rail robots' lines (%s)" % str(o))
	_check(t == ["Heading to {station}."], "the others still do (%s)" % str(t))
	_check(lib.candidates("idle", "ogre", {}).size() == 1, "and 'any' lines are for Ogre too")
	var real := BarkLibrary.shared()
	for trig in ["start_job", "job_done", "idle", "route_blocked", "recharge"]:
		_check(not real.candidates(trig, "ogre", {}).is_empty(), "barks.txt has Ogre lines for %s" % trig)
	var tr := RobotTraits.load_for("ogre")
	_check(tr.voice_pitch < RobotTraits.load_for("hauler").voice_pitch, "Ogre's voice is the lowest")


func _test_world() -> void:
	var facility: Node = get_root().get_node("Facility")
	facility.wipe_save("user://test_ogre_save.json")
	facility.start_session(FacilitySetup.systems(), "user://test_ogre_save.json", 9)
	var world: Node3D = (load("res://game/facility_world.tscn") as PackedScene).instantiate()
	get_root().add_child(world)
	for i in 5:   # let the animation tree settle
		await process_frame
	var ov = world.views["ogre"]
	var agent: RobotAgent = facility.sim.get_system("robot_ogre")
	var l := FacilitySetup.layout()
	_check(is_equal_approx(ov.actor.scale.x, 8.0), "the 3D Ogre is drawn huge (x%.1f)" % ov.actor.scale.x)
	_check(ov.position.distance_to(l.world_pos(agent.seg, agent.off)) < 0.01, "it hangs at its mount")
	var core: Node3D = ov.actor.rig.get_node("Core")
	_check(core.global_position.y > 8.0 and core.global_position.y < 18.0, "its core hangs in the middle of the hangar's height (%.1f m)" % core.global_position.y)
	_check(world.camera_rooms.count("hangar") >= 1, "a camera watches the hangar")
	var rail_bits: int = world.get_node("Rails").get_child_count()
	var expect := 0
	for sid in l.segments:
		if not l.is_pad(sid):
			expect += 1
	for nid in l.nodes:
		if not (nid.begins_with("ogre_mount") or nid.begins_with("deep_stacks")):
			expect += 1
	_check(rail_bits == expect, "no rail is drawn to the pads (%d pieces, expected %d)" % [rail_bits, expect])
	world.free()
	facility.end_session()
	facility.wipe_save("user://test_ogre_save.json")


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

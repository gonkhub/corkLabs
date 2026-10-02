# Checks rooms and the rail network: route planning across rooms, route
# caveats (a hatch too narrow for Hauler, a freight gate that jams and blocks
# the way), robots re-routing when a route closes and giving up (and saying
# why) when there's no way at all, the bigger Hauler, and the 3D world being
# built from the same floor plan.
extends SceneTree

var failures := 0


func _initialize() -> void:
	SupervisorArchive.use_file("user://test_supervisor_archive.json")   # never the real personnel file
	_test_floor_plan()
	_test_planning()
	_test_caveats()
	_test_rerouting()
	_test_giving_up_and_orders()
	_test_gate_fault()
	await _test_world()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


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


func _test_floor_plan() -> void:
	var l := FacilitySetup.layout()
	_check(l.rooms.size() >= 3, "at least three rooms (%d)" % l.rooms.size())
	var hall: Rect2 = l.rooms.hall.rect
	var biggest := true
	for id in l.rooms:
		var area := (l.rooms[id].rect as Rect2).get_area()
		# Ogre's hangar is big by design (a 12 m robot lives in it), but still smaller than the hall.
		if id != "hall" and (area * 4.0 > hall.get_area() if id != "hangar" else area >= hall.get_area()):
			biggest = false
	_check(biggest and hall.get_area() >= 3000.0, "the main hall is very large (%d m²) and the others much smaller (Ogre's hangar: smaller)" % hall.get_area())
	# Every room connects to the hall, some by more than one passage.
	var links := {}
	for sid in l.passages():
		var s := l.segment(sid)
		for n in [s.a, s.b]:
			var r: String = l.nodes[n].room
			if r != "hall":
				links[r] = int(links.get(r, 0)) + 1
	_check(links.size() == l.rooms.size() - 1, "every smaller room joins the hall")
	_check(links.values().any(func(v): return v >= 2), "some rooms are joined by more than one passage")
	for id in l.stations:
		var st := l.station(id)
		_check(l.segments.has(st.segment), "station %s sits on a rail" % id)


func _test_planning() -> void:
	var l := FacilitySetup.layout()
	var dock := l.station("t_dock")
	var bench := l.station("bench")
	var r := l.plan(dock.segment, dock.offset, bench.segment, bench.offset, 0.7)
	_check(not r.is_empty(), "a small robot can plan from the docks to the workshop")
	var through: Array = r.legs.map(func(leg): return leg.seg)
	_check(through.has("dock_door") and through.has("ws_hatch"), "through the dock door and the workshop hatch (%s)" % str(through))
	# Legs join up end to end.
	var joined := true
	for i in range(1, r.legs.size()):
		var prev := l.world_pos(r.legs[i - 1].seg, r.legs[i - 1].to)
		var next := l.world_pos(r.legs[i].seg, r.legs[i].from)
		if prev.distance_to(next) > 0.01:
			joined = false
	_check(joined, "the route's legs join up end to end")
	var same := l.plan("hall_s", 5.0, "hall_s", 20.0, 0.7)
	_check(same.legs.size() == 1 and is_equal_approx(float(same.length), 15.0), "along one rail it's one leg")


func _test_caveats() -> void:
	var l := FacilitySetup.layout()
	var hauler := RobotTraits.load_for("hauler")
	var tinker := RobotTraits.load_for("tinker")
	_check(hauler.width > l.segment("ws_hatch").clearance and tinker.width < l.segment("ws_hatch").clearance,
		"Hauler is too wide for the workshop hatch; Tinker fits")
	_check(hauler.visual_scale >= 2.0, "Hauler is much larger (x%.1f)" % hauler.visual_scale)
	var dock := l.station("h_dock")
	var relay := l.station("relay")
	var r := l.plan(dock.segment, dock.offset, relay.segment, relay.offset, hauler.width)
	var through: Array = r.legs.map(func(leg): return leg.seg) if not r.is_empty() else []
	_check(through.has("freight_gate") and not through.has("ws_hatch"), "Hauler's way into the workshop is the freight gate (%s)" % str(through))
	var pd := l.station("t_dock")
	var pods := l.station("pods_a")
	var tr := l.plan(pd.segment, pd.offset, pods.segment, pods.offset, tinker.width)
	var hr := l.plan(dock.segment, dock.offset, pods.segment, pods.offset, hauler.width)
	_check(tr.legs.map(func(leg): return leg.seg).has("pod_duct"), "Tinker takes the pod bay duct shortcut")
	_check(not hr.legs.map(func(leg): return leg.seg).has("pod_duct") and float(hr.length) > float(tr.length),
		"Hauler has to go the long way round, through the door (%.0f m vs %.0f m)" % [hr.length, tr.length])
	l.set_blocked(null, "freight_gate", true, "jammed")
	_check(l.plan(dock.segment, dock.offset, relay.segment, relay.offset, hauler.width).is_empty(),
		"with the freight gate blocked, Hauler can't get into the workshop at all")
	_check(not l.plan(pd.segment, pd.offset, relay.segment, relay.offset, tinker.width).is_empty(),
		"but Tinker still can, through the hatch")


func _test_rerouting() -> void:
	var sim := _facility()
	var l: FacilityLayout = sim.get_system("layout")
	var tinker: RobotAgent = sim.get_system("robot_tinker")
	var board: WorkBoard = sim.get_system("work")
	for j in board.open_jobs():
		board.cancel(sim, j.id, "test")
	var id := board.post(sim, "Recalibrate", "precise", "pods_a", 60.0, 3, "test")
	sim.advance(5.0)
	_check(tinker.activity_key() == "work:%d" % id and tinker.route.any(func(leg): return leg.seg == "pod_duct"),
		"Tinker heads for the pods through the duct (%s %s %s)" % [tinker.activity_key(), str(board.get_job(id)), str(tinker.scores.slice(0, 3).map(func(o): return "%s %.2f %s" % [o.key, o.score, o.why]))])
	l.set_blocked(sim, "pod_duct", true, "debris")
	sim.advance(2.0)
	_check(tinker.activity_key() == "work:%d" % id and not tinker.route.any(func(leg): return leg.seg == "pod_duct"),
		"when the duct is blocked on the way, it re-plans another route and carries on")
	sim.advance(400.0)
	_check(board.get_job(id).status == "done", "and gets there by the long way")
	var lines := sim.journal.entries.map(func(e): return str(e.text))
	_check(lines.any(func(t: String): return t.contains("Pod bay duct is BLOCKED")), "the blocked route is journaled")


func _test_giving_up_and_orders() -> void:
	var sim := _facility(4)
	var l: FacilityLayout = sim.get_system("layout")
	var hauler: RobotAgent = sim.get_system("robot_hauler")
	var board: WorkBoard = sim.get_system("work")
	sim.remove_system("robot_tinker")   # just Hauler here (Tinker could take the job through the hatch)
	for j in board.open_jobs():
		board.cancel(sim, j.id, "test")
	l.set_blocked(sim, "freight_gate", true, "jammed")
	sim.step()
	var id := board.post(sim, "Lift crate", "heavy", "bench", 60.0, 3, "test")
	var r := hauler.give_order(sim, "job", id)
	_check(not r.ok and r.reply.contains("Freight gate is blocked"), "ordered somewhere it can't get to, it says why (%s)" % r.reply)
	sim.advance(10.0)
	_check(hauler.activity_key() != "work:%d" % id, "and doesn't try")
	l.set_blocked(sim, "freight_gate", false)
	sim.advance(1.0)
	r = hauler.give_order(sim, "job", id)
	_check(r.ok and hauler.activity_key() == "work:%d" % id, "once the gate reopens, the same order works (%s)" % r.reply)
	# Blocked halfway there: nowhere to go, so it gives up and says so.
	sim.advance(20.0)
	l.set_blocked(sim, "freight_gate", true, "jammed again")
	sim.advance(3.0)
	if hauler.seg != "freight_gate" and l.room_at(hauler.seg, hauler.off) != "workshop":
		_check(hauler.activity_key() != "work:%d" % id, "if the only way closes on the way, it gives up the job")
		var chatter: RobotChatter = sim.get_system("chatter")
		_check(chatter.recent.any(func(line): return line.robot == "hauler" and line.trigger == "route_blocked"),
			"and says it can't get there")


func _test_gate_fault() -> void:
	var sim := _facility(5)
	var l: FacilityLayout = sim.get_system("layout")
	var plant: FacilityPlant = sim.get_system("plant")
	var board: WorkBoard = sim.get_system("work")
	sim.schedule_in(0.0, "plant_fault", {"device": "gate"})
	sim.step()
	_check(plant.device("gate").fault and l.segment("freight_gate").blocked, "a jammed freight gate blocks the route")
	var job := board.get_job(int(plant.device("gate").job))
	board.claim(job.id, "robot_tinker")
	board.add_progress(sim, job.id, "robot_tinker", 1e6)
	sim.step()
	_check(not plant.device("gate").fault and not l.segment("freight_gate").blocked, "unjamming it reopens the route")
	# Blocked state survives save/load.
	l.set_blocked(sim, "pod_door", true, "test")
	var b := FacilitySim.new()
	for s in FacilitySetup.systems():
		b.add_system(s)
	b.load_data(JSON.parse_string(JSON.stringify(sim.save_data())))
	_check((b.get_system("layout") as FacilityLayout).segment("pod_door").blocked, "blocked routes survive save/load")


func _test_world() -> void:
	var facility: Node = get_root().get_node("Facility")
	facility.wipe_save("user://test_rooms_save.json")
	facility.start_session(FacilitySetup.systems(), "user://test_rooms_save.json", 9)
	var world: Node3D = (load("res://game/facility_world.tscn") as PackedScene).instantiate()
	get_root().add_child(world)
	await process_frame
	_check(world.find_children("Room_*", "", false, false).size() == FacilitySetup.layout().rooms.size(), "the 3D world builds every room")
	_check(world.find_children("Passage_*", "", false, false).size() == FacilitySetup.layout().passages().size(), "and every passage (frame, sign, shutter)")
	_check(world.cameras.size() == FacilitySetup.cameras().size(), "and every camera")
	var hv = world.views["hauler"]
	_check(is_equal_approx(hv.actor.scale.x, RobotTraits.load_for("hauler").visual_scale), "the 3D Hauler is drawn at its big scale")
	var agent: RobotAgent = facility.sim.get_system("robot_hauler")
	await process_frame
	_check(hv.seg == agent.seg and absf(hv.off - agent.off) < 0.1, "the 3D robot starts where the sim has it")
	(facility.sim.get_system("layout") as FacilityLayout).set_blocked(facility.sim, "dock_door", true, "test")
	await process_frame
	_check(world._shutters["dock_door"].visible, "a blocked passage shows its shutter")
	world.free()
	facility.end_session()
	facility.wipe_save("user://test_rooms_save.json")


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

# The units' lives between the work: Hauler's wrench (fetched for the jobs
# that need it; cut off from it by a jammed gate it asks for Tinker, who
# fetches it through the hatch and brings it; put back when it's idle), and
# habits (what an idle unit does with itself; Ogre swinging its crate).
extends SceneTree

var failures := 0


func _initialize() -> void:
	SupervisorArchive.use_file("user://test_supervisor_archive.json")
	_test_wrench()
	_test_cut_off()
	_test_habits()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _facility(seed_value: int) -> FacilitySim:
	var sim := FacilitySim.new()
	var systems := FacilitySetup.systems()
	for s in systems:
		sim.add_system(s)
	sim.new_game(seed_value)
	for s in systems:
		if s.has_method("sim_start"):
			s.sim_start(sim)
	(sim.get_system("robot_ogre") as RobotAgent).repair(sim)
	var plant: FacilityPlant = sim.get_system("plant")
	var layout: FacilityLayout = sim.get_system("layout")
	var board: WorkBoard = sim.get_system("work")
	for j in board.open_jobs():
		board.cancel(sim, int(j.id), "test")
	for id in plant.device_ids():
		plant.devices[id].fault = false
		if plant.devices[id].has("blocks"):
			layout.set_blocked(sim, plant.devices[id].blocks, false)
	for b in FacilitySetup.robots(sim):
		b.wear = 0.1
		b.power = 1.0
		b.stability = 0.9
		if b.offline():
			b.activity = {"kind": "idle"}
	return sim


# Run until `done` holds (or `hours` pass), keeping power up and the plant quiet.
func _until(sim: FacilitySim, done: Callable, hours := 3.0) -> bool:
	var t := 0.0
	while t < hours * 3600.0:
		if done.call():
			return true
		for b in FacilitySetup.robots(sim):
			b.power = maxf(b.power, 0.6)
			b.wear = minf(b.wear, 0.3)
		sim.advance(60.0)
		t += 60.0
	return done.call()


func _test_wrench() -> void:
	var sim := _facility(51)
	var plant: FacilityPlant = sim.get_system("plant")
	var board: WorkBoard = sim.get_system("work")
	var props: UnitProps = sim.get_system("props")
	_check(props.item("wrench").at == "tool_rack", "Hauler's wrench lives on the tool rack")
	plant.devices.pipe_2.job = -1
	sim.schedule_in(0.0, "plant_fault", {"device": "pipe_2"})
	sim.step()
	var leak := board.get_job(int(plant.device("pipe_2").job))
	board.request(sim, int(leak.id))
	_check(_until(sim, func(): return board.get_job(int(leak.id)).status == "done"), "Hauler clamps the leak")
	var lines := sim.journal.entries.map(func(e): return str(e.text))
	_check(lines.any(func(t: String): return t.contains("Hauler picked up Hauler's wrench")), "after fetching its wrench first")
	_check(_until(sim, func(): return props.item("wrench").at == "tool_rack", 2.0), "and puts it back when it's idle")


func _test_cut_off() -> void:
	var sim := _facility(52)
	var plant: FacilityPlant = sim.get_system("plant")
	var board: WorkBoard = sim.get_system("work")
	var props: UnitProps = sim.get_system("props")
	var reqs: UnitRequests = sim.get_system("requests")
	var hauler: RobotAgent = sim.get_system("robot_hauler")
	var camp: Campaign = sim.get_system("campaign")
	camp.state = "on_duty"   # (requests are asked on duty)
	# The gate jams: Hauler's way into the workshop, where its wrench is.
	plant.devices.gate.job = -1
	sim.schedule_in(0.0, "plant_fault", {"device": "gate"})
	sim.step()
	var gate := board.get_job(int(plant.device("gate").job))
	board.request(sim, int(gate.id))
	hauler.give_order(sim, "job", int(gate.id))
	_check(_until(sim, func(): return reqs.requests.any(func(q): return q.kind == "tool"), 1.0), "cut off from its wrench, Hauler asks")
	var q: Array = reqs.requests.filter(func(x): return x.kind == "tool")
	if q.is_empty():
		return
	_check(str(q[0].text).contains("Send Tinker") or str(q[0].options).contains("Send Tinker"), "to send Tinker for it")
	reqs.answer(sim, int(q[0].id), 0)
	_check(_until(sim, func(): return props.held_by("wrench", "hauler"), 3.0), "Tinker fetches it through the hatch and brings it (%s)" % str(props.item("wrench")))
	_check(_until(sim, func(): return board.get_job(int(gate.id)).status == "done", 2.0), "and Hauler unjams the gate")


func _test_habits() -> void:
	var sim := _facility(53)
	var tinker: RobotAgent = sim.get_system("robot_tinker")
	var ogre: RobotAgent = sim.get_system("robot_ogre")
	var props: UnitProps = sim.get_system("props")
	_check(tinker.habits().size() >= 3 and ogre.habits().size() >= 2, "each unit has habits")
	var seen := {}
	var ok := _until(sim, func():
		for b in [tinker, ogre]:
			if b.activity.kind == "habit":
				seen[str(b.activity.habit)] = true
		return seen.size() >= 2, 4.0)
	_check(ok, "with nothing to do, they go and do their habits (%s)" % str(seen.keys()))
	var spot := str(props.item("crate").home)
	ogre._habit_last.clear()
	ogre._idle_since = sim.time() - 2000.0
	for h in ogre.habits():
		if str(h.id) != "swing_crate":
			ogre._habit_last[str(h.id)] = sim.time()
	_check(_until(sim, func(): return str(props.item("crate").home) != spot, 2.0), "Ogre swings its crate over to its other spot (%s -> %s)" % [spot, props.item("crate").home])


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS  " + what)
	else:
		failures += 1
		print("FAIL  " + what)

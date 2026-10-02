# Fixes from play notes (2026-10-01): what Pell's reprimands are about,
# units never ordering each other about (and not nagging), cameras repaired
# from the rail right under them, a unit that asks about its job waits for
# the answer, dead cameras aren't alarms, Tinker can free the freight gate,
# Plant colours for every wearing device, "order" known from the start.
extends SceneTree

var failures := 0


func _initialize() -> void:
	SupervisorArchive.use_file("user://test_supervisor_archive.json")
	_test_categories()
	_test_no_orders_between_units()
	_test_camera_spots()
	_test_waits_for_answer()
	_test_camera_not_alarm()
	_test_gate()
	_test_plant_colours()
	_test_order_known()
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


func _test_categories() -> void:
	_check(Oversight.category("discussed pod telemetry with the liaison") == "",
		"something said to Pell isn't a 'maintenance account' violation (no decommissioned-account reprimand)")
	_check(Oversight.category("pod 3 inspected") == "maint" and Oversight.category("login to the decommissioned maintenance account") == "maint",
		"real maintenance-account acts still are")


func _test_no_orders_between_units() -> void:
	var text := FileAccess.get_file_as_string("res://game/speech/barks.txt")
	_check(not text.contains("\npeer_info") and not text.contains("\npeer_reply"), "no job tips between units in barks.txt")
	# A long day with work about: nobody tells anybody what to do, and no one
	# brings up the same passive topic twice in half an hour.
	var sim := _facility(31)
	var board: WorkBoard = sim.get_system("work")
	board.post(sim, "Empty the waste compactor", "heavy", "compactor", 600.0, 1)
	board.post(sim, "Sweep filters", "general", "bay_2", 400.0, 1)
	var chatter: RobotChatter = sim.get_system("chatter")
	var said: Array[Dictionary] = []
	var mark := chatter.said
	for i in 8 * 60:
		for b in FacilitySetup.robots(sim):
			b.power = maxf(b.power, 0.6)
		sim.advance(60.0)
		said.append_array(chatter.said_since(mark))
		mark = chatter.said
	_check(not said.any(func(l): return str(l.trigger).begins_with("peer")), "no unit gives another a job (%d lines in 8 h)" % said.size())
	var last := {}
	var nag := ""
	for l in said:
		if RobotChatter.ALWAYS.has(str(l.trigger)) or str(l.trigger) in ["exchange", "story", "order_reply"]:
			continue
		var key := str(l.robot) + "|" + str(l.trigger)
		var gap: float = RobotChatter.TOPIC_GAPS.get(str(l.trigger), RobotChatter.TOPIC_GAP)
		if last.has(key) and float(l.t) - float(last[key]) < gap - 0.5:
			nag = key
		last[key] = float(l.t)
	_check(nag.is_empty(), "no unit repeats a passive topic within its gap " + nag)


func _test_camera_spots() -> void:
	var sim := _facility(7)
	var layout: FacilityLayout = sim.get_system("layout")
	var plant: FacilityPlant = sim.get_system("plant")
	var cams := FacilitySetup.cameras()
	var ok := true
	var report := []
	for i in cams.size():
		var spot := "cam_%d_spot" % (i + 1)
		var st := layout.station(spot)
		var d := layout.station_world_pos(spot).distance_to(cams[i].pos)
		report.append("%d: %.1f m" % [i + 1, d])
		if st.is_empty() or st.room != cams[i].room or plant.device("cam_%d" % (i + 1)).station != spot:
			ok = false
		# No station in the room on the rail is closer to the camera.
		for sid in layout.stations_of():
			var other := layout.station(sid)
			if other.room == cams[i].room and not layout.is_pad(other.segment) and layout.station_world_pos(sid).distance_to(cams[i].pos) < d - 0.01:
				ok = false
				report.append("%s closer than %s" % [sid, spot])
	_check(ok, "each camera is repaired from the rail point closest to it (%s)" % ", ".join(report))


func _test_waits_for_answer() -> void:
	var sim := _facility(11)
	var board: WorkBoard = sim.get_system("work")
	var reqs: UnitRequests = sim.get_system("requests")
	var tinker := sim.get_system("robot_tinker") as RobotAgent
	Story.campaign(sim).state = "on_duty"   # (off duty, requests are answered for you at once)
	var jid := board.post(sim, "Recalibrate Pod 3", "precise", "pods_a", 3000.0, 2)
	Dispatch.request(sim, jid, false, tinker)
	var t := 0.0
	while t < 3600.0 and float(board.get_job(jid).progress) <= 0.0:
		tinker.power = 1.0
		sim.advance(10.0)
		t += 10.0
	_check(float(board.get_job(jid).progress) > 0.0, "Tinker gets to work on the pod")
	tinker.power = tinker.traits.power_reserve + 0.05
	var rid := reqs.ask(sim, "tinker", "recharge", "Power's low. Finish it first, or go and charge?", ["Finish it", "Go and charge"], 1, {"job": jid})
	var before := float(board.get_job(jid).progress)
	for i in 30:
		sim.advance(10.0)
	_check(rid >= 0 and tinker.waiting_on_answer(sim) and absf(float(board.get_job(jid).progress) - before) < 0.001,
		"asked 'finish or charge?', Tinker holds the job until you answer (rid %d, waiting %s, %.1f -> %.1f, %s, power %.2f)" % [rid, tinker.waiting_on_answer(sim),
		before, float(board.get_job(jid).progress), tinker.activity, tinker.power])
	reqs.answer(sim, rid, 0)
	for i in 30:
		tinker.power = maxf(tinker.power, 0.3)
		sim.advance(10.0)
	_check(not tinker.waiting_on_answer(sim) and float(board.get_job(jid).progress) > before, "told to finish it, it carries on")


func _test_camera_not_alarm() -> void:
	var PlantApp = load("res://os/apps/plant_app.gd")
	var sim := _facility(5)
	var plant: FacilityPlant = sim.get_system("plant")
	var n := sim.journal.added
	plant._fault(sim, "cam_3")
	var alarms := sim.journal.added_since(n).filter(func(e): return e.cat == "alarm")
	_check(alarms.is_empty() and PlantApp.active_faults(plant) == 0, "a dead camera isn't an alarm (no ALARM line, no alarm light)")
	plant._fault(sim, "pipe_1" if plant.devices.has("pipe_1") else plant.device_ids().filter(func(i): return plant.device(i).kind == "pipe")[0])
	_check(PlantApp.active_faults(plant) == 1, "a leak still is")


func _test_gate() -> void:
	_check("tinker" in FacilityPlant.KINDS.gate.units, "Tinker can free the freight gate (Hauler may be shut in behind it)")
	var sim := _facility(13)
	var plant: FacilityPlant = sim.get_system("plant")
	var layout: FacilityLayout = sim.get_system("layout")
	var hauler := sim.get_system("robot_hauler") as RobotAgent
	var tinker := sim.get_system("robot_tinker") as RobotAgent
	# Hauler in the workshop, the gate jams: Tinker can still get to the controls.
	var bench := layout.station("bench")
	hauler.seg = bench.segment
	hauler.off = bench.offset
	plant._fault(sim, "gate")
	var cant := Dispatch.unfit(sim, tinker, (sim.get_system("work") as WorkBoard).get_job(int(plant.device("gate").job)))
	_check(cant.is_empty() or cant == "busy" or cant.contains("part"), "with Hauler shut in, Tinker is fit for the gate (%s)" % cant)


func _test_plant_colours() -> void:
	var PlantApp = load("res://os/apps/plant_app.gd")
	var rails := {"kind": "rails", "value": 0.0, "fault": false, "job": -1}
	var waste := {"kind": "waste", "value": 0.05, "fault": false, "job": -1}
	var clean := {"kind": "rails", "value": 1.0, "fault": false, "job": -1}
	_check(PlantApp._device_color(rails) == OSTheme.ALARM and PlantApp._device_color(waste) == OSTheme.ALARM
		and PlantApp._device_color(clean) == OSTheme.ACCENT, "Plant: rail grime at 100% and full waste show red; clean rails green")


func _test_order_known() -> void:
	var sim := _facility(3)
	_check(Story.knowledge(sim).has("cmd:order"), "a new supervisor knows 'order'")
	var k := Knowledge.new()
	k.sim_load({"flags": {"cmd:ls": 0.0}})
	_check(k.has("cmd:order"), "and an older save learns it on load")


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS  " + what)
	else:
		failures += 1
		print("FAIL  " + what)

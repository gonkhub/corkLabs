# Checks the facility's machinery: pods drift and get recalibration jobs that
# escalate, faults (leaks, fuses, debris) post jobs and chain into other
# problems, repairs restore devices, the salvage hand-off between robots,
# shift reports, and save/load.
extends SceneTree

var failures := 0


func _initialize() -> void:
	SupervisorArchive.use_file("user://test_supervisor_archive.json")   # never the real personnel file
	_test_drift_posts_and_escalates()
	_test_leak_heats_the_facility()
	_test_relay_slows_charging()
	_test_repair_and_salvage_chain()
	_test_shift_report()
	_test_save_load()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


# A standard facility with no robots (so nothing gets fixed unless we say so).
func _facility(with_robots := false, seed_value := 3) -> FacilitySim:
	var sim := FacilitySim.new()
	var systems := FacilitySetup.systems().filter(func(s): return with_robots or not (s is RobotAgent))
	for s in systems:
		sim.add_system(s)
	sim.new_game(seed_value)
	for s in systems:
		if s.has_method("sim_start"):
			s.sim_start(sim)
	return sim


func _plant(sim: FacilitySim) -> FacilityPlant:
	return sim.get_system("plant")


func _board(sim: FacilitySim) -> WorkBoard:
	return sim.get_system("work")


func _test_drift_posts_and_escalates() -> void:
	var sim := _facility()
	var plant := _plant(sim)
	var pods := plant.device_ids().filter(func(i): return plant.device(i).kind == "pod")
	var worn := pods.filter(func(i): return plant.device(i).value <= 0.7)
	_check(worn.size() >= 1, "a new facility starts with a pod that needs care")
	var job := _board(sim).get_job(int(plant.device(worn[0]).job))
	_check(not job.is_empty() and job.title.begins_with("Recalibrate Pod") and job.skill == "precise",
		"and its recalibration job is on the board (%s)" % job.get("title", "none"))
	var p0 := int(job.priority)
	sim.advance(4 * 3600.0)
	_check(int(job.priority) > p0, "left alone, the job escalates as the pod drifts (%s -> %s)" % [
		WorkBoard.PRIORITY_NAMES[p0], WorkBoard.PRIORITY_NAMES[int(job.priority)]])
	var jobs_for_pod := _board(sim).jobs_from(worn[0])
	_check(jobs_for_pod.size() == 1, "a device never has two jobs open at once (%d)" % jobs_for_pod.size())
	_check(plant.throughput < 0.85, "throughput falls as pods drift (%d%%)" % roundi(plant.throughput * 100))


func _test_leak_heats_the_facility() -> void:
	var sim := _facility()
	var plant := _plant(sim)
	var h0 := plant.heat()
	var fired := []
	sim.event_fired.connect(func(n: String, _d: Dictionary): fired.append(n))
	sim.schedule_in(1.0, "plant_fault", {"device": "pipe_2"})
	sim.advance(2.0)
	_check(plant.device("pipe_2").fault and fired.has("alarm"), "a leak is a fault and sounds the alarm")
	var job := _board(sim).get_job(int(plant.device("pipe_2").job))
	_check(job.get("skill", "") == "heavy" and int(job.get("priority", 0)) == 2, "and posts a heavy, high-priority clamp job")
	sim.advance(5400.0)
	_check(plant.coolant < 0.6 and plant.heat() > h0 + 1.0, "an unclamped leak drains coolant and heats the facility (coolant %d%%, heat %.1fx)" % [
		roundi(plant.coolant * 100), plant.heat()])
	# Pods drift faster when hot.
	var cold := _facility()
	var hot_sum := 0.0
	var cold_sum := 0.0
	for id in ["pod_1", "pod_2", "pod_3", "pod_4"]:
		hot_sum += plant.device(id).value
	sim.advance(3600.0)
	for id in ["pod_1", "pod_2", "pod_3", "pod_4"]:
		hot_sum -= plant.device(id).value
		cold_sum += _plant(cold).device(id).value
	cold.advance(3600.0)
	for id in ["pod_1", "pod_2", "pod_3", "pod_4"]:
		cold_sum -= _plant(cold).device(id).value
	_check(hot_sum > cold_sum * 1.5, "pods drift faster in a hot facility (%.2f vs %.2f sync lost)" % [hot_sum, cold_sum])


func _test_relay_slows_charging() -> void:
	var sim := _facility(true)
	var plant := _plant(sim)
	var hauler: RobotAgent = sim.get_system("robot_hauler")
	hauler.power = 0.3
	hauler.give_order(sim, "recharge")
	sim.advance(10.0)
	var p0 := hauler.power
	sim.advance(100.0)
	var normal := hauler.power - p0
	sim.schedule_in(0.0, "plant_fault", {"device": "relay"})
	sim.advance(1.0)
	_check(plant.charge_factor() < 1.0, "a blown fuse cuts dock power")
	p0 = hauler.power
	sim.advance(100.0)
	var slow := hauler.power - p0
	_check(slow < normal * 0.6, "and robots charge slower (%.4f vs %.4f per 100 s)" % [slow, normal])


func _test_repair_and_salvage_chain() -> void:
	var sim := _facility()
	var plant := _plant(sim)
	var board := _board(sim)
	# Fake robots finishing jobs: claim + add all the work.
	var finish := func(id: int, by: String) -> void:
		board.claim(id, by)
		board.add_progress(sim, id, by, 1e6)
		sim.step()
	sim.schedule_in(0.0, "plant_fault", {"device": "pipe_1"})
	sim.advance(1.0)
	finish.call(int(plant.device("pipe_1").job), "robot_hauler")
	_check(not plant.device("pipe_1").fault and int(plant.device("pipe_1").job) == -1, "a finished clamp job fixes the pipe")
	# Clear debris until a part turns up (50% each time).
	var repair := {}
	for i in 12:
		sim.schedule_in(0.0, "plant_fault", {"device": "bay_3"})
		sim.advance(1.0)
		finish.call(int(plant.device("bay_3").job), "robot_hauler")
		var found := board.open_jobs().filter(func(j): return str(j.source).begins_with("part:repair"))
		if not found.is_empty():
			repair = found[0]
			break
	_check(not repair.is_empty() and repair.station == "bench" and repair.skill == "precise",
		"cleared debris sometimes turns up a part for the workbench (%s)" % repair.get("title", "none"))
	if repair.is_empty():
		return
	finish.call(int(repair.id), "robot_tinker")
	var refit := board.open_jobs().filter(func(j): return str(j.source).begins_with("part:refit"))
	_check(refit.size() == 1 and refit[0].skill == "heavy" and refit[0].station == "bay_3",
		"once repaired, it goes back to its bay to be refitted (heavy work)")
	finish.call(int(refit[0].id), "robot_hauler")
	var said := sim.journal.entries.any(func(e): return str(e.text).contains("refitted") and str(e.text).contains("repaired by Tinker"))
	_check(said, "the hand-off is journaled with both robots")


func _test_shift_report() -> void:
	var sim := _facility(true)
	sim.advance(9 * 3600.0)   # 05:55 -> 14:55: the Day shift ended at 14:00
	var reports := sim.journal.entries.filter(func(e): return e.cat == "report")
	_check(reports.size() == 1 and str(reports[0].text).begins_with("Shift report: throughput"),
		"the end of a shift writes a report (%s)" % (str(reports[0].text) if reports.size() > 0 else "none"))


func _test_save_load() -> void:
	var a := _facility(true, 11)
	a.advance(2 * 3600.0)
	var saved := JSON.stringify(a.save_data())
	a.advance(3 * 3600.0)
	var b := FacilitySim.new()
	for s in FacilitySetup.systems():
		b.add_system(s)
	b.load_data(JSON.parse_string(saved))
	b.advance(3 * 3600.0)
	var pa := _plant(a)
	var pb := _plant(b)
	var same := pa.device_ids().all(func(i): return is_equal_approx(pa.device(i).value, pb.device(i).value) and pa.device(i).fault == pb.device(i).fault)
	_check(same and is_equal_approx(pa.coolant, pb.coolant), "the plant saves and loads, and plays out identically")
	_check(a.journal.tail(30).map(func(e): return e.text) == b.journal.tail(30).map(func(e): return e.text),
		"with identical journals")


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

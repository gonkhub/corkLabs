# Checks the facility simulation: tick timing, event order, repeatability
# across save/load, offline catch-up, shifts, and the Facility session layer.
extends SceneTree

var failures := 0


# A test system: wanders randomly and books random events, so any
# non-repeatability shows up as a different position or journal.
class Wanderer:
	extends RefCounted
	var sim_id := "wanderer"
	var pos := 0.0
	var pings := 0

	func sim_start(sim: FacilitySim) -> void:
		sim.schedule_in(1.0, "ping", {"n": 0})

	func sim_tick(sim: FacilitySim, dt: float) -> void:
		pos += sim.rng.randf_range(-1.0, 1.0) * dt

	func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
		if event_name == "ping":
			pings += 1
			sim.note("test", "ping %d at %.3f" % [int(data.n), pos])
			sim.schedule_in(sim.rng.randf_range(0.5, 3.0), "ping", {"n": int(data.n) + 1})

	func sim_save() -> Dictionary:
		return {"pos": pos, "pings": pings}

	func sim_load(d: Dictionary) -> void:
		pos = float(d.pos)
		pings = int(d.pings)


func _initialize() -> void:
	_test_scheduler()
	_test_carry()
	_test_repeatable_save_load()
	_test_shifts()
	await _test_session()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _test_scheduler() -> void:
	var sim := FacilitySim.new()
	sim.new_game(1)
	var fired := []
	sim.event_fired.connect(func(n: String, _d: Dictionary): fired.append(n))
	sim.schedule(0.5, "b")
	sim.schedule(0.2, "a")
	sim.schedule(0.5, "c")          # same time as b: fires after b (booked later)
	var gone := sim.schedule(0.3, "x")
	sim.scheduler.cancel(gone)
	sim.advance(1.0)
	_check(fired == ["a", "b", "c"], "events fire in time order, ties in booking order (%s)" % str(fired))
	sim.schedule(0.0, "late")       # in the past
	sim.step()
	_check(fired.back() == "late", "an event booked in the past fires on the next tick")


func _test_carry() -> void:
	var sim := FacilitySim.new()
	sim.new_game(1)
	var start := sim.tick
	_check(FacilitySim.format_time(sim.time()) == "Day 1  05:55:00", "a new facility starts at Day 1 05:55")
	var n := sim.advance(0.05) + sim.advance(0.05) + sim.advance(0.05)
	_check(n == 1 and sim.tick == start + 1, "time smaller than a tick is carried over (%d ticks)" % n)
	sim.advance(3600.0)
	_check(sim.tick - start == 36001, "an hour is 36000 ticks (%d)" % (sim.tick - start - 1))


func _run(ticks: int, sim: FacilitySim) -> void:
	for i in ticks:
		sim.step()


func _test_repeatable_save_load() -> void:
	var a := FacilitySim.new()
	var wa := Wanderer.new()
	a.add_system(wa)
	a.new_game(1234)
	wa.sim_start(a)
	_run(3000, a)

	var b := FacilitySim.new()
	var wb := Wanderer.new()
	b.add_system(wb)
	b.new_game(1234)
	wb.sim_start(b)
	_run(1234, b)
	# Save through JSON text, like the real save file.
	var text := JSON.stringify(b.save_data())
	var c := FacilitySim.new()
	var wc := Wanderer.new()
	c.add_system(wc)
	c.load_data(JSON.parse_string(text))
	_run(3000 - 1234, c)

	_check(wa.pings > 20, "the test system actually did things (%d pings)" % wa.pings)
	_check(is_equal_approx(wa.pos, wc.pos) and wa.pings == wc.pings,
		"save/load mid-run gives the same result (%.6f vs %.6f)" % [wa.pos, wc.pos])
	var ja := a.journal.tail(5).map(func(e): return e.text)
	var jc := c.journal.tail(5).map(func(e): return e.text)
	_check(ja == jc, "journals match after save/load")
	_check(a.rng.randi() == c.rng.randi(), "random numbers continue identically after load")


func _test_shifts() -> void:
	var sim := FacilitySim.new()
	var shifts := ShiftSchedule.new()
	sim.add_system(shifts)
	sim.new_game(1)
	shifts.sim_start(sim)
	sim.advance(30 * 3600.0)   # 05:55 + 30 h = Day 2 11:55
	_check(shifts.shift_number == 4, "30 hours in: 4 shifts have started (%d)" % shifts.shift_number)
	_check(shifts.current_name() == "Day", "Day 2 11:55 is in a Day shift (%s)" % shifts.current_name())
	var texts := sim.journal.entries.map(func(e): return e.text)
	_check(texts.has("Day shift #1 begins") and texts.has("Night shift #3 ends"), "shifts are journaled")


# The Facility autoload layer: session start/save/log off/log back on.
func _test_session() -> void:
	var path := "user://test_facility_save.json"
	var facility: Node = load("res://game/sim/facility.gd").new()
	get_root().add_child(facility)
	facility.wipe_save(path)
	facility.start_session([ShiftSchedule.new()], path, 7)
	_check(facility.running and facility.clock_text() == "05:55", "first session starts a new facility at 05:55 (%s)" % facility.clock_text())
	facility.spend(4 * 3600.0, "test: a long task")   # to 09:55, Day shift running
	facility.end_session()
	var t_saved: float = facility.sim.time()

	# Reopen (after any amount of real time): the clock resumes at the saved moment.
	await create_timer(0.3).timeout
	facility.start_session([ShiftSchedule.new()], path)
	var shifts: ShiftSchedule = facility.sim.get_system("shifts")
	_check(facility.sim.time() == t_saved and facility.clock_text() == "09:55",
		"reopening resumes at exactly the saved facility time (%s)" % facility.clock_text())
	_check(shifts.shift_number == 1 and shifts.current_name() == "Day", "shift state survives closing the game")
	_check(facility.sim.scheduler.size() >= 2, "booked events survive closing the game (%d)" % facility.sim.scheduler.size())

	# Real time does nothing; only player actions move the clock.
	var before: float = facility.sim.time()
	await create_timer(0.5).timeout
	_check(facility.sim.time() == before, "facility time doesn't move while the player does nothing")
	var spent := []
	facility.time_spent.connect(func(a: float, b: float, cause: String): spent.append([b - a, cause]))
	facility.act("dialogue_line", "Tinker: status report")
	facility.act("choice", "Order Tinker to bay 2")
	_check(is_equal_approx(facility.sim.time() - before, 180.0) and facility.clock_text() == "09:58",
		"a dialogue line (1 min) + a choice (2 min) = 3 minutes (%s)" % facility.clock_text())
	_check(spent.size() == 2 and spent[1][1] == "Order Tinker to bay 2", "time_spent signal reports each action")
	var noted: bool = facility.sim.journal.tail(3).any(func(e): return str(e.text).contains("Tinker: status report"))
	_check(noted, "each action is written to the journal")
	facility.end_session()
	facility.wipe_save(path)
	facility.free()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

# Checks robot behaviour: utility decisions, work, power and software stability
# (independence, errant behaviour, critical errors, sabotage, reboots),
# orders (and pushing back), stalls, and repeatability across save/load.
# (Rooms, routes and blocking: test_rooms_and_routes.gd.)
extends SceneTree

var failures := 0


func _initialize() -> void:
	_test_board()
	_test_picks_and_finishes_work()
	_test_skill_preference()
	_test_orders()
	_test_power()
	_test_stability()
	_test_critical()
	_test_sabotage()
	_test_order_stress()
	_test_stall()
	_test_repeatable()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


# A small facility: one room, one straight 8 m rail with a dock at 0 and work at 2 and 6.
func _small(robot_traits: RobotTraits = null, start := 0.0) -> Array:
	var sim := FacilitySim.new()
	var l := FacilityLayout.new()
	l.add_room("room", "Room", Rect2(-1, -1, 10, 2), 5.0, 4.0)
	l.add_node("n0", "room", 0, 0)
	l.add_node("n1", "room", 8, 0)
	l.add_segment("r", "n0", "n1")
	l.add_station("dock", "r", 0.0, "dock", "Dock")
	l.add_station("near", "r", 2.0, "work", "Near")
	l.add_station("far", "r", 6.0, "work", "Far")
	var board := WorkBoard.new()
	var t := robot_traits if robot_traits else _traits()
	var bot := RobotAgent.new("bot", t, "r", start)
	sim.add_system(l)
	sim.add_system(board)
	sim.add_system(bot)
	sim.new_game(5)
	return [sim, board, bot]


func _traits() -> RobotTraits:
	var t := RobotTraits.new()
	t.display_name = "Bot"
	t.rail_speed = 1.0
	t.skill_heavy = 1.0
	t.skill_precise = 0.1
	t.skill_general = 0.6
	t.refuse_below_skill = 0.2
	return t


func _test_board() -> void:
	var parts := _small()
	var sim: FacilitySim = parts[0]
	var board: WorkBoard = parts[1]
	var id := board.post(sim, "Lift", "heavy", "near", 10.0)
	_check(board.claim(id, "a") and not board.claim(id, "b"), "only one robot can claim a job")
	board.release(id, "a")
	_check(board.claim(id, "b"), "a released job can be claimed again")
	var fired := []
	sim.event_fired.connect(func(n: String, d: Dictionary): fired.append([n, d]))
	board.add_progress(sim, id, "b", 4.0)
	_check(board.add_progress(sim, id, "b", 6.0), "progress adds up to done")
	sim.step()
	_check(fired.size() == 1 and fired[0][0] == "job_done" and int(fired[0][1].job) == id, "job_done event fires")
	_check(board.open_jobs().is_empty(), "done jobs leave the open list")


func _test_picks_and_finishes_work() -> void:
	var parts := _small()
	var sim: FacilitySim = parts[0]
	var board: WorkBoard = parts[1]
	var bot: RobotAgent = parts[2]
	var id := board.post(sim, "Lift crate", "heavy", "far", 30.0)
	sim.advance(3.0)
	_check(bot.activity.kind == "work" and int(bot.activity.job) == id, "robot picks up the open job (%s)" % bot.activity_key())
	_check(board.get_job(id).claimed_by == "robot_bot", "and claims it on the board")
	bot.stability = 0.5
	var p0 := bot.stability
	sim.advance(60.0)   # 6 m at 1 m/s + 30 units of work
	_check(board.get_job(id).status == "done", "it travels there and finishes the job")
	_check(bot.jobs_done == 1 and bot.stability > p0, "finishing work restores stability (%.2f -> %.2f)" % [p0, bot.stability])
	var lines := sim.journal.entries.map(func(e): return str(e.text))
	_check(lines.any(func(t: String): return t.begins_with("Bot: work #%d Lift crate" % id) and t.contains("next best")),
		"the decision is journaled with its reason and the runner-up")


func _test_skill_preference() -> void:
	var parts := _small()
	var sim: FacilitySim = parts[0]
	var board: WorkBoard = parts[1]
	var bot: RobotAgent = parts[2]
	var fine := board.post(sim, "Fix fuse", "precise", "near", 30.0, 2)
	var heavy := board.post(sim, "Lift crate", "heavy", "far", 30.0, 1)
	sim.advance(1.0)
	_check(bot.activity_key() == "work:%d" % heavy,
		"a heavy robot prefers heavy work, even further away and lower priority (%s)" % bot.activity_key())
	_check(fine > 0, "sanity")


func _test_orders() -> void:
	var parts := _small()
	var sim: FacilitySim = parts[0]
	var board: WorkBoard = parts[1]
	var bot: RobotAgent = parts[2]
	var a := board.post(sim, "Sweep", "general", "near", 500.0, 1)
	var b := board.post(sim, "Inspect", "general", "far", 50.0, 0)
	sim.advance(1.0)
	_check(bot.activity_key() == "work:%d" % a, "left alone it takes the higher-priority job")
	var r := bot.give_order(sim, "job", b)
	_check(r.ok and bot.activity_key() == "work:%d" % b, "an order nudges it onto another job (%s)" % r.reply)
	_check(board.get_job(a).status == "open", "the job it walked away from goes back on the board")
	var no := bot.give_order(sim, "job", board.post(sim, "Solder", "precise", "near", 10.0, 3))
	_check(not no.ok and no.reply.contains("not built"), "it refuses work it's hopeless at (%s)" % no.reply)
	_check(bot.activity_key() == "work:%d" % b, "and carries on with the standing order")
	sim.advance(120.0)
	_check(board.get_job(b).status == "done" and bot.order.is_empty(), "the order clears when the job is done")
	var lines := sim.journal.entries.map(func(e): return str(e.text))
	_check(lines.any(func(t: String): return t.contains(" answers: ")), "replies to orders are journaled")


func _test_power() -> void:
	var parts := _small(null, 6.0)
	var sim: FacilitySim = parts[0]
	var board: WorkBoard = parts[1]
	var bot: RobotAgent = parts[2]
	bot.power = 0.1   # below the 0.15 reserve
	var id := board.post(sim, "Lift crate", "heavy", "far", 30.0, 3)
	var r := bot.give_order(sim, "job", id)
	_check(not r.ok and r.reply.contains("Recharging first"), "below reserve it pushes back and recharges first (%s)" % r.reply)
	_check(bot.activity.kind == "recharge", "and heads for the dock")
	sim.advance(6.0 + 800.0)
	_check(bot.power >= bot.traits.charge_until - 0.01 or bot.activity.kind == "work",
		"it charges up (%.2f, %s)" % [bot.power, bot.activity_key()])
	sim.advance(200.0)
	_check(board.get_job(id).status == "done", "then does the ordered job")


func _test_stability() -> void:
	var t := _traits()
	t.stability_decay = 0.002
	t.independence = 1.0
	var parts := _small(t)
	var sim: FacilitySim = parts[0]
	var bot: RobotAgent = parts[2]
	bot.stability = 0.9
	sim.advance(100.0)
	_check(bot.activity.kind == "idle" and bot.stability < 0.9, "with nothing to do it stands by and its software drifts (%.2f)" % bot.stability)
	sim.advance(200.0)
	_check(bot.stability_state != "stable", "idleness makes it %s" % bot.stability_state)
	var lines := sim.journal.entries.map(func(e): return str(e.text))
	_check(lines.any(func(l: String): return l.contains("software now")), "stability changes are journaled")
	# Independence: orders count for less as stability falls.
	bot.stability = 0.9
	var obedient := bot.independence()
	bot.stability = 0.1
	_check(obedient == 0.0 and bot.independence() > 0.9, "a stable robot is obedient; an unstable one independent (%.2f)" % bot.independence())
	var r := bot.give_order(sim, "standby")
	_check(not r.ok, "an unstable robot ignores orders (%s)" % r.reply)
	# Errant options appear when unstable.
	var keys := bot.evaluate(sim).map(func(o): return o.key)
	_check(keys.has("fixate"), "an unstable robot considers errant fixations")


func _test_critical() -> void:
	# Critical errors: crash (offline, then reboot) or glitch.
	var t := _traits()
	t.error_resistance = 0.0
	var parts := _small(t)
	var sim: FacilitySim = parts[0]
	var bot: RobotAgent = parts[2]
	bot.traits.stability_decay = 0.0
	bot.stability = 0.0
	var kinds := {}
	for i in 600:
		sim.advance(2.0)
		kinds[bot.activity.kind] = true
		if kinds.has("crashed") and kinds.has("glitch"):
			break
	_check(kinds.has("crashed") or kinds.has("glitch"), "at critical stability it has critical errors (%s)" % str(kinds.keys()))
	# Crash -> offline -> reboot restores stability.
	bot.stability = 0.05
	bot.activity = {"kind": "crashed", "until": sim.time() + 60.0}
	var r := bot.give_order(sim, "recharge")
	_check(not r.ok and bot.offline(), "a crashed robot can't take orders")
	sim.advance(70.0)
	_check(not bot.offline() and bot.stability > 0.3, "after the crash it reboots with stability restored (%.2f)" % bot.stability)
	# Remote reboot.
	bot.reboot(sim)
	_check(bot.activity.kind == "rebooting", "a remote reboot takes it offline")


func _test_sabotage() -> void:
	# A critically unstable robot breaks something it can then fix.
	var sim := FacilitySim.new()
	var systems := FacilitySetup.systems()
	for s in systems:
		sim.add_system(s)
	sim.new_game(12)
	for s in systems:
		if s.has_method("sim_start"):
			s.sim_start(sim)
	var board: WorkBoard = sim.get_system("work")
	for j in board.open_jobs():
		board.cancel(sim, j.id, "test")
	var plant: FacilityPlant = sim.get_system("plant")
	for id in plant.device_ids():   # a spotless facility: no work to do but what it makes
		plant.device(id).value = 1.0
	for e in sim.scheduler.peek(1000):
		if e.name == "plant_fault":
			sim.scheduler.cancel(e.id)
	sim.remove_system("robot_hauler")
	var tinker: RobotAgent = sim.get_system("robot_tinker")
	tinker.traits.sabotage_tendency = 1.0
	tinker.traits.error_resistance = 1.0
	tinker.traits.stability_decay = 0.0
	tinker.stability = 0.02
	var options := tinker.evaluate(sim).map(func(o): return o.key)
	_check(options.any(func(k: String): return k.begins_with("sabotage:")), "at critical stability, sabotage is an option (%s)" % str(options.slice(0, 4)))
	sim.advance(1800.0)
	var did := sim.journal.entries.filter(func(e): return e.cat == "sabotage" and str(e.text).contains("SABOTAGED"))
	_check(not did.is_empty(), "left alone, it sabotages a device (%s)" % (did[0].text if not did.is_empty() else "-"))


func _test_order_stress() -> void:
	var parts := _small()
	var sim: FacilitySim = parts[0]
	var board: WorkBoard = parts[1]
	var bot: RobotAgent = parts[2]
	board.post(sim, "Sweep", "general", "near", 500.0, 2)
	var b := board.post(sim, "Inspect", "general", "far", 50.0, 0)
	sim.advance(1.0)
	var s0 := bot.stability
	bot.give_order(sim, "job", b)
	_check(bot.stability < s0, "being overruled wears on its software (%.3f -> %.3f)" % [s0, bot.stability])


func _test_stall() -> void:
	var parts := _small(null, 6.0)
	var sim: FacilitySim = parts[0]
	var board: WorkBoard = parts[1]
	var bot: RobotAgent = parts[2]
	bot.power = 0.0005   # 6 m from the dock: not enough to get there
	board.post(sim, "Lift crate", "heavy", "far", 3000.0)
	sim.advance(30.0)
	_check(bot.activity.kind == "stalled", "at zero power it stalls (%s)" % bot.activity_key())
	_check(board.open_jobs()[0].status == "open", "and lets go of its job")
	sim.advance(400.0)
	_check(bot.activity.kind != "stalled", "emergency cells get it going again (%.2f)" % bot.power)


# The full standard facility, run for 3 hours in one go vs. with a JSON
# save/load in the middle: must end identical.
func _test_repeatable() -> void:
	var a := FacilitySim.new()
	var systems := FacilitySetup.systems()
	for s in systems:
		a.add_system(s)
	a.new_game(99)
	for s in systems:
		if s.has_method("sim_start"):
			s.sim_start(a)
	a.advance(3600.0)
	var saved := JSON.stringify(a.save_data())
	# An order in the middle, like a player would give.
	a.get_system("robot_hauler").give_order(a, "recharge")
	a.advance(2 * 3600.0)

	var c := FacilitySim.new()
	for s in FacilitySetup.systems():
		c.add_system(s)
	c.load_data(JSON.parse_string(saved))
	c.get_system("robot_hauler").give_order(c, "recharge")
	c.advance(2 * 3600.0)

	var ha: RobotAgent = a.get_system("robot_hauler")
	var hc: RobotAgent = c.get_system("robot_hauler")
	var ta: RobotAgent = a.get_system("robot_tinker")
	var tc: RobotAgent = c.get_system("robot_tinker")
	_check(ha.seg == hc.seg and is_equal_approx(ha.off, hc.off) and is_equal_approx(ta.power, tc.power) and ta.activity_key() == tc.activity_key(),
		"3 facility hours with a save/load in the middle give identical robots")
	var ja := a.journal.tail(40).map(func(e): return e.text)
	var jc := c.journal.tail(40).map(func(e): return e.text)
	_check(ja == jc, "and identical journals")
	var did := a.journal.entries.filter(func(e): return str(e.cat) == "work" and str(e.text).contains("done"))
	_check(did.size() >= 2, "robots got real work done in 3 hours (%d jobs)" % did.size())


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

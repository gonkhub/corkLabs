# Checks robot behaviour: utility decisions, work, power and purpose needs,
# orders (and pushing back), stalls, repeatability across save/load, and that
# the sim's rails match the 3D world.
extends SceneTree

var failures := 0


func _initialize() -> void:
	_test_layout()
	_test_board()
	_test_picks_and_finishes_work()
	_test_skill_preference()
	_test_orders()
	_test_power()
	_test_purpose()
	_test_stall()
	_test_repeatable()
	_test_rails_match_world()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


# A small facility: one straight rail with a dock at 0 and work at 2 and 6.
func _small(robot_traits: RobotTraits = null, start := 0.0) -> Array:
	var sim := FacilitySim.new()
	var l := FacilityLayout.new()
	l.add_rail("r", 8.0)
	l.add_station("dock", "r", 0.0, "dock", "Dock")
	l.add_station("near", "r", 2.0, "work", "Near")
	l.add_station("far", "r", 6.0, "work", "Far")
	var board := WorkBoard.new()
	var t := robot_traits if robot_traits else _traits()
	var bot := RobotAgent.new("bot", "r", t, start)
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


func _test_layout() -> void:
	var l := FacilityLayout.new()
	l.add_rail("loop", 30.0, true)
	l.add_rail("line", 8.0)
	_check(is_equal_approx(l.distance("loop", 1.0, 29.0), 2.0), "loop distance goes the short way round")
	_check(is_equal_approx(l.signed_offset("loop", 29.0, 1.0), 2.0), "loop offset crosses the seam forwards")
	_check(is_equal_approx(l.distance("line", 1.0, 7.0), 6.0), "line distance is plain")
	_check(is_equal_approx(l.wrap("loop", 31.0), 1.0) and is_equal_approx(l.wrap("line", 9.0), 8.0), "positions wrap on loops, clamp on lines")


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
	var p0 := bot.purpose
	sim.advance(60.0)   # 6 m at 1 m/s + 30 units of work
	_check(board.get_job(id).status == "done", "it travels there and finishes the job")
	_check(bot.jobs_done == 1 and bot.purpose > p0, "finishing work restores purpose (%.2f -> %.2f)" % [p0, bot.purpose])
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
	_check(lines.any(func(t: String): return t.contains("to the supervisor")), "replies to orders are journaled")


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


func _test_purpose() -> void:
	var t := _traits()
	t.restlessness = 0.002
	var parts := _small(t)
	var sim: FacilitySim = parts[0]
	var bot: RobotAgent = parts[2]
	bot.purpose = 0.9
	sim.advance(100.0)
	_check(bot.activity.kind == "idle" and bot.purpose < 0.9, "with nothing to do it stands by and purpose drains (%.2f)" % bot.purpose)
	sim.advance(400.0)
	_check(bot.mood != "content", "idleness makes it %s" % bot.mood)
	_check(bot.activity.kind == "wander", "a restless robot starts wandering the rail (%s)" % bot.activity_key())
	var lines := sim.journal.entries.map(func(e): return str(e.text))
	_check(lines.any(func(s: String): return s.contains("feels restless")), "mood changes are journaled")
	# Stand-by orders: a content robot obeys, an uneasy one struggles.
	bot.purpose = 0.05
	var r := bot.give_order(sim, "standby")
	_check(not r.ok, "an uneasy robot can't stand still, even when ordered (%s)" % r.reply)


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
	_check(is_equal_approx(ha.pos, hc.pos) and is_equal_approx(ta.power, tc.power) and ta.activity_key() == tc.activity_key(),
		"3 facility hours with a save/load in the middle give identical robots")
	var ja := a.journal.tail(40).map(func(e): return e.text)
	var jc := c.journal.tail(40).map(func(e): return e.text)
	_check(ja == jc, "and identical journals")
	var did := a.journal.entries.filter(func(e): return str(e.cat) == "work" and str(e.text).contains("done"))
	_check(did.size() >= 2, "robots got real work done in 3 hours (%d jobs)" % did.size())


func _test_rails_match_world() -> void:
	var l := FacilitySetup.layout()
	var scene := (load("res://game/facility_world.tscn") as PackedScene).instantiate()
	var tinker: Path3D = scene.get_node("TinkerRail")
	var hauler: Path3D = scene.get_node("HaulerRail")
	_check(absf(tinker.curve.get_baked_length() - l.rail_length(FacilitySetup.TINKER_RAIL)) < 0.05,
		"Tinker's sim rail matches the 3D rail (%.2f)" % tinker.curve.get_baked_length())
	_check(absf(hauler.curve.get_baked_length() - l.rail_length(FacilitySetup.HAULER_RAIL)) < 0.05,
		"Hauler's sim rail matches the 3D rail (%.2f)" % hauler.curve.get_baked_length())
	scene.free()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

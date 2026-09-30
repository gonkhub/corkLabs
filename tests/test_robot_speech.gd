# Checks the robot speech framework: the bark library (barks.txt, conditions,
# placeholders), RobotChatter (who says what when: reports, cooldowns, peer
# exchanges with a reply, alarms, repeatable across save/load), the speech
# director (typing out, one line per robot, only heard on camera) and the
# generated voice blips.
extends SceneTree

var failures := 0


func _initialize() -> void:
	_test_library()
	_test_chatter()
	_test_peer_exchange()
	_test_repeatable()
	_test_voice()
	await _test_director()
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


func _test_library() -> void:
	var lib := BarkLibrary.shared()
	_check(lib.lines.size() > 40, "barks.txt loads (%d lines)" % lib.lines.size())
	var test := BarkLibrary.new()
	test.load_text("""# comment
start_job | any | | Going to {station}.
start_job | tinker | low_power | Tired. {station}.
idle | hauler | | Hm.""")
	_check(test.lines.size() == 3, "comments are skipped")
	var fresh := test.candidates("start_job", "tinker", {"power": 0.9})
	var tired := test.candidates("start_job", "tinker", {"power": 0.1})
	_check(fresh.size() == 1 and tired.size() == 2, "condition lines only count when the condition holds")
	_check(tired.any(func(c): return c.text.begins_with("Tired") and c.weight > 1.0), "and are picked more often when they do")
	_check(test.candidates("idle", "tinker", {}).is_empty(), "robot-specific lines stay with their robot")
	_check(BarkLibrary.fill("Going to {station}, {power}.", {"station": "Bay 2", "power": 0.25}) == "Going to Bay 2, 25%.",
		"placeholders are filled in")


func _test_chatter() -> void:
	var sim := _facility()
	var chatter: RobotChatter = sim.get_system("chatter")
	var tinker: RobotAgent = sim.get_system("robot_tinker")
	var n0 := chatter.said
	tinker.give_order(sim, "recharge")
	_check(chatter.said > n0 and chatter.recent.back().trigger == "order_reply", "a robot always answers an order out loud")
	# Cooldown: a chatty trigger right after speaking is skipped.
	var n1 := chatter.said
	for i in 10:
		chatter.trigger(sim, tinker, "wander")
	_check(chatter.said == n1, "the cooldown stops a robot talking over itself")
	# Forced triggers ignore it.
	chatter.trigger(sim, tinker, "stalled")
	_check(chatter.said == n1 + 1, "urgent things (stalling) are always said")
	# Condition-dependent lines.
	tinker.power = 0.05
	var said_low := []
	for i in 30:
		chatter._last_spoke.clear()
		if chatter.trigger(sim, tinker, "recharge"):
			said_low.append(chatter.recent.back().text)
	_check(said_low.any(func(t): return t in ["Dock. Now.", "Charge, charge, charge..."]), "a robot low on power sounds it (%s)" % str(said_low.slice(0, 3)))
	# Over a few hours, they talk, but not constantly.
	var before := chatter.said
	sim.advance(3 * 3600.0)
	var per_hour := (chatter.said - before) / 3.0
	_check(per_hour > 3 and per_hour < 60, "robots talk now and then (%.0f lines per facility hour)" % per_hour)
	_check(sim.journal.entries.any(func(e): return e.cat == "speech"), "what they say is in the journal")


func _test_peer_exchange() -> void:
	var sim := _facility(8)
	var chatter: RobotChatter = sim.get_system("chatter")
	var tinker: RobotAgent = sim.get_system("robot_tinker")
	var hauler: RobotAgent = sim.get_system("robot_hauler")
	# Both at the docks, in the same room: a conversation should start.
	tinker.activity = {"kind": "idle"}
	hauler.activity = {"kind": "idle"}
	chatter._last_spoke.clear()
	chatter._pair_last.clear()
	chatter.rng.seed = 1
	var started := false
	for i in 20:
		chatter._maybe_talk(sim, hauler, tinker)
		if chatter.recent.back().trigger in ["peer_greet", "peer_info"]:
			started = true
			break
		chatter._last_spoke.clear()
	_check(started, "two robots close together in the same room strike up a conversation")
	var opener: Dictionary = chatter.recent.back()
	sim.advance(RobotChatter.REPLY_DELAY + 1.0)
	var reply := chatter.recent.filter(func(l): return l.trigger in ["peer_reply", "peer_info_reply"])
	_check(not reply.is_empty() and reply.back().robot != opener.robot, "and the other one answers (%s: %s / %s: %s)" % [
		opener.robot, opener.text, reply.back().robot if not reply.is_empty() else "-", reply.back().text if not reply.is_empty() else "-"])


func _test_repeatable() -> void:
	var a := _facility(21)
	a.advance(1800.0)
	var saved := JSON.stringify(a.save_data())
	a.advance(3600.0)
	var b := FacilitySim.new()
	for s in FacilitySetup.systems():
		b.add_system(s)
	b.load_data(JSON.parse_string(saved))
	b.advance(3600.0)
	var ca: RobotChatter = a.get_system("chatter")
	var cb: RobotChatter = b.get_system("chatter")
	_check(ca.said == cb.said and ca.recent.map(func(l): return l.text) == cb.recent.map(func(l): return l.text),
		"with a save/load in the middle, they say exactly the same things (%d lines)" % ca.said)


func _test_voice() -> void:
	var blip := RobotVoice._make_blip(220.0, "square")
	_check(blip.data.size() > 1000 and blip.format == AudioStreamWAV.FORMAT_16_BITS, "voice blips are generated")
	var t := RobotTraits.load_for("hauler")
	var u := RobotTraits.load_for("tinker")
	_check(t.voice_pitch < u.voice_pitch and t.speech_color != u.speech_color, "Hauler's voice is lower than Tinker's, in its own colour")


func _test_director() -> void:
	var facility: Node = get_root().get_node("Facility")
	OSSettings.use_file("user://test_speech_os.json")
	facility.wipe_save("user://test_speech_save.json")
	facility.start_session(FacilitySetup.systems(), "user://test_speech_save.json", 4)
	var d = load("res://os/speech_director.gd").new()   # by path: it uses the Facility autoload
	get_root().add_child(d)
	await process_frame
	d.say("tinker", "Hello there, Hauler!")
	await process_frame
	var b: Array = d.bubbles()
	_check(b.size() == 1 and str(b[0].text).length() < "Hello there, Hauler!".length(), "speech types itself out (%s)" % (b[0].text if b.size() > 0 else "-"))
	for i in 30:
		await process_frame
	d.say("tinker", "Never mind.")
	_check(d.bubbles().size() == 1, "a newer line replaces the old one")
	_check(not d.heard("tinker"), "a robot isn't heard unless a camera sees it")
	d.mark_seen("tinker")
	_check(d.heard("tinker"), "it is once a feed sees it")
	# New lines from the sim appear on their own.
	var chatter: RobotChatter = facility.sim.get_system("chatter")
	chatter.trigger(facility.sim, facility.sim.get_system("robot_hauler"), "stalled")
	await process_frame
	_check(d.active.has("hauler"), "lines the robots say in the sim show up as speech")
	d.free()
	facility.end_session()
	facility.wipe_save("user://test_speech_save.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_speech_os.json"))


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

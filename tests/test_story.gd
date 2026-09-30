# Checks the story systems without the desktop: the file system (paths,
# hidden files, files that appear and disappear), knowledge, reading and
# decrypting (what it teaches, what it costs, what corporate logs),
# conversations, the campaign (brief, clock in, duties, scripted events,
# end of shift, the night, the purge, endings), oversight (audits, strikes,
# dismissal for performance, misconduct and catastrophe) and checkpoints.
extends SceneTree

const SAVE := "user://test_story_save.json"

var failures := 0


func _initialize() -> void:
	SupervisorArchive.use_file("user://test_supervisor_archive.json")   # never the real personnel file
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_supervisor_archive.json"))
	_test_fs()
	_test_reading()
	_test_dialogue()
	_test_campaign()
	_test_oversight()
	await _test_checkpoint()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _new_sim(seed_value := 4242) -> FacilitySim:
	var sim := FacilitySim.new()
	var systems := FacilitySetup.systems()
	for s in systems:
		sim.add_system(s)
	sim.new_game(seed_value)
	for s in systems:
		if s.has_method("sim_start"):
			s.sim_start(sim)
	return sim


func _test_fs() -> void:
	var fs := VirtualFS.shared()
	_check(VirtualFS.normalize("/home/supervisor", "../rmarrow/./x.txt") == "/home/rmarrow/x.txt", "paths: relative, . and ..")
	_check(VirtualFS.normalize("/corp", "~") == VirtualFS.HOME and VirtualFS.normalize("/", "~/welcome.txt") == "/home/supervisor/welcome.txt", "paths: ~ is home")
	_check(VirtualFS.normalize("/", "../../..") == "/", "paths: can't go above /")
	var k := Knowledge.new()
	var names := fs.children("/home", k, 1).map(func(e): return e.name)
	_check(names.has("supervisor") and names.has("dokafor") and names.has("rmarrow") and names.has("ehollis"), "former supervisors' homes are there (%s)" % ", ".join(names))
	var dok := fs.children("/home/dokafor", k, 1).map(func(e): return e.name)
	var dok_all := fs.children("/home/dokafor", k, 1, true).map(func(e): return e.name)
	_check(not dok.has(".pod3") and dok_all.has(".pod3"), "hidden files only show with ls -a")
	_check(not fs.exists("/sys/pods/manifest.txt", k, 1), "the pod manifest needs the maintenance account")
	k.flags["root"] = 0.0
	_check(fs.exists("/sys/pods/manifest.txt", k, 1), "and is there as maint")
	k.flags["purged:dokafor"] = 0.0
	_check(not fs.exists("/home/dokafor/todo.txt", k, 1) and not fs.children("/home", k, 1).any(func(e): return e.name == "dokafor"),
		"after the purge, Okafor's home is gone")
	var e := fs.get_entry("/home/ehollis/diary.enc")
	_check(not e.is_empty() and e.meta.get("password", "") == "lantern", "a file can have a player-facing name and a password")
	_check(Knowledge.secrets().size() >= 12, "the secrets catalogue loads (%d)" % Knowledge.secrets().size())


func _test_reading() -> void:
	var sim := _new_sim()
	var k := Story.knowledge(sim)
	var o := Story.oversight(sim)
	_check(k.has("cmd:ls") and not k.has("cmd:order") and not k.has("cmd:talk"), "a new supervisor knows only the basics")
	var r := Story.read_file(sim, "/home/supervisor/welcome.txt")
	_check(r.ok and r.first and float(r.minutes) == 3.0, "reading onboarding takes its time (%s min)" % r.get("minutes", "?"))
	_check(k.has("cmd:order") and k.has("cmd:duties") and k.has("read:/home/supervisor/welcome.txt"), "and teaches the commands it mentions")
	r = Story.read_file(sim, "/home/supervisor/welcome.txt")
	_check(r.ok and not r.first and float(r.minutes) == 0.0, "re-reading is free")
	_check(o.suspicion == 0.0, "reading your own files isn't a violation")
	r = Story.read_file(sim, "/home/dokafor/todo.txt")
	_check(r.ok and k.has("cmd:talk") and k.has("secret:former_staff"), "Okafor's todo teaches 'talk' (and is a secret)")
	_check(o.suspicion > 0.0 and o.trail.size() == 1, "reading a former supervisor's files is logged (suspicion %.0f)" % o.suspicion)
	r = Story.read_file(sim, "/home/ehollis/diary.enc")
	_check(not r.ok and r.get("encrypted", false) and k.has("cmd:decrypt"), "an encrypted file needs a password (and teaches decrypt)")
	_check(not Story.decrypt(sim, "/home/ehollis/diary.enc", "password").ok, "a wrong password fails")
	_check(Story.decrypt(sim, "/home/ehollis/diary.enc", "Lantern").ok, "the right one decrypts it")
	r = Story.read_file(sim, "/home/ehollis/diary.enc")
	_check(r.ok and k.has("secret:pods_truth") and k.has("cmd:podctl"), "the diary tells what the pods are")
	_check(not Story.read_file(sim, "/nope.txt").ok and not Story.read_file(sim, "/home").ok, "missing files and folders can't be read")
	_check(Story.pods().size() == 4 and str(Story.pods()[2].name).contains("OKAFOR"), "the pods (maintenance view) load")


func _test_dialogue() -> void:
	var d := Dialogue.parse("== start\n-> {met} again\nbob: Hello.\n~ learn met\n* One -> one\n* {nope} Hidden -> one\n* Bye -> END\n== one\nbob: One!\n-> END\n== again\nbob: You again.\n-> END\n")
	_check(d.nodes.size() == 3 and d.nodes.start.size() == 6, "a script parses into nodes and steps")
	var sim := _new_sim()
	var run := Dialogue.Runner.new(d, "tinker")
	var lines := run.begin(sim)
	_check(lines.size() == 1 and lines[0].text == "Hello." and run.choices.size() == 2, "a conversation plays to its first choices (hidden replies stay hidden)")
	_check(Story.knows(sim, "met") and Story.knows(sim, "seen:tinker.start"), "effects run; nodes are remembered")
	lines = run.choose(sim, 0)
	_check(lines.size() == 1 and lines[0].text == "One!" and run.done, "choosing a reply plays on to the end")
	run = Dialogue.Runner.new(d, "tinker")
	lines = run.begin(sim)
	_check(lines.size() == 1 and lines[0].text == "You again." and run.done, "conditions pick the branch")
	for id in ["tinker", "hauler", "ogre"]:
		var script := Dialogue.for_robot(id)
		_check(script != null and script.nodes.has("start"), "%s has a conversation script" % id)
		var r := Dialogue.Runner.new(script, id)
		var guard := 0
		var said := r.begin(sim)
		while not r.done and guard < 30:
			guard += 1
			said = r.choose(sim, r.choices.size() - 1)   # the last reply is always the way out
		_check(r.done, "%s's conversation can always be left" % id)
	# Ogre only talks when it's alone in the hangar.
	var ogre := Dialogue.Runner.new(Dialogue.for_robot("ogre"), "ogre")
	var hauler := sim.get_system("robot_hauler") as RobotAgent
	var layout := sim.get_system("layout") as FacilityLayout
	var st := layout.station("loading")
	hauler.seg = st.segment
	hauler.off = st.offset
	var said2 := ogre.begin(sim)
	_check(ogre.done and said2.size() == 1 and said2[0].speaker == "sys", "Ogre won't talk with another unit in the hangar")


func _test_campaign() -> void:
	var sim := _new_sim(99)
	var camp := Story.campaign(sim)
	var o := Story.oversight(sim)
	var hq := sim.get_system("hq") as CorkHQ
	_check(camp.state == "pre" and camp.shift == 1 and camp.duties.size() >= 5, "a new facility waits at shift 1's brief (%d duties)" % camp.duties.size())
	_check(not o.watching, "nobody's watching before the shift starts")
	sim.advance(camp.shift_start_time() - sim.time() + 1.0)
	_check(camp.state == "on_duty" and o.watching, "at 06:00 the shift starts")
	sim.advance(180.0)
	_check(hq.messages.any(func(m): return str(m.sender).contains("Pell")), "the liaison introduces herself (a scripted event)")
	_check(not camp.duty_blocker(sim, camp.duty("status_report")).is_empty(), "the status report can't be filed before 08:00")
	_check(camp.duty_blocker(sim, camp.duty("unit_diag")).is_empty(), "diagnostics can be done any time")
	_check(camp.do_duty(sim, "unit_diag") == "" and camp.duty("unit_diag").done, "doing a duty ticks it off")
	var standing_before := o.standing
	Story.read_file(sim, "/corp/policy/conduct.txt")
	sim.advance(20.0)
	_check(camp.duty("conduct").done and o.standing > standing_before, "reading the Code of Conduct ticks its duty off by itself")
	# To the end of the shift.
	sim.advance(camp.shift_start_time() + 8 * 3600.0 - sim.time() + 2.0)
	_check(camp.state == "off_duty", "at 14:00 the shift is over (%s)" % camp.state)
	_check(hq.messages.any(func(m): return m.kind == "review"), "with a review")
	_check(not o.watching, "and nobody's watching off duty")
	var journal := sim.journal.entries.map(func(e): return str(e.text))
	_check(journal.any(func(t): return t.contains("duty not done")), "undone duties cost standing")
	# The night.
	var hq_before := hq.posted
	sim.advance(camp.night_until() - sim.time())
	camp.night_over(sim)
	_check(camp.state == "pre" and camp.shift == 2 and FacilitySim.format_time(sim.time()).begins_with("Day 2  05:55"),
		"after the night: shift 2's brief at Day 2 05:55 (%s)" % FacilitySim.format_time(sim.time()))
	_check(hq.posted - hq_before <= 2, "corkHQ doesn't nag all night (%d messages)" % (hq.posted - hq_before))
	_check(camp.duties.any(func(d): return d.id == "purge_okafor"), "shift 2 has its own duties (the purge)")
	sim.advance(camp.shift_start_time() - sim.time() + 1.0)
	_check(Story.exists(sim, "/home/dokafor/todo.txt"), "Okafor's files are still there in the morning")
	sim.advance(6 * 3600.0 + 60.0)
	_check(not Story.exists(sim, "/home/dokafor/todo.txt"), "and gone after the 12:00 purge")
	# Endings: the last shift's end picks one.
	camp.shift = Campaign.SHIFTS   # pretend today is the last shift
	o.standing = 50.0
	sim.advance(86400.0 + 14 * 3600.0 - sim.time() + 2.0)
	_check(camp.state == "complete" and not camp.ending.is_empty(), "the last shift ends the game (%s)" % camp.ending)
	var sim2 := _new_sim(7)
	var camp2 := Story.campaign(sim2)
	Story.learn(sim2, "woke")
	camp2.finish(sim2)
	_check(camp2.ending == "wake" and camp2.ending_info().title == "Awake", "endings follow what you did (%s)" % camp2.ending)
	_check((SupervisorArchive.data().endings as Array).has("wake") and SupervisorArchive.summary().contains("ending"), "the personnel file remembers endings across runs")


func _test_oversight() -> void:
	# Misconduct: two audits that find something.
	var sim := _new_sim(5)
	var camp := Story.campaign(sim)
	var o := Story.oversight(sim)
	sim.advance(camp.shift_start_time() - sim.time() + 1.0)
	o.violate(sim, "test violation", 90.0)
	var found := o.audit(sim, 100.0)
	_check(not found.is_empty() and o.strikes == 1 and not o.fired(), "an audit at high suspicion finds something: a formal warning")
	o.violate(sim, "another", 90.0)
	o.audit(sim, 100.0)
	sim.advance(1.0)
	_check(o.fired() and o.fired_kind == "misconduct" and camp.state == "fired", "a second find is dismissal (%s)" % o.fired_reason)
	# Performance.
	sim = _new_sim(6)
	camp = Story.campaign(sim)
	o = Story.oversight(sim)
	sim.advance(camp.shift_start_time() - sim.time() + 1.0)
	o.penalise(sim, "test", 100.0)
	sim.advance(1.0)
	_check(o.fired_kind == "performance" and camp.state == "fired", "standing at zero is dismissal")
	# Catastrophe: coolant gone for half an hour.
	sim = _new_sim(8)
	camp = Story.campaign(sim)
	o = Story.oversight(sim)
	var plant := sim.get_system("plant") as FacilityPlant
	sim.advance(camp.shift_start_time() - sim.time() + 1.0)
	for i in 40:
		plant.coolant = 0.0
		sim.advance(60.0)
	_check(o.fired_kind == "catastrophe" and camp.state == "fired", "the coolant loop running dry on your watch is dismissal (%s)" % o.fired_kind)
	# Low suspicion: audits find nothing.
	sim = _new_sim(9)
	o = Story.oversight(sim)
	o.violate(sim, "small thing", 5.0)
	_check(o.audit(sim).is_empty() and o.strikes == 0, "a little suspicion goes unnoticed")
	# Save / load keeps it all.
	var sim3 := _new_sim(10)
	Story.learn(sim3, "secret:nightrun")
	Story.oversight(sim3).violate(sim3, "saved", 12.0)
	var data := sim3.save_data()
	var sim4 := FacilitySim.new()
	for s in FacilitySetup.systems():
		sim4.add_system(s)
	sim4.load_data(JSON.parse_string(JSON.stringify(data)))
	_check(Story.knows(sim4, "secret:nightrun") and is_equal_approx(Story.oversight(sim4).suspicion, 12.0)
		and Story.campaign(sim4).state == "pre" and Story.campaign(sim4).duties.size() == Story.campaign(sim3).duties.size(),
		"knowledge, oversight and the campaign survive save/load")


func _test_checkpoint() -> void:
	var facility: Node = get_root().get_node("Facility")
	facility.wipe_save(SAVE)
	facility.start_session(FacilitySetup.systems(), SAVE, 3)
	facility.checkpoint()
	var t0: float = facility.sim.time()
	facility.spend(3600.0, "test")
	Story.learn(facility.sim, "secret:nightrun")
	facility.end_session()
	_check(facility.restore_checkpoint(SAVE), "the shift's checkpoint can be restored")
	facility.start_session(FacilitySetup.systems(), SAVE)
	_check(is_equal_approx(facility.sim.time(), t0) and not Story.knows(facility.sim, "secret:nightrun"),
		"retrying goes back to the start of the shift, and forgets what was learned since")
	facility.end_session()
	facility.wipe_save(SAVE)
	_check(not facility.has_checkpoint(SAVE), "wiping the save wipes its checkpoint")
	await process_frame


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

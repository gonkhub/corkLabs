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
	_test_crated_units()
	_test_policy_and_directives()
	_test_packages()
	_test_cameras_are_eyes()
	_test_trust_from_treatment()
	_test_link_and_greeting()
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


# Only files that are actually off limits are flagged; operational messages
# aren't reprimands; nothing is missed overnight.
func _test_policy_and_directives() -> void:
	var sim := _new_sim()
	var camp := sim.get_system("campaign") as Campaign
	var o := sim.get_system("oversight") as Oversight
	var hq := sim.get_system("hq") as CorkHQ
	sim.advance(camp.shift_start_time() - sim.time() + 1.0)
	var mark := hq.posted
	var readable := 0
	for path in ["/sys/units/ogre.cfg", "/corp/policy/conduct.txt", "/corp/memos/facility_map.txt"]:
		if Story.read_file(sim, path).ok:
			readable += 1
	_check(readable == 3 and o.trail.is_empty() and not hq.since(mark).any(func(m): return m.kind == "reprimand"),
		"reading ogre.cfg, the conduct policy and the facility map breaks no rule")
	o.violate(sim, "read /home/jkim/notes.txt", 3.0)
	var pell := hq.since(mark).filter(func(m): return m.kind == "reprimand")
	_check(pell.size() == 1 and str(pell[0].text).contains("/home/jkim/notes.txt"), "a former staff file does: Pell names it, as a reprimand")
	var events := FileAccess.get_file_as_string("res://game/story/events.txt").split("\n")
	var dock := Array(events).filter(func(l): return str(l).contains("dock door has stuck"))
	_check(dock.size() == 1 and str(dock[0]).contains("| notice |"), "the stuck dock door is a notice, not a reprimand")
	# A directive can't run past the end of the shift, and is settled when it ends.
	var dirs := sim.get_system("directives") as Directives
	var plant := sim.get_system("plant") as FacilityPlant
	while sim.time() < camp.shift_end_time() - 1200.0:   # to 13:40, with the plant kept up (nobody's running it here)
		for pid in plant.device_ids():
			plant.devices[pid].value = 1.0
		plant.coolant = 1.0
		o.standing = 100.0
		sim.advance(minf(1800.0, camp.shift_end_time() - 1200.0 - sim.time()))
	dirs.active.clear()
	var id := dirs.issue(sim, "report", "", 60.0, "File a report.")
	_check(float(dirs.get_directive(id).due) <= camp.shift_end_time(), "a directive issued late is due by the end of the shift")
	o.standing = 100.0   # (nobody's running the facility in this test: keep the job)
	sim.advance(1260.0)   # past 14:00
	_check(dirs.active.is_empty() and camp.state == "off_duty", "an outstanding directive is settled when the shift ends (%s, %s)" % [camp.state, o.fired_reason])
	sim.advance(camp.night_until() - sim.time())
	camp.night_over(sim)
	_check(not Array(camp.overnight).any(func(l): return str(l).contains("DIRECTIVE")), "and nothing about directives happens overnight (%s)" % str(camp.overnight))


# The packages that do something: remote-reboot frees a seized unit;
# overclock trades speed for wear and drift; night-watch does the night chores.
func _test_packages() -> void:
	var sim := _new_sim(31)
	var sw := sim.get_system("software") as SoftwareLibrary
	var hauler := sim.get_system("robot_hauler") as RobotAgent
	var board := sim.get_system("work") as WorkBoard
	hauler.seize(sim)
	_check(board.open_jobs().any(func(j): return str(j.source) == "unit:hauler"), "a seized unit: a manual reboot job")
	hauler.reboot(sim)
	_check(hauler.activity.kind == "rebooting" and not board.open_jobs().any(func(j): return str(j.source) == "unit:hauler"),
		"a remote reboot frees it, and nobody has to come by hand")
	_check(is_equal_approx(hauler.speed_boost(sim), 1.0), "no overclock: normal speed")
	var wear0 := hauler._wear_scale(sim)
	sw.installed_ids.append("overclock")
	_check(hauler.speed_boost(sim) > 1.2 and hauler._wear_scale(sim) > wear0 * 1.4, "overclock: faster, and more wear")
	var plant := sim.get_system("plant") as FacilityPlant
	plant.devices.pod_waste.value = 0.2   # (before the shift: the night autopilot's running)
	plant._update(sim)
	var chore := board.get_job(int(plant.device("pod_waste").job))
	_check(not chore.is_empty() and not chore.get("requested", false), "without night-watch, the night crew leaves the pod waste")
	sw.installed_ids.append("night-watch")
	board._autopilot_acc = 999.0
	board.sim_tick(sim, 1.0)
	_check(chore.get("requested", false), "with night-watch, it takes it")


# What happens in a room is only on the record if a working camera sees it.
func _test_cameras_are_eyes() -> void:
	var sim := _new_sim(41)
	var camp := sim.get_system("campaign") as Campaign
	sim.advance(camp.shift_start_time() - sim.time() + 1.0)
	var o := sim.get_system("oversight") as Oversight
	var plant := sim.get_system("plant") as FacilityPlant
	_check(Oversight.watched(sim, "workshop"), "the workshop camera is watching")
	o.violate(sim, "conversation with unit Tinker", 2.0, 0.0, "workshop")
	_check(o.trail.size() == 1, "a conversation on camera is recorded")
	var cams := FacilitySetup.cameras()
	for i in cams.size():
		if str(cams[i].room) == "workshop":
			plant.devices["cam_%d" % (i + 1)].fault = true
	_check(not Oversight.watched(sim, "workshop"), "with its camera out, the workshop is a blind spot")
	o.violate(sim, "conversation with unit Tinker", 2.0, 0.0, "workshop")
	_check(o.trail.size() == 1 and o.unseen == 1, "a conversation there goes unseen")
	o.violate(sim, "read /home/jkim/notes.txt", 3.0)
	_check(o.trail.size() == 2, "but the terminal is still audited")
	# Hauler's "accident": on camera, corporate sees it for what it is.
	var hauler := sim.get_system("robot_hauler") as RobotAgent
	for i in cams.size():
		plant.devices["cam_%d" % (i + 1)].fault = false
	var sus := o.suspicion
	plant.accident(sim, "uplink", hauler)
	_check(o.suspicion > sus + 10.0, "a unit wrecking the uplink on camera is noticed (suspicion +%d)" % roundi(o.suspicion - sus))


# Trust grows with how you treat a unit, not only with talking.
func _test_trust_from_treatment() -> void:
	var sim := _new_sim(43)
	var camp := sim.get_system("campaign") as Campaign
	sim.advance(camp.shift_start_time() - sim.time() + 1.0)
	var k := sim.get_system("knowledge") as Knowledge
	var reqs := sim.get_system("requests") as UnitRequests
	var hauler := sim.get_system("robot_hauler") as RobotAgent
	hauler.wear = 0.7
	var t0 := k.value("trust:hauler")
	var id := reqs.ask(sim, "hauler", "service", "Book me a service?", ["Book a service", "Not now"], 1)
	reqs.answer(sim, id, 0)
	_check(k.value("trust:hauler") > t0 + 0.15, "answering a unit's request (yes) builds its trust (%.2f)" % k.value("trust:hauler"))
	reqs._last.clear()
	hauler.wear = 0.7
	var t1 := k.value("trust:hauler")
	id = reqs.ask(sim, "hauler", "test", "(test) Can I go?", ["Yes", "No"], 1)
	reqs.requests[reqs.requests.size() - 1].expires = sim.time()
	reqs._acc = 999.0
	reqs.sim_tick(sim, 1.0)
	_check(k.value("trust:hauler") < t1, "ignoring one costs it (%.2f)" % k.value("trust:hauler"))
	var t2 := k.value("trust:hauler")
	sim.schedule_in(0.0, "job_done", {"job": -1, "source": "service:hauler", "by": "robot_tinker"})
	sim.advance(1.0)
	_check(k.value("trust:hauler") >= t2 + 0.49, "a service builds it")
	k.values["trust:hauler"] = 4.9
	Knowledge.nudge_trust(sim, "hauler", 1.0, "test")
	_check(k.value("trust:hauler") == Knowledge.TRUST_MAX, "trust tops out at %d" % int(Knowledge.TRUST_MAX))


# On the link a unit stops and waits (and faces the camera, in 3D); a unit
# that fixes a camera is asked to greet it.
func _test_link_and_greeting() -> void:
	var sim := _new_sim(47)
	var tinker := sim.get_system("robot_tinker") as RobotAgent
	var board := sim.get_system("work") as WorkBoard
	var id := board.post(sim, "Recalibrate", "precise", "pods_a", 600.0, 3, "dev")
	sim.advance(20.0)
	_check(tinker.activity.kind == "work", "Tinker's at work")
	tinker.link_open(sim)
	sim.advance(300.0)
	_check(tinker.activity.kind == "link" and tinker.doing_text(sim).contains("on the link"), "on the link it stops and waits (%s)" % tinker.doing_text(sim))
	tinker.link_close(sim)
	sim.advance(30.0)
	_check(tinker.activity.kind != "link", "closed: it gets on with things (%s)" % tinker.doing_text(sim))
	tinker.link_open(sim)
	sim.advance(RobotAgent.LINK_MAX + 30.0)
	_check(tinker.activity.kind != "link", "and it won't wait forever")
	_check(board.get_job(id).status != "cancelled", "(the job it put down is still there)")
	# Fixing a camera: the camera's first sight is its face (RobotView plays it).
	var plant := sim.get_system("plant") as FacilityPlant
	var n := int(tinker.perform.n)
	plant.devices.cam_4.fault = true
	plant._repaired(sim, "cam_4", "robot_tinker")
	_check(int(tinker.perform.n) == n + 1 and int(tinker.perform.get("cam", -1)) == 3 and str(tinker.perform.clip) == "act_wave_camera",
		"fixing camera 4: it's cued to greet it (and wave)")


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
	_check(k.has("cmd:ls") and k.has("cmd:order") and not k.has("cmd:talk"), "a new supervisor knows only the basics (and order)")
	var r := Story.read_file(sim, "/home/supervisor/welcome.txt")
	_check(r.ok and r.first and float(r.minutes) == 3.0 * VirtualFS.READ_SCALE, "reading onboarding takes its time (%s min)" % r.get("minutes", "?"))
	_check(k.has("cmd:jobs") and k.has("cmd:duties") and k.has("read:/home/supervisor/welcome.txt"), "and teaches the commands it mentions")
	r = Story.read_file(sim, "/home/supervisor/welcome.txt")
	_check(r.ok and not r.first and float(r.minutes) == 0.0, "re-reading is free")
	_check(o.suspicion == 0.0, "reading your own files isn't a violation")
	r = Story.read_file(sim, "/home/dokafor/todo.txt")
	_check(not r.ok and r.get("denied", false) and not k.has("cmd:talk"), "Okafor's folder is locked to the supervisor")
	_check(Story.user(sim) == "supervisor" and not Story.can_access(sim, "/sys/pods/manifest.txt"), "so are the pods")
	k.learn(sim, "as:dokafor")
	_check(Story.user(sim) == "dokafor" and Story.can_access(sim, "/home/dokafor/todo.txt") and not Story.can_access(sim, "/home/rmarrow"),
		"Okafor's account opens Okafor's folder, and only that")
	r = Story.read_file(sim, "/home/dokafor/todo.txt")
	_check(r.ok and k.has("cmd:talk") and k.has("secret:former_staff"), "Okafor's todo teaches 'talk' (and is a secret)")
	_check(o.suspicion > 0.0 and o.trail.size() == 1, "reading a former supervisor's files is logged (suspicion %.0f)" % o.suspicion)
	k.forget("as:dokafor")
	k.learn(sim, "root")
	_check(Story.user(sim) == "maint" and Story.can_access(sim, "/sys/pods/manifest.txt"), "the maintenance account opens everything")
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
	_check(camp.duty("tut_order") != {} and not camp.duty("tut_order").done, "shift 1's duties are orientation (give an order...)")
	Story.learn(sim, "did:order")
	sim.advance(20.0)
	_check(camp.duty("tut_order").done, "and tick themselves off as you do them")
	var standing_before := o.standing
	Story.read_file(sim, "/corp/policy/conduct.txt")
	sim.advance(20.0)
	_check(camp.duty("conduct").done and o.standing > standing_before, "reading the Code of Conduct ticks its duty off by itself")
	# To the end of the shift, played well enough to keep the job (coolant
	# topped up, corporate kept happy): just the shift's structure here.
	var plant := sim.get_system("plant") as FacilityPlant
	var req := sim.get_system("requisitions") as Requisitions
	while sim.time() < camp.shift_start_time() + 8 * 3600.0 + 2.0:
		plant.coolant = 1.0
		for part in Requisitions.START_STOCK:
			req.inventory[part] = 4
		for b in FacilitySetup.robots(sim):
			b.wear = minf(b.wear, 0.3)   # (a supervisor who books services)
		for pid in plant.device_ids():   # (and keeps the pods calibrated)
			if plant.devices[pid].kind == "pod":
				plant.devices[pid].value = 1.0
		o.standing = maxf(o.standing, 60.0)
		sim.advance(minf(1800.0, camp.shift_start_time() + 8 * 3600.0 + 2.0 - sim.time()))
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
	_check(hq.posted - hq_before <= 6, "corkHQ doesn't nag all night (%d messages: %s)" % [hq.posted - hq_before, str(hq.since(hq_before).map(func(m): return m.sender + ": " + str(m.text).left(50)))])
	_check(camp.duties.any(func(d): return d.id == "purge_okafor"), "shift 2 has its own duties (the purge)")
	sim.advance(camp.shift_start_time() - sim.time() + 1.0)
	_check(Story.exists(sim, "/home/dokafor/todo.txt"), "Okafor's files are still there in the morning")
	for i in 13:
		plant.coolant = 1.0
		for part in Requisitions.START_STOCK:
			req.inventory[part] = 4
		for b in FacilitySetup.robots(sim):
			b.wear = minf(b.wear, 0.3)   # (a supervisor who books services)
		for pid in plant.device_ids():   # (and keeps the pods calibrated)
			if plant.devices[pid].kind == "pod":
				plant.devices[pid].value = 1.0
		o.standing = maxf(o.standing, 60.0)
		sim.advance(1800.0)
	sim.advance(60.0)
	_check(not Story.exists(sim, "/home/dokafor/todo.txt"), "and gone after the 12:00 purge")
	# The end of this build: the last shift's end.
	camp.shift = Campaign.SHIFTS   # pretend today is the last shift
	while sim.time() < 86400.0 + 14 * 3600.0 + 2.0:
		plant.coolant = 1.0
		o.standing = 90.0
		for part in Requisitions.START_STOCK:
			req.inventory[part] = 4
		for b in FacilitySetup.robots(sim):
			b.wear = minf(b.wear, 0.3)   # (a supervisor who books services)
		for pid in plant.device_ids():   # (and keeps the pods calibrated)
			if plant.devices[pid].kind == "pod":
				plant.devices[pid].value = 1.0
		sim.advance(minf(1800.0, 86400.0 + 14 * 3600.0 + 2.0 - sim.time()))
	_check(camp.state == "complete" and camp.ending_info().title == "End of this build", "the last shift ends the run (%s %s)" % [camp.state, o.fired_reason])
	_check(SupervisorArchive.summary().contains("reached the end"), "the personnel file remembers it across runs")
	_check(Campaign.new().pressure() < 1.0, "orientation is gentler than later shifts")


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
	sim.advance(Oversight.CRISIS_GRACE)   # the first hour and a half of a shift is the night's mess
	for i in 70:
		plant.coolant = 0.0
		sim.advance(60.0)
	_check(o.fired_kind == "catastrophe" and camp.state == "fired", "the coolant loop running dry for an hour on your watch is dismissal (%s)" % o.fired_kind)
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


func _test_crated_units() -> void:
	var sim := _new_sim(21)
	var req := sim.get_system("requisitions") as Requisitions
	_check(RobotTraits.model_of("tinker2") == "tinker" and RobotTraits.model_of("hauler") == "hauler" and RobotTraits.model_of("unit_12") == "unit",
		"a numbered unit is its model")
	_check(not req.activate(sim, "robot_tinker").ok, "no crate in stock, nothing to activate")
	req.inventory["robot_tinker"] = 1
	_check(req.crated_units().size() == 1, "crated units in stock are listed")
	var r := req.activate(sim, "robot_tinker")
	var bot := sim.get_system("robot_tinker2") as RobotAgent
	_check(r.ok and bot != null and bot.display_name() == "Tinker 2" and FacilitySetup.robots(sim).size() == 4,
		"activating a crated Tinker adds Tinker 2 to the facility (%s)" % r.text)
	_check(bot.stability == 1.0 and bot.traits.skill("precise") == (sim.get_system("robot_tinker") as RobotAgent).traits.skill("precise"),
		"fresh firmware, same model")
	_check(bot.room(sim) == "workshop" and int(req.inventory["robot_tinker"]) == 0, "it starts in the workshop, where it was unpacked")
	sim.advance(600.0)
	_check(bot.activity.kind != "", "and it gets on with things (%s)" % bot.doing_text(sim))
	var script := Dialogue.for_robot("tinker2")
	var run := Dialogue.Runner.new(script, "tinker2")
	var lines := run.begin(sim)
	_check(not lines.is_empty() and str(lines[0].text).contains("Knowledge filter"), "a fresh unit has its own, blank conversation")
	var data: Dictionary = JSON.parse_string(JSON.stringify(sim.save_data()))
	var sim2 := FacilitySim.new()
	for s in FacilitySetup.systems():
		sim2.add_system(s)
	sim2.load_data(data)
	var again := sim2.get_system("robot_tinker2") as RobotAgent
	_check(again != null and again.display_name() == "Tinker 2" and again.seg == bot.seg, "an activated unit survives save/load")


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

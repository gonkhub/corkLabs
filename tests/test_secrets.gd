# Plays through the corkLabs OS: the Terminal (help only lists what you know,
# typing a real command teaches it), the file system and its locked folders
# (Okafor's account, the maintenance account), conversations, Files, Duties
# and directives, units' requests, parts and wear, the corkHQ uplink and
# Hauler's "accident", Pell escalating, Night Run, dismissal and retrying the
# shift, and the end of the build.
extends SceneTree

const SAVE := "user://test_secrets_save.json"
const OS_SETTINGS := "user://test_secrets_os_settings.json"

var failures := 0
var facility: Node
var desk: Control
var sup   # Supervisor, by path: classes that use the Facility autoload can't be named in --script tests


func _initialize() -> void:
	SupervisorArchive.use_file("user://test_supervisor_archive.json")   # never the real personnel file
	sup = load("res://game/supervisor.gd")
	get_root().size = Vector2i(1600, 900)
	facility = get_root().get_node("Facility")
	facility.wipe_save(SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OS_SETTINGS))
	OSSettings.use_file(OS_SETTINGS)
	desk = (load("res://os/desktop.tscn") as PackedScene).instantiate()
	desk.save_path = SAVE
	desk.skip_boot = true
	get_root().add_child(desk)
	await process_frame
	desk.set_anchors_preset(Control.PRESET_TOP_LEFT)
	desk.size = Vector2(1600, 900)
	desk.log_on()
	await process_frame
	await process_frame
	_check(desk.shift_screen.visible and _screen_says("SHIFT 1"), "log on shows shift 1's brief")
	_check(facility.has_checkpoint(SAVE), "the brief saves the shift's checkpoint")
	desk.clock_in()
	await process_frame
	await process_frame

	await _test_terminal()
	_keep_employed()
	await _test_apps()
	_keep_employed()
	await _test_bin_and_notes()
	_keep_employed()
	await _test_parts_and_wear()
	_keep_employed()
	await _test_corporate()
	_keep_employed()
	await _test_uplink()
	_keep_employed()
	await _test_nightrun()
	_keep_employed()
	await _test_maint()
	_keep_employed()
	await _test_fired_and_retry()
	await _test_end()

	desk.log_off()
	desk.free()
	facility.wipe_save(SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OS_SETTINGS))
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func sim() -> FacilitySim:
	return facility.sim


# Every section spends hours of facility time and breaks rules on purpose:
# keep the supervisor employed (and the facility alive) between them.
func _keep_employed() -> void:
	var o := Story.oversight(sim())
	o.standing = 100.0
	o.suspicion = 0.0
	o.strikes = 0
	o.fired_reason = ""
	o.fired_kind = ""
	var camp := Story.campaign(sim())
	if camp.state == "fired":
		camp.state = "on_duty"
	(sim().get_system("plant") as FacilityPlant).coolant = 1.0
	var dirs := sim().get_system("directives") as Directives
	dirs.active.clear()


func _test_terminal() -> void:
	var term = desk.open_app("terminal")
	await process_frame
	var help: String = term.run("help")
	_check(help.contains("ls") and not help.contains("order") and not help.contains("podctl"), "help lists only what a new supervisor knows")
	_check(term.run("ls").contains("welcome.txt"), "ls in the home folder shows the onboarding file")
	var t0 := sim().time()
	var out: String = term.run("cat welcome.txt")
	_check(out.contains("WELCOME TO corkLabs") and sim().time() - t0 >= 539.0, "cat reads it, and reading takes a while (%d min)" % roundi((sim().time() - t0) / 60.0))
	_check(out.contains("new commands noted") and term.run("help").contains("jobs"), "what it mentions is learned (help lists 'jobs' now)")
	t0 = sim().time()
	term.run("cat welcome.txt")
	_check(is_equal_approx(sim().time(), t0), "reading it again is free")
	out = term.run("whoami")
	_check(out.contains("new command noted") and out.contains("probationary"), "typing a real, unlisted command works and teaches it")
	_check(term.run("xyzzy").contains("command not found"), "made-up commands don't")
	t0 = sim().time()
	out = term.run("grep transferred")
	_check(out.contains("/corp/memos/") and sim().time() - t0 >= 899.0, "grep searches what you can open (15 min)")
	_check(not out.contains("/home/dokafor"), "but not folders you can't open")
	_check(term.run("find transfer").contains("/corp/memos/1994-transfer-hollis.txt"), "find lists files by name")
	_check(term.run("who").contains("pell") and term.run("ps").contains("auditd") and Story.knows(sim(), "hint:uplink"),
		"who and ps show who's watching (and how: the uplink)")
	_check(term.run("kill 45").contains("permission denied"), "kill is for maint")
	_check(term.run("history").contains("whoami"), "history lists what you typed")
	term.run("cd /home")
	out = term.run("ls")
	_check(out.contains("dokafor/") and out.contains("rmarrow/"), "/home has the former supervisors' folders")
	_check(term.run("ls dokafor").contains("Permission denied") and term.run("cat dokafor/todo.txt").contains("Permission denied"),
		"which are locked")
	_check(term.run("cat jkim/notes.txt").contains("the panel won't close"), "(the short-timers' aren't)")
	# Okafor's account: Tinker, backwards.
	term.run("su dokafor")
	out = term.run("tinker")
	_check(out.contains("Authentication failure"), "su dokafor: not that")
	term.run("su dokafor")
	out = term.run("reknit")
	_check(out.contains("2,511 sessions") and term.prompt_label.text.begins_with("dokafor@") and Story.knows(sim(), "secret:okafor_account"),
		"su dokafor with Tinker backwards opens Okafor's account")
	_check(term.run("pwd").contains("/home/dokafor"), "and drops you in their home")
	_check(not term.run("ls").contains(".pod3") and term.run("ls -a").contains(".pod3"), "ls -a shows hidden files")
	out = term.run("cat todo.txt")
	_check(out.contains("talk tinker") and Story.knows(sim(), "cmd:talk"), "Okafor's todo list teaches 'talk'")
	_check(Story.oversight(sim()).suspicion > 0.0, "and reading it was logged")
	out = term.run("cp todo.txt")
	_check(out.contains("Copied to ~/todo.txt") and Story.knows(sim(), "secret:kept"), "cp copies Okafor's todo into your home (%s)" % out.strip_edges())
	_check(term.run("cat /home/rmarrow/README_IF_YOU_REPLACED_ME.txt").contains("Permission denied"), "Marrow's home is still shut to dokafor")
	term.run("exit")
	_check(term.prompt_label.text.begins_with("supervisor@") and term.run("ls /home/dokafor").contains("Permission denied"), "exit: back to yourself")
	Story.learn(sim(), "purged:dokafor")
	_check(term.run("cat ~/todo.txt").contains("talk tinker") and term.run("su dokafor").contains("does not exist"),
		"after the purge the account's gone, the copy isn't")
	Story.knowledge(sim()).forget("purged:dokafor")
	# Talk to Tinker: it takes trust, built over separate conversations.
	var tinker := sim().get_system("robot_tinker") as RobotAgent
	tinker.stability = 0.5
	t0 = sim().time()
	out = term.run("talk tinker")
	var cams = desk._windows["cameras"].app if desk._windows.has("cameras") else null
	_check(cams != null and out.contains("unit link") and cams.talk_runner != null and cams.talk_log.get_parsed_text().contains("TINKER:")
		and sim().time() - t0 >= 179.0, "talk opens the unit link in Cameras; lines cost time")
	if cams == null:
		return
	_check(tinker.stability > 0.5, "a conversation steadies the unit")
	_check(Story.knowledge(sim()).value("trust:tinker") == 1.0, "and counts toward its trust")
	cams._talk_choose(1)   # "Who was here before me?"
	_check(cams.talk_log.get_parsed_text().contains("Okafor") and Story.knows(sim(), "asked:okafor"), "picking a reply plays on")
	_check(cams.talk_runner == null or not cams.talk_runner.choices.any(func(c): return str(c.text).contains("private")), "(nothing private yet: trust 1)")
	cams.end_talk()
	_check(cams.talk_runner == null and not cams.talk_box.visible, "closing the link")
	cams.start_talk("tinker")
	cams.end_talk()
	_check(Story.knowledge(sim()).value("trust:tinker") == 1.0, "talking again straight away doesn't build trust")
	Story.knowledge(sim()).values["trust:tinker"] = 3.0
	cams.start_talk("tinker")
	_check(cams.talk_runner.choices.any(func(c): return str(c.text).contains("private")), "with trust, Tinker can be asked something private")
	cams.end_talk()


func _test_apps() -> void:
	var files = desk.open_app("files")
	await process_frame
	files.dir = "/corp/memos"
	files._fill_list()
	var names: Array = []
	for i in files.list.item_count:
		names.append(files.list.get_item_text(i))
	_check(names.any(func(n): return str(n).begins_with("facility_map")), "Files lists a folder (%s)" % ", ".join(names))
	files.dir = "/home/rmarrow"
	files._fill_list()
	_check(files.list.item_count == 0 and files.view.get_parsed_text().contains("Permission denied"), "and won't open a locked one")
	files.refresh()
	_check(files.hidden_box.visible, "Show hidden appears once ls -a showed you hidden files exist")
	files.open_file("/corp/memos/facility_map.txt")
	_check(files.view.get_parsed_text().contains("UPLINK RELAY") and Story.knows(sim(), "cmd:routes"), "opening a file reads it (and teaches)")
	# Duties: shift 1 walks you through the OS.
	var duties = desk.open_app("duties")
	desk.open_app("cameras")
	await process_frame
	facility.spend(20.0, "test")
	var camp := Story.campaign(sim())
	_check(camp.duty("tut_cameras").done and camp.duty("onboarding").done and camp.duty("tut_order").done == false,
		"tutorial duties tick themselves off as you do things (cameras, onboarding)")
	duties.refresh()
	_check(duties.rows.get_child_count() >= camp.duties.size(), "Duties lists the shift's duties")
	# A unit's menu (Cameras): Talk once you know you can; diagnose takes half an hour.
	var menu: Array = load("res://os/object_menu.gd").entries(sim(), "robot:tinker")
	_check(menu.any(func(e): return e.get("talk", false)) and load("res://os/object_menu.gd").describe(sim(), "robot:tinker").contains("wear"),
		"a unit's menu has Talk, and hovering it shows its wear")
	var t0 := sim().time()
	var diag: Dictionary = load("res://os/object_menu.gd").entries(sim(), "robot:hauler").filter(func(e): return str(e.get("text", "")).begins_with("Diagnose"))[0]
	var said: String = diag.act.call()
	_check(sim().time() - t0 >= 1799.0 and said.contains("DIAG"), "Diagnose takes 30 minutes and reads the unit out")


func _test_bin_and_notes() -> void:
	var bin = desk.open_app("bin")
	await process_frame
	bin._fill_list()
	var names: Array = []
	for i in bin.list.item_count:
		names.append(bin.list.get_item_text(i))
	_check(bin.dir == "/trash" and names.any(func(n): return str(n).begins_with("resignation_draft")), "the Recycle Bin holds deleted files (%s)" % ", ".join(names))
	bin.open_file("/trash/untitled.txt")
	_check(bin.view.get_parsed_text().contains("the light stays on"), "which can still be read")
	var standing := Story.oversight(sim()).standing
	Story.oversight(sim()).standing = 50.0
	bin.empty_button.pressed.emit()
	bin._fill_list()
	_check(bin.list.item_count == 0 and Story.oversight(sim()).standing > 50.0 and bin.empty_button.disabled,
		"emptying it deletes them for good (corporate likes a tidy terminal)")
	Story.oversight(sim()).standing = standing
	var notes = desk.open_app("notes")
	await process_frame
	_check(notes.edit.text.contains("already on the notepad"), "the Notes app came with someone else's notes")
	notes.edit.text += "\nmaint: top score"
	notes._dirty = 0.01
	notes._process(0.1)
	_check(str(OSSettings.get_value("notes")).contains("maint: top score"), "and keeps yours on the desk")


func _test_parts_and_wear() -> void:
	var plant := sim().get_system("plant") as FacilityPlant
	var board := sim().get_system("work") as WorkBoard
	var req := sim().get_system("requisitions") as Requisitions
	var reqs := sim().get_system("requests") as UnitRequests
	# A leak with no clamps in stock: nobody can be sent until there's a part.
	req.inventory["pipe_clamps"] = 0
	reqs.requests.clear()
	reqs._last.clear()
	if int(plant.device("pipe_2").job) >= 0:
		board.cancel(sim(), int(plant.device("pipe_2").job), "test")
	plant.devices["pipe_2"].job = -1
	plant.devices["pipe_2"].fault = false
	sim().schedule_in(0.0, "plant_fault", {"device": "pipe_2"})
	facility.spend(1.0, "test")
	var job := board.get_job(int(plant.device("pipe_2").job))
	_check(not job.is_empty() and str(job.get("part", "")) == "pipe_clamps", "a leak repair needs a pipe clamp")
	facility.spend(600.0, "test")
	_check(job.status == "open" and not job.get("requested", false), "on duty, nobody touches it until you order it")
	_check(board.waiting_jobs(sim()).has(job) and plant.inspect_text(sim(), "pipe_2").contains("NO PART"), "no clamp in stock: it's waiting for one (and Inspect says so)")
	var menu: Array = load("res://os/object_menu.gd").entries(sim(), "pipe_2")
	var order: Dictionary = menu.filter(func(e): return str(e.get("text", "")) == "Order maintenance")[0]
	var buy: Array = menu.filter(func(e): return str(e.get("text", "")).begins_with("Order Pipe clamp"))
	var patch: Array = menu.filter(func(e): return str(e.get("text", "")).begins_with("Patch it"))
	_check(order.disabled and buy.size() == 1 and patch.size() == 1, "its menu: Order maintenance greyed out, Order a clamp set, Patch it")
	var funds := req.funds
	var t0 := sim().time()
	var out: String = buy[0].act.call()
	_check(out.contains("Requisition") and req.funds < funds and sim().time() - t0 >= 299.0, "ordering the part from the menu places a requisition (5 min)")
	_check(Story.campaign(sim()).duty("tut_requisition").done or Story.knows(sim(), "did:requisition"), "(the tutorial notices)")
	req.unpacked(sim(), int(req.orders.back().id))
	var clamps := int(req.inventory["pipe_clamps"])
	menu = load("res://os/object_menu.gd").entries(sim(), "pipe_2")
	order = menu.filter(func(e): return str(e.get("text", "")).begins_with("Order maintenance"))[0]
	_check(not order.disabled, "with clamps in stock, Order maintenance is there")
	out = order.act.call()
	_check(job.get("requested", false) and int(req.inventory["pipe_clamps"]) == clamps - 1 and (out.contains("on its way") or out.contains("Queued") or out.contains("on it")),
		"ordering maintenance takes a clamp and sends a unit: " + out)
	# Express shipping: dearer, faster.
	var normal := req.place(sim(), "fuse_pack", 1)
	var fast := req.place(sim(), "fuse_pack", 1, true)
	_check(int(fast.order.cost) > int(normal.order.cost) and float(fast.order.eta) - sim().time() < float(normal.order.eta) - sim().time(), "express costs more and arrives sooner")
	# Wear: a seized unit needs a manual reboot (you send someone); services need servos.
	var hauler := sim().get_system("robot_hauler") as RobotAgent
	hauler.seize(sim())
	var reboot := board.jobs.filter(func(j): return str(j.source) == "unit:hauler" and WorkBoard.active(j))
	_check(hauler.offline() and hauler.doing_text(sim()).contains("SEIZED") and reboot.size() == 1 and not reboot[0].get("requested", false),
		"a seized unit is frozen, with a manual reboot job posted (not yet asked for)")
	var send: Array = load("res://os/object_menu.gd").entries(sim(), "robot:hauler").filter(func(e): return str(e.get("text", "")).begins_with("Send a unit to reboot"))
	_check(send.size() == 1, "its menu offers to send a unit to reboot it")
	if send.size() == 1:
		send[0].act.call()
	_check(reboot[0].get("requested", false), "and that requests the reboot")
	var tinker := sim().get_system("robot_tinker") as RobotAgent
	board.release(int(reboot[0].id), str(reboot[0].claimed_by))
	board.claim(int(reboot[0].id), tinker.sim_id)
	board.add_progress(sim(), int(reboot[0].id), tinker.sim_id, float(reboot[0].work))
	facility.spend(1.0, "test")
	_check(not hauler.offline(), "rebooting it by hand gets it moving")
	req.inventory["servo_bundle"] = 1
	hauler.wear = 0.7
	var book: Array = load("res://os/object_menu.gd").entries(sim(), "robot:hauler").filter(func(e): return str(e.get("text", "")).begins_with("Book a service"))
	_check(book.size() == 1 and not book[0].disabled, "its menu offers a service")
	book[0].act.call()
	var svc := board.jobs.filter(func(j): return str(j.source) == "service:hauler" and WorkBoard.active(j))
	_check(svc.size() == 1 and str(svc[0].get("only", "")) == hauler.sim_id and int(req.inventory["servo_bundle"]) == 0,
		"Book a service posts a service only that unit takes, with the servo taken from stock")
	if svc.size() == 1:
		board.release(int(svc[0].id), str(svc[0].claimed_by))
		board.claim(int(svc[0].id), hauler.sim_id)
		board.add_progress(sim(), int(svc[0].id), hauler.sim_id, float(svc[0].work))
	facility.spend(1.0, "test")
	_check(hauler.wear < 0.1, "a service brings wear down")


func _test_corporate() -> void:
	var dirs := sim().get_system("directives") as Directives
	var o := Story.oversight(sim())
	# A directive: report, with a deadline.
	dirs.issue(sim(), "report", "", 60.0, "File a report.")
	var duties = desk.open_app("duties")
	duties._key = ""
	duties.refresh()
	_check(duties.rows.get_children().any(func(r): return r.find_children("*", "Label", true, false).any(func(l): return l.text.begins_with("DIRECTIVE"))),
		"directives sit at the top of Duties")
	var met := dirs.met
	sup.file_report()
	_check(dirs.met > met, "filing the report meets it")
	dirs.issue(sim(), "diagnose", "tinker", 30.0, "Diagnose Tinker.")
	o.standing = 50.0
	facility.spend(31.0 * 60.0, "test")
	_check(not dirs.active.any(func(d): return d.kind == "diagnose") and o.standing < 50.0, "a missed directive costs standing (%s, %s, %.0f)" % [FacilitySim.format_clock(sim().time()), Story.campaign(sim()).state, o.standing])
	# Pell escalates as violations of a kind pile up.
	var hq := sim().get_system("hq") as CorkHQ
	o.counts.clear()
	var before := hq.posted
	o.violate(sim(), "read /home/x", 1.0)
	_check(hq.posted > before and hq.messages.back().sender == "Liaison Pell", "Pell notices the first one")
	o.violate(sim(), "read /home/y", 1.0)
	o.violate(sim(), "read /home/z", 1.0)
	_check(dirs.active.any(func(d): return d.kind == "explain"), "by the third she wants an explanation")
	var panel = desk.hq_panel
	panel.open_reply()
	await process_frame
	var explain := -1
	for i in panel.reply_runner.choices.size():
		if str(panel.reply_runner.choices[i].text).contains("explain"):
			explain = i
	_check(explain >= 0, "Pell's Reply offers to explain")
	panel.choose_reply(explain)
	panel.choose_reply(0)   # "It won't happen again."
	_check(not dirs.active.any(func(d): return d.kind == "explain"), "explaining meets the directive")
	panel.choose_reply(panel.reply_runner.choices.size() - 1)
	await process_frame
	_check(panel.reply_runner == null, "and the reply closes")
	o.violate(sim(), "read /home/a", 1.0)
	var standing := o.standing
	o.violate(sim(), "read /home/b", 1.0)
	_check(o.standing < standing and sim().scheduler.peek(50).any(func(e): return e.name == "targeted_audit"),
		"the fifth: Compliance takes your standing and books a targeted audit")


func _test_uplink() -> void:
	var o := Story.oversight(sim())
	var plant := sim().get_system("plant") as FacilityPlant
	var layout := sim().get_system("layout") as FacilityLayout
	layout.set_blocked(sim(), "freight_gate", false)
	plant.devices["gate"].fault = false
	var k := Story.knowledge(sim())
	k.values["trust:hauler"] = 2.0
	var hauler := sim().get_system("robot_hauler") as RobotAgent
	hauler.power = 1.0
	hauler.stability = 0.9
	var cams = desk.open_app("cameras")
	cams.start_talk("hauler")
	var choice := -1
	for i in cams.talk_runner.choices.size():
		if str(cams.talk_runner.choices[i].text).contains("uplink"):
			choice = i
	_check(choice >= 0, "with trust (and the uplink known), Hauler can be asked about the uplink")
	cams._talk_choose(choice)
	cams._talk_choose(0)   # "Just for an hour."
	_check(cams.talk_log.get_parsed_text().contains("Accidents happen"), "Hauler agrees, and goes")
	cams.end_talk()
	for i in 40:
		if plant.device("uplink").fault:
			break
		facility.spend(300.0, "test")
	_check(plant.device("uplink").fault, "and the uplink relay goes down (%s / %s / %s)" % [str(hauler.order), str(hauler.activity), str(hauler.scores.slice(0, 3).map(func(o): return "%s %.2f" % [o.key, o.score]))])
	_check(not sim().journal.entries.any(func(e): return e.cat == "sabotage" and str(e.text).contains("uplink")), "as an accident: nothing says sabotage")
	await process_frame
	await process_frame
	_check(desk.hq_panel._suspended.visible and desk.hq_panel._suspended.text.begins_with("UPLINK LOST"), "the corkHQ panel loses its link")
	var sus := o.suspicion
	o.violate(sim(), "read /home/anything", 5.0)
	_check(is_equal_approx(o.suspicion, sus) and o.blind > 0, "while it's down, nothing gets recorded")
	_check(o.audit(sim(), 100.0).is_empty(), "and audits can't run")
	var dirs := sim().get_system("directives") as Directives
	_check(dirs.active.any(func(d): return d.kind == "uplink"), "corporate wants it back within the hour")
	plant._repaired(sim(), "uplink", "robot_tinker")
	sim().schedule_in(0.0, "job_done", {"job": -1, "source": "uplink", "by": "robot_tinker"})
	facility.spend(61.0, "test")
	_check(not o.uplink_down(sim()) and o.blind == 0, "repaired: corkHQ is listening again")


func _test_nightrun() -> void:
	_check(desk.open_app("nightrun") == null and not desk.app_available("nightrun"), "Night Run isn't on the desktop until it's found")
	var term = desk.open_app("terminal")
	term.run("cd /opt/games")
	var out: String = term.run("run nightrun")
	await process_frame
	_check(desk.is_open("nightrun") and Story.knows(sim(), "secret:nightrun"), "run nightrun starts the game (%s)" % out.strip_edges())
	desk._refresh_all()
	_check(desk.app_available("nightrun"), "and it's on the desktop from now on")
	var game = desk._windows["nightrun"].app
	_check(game.table()[0][1] == int(Story.MAINT_PASSWORD) and game.table()[0][0] == "RM", "Marrow's top score heads the table")
	var sus := Story.oversight(sim()).suspicion
	var t0 := sim().time()
	game.start_run()
	game.lane = 1
	for i in 6000:
		game.step(1.0 / 60.0, false, false)
		if game.state != "run":
			break
	_check(game.state == "crash" and sim().time() - t0 >= 1799.0, "a run ends in a crash, and costs 30 facility minutes")
	_check(Story.oversight(sim()).suspicion > sus, "playing is logged (recreational software)")
	game.start_run()
	game.step(0.02, true, false)
	game.step(0.02, false, false)
	game.step(0.02, true, false)
	for i in 120:
		game.step(1.0 / 60.0, true, false)
	_check(game.state == "wrong_way" and Story.knows(sim(), "secret:wrong_way") and Story.knows(sim(), "hint:lantern"),
		"holding left into the NO ENTRY sign takes you the wrong way (%s)" % game.state)


func _test_maint() -> void:
	var term = desk.open_app("terminal")
	var out: String = term.run("podctl list")
	_check(out.contains("permission denied") and Story.knows(sim(), "cmd:podctl"), "maintenance commands are real, but denied")
	_check(term.run("ls /sys/pods").contains("Permission denied"), "the pods folder is there, and shut")
	term.run("su maint")
	_check(term.mode == "password" and term.input.secret, "su asks for a password (hidden)")
	out = term.run("letmein")
	_check(out.contains("Authentication failure") and not term.root, "a wrong password fails")
	term.run("su maint")
	var sus := Story.oversight(sim()).suspicion
	out = term.run(Story.MAINT_PASSWORD)
	_check(term.root and out.contains("Welcome back") and Story.knows(sim(), "secret:maint_account"), "the top score logs in as maint")
	_check(Story.oversight(sim()).suspicion >= sus + 9.0, "which corporate would very much like to know about")
	_check(term.prompt_label.text.begins_with("maint@corklabs"), "the prompt changes")
	_check(term.run("cat /sys/pods/manifest.txt").contains("POD MANIFEST"), "maint can read the pod manifest")
	_check(term.run("cat /home/rmarrow/README_IF_YOU_REPLACED_ME.txt").contains("su maint"), "and Marrow's home")
	out = term.run("podctl inspect 3")
	_check(out.contains("OKAFOR") and Story.knows(sim(), "secret:pod3"), "pod 3 is Okafor")
	out = term.run("auditctl list")
	_check(out.contains("maintenance account") and Story.knows(sim(), "secret:audit_trail"), "auditctl shows what corporate has on you")
	var trail: int = Story.oversight(sim()).trail.size()
	term.run("auditctl purge")
	_check(Story.oversight(sim()).trail.size() == 1 and trail > 1, "a purge empties the trail (except the gap it leaves)")
	_check(term.run("auditctl purge").contains("already"), "once a shift")
	term.run("hqctl mute 30")
	await process_frame
	_check(Story.oversight(sim()).hq_muted(sim()) and desk.hq_panel._suspended.visible, "hqctl mute suspends the corkHQ panel")
	term.run("hqctl unmute")
	await process_frame
	_check(not desk.hq_panel._suspended.visible, "and unmute brings it back")
	_check(term.run("podctl wake 3").contains("sequence unknown"), "waking a pod needs Hollis's diary")
	_check(term.run("decrypt /home/ehollis/diary.enc lantern").contains("decrypted"), "Hollis's diary opens with Ogre's word")
	term.run("cat /home/ehollis/diary.enc")
	_check(term.run("podctl wake 3").contains("refused"), "and even then, the pods stay shut (for now)")
	term.run("exit")
	_check(not term.root and not Story.knows(sim(), "root") and term.run("podctl list").contains("permission denied"), "exit leaves maint")


func _test_fired_and_retry() -> void:
	var camp := Story.campaign(sim())
	var o := Story.oversight(sim())
	var learned_before := Story.knows(sim(), "secret:pod3")
	o.fire(sim(), "misconduct", "Test dismissal.")
	facility.spend(1.0, "test")
	await process_frame
	await process_frame
	_check(camp.state == "fired" and desk.shift_screen.visible, "dismissal covers the desktop (%s)" % camp.state)
	_check(_screen_says("Test dismissal"), "and says why")
	desk.retry_shift()
	await process_frame
	await process_frame
	camp = Story.campaign(sim())
	_check(camp.state == "pre" and camp.shift == 1 and FacilitySim.format_clock(sim().time()) == "05:55", "retry goes back to the shift's brief")
	_check(learned_before and not Story.knows(sim(), "secret:pod3") and not Story.knows(sim(), "cmd:talk"), "forgetting what was found since")
	desk.clock_in()
	await process_frame
	var term = desk.open_app("terminal")
	await process_frame
	var out: String = term.run("talk tinker")
	var cams = desk._windows["cameras"].app if desk._windows.has("cameras") else null
	_check(out.contains("unit link") and cams != null and cams.talk_log.get_parsed_text().contains("TINKER:") and Story.knows(sim(), "cmd:talk"),
		"but what the PLAYER remembers still works: talk")
	if cams:
		cams.end_talk()


func _test_end() -> void:
	var camp := Story.campaign(sim())
	camp.finish(sim())
	await process_frame
	await process_frame
	_check(desk.shift_screen.visible and _screen_says("END OF THIS BUILD"), "the end of the run gets its screen")
	_check(_screen_says("FOUND THIS RUN"), "with what you found")
	desk.start_over()
	await process_frame
	await process_frame
	camp = Story.campaign(sim())
	_check(camp.state == "pre" and camp.shift == 1 and not Story.knows(sim(), "cmd:talk"), "start over: a new facility, a new supervisor")
	_check(not SupervisorArchive.summary().is_empty(), "the personnel file carries on (%s)" % SupervisorArchive.summary())


func _screen_says(text: String) -> bool:
	return desk.shift_screen.body.find_children("*", "Label", true, false).any(func(l): return l.text.contains(text))


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

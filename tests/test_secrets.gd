# Plays through the corkLabs OS like a rascal would: the Terminal (help only
# lists what you know, typing a real command teaches it), the file system,
# a conversation with Tinker, Files, Duties, Night Run and its wrong-way
# secret, the maintenance account (su maint, podctl, hqctl, auditctl), the
# end of a shift, dismissal and retrying the shift, and an ending.
extends SceneTree

const SAVE := "user://test_secrets_save.json"
const OS_SETTINGS := "user://test_secrets_os_settings.json"

var failures := 0
var facility: Node
var desk: Control


func _initialize() -> void:
	SupervisorArchive.use_file("user://test_supervisor_archive.json")   # never the real personnel file
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
	_check(desk.shift_screen.visible and _screen_says("SHIFT 1"),
		"log on shows shift 1's brief")
	_check(facility.has_checkpoint(SAVE), "the brief saves the shift's checkpoint")
	desk.clock_in()
	await process_frame
	await process_frame

	await _test_terminal()
	await _test_apps()
	await _test_bin_and_notes()
	await _test_plant_and_liaison()
	await _test_nightrun()
	await _test_maint()
	await _test_fired_and_retry()
	await _test_ending()

	desk.log_off()
	desk.free()
	facility.wipe_save(SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OS_SETTINGS))
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func sim() -> FacilitySim:
	return facility.sim


func _test_terminal() -> void:
	var term = desk.open_app("terminal")
	await process_frame
	var help: String = term.run("help")
	_check(help.contains("ls") and not help.contains("order") and not help.contains("podctl"), "help lists only what a new supervisor knows")
	_check(term.run("ls").contains("welcome.txt"), "ls in the home folder shows the onboarding file")
	var t0 := sim().time()
	var out: String = term.run("cat welcome.txt")
	_check(out.contains("WELCOME TO corkLabs") and sim().time() - t0 >= 179.0, "cat reads it, and reading takes facility time")
	_check(out.contains("new commands noted") and term.run("help").contains("order"), "what it mentions is learned (help lists 'order' now)")
	t0 = sim().time()
	term.run("cat welcome.txt")
	_check(is_equal_approx(sim().time(), t0), "reading it again is free")
	out = term.run("whoami")
	_check(out.contains("new command noted") and out.contains("probationary"), "typing a real, unlisted command works and teaches it")
	_check(term.run("xyzzy").contains("command not found"), "made-up commands don't")
	t0 = sim().time()
	out = term.run("grep lantern")
	_check(out.contains("No matches") and sim().time() - t0 >= 299.0, "grep searches what you can open (the diary's still encrypted), 5 min")
	out = term.run("grep transferred")
	_check(out.contains("/corp/memos/") and out.contains(":"), "grep finds lines across files (%d chars)" % out.length())
	_check(term.run("find memo").is_empty() == false and term.run("find transfer").contains("/corp/memos/1994-transfer-hollis.txt"), "find lists files by name")
	_check(term.run("who").contains("pell") and term.run("ps").contains("auditd"), "who and ps show who's watching")
	_check(term.run("kill 45").contains("permission denied"), "kill is for maint")
	_check(term.run("history").contains("whoami"), "history lists what you typed")
	term.run("cd /home")
	out = term.run("ls")
	_check(out.contains("dokafor/") and out.contains("rmarrow/"), "/home has the former supervisors' folders")
	term.run("cd dokafor")
	_check(not term.run("ls").contains(".pod3") and term.run("ls -a").contains(".pod3"), "ls -a shows hidden files")
	out = term.run("cat todo.txt")
	_check(out.contains("talk tinker") and Story.knows(sim(), "cmd:talk"), "Okafor's todo list teaches 'talk'")
	_check(Story.oversight(sim()).suspicion > 0.0, "and reading it was logged")
	# cp: keep a copy before the purge.
	out = term.run("cp todo.txt")
	_check(out.contains("Copied to ~/todo.txt") and Story.knows(sim(), "secret:kept"), "cp copies Okafor's todo into your home (%s)" % out.strip_edges())
	_check(term.run("ls ~").contains("todo.txt") and term.run("cp todo.txt").contains("already"), "it's in your home folder, once")
	Story.learn(sim(), "purged:dokafor")
	_check(not Story.exists(sim(), "/home/dokafor/todo.txt") and term.run("cat ~/todo.txt").contains("talk tinker"),
		"after the purge the original's gone, the copy isn't")
	Story.knowledge(sim()).forget("purged:dokafor")
	term.run("cd /home/dokafor")
	out = term.run("cat /home/ehollis/diary.enc")
	_check(out.contains("encrypted"), "the diary is encrypted")
	_check(term.run("decrypt /home/ehollis/diary.enc wrong").contains("wrong password"), "decrypt with a wrong password")
	# Talk to Tinker.
	var tinker := sim().get_system("robot_tinker") as RobotAgent
	tinker.stability = 0.5
	var stab := tinker.stability
	t0 = sim().time()
	out = term.run("talk tinker")
	_check(out.contains("TINKER:") and term.mode == "talk" and sim().time() - t0 >= 59.0, "talk opens the unit link; lines cost time")
	_check(tinker.stability > stab, "a conversation steadies the unit")
	out = term.run("2")   # "Who was here before me?"
	_check(out.contains("Okafor") and Story.knows(sim(), "asked:okafor"), "picking a reply plays on (%s)" % out.strip_edges().left(60))
	out = term.run("0")
	_check(term.mode == "" and out.contains("link closed"), "0 closes the link")
	_check(term.run("pwd").contains("/home/dokafor"), "and the shell is back")


func _test_apps() -> void:
	# Files: the same file system.
	var files = desk.open_app("files")
	await process_frame
	files.dir = "/home/rmarrow"
	files._fill_list()
	var names: Array = []
	for i in files.list.item_count:
		names.append(files.list.get_item_text(i))
	_check(names.any(func(n): return str(n).begins_with("README_IF_YOU_REPLACED_ME")), "Files lists a folder (%s)" % ", ".join(names))
	_check(not names.any(func(n): return str(n).begins_with(".plan")) , "without hidden files...")
	files.refresh()
	files.hidden_box.button_pressed = true
	files._fill_list()
	names.clear()
	for i in files.list.item_count:
		names.append(files.list.get_item_text(i))
	_check(files.hidden_box.visible and names.any(func(n): return str(n).begins_with(".plan")), "...until ls -a showed you they exist")
	files.open_file("/home/rmarrow/README_IF_YOU_REPLACED_ME.txt")
	_check(files.view.get_parsed_text().contains("su maint") and Story.knows(sim(), "cmd:su"), "opening a file reads it (and teaches)")
	# Duties.
	var duties = desk.open_app("duties")
	await process_frame
	duties.refresh()
	var camp := Story.campaign(sim())
	_check(duties.rows.get_child_count() == camp.duties.size(), "Duties lists the shift's duties")
	var t0 := sim().time()
	duties._do("coolant_walk")
	_check(camp.duty("coolant_walk").done and sim().time() - t0 >= 1799.0, "doing one from the app takes its time")
	# Units: Talk shows once you know you can.
	var units = desk.open_app("units")
	await process_frame
	units.refresh()
	_check(units.cards["tinker"].talk.visible, "Units shows Talk now that 'talk' is known")
	t0 = sim().time()
	units._diagnose("hauler")
	_check(sim().time() - t0 >= 599.0 and units.cards["hauler"].reply.text.contains("DIAG"), "Diagnose takes 10 minutes and reads the unit out")


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
	bin.empty_button.pressed.emit()
	bin._fill_list()
	_check(bin.list.item_count == 0 and Story.oversight(sim()).standing > standing and bin.empty_button.disabled,
		"emptying it deletes them for good (corporate likes a tidy terminal)")
	var notes = desk.open_app("notes")
	await process_frame
	_check(notes.edit.text.contains("already on the notepad"), "the Notes app came with someone else's notes")
	notes.edit.text += "\nmaint: top score"
	notes._dirty = 0.01
	notes._process(0.1)
	_check(str(OSSettings.get_value("notes")).contains("maint: top score"), "and keeps yours on the desk")


func _test_plant_and_liaison() -> void:
	# Plant: inspect, request maintenance, spare parts from Requisitions stock.
	var plant_app = desk.open_app("plant")
	await process_frame
	var plant := sim().get_system("plant") as FacilityPlant
	var board := sim().get_system("work") as WorkBoard
	var req := sim().get_system("requisitions") as Requisitions
	plant.device("filter_2").value = 0.8
	plant_app.selected = "filter_2"
	var t0 := sim().time()
	var text: String = load("res://game/supervisor.gd").inspect_device("filter_2")
	_check(text.contains("Bay 2 filters") and text.contains("Needs work in about") and sim().time() - t0 >= 599.0,
		"Inspect reads a device out in 10 minutes (%s)" % text.replace("\n", " / "))
	var why: String = load("res://game/supervisor.gd").request_maintenance("filter_2")
	var job := board.get_job(int(plant.device("filter_2").job))
	_check(why.is_empty() and not job.is_empty() and job.status in ["open", "claimed"], "Request maintenance posts the job before it's an alarm (%s)" % why)
	_check(not load("res://game/supervisor.gd").request_maintenance("filter_2").is_empty(), "but not twice")
	_check(load("res://game/supervisor.gd").use_part("filter_2").contains("No "), "no spare in stock, no shortcut")
	_check(Requisitions.pack_size(req.item("filter_cartridges")) == 6, "a pack of six cartridges counts as six")
	req.inventory["filter_cartridges"] = 1
	var work_before := float(job.work)
	why = load("res://game/supervisor.gd").use_part("filter_2")
	_check(why.is_empty() and float(job.work) < work_before * 0.75 and int(req.inventory["filter_cartridges"]) == 0,
		"a spare part shrinks the job (%.0f -> %.0f s of work) and leaves stock" % [work_before, float(job.work)])
	# Replying to the liaison, in the corkHQ panel.
	var panel = desk.hq_panel
	t0 = sim().time()
	panel.open_reply()
	await process_frame
	_check(panel.reply_runner != null and panel._reply_scroll.visible and sim().time() > t0, "Reply opens a conversation with Pell in the panel")
	var n: int = panel.reply_runner.choices.size()
	var door := -1
	for i in n:
		if str(panel.reply_runner.choices[i].text).contains("door"):
			door = i
	_check(door >= 0, "one of the replies asks where the door is")
	panel.choose_reply(door)
	await process_frame
	var said: bool = panel._reply_box.find_children("*", "Label", true, false).any(func(l): return l.text.contains("won't need one"))
	_check(said, "Pell answers")
	panel.choose_reply(panel.reply_runner.choices.size() - 1)
	await process_frame
	_check(panel.reply_runner == null and panel._scroll.visible, "closing the reply shows the messages again")


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
	# A normal run, crashed into a crate: costs facility time, logged once.
	var sus := Story.oversight(sim()).suspicion
	var t0 := sim().time()
	game.start_run()
	game.lane = 1
	for i in 6000:
		game.step(1.0 / 60.0, false, false)
		if game.state != "run":
			break
	_check(game.state == "crash" and sim().time() - t0 >= 599.0, "a run ends in a crash, and costs 10 facility minutes")
	_check(Story.oversight(sim()).suspicion > sus, "playing is logged (recreational software)")
	# The wrong way: push left into the NO ENTRY sign at the start.
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
	out = term.run("cat /sys/pods/manifest.txt")
	_check(out.contains("POD MANIFEST"), "maint can read the pod manifest")
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
	var o := Story.oversight(sim())
	_check(o.hq_muted(sim()) and desk.hq_panel._suspended.visible, "hqctl mute suspends the corkHQ panel")
	term.run("hqctl unmute")
	await process_frame
	_check(not desk.hq_panel._suspended.visible, "and unmute brings it back")
	var sus2 := Story.oversight(sim()).suspicion
	out = term.run("kill 45")
	_check(out.contains("restarted") and (Story.oversight(sim()).suspicion > sus2 or Story.oversight(sim()).strikes > 0), "maint can kill auditd; it comes straight back, and it's noticed")
	_unfire()   # whether that got caught is down to chance: keep the rest of the test on the same footing
	out = term.run("podctl wake 3")
	_check(out.contains("sequence unknown") and term.mode == "", "waking a pod needs Hollis's diary")
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
	var term_open: bool = desk.is_open("terminal")
	desk.retry_shift()
	await process_frame
	await process_frame
	camp = Story.campaign(sim())
	_check(camp.state == "pre" and camp.shift == 1 and FacilitySim.format_clock(sim().time()) == "05:55", "retry goes back to the shift's brief")
	_check(learned_before and not Story.knows(sim(), "secret:pod3") and not Story.knows(sim(), "cmd:talk"), "forgetting what was found since")
	_check(term_open, "(the terminal was open before)")
	desk.clock_in()
	await process_frame
	var term = desk.open_app("terminal")
	await process_frame
	var out: String = term.run("talk tinker")
	_check(out.contains("TINKER:") and Story.knows(sim(), "cmd:talk"), "but what the PLAYER remembers still works: talk")
	term.run("0")


func _test_ending() -> void:
	var camp := Story.campaign(sim())
	camp.finish(sim(), "renewed")
	await process_frame
	await process_frame
	_check(desk.shift_screen.visible and _screen_says("CONTRACT RENEWED"),
		"an ending gets its screen")
	_check(_screen_says("FOUND THIS RUN"), "with what you found")
	desk.start_over()
	await process_frame
	await process_frame
	camp = Story.campaign(sim())
	_check(camp.state == "pre" and camp.shift == 1 and not Story.knows(sim(), "cmd:talk"), "start over: a new facility, a new supervisor")
	_check(not SupervisorArchive.summary().is_empty(), "the personnel file carries on (%s)" % SupervisorArchive.summary())


func _unfire() -> void:
	var o := Story.oversight(sim())
	o.strikes = 0
	o.fired_reason = ""
	o.fired_kind = ""
	var camp := Story.campaign(sim())
	if camp.state == "fired":
		camp.state = "on_duty"


func _screen_says(text: String) -> bool:
	return desk.shift_screen.body.find_children("*", "Label", true, false).any(func(l): return l.text.contains(text))


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

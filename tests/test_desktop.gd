# Checks the corkLabs OS desktop: log on starts the facility (at the shift
# brief; clocking in starts the shift), apps open in windows, orders from the
# apps cost facility time and get answers, alarms become toasts and light the
# taskbar, there's no way to just wait, log off saves and resumes.
extends SceneTree

const SAVE := "user://test_desktop_save.json"
const OS_SETTINGS := "user://test_desktop_os_settings.json"

var failures := 0


func _initialize() -> void:
	SupervisorArchive.use_file("user://test_supervisor_archive.json")   # never the real personnel file
	var facility: Node = get_root().get_node("Facility")
	facility.seed_override = 4242   # the same facility every run (its random faults too)
	facility.wipe_save(SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OS_SETTINGS))
	OSSettings.use_file(OS_SETTINGS)
	var desk: Control = (load("res://os/desktop.tscn") as PackedScene).instantiate()
	desk.save_path = SAVE
	desk.skip_boot = true
	get_root().add_child(desk)
	await process_frame

	_check(desk.login.visible and not facility.running, "it starts at the login screen, facility closed")
	desk.log_on()
	await process_frame
	await process_frame
	_check(facility.running and not desk.login.visible, "log on opens the facility")
	_check(desk.shift_screen.blocking(), "a new facility starts at the first shift's brief, over the desktop")
	desk.clock_in()
	await process_frame
	await process_frame
	_check(not desk.shift_screen.blocking() and FacilitySim.format_clock(facility.sim.time()) == "06:00",
		"clocking in starts the shift at 06:00 (%s)" % FacilitySim.format_clock(facility.sim.time()))
	_check(desk.world != null and desk.world.cameras.size() == FacilitySetup.cameras().size(), "the 3D facility runs hidden, with its cameras")
	_check(str(desk.clock_button.text).contains(FacilitySim.format_time(facility.sim.time())), "the taskbar clock shows facility time (%s)" % desk.clock_button.text)

	_check(not desk.APPS.any(func(a): return a[0] == "units" or a[0] == "work"), "no Units or Work Orders apps: that's all in Cameras now")
	for id in ["cameras", "plant", "log", "terminal"]:
		_check(desk.open_app(id) != null and desk.is_open(id), "the %s app opens in a window" % id)
	var again: Object = desk.open_app("plant")
	_check(desk.window_layer.get_child_count() == 4 and again == desk._windows["plant"].app, "opening an open app just brings it forward")

	# On duty, a stable unit leaves a broken thing alone until you order maintenance on it.
	var cams = desk._windows["cameras"].app
	var sim: FacilitySim = facility.sim
	var board: WorkBoard = sim.get_system("work")
	var plant: FacilityPlant = sim.get_system("plant")
	plant.devices["bay_2"].job = -1
	sim.schedule_in(0.0, "plant_fault", {"device": "bay_2"})
	desk.get_node("/root/Facility").spend(600.0, "test")
	var job := board.get_job(int(plant.device("bay_2").job))
	_check(not job.is_empty() and job.status == "open" and not job.get("requested", false), "debris in bay 2: posted, but nobody goes")
	var menu: Array = load("res://os/object_menu.gd").entries(sim, "bay_2")
	var order: Array = menu.filter(func(e): return str(e.get("text", "")).begins_with("Order maintenance"))
	_check(order.size() == 1 and order[0].has("sub"), "clicking it in Cameras offers Order maintenance")
	var send: Array = load("res://os/object_menu.gd").entries(sim, "robot:tinker").filter(func(e): return str(e.get("text", "")) == "Send to a job")
	_check(send.size() == 1 and not send[0].sub.any(func(e): return e.get("disabled", false) and not e.get("label", false)),
		"a unit's Send to a job lists only jobs it can take (Tinker: %s)" % (str(send[0].sub.map(func(e): return e.text)) if send.size() == 1 else "no menu"))
	var units: Array = order[0].sub
	_check(units.size() == FacilitySetup.robots(sim).size() and str(units[0].text).contains("(best)"),
		"you pick which unit goes: every unit listed, the best free one first (%s)" % str(units.map(func(u): return u.text)))
	var ogre: Array = units.filter(func(u): return str(u.text).begins_with("Ogre"))
	_check(ogre.size() == 1 and ogre[0].disabled, "units that can't do it are greyed out, with why (%s)" % (ogre[0].text if ogre.size() == 1 else ""))
	var t0: float = sim.time()
	cams._menu_entries = [units[0].merged({"for": "bay_2"})]
	cams._on_menu(0)
	var facility_node := desk.get_node("/root/Facility")
	_check(job.get("requested", false) and cams.feedback.text.contains("on its way"), "ordering it requests the job and sends a unit (%s)" % cams.feedback.text)
	_check(sim.time() - t0 < 1.0 and facility_node.errand_running(), "no time passes when you order: the unit's errand runs instead")
	for i in 30:
		await process_frame
	_check(sim.time() > t0, "the clock runs while you watch it go")
	facility_node.finish_errands()
	_check(job.status == "done" and not facility_node.errand_running(), "and the job's done without anything else from you")
	_check(not load("res://os/object_menu.gd").describe(sim, "robot:hauler").is_empty() and load("res://os/object_menu.gd").describe(sim, "bay_2").contains("Bay 2"), "hovering shows what a thing is")

	# Break something: toast + alarm light.
	var toasts_before: int = desk.toast_box.get_child_count()
	sim.schedule_in(0.0, "plant_fault", {"device": "relay"})
	desk.get_node("/root/Facility").spend(1.0, "test")
	await process_frame
	var alarm_toast: bool = desk.toast_box.get_children().any(func(t): return t.find_children("*", "Label", true, false).any(func(l): return l.text.contains("FUSE BLOWN")))
	_check(desk.toast_box.get_child_count() > toasts_before and alarm_toast, "an alarm pops up as a toast")
	_check(desk.alarm_button.visible and desk.alarm_button.text.begins_with("ALARM"), "and lights the taskbar alarm (%s)" % desk.alarm_button.text)

	# No waiting: time moves when the supervisor does something (an inspection here).
	_check(not desk.has_method("start_wait") and not load("res://game/supervisor.gd").new().has_method("wait"), "there is no Wait")
	# Inspecting: a unit goes, looks, and reports back.
	var t1: float = sim.time()
	var r: Dictionary = load("res://game/supervisor.gd").order_inspection("filter_1")   # by path: classes that use the Facility autoload can't be named in --script tests
	var fac := desk.get_node("/root/Facility")
	fac.finish_errands()
	var plant2: FacilityPlant = sim.get_system("plant")
	var rep: Dictionary = plant2.reports.get("filter_1", {})
	_check(r.ok and not rep.is_empty() and str(rep.text).contains("Bay 1 filters") and sim.time() > t1,
		"a unit inspects a device and reports back (%s, %s)" % [r.text, str(rep.get("by", ""))])
	_check(sim.journal.tail(40).any(func(e): return e.cat == "report" and str(e.text).contains("report on Bay 1 filters")), "the report is in the Facility Log")
	# The hover card: what a thing is, at a glance.
	var om = load("res://os/object_menu.gd")
	var card_unit: Dictionary = om.info(sim, "robot:tinker")
	_check(card_unit.title == "TINKER" and (card_unit.bars as Array).size() == 3 and not (card_unit.chips as Array).is_empty(),
		"hovering a unit: a card with its state, power, stability and condition")
	var card_dev: Dictionary = om.info(sim, "pod_1")
	_check(str(card_dev.title).begins_with("POD 1") and (card_dev.bars as Array).any(func(b): return b[0] == "Sync"), "hovering a pod: its sync")
	# Pop out: a camera in a window of its own.
	cams.show_camera(2)
	cams.pop_out()
	await process_frame
	_check(desk.is_open("cam_pop_2") and desk._windows["cam_pop_2"].app.cam == 2 and desk._windows["cam_pop_2"].app.feeds.size() == 1,
		"Pop out: camera 3 in its own window")
	desk._windows["cam_pop_2"].app.show_camera(5)
	_check(desk._windows["cam_pop_2"].app.cam == 2, "and it stays on its camera")
	# A unit's request: it pings, and asks on camera when you watch its feed.
	var reqs: UnitRequests = sim.get_system("requests")
	reqs.requests.clear()
	reqs._last.clear()
	(sim.get_system("robot_hauler") as RobotAgent).wear = 0.7   # (worn: the question stands)
	for j in board.jobs:
		if str(j.source) == "service:hauler" and WorkBoard.active(j):
			board.cancel(sim, int(j.id), "test")
	var rid := reqs.ask(sim, "hauler", "service", "My joints are grinding. Book me a service?", ["Book a service", "Not now"], 1)
	cams.set_grid(true)
	cams.refresh()
	_check(cams.asking < 0 and not cams.talk_box.visible, "a request waits while you're not watching the unit")
	_check(not load("res://os/object_menu.gd").entries(sim, "robot:hauler").any(func(e): return str(e.get("text", "")).begins_with("Answer")),
		"and isn't in its click menu")
	cams.look_at_unit("hauler")
	cams.refresh()
	_check(cams.asking == rid and cams.talk_box.visible and cams.talk_choices.get_child_count() == 2, "watching its feed: it asks, answers under the picture")
	_check(desk.speech.active.has("hauler") or desk.speech._queued.has("hauler"), "out loud, on camera")
	var t2: float = sim.time()
	cams.answer_request(1)
	_check(reqs.get_request(rid).is_empty() and sim.time() - t2 >= 299.0 and not cams.talk_box.visible, "answering takes 5 minutes and closes it")
	var log_app = desk._windows["log"].app
	_check(log_app.view.get_parsed_text().contains("FUSE BLOWN"), "the Facility Log shows the journal")

	# Log off, log back on: same moment.
	var t_off: float = sim.time()
	desk.log_off()
	await process_frame
	_check(not facility.running and desk.login.visible, "log off closes the facility")
	await process_frame
	_check(desk.window_layer.get_child_count() == 0, "and its windows")
	var info: Label = desk.login.find_child("Info", true, false)
	_check(info.text.contains(FacilitySim.format_time(t_off)), "the login screen says where the facility is on hold (%s)" % info.text.split("\n")[0])
	desk.log_on()
	_check(is_equal_approx(facility.sim.time(), t_off), "log on resumes at exactly that moment")
	await process_frame
	_check(not desk.shift_screen.blocking(), "mid-shift, with no brief in the way")

	desk.log_off()
	desk.free()
	facility.wipe_save(SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OS_SETTINGS))
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

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

	for id in ["cameras", "units", "work", "plant", "log", "terminal"]:
		_check(desk.open_app(id) != null and desk.is_open(id), "the %s app opens in a window" % id)
	var again: Object = desk.open_app("work")
	_check(desk.window_layer.get_child_count() == 6 and again == desk._windows["work"].app, "opening an open app just brings it forward")

	# Assign a job from the Work Orders app.
	var work = desk._windows["work"].app
	var sim: FacilitySim = facility.sim
	var board: WorkBoard = sim.get_system("work")
	var job := board.post(sim, "Clear debris", "heavy", "bay_2", 300.0, 1, "test")
	work.selected_job = job
	var t0: float = sim.time()
	work._assign("hauler")
	_check(sim.time() - t0 >= 119.9, "an order from the Work app costs facility time")
	_check(work.reply.text.contains("Order sent to Hauler"), "and says the order went (%s)" % work.reply.text)
	_check(str(facility.sim.journal.tail(20).map(func(e): return e.text)).contains("Hauler answers"),
		"the robot's answer goes to the journal (and is spoken on camera)")

	# Break something: toast + alarm light.
	var toasts_before: int = desk.toast_box.get_child_count()
	sim.schedule_in(0.0, "plant_fault", {"device": "relay"})
	desk.get_node("/root/Facility").spend(1.0, "test")
	await process_frame
	var alarm_toast: bool = desk.toast_box.get_children().any(func(t): return t.find_children("*", "Label", true, false).any(func(l): return l.text.contains("FUSE BLOWN")))
	_check(desk.toast_box.get_child_count() > toasts_before and alarm_toast, "an alarm pops up as a toast")
	_check(desk.alarm_button.visible and desk.alarm_button.text.contains("1"), "and lights the taskbar alarm (%s)" % desk.alarm_button.text)

	# No waiting: time moves when the supervisor does something (an inspection here).
	_check(not desk.has_method("start_wait") and not load("res://game/supervisor.gd").new().has_method("wait"), "there is no Wait")
	var t1: float = sim.time()
	var text: String = load("res://game/supervisor.gd").inspect_device("filter_1")   # by path: classes that use the Facility autoload can't be named in --script tests
	await process_frame
	_check(not text.is_empty() and is_equal_approx(sim.time() - t1, 1800.0), "an inspection passes its facility time (30 min)")
	var units = desk._windows["units"].app
	_check(not str(units.cards["tinker"].think.text).is_empty(), "the Units app shows what each robot is weighing up")
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

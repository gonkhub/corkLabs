# Checks the corkLabs OS build-out: the game boots into the desktop, the
# boot screen, camera pan/tilt/zoom (free: no facility time), keys going to
# the focused app, window snapping and maximising, the window layout coming
# back at the next log on, the notification centre, pop-up settings, and the
# Terminal's commands.
extends SceneTree

const SAVE := "user://test_os_buildout_save.json"
const OS_SETTINGS := "user://test_os_buildout_settings.json"

var failures := 0
var facility: Node
var desk: Control


func _initialize() -> void:
	get_root().size = Vector2i(1600, 900)
	facility = get_root().get_node("Facility")
	facility.wipe_save(SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OS_SETTINGS))
	OSSettings.use_file(OS_SETTINGS)

	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://os/desktop.tscn", "the game boots into the corkLabs OS")
	desk = (load("res://os/desktop.tscn") as PackedScene).instantiate()
	desk.save_path = SAVE
	get_root().add_child(desk)
	await process_frame
	_check(desk.boot.visible, "it starts with the boot screen")
	for i in 5:
		await process_frame
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	_check(not desk.boot.visible and desk.login.visible, "any key skips to the login screen")
	# Headless windows are 64x64: give the desktop a real screen size to lay windows out on.
	desk.set_anchors_preset(Control.PRESET_TOP_LEFT)
	desk.size = Vector2(1600, 900)
	desk.log_on()
	await process_frame

	await _test_cameras()
	await _test_windows()
	await _test_notifications()
	await _test_terminal()
	await _test_layout_memory()

	desk.log_off()
	desk.free()
	facility.wipe_save(SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OS_SETTINGS))
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _test_cameras() -> void:
	var app = desk.open_app("cameras")
	await process_frame
	var sim: FacilitySim = facility.sim
	var t0 := sim.time()
	var cam: SecurityCamera = desk.world.cameras[0]
	var basis0 := cam.global_transform.basis
	cam.nudge(20.0, -10.0)
	cam.zoom_by(0.5)
	for i in 30:
		await process_frame
	_check(not cam.global_transform.basis.is_equal_approx(basis0) and cam.zoom_level() > 1.5,
		"the camera pans, tilts and zooms (zoom %.1fx)" % cam.zoom_level())
	cam.nudge(500.0, 500.0)
	_check(cam.pan <= cam.pan_limit_deg and cam.tilt <= cam.tilt_limit_deg, "within its motor limits")
	cam.reset_view()
	_check(cam.pan == 0.0 and cam.zoom_level() == 1.0, "reset goes back to the home view")
	var tracker: SecurityCamera = desk.world.cameras[2]
	_check(tracker.auto_track, "the Hauler camera auto-tracks by default")
	tracker.nudge(5.0, 0.0)
	_check(not tracker.auto_track, "moving it by hand takes over from auto-tracking")
	tracker.reset_view()
	_check(tracker.auto_track, "reset hands it back to auto-tracking")
	_check(sim.time() == t0, "looking around costs no facility time")

	# Keys go to the focused app.
	desk.focus_window(desk._windows["cameras"])
	_key(KEY_2)
	await process_frame
	_check(app.cam == 1, "number keys switch cameras in the focused Cameras window")
	_key(KEY_LEFT)
	await process_frame
	_check(desk.world.cameras[1].pan > 0.0, "arrow keys pan it")
	_key(KEY_G)
	await process_frame
	_check(app.grid_mode and app.feeds.size() == 4, "G shows all four feeds in a grid")
	app.feeds[3].clicked.emit(app.feeds[3])
	await process_frame
	_check(not app.grid_mode and app.cam == 3, "clicking a feed in the grid opens it")
	_check(sim.time() == t0, "still no facility time spent")


func _test_windows() -> void:
	var w = desk._windows["cameras"]
	var area: Vector2 = desk.window_layer.size
	var before := Rect2(w.position, w.size)
	desk._on_window_drag_ended(w, Vector2(2, 300))
	_check(w.position == Vector2.ZERO and is_equal_approx(w.size.x, area.x * 0.5), "dragging to the left edge snaps to the left half")
	w.restore()
	_check(Rect2(w.position, w.size) == before and not w.is_maximized(), "and restore puts it back")
	desk._on_window_drag_ended(w, Vector2(500, 1))
	_check(w.is_maximized() and w.size == area, "dragging to the top maximises")
	w.toggle_maximize()
	_check(not w.is_maximized(), "the maximise button toggles back")
	desk.open_app("units")
	desk.show_desktop()
	_check(not desk.is_open("cameras") and not desk.is_open("units"), "Show desktop minimises everything")
	desk.open_app("cameras")
	_check(desk.is_open("cameras"), "opening a minimised app brings it back")


func _test_notifications() -> void:
	var n0: int = desk.notifications.size()
	OSSettings.set_value("toast_alarm", false)
	var toasts0: int = desk.toast_box.get_child_count()
	facility.sim.schedule_in(0.0, "plant_fault", {"device": "pipe_3"})
	facility.spend(1.0, "test")
	await process_frame
	_check(desk.notifications.size() > n0, "alarms go to the notification centre")
	_check(desk.toast_box.get_child_count() == toasts0, "and don't pop up when alarm pop-ups are off")
	OSSettings.set_value("toast_alarm", true)
	desk.toggle_notice_panel()
	await process_frame
	_check(desk.notice_panel.visible and desk.notice_list.get_child_count() >= 1 and desk.unseen_notifications == 0,
		"clicking the clock opens the notification centre")
	desk.toggle_notice_panel()


func _test_terminal() -> void:
	var term = desk.open_app("terminal")
	await process_frame
	_check(term.run("help").contains("order <robot>"), "Terminal: help lists the commands")
	_check(term.run("status").contains("throughput"), "Terminal: status")
	_check(term.run("units").contains("HAULER"), "Terminal: units")
	_check(term.run("jobs").contains("Clamp coolant leak"), "Terminal: jobs shows the leak")
	var board: WorkBoard = facility.sim.get_system("work")
	var leak: int = int((facility.sim.get_system("plant") as FacilityPlant).device("pipe_3").job)
	var t0: float = facility.sim.time()
	var out: String = term.run("order hauler %d" % leak)
	_check(out.contains("Hauler:") and facility.sim.time() - t0 >= 119.9, "Terminal: order costs time and gets an answer (%s)" % out.strip_edges())
	out = term.run("order tinker %d" % leak)
	_check(out.contains("can't reach") or out.contains("already"), "Terminal: Tinker can't take Hauler's job (%s)" % out.strip_edges())
	term.run("priority %d critical" % leak)
	_check(int(board.get_job(leak).priority) == 3, "Terminal: priority")
	_check(term.run("order nobody 1").contains("No robot"), "Terminal: bad input gets a helpful error")
	_check(term.run("frobnicate").contains("Unknown command"), "Terminal: unknown commands")
	term.run("wait 5")
	_check(desk.is_waiting(), "Terminal: wait uses the taskbar wait")
	desk._end_wait("")
	_check(term.run("log 3 alarm").contains("COOLANT LEAK"), "Terminal: log with a category filter")
	term.run("open plant")
	_check(desk.is_open("plant"), "Terminal: open an app")


func _test_layout_memory() -> void:
	var cams = desk.open_app("cameras")
	cams.show_camera(2)
	var w = desk._windows["cameras"]
	w.position = Vector2(300, 120)
	w.size = Vector2(640, 420)
	desk.log_off()
	await process_frame
	await process_frame
	var saved: Dictionary = OSSettings.windows()
	_check(saved.has("cameras") and saved.cameras.open and saved.has("terminal"), "log off remembers the open windows")
	desk.log_on()
	await process_frame
	_check(desk.is_open("cameras") and desk.is_open("terminal") and desk.is_open("plant"), "log on reopens them")
	var w2 = desk._windows["cameras"]
	_check(w2.position == Vector2(300, 120) and w2.size == Vector2(640, 420), "in the same place and size (%s, %s)" % [w2.position, w2.size])
	_check(w2.app.cam == 2, "showing the same camera")
	w2.close()
	await process_frame
	_check(not OSSettings.windows().cameras.open, "a window closed by hand stays closed next time")


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

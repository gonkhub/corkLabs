# Drives the recorder scene without a headset: fakes head/hand motion,
# runs a countdown + recording, stops, and checks the take saved, baked and
# replays. (The OpenXR error printed at startup is expected here.)
extends SceneTree

var failures := 0


# _initialize runs once the scene tree is live (so the recorder's _ready runs).
func _initialize() -> void:
	var before := TakeStore.list().size()
	var rec: Node3D = (load("res://recorder/recorder.tscn") as PackedScene).instantiate()
	get_root().add_child(rec)
	await process_frame   # let _ready run
	var dt := 1.0 / 72.0

	_check(rec.robot != null, "a robot is loaded for the mirror (%s of %s)" % [rec._robot_id(), str(rec.robot_ids)])
	if rec.robot == null:
		print("1 FAILED (stopping early)")
		quit(1)
		return
	rec.play_along = true   # exercises play-along if an older take exists

	rec._toggle_recording()   # start countdown
	var t := 0.0
	var frames := 0
	while rec.state != rec.State.RECORDING and frames < 1000:
		_pose(rec, t)
		rec._process(dt)
		t += dt
		frames += 1
	_check(rec.state == rec.State.RECORDING, "countdown leads into recording")
	_check(absf(rec.calibrated_eye_height - 1.62) < 0.02, "eye height calibrated (%.3f m)" % rec.calibrated_eye_height)

	# Record ~2 seconds. Frame timing comes from the real clock, so wait a little.
	var start_ms := Time.get_ticks_msec()
	while rec.state == rec.State.RECORDING and Time.get_ticks_msec() - start_ms < 2000:
		_pose(rec, t)
		rec._process(dt)
		t += dt
		OS.delay_msec(10)
	rec._toggle_recording()   # stop
	_check(rec.state == rec.State.IDLE, "stops recording")
	_check(TakeStore.list().size() == before + 1, "take saved (%s)" % rec.last_take_path)
	_check(rec.last_take != null and rec.last_take.frame_count() > 20, "take has frames (%d)" % rec.last_take.frame_count())
	_check(rec.last_take.robot_id == rec._robot_id(), "take remembers its robot")
	var clip := Baker.clip_name_for(rec.last_take, rec.last_take_path)
	var lib := ResourceLoader.load(RobotLibrary.library_path(rec._robot_id()), "", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
	_check(lib != null and lib.has_animation(clip), "take baked into the %s library as %s" % [rec._robot_id(), clip])
	_check(rec.replay != null, "robot replays the new take")

	for i in 60:
		rec._process(dt)
	rec._on_left_button("ax_button")   # next robot
	rec._on_right_button("by_button")  # behind view
	for i in 10:
		_pose(rec, t)
		rec._process(dt)
	_check(true, "switching robot and view runs without errors")

	rec.free()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


# Fake performer: eye height 1.62 m, swaying and gesturing.
func _pose(rec: Node3D, t: float) -> void:
	rec.head.transform = Transform3D(Basis(Vector3.UP, sin(t) * 0.4), Vector3(0.03 * sin(t), 1.62, 0))
	rec.left_hand.transform = Transform3D(Basis(), Vector3(-0.3, 1.1 + 0.2 * sin(t * 3.0), -0.3))
	rec.right_hand.transform = Transform3D(Basis(Vector3.RIGHT, t), Vector3(0.3, 1.1, -0.35 - 0.1 * sin(t * 2.0)))


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

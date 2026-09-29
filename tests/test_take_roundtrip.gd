# Checks that a take survives save -> load unchanged and that playback
# reproduces the recorded frames. Runs without a headset:
#   Godot --headless --xr-mode off --path <project> --script res://tests/test_take_roundtrip.gd
extends SceneTree

var failures := 0


func _init() -> void:
	var take := PerformanceTake.new()
	take.created = "test"
	var rate := 90.0
	for i in int(30.0 * rate):   # 30 seconds at 90 Hz
		var t := i / rate
		take.append(t, _fake_frame(t))

	var path := "user://test_take.res"
	_check(ResourceSaver.save(take, path) == OK, "save")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PerformanceTake
	_check(loaded != null, "load")
	_check(loaded.frame_count() == take.frame_count(), "frame count %d" % loaded.frame_count())
	_check(is_equal_approx(loaded.duration(), take.duration()), "duration %.3f" % loaded.duration())

	# Every recorded frame must play back exactly.
	var worst := 0.0
	for i in loaded.frame_count():
		var t := loaded.sample_times[i]
		worst = maxf(worst, _error(loaded.sample(t), _fake_frame(t)))
	_check(worst < 0.001, "exact frames, worst error %.6f" % worst)

	# Halfway between frames, playback must land close to the true motion.
	worst = 0.0
	for i in loaded.frame_count() - 1:
		var t := (loaded.sample_times[i] + loaded.sample_times[i + 1]) * 0.5
		worst = maxf(worst, _error(loaded.sample(t), _fake_frame(t)))
	_check(worst < 0.005, "between frames, worst error %.6f" % worst)

	_check(loaded.sample(-5.0) != null and loaded.sample(999.0) != null, "out-of-range times")

	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


# Smooth fake motion: head sways and turns, hands circle, triggers pulse.
func _fake_frame(t: float) -> PerformanceFrame:
	var f := PerformanceFrame.new()
	f.head = Transform3D(Basis(Vector3.UP, sin(t) * 0.8), Vector3(sin(t * 0.5) * 0.2, 1.7, 0))
	f.left = Transform3D(Basis(Vector3.RIGHT, t), Vector3(-0.3 + cos(t) * 0.2, 1.2 + sin(t) * 0.2, -0.3))
	f.right = Transform3D(Basis(Vector3.FORWARD, t * 0.7), Vector3(0.3, 1.2 + cos(t) * 0.1, -0.4))
	f.left_trigger = (sin(t * 2.0) + 1.0) * 0.5
	f.right_grip = (cos(t) + 1.0) * 0.5
	f.right_stick = Vector2(sin(t), cos(t)) * 0.9
	f.left_buttons = PerformanceFrame.BTN_AX if int(t) % 2 == 0 else 0
	f.left_confidence = 2
	return f


func _error(a: PerformanceFrame, b: PerformanceFrame) -> float:
	var e := 0.0
	for pair in [[a.head, b.head], [a.left, b.left], [a.right, b.right]]:
		var x: Transform3D = pair[0]
		var y: Transform3D = pair[1]
		e = maxf(e, x.origin.distance_to(y.origin))
		e = maxf(e, x.basis.get_rotation_quaternion().angle_to(y.basis.get_rotation_quaternion()))
	e = maxf(e, absf(a.left_trigger - b.left_trigger))
	e = maxf(e, absf(a.right_grip - b.right_grip))
	e = maxf(e, a.right_stick.distance_to(b.right_stick))
	return e


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

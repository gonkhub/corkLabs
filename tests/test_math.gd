# Checks the spring follower, 1-euro filter and frame mirroring/blending.
extends SceneTree

var failures := 0


func _init() -> void:
	_test_spring()
	_test_quat_spring()
	_test_one_euro()
	_test_mirror_and_blend()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _test_spring() -> void:
	var dt := 1.0 / 90.0
	# Critically damped: reaches the target without overshooting.
	var s := SecondOrder.new(3.0, 1.0, 0.0)
	s.reset_float(0.0)
	var peak := 0.0
	var y := 0.0
	for i in 270:   # 3 seconds
		y = s.update_float(dt, 1.0)
		peak = maxf(peak, y)
	_check(absf(y - 1.0) < 0.01, "critically damped spring settles (%.4f)" % y)
	_check(peak < 1.01, "critically damped spring doesn't overshoot (peak %.4f)" % peak)

	# Underdamped: overshoots, then settles.
	s = SecondOrder.new(2.0, 0.4, 0.0)
	s.reset_float(0.0)
	peak = 0.0
	for i in 540:
		y = s.update_float(dt, 1.0)
		peak = maxf(peak, y)
	_check(peak > 1.1, "underdamped spring overshoots (peak %.3f)" % peak)
	_check(absf(y - 1.0) < 0.02, "underdamped spring settles (%.4f)" % y)

	# Passthrough.
	s = SecondOrder.new(SecondOrder.PASSTHROUGH_HZ, 1.0, 0.0)
	s.reset_vec3(Vector3.ZERO)
	var v := s.update_vec3(dt, Vector3(1, 2, 3))
	_check(v.is_equal_approx(Vector3(1, 2, 3)), "passthrough spring returns target")

	# Stable with long frames (a dropped-frame hitch).
	s = SecondOrder.new(8.0, 0.5, 2.0)
	s.reset_float(0.0)
	for i in 50:
		y = s.update_float(0.2, 1.0)
	_check(is_finite(y) and absf(y) < 10.0, "spring stays stable with 0.2 s frames (%.3f)" % y)


func _test_quat_spring() -> void:
	var dt := 1.0 / 90.0
	var target := Quaternion(Vector3.UP, 2.5)
	var s := SecondOrder.new(3.0, 1.0, 0.0)
	s.reset_quat(Quaternion.IDENTITY)
	var q := Quaternion.IDENTITY
	for i in 270:
		# Feed the target with alternating sign: must not matter.
		q = s.update_quat(dt, target if i % 2 == 0 else -target)
	_check(q.angle_to(target) < 0.01, "rotation spring settles on target (%.4f rad off)" % q.angle_to(target))


func _test_one_euro() -> void:
	var dt := 1.0 / 90.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# Still hand with 2 mm jitter: output jitter should shrink a lot.
	var f := OneEuroFilter.new(1.5, 1.5)
	var raw_var := 0.0
	var out_var := 0.0
	for i in 900:
		var noise := rng.randfn(0.0, 0.002)
		var o := f.filter(Vector4(noise, 0, 0, 0), dt)
		if i > 90:
			raw_var += noise * noise
			out_var += o.x * o.x
	_check(out_var < raw_var * 0.25, "1-euro cuts jitter (%.1f%% of raw power left)" % (100.0 * out_var / raw_var))

	# Fast sweep: lag must stay small.
	f = OneEuroFilter.new(1.5, 1.5)
	var lag := 0.0
	for i in 180:
		var x := i * dt * 2.0   # 2 m/s
		var o := f.filter(Vector4(x, 0, 0, 0), dt)
		if i > 30:
			lag = maxf(lag, x - o.x)
	_check(lag < 0.05, "1-euro lags < 5 cm on a 2 m/s sweep (%.3f m)" % lag)


func _test_mirror_and_blend() -> void:
	var f := PerformanceFrame.new()
	f.head = Transform3D(Basis(Vector3(0.3, 1, 0.2).normalized(), 0.7), Vector3(0.1, 1.7, -0.05))
	f.left = Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(-0.3, 1.2, -0.3))
	f.right = Transform3D(Basis(Vector3.UP, -0.6), Vector3(0.35, 1.1, -0.4))
	f.left_trigger = 0.2
	f.right_trigger = 0.9

	var m := f.mirrored()
	# Right hand at x = +0.35 becomes the mirror's LEFT hand, on the left side (x = -0.35).
	_check(is_equal_approx(m.left.origin.x, -0.35) and is_equal_approx(m.left_trigger, 0.9),
		"mirror swaps hands and flips x")
	var mm := m.mirrored()
	var same := mm.head.is_equal_approx(f.head) and mm.left.is_equal_approx(f.left) and mm.right.is_equal_approx(f.right)
	_check(same, "mirroring twice gives the original")
	# A reflection must keep the rotation a proper rotation (no flipped handedness).
	_check(m.head.basis.determinant() > 0.99, "mirrored rotation is a valid rotation")

	var g := PerformanceFrame.new()
	g.left_trigger = 1.0
	var b := PerformanceFrame.blend(f, g, 0.0)
	_check(b.head.is_equal_approx(f.head), "blend at 0 = first frame")
	b = PerformanceFrame.blend(f, g, 0.5)
	_check(is_equal_approx(b.left_trigger, 0.6), "blend halfway mixes triggers")


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

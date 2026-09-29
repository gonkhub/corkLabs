# Checks TakeCleanup: smoothing, gap repair, trimming, deadzones, loop closing.
extends SceneTree

var failures := 0


func _init() -> void:
	_test_smoothing()
	_test_gap_repair()
	_test_stop_trim()
	_test_deadzones()
	_test_loop()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


static func _still(_t: float) -> PerformanceFrame:
	var f := PerformanceFrame.new()
	f.head = Transform3D(Basis(), Vector3(0, 1.65, 0))
	f.left = Transform3D(Basis(), Vector3(-0.3, 1.1, -0.3))
	f.right = Transform3D(Basis(), Vector3(0.3, 1.1, -0.3))
	return f


static func _sway(t: float) -> PerformanceFrame:
	var f := _still(t)
	f.right.origin.x = 0.3 + 0.2 * sin(t * TAU / 2.0)   # 2 s period
	return f


func _test_smoothing() -> void:
	var take := FakePerformance.build(_still, 5.0, 0.003)
	var raw_jitter := _jitter(TakeCleanup.resample(take, 90.0))
	var recipe := CleanupRecipe.new()
	recipe.smoothing = 0.03
	recipe.trim_stop_reach = false
	var clean: PerformanceTake = TakeCleanup.run(take, recipe).take
	var clean_jitter := _jitter(TakeCleanup.resample(clean, 90.0))
	_check(clean_jitter < raw_jitter * 0.3, "smoothing cuts jitter: %.2f mm -> %.2f mm" % [raw_jitter * 1000, clean_jitter * 1000])

	# Zero lag: the smoothed sway peaks at the same time as the real one.
	take = FakePerformance.build(_sway, 6.0)
	clean = TakeCleanup.run(take, recipe).take
	var peak_t := 0.0
	var peak := -INF
	for i in clean.frame_count():
		var x := clean.sample(clean.sample_times[i]).right.origin.x
		if clean.sample_times[i] > 2.0 and clean.sample_times[i] < 4.0 and x > peak:
			peak = x
			peak_t = clean.sample_times[i]
	_check(absf(peak_t - 2.5) < 0.02, "smoothing adds no lag (peak at %.3f s, expected 2.5)" % peak_t)


# Average frame-to-frame movement of the right hand.
func _jitter(frames: Array[PerformanceFrame]) -> float:
	var total := 0.0
	for i in range(1, frames.size()):
		total += frames[i].right.origin.distance_to(frames[i - 1].right.origin)
	return total / (frames.size() - 1)


func _test_gap_repair() -> void:
	var take := FakePerformance.build(_sway, 6.0)
	# Knock out 0.2 s of right-hand tracking (frozen, like a real dropout),
	# and 1 s of left-hand tracking (too long to repair).
	var frozen := PackedFloat32Array()
	for i in take.frame_count():
		var t := take.sample_times[i]
		if t >= 1.0 and t < 1.2:
			if frozen.is_empty():
				frozen = take.right_track.slice(i * PerformanceTake.STRIDE, (i + 1) * PerformanceTake.STRIDE)
			take.right_confidence[i] = 0
			for k in 7:
				take.right_track[i * PerformanceTake.STRIDE + k] = frozen[k]
		if t >= 3.0 and t < 4.0:
			take.left_confidence[i] = 0
	var recipe := CleanupRecipe.new()
	recipe.smoothing = 0.0
	recipe.trim_stop_reach = false
	var result := TakeCleanup.run(take, recipe)
	var clean: PerformanceTake = result.take
	var report: Dictionary = result.report
	_check(report.gaps_repaired == 1, "one short gap repaired (%d)" % report.gaps_repaired)
	_check(report.gaps_left.size() == 1, "one long gap reported: %s" % str(report.gaps_left))
	var mid := clean.sample(1.1).right.origin.x
	var truth := _sway(1.1).right.origin.x
	_check(absf(mid - truth) < 0.03, "repaired pose follows the motion (%.3f vs %.3f)" % [mid, truth])


func _test_stop_trim() -> void:
	var take := FakePerformance.build(_still, 5.0)
	for i in take.frame_count():
		if take.sample_times[i] > 4.7:
			take.left_buttons[i] = PerformanceFrame.BTN_MENU
	var clean: PerformanceTake = TakeCleanup.run(take, CleanupRecipe.new()).take
	_check(absf(clean.duration() - 4.1) < 0.05, "stop reach trimmed (%.2f s, expected ~4.1)" % clean.duration())


static func _drifty(t: float) -> PerformanceFrame:
	var f := _still(t)
	f.left_stick = Vector2(0.05, 0.05)
	f.right_stick = Vector2(1.0, 0.0)
	f.right_trigger = 0.02
	return f


func _test_deadzones() -> void:
	var take := FakePerformance.build(_drifty, 1.0)
	var clean: PerformanceTake = TakeCleanup.run(take, CleanupRecipe.new()).take
	var f := clean.sample(0.5)
	_check(f.left_stick == Vector2.ZERO, "small stick drift removed")
	_check(is_equal_approx(f.right_stick.x, 1.0), "full stick stays full")
	_check(f.right_trigger == 0.0, "resting trigger reads 0")


func _test_loop() -> void:
	var take := FakePerformance.build(_sway, 7.3)
	var recipe := CleanupRecipe.new()
	recipe.loop = true
	recipe.smoothing = 0.0
	recipe.trim_stop_reach = false
	var result := TakeCleanup.run(take, recipe)
	var clean: PerformanceTake = result.take
	var n := clean.frame_count()
	# The seam: last frame -> first frame must look like any ordinary step.
	var seam := clean.sample(clean.sample_times[n - 1]).right.origin.distance_to(clean.sample(0.0).right.origin)
	var step := clean.sample(clean.sample_times[1]).right.origin.distance_to(clean.sample(0.0).right.origin)
	_check(seam < 0.02, "loop seam is small (%.4f m; normal step %.4f m)" % [seam, step])
	var cycles := (clean.duration() + 1.0 / 90.0) / 2.0
	_check(absf(cycles - round(cycles)) < 0.05, "loop length is a whole number of sways (%.2f cycles)" % cycles)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

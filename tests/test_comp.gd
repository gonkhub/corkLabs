# Checks take comping (punch-in).
extends SceneTree

var failures := 0


func _init() -> void:
	var base := FakePerformance.build(FakePerformance.idle, 6.0)
	var over := FakePerformance.build(FakePerformance.wave, 3.0)
	var out := TakeComp.comp(base, over, PackedStringArray(["left", "face"]), 1.0, 3.5, 0.2, 1.0)

	_check(absf(out.duration() - base.duration()) < 0.02, "comp keeps the base length (%.2f s)" % out.duration())
	# Before the punch: all base.
	var f := out.sample(0.5)
	_check(f.left.origin.distance_to(base.sample(0.5).left.origin) < 0.002, "before punch-in = base")
	# Inside: left hand + face from the overlay (offset by 1 s), head still base.
	f = out.sample(2.0)
	var o := over.sample(1.0)
	_check(f.left.origin.distance_to(o.left.origin) < 0.002, "inside: left hand from the new take")
	_check(f.right_stick.distance_to(o.right_stick) < 0.01, "inside: face from the new take")
	_check(f.head.origin.distance_to(base.sample(2.0).head.origin) < 0.002, "inside: head still from the base take")
	# Crossfade is smooth: no jump bigger than a few mm between frames.
	var worst := 0.0
	for i in range(1, out.frame_count()):
		var a := out.sample(out.sample_times[i - 1]).left.origin
		var b := out.sample(out.sample_times[i]).left.origin
		worst = maxf(worst, a.distance_to(b))
	# Compare with the fastest the source motion itself moves per frame.
	var natural := 0.0
	for src in [base, over]:
		for i in range(1, src.frame_count()):
			natural = maxf(natural, src.sample(src.sample_times[i - 1]).left.origin.distance_to(src.sample(src.sample_times[i]).left.origin))
	_check(worst < natural * 1.5 + 0.01, "no pops at the punch points (largest step %.4f m; source motion's largest %.4f m)" % [worst, natural])
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

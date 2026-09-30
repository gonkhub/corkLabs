# Procedural "performances" for testing the pipeline and making demo clips
# without a headset. Motion is deliberately human-ish: breathing sway,
# glances, gestures, trigger squeezes.
class_name FakePerformance
extends RefCounted

const EYE_HEIGHT := 1.65


# Builds a take by calling `motion` (a Callable taking t -> PerformanceFrame)
# at an uneven rate around 90 Hz, like a real headset would.
static func build(motion: Callable, seconds: float, jitter_m := 0.0, seed := 1) -> PerformanceTake:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var take := PerformanceTake.new()
	take.created = "procedural"
	take.eye_height = EYE_HEIGHT
	var t := 0.0
	while t <= seconds:
		var f: PerformanceFrame = motion.call(t)
		if jitter_m > 0.0:
			f.head.origin += _noise(rng, jitter_m * 0.5)
			f.left.origin += _noise(rng, jitter_m)
			f.right.origin += _noise(rng, jitter_m)
		f.left_confidence = 2
		f.right_confidence = 2
		take.append(t, f)
		t += 1.0 / 90.0 + rng.randf_range(-0.0015, 0.0015)
	return take


static func _noise(rng: RandomNumberGenerator, s: float) -> Vector3:
	return Vector3(rng.randfn(0, s), rng.randfn(0, s), rng.randfn(0, s))


static func _head(pos: Vector3, yaw: float, pitch: float, roll := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	return Transform3D(b, pos)


# Hands held as if holding controllers, pointing forward and a little down.
static func _hand(pos: Vector3, yaw := 0.0, pitch := -0.3, roll := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	return Transform3D(b, pos)


# --- Motions ---------------------------------------------------------------

# Standing idle: breathing, weight shifts, slow glances. Loops well-ish.
static func idle(t: float) -> PerformanceFrame:
	var f := PerformanceFrame.new()
	var breathe := sin(t * TAU / 4.0)
	var shift := sin(t * TAU / 9.0)
	var glance := sin(t * TAU / 6.0) * 0.5 + sin(t * TAU / 2.3) * 0.1
	f.head = _head(Vector3(shift * 0.04, EYE_HEIGHT + breathe * 0.008, 0.0), glance * 0.7, -0.1 + breathe * 0.03)
	f.left = _hand(Vector3(-0.25 + shift * 0.03, 1.05 + breathe * 0.01, -0.2), 0.1)
	f.right = _hand(Vector3(0.25 + shift * 0.03, 1.05 + breathe * 0.01, -0.2), -0.1)
	f.left_trigger = 0.15 + 0.1 * maxf(0.0, sin(t * TAU / 3.0))
	f.right_trigger = 0.15
	f.left_stick = Vector2(0.0, -0.2 * maxf(0.0, sin(t * TAU / 5.0 + 1.0)))
	return f


# Looks at something to the right, reaches out, squeezes the claw, pulls back.
static func reach_and_grab(t: float) -> PerformanceFrame:
	var f := idle(t * 0.5)
	var phase := clampf(t / 3.0, 0.0, 1.0)            # 0..1 over 3 s
	var reach := sin(phase * PI)                       # out and back
	var look := smoothstep(0.0, 0.3, phase) * (1.0 - smoothstep(0.8, 1.0, phase))
	f.head = _head(Vector3(0.05 * reach, EYE_HEIGHT - 0.05 * reach, -0.05 * reach), -0.6 * look, -0.35 * look)
	f.right = _hand(Vector3(0.25 + 0.3 * reach, 1.05 + 0.1 * reach, -0.2 - 0.35 * reach), -0.5 * reach, -0.3 - 0.4 * reach)
	var grip_window := smoothstep(0.4, 0.5, phase) * (1.0 - smoothstep(0.75, 0.85, phase))
	f.right_trigger = grip_window
	f.right_grip = grip_window * 0.6
	f.left_buttons = PerformanceFrame.BTN_AX if phase > 0.45 and phase < 0.5 else 0   # blink as it grabs
	return f


# An excited wave with the left hand plus a curious head tilt.
static func wave(t: float) -> PerformanceFrame:
	var f := idle(t)
	var up := smoothstep(0.0, 0.4, t) * (1.0 - smoothstep(2.2, 2.6, t))
	var wag := sin(t * TAU * 2.2) * up
	f.head.basis = Basis(Vector3.BACK, 0.25 * up) * f.head.basis
	f.left = _hand(Vector3(-0.35 - 0.1 * up, 1.05 + 0.65 * up, -0.2 - 0.1 * up), 0.3 * up, -0.3 + 1.6 * up, wag * 0.6)
	f.left_trigger = 0.0
	f.right_stick = Vector2(0.0, 0.7 * up)   # eyes wide
	f.right_buttons = PerformanceFrame.BTN_BY if t > 1.0 and t < 1.15 else 0   # glow flash
	return f


# A crane lift (for Ogre): reach out, pay out cable with the left trigger,
# grab with the right trigger, hoist, swing the load across, lower it, let go.
static func crane_lift(t: float) -> PerformanceFrame:
	var f := idle(t * 0.5)
	var out := smoothstep(0.0, 1.5, t) * (1.0 - smoothstep(6.0, 7.0, t))   # arm out and back
	var across := smoothstep(3.6, 5.0, t) * (1.0 - smoothstep(6.0, 7.0, t))  # swing the load left
	var lower := smoothstep(1.0, 2.0, t) - 0.7 * smoothstep(2.6, 3.6, t) + 0.6 * smoothstep(5.0, 5.6, t) - 0.9 * smoothstep(6.0, 6.8, t)
	var grab := smoothstep(2.0, 2.6, t) * (1.0 - smoothstep(5.6, 6.0, t))
	f.head = _head(Vector3(0.0, EYE_HEIGHT, 0.0), -0.4 * out + 0.6 * across, -0.3 * out)
	f.right = _hand(Vector3(0.25 + 0.2 * out - 0.4 * across, 1.05 - 0.05 * out, -0.2 - 0.3 * out), 0.5 * across, -0.3)
	f.left_trigger = clampf(lower, 0.0, 1.0)
	f.right_trigger = grab
	f.right_grip = grab * 0.8
	return f

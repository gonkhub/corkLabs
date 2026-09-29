# Checks the robot rigs (IK reaches its targets, claws respond) and that a
# baked animation replays exactly what the rig did.
extends SceneTree

var failures := 0


func _init() -> void:
	_check(RobotLibrary.ids().has("tinker") and RobotLibrary.ids().has("hauler"),
		"robot library finds tinker and hauler (%s)" % str(RobotLibrary.ids()))
	_test_ik("hauler", "Body/ShoulderR/Upper/Fore/Wrist", Vector3(0.1, -0.4, -0.3))
	_test_ik("tinker", "Core/ArmR/Wrist", Vector3(0.15, -0.3, -0.25))
	_test_claw()
	for id in ["tinker", "hauler"]:
		_test_bake_matches_rig(id)
	_test_loop_bake()
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


# A profile with every spring switched off, so poses are exact.
func _stiff(rig: RobotRig) -> void:
	var p: RobotProfile = rig.profile.duplicate()
	for key in ["body", "head", "eye", "hand", "tool"]:
		p.set(key + "_frequency", SecondOrder.PASSTHROUGH_HZ)
	p.amplitude = 1.0
	rig.profile = p


func _frame_with_right_hand(rel: Vector3) -> PerformanceFrame:
	var f := PerformanceFrame.new()
	f.head = Transform3D(Basis(), Vector3(0, 1.65, 0))
	f.left = Transform3D(Basis(), Vector3(-0.25, 1.05, -0.2))
	f.right = Transform3D(Basis(), f.head.origin + rel)
	return f


func _test_ik(id: String, wrist_path: String, rel: Vector3) -> void:
	var rig := RobotLibrary.instantiate(id)
	_stiff(rig)
	rig.begin(1.65)
	var f := _frame_with_right_hand(rel)
	rig.drive(f, 1.0 / 30.0)
	rig.drive(f, 1.0 / 30.0)
	var wrist := rig.rig_xform(rig.get_node(wrist_path)).origin
	var anchor: Vector3
	if id == "hauler":
		anchor = rig.rig_xform(rig.get_node("Body/Neck")).origin
	else:
		anchor = rig.get_node("Core").position
	var target := anchor + rel * rig.profile.reach_scale
	var err := wrist.distance_to(target)
	_check(err < 0.002, "%s wrist reaches its IK target (off by %.4f m)" % [id, err])
	# Wrist copies the controller's rotation.
	var hand_rot := Quaternion(Vector3.RIGHT, 0.7)
	f.right.basis = Basis(hand_rot)
	rig.drive(f, 1.0 / 30.0)
	var wq := rig.rig_xform(rig.get_node(wrist_path)).basis.get_rotation_quaternion()
	if id == "tinker":
		wq = wq * Quaternion(Vector3.FORWARD, 0.0)   # no grip spin at grip 0
	_check(wq.angle_to(hand_rot) < 0.01, "%s wrist copies the controller rotation (%.4f rad off)" % [id, wq.angle_to(hand_rot)])
	rig.free()


func _test_claw() -> void:
	var rig := RobotLibrary.instantiate("tinker")
	_stiff(rig)
	rig.begin(1.65)
	var f := _frame_with_right_hand(Vector3(0.1, -0.3, -0.25))
	rig.drive(f, 1.0 / 30.0)
	var open: float = rig.get_node("Core/ArmR/Wrist/ClawA").rotation.x
	f.right_trigger = 1.0
	rig.drive(f, 1.0 / 30.0)
	var closed: float = rig.get_node("Core/ArmR/Wrist/ClawA").rotation.x
	_check(open > 0.4 and absf(closed) < 0.01, "trigger closes the claw (%.2f -> %.2f rad)" % [open, closed])
	rig.free()


# Bake a take, then play the clip on a fresh robot and compare against the
# rig driven directly: they must match.
func _test_bake_matches_rig(id: String) -> void:
	var take := FakePerformance.build(FakePerformance.reach_and_grab, 3.0, 0.002)
	var recipe := CleanupRecipe.new()
	recipe.trim_stop_reach = false
	take.recipe = recipe

	var baker_rig := RobotLibrary.instantiate(id)
	var result := Baker.bake(take, baker_rig, recipe)
	var anim: Animation = result.animation
	var report: Dictionary = result.report
	var retime: float = baker_rig.profile.retime
	baker_rig.free()
	_check(absf(anim.length - 3.0 * retime) < 0.05, "%s clip length %.2f s (retime %.2f)" % [id, anim.length, retime])
	_check(report.tracks > 10, "%s clip has %d tracks" % [id, report.tracks])

	# Reference: drive a rig by hand through the same cleaned frames.
	var clean: PerformanceTake = TakeCleanup.run(take, recipe, Baker.CLEAN_RATE).take
	var ref := RobotLibrary.instantiate(id)
	ref.begin(take.eye_height)
	var check_frame := 45   # 1.5 s at 30 fps
	for i in check_frame + 1:
		ref.drive(clean.sample(i / 30.0), 1.0 / 30.0)

	var actor := RobotLibrary.instantiate(id)
	get_root().add_child(actor)
	var player := AnimationPlayer.new()
	actor.add_child(player)
	var lib := AnimationLibrary.new()
	lib.add_animation("clip", anim)
	player.add_animation_library("", lib)
	player.play("clip")
	player.seek(check_frame / 30.0 * retime, true)

	var worst := 0.0
	for n in ref.baked_nodes():
		var path := Baker.node_path(ref, n)
		var a := ref.rig_xform(n)
		var b := actor.rig_xform(actor.get_node(path))
		worst = maxf(worst, a.origin.distance_to(b.origin))
	_check(worst < 0.001, "%s baked clip matches the rig (worst joint off by %.5f m)" % [id, worst])
	ref.free()
	actor.free()


func _test_loop_bake() -> void:
	var take := FakePerformance.build(FakePerformance.idle, 12.5)
	var recipe := CleanupRecipe.new()
	recipe.loop = true
	recipe.trim_stop_reach = false
	take.recipe = recipe
	var rig := RobotLibrary.instantiate("hauler")
	var result := Baker.bake(take, rig, recipe)
	rig.free()
	var anim: Animation = result.animation
	_check(anim.loop_mode == Animation.LOOP_LINEAR, "idle clip loops")
	# The seam: interpolating from the last key back to the first must be a
	# small step, like any other frame step.
	var body_track := anim.find_track(NodePath("Body"), Animation.TYPE_POSITION_3D)
	var n := anim.track_get_key_count(body_track)
	var seam := (anim.track_get_key_value(body_track, n - 1) as Vector3).distance_to(anim.track_get_key_value(body_track, 0))
	var biggest_step := 0.0
	for i in range(1, n):
		biggest_step = maxf(biggest_step, (anim.track_get_key_value(body_track, i) as Vector3).distance_to(anim.track_get_key_value(body_track, i - 1)))
	_check(seam <= biggest_step * 1.5 + 0.0005, "loop seam %.4f m vs largest normal step %.4f m" % [seam, biggest_step])


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

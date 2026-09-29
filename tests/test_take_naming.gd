# Checks naming new takes: clip names, file moves, discards, library updates,
# punch-in sources following their comp, and references being kept.
extends SceneTree

var failures := 0


func _init() -> void:
	TakeStore.takes_dir = "user://test_naming_takes"
	RobotLibrary.animations_dir = "user://test_naming_animations"
	for dir in [TakeStore.takes_dir, RobotLibrary.animations_dir]:
		_wipe(ProjectSettings.globalize_path(dir))

	_check(TakeNaming.make_clip_name("idle", "Scan the Room!") == "idle_scan_the_room", "names are cleaned to snake_case")
	_check(TakeNaming.make_clip_name("act", "act_weld") == "act_weld", "type prefix isn't doubled")
	_check(TakeNaming.make_clip_name("", "  ") == "", "blank names are rejected")

	# Three freshly recorded takes (timestamp names, no clip names) + a punch-in.
	var a := _record("tinker", "take_2026-09-29T10-00-00.res", FakePerformance.idle, "2026-09-29T10:00:00")
	var b := _record("tinker", "take_2026-09-29T10-01-00.res", FakePerformance.wave, "2026-09-29T10:01:00")
	var c := _record("hauler", "take_2026-09-29T10-02-00.res", FakePerformance.reach_and_grab, "2026-09-29T10:02:00")
	var src := _record("", "take_2026-09-29T10-03-00.res", FakePerformance.wave, "2026-09-29T10:03:00")
	var comp_take := TakeComp.comp(TakeStore.load_take(a), TakeStore.load_take(src), PackedStringArray(["right"]))
	comp_take.overdub_of = PackedStringArray([a, src])
	var comp := TakeStore.takes_dir.path_join("take_2026-09-29T10-03-00_punch_right.res")
	comp_take.created = "2026-09-29T10:03:00"
	TakeStore.save(comp_take, comp)
	for p in [a, b, c, comp]:
		Baker.bake_to_library(TakeStore.load_take(p), p, TakeStore.load_take(p).robot_id)

	var unnamed := TakeNaming.unnamed_takes()
	_check(unnamed.size() == 4 and not unnamed.has(src), "4 unnamed takes found, raw punch source not listed (%d)" % unnamed.size())
	_check(TakeStore.newest() == comp, "newest take found by recording time")

	var lines := TakeNaming.apply([
		{"path": src, "action": "keep", "type": "act", "name": "oops"},   # must be skipped
		{"path": a, "action": "keep", "type": "idle", "name": "scan"},
		{"path": b, "action": "discard"},
		{"path": c, "action": "keep", "type": "act", "name": "Lift Crate", "loop": false},
		{"path": comp, "action": "keep", "type": "idle", "name": "scan"},   # same name -> idle_scan_2
	])
	for l in lines:
		print("      " + l)

	_check(lines[0].begins_with("SKIP") and not FileAccess.file_exists(TakeStore.takes_dir.path_join("act_oops.res")),
		"raw punch-in recording is skipped, not renamed on its own")
	var scan := TakeStore.takes_dir.path_join("tinker/idle_scan.res")
	var scan2 := TakeStore.takes_dir.path_join("tinker/idle_scan_2.res")
	var lift := TakeStore.takes_dir.path_join("hauler/act_lift_crate.res")
	_check(FileAccess.file_exists(scan) and not FileAccess.file_exists(a), "take moved to takes/tinker/idle_scan.res")
	_check(FileAccess.file_exists(lift), "hauler take moved to takes/hauler/act_lift_crate.res")
	_check(FileAccess.file_exists(scan2), "duplicate name gets _2 (idle_scan_2)")
	_check(not FileAccess.file_exists(b) and FileAccess.file_exists(TakeStore.takes_dir.path_join("_discarded/" + b.get_file())),
		"discarded take moved to _discarded, not deleted")

	var t := TakeStore.load_take(scan)
	_check(t.clip_name == "idle_scan" and t.recipe.loop, "idle take named and set to loop")
	_check(not TakeStore.load_take(lift).recipe.loop, "action take doesn't loop")

	var tinker_lib := ResourceLoader.load(RobotLibrary.library_path("tinker"), "", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
	var hauler_lib := ResourceLoader.load(RobotLibrary.library_path("hauler"), "", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
	_check(tinker_lib.has_animation("idle_scan") and tinker_lib.has_animation("idle_scan_2"), "clips baked under their new names")
	_check(tinker_lib.get_animation("idle_scan").loop_mode == Animation.LOOP_LINEAR, "idle clip loops")
	_check(not tinker_lib.has_animation("take_2026-09-29T10-00-00") and not tinker_lib.has_animation("take_2026-09-29T10-01-00"),
		"old timestamp clips removed from the library (%s)" % str(tinker_lib.get_animation_list()))
	_check(hauler_lib.has_animation("act_lift_crate"), "hauler library has act_lift_crate")
	_check(not FileAccess.file_exists(RobotLibrary.animation_dir("tinker").path_join("take_2026-09-29T10-00-00.res")),
		"old clip file removed")

	var c2 := TakeStore.load_take(scan2)
	_check(c2.overdub_of[0] == scan, "comp's link to its base take follows the rename")
	_check(c2.overdub_of[1].contains("tinker/sources/idle_scan_2_punch_source") and FileAccess.file_exists(c2.overdub_of[1]),
		"punch-in source moved next to its comp (%s)" % c2.overdub_of[1])
	_check(TakeNaming.unnamed_takes().is_empty(), "nothing left unnamed")

	# Discarding a punch-in comp also discards its raw punch recording.
	var src2 := _record("", "take_2026-09-29T11-00-00.res", FakePerformance.wave, "2026-09-29T11:00:00")
	var comp2_take := TakeComp.comp(TakeStore.load_take(scan), TakeStore.load_take(src2), PackedStringArray(["left"]))
	comp2_take.overdub_of = PackedStringArray([scan, src2])
	var comp2 := TakeStore.takes_dir.path_join("take_2026-09-29T11-00-00_punch_left.res")
	TakeStore.save(comp2_take, comp2)
	TakeNaming.apply([{"path": comp2, "action": "discard"}])
	_check(not FileAccess.file_exists(src2) and FileAccess.file_exists(TakeStore.takes_dir.path_join("_discarded/" + src2.get_file())),
		"discarding a comp moves its raw punch recording to _discarded too")

	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _record(robot: String, file: String, motion: Callable, created: String) -> String:
	var take := FakePerformance.build(motion, 2.0)
	take.robot_id = robot
	take.created = created
	var path := TakeStore.takes_dir.path_join(file)
	TakeStore.save(take, path)
	return path


static func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_wipe(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1

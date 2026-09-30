# Writes procedural demo takes to res://takes/demo/ and bakes them, so the
# demo scene has clips to play before anything is recorded in VR.
# Delete res://takes/demo/ and the demo clips whenever you like.
#
#   Godot --headless --xr-mode off --path . --script res://tools/make_demo_takes.gd [-- --robot ogre]
extends SceneTree

const DEMO_DIR := "res://takes/demo"


func _init() -> void:
	var specs := [
		# robot, clip, motion, seconds, loop
		["tinker", "idle_demo", FakePerformance.idle, 12.5, true],
		["tinker", "act_reach_demo", FakePerformance.reach_and_grab, 3.2, false],
		["tinker", "act_wave_demo", FakePerformance.wave, 3.0, false],
		["hauler", "idle_demo", FakePerformance.idle, 12.5, true],
		["hauler", "act_reach_demo", FakePerformance.reach_and_grab, 3.2, false],
		["hauler", "act_wave_demo", FakePerformance.wave, 3.0, false],
		["ogre", "idle_demo", FakePerformance.idle, 12.5, true],
		["ogre", "act_lift_demo", FakePerformance.crane_lift, 7.0, false],
		["ogre", "act_reach_demo", FakePerformance.reach_and_grab, 3.2, false],
	]
	var args := OS.get_cmdline_user_args()
	var only := args[args.find("--robot") + 1] if args.find("--robot") >= 0 and args.find("--robot") + 1 < args.size() else ""
	var seed := 1
	for s in specs:
		seed += 1
		if not only.is_empty() and s[0] != only:
			continue
		var take := FakePerformance.build(s[2], s[3], 0.002, seed - 1)
		take.robot_id = s[0]
		take.clip_name = s[1]
		take.note = "Procedural demo take (tools/make_demo_takes.gd)"
		var recipe := CleanupRecipe.new()
		recipe.loop = s[4]
		recipe.trim_stop_reach = false
		take.recipe = recipe
		var path := "%s/%s_%s.res" % [DEMO_DIR, s[0], s[1]]
		TakeStore.save(take, path)
		var r := Baker.bake_to_library(take, path, s[0])
		print("%s -> %s/%s  (%s)" % [path, s[0], r.clip, TakeStore.describe_report(r.report)])
	quit()

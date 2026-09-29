# Rebakes every take into its robot's animation library.
#
#   Godot --headless --xr-mode off --path . --script res://tools/bake_all.gd
#   Godot ... --script res://tools/bake_all.gd -- --robot hauler
#   Godot ... --script res://tools/bake_all.gd -- --take res://takes/take_X.res
#
# (The same thing is available as a button in the editor's corkLabs dock.)
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var only_robot := _arg(args, "--robot")
	var only_take := _arg(args, "--take")
	var paths := PackedStringArray([only_take]) if only_take else TakeStore.list()
	var ok := 0
	var failed := 0
	for path in paths:
		var take := TakeStore.load_take(path)
		if take == null:
			print("SKIP  %s (not a take)" % path)
			continue
		if take.robot_id.is_empty():
			print("SKIP  %s (no robot chosen)" % path)
			continue
		if only_robot and take.robot_id != only_robot:
			continue
		var r := Baker.bake_to_library(take, path, take.robot_id)
		if r.ok:
			ok += 1
			print("BAKED %s -> %s/%s  (%s)" % [path.get_file(), take.robot_id, r.clip, TakeStore.describe_report(r.report)])
		else:
			failed += 1
			print("FAIL  %s: %s" % [path, str(r.report.get("notes", []))])
	print("%d baked, %d failed" % [ok, failed])
	quit(1 if failed > 0 else 0)


static func _arg(args: PackedStringArray, name: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else ""

# Opens a scene, waits, and saves a screenshot. Handy for checking visuals
# without clicking around.
#
#   Godot --xr-mode off --path . --resolution 1280x720 --script res://tools/screenshot.gd -- \
#       --scene res://game/demo_facility.tscn --wait 4 --out C:/temp/shot.png [--cam 2] [--nofilter]
#       [--fault pipe_2 --fault relay] [--spend 1800]   (facility scenes: break things, pass facility time)
#       [--call log_on --call open_app:cameras]         (call methods on the scene first)
# Note: facility scenes use their normal save, so this moves the demo's facility on.
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := _arg(args, "--scene", "res://game/demo_facility.tscn")
	var wait := float(_arg(args, "--wait", "3"))
	var out := _arg(args, "--out", "user://screenshot.png")
	var cam := int(_arg(args, "--cam", "0"))
	var scene: Node = (load(scene_path) as PackedScene).instantiate()
	get_root().add_child(scene)
	await process_frame
	if cam > 0 and scene.has_method("_use_camera"):
		scene._use_camera(cam - 1)
	if args.has("--nofilter") and scene.get("cctv"):
		scene.cctv.visible = false
	# Call methods on the scene first, e.g. --call log_on --call open_app:cameras
	for i in args.size():
		if args[i] == "--call" and i + 1 < args.size():
			var bits := args[i + 1].split(":")
			var call_args := Array(bits.slice(1)).map(func(a: String): return float(a) if a.is_valid_float() else a)
			scene.callv(bits[0], call_args)
			await process_frame
	# Facility scenes: break something and/or let facility time pass first.
	var facility := get_root().get_node_or_null("Facility")
	if facility and facility.running:
		for i in args.size():
			if args[i] == "--fault" and i + 1 < args.size():
				facility.sim.schedule_in(0.0, "plant_fault", {"device": args[i + 1]})
		facility.spend(float(_arg(args, "--spend", "0.1")), "screenshot tool")
	await create_timer(wait).timeout
	await process_frame
	var img := get_root().get_texture().get_image()
	img.save_png(out)
	print("saved ", out)
	quit()


static func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback

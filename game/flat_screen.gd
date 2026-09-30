# VR is switched on for the whole project (the recorder needs it at
# startup), so every scene you run opens a session with the headset, and a
# flat monitor scene then never shows its window. Closing the session from
# inside the game isn't enough, so flat scenes call FlatScreen.relaunch_if_xr()
# first thing: if VR is running, it starts the same scene again as a new
# process with VR switched off (--xr-mode off) and quits this one.
#
# Side effect: the relaunched game isn't attached to the editor's debugger,
# so print() output and errors don't show in the Output panel. They go to
# the log file in %APPDATA%\Godot\app_userdata\corkLabs\logs\ instead.
class_name FlatScreen
extends RefCounted


# Returns true if the scene is being relaunched (the caller should stop).
static func relaunch_if_xr(scene: Node) -> bool:
	var xr := XRServer.find_interface("OpenXR")
	if xr == null or not xr.is_initialized():
		return false
	var args := PackedStringArray([
		"--path", ProjectSettings.globalize_path("res://"),
		"--xr-mode", "off",
		scene.scene_file_path,
	])
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		args.append("--")
		args.append_array(user_args)
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		push_error("FlatScreen: could not relaunch without VR")
		return false
	# A normal quit() gets stuck on the VR session, so end this process hard.
	# The headset runtime cleans the session up when the process is gone.
	OS.kill(OS.get_process_id())
	return true

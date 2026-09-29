# Phase 1 test scene: proves Godot can talk to the headset.
#
# What it does:
#   - Turns on VR output when the scene starts.
#   - Shows each controller as a cube (the XRController3D nodes in the scene
#     move themselves; this script doesn't have to).
#   - Prints every input we plan to record (trigger, grip, stick, buttons)
#     on a floating label above each hand, and tints the cube by trigger
#     pressure so you can see analog values working.
#
# If it all shows up in the headset, phase 1 is done.
extends Node3D

# $Name is shorthand for "find the child node with this path".
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var right_hand: XRController3D = $XROrigin3D/RightHand
@onready var head: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var status_label: Label3D = $StatusLabel


# _ready() runs once, when the scene starts.
func _ready() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		# The headset sets its own frame rate, so the PC monitor's vsync
		# must not hold it back.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		# Render this viewport to the headset instead of the monitor.
		get_viewport().use_xr = true
		print("OpenXR is running.")
	else:
		# Most common cause: the headset isn't connected to Link, or Link
		# isn't the active OpenXR runtime.
		status_label.text = "OpenXR failed to start.\nIs the headset on Link?"
		push_error("OpenXR did not initialize. Check the Link connection and active runtime.")


# _process() runs every frame. `delta` is seconds since the last frame.
func _process(_delta: float) -> void:
	_show_inputs(left_hand, "LEFT")
	_show_inputs(right_hand, "RIGHT")

	var p := head.position
	status_label.text = "corkLabs phase 1\nhead height: %.2f m" % p.y


# Reads one controller's inputs and writes them on its label.
func _show_inputs(hand: XRController3D, side: String) -> void:
	# The names ("trigger", "grip", "primary", ...) come from Godot's default
	# XR action map (res://openxr_action_map.tres once Godot creates it).
	var trigger := hand.get_float("trigger")
	var grip := hand.get_float("grip")
	var stick := hand.get_vector2("primary")
	var ax := hand.is_button_pressed("ax_button")
	var by := hand.is_button_pressed("by_button")
	var menu := hand.is_button_pressed("menu_button")

	var label: Label3D = hand.get_node("InputLabel")
	if not hand.get_has_tracking_data():
		label.text = "%s\n(not tracked)" % side
	else:
		label.text = "%s\ntrigger %.2f  grip %.2f\nstick %+.2f %+.2f\nA/X %s  B/Y %s  menu %s" % [
			side, trigger, grip, stick.x, stick.y, _on(ax), _on(by), _on(menu)]

	# Tint the cube from grey (0) to orange (1) with trigger pressure.
	var cube: MeshInstance3D = hand.get_node("Cube")
	var mat: StandardMaterial3D = cube.get_active_material(0)
	mat.albedo_color = Color(0.6, 0.6, 0.6).lerp(Color(1.0, 0.45, 0.05), trigger)


func _on(pressed: bool) -> String:
	return "ON" if pressed else "--"

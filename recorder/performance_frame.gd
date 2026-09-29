# One moment of a performance: where your head and hands were, and what
# every trigger, stick and button was doing.
#
# The live headset and a saved take both hand out PerformanceFrames, so
# anything that consumes them (ghosts now, robots later) can't tell whether
# it's watching you live or a recording. This is the "playback trick" from
# the pipeline doc.
class_name PerformanceFrame
extends RefCounted

# Button bits, packed into one number per hand (like MIDI note flags).
const BTN_AX := 1         # A (right hand) or X (left hand)
const BTN_BY := 2         # B (right hand) or Y (left hand)
const BTN_MENU := 4       # left hand only
const BTN_STICK := 8      # thumbstick pressed in
const TOUCH_AX := 16      # thumb resting on A/X
const TOUCH_BY := 32      # thumb resting on B/Y
const TOUCH_STICK := 64   # thumb resting on the stick
const TOUCH_TRIGGER := 128  # finger resting on the trigger

# Poses are relative to the XROrigin3D, which sits on the floor mark.
var head := Transform3D()
var left := Transform3D()
var right := Transform3D()

# 0 = not tracked, 1 = low confidence (guessing), 2 = high confidence.
var left_confidence := 0
var right_confidence := 0

var left_trigger := 0.0
var left_grip := 0.0
var left_stick := Vector2.ZERO
var left_buttons := 0

var right_trigger := 0.0
var right_grip := 0.0
var right_stick := Vector2.ZERO
var right_buttons := 0


# Reads the live headset right now.
static func capture(head_node: XRCamera3D, left_node: XRController3D,
		right_node: XRController3D) -> PerformanceFrame:
	var f := PerformanceFrame.new()
	f.head = head_node.transform
	f.left = left_node.transform
	f.right = right_node.transform

	f.left_confidence = _confidence(left_node)
	f.left_trigger = left_node.get_float("trigger")
	f.left_grip = left_node.get_float("grip")
	f.left_stick = left_node.get_vector2("primary")
	f.left_buttons = _buttons(left_node)

	f.right_confidence = _confidence(right_node)
	f.right_trigger = right_node.get_float("trigger")
	f.right_grip = right_node.get_float("grip")
	f.right_stick = right_node.get_vector2("primary")
	f.right_buttons = _buttons(right_node)
	return f


static func _confidence(node: XRController3D) -> int:
	var pose := node.get_pose()
	if pose == null or not node.get_has_tracking_data():
		return 0
	return pose.tracking_confidence


static func _buttons(node: XRController3D) -> int:
	var b := 0
	if node.is_button_pressed("ax_button"): b |= BTN_AX
	if node.is_button_pressed("by_button"): b |= BTN_BY
	if node.is_button_pressed("menu_button"): b |= BTN_MENU
	if node.is_button_pressed("primary_click"): b |= BTN_STICK
	if node.is_button_pressed("ax_touch"): b |= TOUCH_AX
	if node.is_button_pressed("by_touch"): b |= TOUCH_BY
	if node.is_button_pressed("primary_touch"): b |= TOUCH_STICK
	if node.is_button_pressed("trigger_touch"): b |= TOUCH_TRIGGER
	return b

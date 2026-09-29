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


func duplicate_frame() -> PerformanceFrame:
	var f := PerformanceFrame.new()
	f.head = head
	f.left = left
	f.right = right
	f.left_confidence = left_confidence
	f.left_trigger = left_trigger
	f.left_grip = left_grip
	f.left_stick = left_stick
	f.left_buttons = left_buttons
	f.right_confidence = right_confidence
	f.right_trigger = right_trigger
	f.right_grip = right_grip
	f.right_stick = right_stick
	f.right_buttons = right_buttons
	return f


# A frame part-way between a and b (w = 0 gives a, w = 1 gives b).
# Buttons and confidence switch over at the halfway point.
static func blend(a: PerformanceFrame, b: PerformanceFrame, w: float) -> PerformanceFrame:
	var f := PerformanceFrame.new()
	f.head = blend_xform(a.head, b.head, w)
	f.left = blend_xform(a.left, b.left, w)
	f.right = blend_xform(a.right, b.right, w)
	var src := a if w < 0.5 else b
	f.left_confidence = src.left_confidence
	f.right_confidence = src.right_confidence
	f.left_buttons = src.left_buttons
	f.right_buttons = src.right_buttons
	f.left_trigger = lerpf(a.left_trigger, b.left_trigger, w)
	f.left_grip = lerpf(a.left_grip, b.left_grip, w)
	f.left_stick = a.left_stick.lerp(b.left_stick, w)
	f.right_trigger = lerpf(a.right_trigger, b.right_trigger, w)
	f.right_grip = lerpf(a.right_grip, b.right_grip, w)
	f.right_stick = a.right_stick.lerp(b.right_stick, w)
	return f


static func blend_xform(a: Transform3D, b: Transform3D, w: float) -> Transform3D:
	var qa := a.basis.get_rotation_quaternion()
	var qb := b.basis.get_rotation_quaternion()
	return Transform3D(Basis(qa.slerp(qb, w)), a.origin.lerp(b.origin, w))


# The frame as seen in a mirror: left and right swap, and everything is
# reflected across the performer's centre line. Used for the mirror robot.
func mirrored() -> PerformanceFrame:
	var f := PerformanceFrame.new()
	f.head = mirror_xform(head)
	f.left = mirror_xform(right)
	f.right = mirror_xform(left)
	f.left_confidence = right_confidence
	f.right_confidence = left_confidence
	f.left_trigger = right_trigger
	f.left_grip = right_grip
	f.left_stick = Vector2(-right_stick.x, right_stick.y)
	f.left_buttons = right_buttons
	f.right_trigger = left_trigger
	f.right_grip = left_grip
	f.right_stick = Vector2(-left_stick.x, left_stick.y)
	f.right_buttons = left_buttons
	return f


# Reflects a pose across the x = 0 plane.
static func mirror_xform(x: Transform3D) -> Transform3D:
	var q := x.basis.get_rotation_quaternion()
	var mq := Quaternion(q.x, -q.y, -q.z, q.w)
	return Transform3D(Basis(mq), Vector3(-x.origin.x, x.origin.y, x.origin.z))


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

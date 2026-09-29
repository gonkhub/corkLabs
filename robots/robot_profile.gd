# A robot's "personality": how it turns your performance into its motion.
# The same take played through two profiles should read as two different
# machines. Every value can be changed and the takes rebaked. Nothing is
# re-recorded.
class_name RobotProfile
extends Resource

@export var display_name := "Robot"
@export_multiline var description := ""

@export_group("Reach and travel")
## How far the robot's hands reach compared to yours. 1.8 = long-armed hauler.
@export_range(0.2, 4.0, 0.05) var reach_scale := 1.0
## How much your head's movement moves the robot's body/core.
@export_range(0.0, 3.0, 0.05) var travel_scale := 1.0
## Furthest the body/core can move from its rest point, in meters.
@export_range(0.0, 2.0, 0.01) var travel_limit := 0.35
## Exaggerates (>1) or damps (<1) head turns and tilts.
@export_range(0.0, 2.0, 0.05) var amplitude := 1.0
## Eye height used when a take has no calibration.
@export_range(1.0, 2.2, 0.01) var default_eye_height := 1.65
## Where YOUR right hand rests relative to your eyes when relaxed (left is
## mirrored). Movement away from this rest is what gets scaled by reach_scale.
@export var performer_rest_hand := Vector3(0.22, -0.58, -0.22)

@export_group("Body (slow layer)")
## Body/core response speed in Hz. Low = heavy.
@export_range(0.1, 20.0, 0.1) var body_frequency := 2.0
## 1 = no overshoot. Lower = overshoots and settles, like a heavy thing on a cable.
@export_range(0.0, 3.0, 0.05) var body_damping := 0.8
## 0 = eases in. Negative = winds up before moving.
@export_range(-3.0, 3.0, 0.05) var body_response := 0.0

@export_group("Head (medium layer)")
@export_range(0.1, 20.0, 0.1) var head_frequency := 4.0
@export_range(0.0, 3.0, 0.05) var head_damping := 0.8
@export_range(-3.0, 3.0, 0.05) var head_response := 0.5
## How far the head can turn away from the body, in degrees.
@export_range(0.0, 180.0, 1.0) var neck_limit_deg := 70.0

@export_group("Eye (fast layer)")
@export_range(0.1, 30.0, 0.1) var eye_frequency := 8.0
@export_range(0.0, 3.0, 0.05) var eye_damping := 0.9
@export_range(-3.0, 3.0, 0.05) var eye_response := 1.0
## How far the eye can look away from where the head/core points, in degrees.
@export_range(0.0, 90.0, 1.0) var eye_limit_deg := 30.0
## Right stick left/right moves the eye this many degrees.
@export_range(0.0, 60.0, 1.0) var stick_look_yaw_deg := 25.0
## Right stick up/down moves the eye this many degrees.
@export_range(0.0, 60.0, 1.0) var stick_look_pitch_deg := 20.0

@export_group("Hands")
@export_range(0.1, 30.0, 0.1) var hand_frequency := 3.0
@export_range(0.0, 3.0, 0.05) var hand_damping := 0.8
@export_range(-3.0, 3.0, 0.05) var hand_response := 0.0

@export_group("Tools")
@export_range(0.1, 30.0, 0.1) var tool_frequency := 6.0
@export_range(0.0, 3.0, 0.05) var tool_damping := 0.7
## Shapes trigger -> claw. Leave empty for a straight line. Make the curve
## bite late for a heavy clamp, or early for twitchy tweezers.
@export var trigger_curve: Curve
## How wide the claws open, in degrees, with the trigger released.
@export_range(0.0, 90.0, 1.0) var claw_open_deg := 35.0

@export_group("Face")
## Left stick down closes the eyelid this far (degrees). Blink (A/X) closes it fully.
@export_range(0.0, 120.0, 1.0) var lid_closed_deg := 80.0
## Left stick left/right changes the lens/pupil size by up to this fraction.
@export_range(0.0, 1.0, 0.01) var lens_range := 0.35
## How long a blink takes to reopen, in seconds.
@export_range(0.01, 1.0, 0.01) var blink_release := 0.12
## Eye glow at rest (light energy).
@export_range(0.0, 10.0, 0.05) var glow_base := 0.8
## Extra glow when B/Y flashes it.
@export_range(0.0, 20.0, 0.1) var glow_flash := 4.0
## How long the flash takes to fade, in seconds.
@export_range(0.01, 3.0, 0.01) var flash_release := 0.4

@export_group("Timing")
## Stretches baked clips in time. >1 = slower. Big robots feel bigger when
## slowed by roughly the square root of their size. Breaks sync with
## dialogue, so use it for gameplay clips.
@export_range(0.25, 4.0, 0.05) var retime := 1.0

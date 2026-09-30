# Ogre: a massive, stationary crane core. It never leaves its hangar.
#   ceiling mount -> column -> core (a huge sphere) with a big eye that
#   throws a cone of light, and ONE arm: a knuckle-boom crane.
#   crane base -> boom -> jib -> tip sheave -> cable -> hook block -> grab jaws
#
# Gaze cascade: the core is enormous, so it turns very slowly and only part
# of the way; the eye (and its beam) makes up the rest. Only YOUR RIGHT HAND
# drives the crane: two-bone IK puts the jib tip where your hand is (the
# knuckle points up, like a real knuckle-boom crane, never like a knee). The
# hook hangs from the tip on its cable and lags behind like a real load.
#
#   right hand     where the jib tip goes (hook hangs below it)
#   right wrist    turns the hook (yaw only: it's hanging)
#   right trigger  closes the grab jaws (grip clamps hard)
#   left trigger   winch: pays out cable, lowering the hook
#   head           core turns slowly, eye darts; A/X blink, B/Y flash the beam
extends RobotRig

## The eye's resting tilt, in degrees (negative = angled down, so the beam
## lands on the hangar floor when you look straight ahead).
@export var eye_rest_pitch_deg := -25.0
## How much of your head turn the core itself follows (the eye does the rest).
@export_range(0.0, 1.0, 0.05) var core_follow := 0.55
## Where the jib tip rests relative to the core's centre when you're relaxed:
## out front and to the right, hook over the floor.
@export var tip_rest := Vector3(0.75, -0.3, -1.85)
## Which way the knuckle (boom/jib joint) points: UP and out.
@export var knuckle_hint := Vector3(0.35, 1.0, 0.1)
## Cable length with the left trigger released, and fully pressed.
@export var cable_rest := 0.6
@export var cable_max := 1.5
## The hook's swing on its cable: low frequency + low damping = a heavy
## pendulum that lags and sways behind the jib.
@export var hook_frequency := 0.7
@export var hook_damping := 0.3

var core: Node3D
var eye: Node3D
var lid: Node3D
var lens: Node3D
var glow: SpotLight3D
var boom: Node3D
var jib: Node3D
var tip: Node3D
var cable: Node3D
var hook: Node3D
var jaw_a: Node3D
var jaw_b: Node3D
var base: Node3D
var boom_len := 1.0
var jib_len := 1.0
var core_rest := Vector3.ZERO


func _bind() -> void:
	core = $Core
	eye = $Core/Eye
	lid = $Core/Eye/LidTop
	lens = $Core/Eye/Lens
	glow = $Core/Eye/Glow
	base = $Core/CraneBase
	boom = $Core/CraneBase/Boom
	jib = $Core/CraneBase/Boom/Jib
	tip = $Core/CraneBase/Boom/Jib/Tip
	cable = $Core/CraneBase/Boom/Jib/Tip/Cable
	hook = $Core/CraneBase/Boom/Jib/Tip/Hook
	jaw_a = hook.get_node("JawA")
	jaw_b = hook.get_node("JawB")
	core_rest = core.position
	# Segment lengths come from the scene, so resizing the model just works.
	boom_len = absf(jib.position.z)
	jib_len = absf(tip.position.z)


func drive(f: PerformanceFrame, dt: float) -> void:
	var p := profile
	var rest_q := Quaternion(Vector3.RIGHT, deg_to_rad(eye_rest_pitch_deg))

	# Core layer: stays put (it's bolted to the ceiling), turns slowly and
	# only part of the way towards where you look.
	var head_q := head_rotation(f)
	var core_target := clamp_rotation(scale_rotation(head_q, core_follow), deg_to_rad(p.neck_limit_deg))
	var core_q := follow_quat("core_rot", dt, core_target, p.body_frequency, p.body_damping, p.body_response)
	core.position = core_rest
	core.quaternion = core_q

	# Eye layer: the remainder, plus the right stick.
	var eye_target := clamp_rotation(core_q.inverse() * head_q, deg_to_rad(p.eye_limit_deg)) * rest_q * stick_look(f)
	eye.quaternion = follow_quat("eye", dt, eye_target, p.eye_frequency, p.eye_damping, p.eye_response)

	# Face: the lid is a heavy shutter; closing it also cuts the beam.
	var fc := face(f, dt)
	lid.rotation.x = -deg_to_rad(p.lid_closed_deg) * fc.lid
	lens.scale = Vector3(fc.lens, 1.0, fc.lens)
	glow.light_energy = fc.glow * (1.0 - 0.9 * clampf(fc.lid, 0.0, 1.0))

	# Crane: the jib tip goes where your right hand is (relative to your head
	# -> relative to the core), boom and jib solved with two-bone IK.
	var target := follow_vec3("tip", dt, core_rest + hand_offset(f, "right", tip_rest),
		p.hand_frequency, p.hand_damping, p.hand_response)
	var shoulder := rig_xform(boom).origin
	var up := core_q * Vector3.UP
	var knuckle := two_bone_elbow(shoulder, target, boom_len, jib_len, core_q * knuckle_hint)
	set_rig_rotation(boom, look_rotation(knuckle - shoulder, up))
	set_rig_rotation(jib, look_rotation(target - knuckle, up))
	var tip_pos := rig_xform(tip).origin

	# Winch + hook: hangs below the tip, swinging behind it like a load.
	var winch := follow_float("winch", dt, clampf(f.left_trigger, 0.0, 1.0), p.tool_frequency * 0.5, 1.0, 0.0)
	var length := lerpf(cable_rest, cable_max, winch)
	var hook_pos := follow_vec3("hook", dt, tip_pos + Vector3.DOWN * length, hook_frequency, hook_damping, 0.0)
	var to_hook := hook_pos - tip_pos
	set_rig_rotation(cable, look_rotation(to_hook, Vector3.BACK))
	cable.scale = Vector3(1, 1, maxf(to_hook.length(), 0.01))
	_set_rig_position(hook, hook_pos)

	# The hook turns with your wrist (yaw only), and tilts with its cable.
	var fwd := hand_rotation(f, "right") * Vector3.FORWARD
	var yaw := atan2(-fwd.x, -fwd.z) if Vector2(fwd.x, fwd.z).length() > 0.05 else 0.0
	var hook_yaw := follow_float("hook_yaw", dt, yaw, p.hand_frequency, p.hand_damping, 0.0)
	var tilt := Quaternion(Vector3.DOWN, to_hook.normalized()) if to_hook.length() > 0.01 else Quaternion.IDENTITY
	set_rig_rotation(hook, tilt * Quaternion(Vector3.UP, hook_yaw))

	# Trigger closes the grab; grip clamps it hard.
	var closure := maxf(claw_closure(f, "right", dt), f.right_grip)
	var open := deg_to_rad(p.claw_open_deg) * (1.0 - closure)
	jaw_a.rotation.x = open
	jaw_b.rotation.x = -open


# Places `node` so that, in rig space, it's at `pos`.
func _set_rig_position(node: Node3D, pos: Vector3) -> void:
	var parent := node.get_parent()
	if parent == self or not parent is Node3D:
		node.position = pos
	else:
		node.position = rig_xform(parent).affine_inverse() * pos


func baked_nodes() -> Array[Node3D]:
	return [core, eye, lid, lens, boom, jib, cable, hook, jaw_a, jaw_b]


func baked_properties() -> Array:
	return [[glow, &"light_energy"]]

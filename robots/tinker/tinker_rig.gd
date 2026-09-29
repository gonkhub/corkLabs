# Tinker: a Wheatley-style core-bot for precise work.
#   rail mount -> tether -> core (the whole body) with an eye and two
#   telescoping arms bolted to its sides.
#
# Gaze cascade: the core follows your head's rotation slowly (it's heavy and
# the arms hang off it); the eye makes up the difference quickly, so glances
# read instantly while big turns take the whole body.
extends RobotRig

## Shortest and longest the telescoping arms can get, in meters.
@export var min_reach := 0.12
@export var max_reach := 0.85
## Where the right hand rests relative to the core when you're relaxed
## (left is mirrored).
@export var hand_rest := Vector3(0.24, -0.3, -0.22)

var core: Node3D
var eye: Node3D
var lid: Node3D
var lens: Node3D
var glow: OmniLight3D
var tether: Node3D
var core_rest := Vector3.ZERO
var arms := {}


func _bind() -> void:
	core = $Core
	eye = $Core/Eye
	lid = $Core/Eye/LidTop
	lens = $Core/Eye/Lens
	glow = $Core/Eye/Glow
	tether = $Tether
	core_rest = core.position
	for side in ["left", "right"]:
		var root: Node3D = get_node("Core/ArmL" if side == "left" else "Core/ArmR")
		arms[side] = {
			"root": root,
			"rod": root.get_node("Rod"),
			"wrist": root.get_node("Wrist"),
			"claw_a": root.get_node("Wrist/ClawA"),
			"claw_b": root.get_node("Wrist/ClawB"),
		}


func drive(f: PerformanceFrame, dt: float) -> void:
	var p := profile

	# Body layer: the core drifts with your head, heavily.
	var core_pos := follow_vec3("core_pos", dt, core_rest + head_offset(f),
		p.body_frequency, p.body_damping, p.body_response)
	var head_q := head_rotation(f)
	var core_q := follow_quat("core_rot", dt, head_q, p.body_frequency, p.body_damping, p.body_response)
	core.position = core_pos
	core.quaternion = core_q

	# Eye layer: whatever the core hasn't caught up on, plus the right stick.
	var eye_target := clamp_rotation(core_q.inverse() * head_q, deg_to_rad(p.eye_limit_deg)) * stick_look(f)
	eye.quaternion = follow_quat("eye", dt, eye_target, p.eye_frequency, p.eye_damping, p.eye_response)

	# Tether stretches from the mount to the top of the core.
	var to_core := core_pos + core_q * Vector3(0, 0.2, 0) - tether.position
	tether.quaternion = look_rotation(to_core, Vector3.BACK)
	tether.scale = Vector3(1, 1, maxf(to_core.length(), 0.01))

	# Face.
	var fc := face(f, dt)
	lid.rotation.x = -deg_to_rad(p.lid_closed_deg) * fc.lid
	lens.scale = Vector3(fc.lens, 1.0, fc.lens)   # lens cylinder's round faces are X/Z
	glow.light_energy = fc.glow

	# Arms: aim at where your hand is (relative to your head -> relative to
	# the core), telescope to the distance, and copy your wrist's rotation.
	for side in ["left", "right"]:
		var arm: Dictionary = arms[side]
		var rest := Vector3(-hand_rest.x, hand_rest.y, hand_rest.z) if side == "left" else hand_rest
		var target := follow_vec3(side + "_hand", dt, core_pos + hand_offset(f, side, rest),
			p.hand_frequency, p.hand_damping, p.hand_response)
		var hand_q := follow_quat(side + "_hand_rot", dt, hand_rotation(f, side),
			p.hand_frequency * 1.5, p.hand_damping, p.hand_response)
		var shoulder := rig_xform(arm.root).origin
		var to_target := target - shoulder
		var length := clampf(to_target.length(), min_reach, max_reach)
		set_rig_rotation(arm.root, look_rotation(to_target, core_q * Vector3.UP))
		(arm.rod as Node3D).scale = Vector3(1, 1, length)
		(arm.wrist as Node3D).position = Vector3(0, 0, -length)

		# Grip spins the tool head (drill / screwdriver) up to a quarter turn.
		var grip: float = f.get(side + "_grip")
		var spin := Quaternion(Vector3.FORWARD, follow_float(side + "_spin", dt, grip * PI * 0.5,
			p.tool_frequency, p.tool_damping, 0.0))
		set_rig_rotation(arm.wrist, hand_q * spin)

		var open := deg_to_rad(p.claw_open_deg) * (1.0 - claw_closure(f, side, dt))
		(arm.claw_a as Node3D).rotation.x = open
		(arm.claw_b as Node3D).rotation.x = -open


func baked_nodes() -> Array[Node3D]:
	var list: Array[Node3D] = [core, eye, lid, lens, tether]
	for side in ["left", "right"]:
		var arm: Dictionary = arms[side]
		list.append_array([arm.root, arm.rod, arm.wrist, arm.claw_a, arm.claw_b])
	return list


func baked_properties() -> Array:
	return [[glow, &"light_energy"]]

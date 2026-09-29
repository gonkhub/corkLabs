# Hauler: a heavy-labour hanger-bot.
#   rail carriage -> hanger rod -> body (arms mount here) -> neck/head -> eye
#
# Gaze cascade in three layers: the body swings round slowly to face where
# you're looking (yaw only), the head turns on its neck at medium speed, and
# the eye darts. The long two-segment arms use two-bone IK, with elbows
# pointing out and back like an excavator.
extends RobotRig

## Which way each elbow points, in body space (out, down, back).
@export var elbow_hint_left := Vector3(-0.7, -0.3, 0.6)
@export var elbow_hint_right := Vector3(0.7, -0.3, 0.6)
## How far above the body's centre the hanger rod attaches.
@export var hanger_attach_height := 0.28

var hanger: Node3D
var body: Node3D
var neck: Node3D
var eye: Node3D
var lid: Node3D
var lens: Node3D
var glow: OmniLight3D
var body_rest := Vector3.ZERO
var arms := {}


func _bind() -> void:
	hanger = $Hanger
	body = $Body
	neck = $Body/Neck
	eye = $Body/Neck/Eye
	lid = $Body/Neck/Eye/LidTop
	lens = $Body/Neck/Eye/Lens
	glow = $Body/Neck/Eye/Glow
	body_rest = body.position
	for side in ["left", "right"]:
		var shoulder: Node3D = get_node("Body/ShoulderL" if side == "left" else "Body/ShoulderR")
		var upper: Node3D = shoulder.get_node("Upper")
		var fore: Node3D = upper.get_node("Fore")
		var wrist: Node3D = fore.get_node("Wrist")
		arms[side] = {
			"shoulder": shoulder,
			"upper": upper,
			"fore": fore,
			"wrist": wrist,
			"claw_a": wrist.get_node("ClawA"),
			"claw_b": wrist.get_node("ClawB"),
			# Segment lengths come from the scene, so resizing the model just works.
			"upper_len": absf(fore.position.z),
			"fore_len": absf(wrist.position.z),
			"hint": elbow_hint_left if side == "left" else elbow_hint_right,
		}


func drive(f: PerformanceFrame, dt: float) -> void:
	var p := profile

	# Body layer: sways on its hanger with your head position, and turns
	# (yaw only) to face where you look.
	var body_pos := follow_vec3("body_pos", dt, body_rest + head_offset(f),
		p.body_frequency, p.body_damping, p.body_response)
	var head_q := head_rotation(f)
	var look := head_q * Vector3.FORWARD
	var yaw := atan2(-look.x, -look.z)
	var body_q := follow_quat("body_rot", dt, Quaternion(Vector3.UP, yaw * 0.8),
		p.body_frequency, p.body_damping, p.body_response)
	body.position = body_pos
	body.quaternion = body_q

	var attach := body_pos + body_q * Vector3(0, hanger_attach_height, 0)
	var to_body := attach - hanger.position
	hanger.quaternion = look_rotation(to_body, Vector3.BACK)
	hanger.scale = Vector3(1, 1, maxf(to_body.length(), 0.01))

	# Head layer: turns on the neck, within its limit.
	var neck_target := clamp_rotation(body_q.inverse() * head_q, deg_to_rad(p.neck_limit_deg))
	var neck_q := follow_quat("neck", dt, neck_target, p.head_frequency, p.head_damping, p.head_response)
	neck.quaternion = neck_q

	# Eye layer: the remainder, plus the right stick.
	var eye_target := clamp_rotation((body_q * neck_q).inverse() * head_q, deg_to_rad(p.eye_limit_deg)) * stick_look(f)
	eye.quaternion = follow_quat("eye", dt, eye_target, p.eye_frequency, p.eye_damping, p.eye_response)

	var fc := face(f, dt)
	lid.rotation.x = -deg_to_rad(p.lid_closed_deg) * fc.lid
	lens.scale = Vector3(fc.lens, 1.0, fc.lens)
	glow.light_energy = fc.glow

	# Arms: hands relative to your head map to hands relative to the neck.
	var anchor := rig_xform(neck).origin
	var body_up := body_q * Vector3.UP
	for side in ["left", "right"]:
		var arm: Dictionary = arms[side]
		var target := follow_vec3(side + "_hand", dt, anchor + hand_offset(f, side),
			p.hand_frequency, p.hand_damping, p.hand_response)
		var hand_q := follow_quat(side + "_hand_rot", dt, hand_rotation(f, side),
			p.hand_frequency * 1.5, p.hand_damping, p.hand_response)
		var shoulder := rig_xform(arm.shoulder).origin
		var hint: Vector3 = body_q * (arm.hint as Vector3)
		var elbow := two_bone_elbow(shoulder, target, arm.upper_len, arm.fore_len, hint)
		set_rig_rotation(arm.upper, look_rotation(elbow - shoulder, body_up))
		set_rig_rotation(arm.fore, look_rotation(target - elbow, body_up))
		set_rig_rotation(arm.wrist, hand_q)

		# Trigger closes the claws; grip clamps them hard.
		var grip: float = f.get(side + "_grip")
		var closure := maxf(claw_closure(f, side, dt), grip)
		var open := deg_to_rad(p.claw_open_deg) * (1.0 - closure)
		(arm.claw_a as Node3D).rotation.x = open
		(arm.claw_b as Node3D).rotation.x = -open


func baked_nodes() -> Array[Node3D]:
	var list: Array[Node3D] = [hanger, body, neck, eye, lid, lens]
	for side in ["left", "right"]:
		var arm: Dictionary = arms[side]
		list.append_array([arm.upper, arm.fore, arm.wrist, arm.claw_a, arm.claw_b])
	return list


func baked_properties() -> Array:
	return [[glow, &"light_energy"]]

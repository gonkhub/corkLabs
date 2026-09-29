# Base class for every robot. A rig turns PerformanceFrames into poses for
# its joint nodes, using its RobotProfile. Two things use it:
#   - the recorder, driving it live as a mirror (drive() every frame)
#   - the baker, stepping through a take and recording the joints into an
#     Animation (see pipeline/baker.gd)
#
# Robot-specific rigs (robots/<name>/<name>_rig.gd) extend this and fill in
# _bind(), drive() and baked_nodes().
#
# All maths is done in "rig space" (relative to this root node) by walking
# up the parent chain ourselves, so a rig works even when it isn't in the
# scene tree (the baker uses it that way).
class_name RobotRig
extends Node3D

@export var profile: RobotProfile

var eye_height := 1.65
var _springs := {}
var _blink := 0.0
var _flash := 0.0
var _bound := false


# Call before driving a new take. Springs snap to the first frame.
func begin(p_eye_height := 0.0) -> void:
	if profile == null:
		profile = RobotProfile.new()
	if not _bound:
		_bind()
		_bound = true
	eye_height = p_eye_height if p_eye_height > 0.0 else profile.default_eye_height
	_springs.clear()
	_blink = 0.0
	_flash = 0.0


# Pose every joint for this frame. dt = seconds since the previous frame.
func drive(_frame: PerformanceFrame, _dt: float) -> void:
	pass


# Nodes whose transforms get baked into animations.
func baked_nodes() -> Array[Node3D]:
	return []


# Extra [node, property] pairs to bake (e.g. light energy).
func baked_properties() -> Array:
	return []


# Look up joint nodes here (called once, even outside the scene tree).
func _bind() -> void:
	pass


# --- Performance -> robot mapping (shared by all robots) -------------------

# How far your head has moved from its neutral standing spot, scaled and
# softly limited by the profile.
func head_offset(f: PerformanceFrame) -> Vector3:
	var d := (f.head.origin - Vector3(0.0, eye_height, 0.0)) * profile.travel_scale
	return soft_limit(d, profile.travel_limit)


# Your head's rotation, exaggerated or damped by the profile's amplitude.
func head_rotation(f: PerformanceFrame) -> Quaternion:
	return scale_rotation(f.head.basis.get_rotation_quaternion(), profile.amplitude)


# A hand's position relative to your head, scaled to the robot's reach.
func hand_offset(f: PerformanceFrame, side: String) -> Vector3:
	var hand: Transform3D = f.get(side)
	return (hand.origin - f.head.origin) * profile.reach_scale


func hand_rotation(f: PerformanceFrame, side: String) -> Quaternion:
	var hand: Transform3D = f.get(side)
	return hand.basis.get_rotation_quaternion()


# 0 = claw open, 1 = closed, through the profile's trigger curve and a spring.
func claw_closure(f: PerformanceFrame, side: String, dt: float) -> float:
	var v: float = f.get(side + "_trigger")
	if profile.trigger_curve:
		v = profile.trigger_curve.sample_baked(v)
	return clampf(follow_float(side + "_claw", dt, v, profile.tool_frequency, profile.tool_damping, 0.0), 0.0, 1.2)


# Extra eye rotation from the right stick ("look over there").
func stick_look(f: PerformanceFrame) -> Quaternion:
	var yaw := deg_to_rad(-f.right_stick.x * profile.stick_look_yaw_deg)
	var pitch := deg_to_rad(f.right_stick.y * profile.stick_look_pitch_deg)
	return Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch)


# Updates blink and flash envelopes from A/X and B/Y (either hand).
# Returns {"lid": 0..1 closed, "lens": scale, "glow": light energy}.
func face(f: PerformanceFrame, dt: float) -> Dictionary:
	var buttons := f.left_buttons | f.right_buttons
	_blink = 1.0 if buttons & PerformanceFrame.BTN_AX else maxf(0.0, _blink - dt / profile.blink_release)
	_flash = 1.0 if buttons & PerformanceFrame.BTN_BY else maxf(0.0, _flash - dt / profile.flash_release)
	var lid := maxf(clampf(-f.left_stick.y, 0.0, 1.0) * 0.8, _blink)
	var lens := 1.0 + f.left_stick.x * profile.lens_range
	return {
		"lid": follow_float("lid", dt, lid, 25.0, 1.0, 0.0),
		"lens": follow_float("lens", dt, lens, 6.0, 0.8, 0.0),
		"glow": profile.glow_base + _flash * _flash * profile.glow_flash,
	}


# --- Springs -----------------------------------------------------------------
# Each named spring is created on first use and snaps to its first target.

func follow_vec3(key: String, dt: float, target: Vector3, f: float, z: float, r: float) -> Vector3:
	var s: SecondOrder = _springs.get(key)
	if s == null:
		s = SecondOrder.new(f, z, r)
		s.reset_vec3(target)
		_springs[key] = s
		return target
	return s.update_vec3(dt, target)


func follow_quat(key: String, dt: float, target: Quaternion, f: float, z: float, r: float) -> Quaternion:
	var s: SecondOrder = _springs.get(key)
	if s == null:
		s = SecondOrder.new(f, z, r)
		s.reset_quat(target)
		_springs[key] = s
		return target
	return s.update_quat(dt, target)


func follow_float(key: String, dt: float, target: float, f: float, z: float, r: float) -> float:
	var s: SecondOrder = _springs.get(key)
	if s == null:
		s = SecondOrder.new(f, z, r)
		s.reset_float(target)
		_springs[key] = s
		return target
	return s.update_float(dt, target)


# --- Rig-space helpers -------------------------------------------------------

# A node's transform relative to this rig's root.
func rig_xform(node: Node3D) -> Transform3D:
	var t := node.transform
	var p := node.get_parent()
	while p != null and p != self:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


# Rotates `node` so that, in rig space, it has rotation `q`.
func set_rig_rotation(node: Node3D, q: Quaternion) -> void:
	var parent_q := Quaternion.IDENTITY
	var p := node.get_parent()
	if p != self and p is Node3D:
		parent_q = rig_xform(p).basis.get_rotation_quaternion()
	node.quaternion = (parent_q.inverse() * q).normalized()


# Rotation whose -Z axis points along `dir` (Godot's "forward").
static func look_rotation(dir: Vector3, up_hint := Vector3.UP) -> Quaternion:
	if dir.length_squared() < 0.000001:
		return Quaternion.IDENTITY
	var d := dir.normalized()
	var up := up_hint.normalized()
	if absf(d.dot(up)) > 0.999:
		up = Vector3.BACK if absf(d.dot(Vector3.BACK)) < 0.9 else Vector3.RIGHT
	return Basis.looking_at(d, up).get_rotation_quaternion()


# Scales how far a rotation turns (amplitude > 1 exaggerates).
static func scale_rotation(q: Quaternion, amount: float) -> Quaternion:
	if q.w < 0.0:
		q = -q
	var angle := q.get_angle()
	if angle < 0.00001 or is_equal_approx(amount, 1.0):
		return q
	return Quaternion(q.get_axis().normalized(), angle * amount)


# Limits how far a rotation turns, in radians.
static func clamp_rotation(q: Quaternion, max_angle: float) -> Quaternion:
	if q.w < 0.0:
		q = -q
	var angle := q.get_angle()
	if angle <= max_angle or angle < 0.00001:
		return q
	return Quaternion(q.get_axis().normalized(), max_angle)


# Keeps a vector under `limit` long, easing into the limit instead of
# stopping dead (feels like a cable or piston reaching its end).
static func soft_limit(v: Vector3, limit: float) -> Vector3:
	var l := v.length()
	if l < 0.00001 or limit <= 0.0:
		return Vector3.ZERO if limit <= 0.0 else v
	var soft := limit * tanh(l / limit)
	return v * (soft / l)


# Classic two-bone IK (shoulder -> elbow -> wrist). Returns the elbow
# position. `bend_hint` says which way the elbow should point.
static func two_bone_elbow(shoulder: Vector3, target: Vector3, upper: float, fore: float,
		bend_hint: Vector3) -> Vector3:
	var to_target := target - shoulder
	var dist := clampf(to_target.length(), absf(upper - fore) + 0.001, upper + fore - 0.001)
	var dir := to_target.normalized() if to_target.length() > 0.00001 else Vector3.FORWARD
	# Angle at the shoulder between "straight at the target" and the upper arm.
	var cos_a := clampf((upper * upper + dist * dist - fore * fore) / (2.0 * upper * dist), -1.0, 1.0)
	var bend := bend_hint - dir * dir.dot(bend_hint)
	if bend.length_squared() < 0.000001:
		bend = dir.cross(Vector3.RIGHT)
		if bend.length_squared() < 0.000001:
			bend = dir.cross(Vector3.UP)
	bend = bend.normalized()
	return shoulder + dir * (cos_a * upper) + bend * (sqrt(1.0 - cos_a * cos_a) * upper)

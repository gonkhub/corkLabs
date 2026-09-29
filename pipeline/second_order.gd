# A "second-order" spring follower: something that chases a target the way a
# heavy object on a spring would. This is how robots get weight and
# personality. Three knobs:
#
#   frequency (Hz)  how quickly it responds. 1.5 = sluggish hauler, 6 = crisp.
#   damping         0 = wobbles forever, 0.5 = overshoots then settles,
#                   1 = arrives without overshoot, >1 = slow and syrupy.
#   response        0 = eases in, 1 = starts moving immediately,
#                   >1 = overshoots the start, <0 = wind-up (moves backwards first).
#
# Based on t3ssel8r's "Giving Personality to Procedural Animations using Math".
# Works on Vector4; helpers wrap Vector3 positions, Quaternion rotations and floats.
class_name SecondOrder
extends RefCounted

# At or above this frequency the spring is bypassed (output = target).
const PASSTHROUGH_HZ := 1000.0

var frequency := 2.0
var damping := 1.0
var response := 0.0

var _k1 := 0.0
var _k2 := 0.0
var _k3 := 0.0
var _xp := Vector4.ZERO   # previous target
var _y := Vector4.ZERO    # current output
var _yd := Vector4.ZERO   # current output velocity


func _init(p_frequency := 2.0, p_damping := 1.0, p_response := 0.0) -> void:
	configure(p_frequency, p_damping, p_response)


func configure(p_frequency: float, p_damping: float, p_response: float) -> void:
	frequency = maxf(p_frequency, 0.001)
	damping = p_damping
	response = p_response
	_k1 = damping / (PI * frequency)
	_k2 = 1.0 / ((TAU * frequency) * (TAU * frequency))
	_k3 = response * damping / (TAU * frequency)


# Snap to a value with no motion (use at the start of a take).
func reset(x: Vector4) -> void:
	_xp = x
	_y = x
	_yd = Vector4.ZERO


func update(dt: float, x: Vector4) -> Vector4:
	if frequency >= PASSTHROUGH_HZ or dt <= 0.0:
		_xp = x
		_y = x
		_yd = Vector4.ZERO
		return x
	var xd := (x - _xp) / dt
	_xp = x
	# Keeps the simulation stable even when frames are long.
	var k2_stable := maxf(_k2, maxf(dt * dt / 2.0 + dt * _k1 / 2.0, dt * _k1))
	_y += dt * _yd
	_yd += dt * (x + _k3 * xd - _y - _k1 * _yd) / k2_stable
	return _y


# --- Typed helpers ----------------------------------------------------------

func reset_vec3(v: Vector3) -> void:
	reset(Vector4(v.x, v.y, v.z, 0.0))


func update_vec3(dt: float, v: Vector3) -> Vector3:
	var r := update(dt, Vector4(v.x, v.y, v.z, 0.0))
	return Vector3(r.x, r.y, r.z)


func reset_float(f: float) -> void:
	reset(Vector4(f, 0.0, 0.0, 0.0))


func update_float(dt: float, f: float) -> float:
	return update(dt, Vector4(f, 0.0, 0.0, 0.0)).x


func reset_quat(q: Quaternion) -> void:
	reset(Vector4(q.x, q.y, q.z, q.w))


# Quaternions q and -q are the same rotation; flip the target onto the same
# side as the last one so the spring never takes the long way round.
func update_quat(dt: float, q: Quaternion) -> Quaternion:
	var v := Vector4(q.x, q.y, q.z, q.w)
	if v.dot(_xp) < 0.0:
		v = -v
	var r := update(dt, v)
	var out := Quaternion(r.x, r.y, r.z, r.w)
	return out.normalized() if out.length_squared() > 0.000001 else Quaternion.IDENTITY

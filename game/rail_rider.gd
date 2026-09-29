# Moves along a rail (put this on a PathFollow3D under a Path3D) and makes
# whatever hangs from it swing like a pendulum when it speeds up, brakes or
# takes a corner. This is the "runtime layer" from the pipeline doc: rail
# travel and sway are never baked, so they react to whatever the robot does.
#
# Children of the "Swing" node hang from the rail and swing.
class_name RailRider
extends PathFollow3D

signal arrived

## Top speed along the rail, in m/s.
@export var max_speed := 1.2
## Acceleration and braking, in m/s^2. Heavy robots: low values.
@export var acceleration := 0.8
## Keep driving round the rail forever at max_speed (a patrol).
@export var patrol := false

@export_group("Swing")
## Length of the pendulum (rail to the robot's centre of mass), in meters.
@export var pendulum_length := 1.0
## How quickly swinging dies away. 0 = swings forever.
@export var swing_damping := 1.2
## Exaggerates the swing (1 = physical).
@export var swing_amount := 1.0

var speed := 0.0
var target := -1.0            # target progress in meters; < 0 = none
var swing: Node3D
var _prev_pos := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _disp := Vector2.ZERO      # pendulum bob offset: x = sideways, y = forwards
var _disp_vel := Vector2.ZERO
var _started := false


func _ready() -> void:
	rotation_mode = PathFollow3D.ROTATION_Y
	swing = get_node_or_null("Swing")


## Drive to a point along the rail (meters from the rail's start).
func travel_to(distance: float) -> void:
	target = distance


func is_moving() -> bool:
	return absf(speed) > 0.01 or target >= 0.0


func rail_length() -> float:
	var path := get_parent() as Path3D
	return path.curve.get_baked_length() if path and path.curve else 0.0


func _physics_process(delta: float) -> void:
	_drive(delta)
	_swing(delta)


func _drive(delta: float) -> void:
	if patrol:
		speed = move_toward(speed, max_speed, acceleration * delta)
	elif target >= 0.0:
		var to_go := target - progress
		var dir := signf(to_go)
		# Brake in time: v^2 = 2 a d.
		var stop_speed := sqrt(2.0 * acceleration * absf(to_go))
		var want := dir * minf(max_speed, stop_speed)
		speed = move_toward(speed, want, acceleration * delta)
		if absf(to_go) < 0.01 and absf(speed) < 0.05:
			progress = target
			speed = 0.0
			target = -1.0
			arrived.emit()
	else:
		speed = move_toward(speed, 0.0, acceleration * delta)
	progress += speed * delta


# Small-angle pendulum driven by the carriage's acceleration (in its own
# frame): speeding up swings the robot back, braking swings it forward,
# corners swing it outwards.
func _swing(delta: float) -> void:
	if swing == null or delta <= 0.0:
		return
	var pos := global_position
	if not _started:
		_prev_pos = pos
		_prev_vel = Vector3.ZERO
		_started = true
		return
	var vel := (pos - _prev_pos) / delta
	var acc := (vel - _prev_vel) / delta
	_prev_pos = pos
	_prev_vel = vel
	var local_acc := global_transform.basis.inverse() * acc
	# Forwards is -Z. x = sideways (+X), y = forwards.
	var a := Vector2(local_acc.x, -local_acc.z) * swing_amount
	var omega2 := 9.81 / maxf(pendulum_length, 0.05)
	var accel := -omega2 * _disp - swing_damping * _disp_vel - a
	_disp_vel += accel * delta
	_disp += _disp_vel * delta
	_disp = _disp.limit_length(pendulum_length * 0.6)
	# Rotating about X by +angle moves the bob forwards; about Z by +angle moves it to +X.
	swing.rotation = Vector3(asin(clampf(_disp.y / pendulum_length, -1, 1)), 0.0,
		asin(clampf(_disp.x / pendulum_length, -1, 1)))

# A motorised security camera: it has a home view (aimed at `look_point`),
# and the supervisor can pan, tilt and zoom it from the Cameras app. The head
# eases towards where it's told to point, like a real PTZ camera. A camera
# with a `target` can auto-track it (Cam 3 follows Hauler); any manual move
# switches auto-tracking off.
#
# Pointing a camera is only looking: it never changes the facility or costs
# facility time.
class_name SecurityCamera
extends Camera3D

## Name shown on feeds ("Floor overview").
@export var display_name := "Camera"
## Point to aim at (world space) in the home view.
@export var look_point := Vector3.ZERO
## Optional node to track.
@export var target: Node3D
## How quickly it follows the target when auto-tracking (per second).
@export var pan_speed := 1.5

@export_group("Pan / tilt / zoom")
## Furthest it pans left/right of home, in degrees.
@export_range(0.0, 180.0, 1.0) var pan_limit_deg := 70.0
## Furthest it tilts up/down from home, in degrees.
@export_range(0.0, 89.0, 1.0) var tilt_limit_deg := 40.0
## Narrowest field of view (most zoomed in), in degrees.
@export_range(5.0, 90.0, 1.0) var min_fov := 18.0
## How fast the motor turns towards the requested direction.
@export var motor_speed := 6.0

## Requested pan/tilt (degrees from home) and field of view.
var pan := 0.0
var tilt := 0.0
var zoom_fov := 60.0
var auto_track := false
## False while the tracked robot is out of this camera's room (the world
## sets it): the camera waits at its home view instead of staring at a wall.
var target_in_view := true

## How much faster the head turns while framing a moment.
const FRAME_SNAP := 6.0
## Framing a subject for a moment (frame()): seconds left, and what to put back.
var _frame_left := 0.0
var _frame_restore := {}
var _home: Basis
var _home_fov := 60.0
var _pan_now := 0.0
var _tilt_now := 0.0
var _tracking := false


func _ready() -> void:
	look_at(look_point, Vector3.UP)
	_home = global_transform.basis
	_home_fov = fov
	zoom_fov = fov
	auto_track = target != null


## Points at `subject` (and zooms to `fov_deg`, unless it's negative) for
## `seconds` (a moment worth seeing: a unit that just fixed this camera,
## looking into it), then goes back to how it was.
func frame(subject: Node3D, fov_deg: float, seconds: float) -> void:
	if _frame_left <= 0.0:
		_frame_restore = {"target": target, "auto_track": auto_track, "zoom": zoom_fov}
	target = subject
	auto_track = true
	target_in_view = true
	if fov_deg > 0.0:
		zoom_fov = fov_deg
	_frame_left = seconds


func framing() -> bool:
	return _frame_left > 0.0


func _process(delta: float) -> void:
	if _frame_left > 0.0:
		_frame_left -= delta
		if _frame_left <= 0.0:
			target = _frame_restore.get("target")
			auto_track = bool(_frame_restore.get("auto_track", false))
			zoom_fov = float(_frame_restore.get("zoom", _home_fov))
			if not auto_track:
				pan = 0.0
				tilt = 0.0
	var k := clampf(motor_speed * delta, 0.0, 1.0)
	fov = lerpf(fov, zoom_fov, k)
	if auto_track and target and target_in_view:
		_tracking = true
		var want := global_transform.looking_at(target.global_position + Vector3(0, -0.6, 0), Vector3.UP)
		var speed := pan_speed * (FRAME_SNAP if _frame_left > 0.0 else 1.0)   # framing a moment: snap to it
		global_transform.basis = global_transform.basis.slerp(want.basis, clampf(speed * delta, 0.0, 1.0)).orthonormalized()
		return
	if auto_track and not target_in_view:
		if _tracking:
			_take_over()        # start from where tracking left the head...
			auto_track = true   # ...but keep tracking for when it comes back
		pan = 0.0
		tilt = 0.0
	_tracking = auto_track and target != null and target_in_view
	_pan_now = lerpf(_pan_now, pan, k)
	_tilt_now = lerpf(_tilt_now, tilt, k)
	global_transform.basis = _aim(_pan_now, _tilt_now)


## Moves the head by this many degrees (manual control: stops auto-tracking).
func nudge(pan_deg: float, tilt_deg: float) -> void:
	if auto_track:
		_take_over()
	pan = clampf(pan + pan_deg, -pan_limit_deg, pan_limit_deg)
	tilt = clampf(tilt + tilt_deg, -tilt_limit_deg, tilt_limit_deg)


## factor < 1 zooms in, > 1 zooms out.
func zoom_by(factor: float) -> void:
	zoom_fov = clampf(zoom_fov * factor, min_fov, _home_fov)


## Back to the home view (and auto-tracking, if it has a target).
func reset_view() -> void:
	pan = 0.0
	tilt = 0.0
	zoom_fov = _home_fov
	auto_track = target != null


func set_auto_track(on: bool) -> void:
	if on and target:
		auto_track = true
	elif auto_track:
		_take_over()


func can_track() -> bool:
	return target != null


## 1 = home view, 2 = twice as close...
func zoom_level() -> float:
	return tan(deg_to_rad(_home_fov) * 0.5) / tan(deg_to_rad(zoom_fov) * 0.5)


# Stop tracking, keeping the head where tracking left it.
func _take_over() -> void:
	auto_track = false
	var f := -global_transform.basis.z
	var h := -_home.z
	# Pan: angle around world up between home and now; tilt: difference in elevation.
	pan = clampf(rad_to_deg(atan2(h.cross(f).y, h.x * f.x + h.z * f.z)) if Vector2(f.x, f.z).length() > 0.01 else 0.0,
		-pan_limit_deg, pan_limit_deg)
	tilt = clampf(rad_to_deg(asin(clampf(f.y, -1, 1)) - asin(clampf(h.y, -1, 1))), -tilt_limit_deg, tilt_limit_deg)
	_pan_now = pan
	_tilt_now = tilt


func _aim(pan_deg: float, tilt_deg: float) -> Basis:
	# Pan about world up, tilt about the camera's own right axis.
	var b := Basis(Vector3.UP, deg_to_rad(pan_deg)) * _home
	return Basis(b.x, deg_to_rad(tilt_deg)) * b

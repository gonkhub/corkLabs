# The 1-euro filter (Casiez et al.): smooths jitter out of a live signal.
# Slow movement -> heavy smoothing (kills tracking shimmer).
# Fast movement -> light smoothing (so it doesn't lag behind).
#
# Only used for LIVE preview (the mirror robot). Baking uses zero-lag
# offline smoothing instead (see take_cleanup.gd).
#
# Works on Vector4 so one class handles positions (x, y, z, 0) and
# rotations (quaternion x, y, z, w).
class_name OneEuroFilter
extends RefCounted

var min_cutoff := 1.0   # Hz. Lower = smoother when still, but laggier.
var beta := 0.0         # How fast the cutoff rises with speed. Higher = less lag on fast moves.
var d_cutoff := 1.0     # Hz. Smoothing of the speed estimate itself; rarely needs changing.

var _x := Vector4.ZERO
var _dx := Vector4.ZERO
var _has_value := false


func _init(p_min_cutoff := 1.0, p_beta := 0.0, p_d_cutoff := 1.0) -> void:
	min_cutoff = p_min_cutoff
	beta = p_beta
	d_cutoff = p_d_cutoff


func reset() -> void:
	_has_value = false


func filter(x: Vector4, dt: float) -> Vector4:
	if not _has_value or dt <= 0.0:
		_x = x
		_dx = Vector4.ZERO
		_has_value = true
		return x
	var dx := (x - _x) / dt
	_dx = _dx.lerp(dx, _alpha(d_cutoff, dt))
	var cutoff := min_cutoff + beta * _dx.length()
	_x = _x.lerp(x, _alpha(cutoff, dt))
	return _x


# Last filtered value (used to keep quaternion signs consistent).
func value() -> Vector4:
	return _x


static func _alpha(cutoff: float, dt: float) -> float:
	var tau := 1.0 / (TAU * cutoff)
	return 1.0 / (1.0 + tau / dt)

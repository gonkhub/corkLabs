# Applies 1-euro filters to the head and hand poses of live frames.
# Used by the recorder's mirror robot so live preview doesn't shimmer.
# Triggers, sticks and buttons pass through untouched.
class_name FrameSmoother
extends RefCounted

# Positions are in meters, so beta is in "per meter/second".
var pos_min_cutoff := 1.5
var pos_beta := 1.5
var rot_min_cutoff := 1.5
var rot_beta := 0.5

var _filters := {}


func reset() -> void:
	_filters.clear()


func smooth(f: PerformanceFrame, dt: float) -> PerformanceFrame:
	var out := f.duplicate_frame()
	out.head = _smooth_xform("head", f.head, dt)
	out.left = _smooth_xform("left", f.left, dt)
	out.right = _smooth_xform("right", f.right, dt)
	return out


func _smooth_xform(key: String, x: Transform3D, dt: float) -> Transform3D:
	if not _filters.has(key):
		_filters[key] = [
			OneEuroFilter.new(pos_min_cutoff, pos_beta),
			OneEuroFilter.new(rot_min_cutoff, rot_beta),
		]
	var pf: OneEuroFilter = _filters[key][0]
	var rf: OneEuroFilter = _filters[key][1]

	var p := pf.filter(Vector4(x.origin.x, x.origin.y, x.origin.z, 0.0), dt)
	var q := x.basis.get_rotation_quaternion()
	var qv := Vector4(q.x, q.y, q.z, q.w)
	if qv.dot(rf.value()) < 0.0:
		qv = -qv
	var r := rf.filter(qv, dt)
	var rq := Quaternion(r.x, r.y, r.z, r.w).normalized()
	return Transform3D(Basis(rq), Vector3(p.x, p.y, p.z))

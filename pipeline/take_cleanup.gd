# Turns a raw take into a clean one, following its CleanupRecipe.
# The input take is never modified; a new take comes out.
#
# Steps, in order:
#   1. resample to an even frame rate (headset frames arrive unevenly)
#   2. trim (including the reach for the MENU button that stopped recording)
#   3. repair short tracking dropouts
#   4. zero-lag smoothing (looks forwards AND backwards, so no delay)
#   5. deadzones on sticks and triggers
#   6. loop closing (optional): cut at the best-matching point and crossfade
class_name TakeCleanup
extends RefCounted

## Seconds before the MENU press where the reach toward the button starts.
const STOP_REACH_SECONDS := 0.6
## Only look for the stop press in this many seconds at the end.
const STOP_SEARCH_SECONDS := 3.0


# Returns {"take": PerformanceTake, "report": Dictionary}.
static func run(take: PerformanceTake, recipe: CleanupRecipe = null, rate := 90.0) -> Dictionary:
	if recipe == null:
		recipe = take.recipe if take.recipe else CleanupRecipe.new()
	var report := {
		"source_frames": take.frame_count(),
		"gaps_repaired": 0,
		"gaps_left": [],
		"trim": [0.0, take.duration()],
		"loop_point": -1.0,
		"loop_error": -1.0,
		"notes": [],
	}
	var frames := resample(take, rate)
	if frames.size() < 2:
		report.notes.append("take too short to clean")
		return {"take": _to_take(take, frames, rate, recipe), "report": report}

	frames = _trim(frames, rate, recipe, report)
	_repair_gaps(frames, rate, recipe.max_gap_repair, report)
	if recipe.smoothing > 0.0:
		frames = _smooth(frames, recipe.smoothing * rate)
	_deadzones(frames, recipe)
	if recipe.loop:
		frames = _close_loop(frames, rate, recipe, report)
	return {"take": _to_take(take, frames, rate, recipe), "report": report}


# Evenly spaced frames from the take's (uneven) samples.
static func resample(take: PerformanceTake, rate: float) -> Array[PerformanceFrame]:
	var out: Array[PerformanceFrame] = []
	if take.frame_count() == 0:
		return out
	var count := int(floor(take.duration() * rate)) + 1
	for i in count:
		out.append(take.sample(i / rate))
	return out


static func _trim(frames: Array[PerformanceFrame], rate: float, recipe: CleanupRecipe,
		report: Dictionary) -> Array[PerformanceFrame]:
	var n := frames.size()
	var duration := (n - 1) / rate
	var start_t := recipe.trim_start
	var end_t := duration - recipe.trim_end

	if recipe.trim_stop_reach:
		# Find the start of the final MENU press near the end.
		var i := n - 1
		var search_from := maxi(0, n - int(STOP_SEARCH_SECONDS * rate))
		while i >= search_from and not (frames[i].left_buttons & PerformanceFrame.BTN_MENU):
			i -= 1
		if i >= search_from:
			while i > 0 and (frames[i - 1].left_buttons & PerformanceFrame.BTN_MENU):
				i -= 1
			var reach_t := i / rate - STOP_REACH_SECONDS
			if reach_t > start_t + 0.2:
				end_t = minf(end_t, reach_t)
				report.notes.append("cut the stop-button reach at %.2f s" % reach_t)

	var a := clampi(int(round(start_t * rate)), 0, n - 1)
	var b := clampi(int(round(end_t * rate)), a, n - 1)
	report.trim = [a / rate, b / rate]
	return frames.slice(a, b + 1)


# Bridges stretches where a controller lost tracking (confidence 0).
static func _repair_gaps(frames: Array[PerformanceFrame], rate: float, max_gap: float,
		report: Dictionary) -> void:
	for side in ["left", "right"]:
		var conf_key: String = side + "_confidence"
		var n := frames.size()
		var i := 0
		while i < n:
			if frames[i].get(conf_key) != 0:
				i += 1
				continue
			var gap_start := i
			while i < n and frames[i].get(conf_key) == 0:
				i += 1
			var gap_end := i - 1   # last untracked frame
			var gap_len := (gap_end - gap_start + 1) / rate
			var before := gap_start - 1
			var after := gap_end + 1
			if gap_len > max_gap or (before < 0 and after >= n):
				report.gaps_left.append("%s hand %.2f-%.2f s" % [side, gap_start / rate, gap_end / rate])
				continue
			for k in range(gap_start, gap_end + 1):
				var pose: Transform3D
				if before < 0:
					pose = frames[after].get(side)
				elif after >= n:
					pose = frames[before].get(side)
				else:
					var w := float(k - before) / float(after - before)
					w = w * w * (3.0 - 2.0 * w)   # smoothstep: eases in and out
					pose = PerformanceFrame.blend_xform(frames[before].get(side), frames[after].get(side), w)
				frames[k].set(side, pose)
				frames[k].set(conf_key, 1)
			report.gaps_repaired += 1


# Gaussian smoothing centred on each frame. Because it averages frames on
# BOTH sides, motion isn't delayed the way a live filter delays it.
static func _smooth(frames: Array[PerformanceFrame], sigma_frames: float) -> Array[PerformanceFrame]:
	var radius := int(ceil(sigma_frames * 3.0))
	if radius < 1:
		return frames
	var weights := PackedFloat32Array()
	for k in range(-radius, radius + 1):
		weights.append(exp(-0.5 * (k * k) / (sigma_frames * sigma_frames)))
	var n := frames.size()
	var out: Array[PerformanceFrame] = []
	for i in n:
		var f := frames[i].duplicate_frame()
		for side in ["head", "left", "right"]:
			f.set(side, _smooth_xform_at(frames, i, side, radius, weights))
		out.append(f)
	return out


static func _smooth_xform_at(frames: Array[PerformanceFrame], i: int, side: String, radius: int,
		weights: PackedFloat32Array) -> Transform3D:
	var n := frames.size()
	var centre: Transform3D = frames[i].get(side)
	var cq := centre.basis.get_rotation_quaternion()
	var cv := Vector4(cq.x, cq.y, cq.z, cq.w)
	var pos := Vector3.ZERO
	var rot := Vector4.ZERO
	var total := 0.0
	for k in range(-radius, radius + 1):
		var j := clampi(i + k, 0, n - 1)
		var w := weights[k + radius]
		var x: Transform3D = frames[j].get(side)
		var q := x.basis.get_rotation_quaternion()
		var qv := Vector4(q.x, q.y, q.z, q.w)
		if qv.dot(cv) < 0.0:
			qv = -qv
		pos += x.origin * w
		rot += qv * w
		total += w
	pos /= total
	var rq := Quaternion(rot.x, rot.y, rot.z, rot.w).normalized()
	return Transform3D(Basis(rq), pos)


static func _deadzones(frames: Array[PerformanceFrame], recipe: CleanupRecipe) -> void:
	for f in frames:
		f.left_stick = _stick_dz(f.left_stick, recipe.stick_deadzone)
		f.right_stick = _stick_dz(f.right_stick, recipe.stick_deadzone)
		f.left_trigger = _axis_dz(f.left_trigger, recipe.trigger_deadzone)
		f.right_trigger = _axis_dz(f.right_trigger, recipe.trigger_deadzone)
		f.left_grip = _axis_dz(f.left_grip, recipe.trigger_deadzone)
		f.right_grip = _axis_dz(f.right_grip, recipe.trigger_deadzone)


static func _stick_dz(v: Vector2, dz: float) -> Vector2:
	var l := v.length()
	if l <= dz or dz >= 1.0:
		return Vector2.ZERO if l <= dz else v
	return v * ((minf(l, 1.0) - dz) / (1.0 - dz)) / l


static func _axis_dz(v: float, dz: float) -> float:
	if v <= dz:
		return 0.0
	return clampf((v - dz) / (1.0 - dz), 0.0, 1.0)


# Finds the frame near the end that best matches the first frame (pose and
# motion), cuts there, and crossfades so the loop seam can't be seen:
# the first `fade` frames of the loop are blended from "what came after the
# cut" into "the real start", so the end flows straight back into the start.
static func _close_loop(frames: Array[PerformanceFrame], rate: float, recipe: CleanupRecipe,
		report: Dictionary) -> Array[PerformanceFrame]:
	var n := frames.size()
	var fade := maxi(1, int(round(recipe.loop_crossfade * rate)))
	var search := int(round(recipe.loop_search * rate))
	var lo := maxi(fade + 2, n - fade - search)
	var hi := n - fade - 1
	if hi <= lo:
		report.notes.append("too short to loop with a %.2f s crossfade" % recipe.loop_crossfade)
		return frames

	var best_k := hi
	var best_cost := INF
	for k in range(lo, hi + 1):
		var cost := _pose_distance(frames[k], frames[0])
		cost += 0.1 * _motion_distance(frames[k], frames[k + 1], frames[0], frames[1]) * rate
		if cost < best_cost:
			best_cost = cost
			best_k = k

	var out: Array[PerformanceFrame] = []
	for i in best_k:
		out.append(frames[i])
	for m in fade:
		var w := float(m) / float(fade)
		w = w * w * (3.0 - 2.0 * w)
		out[m] = PerformanceFrame.blend(frames[best_k + m], frames[m], w)
	report.loop_point = best_k / rate
	report.loop_error = best_cost
	return out


static func _pose_distance(a: PerformanceFrame, b: PerformanceFrame) -> float:
	var d := 0.0
	for side in ["head", "left", "right"]:
		var x: Transform3D = a.get(side)
		var y: Transform3D = b.get(side)
		d += x.origin.distance_to(y.origin)
		d += 0.3 * x.basis.get_rotation_quaternion().angle_to(y.basis.get_rotation_quaternion())
	return d


static func _motion_distance(a0: PerformanceFrame, a1: PerformanceFrame, b0: PerformanceFrame,
		b1: PerformanceFrame) -> float:
	var d := 0.0
	for side in ["head", "left", "right"]:
		var va: Vector3 = (a1.get(side) as Transform3D).origin - (a0.get(side) as Transform3D).origin
		var vb: Vector3 = (b1.get(side) as Transform3D).origin - (b0.get(side) as Transform3D).origin
		d += va.distance_to(vb)
	return d


static func _to_take(source: PerformanceTake, frames: Array[PerformanceFrame], rate: float,
		recipe: CleanupRecipe) -> PerformanceTake:
	var t := PerformanceTake.new()
	t.created = source.created
	t.note = source.note
	t.robot_id = source.robot_id
	t.clip_name = source.clip_name
	t.eye_height = source.eye_height
	t.overdub_of = source.overdub_of
	t.recipe = recipe
	for i in frames.size():
		t.append(i / rate, frames[i])
	return t

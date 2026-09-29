# A recorded take: every PerformanceFrame captured during one recording,
# stored as raw data. This is the "source of truth" from the pipeline doc.
# Robots' animations get baked FROM takes later; takes are never edited.
#
# Each channel is its own packed array (a compact list of numbers), one
# entry per captured frame, like parallel tracks in a DAW session.
class_name PerformanceTake
extends Resource

# Each tracker (head, left, right) stores 7 numbers per frame:
# position x, y, z, then rotation as a quaternion x, y, z, w.
const STRIDE := 7

@export var created := ""   # date and time the take was recorded
@export var note := ""      # free text, for you

## Which robot this take was performed for (folder name under res://robots/).
@export var robot_id := ""
## Name of the baked animation clip, e.g. "idle_scan" or "act_weld".
## Empty = use the take's file name.
@export var clip_name := ""
## Your standing eye height, measured during the countdown. Robots measure
## head movement relative to this. 0 = unknown (the robot's default is used).
@export var eye_height := 0.0
## Cleanup applied before baking. Editable any time; the raw data above never changes.
@export var recipe: CleanupRecipe
## Takes that were playing along while this one was recorded (all started
## at the same moment as this take).
@export var overdub_of := PackedStringArray()

# Seconds since the take started, one per frame. Frames are not perfectly
# evenly spaced (the headset can drop frames), which is why we keep these.
@export var sample_times := PackedFloat32Array()

@export var head_track := PackedFloat32Array()
@export var left_track := PackedFloat32Array()
@export var right_track := PackedFloat32Array()

@export var left_confidence := PackedByteArray()
@export var left_trigger := PackedFloat32Array()
@export var left_grip := PackedFloat32Array()
@export var left_stick := PackedVector2Array()
@export var left_buttons := PackedByteArray()

@export var right_confidence := PackedByteArray()
@export var right_trigger := PackedFloat32Array()
@export var right_grip := PackedFloat32Array()
@export var right_stick := PackedVector2Array()
@export var right_buttons := PackedByteArray()


func frame_count() -> int:
	return sample_times.size()


func duration() -> float:
	return sample_times[sample_times.size() - 1] if frame_count() > 0 else 0.0


# Average frames per second actually captured.
func sample_rate() -> float:
	return (frame_count() - 1) / duration() if duration() > 0.0 else 0.0


# Adds one frame to the end of the take.
func append(time: float, f: PerformanceFrame) -> void:
	sample_times.append(time)
	head_track.append_array(_pack(f.head))
	left_track.append_array(_pack(f.left))
	right_track.append_array(_pack(f.right))

	left_confidence.append(f.left_confidence)
	left_trigger.append(f.left_trigger)
	left_grip.append(f.left_grip)
	left_stick.append(f.left_stick)
	left_buttons.append(f.left_buttons)

	right_confidence.append(f.right_confidence)
	right_trigger.append(f.right_trigger)
	right_grip.append(f.right_grip)
	right_stick.append(f.right_stick)
	right_buttons.append(f.right_buttons)


# Returns the performance at any moment, blending smoothly between the two
# recorded frames on either side of it (like sample interpolation in audio).
# Buttons and tracking confidence don't blend; they hold the earlier value.
func sample(time: float) -> PerformanceFrame:
	var f := PerformanceFrame.new()
	var n := frame_count()
	if n == 0:
		return f
	if n == 1:
		return _frame_at(0)

	time = clampf(time, sample_times[0], sample_times[n - 1])
	# Binary search: index of the first frame later than `time`.
	var j := clampi(sample_times.bsearch(time, false), 1, n - 1)
	var i := j - 1
	var span := sample_times[j] - sample_times[i]
	var w := 0.0 if span <= 0.0 else clampf((time - sample_times[i]) / span, 0.0, 1.0)

	f.head = _blend(head_track, i, j, w)
	f.left = _blend(left_track, i, j, w)
	f.right = _blend(right_track, i, j, w)

	f.left_confidence = left_confidence[i]
	f.left_trigger = lerpf(left_trigger[i], left_trigger[j], w)
	f.left_grip = lerpf(left_grip[i], left_grip[j], w)
	f.left_stick = left_stick[i].lerp(left_stick[j], w)
	f.left_buttons = left_buttons[i]

	f.right_confidence = right_confidence[i]
	f.right_trigger = lerpf(right_trigger[i], right_trigger[j], w)
	f.right_grip = lerpf(right_grip[i], right_grip[j], w)
	f.right_stick = right_stick[i].lerp(right_stick[j], w)
	f.right_buttons = right_buttons[i]
	return f


# The exact frame stored at index i, with no blending.
func _frame_at(i: int) -> PerformanceFrame:
	var f := PerformanceFrame.new()
	f.head = _blend(head_track, i, i, 0.0)
	f.left = _blend(left_track, i, i, 0.0)
	f.right = _blend(right_track, i, i, 0.0)
	f.left_confidence = left_confidence[i]
	f.left_trigger = left_trigger[i]
	f.left_grip = left_grip[i]
	f.left_stick = left_stick[i]
	f.left_buttons = left_buttons[i]
	f.right_confidence = right_confidence[i]
	f.right_trigger = right_trigger[i]
	f.right_grip = right_grip[i]
	f.right_stick = right_stick[i]
	f.right_buttons = right_buttons[i]
	return f


static func _pack(x: Transform3D) -> PackedFloat32Array:
	var q := x.basis.get_rotation_quaternion()
	return PackedFloat32Array([x.origin.x, x.origin.y, x.origin.z, q.x, q.y, q.z, q.w])


# Position blends in a straight line; rotation blends along the shortest arc
# (slerp), so hands never "wobble" between two recorded orientations.
static func _blend(track: PackedFloat32Array, i: int, j: int, w: float) -> Transform3D:
	var a := i * STRIDE
	var b := j * STRIDE
	var pa := Vector3(track[a], track[a + 1], track[a + 2])
	var pb := Vector3(track[b], track[b + 1], track[b + 2])
	var qa := Quaternion(track[a + 3], track[a + 4], track[a + 5], track[a + 6]).normalized()
	var qb := Quaternion(track[b + 3], track[b + 4], track[b + 5], track[b + 6]).normalized()
	return Transform3D(Basis(qa.slerp(qb, w)), pa.lerp(pb, w))

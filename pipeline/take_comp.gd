# Comping: build a take from parts of two takes, like comping vocal takes
# in a DAW. Channel groups:
#   head   the head pose (body/core/neck/eye follow it)
#   left   left hand pose + left trigger/grip
#   right  right hand pose + right trigger/grip
#   face   both sticks + all face buttons (eye look, lid, lens, blink, flash)
#
# The punch-in recorder uses this: re-perform just the right arm while the
# rest of the old take plays, then comp the new arm into the old take.
class_name TakeComp
extends RefCounted

const GROUPS := ["head", "left", "right", "face"]


# A copy of `base` with `groups` taken from `overlay` between start and end
# (seconds on base's timeline), faded in/out over `fade` seconds.
# overlay time = base time - offset.
static func comp(base: PerformanceTake, overlay: PerformanceTake, groups: PackedStringArray,
		start := 0.0, end := -1.0, fade := 0.3, offset := 0.0, rate := 90.0) -> PerformanceTake:
	if end < 0.0:
		end = offset + overlay.duration()
	var out := PerformanceTake.new()
	out.created = base.created
	out.robot_id = base.robot_id
	out.clip_name = base.clip_name
	out.eye_height = base.eye_height
	out.recipe = base.recipe
	out.overdub_of = base.overdub_of
	out.note = ("%s\n" % base.note if base.note else "") + "comp: %s from another take, %.2f-%.2f s" % [",".join(groups), start, end]
	var count := int(floor(base.duration() * rate)) + 1
	for i in count:
		var t := i / rate
		var f := base.sample(t)
		var w := _weight(t, start, end, fade)
		if w > 0.0:
			f = merge(f, overlay.sample(t - offset), groups, w)
		out.append(t, f)
	return out


# `base` with the given groups blended toward `over` by w (0..1).
static func merge(base: PerformanceFrame, over: PerformanceFrame, groups: PackedStringArray, w := 1.0) -> PerformanceFrame:
	var f := base.duplicate_frame()
	var mix := PerformanceFrame.blend(base, over, w)
	var switch_src := over if w >= 0.5 else base
	for g in groups:
		match g:
			"head":
				f.head = mix.head
			"left":
				f.left = mix.left
				f.left_trigger = mix.left_trigger
				f.left_grip = mix.left_grip
				f.left_confidence = switch_src.left_confidence
			"right":
				f.right = mix.right
				f.right_trigger = mix.right_trigger
				f.right_grip = mix.right_grip
				f.right_confidence = switch_src.right_confidence
			"face":
				f.left_stick = mix.left_stick
				f.right_stick = mix.right_stick
				f.left_buttons = switch_src.left_buttons
				f.right_buttons = switch_src.right_buttons
	return f


static func _weight(t: float, start: float, end: float, fade: float) -> float:
	if t < start or t > end:
		return 0.0
	if fade <= 0.0:
		return 1.0
	var w := minf((t - start) / fade, (end - t) / fade)
	w = clampf(w, 0.0, 1.0)
	return w * w * (3.0 - 2.0 * w)

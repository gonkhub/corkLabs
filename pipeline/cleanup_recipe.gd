@tool
# How a take gets cleaned up before baking. Stored inside each take, and
# non-destructive: the raw recording is never changed, so any setting here
# can be tweaked and the take rebaked. Think clip gain and fades in a DAW.
class_name CleanupRecipe
extends Resource

@export_group("Trim")
## Seconds cut from the start.
@export_range(0.0, 60.0, 0.01, "or_greater") var trim_start := 0.0
## Seconds cut from the end.
@export_range(0.0, 60.0, 0.01, "or_greater") var trim_end := 0.0
## Also cut the reach for the MENU button that stopped the recording.
@export var trim_stop_reach := true

@export_group("Repair")
## Tracking gaps up to this long get bridged smoothly. Longer ones are
## left as-is and reported (re-record or punch in).
@export_range(0.0, 2.0, 0.01) var max_gap_repair := 0.3

@export_group("Smoothing")
## Zero-lag smoothing strength, in seconds. 0 = off. 0.02-0.05 removes
## tracking jitter; above 0.1 starts softening real motion.
@export_range(0.0, 0.3, 0.005) var smoothing := 0.03

@export_group("Inputs")
## Stick values smaller than this read as 0 (stops drift twitching the face).
@export_range(0.0, 0.5, 0.01) var stick_deadzone := 0.12
## Trigger and grip values smaller than this read as 0.
@export_range(0.0, 0.3, 0.01) var trigger_deadzone := 0.03

@export_group("Loop")
## Make the clip loop seamlessly (for idles and fidgets).
@export var loop := false
## Length of the crossfade that hides the loop seam, in seconds.
@export_range(0.05, 2.0, 0.01) var loop_crossfade := 0.4
## How far back from the end to search for the best loop point, in seconds.
@export_range(0.1, 5.0, 0.05) var loop_search := 1.5

@export_group("Output")
## Frame rate of the baked animation. 30 for most clips, 60 for fast actions.
@export_range(10, 120, 1) var fps := 30

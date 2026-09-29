# Plays a take through a robot rig in real time (the recorder's replay and
# play-along robots). Same maths as baking, just live.
class_name TakePlayback
extends RefCounted

var rig: RobotRig
var take: PerformanceTake
var time := 0.0
var looping := true
var mirrored := false


func _init(p_rig: RobotRig, p_take: PerformanceTake, p_mirrored := false) -> void:
	rig = p_rig
	take = p_take
	mirrored = p_mirrored
	restart()


func restart() -> void:
	time = 0.0
	rig.begin(take.eye_height)


# Advances by dt seconds and poses the rig. Returns the frame it used.
func step(dt: float) -> PerformanceFrame:
	time += dt
	if time > take.duration():
		if looping:
			time = fmod(time, maxf(take.duration(), 0.001))
		else:
			time = take.duration()
	var f := take.sample(time)
	rig.drive(f.mirrored() if mirrored else f, dt)
	return f


func finished() -> bool:
	return not looping and time >= take.duration()

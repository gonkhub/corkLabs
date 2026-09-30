# Makes a 3D robot (RailRider + RobotActor) show what its RobotAgent is doing
# in the facility simulation.
#
# The simulation only moves when the player acts, but the 3D world runs in
# real time. So the view *follows* the sim: when facility time jumps, the
# robot glides along its rail to where the sim says it is, and it keeps
# performing its current activity (working clips at a job, idles while
# charging or standing by) until the next player action changes it.
#
#     var view := RobotView.new()
#     view.setup("hauler", hauler_rider, hauler_actor)
#     add_child(view)
class_name RobotView
extends Node

var robot_id := ""
var rider: RailRider
var actor: RobotActor

var _snapped := false
var _pause := 0.0
var _rng := RandomNumberGenerator.new()


func setup(id: String, rail_rider: RailRider, robot_actor: RobotActor) -> void:
	robot_id = id
	rider = rail_rider
	actor = robot_actor
	name = "View_" + id


func _ready() -> void:
	_rng.randomize()


func agent() -> RobotAgent:
	if not Facility.running:
		return null
	return Facility.sim.get_system("robot_" + robot_id) as RobotAgent


func _process(delta: float) -> void:
	var a := agent()
	if a == null or rider == null:
		return
	rider.patrol = false
	# First frame: jump straight to where the sim has it.
	if not _snapped:
		rider.progress = a.pos
		rider.speed = 0.0
		_snapped = true
	var layout := Facility.sim.get_system("layout") as FacilityLayout
	var off := layout.signed_offset(a.rail, rider.progress, a.pos) if layout else a.pos - rider.progress
	if absf(off) > 0.03 and (rider.target < 0.0 or absf(rider.target - a.pos) > 0.03):
		rider.travel_to(a.pos)

	# Working at a job: perform work clips, with short pauses between.
	var at_work: bool = a.activity.kind == "work" and not a.moving and not rider.is_moving()
	if at_work and actor and not actor.is_busy():
		_pause -= delta
		if _pause <= 0.0:
			_play_work_clip(a)
			_pause = _rng.randf_range(0.4, 2.0)


func _play_work_clip(a: RobotAgent) -> void:
	var skill := "general"
	var board := Facility.sim.get_system("work") as WorkBoard
	if board:
		skill = str(board.get_job(int(a.activity.job)).get("skill", "general"))
	var wanted: Array = a.traits.work_clips.get(skill, [])
	var usable := wanted.filter(func(c): return actor.action_names.has(c))
	if usable.is_empty():
		actor.play_random_action()
	else:
		actor.play_action(usable[_rng.randi() % usable.size()])

# A 3D robot riding the rail network, showing what its RobotAgent is doing
# in the facility simulation.
#
# The simulation only moves when the player acts, but the 3D world runs in
# real time. So the view *follows* the sim along the rails: it keeps its own
# place on the network, plans a route to where the sim says the robot is,
# and rides it (faster when it's far behind, e.g. after a Wait). It turns to
# face where it's going, swings like a pendulum when it speeds up, brakes or
# turns, and performs its current activity (work clips at a job, idles
# otherwise) until the next player action changes it.
#
# A stationary robot (Ogre) stays on its mount: no riding, no swinging. It
# turns slowly on the spot to bring its crane round over whatever it's
# working on.
#
#   RobotView (this, on the rail)
#   └── Swing (pendulum pivot)
#       └── RobotActor (the baked robot, scaled by traits.visual_scale)
class_name RobotView
extends Node3D

## Catch up with the sim within about this many seconds when far behind.
const CATCH_UP_TIME := 2.0
## How quickly a stationary robot turns towards its work (fraction per second; low = massive).
const SLEW_RATE := 0.3

var robot_id := ""
var traits: RobotTraits
var layout: FacilityLayout
var swing: Node3D
var actor: RobotActor
## Where the 3D robot is on the network (not always where the sim has it yet).
var seg := ""
var off := 0.0

var _route: Array = []
var _goal := ""
var _snapped := false
var _pause := 0.0
var _rng := RandomNumberGenerator.new()
var _yaw := 0.0
# Pendulum sway (as the old RailRider): bob offset x = sideways, y = forwards.
var _prev_pos := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _disp := Vector2.ZERO
var _disp_vel := Vector2.ZERO
var _pendulum := 1.0


func setup(id: String, facility_layout: FacilityLayout) -> void:
	robot_id = id
	layout = facility_layout
	traits = RobotTraits.load_for(id)
	name = "Robot_" + id
	swing = Node3D.new()
	swing.name = "Swing"
	add_child(swing)
	actor = RobotActor.new()
	actor.robot_id = id
	actor.scale = Vector3.ONE * traits.visual_scale
	actor.position.y = 0.0 if traits.stationary else -0.15 * traits.visual_scale
	swing.add_child(actor)
	_pendulum = 0.9 * traits.visual_scale
	var st := layout.station(FacilitySetup.START_STATIONS.get(id, ""))
	if not st.is_empty():
		seg = st.segment
		off = st.offset
		position = layout.world_pos(seg, off)


func _ready() -> void:
	_rng.randomize()


func agent() -> RobotAgent:
	if not Facility.running:
		return null
	return Facility.sim.get_system("robot_" + robot_id) as RobotAgent


## Where its words float in camera feeds (a "SpeechAnchor" node in the robot's
## scene if it has one, else just above the rail).
func speech_anchor() -> Vector3:
	var mark: Node3D = actor.rig.get_node_or_null("SpeechAnchor") as Node3D if actor and actor.rig else null
	if mark:
		return mark.global_position
	return global_position + Vector3(0, 0.6 + 0.2 * traits.visual_scale, 0)


func _process(delta: float) -> void:
	var a := agent()
	if a == null:
		return
	if not _snapped:
		seg = a.seg
		off = a.off
		_snapped = true
	if traits.stationary:
		seg = a.seg
		off = a.off
		position = layout.world_pos(seg, off)
		_slew(a, delta)
		rotation.y = _yaw
		_perform(a, delta)
		return
	_follow(a, delta)
	var pos := layout.world_pos(seg, off)
	var moved := pos - position
	position = pos
	if Vector2(moved.x, moved.z).length() > 0.001:
		_yaw = lerp_angle(_yaw, atan2(-moved.x, -moved.z), clampf(6.0 * delta, 0.0, 1.0))
	rotation.y = _yaw
	_swing(delta)
	_perform(a, delta)


# Working at a job: perform work clips, with short pauses between.
func _perform(a: RobotAgent, delta: float) -> void:
	var at_work: bool = a.activity.kind == "work" and not a.moving and _route.is_empty()
	if at_work and actor and not actor.is_busy():
		_pause -= delta
		if _pause <= 0.0:
			_play_work_clip(a)
			_pause = _rng.randf_range(0.4, 2.0)


# A stationary robot turns on the spot so its crane's resting reach points at
# the station it's working at (or fixated on).
func _slew(a: RobotAgent, delta: float) -> void:
	var st := layout.station(str(a.activity.get("station", "")))
	if st.is_empty() or st.segment == seg:
		return
	var to := layout.station_world_pos(st.id) - position
	if Vector2(to.x, to.z).length() < 0.5:
		return
	var face := atan2(-to.x, -to.z)
	var rest = actor.rig.get("tip_rest") if actor and actor.rig else null
	if rest is Vector3:
		face += atan2((rest as Vector3).x, -(rest as Vector3).z)   # the crane is off to one side
	_yaw = lerp_angle(_yaw, face, clampf(SLEW_RATE * delta, 0.0, 1.0))


# Ride toward where the sim has the robot.
func _follow(a: RobotAgent, delta: float) -> void:
	if a.seg == seg and absf(a.off - off) < 0.02:
		_route.clear()
		return
	var goal := "%s:%.2f" % [a.seg, a.off]
	if goal != _goal or _route.is_empty():
		# Visual only: ignore blocks (the sim already decided it got through).
		var r := layout.plan(seg, off, a.seg, a.off, traits.width, true)
		if r.is_empty():
			seg = a.seg   # no rail between us (shouldn't happen): jump
			off = a.off
			return
		_route = r.legs.duplicate(true)
		_goal = goal
	var remaining := 0.0
	for leg in _route:
		remaining += absf(float(leg.to) - float(leg.from))
	var speed := maxf(traits.rail_speed * 1.2, remaining / CATCH_UP_TIME)
	var budget := speed * delta
	while budget > 0.0001 and not _route.is_empty():
		var leg: Dictionary = _route[0]
		if leg.seg != seg:
			seg = leg.seg
			off = float(leg.from)
		var step := minf(budget, absf(float(leg.to) - off))
		off += signf(float(leg.to) - off) * step
		budget -= step
		if absf(float(leg.to) - off) < 0.001:
			off = float(leg.to)
			_route.pop_front()


# Small-angle pendulum driven by the carriage's acceleration (in its own
# frame): speeding up swings the robot back, braking swings it forward,
# corners swing it outwards.
func _swing(delta: float) -> void:
	if delta <= 0.0:
		return
	var pos := global_position
	var vel := (pos - _prev_pos) / delta
	var acc := (vel - _prev_vel) / delta
	_prev_pos = pos
	_prev_vel = vel
	if acc.length() > 200.0:
		return   # a jump, not a swing
	var local_acc := global_transform.basis.inverse() * acc
	var a := Vector2(local_acc.x, -local_acc.z)
	var omega2 := 9.81 / maxf(_pendulum, 0.05)
	var accel := -omega2 * _disp - 1.2 * _disp_vel - a
	_disp_vel += accel * delta
	_disp += _disp_vel * delta
	_disp = _disp.limit_length(_pendulum * 0.5)
	swing.rotation = Vector3(asin(clampf(_disp.y / _pendulum, -1, 1)), 0.0, asin(clampf(_disp.x / _pendulum, -1, 1)))


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

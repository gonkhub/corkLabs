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
#   RobotView (this, on the rail)
#   ├── Swing (pendulum pivot)
#   │   └── RobotActor (the baked robot, scaled by traits.visual_scale)
#   └── Led (status light on the trolley: about the only light a robot gives off)
#
# The LED is how you spot a robot in the dark without night vision:
# cold blue when it's fine, amber when its power is low, a slow red blink
# while it's offline (crashed, stalled, rebooting).
class_name RobotView
extends Node3D

## Catch up with the sim within about this many seconds when far behind.
const CATCH_UP_TIME := 2.0
const LED_OK := Color(0.35, 0.75, 1.0)
const LED_LOW := Color(1.0, 0.6, 0.1)
const LED_OFFLINE := Color(1.0, 0.1, 0.05)

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
var _led_light: OmniLight3D
var _led_mat: StandardMaterial3D
var _led_time := 0.0


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
	actor.position.y = -0.15 * traits.visual_scale
	swing.add_child(actor)
	_pendulum = 0.9 * traits.visual_scale
	_build_led()
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


## Where its words float in camera feeds.
func speech_anchor() -> Vector3:
	return global_position + Vector3(0, 0.6 + 0.2 * traits.visual_scale, 0)


func _process(delta: float) -> void:
	var a := agent()
	if a == null:
		return
	_update_led(a, delta)   # first: whatever else happens this frame, the LED shows its state
	if not _snapped:
		seg = a.seg
		off = a.off
		_snapped = true
	_follow(a, delta)
	var pos := layout.world_pos(seg, off)
	var moved := pos - position
	position = pos
	if Vector2(moved.x, moved.z).length() > 0.001:
		_yaw = lerp_angle(_yaw, atan2(-moved.x, -moved.z), clampf(6.0 * delta, 0.0, 1.0))
	rotation.y = _yaw
	_swing(delta)

	# Working at a job: perform work clips, with short pauses between.
	var at_work: bool = a.activity.kind == "work" and not a.moving and _route.is_empty()
	if at_work and actor and not actor.is_busy():
		_pause -= delta
		if _pause <= 0.0:
			_play_work_clip(a)
			_pause = _rng.randf_range(0.4, 2.0)


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


func _build_led() -> void:
	_led_mat = StandardMaterial3D.new()
	_led_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_led_mat.emission_enabled = true
	_led_mat.emission_energy_multiplier = 2.0
	var bulb := MeshInstance3D.new()
	bulb.name = "Led"
	var sphere := SphereMesh.new()
	sphere.radius = 0.04 * traits.visual_scale
	sphere.height = sphere.radius * 2.0
	bulb.mesh = sphere
	bulb.material_override = _led_mat
	bulb.position = Vector3(0, -0.02, 0)
	add_child(bulb)
	_led_light = OmniLight3D.new()
	_led_light.omni_range = 1.2 * traits.visual_scale
	_led_light.light_energy = 0.3
	bulb.add_child(_led_light)
	_set_led(LED_OK, 1.0)


func _update_led(a: RobotAgent, delta: float) -> void:
	_led_time += delta
	if a.offline():
		_set_led(LED_OFFLINE, 1.0 if fmod(_led_time, 2.0) < 0.3 else 0.0)
	elif a.power < 0.25:
		_set_led(LED_LOW, 1.0)
	else:
		_set_led(LED_OK, 1.0)


func _set_led(col: Color, level: float) -> void:
	_led_mat.albedo_color = col * level
	_led_mat.emission = col * level
	_led_light.light_color = col
	_led_light.light_energy = 0.3 * level

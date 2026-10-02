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
## Motor hum level at full rail speed (placeholder sound: SoundSynth "hum").
const MOTOR_DB := -12.0
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
var _led_light: OmniLight3D
var _led_mat: StandardMaterial3D
var _led_time := 0.0
## Motor hum while it rides (a FacilitySound: heard through the cameras).
var motor: FacilitySound
var _motor_level := 0.0
## The camera greeting (it just repaired a camera): seconds in, which camera.
var _greet_t := -1.0
var _greet_cam := -1
var _greet_back := 0.0
## Greeting timeline (real seconds): close-up, back away, wave, done.
const GREET_HOLD := 1.6
const GREET_BACK := 1.0
const GREET_WAVE := 2.2
const GREET_BACK_M := 1.0


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
	_build_led()
	motor = FacilitySound.new()
	motor.name = "Motor"
	motor.robot_id = id
	motor.stream = SoundSynth.builtin("hum")
	motor.unit_size = 4.0 * traits.visual_scale   # bigger robots carry further
	motor.position.y = 0.5 * traits.visual_scale
	add_child(motor)
	var st := layout.station(FacilitySetup.START_STATIONS.get(id, ""))
	if not st.is_empty():
		seg = st.segment
		off = st.offset
		position = layout.world_pos(seg, off)


var _perform_seen := 0


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
	_update_led(a, delta)   # first: whatever else happens this frame, the LED shows its state
	_show_dead(a.activity.kind == "broken")
	if int(a.perform.n) != _perform_seen:
		_perform_seen = int(a.perform.n)
		if a.perform.has("cam"):
			_start_greet(int(a.perform.cam))   # the clip plays in the greeting, after the close-up
		elif actor and not str(a.perform.clip).is_empty():
			actor.play_action(str(a.perform.clip))   # quietly nothing if it hasn't been performed yet
	if not _snapped:
		seg = a.seg
		off = a.off
		_snapped = true
	if traits.stationary:
		seg = a.seg
		off = a.off
		position = layout.world_pos(seg, off)
		if not _face_camera(a, delta):
			_slew(a, delta)
		rotation.y = _yaw
		_perform(a, delta)
		return
	_follow(a, delta)
	var pos := layout.world_pos(seg, off)
	var moved := pos - position
	position = pos
	if not _face_camera(a, delta) and Vector2(moved.x, moved.z).length() > 0.001:
		_yaw = lerp_angle(_yaw, atan2(-moved.x, -moved.z), clampf(6.0 * delta, 0.0, 1.0))
	rotation.y = _yaw
	_greet(delta)
	_swing(delta)
	_motor_sound(moved.length() / maxf(delta, 0.0001), delta)
	_perform(a, delta)


# A broken unit (Ogre's dead core): no animation, the eye shut and dark.
var _dead := false


func _show_dead(dead: bool) -> void:
	if actor == null:
		return
	var rig := actor.rig
	if dead != _dead:
		_dead = dead
		if actor.tree:
			actor.tree.active = not dead
		var lens := rig.get_node_or_null("Core/Eye/Lens") if rig else null
		if lens is Node3D:
			(lens as Node3D).visible = not dead
	if not dead or rig == null:
		return
	# Every frame: the rig would put its eye back otherwise.
	var glow := rig.get_node_or_null("Core/Eye/Glow")
	if glow is Light3D:
		(glow as Light3D).light_energy = 0.0
	var lid := rig.get_node_or_null("Core/Eye/LidTop")
	if lid is Node3D:
		(lid as Node3D).rotation.x = -deg_to_rad(85.0)


# On the link, or greeting a camera: turn to face it. Returns true if it is.
func _face_camera(a: RobotAgent, delta: float) -> bool:
	var w := get_parent() as FacilityWorld
	if w == null:
		return false
	var cam := _greet_cam if _greet_t >= 0.0 else -1
	if cam < 0 and a.activity.kind == "link":
		cam = w.nearest_camera(global_position, w.robot_room(robot_id))
	if cam < 0 or cam >= w.cameras.size():
		return false
	var to := w.cameras[cam].global_position - global_position
	_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), clampf(5.0 * delta, 0.0, 1.0))
	return true


# A unit that just repaired a camera (from the rail right under it): the
# camera comes back on looking at it, no zoom; it backs away a little, and waves.
func _start_greet(cam: int) -> void:
	var w := get_parent() as FacilityWorld
	if w == null or cam < 0 or cam >= w.cameras.size():
		return
	_greet_cam = cam
	_greet_t = 0.0
	_greet_back = 0.0
	w.cameras[cam].frame(actor if actor else self, -1.0, GREET_HOLD + GREET_BACK + GREET_WAVE)


func _greet(delta: float) -> void:
	if _greet_t < 0.0:
		return
	var was := _greet_t
	_greet_t += delta
	var w := get_parent() as FacilityWorld
	var cam: SecurityCamera = w.cameras[_greet_cam] if w and _greet_cam < w.cameras.size() else null
	# Back away from the lens.
	if _greet_t > GREET_HOLD and _greet_t <= GREET_HOLD + GREET_BACK:
		_greet_back = GREET_BACK_M * smoothstep(GREET_HOLD, GREET_HOLD + GREET_BACK, _greet_t)
	# Wave: the recorded clip if there is one, else a little happy wobble.
	if was <= GREET_HOLD + GREET_BACK and _greet_t > GREET_HOLD + GREET_BACK:
		if actor and actor.action_names.has("act_wave_camera"):
			actor.play_action("act_wave_camera")
	var in_wave := _greet_t - GREET_HOLD - GREET_BACK
	if in_wave > 0.0 and in_wave < GREET_WAVE and not (actor and actor.action_names.has("act_wave_camera")):
		swing.rotation.z = sin(in_wave * 9.0) * 0.18 * (1.0 - in_wave / GREET_WAVE)
	if _greet_t > GREET_HOLD + GREET_BACK + GREET_WAVE:
		_greet_back = move_toward(_greet_back, 0.0, delta * 1.5)
		if _greet_back <= 0.0:
			_greet_t = -1.0
			_greet_cam = -1
	# The step back is along its own facing (towards the camera is forward).
	if _greet_back > 0.0:
		position += global_transform.basis.z * _greet_back


# Working at a job: perform work clips, with short pauses between.
func _perform(a: RobotAgent, delta: float) -> void:
	var at_work: bool = a.activity.kind == "work" and not a.moving and _route.is_empty()
	if at_work and actor and not actor.is_busy():
		_pause -= delta
		if _pause <= 0.0:
			_play_work_clip(a)
			_pause = _rng.randf_range(0.4, 2.0)


# Hum while riding: louder and higher the faster it goes; bigger robots hum lower.
func _motor_sound(speed: float, delta: float) -> void:
	var want := clampf(speed / maxf(traits.rail_speed, 0.1), 0.0, 1.5)
	_motor_level = move_toward(_motor_level, want, delta * 3.0)
	if _motor_level < 0.02:
		if motor.playing:
			motor.stop()
		return
	if not motor.playing:
		motor.play()
	motor.set_level_db(MOTOR_DB + linear_to_db(_motor_level))
	motor.pitch_scale = clampf((0.8 + 0.3 * _motor_level) / sqrt(traits.visual_scale), 0.3, 2.0)


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

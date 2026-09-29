# The VR recorder: perform as a robot, watch yourself in a live mirror,
# record takes, replay them, and bake them to animation clips.
#
# Controls (in the headset). X/Y/A/B only act as controls while NOT
# recording; during a take they're performance inputs (blink, flash, ...).
#
#   Left MENU        start the 3-2-1 countdown / stop recording
#                    (press during the countdown to cancel)
#   Left X           choose the robot you're performing for
#   Left Y           play-along on/off: your previous take plays on its robot
#                    while you record the next one (act a scene with yourself)
#   Right A          replay the last take on the robot / back to live mirror
#   Right B          robot view: mirror (facing you) <-> behind (facing away)
#   Right stick in   show/hide the cyan ghost cubes (raw recording)
#   Left stick in    punch-in mode: off -> right arm -> left arm -> head -> face.
#                    While punching, the last take plays on the robot and you
#                    re-perform ONLY that part; the result is comped into a
#                    new take (the old one is kept).
#   Space (keyboard) same as MENU, for testing at the desk
#
# Takes save to res://takes/. When a robot is chosen, each take is also
# cleaned up and baked straight into res://animations/<robot>/.
extends Node3D

enum State { IDLE, COUNTDOWN, RECORDING }

const COUNTDOWN_SECONDS := 3.0
## Height of the rail the robots hang from, in meters.
const RAIL_HEIGHT := 2.5
## Where the mirror robot hangs, in front of the floor mark.
const STAGE_DISTANCE := 2.2
## Where the play-along robot hangs (to your front-right).
const PLAY_ALONG_SPOT := Vector3(1.6, 0.0, -1.3)

@onready var head: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var right_hand: XRController3D = $XROrigin3D/RightHand
@onready var hud: Label3D = $Hud
@onready var beeper: AudioStreamPlayer = $Beeper
@onready var ghost: Node3D = $Ghost
@onready var ghost_head: Node3D = $Ghost/Head
@onready var ghost_left: MeshInstance3D = $Ghost/LeftHand
@onready var ghost_right: MeshInstance3D = $Ghost/RightHand
@onready var stage: Node3D = $Stage
@onready var play_along_spot: Node3D = $PlayAlongSpot

var state := State.IDLE
var countdown := 0.0
var record_start_usec := 0
var take: PerformanceTake              # the take being recorded right now
var height_samples := PackedFloat32Array()
var calibrated_eye_height := 0.0

# Robot you're performing for, and its live/replay rig.
var robot_ids := PackedStringArray()
var robot_index := -1                  # -1 = no robot (cubes only)
var robot: RobotRig
var smoother := FrameSmoother.new()
var mirror_view := true

# Replay of the last take.
var last_take: PerformanceTake         # raw
var last_take_path := ""
var last_clean: PerformanceTake        # cleaned, what gets baked
var replay: TakePlayback
var ghost_time := 0.0
var ghost_cubes_visible := true
var status_line := ""

# Punch-in.
const PUNCH_MODES := ["", "right", "left", "head", "face"]
var punch_index := 0
var punch_base: PerformanceTake        # raw take being punched into
var punch_base_path := ""
var punch_preview: PerformanceTake     # cleaned, for the live preview

# Play-along.
var play_along := false
var along_robot: RobotRig
var along_playback: TakePlayback
var along_path := ""

var beep_tick: AudioStreamWAV
var beep_go: AudioStreamWAV
var beep_stop: AudioStreamWAV


func _ready() -> void:
	_start_xr()
	beep_tick = _make_beep(660.0, 0.12)
	beep_go = _make_beep(1320.0, 0.3)
	beep_stop = _make_beep(440.0, 0.3)
	left_hand.button_pressed.connect(_on_left_button)
	right_hand.button_pressed.connect(_on_right_button)

	robot_ids = RobotLibrary.ids()
	_place_stage()
	play_along_spot.position = Vector3(PLAY_ALONG_SPOT.x, RAIL_HEIGHT, PLAY_ALONG_SPOT.z)
	play_along_spot.look_at(Vector3(0, RAIL_HEIGHT, 0), Vector3.UP)
	_load_latest_take()
	# Start on the robot of the newest take, if it has one.
	if last_take and robot_ids.has(last_take.robot_id):
		_select_robot(robot_ids.find(last_take.robot_id))
	else:
		_select_robot(0 if robot_ids.size() > 0 else -1)


func _process(delta: float) -> void:
	var live := PerformanceFrame.capture(head, left_hand, right_hand)
	match state:
		State.COUNTDOWN:
			_tick_countdown(delta)
			_drive_live(live, delta)
			if along_playback:
				along_playback.restart()   # hold at the first frame
				along_playback.step(0.0)
		State.RECORDING:
			_record_frame(live)
			_drive_live(live, delta)
			if along_playback:
				along_playback.step(delta)
		State.IDLE:
			if replay:
				replay.step(delta)
			elif robot:
				_drive_live(live, delta)
			if along_playback and replay:
				along_playback.step(delta)
			_play_ghost(delta)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle_recording()


# --- Controls -------------------------------------------------------------

func _on_left_button(button_name: String) -> void:
	if button_name == "menu_button":
		_toggle_recording()
		return
	if state != State.IDLE:
		return
	if button_name == "ax_button":
		_select_robot(robot_index + 1 if robot_index + 1 < robot_ids.size() else -1)
		_stop_replay()
	elif button_name == "by_button":
		play_along = not play_along
		_setup_play_along()
	elif button_name == "primary_click":
		punch_index = (punch_index + 1) % PUNCH_MODES.size()


func _punch_group() -> String:
	return PUNCH_MODES[punch_index]


func _on_right_button(button_name: String) -> void:
	if state != State.IDLE:
		return
	match button_name:
		"ax_button":
			# Replaying -> back to the live mirror. Live -> replay from the start.
			if replay:
				_stop_replay()
				return
			ghost_time = 0.0
			if last_clean and robot:
				_start_replay()
			if along_playback:
				along_playback.restart()
		"by_button":
			mirror_view = not mirror_view
			_place_stage()
			if replay:
				replay.mirrored = mirror_view
		"primary_click":
			ghost_cubes_visible = not ghost_cubes_visible
			ghost.visible = ghost_cubes_visible and last_take != null


func _toggle_recording() -> void:
	match state:
		State.IDLE:
			_stop_replay()
			state = State.COUNTDOWN
			countdown = COUNTDOWN_SECONDS
			height_samples.clear()
			ghost.visible = false
			_setup_play_along()
			_setup_punch()
			_beep(beep_tick)
		State.COUNTDOWN:
			state = State.IDLE
			ghost.visible = ghost_cubes_visible and last_take != null
		State.RECORDING:
			_finish_recording()


# --- Robots ---------------------------------------------------------------

func _select_robot(index: int) -> void:
	if robot:
		robot.queue_free()
		robot = null
	robot_index = index
	if index < 0 or index >= robot_ids.size():
		robot_index = -1
		return
	robot = RobotLibrary.instantiate(robot_ids[index])
	if robot == null:
		robot_index = -1
		return
	stage.add_child(robot)
	robot.begin(calibrated_eye_height)
	smoother.reset()


func _robot_id() -> String:
	return robot_ids[robot_index] if robot_index >= 0 else ""


# Mirror view: the robot faces you and moves like your reflection.
# Behind view: the robot faces away and copies you directly (like
# watching over its shoulder).
func _place_stage() -> void:
	if mirror_view:
		stage.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, RAIL_HEIGHT, -STAGE_DISTANCE))
	else:
		stage.transform = Transform3D(Basis(), Vector3(0, RAIL_HEIGHT, -STAGE_DISTANCE))
	smoother.reset()


func _drive_live(live: PerformanceFrame, delta: float) -> void:
	if robot == null:
		return
	var f := smoother.smooth(live, delta)
	# Punch-in: the old take drives everything except the part you're redoing.
	if punch_base and state != State.IDLE:
		var t := 0.0
		if state == State.RECORDING:
			t = (Time.get_ticks_usec() - record_start_usec) / 1_000_000.0
		f = TakeComp.merge(punch_preview.sample(t), f, PackedStringArray([_punch_group()]))
	robot.drive(f.mirrored() if mirror_view else f, delta)


# Punch-in needs a previous take for the same robot.
func _setup_punch() -> void:
	punch_base = null
	punch_preview = null
	punch_base_path = ""
	if _punch_group().is_empty():
		return
	if last_take == null or last_take.robot_id != _robot_id():
		status_line = "punch-in needs a previous take for this robot - recording normally"
		return
	punch_base = last_take
	punch_base_path = last_take_path
	punch_preview = last_clean if last_clean else TakeCleanup.run(last_take).take


func _start_replay() -> void:
	replay = TakePlayback.new(robot, last_clean, mirror_view)


func _stop_replay() -> void:
	replay = null
	if robot:
		robot.begin(calibrated_eye_height)
		smoother.reset()


# Play-along uses the most recent take on its own robot.
func _setup_play_along() -> void:
	if along_robot:
		along_robot.queue_free()
		along_robot = null
	along_playback = null
	along_path = ""
	if not play_along or last_take == null or not robot_ids.has(last_take.robot_id):
		return
	along_robot = RobotLibrary.instantiate(last_take.robot_id)
	if along_robot == null:
		return
	play_along_spot.add_child(along_robot)
	var clean: PerformanceTake = last_clean if last_clean else TakeCleanup.run(last_take).take
	along_playback = TakePlayback.new(along_robot, clean, false)
	along_path = last_take_path


# --- Recording ------------------------------------------------------------

func _tick_countdown(delta: float) -> void:
	# Measure eye height during the last second (stand still on the mark).
	if countdown < 1.0:
		height_samples.append(head.position.y)
	var before := ceili(countdown)
	countdown -= delta
	if countdown <= 0.0:
		_begin_recording()
	elif ceili(countdown) < before:
		_beep(beep_tick)


func _begin_recording() -> void:
	if height_samples.size() > 0:
		var total := 0.0
		for h in height_samples:
			total += h
		calibrated_eye_height = total / height_samples.size()
	take = PerformanceTake.new()
	take.created = Time.get_datetime_string_from_system()
	take.robot_id = _robot_id()
	take.eye_height = calibrated_eye_height
	if along_playback:
		take.overdub_of = PackedStringArray([along_path])
		along_playback.restart()
	record_start_usec = Time.get_ticks_usec()
	state = State.RECORDING
	_beep(beep_go)


func _record_frame(live: PerformanceFrame) -> void:
	var t := (Time.get_ticks_usec() - record_start_usec) / 1_000_000.0
	take.append(t, live)


func _finish_recording() -> void:
	state = State.IDLE
	_beep(beep_stop)
	if take.frame_count() < 2:
		return
	var path := TakeStore.new_path()
	if punch_base:
		# The raw punch recording is only a source for the comp: no robot, so
		# "Bake all" skips it. Kept on disk in case you want to re-comp.
		take.robot_id = ""
		take.note = "punch-in source (%s) for %s" % [_punch_group(), punch_base_path.get_file()]
	var err := TakeStore.save(take, path)
	if err != OK:
		status_line = "COULD NOT SAVE (error %d)" % err
		push_error("Could not save take to %s (error %d)" % [path, err])
		return
	if punch_base:
		var comp := TakeComp.comp(punch_base, take, PackedStringArray([_punch_group()]), 0.0, take.duration())
		comp.created = take.created
		comp.overdub_of = PackedStringArray([punch_base_path, path])
		var comp_path := path.get_basename() + "_punch_%s.res" % _punch_group()
		TakeStore.save(comp, comp_path)
		take = comp
		path = comp_path
		punch_base = null
	last_take = take
	last_take_path = path
	last_clean = TakeCleanup.run(take).take
	ghost_time = 0.0
	ghost.visible = ghost_cubes_visible
	status_line = "saved %s" % path.get_file()
	if robot:
		var r := Baker.bake_to_library(take, path, take.robot_id)
		status_line += "\nbaked %s/%s" % [take.robot_id, r.clip] if r.ok else "\nBAKE FAILED"
		_start_replay()
	if along_playback:
		along_playback.restart()


func _load_latest_take() -> void:
	ghost.visible = false
	var paths := TakeStore.list()
	# Newest take outside the demo folder.
	for i in range(paths.size() - 1, -1, -1):
		if paths[i].contains("/demo/"):
			continue
		var loaded := TakeStore.load_take(paths[i])
		if loaded:
			last_take = loaded
			last_take_path = paths[i]
			last_clean = TakeCleanup.run(loaded).take
			if loaded.eye_height > 0.0:
				calibrated_eye_height = loaded.eye_height
			ghost.visible = ghost_cubes_visible
			status_line = "loaded %s" % paths[i].get_file()
			return


# --- Ghost cubes (raw take, in place) -------------------------------------

func _play_ghost(delta: float) -> void:
	if last_take == null or last_take.frame_count() < 2:
		return
	ghost_time += delta
	if ghost_time > last_take.duration():
		ghost_time = 0.0
	var f := last_take.sample(ghost_time)
	ghost_head.transform = f.head
	ghost_left.transform = f.left
	ghost_right.transform = f.right
	_tint(ghost_left, f.left_trigger)
	_tint(ghost_right, f.right_trigger)


func _tint(cube: MeshInstance3D, trigger: float) -> void:
	var mat: StandardMaterial3D = cube.get_active_material(0)
	var c := Color(0.3, 0.9, 1.0).lerp(Color(1.0, 0.45, 0.05), trigger)
	c.a = 0.55
	mat.albedo_color = c


# --- HUD, sound, XR -------------------------------------------------------

func _update_hud() -> void:
	var robot_name := "no robot (cubes only)"
	if robot:
		robot_name = robot.profile.display_name if robot.profile else _robot_id()
	match state:
		State.COUNTDOWN:
			hud.text = "%d\nstand on the mark, look ahead" % ceili(countdown)
		State.RECORDING:
			var t := (Time.get_ticks_usec() - record_start_usec) / 1_000_000.0
			var punch := "   PUNCH-IN: %s only" % _punch_group().to_upper() if punch_base else ""
			hud.text = "[REC]  %.1f s   %s%s\nleft MENU to stop" % [t, robot_name, punch]
		State.IDLE:
			var lines := PackedStringArray()
			lines.append("READY  -  performing as: %s" % robot_name)
			lines.append("MENU record   X robot   Y play-along: %s   L-stick click punch-in: %s" % [
				"ON" if play_along else "off", _punch_group().to_upper() if _punch_group() else "off"])
			lines.append("A %s   B view: %s   R-stick click: ghost cubes" % [
				"back to live" if replay else "replay", "mirror" if mirror_view else "behind"])
			if last_take:
				lines.append("")
				lines.append("%s  %.1f s, %d frames, %.0f Hz" % [last_take_path.get_file(), last_take.duration(),
					last_take.frame_count(), last_take.sample_rate()])
			if not status_line.is_empty():
				lines.append(status_line)
			hud.text = "\n".join(lines)


func _beep(sound: AudioStreamWAV) -> void:
	beeper.stream = sound
	beeper.play()


# Builds a short sine-wave beep in memory, with 5 ms fades so it doesn't click.
func _make_beep(freq: float, length: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	var fade := rate * 0.005
	for i in n:
		var env := minf(1.0, minf(i, n - i) / fade)
		var s := sin(TAU * freq * i / rate) * 0.4 * env
		data.encode_s16(i * 2, int(s * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


func _start_xr() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
	else:
		push_error("OpenXR did not initialize. Is the headset on Link?")

# Phase 2 recorder: record a take, save it, and replay it as a ghost.
#
# Controls (in the headset):
#   Left MENU button  start the 3-2-1 countdown / stop recording
#                     (press during the countdown to cancel)
#   Right A           replay the ghost from the start
#   Right B           move the ghost: in place <-> in front of you, facing you
#   Space (keyboard)  same as the menu button, for testing at the desk
#
# Takes are saved to res://takes/ (the "takes" folder in the project).
# The newest take is loaded automatically when the scene starts.
extends Node3D

enum State { IDLE, COUNTDOWN, RECORDING }

const COUNTDOWN_SECONDS := 3.0
const TAKES_DIR := "res://takes"

@onready var head: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var right_hand: XRController3D = $XROrigin3D/RightHand
@onready var hud: Label3D = $Hud
@onready var beeper: AudioStreamPlayer = $Beeper
@onready var ghost: Node3D = $Ghost
@onready var ghost_head: Node3D = $Ghost/Head
@onready var ghost_left: MeshInstance3D = $Ghost/LeftHand
@onready var ghost_right: MeshInstance3D = $Ghost/RightHand

var state := State.IDLE
var countdown := 0.0
var record_start_usec := 0
var take: PerformanceTake          # the take being recorded right now
var ghost_take: PerformanceTake    # the take the ghost is replaying
var ghost_name := ""
var ghost_time := 0.0
var ghost_facing_you := false

var beep_tick: AudioStreamWAV
var beep_go: AudioStreamWAV
var beep_stop: AudioStreamWAV


func _ready() -> void:
	_start_xr()
	beep_tick = _make_beep(660.0, 0.12)
	beep_go = _make_beep(1320.0, 0.3)
	beep_stop = _make_beep(440.0, 0.3)

	# XRController3D emits button_pressed(name) whenever a button goes down.
	left_hand.button_pressed.connect(_on_left_button)
	right_hand.button_pressed.connect(_on_right_button)

	_load_latest_take()


func _process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.RECORDING:
			_record_frame()
		State.IDLE:
			_play_ghost(delta)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle_recording()


# --- Controls -------------------------------------------------------------

func _on_left_button(button_name: String) -> void:
	if button_name == "menu_button":
		_toggle_recording()


func _on_right_button(button_name: String) -> void:
	if state != State.IDLE:
		return
	if button_name == "ax_button":
		ghost_time = 0.0
	elif button_name == "by_button":
		ghost_facing_you = not ghost_facing_you
		_place_ghost()


func _toggle_recording() -> void:
	match state:
		State.IDLE:
			state = State.COUNTDOWN
			countdown = COUNTDOWN_SECONDS
			ghost.visible = false
			_beep(beep_tick)
		State.COUNTDOWN:
			state = State.IDLE   # cancelled
			ghost.visible = ghost_take != null
		State.RECORDING:
			_finish_recording()


# --- Recording ------------------------------------------------------------

func _tick_countdown(delta: float) -> void:
	var before := ceili(countdown)
	countdown -= delta
	if countdown <= 0.0:
		_begin_recording()
	elif ceili(countdown) < before:
		_beep(beep_tick)


func _begin_recording() -> void:
	take = PerformanceTake.new()
	take.created = Time.get_datetime_string_from_system()
	record_start_usec = Time.get_ticks_usec()
	state = State.RECORDING
	_beep(beep_go)
	_record_frame()


func _record_frame() -> void:
	var t := (Time.get_ticks_usec() - record_start_usec) / 1_000_000.0
	take.append(t, PerformanceFrame.capture(head, left_hand, right_hand))


func _finish_recording() -> void:
	state = State.IDLE
	_beep(beep_stop)
	if take.frame_count() < 2:
		return
	var path := _save_take(take)
	ghost_take = take
	ghost_name = path.get_file()
	ghost_time = 0.0
	ghost.visible = true


func _save_take(t: PerformanceTake) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TAKES_DIR))
	# Colons aren't allowed in Windows file names, so 14:05:33 becomes 14-05-33.
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s/take_%s.res" % [TAKES_DIR, stamp]
	var err := ResourceSaver.save(t, path)
	if err != OK:
		push_error("Could not save take to %s (error %d)" % [path, err])
	else:
		print("Saved %s: %d frames, %.1f s, %.0f Hz" % [path, t.frame_count(), t.duration(), t.sample_rate()])
	return path


func _load_latest_take() -> void:
	ghost.visible = false
	if not DirAccess.dir_exists_absolute(TAKES_DIR):
		return
	var names := Array(DirAccess.get_files_at(TAKES_DIR)).filter(
		func(n: String) -> bool: return n.begins_with("take_") and n.ends_with(".res"))
	if names.is_empty():
		return
	names.sort()   # timestamps sort oldest -> newest
	var path: String = TAKES_DIR + "/" + names.back()
	var loaded := load(path) as PerformanceTake
	if loaded:
		ghost_take = loaded
		ghost_name = names.back()
		ghost.visible = true
		print("Loaded %s: %d frames, %.1f s" % [path, loaded.frame_count(), loaded.duration()])


# --- Ghost playback -------------------------------------------------------

func _play_ghost(delta: float) -> void:
	if ghost_take == null or ghost_take.frame_count() < 2:
		return
	ghost_time += delta
	if ghost_time > ghost_take.duration():
		ghost_time = 0.0   # loop
	var f := ghost_take.sample(ghost_time)
	ghost_head.transform = f.head
	ghost_left.transform = f.left
	ghost_right.transform = f.right
	_tint(ghost_left, f.left_trigger)
	_tint(ghost_right, f.right_trigger)


# "In place" puts the ghost exactly where you stood, so you can step aside and
# check it matches. "Facing you" stands it 2 m in front, turned around.
func _place_ghost() -> void:
	if ghost_facing_you:
		ghost.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -2))
	else:
		ghost.transform = Transform3D.IDENTITY


func _tint(cube: MeshInstance3D, trigger: float) -> void:
	var mat: StandardMaterial3D = cube.get_active_material(0)
	var c := Color(0.3, 0.9, 1.0).lerp(Color(1.0, 0.45, 0.05), trigger)
	c.a = 0.55
	mat.albedo_color = c


# --- HUD, sound, XR -------------------------------------------------------

func _update_hud() -> void:
	match state:
		State.COUNTDOWN:
			hud.text = "%d" % ceili(countdown)
		State.RECORDING:
			var t := (Time.get_ticks_usec() - record_start_usec) / 1_000_000.0
			hud.text = "[REC]  %.1f s\nleft MENU to stop" % t
		State.IDLE:
			var lines := "READY\nleft MENU: record\nA: replay from start   B: move ghost"
			if ghost_take:
				lines += "\n\n%s\n%.1f s, %d frames, %.0f Hz  (at %.1f s)" % [
					ghost_name, ghost_take.duration(), ghost_take.frame_count(),
					ghost_take.sample_rate(), ghost_time]
			hud.text = lines


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

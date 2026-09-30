# Checks camera-feed audio: the bus layout (Feed with Voices and World under
# it, UI beside it), the placeholder sounds, the sound library, which feed is
# the listener (single view, grid hover), the Cameras mute button (and M key)
# and feed volume, voices and motors on the right buses, room-aware
# attenuation, and the Terminal's `sound` auditions.
extends SceneTree

const SAVE := "user://test_camera_audio_save.json"
const OS_SETTINGS := "user://test_camera_audio_settings.json"

var failures := 0
var facility: Node
var desk: Control


func _initialize() -> void:
	get_root().size = Vector2i(1600, 900)
	facility = get_root().get_node("Facility")
	facility.wipe_save(SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OS_SETTINGS))
	OSSettings.use_file(OS_SETTINGS)
	OSSettings.set_value("boot_animation", false)

	_test_buses()
	_test_synth_and_library()

	desk = (load("res://os/desktop.tscn") as PackedScene).instantiate()
	desk.save_path = SAVE
	get_root().add_child(desk)
	await process_frame
	desk.set_anchors_preset(Control.PRESET_TOP_LEFT)
	desk.size = Vector2(1600, 900)
	desk.log_on()
	await process_frame

	await _test_listener()
	await _test_mute_and_volume()
	await _test_routing()
	await _test_auditions()

	desk.log_off()
	desk.free()
	FeedAudio.set_muted(false)
	facility.wipe_save(SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OS_SETTINGS))
	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _test_buses() -> void:
	var n := AudioServer.bus_count
	FeedAudio.ensure_buses()
	_check(AudioServer.bus_count == n, "the bus layout already has every bus (ensure_buses adds none)")
	for r in FeedAudio.ROUTING:
		var i := AudioServer.get_bus_index(r[0])
		_check(i > 0 and AudioServer.get_bus_send(i) == r[1], "bus %s sends to %s" % [r[0], r[1]])


func _test_synth_and_library() -> void:
	for n in SoundSynth.NAMES:
		var s := SoundSynth.builtin(n)
		_check(s != null and s.get_length() > 0.01, "built-in '%s' exists (%.2f s)" % [n, s.get_length() if s else 0.0])
	_check(SoundSynth.builtin("tone").loop_mode == AudioStreamWAV.LOOP_FORWARD and SoundSynth.builtin("click").loop_mode == AudioStreamWAV.LOOP_DISABLED,
		"beds loop, the click doesn't")
	_check(SoundSynth.builtin("hum") == SoundSynth.builtin("hum"), "placeholders are made once")
	_check(SoundBank.find_stream("tone") != null and SoundBank.find_stream("no_such_sound") == null, "sounds are found by name")
	_check(Array(SoundBank.library()).has("click"), "the library lists the built-ins")


func _test_listener() -> void:
	var app = desk.open_app("cameras")
	await process_frame
	await process_frame
	var world = desk.world
	var listening: Array = app.feeds.filter(func(f): return f.listening)
	_check(listening.size() == 1 and world.listener_cam == app.cam, "single view: the open camera is the microphone")
	_check(listening.size() == 1 and listening[0].viewport.audio_listener_enable_3d, "its viewport is the 3D audio listener")
	_check(world.listen_room() == world.camera_rooms[app.cam], "the listening room is that camera's room")

	app.set_grid(true)
	await process_frame
	await process_frame
	_check(world.listener_cam == -1 and app.feeds.all(func(f): return not f.viewport.audio_listener_enable_3d),
		"grid: nothing heard until you point at a feed")
	var f3 = app.feeds[2]
	f3.hovered.emit(f3, true)
	await process_frame
	_check(world.listener_cam == 2 and f3.viewport.audio_listener_enable_3d
		and app.feeds.filter(func(f): return f.viewport.audio_listener_enable_3d).size() == 1, "grid: the feed under the mouse listens")
	f3.hovered.emit(f3, false)
	await process_frame
	_check(world.listener_cam == -1, "and stops when the mouse leaves")
	app.show_camera(0)
	await process_frame


func _test_mute_and_volume() -> void:
	var app = desk.open_app("cameras")
	var feed_bus := AudioServer.get_bus_index(FeedAudio.FEED)
	_check(not AudioServer.is_bus_mute(feed_bus) and app.mute_button.text == "Mute", "the feed starts unmuted")
	app.mute_button.button_pressed = true   # as a click
	_check(AudioServer.is_bus_mute(feed_bus) and OSSettings.get_value("feed_muted") == true and app.mute_button.text == "Muted",
		"the mute button mutes the Feed bus and remembers it")
	# The feed's text redraws on its next frame, which may take a few process frames.
	for i in 60:
		await process_frame
		if app.feeds[0].ptz_label.text.contains("AUDIO MUTED"):
			break
	_check(app.feeds[0].ptz_label.text.contains("AUDIO MUTED"), "the feed says it's muted")
	var ev := InputEventKey.new()
	ev.keycode = KEY_M
	ev.pressed = true
	_check(app.key_input(ev) and not AudioServer.is_bus_mute(feed_bus) and not app.mute_button.button_pressed, "M toggles it back")
	FeedAudio.set_volume(0.5)
	_check(absf(AudioServer.get_bus_volume_db(feed_bus) - linear_to_db(0.5)) < 0.01, "feed volume sets the Feed bus level")
	FeedAudio.set_volume(1.0)
	var master := AudioServer.get_bus_index(&"Master")
	_check(not AudioServer.is_bus_mute(master) and AudioServer.get_bus_volume_db(master) == 0.0, "Master is never touched")


func _test_routing() -> void:
	var speech = desk.speech
	var voice = speech._voice("tinker")
	var players: Array = voice.get_children().filter(func(c): return c is AudioStreamPlayer)
	_check(not players.is_empty() and players.all(func(p): return p.bus == FeedAudio.VOICES), "robot voices go to the Voices bus")
	var view = desk.world.views["hauler"]
	_check(view.motor != null and view.motor.bus == FeedAudio.WORLD and view.motor.robot_id == "hauler", "each robot has a motor sound on the World bus")
	var panel = desk.find_children("*", "CorkHQPanel", true, false)
	if not panel.is_empty() and panel[0].chime:
		_check(panel[0].chime.bus == FeedAudio.UI, "the corkHQ chime goes to the UI bus")


func _test_auditions() -> void:
	var world = desk.world
	var term = desk.open_app("terminal")
	await process_frame
	var cams = desk.open_app("cameras")
	cams.show_camera(0)   # main hall
	await process_frame
	var out: String = term.run("sound")
	_check(out.contains("camera 1") and out.contains("tone"), "`sound` says which camera you hear and lists sounds")

	out = term.run("sound loop tone 12")
	_check(world.auditions.size() == 1 and out.contains("in front of camera 1"), "a sound plays in front of the listening camera")
	var ahead = world.auditions[0]
	var cam = world.cameras[0]
	_check(absf(ahead.global_position.distance_to(cam.global_position) - 12.0) < 0.01 and ahead.bus == FeedAudio.WORLD,
		"12 m ahead, on the World bus")

	term.run("sound loop noise workshop")
	term.run("sound loop hum tinker")
	_check(world.auditions.size() == 3, "on a room and on a robot too")
	var other = world.auditions[1]
	var riding = world.auditions[2]
	_check(riding.get_parent() == world.views["tinker"], "the robot's sound rides with it")
	for i in 30:
		await process_frame
	_check(other.current_room() == "workshop" and other.behind_wall(), "a sound in another room is behind a wall")
	_check(absf(other.volume_db - (other.level_db() + other.through_wall_db)) < 0.5 and other.attenuation_filter_cutoff_hz < 1000.0,
		"so it's quieter and muffled (%.1f dB, %d Hz)" % [other.volume_db, other.attenuation_filter_cutoff_hz])
	_check(not ahead.behind_wall() and absf(ahead.volume_db - ahead.level_db()) < 0.01, "a sound in the camera's room isn't")

	cams.show_camera(3)   # workshop
	for i in 30:
		await process_frame
	_check(not other.behind_wall() and ahead.behind_wall(), "switch cameras and the walls switch with you")

	out = term.run("sound stop")
	await process_frame
	_check(world.auditions.is_empty() and out.contains("3"), "`sound stop` ends every audition")

	term.run("sound play click hall")
	_check(world.auditions.size() == 1, "a one-shot plays")
	await create_timer(0.4).timeout
	await process_frame
	_check(world.auditions.is_empty(), "and cleans itself up")
	_check(term.run("sound play nothing_here").contains("No sound"), "unknown sounds are refused")
	_check(term.run("sound play tone nowhere").contains("isn't a distance"), "unknown places are refused")
	term.run("sound mute")
	_check(FeedAudio.is_muted() and cams.mute_button.button_pressed, "`sound mute` mutes the feed (and the button shows it)")
	term.run("sound unmute")


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1

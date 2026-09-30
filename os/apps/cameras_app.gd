# Cameras: observe the facility. Nothing in here changes the facility or
# costs facility time; it's only for looking. Orders and the like live in
# the other apps.
#
#   Single view   one camera, and you drive its pan/tilt/zoom head:
#                 drag to pan/tilt, scroll to zoom, double-click to reset
#                 (or arrow keys, + / -, Home). Auto-track follows a robot.
#   Grid view     every camera at once; click one to open it.
#   Night vision  the facility is dark (it was built for robots); N switches
#                 every feed to infrared.
#   Keys          1-9 camera, G grid/single, N night vision, F CCTV filter, M mute.
#   Robots' speech floats over them in any feed that can see them.
#   Sound         you hear the facility through one camera at a time: the
#                 open one in single view, the one under the mouse in the
#                 grid. Mute silences the whole Feed bus (voices + world).
class_name CamerasApp
extends OSApp

var cam := 0
var grid_mode := false
var filter_on := true
var night_on := false

var body: Control
var feeds: Array[CCTVFeed] = []
var cam_buttons: Array[Button] = []
var single_button: Button
var grid_button: Button
var track_button: Button
var reset_button: Button
var night_button: CheckBox
var mute_button: Button
var hint: Label


func _init() -> void:
	app_id = "cameras"
	title = "Cameras"
	default_size = Vector2(900, 620)
	icon_text = "CAM"
	icon_color = OSTheme.INFO


func build() -> void:
	var world := _world()
	var row := HFlowContainer.new()   # wraps, so the window can be made small
	add_child(row)
	var views := ButtonGroup.new()
	single_button = _toggle(row, "Single", views, func(): set_grid(false))
	grid_button = _toggle(row, "Grid", views, func(): set_grid(true))
	row.add_child(VSeparator.new())
	var cams := ButtonGroup.new()
	if world:
		for i in world.cameras.size():
			var b := _toggle(row, "CAM %d" % (i + 1), cams, show_camera.bind(i))
			b.tooltip_text = world.cameras[i].display_name
			cam_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	track_button = Button.new()
	track_button.text = "Auto-track"
	track_button.toggle_mode = true
	track_button.focus_mode = Control.FOCUS_NONE
	track_button.tooltip_text = "Follow a robot automatically (this camera has a motorised tracker)"
	track_button.toggled.connect(func(on: bool):
		var c := _camera()
		if c:
			c.set_auto_track(on))
	row.add_child(track_button)
	reset_button = Button.new()
	reset_button.text = "Reset view"
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(func():
		var c := _camera()
		if c:
			c.reset_view())
	row.add_child(reset_button)
	mute_button = Button.new()
	mute_button.toggle_mode = true
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.tooltip_text = "Mute the camera feed's sound: robot voices and the facility (M)"
	mute_button.toggled.connect(set_muted)
	row.add_child(mute_button)
	_show_mute()
	night_button = CheckBox.new()
	night_button.text = "Night vision"
	night_button.button_pressed = night_on
	night_button.focus_mode = Control.FOCUS_NONE
	night_button.tooltip_text = "See by the cameras' own infrared light (N)"
	night_button.toggled.connect(set_night_vision)
	row.add_child(night_button)
	var filt := CheckBox.new()
	filt.text = "CCTV filter"
	filt.button_pressed = filter_on
	filt.focus_mode = Control.FOCUS_NONE
	filt.toggled.connect(func(on: bool):
		filter_on = on
		for f in feeds:
			f.set_filter(on))
	row.add_child(filt)

	body = Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	hint = OSTheme.label("", 12, OSTheme.TEXT_DIM)
	hint.clip_text = true   # a long hint never sets how narrow the window can be
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(hint)
	_rebuild()


func show_camera(i: int) -> void:
	cam = i
	grid_mode = false
	_rebuild()


func set_grid(on: bool) -> void:
	grid_mode = on
	_rebuild()


func set_night_vision(on: bool) -> void:
	night_on = on
	night_button.set_pressed_no_signal(on)
	for f in feeds:
		f.set_night_vision(on)


func set_muted(on: bool) -> void:
	FeedAudio.set_muted(on)
	_show_mute()


func _show_mute() -> void:
	var on := FeedAudio.is_muted()
	mute_button.set_pressed_no_signal(on)
	mute_button.text = "Muted" if on else "Mute"
	mute_button.modulate = OSTheme.WARN if on else Color.WHITE


## Which feed you hear the facility through (null: none).
func listen_to(feed: CCTVFeed) -> void:
	for f in feeds:
		f.listening = f == feed
	var w := _world()
	if w:
		w.listener_cam = feed.cam if feed else -1


func _exit_tree() -> void:
	var w := _world()
	if w and is_instance_valid(w):
		w.listener_cam = -1


func _rebuild() -> void:
	for f in feeds:
		f.queue_free()
	feeds.clear()
	for c in body.get_children():
		c.queue_free()
	var world := _world()
	if world == null:
		return
	single_button.set_pressed_no_signal(not grid_mode)
	grid_button.set_pressed_no_signal(grid_mode)
	for i in cam_buttons.size():
		cam_buttons[i].set_pressed_no_signal(not grid_mode and i == cam)
		cam_buttons[i].disabled = grid_mode
	if grid_mode:
		var grid := GridContainer.new()
		grid.columns = ceili(sqrt(float(world.cameras.size())))
		grid.set_anchors_preset(Control.PRESET_FULL_RECT)
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		body.add_child(grid)
		for i in world.cameras.size():
			var f := _feed(i, false)
			f.clicked.connect(func(feed: CCTVFeed): show_camera(feed.cam))
			f.hovered.connect(func(feed: CCTVFeed, on: bool):
				if on:
					listen_to(feed)
				elif feed.listening:
					listen_to(null))
			grid.add_child(f)
		listen_to(null)
		hint.text = "Click a feed to open it · point at one to hear it.   Keys: 1-9 camera, G single/grid, N night vision, F filter, M mute"
	else:
		var f := _feed(cam, true)
		f.set_anchors_preset(Control.PRESET_FULL_RECT)
		body.add_child(f)
		listen_to(f)
		hint.text = "Drag to pan/tilt · scroll to zoom · double-click to reset.   Keys: arrows, + / -, Home, 1-9 camera, G grid, N night vision, F filter, M mute"
	refresh()


func _feed(i: int, interactive: bool) -> CCTVFeed:
	var f := CCTVFeed.new()
	f.setup(_world(), desktop.world_viewport if desktop else null, i, interactive)
	f.speech = desktop.speech if desktop else null
	f.set_filter(filter_on)
	f.set_night_vision(night_on)
	feeds.append(f)
	return f


func refresh() -> void:
	var c := _camera()
	var single := not grid_mode and c != null
	var w := _world()
	track_button.visible = w != null and w.cameras.any(func(cam): return cam.can_track())
	track_button.disabled = not single or not c.can_track()
	track_button.set_pressed_no_signal(single and c.auto_track)
	reset_button.disabled = not single
	_show_mute()


func key_input(event: InputEventKey) -> bool:
	var c := _camera()
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var i: int = event.keycode - KEY_1
			if i < cam_buttons.size():
				show_camera(i)
			return true
		KEY_G:
			set_grid(not grid_mode)
			return true
		KEY_N:
			set_night_vision(not night_on)
			return true
		KEY_F:
			filter_on = not filter_on
			for f in feeds:
				f.set_filter(filter_on)
			return true
		KEY_M:
			set_muted(not FeedAudio.is_muted())
			return true
	if grid_mode or c == null:
		return false
	match event.keycode:
		KEY_LEFT: c.nudge(4.0, 0.0)
		KEY_RIGHT: c.nudge(-4.0, 0.0)
		KEY_UP: c.nudge(0.0, 3.0)
		KEY_DOWN: c.nudge(0.0, -3.0)
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: c.zoom_by(0.85)
		KEY_MINUS, KEY_KP_SUBTRACT: c.zoom_by(1.0 / 0.85)
		KEY_HOME: c.reset_view()
		_: return false
	refresh()
	return true


func _world() -> FacilityWorld:
	return desktop.world if desktop else null


func _camera() -> SecurityCamera:
	var w := _world()
	return w.cameras[cam] if w and not grid_mode else null


func _toggle(row: Container, text: String, group: ButtonGroup, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	row.add_child(b)
	return b


func save_state() -> Dictionary:
	return {"cam": cam, "grid": grid_mode, "filter": filter_on, "night": night_on}


func load_state(state: Dictionary) -> void:
	cam = clampi(int(state.get("cam", 0)), 0, maxi(cam_buttons.size() - 1, 0))
	grid_mode = bool(state.get("grid", false))
	filter_on = bool(state.get("filter", true))
	night_on = bool(state.get("night", false))
	night_button.set_pressed_no_signal(night_on)
	_rebuild()

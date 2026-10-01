# Cameras: watch the facility, and run it. Looking is free (panning,
# zooming, switching cameras); acting costs facility time like everywhere.
#
#   Point and click  hover a robot or a device in the single view: it's
#                 outlined and named. Left-click (no drag) opens its menu at
#                 the cursor (ObjectMenu): order maintenance, talk, send a
#                 unit to a job, recharge, diagnose, service...
#   Units bar     one chip per unit (what it's doing, power; ASKS when it has
#                 a request). Click: jump to a camera that sees it, and its menu.
#   Talking       Talk opens the unit link here: its words float over it on
#                 camera, your replies are buttons under the picture.
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
## The units bar, the last action's result, the object menu.
var roster: HFlowContainer
var _roster_key := ""
var feedback: Label
var menu: PopupMenu
var _menu_entries: Array = []      # menu item id -> entry
## The conversation over the unit link, while one is open.
var talk_box: PanelContainer
var talk_log: RichTextLabel
var talk_choices: HFlowContainer
var talk_runner: Dialogue.Runner
var talk_bot: RobotAgent


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

	roster = HFlowContainer.new()
	roster.add_theme_constant_override("h_separation", 6)
	add_child(roster)
	body = Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	_build_talk()
	feedback = OSTheme.label("", 13, OSTheme.ACCENT)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.visible = false
	add_child(feedback)
	menu = PopupMenu.new()
	menu.id_pressed.connect(_on_menu)
	add_child(menu)
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
		hint.text = "Click a unit or a machine for its menu · drag to pan/tilt · scroll to zoom · double-click to reset.   Keys: 1-9 camera, G grid, N night vision, F filter, M mute"
	refresh()


func _feed(i: int, interactive: bool) -> CCTVFeed:
	var f := CCTVFeed.new()
	f.setup(_world(), desktop.world_viewport if desktop else null, i, interactive)
	f.speech = desktop.speech if desktop else null
	f.set_filter(filter_on)
	f.set_night_vision(night_on)
	f.describe = func(id: String) -> String: return ObjectMenu.describe(sim(), id)
	if interactive:
		f.object_clicked.connect(func(_feed: CCTVFeed, id: String, _at: Vector2):
			if not id.is_empty():
				open_menu(id))
	feeds.append(f)
	return f


func refresh() -> void:
	_refresh_roster()
	var c := _camera()
	var single := not grid_mode and c != null
	var w := _world()
	track_button.visible = w != null and w.cameras.any(func(cam): return cam.can_track())
	track_button.disabled = not single or not c.can_track()
	track_button.set_pressed_no_signal(single and c.auto_track)
	reset_button.disabled = not single
	_show_mute()


func key_input(event: InputEventKey) -> bool:
	if event.keycode == KEY_ESCAPE and talk_runner != null:
		end_talk()
		return true
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


# --- Object menus ----------------------------------------------------------------------

## Opens a thing's menu at the mouse (id from FacilityWorld.pick).
func open_menu(id: String) -> void:
	if sim() == null:
		return
	menu.clear()
	for c in menu.get_children():
		if c is PopupMenu:
			c.queue_free()
	_menu_entries.clear()
	_fill_menu(menu, ObjectMenu.entries(sim(), id), id)
	menu.reset_size()
	menu.position = Vector2i(get_global_mouse_position())
	menu.popup()


func _fill_menu(pm: PopupMenu, entries: Array, id: String) -> void:
	for e in entries:
		if e.get("sep", false):
			pm.add_separator()
			continue
		if e.has("sub"):
			var sub := PopupMenu.new()
			sub.name = "Sub%d" % _menu_entries.size()
			sub.id_pressed.connect(_on_menu)
			pm.add_child(sub)
			_fill_menu(sub, e.sub, id)
			pm.add_submenu_item(str(e.text), sub.name)
			continue
		var n := _menu_entries.size()
		_menu_entries.append(e.merged({"for": id}))
		pm.add_item(str(e.text), n)
		var i := pm.get_item_index(n)
		pm.set_item_disabled(i, e.get("disabled", false))
		if not str(e.get("tip", "")).is_empty():
			pm.set_item_tooltip(i, str(e.tip))


func _on_menu(n: int) -> void:
	if n < 0 or n >= _menu_entries.size():
		return
	var e: Dictionary = _menu_entries[n]
	if e.get("talk", false):
		start_talk(str(e["for"]).trim_prefix("robot:"))
		return
	var act: Callable = e.get("act", Callable())
	if act.is_valid():
		var out = act.call()
		show_feedback(str(out) if out != null else "")


## The result of the last thing you did, under the picture.
func show_feedback(text: String) -> void:
	feedback.text = text
	feedback.visible = not text.is_empty()


# --- Units bar -------------------------------------------------------------------------

func _refresh_roster() -> void:
	if sim() == null:
		return
	var reqs := sim().get_system("requests") as UnitRequests
	var bots := FacilitySetup.robots(sim())
	var key := ""
	for bot in bots:
		var asks := reqs != null and reqs.requests.any(func(r): return str(r.robot) == bot.robot_id)
		key += "%s|%s|%d|%s|%s;" % [bot.robot_id, bot.doing_text(sim()), roundi(bot.power * 20.0), bot.stability_state, asks]
	var req := sim().get_system("requisitions") as Requisitions
	var crated: Array = req.crated_units() if req else []
	key += str(crated.size())
	if key == _roster_key:
		return
	_roster_key = key
	for c in roster.get_children():
		c.queue_free()
	for bot in bots:
		var asks := reqs != null and reqs.requests.any(func(r): return str(r.robot) == bot.robot_id)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		var state := ""
		if bot.offline():
			state = "  " + bot.activity.kind.to_upper()
		elif bot.own_will():
			state = "  " + bot.stability_state.to_upper()
		b.text = "%s%s  %d%%%s" % [bot.display_name().to_upper(), "  ASKS" if asks else "", roundi(bot.power * 100.0), state]
		b.tooltip_text = ObjectMenu.describe(sim(), "robot:" + bot.robot_id)
		var col := OSTheme.WARN if asks or bot.offline() or bot.own_will() else OSTheme.category_color(bot.robot_id)
		b.add_theme_color_override("font_color", col)
		var id := bot.robot_id
		b.pressed.connect(func():
			look_at_unit(id)
			open_menu("robot:" + id))
		roster.add_child(b)
	if not crated.is_empty():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = "CRATED UNIT (workbench)"
		b.add_theme_color_override("font_color", OSTheme.INFO)
		b.pressed.connect(func(): open_menu("bench"))
		roster.add_child(b)


## Switches to a camera that can see this unit (one that tracks it, if any).
func look_at_unit(robot_id: String) -> void:
	var w := _world()
	if w == null:
		return
	var room := w.robot_room(robot_id)
	var best := -1
	for i in w.cameras.size():
		if w.camera_rooms[i] != room:
			continue
		if best < 0 or (w.cameras[i].target and w._trackers.get(i, "") == robot_id):
			best = i
	if best >= 0 and (best != cam or grid_mode):
		show_camera(best)


# --- Talking over the unit link ---------------------------------------------------------

func _build_talk() -> void:
	talk_box = PanelContainer.new()
	talk_box.add_theme_stylebox_override("panel", OSTheme.box(OSTheme.PANEL_LIGHT, OSTheme.LINE, 4, 10, 8))
	talk_box.visible = false
	add_child(talk_box)
	var col := VBoxContainer.new()
	talk_box.add_child(col)
	talk_log = RichTextLabel.new()
	talk_log.bbcode_enabled = true
	talk_log.scroll_following = true
	talk_log.fit_content = false
	talk_log.custom_minimum_size = Vector2(0, 110)
	col.add_child(talk_log)
	talk_choices = HFlowContainer.new()
	talk_choices.add_theme_constant_override("h_separation", 6)
	col.add_child(talk_choices)


## Opens the unit link to a robot (Talk in its menu; the Terminal's talk).
func start_talk(robot_id: String) -> void:
	var bot := sim().get_system("robot_" + robot_id) as RobotAgent if sim() else null
	if bot == null:
		return
	end_talk()
	look_at_unit(robot_id)
	var r: Dictionary = Supervisor.talk_begin(bot)
	if r.runner == null:
		show_feedback(str(r.get("error", "")))
		return
	talk_runner = r.runner
	talk_bot = bot
	talk_log.clear()
	talk_box.visible = true
	_talk_lines(r.lines)


func end_talk() -> void:
	if talk_bot and sim():
		sim().note("supervisor", "Closes the unit link to %s" % talk_bot.display_name())
	talk_runner = null
	talk_bot = null
	talk_box.visible = false


func _talk_lines(lines: Array) -> void:
	for l in lines:
		var speaker := str(l.speaker)
		if speaker == "unit" and talk_bot:
			speaker = talk_bot.robot_id
		var color := OSTheme.TEXT_DIM
		var who := ""
		if speaker == "you":
			who = "YOU"
			color = OSTheme.ACCENT
		elif speaker != "sys":
			who = talk_bot.display_name().to_upper() if talk_bot and speaker == talk_bot.robot_id else speaker.to_upper()
			color = OSTheme.category_color(speaker)
			if desktop and desktop.speech:
				desktop.speech.say(speaker, str(l.text))   # it says it, on camera
		talk_log.append_text("[color=#%s]%s%s[/color]
" % [color.to_html(false), (who + ": ") if not who.is_empty() else "", str(l.text).replace("[", "[lb]")])
	for c in talk_choices.get_children():
		c.queue_free()
	if talk_runner == null or talk_runner.done or talk_runner.choices.is_empty():
		var close := Button.new()
		close.text = "Close the link"
		close.focus_mode = Control.FOCUS_NONE
		close.pressed.connect(end_talk)
		talk_choices.add_child(close)
		return
	for i in talk_runner.choices.size():
		var b := Button.new()
		b.text = str(talk_runner.choices[i].text)
		b.focus_mode = Control.FOCUS_NONE
		var n := i
		b.pressed.connect(func(): _talk_choose(n))
		talk_choices.add_child(b)
	var bye := Button.new()
	bye.text = "(close the link)"
	bye.focus_mode = Control.FOCUS_NONE
	bye.pressed.connect(end_talk)
	talk_choices.add_child(bye)


func _talk_choose(i: int) -> void:
	if talk_runner == null or talk_bot == null:
		return
	talk_log.append_text("[color=#%s]YOU: %s[/color]
" % [OSTheme.ACCENT.to_html(false), str(talk_runner.choices[i].text).replace("[", "[lb]")])
	_talk_lines(Supervisor.talk_choose(talk_runner, talk_bot, i))


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

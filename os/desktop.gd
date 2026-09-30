# The corkLabs OS: the supervisor's desktop, and the whole game screen.
#
#   Login screen   "Log on" opens the facility session (the real save,
#                  user://facility_save.json) exactly where it was left.
#   Desktop        icons (double-click) and the start menu open apps in
#                  windows you can drag, resize, minimise and close.
#   Taskbar        start menu, open windows, the alarm light, throughput,
#                  "Wait" (lets facility time pass), and the facility clock.
#                  The clock shows facility time, never the real clock.
#   Toasts         alarms, shift reports and robot replies pop up bottom right.
#
# The 3D facility runs once, hidden, in a SubViewport; camera windows render
# it from the security cameras through their own viewports.
#
# Run: open os/desktop.tscn, F6 (it restarts itself without VR, like the demo).
class_name CorkDesktop
extends Control

const TASKBAR_HEIGHT := 40
const REFRESH_EVERY := 0.5
const TOAST_SECONDS := 7.0
const WORLD_SCENE := "res://game/facility_world.tscn"

## [id, script] in desktop-icon order.
const APPS := [
	["cameras", preload("res://os/apps/cameras_app.gd")],
	["units", preload("res://os/apps/units_app.gd")],
	["work", preload("res://os/apps/work_app.gd")],
	["plant", preload("res://os/apps/plant_app.gd")],
	["messages", preload("res://os/apps/messages_app.gd")],
	["log", preload("res://os/apps/log_app.gd")],
]

## Where the facility is saved (tests point this elsewhere).
@export var save_path := "user://facility_save.json"

var world_viewport: SubViewport
var world: FacilityWorld
var window_layer: Control
var icons: VBoxContainer
var toast_box: VBoxContainer
var taskbar_buttons: HBoxContainer
var clock_label: Label
var output_label: Label
var alarm_button: Button
var login: Control
var unread := 0

var _windows := {}          # app id -> OSWindow
var _refresh_left := 0.0
var _journal_mark := 0
var _time := 0.0
var _cascade := 0


func _ready() -> void:
	if FlatScreen.relaunch_if_xr(self):
		return
	theme = OSTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_icons()
	window_layer = Control.new()
	window_layer.name = "Windows"
	window_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	window_layer.offset_bottom = -TASKBAR_HEIGHT
	add_child(window_layer)
	_build_toasts()
	_build_taskbar()
	_build_login()
	Facility.time_spent.connect(func(_a, _b, _c): _refresh_all())


func _process(delta: float) -> void:
	_time += delta
	if not Facility.running:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_EVERY
		_refresh_all()
	# The alarm light blinks while anything is broken.
	if alarm_button.visible:
		alarm_button.modulate.a = 0.55 + 0.45 * sin(_time * 6.0)


# Clicking anywhere on a window brings it to the front.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not login.visible:
		for i in range(window_layer.get_child_count() - 1, -1, -1):
			var w := window_layer.get_child(i) as OSWindow
			if w and w.visible and w.get_global_rect().has_point(event.position):
				focus_window(w)
				return


# --- Session -----------------------------------------------------------------------------

func log_on() -> void:
	Facility.start_session(FacilitySetup.systems(), save_path)
	world_viewport = SubViewport.new()
	world_viewport.name = "FacilityWorldViewport"
	world_viewport.own_world_3d = true
	world_viewport.size = Vector2i(8, 8)
	world_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED   # feeds do the rendering
	add_child(world_viewport)
	world = (load(WORLD_SCENE) as PackedScene).instantiate()
	world_viewport.add_child(world)
	_journal_mark = Facility.sim.journal.added
	login.visible = false
	_refresh_all()
	var board := Facility.sim.get_system("work") as WorkBoard
	toast("Welcome, %s" % user_name(), "Facility time %s. %d open job(s)." % [
		FacilitySim.format_time(Facility.sim.time()), board.open_jobs().size()], OSTheme.ACCENT, "work")


func log_off() -> void:
	for id in _windows.keys():
		_windows[id].close()
	_windows.clear()
	for t in toast_box.get_children():
		t.queue_free()
	Facility.end_session()
	if world_viewport:
		world_viewport.queue_free()
		world_viewport = null
		world = null
	_update_login_text()
	login.visible = true


## The player's real first name, lightly: their Windows user name.
static func user_name() -> String:
	var n := OS.get_environment("USERNAME")
	if n.is_empty():
		n = OS.get_environment("USER")
	return n if not n.is_empty() else "Supervisor"


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and Facility.running:
		Facility.end_session()


# --- Windows ---------------------------------------------------------------------------------

func open_app(id: String) -> OSApp:
	if not Facility.running:
		return null
	if _windows.has(id):
		var existing: OSWindow = _windows[id]
		existing.visible = true
		focus_window(existing)
		return existing.app
	var script: Script = null
	for a in APPS:
		if a[0] == id:
			script = a[1]
	if script == null:
		return null
	var app: OSApp = script.new()
	app.desktop = self
	var win := OSWindow.new()
	win.setup(app)
	var area := window_layer.size
	win.position = Vector2(120 + 28 * (_cascade % 8), 30 + 26 * (_cascade % 8))
	win.size = win.size.min(area - Vector2(140, 50))
	_cascade += 1
	window_layer.add_child(win)
	win.focused.connect(focus_window)
	win.minimized.connect(_on_minimized)
	win.closed.connect(_on_closed)
	_windows[id] = win
	focus_window(win)
	return app


func _on_minimized(w: OSWindow) -> void:
	w.visible = false
	_rebuild_taskbar()


func _on_closed(w: OSWindow) -> void:
	_windows.erase(w.app.app_id)
	_rebuild_taskbar.call_deferred()


func focus_window(win: OSWindow) -> void:
	window_layer.move_child(win, -1)
	for w in _windows.values():
		w.set_focused(w == win)
	if win.app.app_id == "messages":
		unread = 0
	_rebuild_taskbar()


func is_open(id: String) -> bool:
	return _windows.has(id) and _windows[id].visible


func _refresh_all() -> void:
	if not Facility.running:
		return
	for w in _windows.values():
		if w.visible:
			w.app.refresh()
	_refresh_taskbar()
	_check_journal()


# --- Toasts --------------------------------------------------------------------------------

## Pops a notification up bottom right. Clicking it opens `app`.
func toast(heading: String, body: String, color := OSTheme.ACCENT, app := "") -> void:
	var p := PanelContainer.new()
	var style := OSTheme.box(OSTheme.PANEL_LIGHT, color, 6, 12, 8)
	style.border_width_left = 4
	p.add_theme_stylebox_override("panel", style)
	p.custom_minimum_size = Vector2(340, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(col)
	var h := OSTheme.label(heading, 14, color)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(h)
	var b := OSTheme.label(body, 13)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(b)
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			if not app.is_empty():
				open_app(app)
			p.queue_free())
	toast_box.add_child(p)
	while toast_box.get_child_count() > 5:
		toast_box.get_child(0).free()
	get_tree().create_timer(TOAST_SECONDS).timeout.connect(func():
		if is_instance_valid(p):
			var tw := p.create_tween()
			tw.tween_property(p, "modulate:a", 0.0, 0.6)
			tw.tween_callback(p.queue_free))


# New journal lines: alarms, reports and robot replies become toasts.
func _check_journal() -> void:
	var journal := Facility.sim.journal
	var fresh := journal.added_since(_journal_mark)
	_journal_mark = journal.added
	var shown := 0
	for e in fresh:
		if shown >= 4:
			break
		var cat: String = e.cat
		var text: String = e.text
		if cat == "alarm":
			toast("ALARM  " + FacilitySim.format_clock(e.t), text, OSTheme.ALARM, "plant")
			shown += 1
		elif cat == "report":
			toast("Shift report", text.trim_prefix("Shift report: "), OSTheme.INFO, "log")
			shown += 1
		elif MessagesApp.is_message(e):
			if not (is_open("messages") and _windows["messages"].is_focused):
				unread += 1
				var who := cat.capitalize()
				toast(who, MessagesApp.message_text(e), OSTheme.category_color(cat), "messages")
				shown += 1


# --- Building ------------------------------------------------------------------------------

func _build_background() -> void:
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.set_color(0, Color("16292c"))
	g.set_color(1, OSTheme.BG)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.45)
	tex.fill_to = Vector2(1.1, 1.1)
	bg.texture = tex
	add_child(bg)
	var mark := VBoxContainer.new()
	mark.set_anchors_preset(Control.PRESET_CENTER)
	mark.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mark.grow_vertical = Control.GROW_DIRECTION_BOTH
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mark)
	var logo := OSTheme.label("corkLabs", 96, Color(OSTheme.ACCENT, 0.07))
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.add_child(logo)
	var sub := OSTheme.mono_label("ORGANIC COMPUTING COMPOUND  ·  SUPERVISOR TERMINAL", 14, Color(OSTheme.TEXT, 0.12))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.add_child(sub)


func _build_icons() -> void:
	icons = VBoxContainer.new()
	icons.position = Vector2(14, 14)
	icons.add_theme_constant_override("separation", 10)
	add_child(icons)
	for a in APPS:
		var app: OSApp = a[1].new()
		var icon := DesktopIcon.new()
		icon.setup(app.icon_text, app.title, app.icon_color)
		icon.opened.connect(open_app.bind(a[0]))
		icons.add_child(icon)
		app.free()


func _build_toasts() -> void:
	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	toast_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	toast_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast_box.offset_right = -14
	toast_box.offset_bottom = -TASKBAR_HEIGHT - 12
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.add_theme_constant_override("separation", 8)
	add_child(toast_box)


func _build_taskbar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -TASKBAR_HEIGHT
	bar.add_theme_stylebox_override("panel", OSTheme.box(Color("0f1c1f"), OSTheme.LINE, 0, 6, 4))
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)

	var start := MenuButton.new()
	start.text = "corkLabs"
	start.flat = false
	start.add_theme_color_override("font_color", OSTheme.ACCENT)
	var menu := start.get_popup()
	for i in APPS.size():
		var app: OSApp = APPS[i][1].new()
		menu.add_item(app.title, i)
		app.free()
	menu.add_separator()
	menu.add_item("Log off", 100)
	menu.id_pressed.connect(func(id: int):
		if id == 100:
			log_off()
		elif id < APPS.size():
			open_app(APPS[id][0]))
	row.add_child(start)

	taskbar_buttons = HBoxContainer.new()
	taskbar_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(taskbar_buttons)

	alarm_button = Button.new()
	alarm_button.text = "ALARM"
	alarm_button.add_theme_color_override("font_color", OSTheme.ALARM)
	alarm_button.add_theme_stylebox_override("normal", OSTheme.box(OSTheme.ALARM.darkened(0.7), OSTheme.ALARM, 4, 8, 4))
	alarm_button.focus_mode = Control.FOCUS_NONE
	alarm_button.pressed.connect(func(): open_app("plant"))
	alarm_button.visible = false
	row.add_child(alarm_button)

	output_label = OSTheme.mono_label("", 13, OSTheme.TEXT_DIM)
	output_label.tooltip_text = "Facility throughput: the pods' average sync"
	output_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(output_label)

	var wait := MenuButton.new()
	wait.text = "Wait ▾"
	wait.tooltip_text = "Let facility time pass. It only moves when you act."
	wait.flat = false
	var wm := wait.get_popup()
	for m in [5, 15, 60]:
		wm.add_item("Wait %s" % ("%d min" % m if m < 60 else "1 hour"), m)
	wm.id_pressed.connect(func(m: int): Supervisor.wait(m * 60.0))
	row.add_child(wait)

	clock_label = OSTheme.mono_label("--:--", 15, OSTheme.TEXT)
	clock_label.tooltip_text = "Facility time"
	clock_label.mouse_filter = Control.MOUSE_FILTER_PASS
	clock_label.custom_minimum_size.x = 150
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(clock_label)


func _rebuild_taskbar() -> void:
	for c in taskbar_buttons.get_children():
		c.queue_free()
	for id in _windows:
		var w: OSWindow = _windows[id]
		var b := Button.new()
		b.text = w.app.title
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = w.visible and w.is_focused
		b.pressed.connect(func():
			if w.visible and w.is_focused:
				w.visible = false
				_rebuild_taskbar()
			else:
				w.visible = true
				focus_window(w))
		taskbar_buttons.add_child(b)


func _refresh_taskbar() -> void:
	var sim := Facility.sim
	clock_label.text = FacilitySim.format_time(sim.time())
	var plant := sim.get_system("plant") as FacilityPlant
	if plant:
		output_label.text = "THROUGHPUT %d%%" % roundi(plant.throughput * 100.0)
		output_label.add_theme_color_override("font_color", OSTheme.ACCENT if plant.throughput >= 0.8 else (OSTheme.WARN if plant.throughput >= 0.6 else OSTheme.ALARM))
		var faults := PlantApp.active_faults(plant)
		alarm_button.visible = faults > 0
		alarm_button.text = "ALARM  %d" % faults
	for icon in icons.get_children():
		if icon.title == "Messages":
			icon.badge = unread


func _build_login() -> void:
	login = PanelContainer.new()
	login.set_anchors_preset(Control.PRESET_FULL_RECT)
	login.add_theme_stylebox_override("panel", OSTheme.box(OSTheme.BG, Color(0, 0, 0, 0), 0))
	add_child(login)
	var center := CenterContainer.new()
	login.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", OSTheme.box(OSTheme.PANEL, OSTheme.LINE, 8, 36, 28))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	var logo := OSTheme.label("corkLabs", 48, OSTheme.ACCENT)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(logo)
	var sub := OSTheme.mono_label("SUPERVISOR TERMINAL", 13, OSTheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(HSeparator.new())
	var hello := OSTheme.label("", 18)
	hello.name = "Hello"
	hello.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hello)
	var info := OSTheme.mono_label("", 13, OSTheme.TEXT_DIM)
	info.name = "Info"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(info)
	var go := Button.new()
	go.name = "LogOn"
	go.text = "Log on"
	go.custom_minimum_size = Vector2(220, 40)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(log_on)
	col.add_child(go)
	_update_login_text()


func _update_login_text() -> void:
	(login.find_child("Hello", true, false) as Label).text = "Welcome, %s." % user_name()
	var info := login.find_child("Info", true, false) as Label
	var t := _saved_time()
	info.text = ("Facility on hold since %s.\nIt resumes the moment you log on." % FacilitySim.format_time(t)) if t >= 0.0 \
		else "No facility on record. A new one will be brought online."


# Reads the facility time out of the save without starting a session.
func _saved_time() -> float:
	if not FileAccess.file_exists(save_path):
		return -1.0
	var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if d is Dictionary and int(d.get("version", 0)) == FacilitySim.SAVE_VERSION:
		return int(d.get("tick", 0)) * FacilitySim.TICK
	return -1.0

# The corkLabs OS: the supervisor's desktop, and the whole game screen. The
# game boots straight into it (it's the main scene).
#
#   Boot screen    a few seconds of start-up text (any key or click skips;
#                  can be turned off in Settings), then the login screen.
#   Login screen   "Log on" opens the facility session (the real save,
#                  user://facility_save.json) exactly where it was left, and
#                  reopens the windows you had open.
#   Desktop        icons (double-click), the start menu or a right-click on
#                  the desktop open apps in windows: drag, snap to screen
#                  edges, maximise, resize, minimise, close.
#   Taskbar        start menu, open windows, the alarm light, throughput,
#                  and the facility clock (never the real clock). Click the
#                  clock for the notification centre. There is no "wait":
#                  facility time only moves when the supervisor DOES something
#                  (orders, duties, reading files, talking, playing...).
#   Toasts         alarms and shift reports pop up bottom right.
#   corkHQ         corporate's panel, pinned top-right above everything. It can't
#                  be closed, moved, resized or muted (CorkHQPanel).
#   Speech         robots talk as coloured text over them in camera feeds, with
#                  voice blips (SpeechDirector; what they say comes from RobotChatter).
#   Keys           go to the focused window's app (e.g. Cameras: arrows pan).
#
# The 3D facility runs once, hidden, in a SubViewport; camera windows render
# it from the security cameras through their own viewports.
#
# OS preferences and the window layout live in OSSettings (os_settings.json),
# separate from the facility save.
class_name CorkDesktop
extends Control

const TASKBAR_HEIGHT := 40
const REFRESH_EVERY := 0.5
const TOAST_SECONDS := 7.0
const WORLD_SCENE := "res://game/facility_world.tscn"
## Notifications kept in the notification centre.
const NOTIFICATION_HISTORY := 60
## Snap zone at the screen edges while dragging a window, in pixels.
const SNAP_MARGIN := 12.0

## [id, script] in desktop-icon order.
const APPS := [
	["duties", preload("res://os/apps/duties_app.gd")],
	["forms", preload("res://os/apps/forms_app.gd")],
	["cameras", preload("res://os/apps/cameras_app.gd")],
	["plant", preload("res://os/apps/plant_app.gd")],
	["requisitions", preload("res://os/apps/requisitions_app.gd")],
	["log", preload("res://os/apps/log_app.gd")],
	["files", preload("res://os/apps/files_app.gd")],
	["notes", preload("res://os/apps/notes_app.gd")],
	["terminal", preload("res://os/apps/terminal_app.gd")],
	["nightrun", preload("res://os/apps/nightrun_app.gd")],
	["settings", preload("res://os/apps/settings_app.gd")],
	["bin", preload("res://os/apps/bin_app.gd")],
	["devtools", preload("res://os/apps/devtools_app.gd")],
]
## Apps that aren't on the desktop until the supervisor finds them
## (Knowledge "app:<id>"): a program in the file system, say.
const HIDDEN_APPS := ["nightrun", "devtools"]

const BOOT_LINES := [
	"corkLabs firmware 3.1.4  (c) corkLabs Organic Computing",
	"Memory check ............................ OK",
	"Rail controllers ........................ 2 found",
	"Unit link: TINKER ....................... online",
	"Unit link: HAULER ....................... online",
	"Unit link: OGRE ......................... online",
	"Pod bus ................................. 4 pods in sync",
	"Coolant loop ............................ pressurised",
	"Mounting /facility ...................... OK",
	"Starting corkLabs OS ...",
]

## Where the facility is saved (tests point this elsewhere).
@export var save_path := "user://facility_save.json"
## Skip the boot screen (tests; players can turn it off in Settings).
@export var skip_boot := false

var world_viewport: SubViewport
var world: FacilityWorld
var window_layer: Control
var icons: VFlowContainer
var toast_box: VBoxContainer
var taskbar_buttons: HBoxContainer
var clock_button: Button
var output_label: Label
var alarm_button: Button
var requests_button: Button
var login: Control
var boot: Control
var notice_panel: PanelContainer
var notice_list: VBoxContainer
var context_menu: PopupMenu
var snap_preview: Panel
## Robot speech for the camera feeds (exists while logged on).
var speech: SpeechDirector
## Corporate's panel (exists while logged on).
var hq_panel: CorkHQPanel
## Brief / end of shift / dismissal / ending, over everything (while logged on).
var shift_screen: ShiftScreen
## Newest last: {"t": facility time, "heading", "body", "color", "app"}
var notifications: Array[Dictionary] = []
var unseen_notifications := 0

var _windows := {}          # app id -> OSWindow
var _refresh_left := 0.0
var _journal_mark := 0
var _time := 0.0
var _cascade := 0
var _boot_left := 0.0
var _learned_mark := -1
var _asked_mark := -1
var _icon_key := ""


func _ready() -> void:
	if FlatScreen.relaunch_if_xr(self):
		return
	theme = OSTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	apply_settings()
	_build_background()
	_build_icons()
	window_layer = Control.new()
	window_layer.name = "Windows"
	window_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	window_layer.offset_bottom = -TASKBAR_HEIGHT
	add_child(window_layer)
	snap_preview = Panel.new()
	snap_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snap_preview.add_theme_stylebox_override("panel", OSTheme.box(Color(OSTheme.ACCENT, 0.12), Color(OSTheme.ACCENT, 0.6), 6))
	snap_preview.visible = false
	add_child(snap_preview)
	_build_toasts()
	_build_taskbar()
	_build_notice_panel()
	_build_context_menu()
	_build_login()
	_build_boot()
	Facility.time_spent.connect(func(_a, _b, _c): _refresh_all())


func _process(delta: float) -> void:
	_time += delta
	if boot.visible:
		_boot_step(delta)
	if not Facility.running:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_EVERY
		_refresh_all()
	# The alarm light blinks while anything is broken.
	if alarm_button.visible:
		alarm_button.modulate.a = 0.55 + 0.45 * sin(_time * 6.0)


func _input(event: InputEvent) -> void:
	# Any key or click skips the boot screen.
	if boot.visible and (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_finish_boot()
		get_viewport().set_input_as_handled()
		return
	if shift_screen and shift_screen.blocking():
		return
	# Clicking anywhere on a window brings it to the front.
	if event is InputEventMouseButton and event.pressed and not login.visible:
		if notice_panel.visible and not notice_panel.get_global_rect().has_point(event.position) \
				and not clock_button.get_global_rect().has_point(event.position):
			notice_panel.visible = false
		if hq_panel and hq_panel.get_global_rect().has_point(event.position):
			return   # corkHQ is on top of everything; clicks there don't reach windows
		for i in range(window_layer.get_child_count() - 1, -1, -1):
			var w := window_layer.get_child(i) as OSWindow
			if w and w.visible and w.get_global_rect().has_point(event.position):
				focus_window(w)
				return


# Keys nobody else used go to the focused window's app.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed) or login.visible:
		return
	if shift_screen and shift_screen.blocking():
		return
	if event.keycode == KEY_ESCAPE and notice_panel.visible:
		notice_panel.visible = false
		get_viewport().set_input_as_handled()
		return
	var w := focused_window()
	if w and w.visible and w.app.key_input(event):
		get_viewport().set_input_as_handled()


# Right-click on the empty desktop: the desktop menu.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and Facility.running:
		context_menu.position = Vector2i(get_global_mouse_position())
		context_menu.popup()
		accept_event()


# --- Settings ----------------------------------------------------------------------------------

## Applies OSSettings (UI scale, fullscreen). Settings app calls this after changes.
func apply_settings() -> void:
	FeedAudio.apply()
	var win := get_window()
	if win and win == get_tree().root:
		win.content_scale_factor = float(OSSettings.get_value("ui_scale"))
		var want_full: bool = OSSettings.get_value("fullscreen")
		var is_full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if want_full != is_full and DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_full else DisplayServer.WINDOW_MODE_WINDOWED)


# --- Boot ------------------------------------------------------------------------------------------

func _build_boot() -> void:
	boot = ColorRect.new()
	(boot as ColorRect).color = Color.BLACK
	boot.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(boot)
	var text := OSTheme.mono_label("", 16, OSTheme.ACCENT)
	text.name = "Text"
	text.position = Vector2(48, 40)
	boot.add_child(text)
	var skip := OSTheme.mono_label("press any key", 12, OSTheme.TEXT_DIM)
	skip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	skip.position = Vector2(48, -40)
	skip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	boot.add_child(skip)
	_boot_left = 0.0
	boot.visible = not skip_boot and bool(OSSettings.get_value("boot_animation"))


func _boot_step(delta: float) -> void:
	_boot_left += delta
	var lines := int(_boot_left / 0.22)
	(boot.get_node("Text") as Label).text = "\n".join(BOOT_LINES.slice(0, mini(lines, BOOT_LINES.size())))
	if lines > BOOT_LINES.size() + 2:
		_finish_boot()


func _finish_boot() -> void:
	if not boot.visible:
		return
	boot.visible = false


# --- Session -----------------------------------------------------------------------------

func log_on() -> void:
	_finish_boot()
	Facility.start_session(FacilitySetup.systems(), save_path)
	world_viewport = SubViewport.new()
	world_viewport.name = "FacilityWorldViewport"
	world_viewport.own_world_3d = true
	world_viewport.size = Vector2i(8, 8)
	world_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED   # feeds do the rendering
	add_child(world_viewport)
	world = (load(WORLD_SCENE) as PackedScene).instantiate()
	world_viewport.add_child(world)
	speech = SpeechDirector.new()
	speech.name = "Speech"
	add_child(speech)
	hq_panel = CorkHQPanel.new()
	add_child(hq_panel)
	move_child(hq_panel, window_layer.get_index() + 1)   # above every window
	var k := Story.knowledge(Facility.sim)
	if k:
		k.forget("root")   # the maintenance account never survives a log off
		k.forget("as:dokafor")
		_learned_mark = k.learned_count
	_rebuild_icons()
	shift_screen = ShiftScreen.new()
	shift_screen.desktop = self
	add_child(shift_screen)
	_journal_mark = Facility.sim.journal.added
	login.visible = false
	if OSSettings.get_value("restore_windows"):
		_restore_layout()
	_refresh_all()
	var board := Facility.sim.get_system("work") as WorkBoard
	toast("Welcome, %s" % user_name(), "Facility time %s. %d open job(s)." % [
		FacilitySim.format_time(Facility.sim.time()), board.open_jobs().size()], OSTheme.ACCENT, "cameras")


# REQUESTS: Cameras, on the unit that's asking, with its menu open.
func _show_request() -> void:
	var cams = open_app("cameras")
	var reqs := Facility.sim.get_system("requests") as UnitRequests if Facility.running else null
	if cams == null or reqs == null or reqs.requests.is_empty():
		return
	cams.look_at_unit(str(reqs.requests[0].robot))   # it asks when you're watching


func log_off() -> void:
	save_layout()
	for id in _windows.keys():
		_windows[id].closed.disconnect(_on_closed)   # closing for log-off isn't "closed by the player"
		_windows[id].close()
	_windows.clear()
	_rebuild_taskbar()
	for t in toast_box.get_children():
		t.queue_free()
	notifications.clear()
	unseen_notifications = 0
	notice_panel.visible = false
	Facility.end_session()
	if speech:
		speech.queue_free()
		speech = null
	if hq_panel:
		hq_panel.queue_free()
		hq_panel = null
	if shift_screen:
		shift_screen.queue_free()
		shift_screen = null
	if world_viewport:
		world_viewport.queue_free()
		world_viewport = null
		world = null
	_update_login_text()
	login.visible = true


## Clocks in: the few facility minutes from the brief to the start of the
## shift (the brief's button; tests use it too).
func clock_in() -> void:
	var camp := Story.campaign(Facility.sim) if Facility.running else null
	if camp == null or camp.state != "pre":
		return
	Facility.spend(maxf(camp.shift_start_time() - Facility.sim.time(), 0.0) + 1.0, "Supervisor clocks in")


## Dismissed: back to the start of this shift (its checkpoint).
func retry_shift() -> void:
	log_off()
	Facility.restore_checkpoint(save_path)
	log_on()


## A new facility, a new supervisor. (The personnel file remembers.)
func start_over() -> void:
	log_off()
	Facility.wipe_save(save_path)
	log_on()


## The player's real first name, lightly: their Windows user name.
static func user_name() -> String:
	var n := OS.get_environment("USERNAME")
	if n.is_empty():
		n = OS.get_environment("USER")
	return n if not n.is_empty() else "Supervisor"


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and Facility.running:
		save_layout()
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
	if script == null or not app_available(id):
		return null
	Supervisor.did("open:" + id)
	var app: OSApp = script.new()
	app.desktop = self
	var win := OSWindow.new()
	win.setup(app)
	var area := window_layer.size
	var saved: Dictionary = OSSettings.windows().get(id, {})
	if saved.has("rect"):
		var r: Array = saved.rect
		win.position = Vector2(r[0], r[1])
		win.size = Vector2(r[2], r[3])
	else:
		win.position = Vector2(120 + 28 * (_cascade % 8), 30 + 26 * (_cascade % 8))
		_cascade += 1
	win.size = win.size.min(area - Vector2(20, 10)).max(OSWindow.MIN_SIZE)
	win.position = win.position.clamp(Vector2.ZERO, (area - Vector2(120, OSWindow.TITLE_HEIGHT)).max(Vector2.ZERO))
	window_layer.add_child(win)
	win.focused.connect(focus_window)
	win.minimized.connect(_on_minimized)
	win.closed.connect(_on_closed)
	win.dragging.connect(_on_window_dragging)
	win.drag_ended.connect(_on_window_drag_ended)
	_windows[id] = win
	if saved.get("maximized", false):
		win.maximize()
	if saved.has("state"):
		app.load_state(saved.state)
	focus_window(win)
	return app


static func app_title(id: String) -> String:
	for a in APPS:
		if a[0] == id:
			var app: OSApp = a[1].new()
			var t := app.title
			app.free()
			return t
	return id


## Is this app on the desktop yet? (Hidden apps have to be found first.)
func app_available(id: String) -> bool:
	if id == "devtools":
		return bool(OSSettings.get_value("devtools"))   # the Terminal's secret "dev"
	return not HIDDEN_APPS.has(id) or (Facility.running and Story.knows(Facility.sim, "app:" + id))


func focused_window() -> OSWindow:
	for w in _windows.values():
		if w.is_focused and w.visible:
			return w
	return null


func _on_minimized(w: OSWindow) -> void:
	w.visible = false
	w.set_focused(false)
	_rebuild_taskbar()


func _on_closed(w: OSWindow) -> void:
	_remember(w, false)
	OSSettings.save()
	_windows.erase(w.app.app_id)
	_rebuild_taskbar.call_deferred()


func focus_window(win: OSWindow) -> void:
	window_layer.move_child(win, -1)
	for w in _windows.values():
		w.set_focused(w == win)
	_rebuild_taskbar()


func is_open(id: String) -> bool:
	return _windows.has(id) and _windows[id].visible


## Minimise everything (desktop menu: "Show desktop").
func show_desktop() -> void:
	for w in _windows.values():
		_on_minimized(w)


## Lines the open windows up diagonally at their normal sizes.
func cascade_windows() -> void:
	var i := 0
	for w in window_layer.get_children():
		var win := w as OSWindow
		if win == null or not win.visible:
			continue
		win.restore()
		win.position = Vector2(110 + 30 * i, 20 + 30 * i)
		i += 1


func close_all_windows() -> void:
	for w in _windows.values():
		w.close()


# Snapping: drag a window to the left/right edge for half the screen, to the top to maximise.
func _snap_rect(mouse: Vector2) -> Rect2:
	var area := window_layer.size
	if mouse.y <= SNAP_MARGIN:
		return Rect2(Vector2.ZERO, area)
	if mouse.x <= SNAP_MARGIN:
		return Rect2(Vector2.ZERO, Vector2(area.x * 0.5, area.y))
	if mouse.x >= area.x - SNAP_MARGIN:
		return Rect2(Vector2(area.x * 0.5, 0), Vector2(area.x * 0.5, area.y))
	return Rect2()


func _on_window_dragging(_w: OSWindow, mouse: Vector2) -> void:
	var r := _snap_rect(mouse)
	snap_preview.visible = r.size != Vector2.ZERO
	if snap_preview.visible:
		snap_preview.position = r.position + Vector2(4, 4)
		snap_preview.size = r.size - Vector2(8, 8)
		move_child(snap_preview, window_layer.get_index() + 1)


func _on_window_drag_ended(w: OSWindow, mouse: Vector2) -> void:
	snap_preview.visible = false
	var r := _snap_rect(mouse)
	if r.size == Vector2.ZERO:
		return
	if r.position == Vector2.ZERO and r.size == window_layer.size:
		w.maximize()
	else:
		w.snap_to(r)


# --- Layout memory ---------------------------------------------------------------------------

## Remembers every open window (place, size, view state) for next time.
func save_layout() -> void:
	var saved := OSSettings.windows()
	for id in saved:
		saved[id].open = false
	for i in window_layer.get_child_count():
		var w := window_layer.get_child(i) as OSWindow
		if w and _windows.has(w.app.app_id):
			_remember(w, true)
			saved[w.app.app_id].z = i
	OSSettings.save()


func _remember(w: OSWindow, open: bool) -> void:
	var r := w.normal_rect()
	var saved := OSSettings.windows()
	var prev: Dictionary = saved.get(w.app.app_id, {})
	saved[w.app.app_id] = {"rect": [r.position.x, r.position.y, r.size.x, r.size.y], "open": open,
		"minimized": not w.visible, "maximized": w.is_maximized(), "state": w.app.save_state(), "z": prev.get("z", 0)}


func _restore_layout() -> void:
	var saved := OSSettings.windows()
	var ids := saved.keys().filter(func(id): return saved[id].get("open", false))
	ids.sort_custom(func(a, b): return int(saved[a].get("z", 0)) < int(saved[b].get("z", 0)))
	for id in ids:
		open_app(id)
		if saved[id].get("minimized", false) and _windows.has(id):
			_on_minimized(_windows[id])


# --- Notifications -----------------------------------------------------------------------

## Pops a notification up bottom right (if that kind is switched on in
## Settings) and files it in the notification centre. Clicking opens `app`.
## kind: "alarm", "report" or "" (always shown).
func toast(heading: String, body: String, color := OSTheme.ACCENT, app := "", kind := "") -> void:
	var t := Facility.sim.time() if Facility.running else 0.0
	notifications.append({"t": t, "heading": heading, "body": body, "color": color, "app": app})
	if notifications.size() > NOTIFICATION_HISTORY:
		notifications.pop_front()
	unseen_notifications += 1
	if notice_panel.visible:
		_fill_notice_panel()
	if not kind.is_empty() and not OSSettings.get_value("toast_" + kind):
		return
	var p := _notice_card(heading, body, color, app, FacilitySim.format_clock(t))
	p.custom_minimum_size = Vector2(340, 0)
	toast_box.add_child(p)
	while toast_box.get_child_count() > 5:
		toast_box.get_child(0).free()
	get_tree().create_timer(TOAST_SECONDS).timeout.connect(func():
		if is_instance_valid(p):
			var tw := p.create_tween()
			tw.tween_property(p, "modulate:a", 0.0, 0.6)
			tw.tween_callback(p.queue_free))


func _notice_card(heading: String, body: String, color: Color, app: String, clock := "") -> PanelContainer:
	var p := PanelContainer.new()
	var style := OSTheme.box(OSTheme.PANEL_LIGHT, color, 6, 12, 8)
	style.border_width_left = 4
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(col)
	var h := OSTheme.label(heading if clock.is_empty() else "%s   %s" % [heading, clock], 14, color)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(h)
	var b := OSTheme.label(body, 13)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(b)
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if not app.is_empty():
				open_app(app)
			if p.get_parent() == toast_box:
				p.queue_free())
	return p


func toggle_notice_panel() -> void:
	notice_panel.visible = not notice_panel.visible
	if notice_panel.visible:
		unseen_notifications = 0
		_fill_notice_panel()
		move_child(notice_panel, -1)
	_refresh_taskbar()


func _fill_notice_panel() -> void:
	for c in notice_list.get_children():
		c.queue_free()
	if notifications.is_empty():
		notice_list.add_child(OSTheme.label("Nothing yet.", 13, OSTheme.TEXT_DIM))
	for i in range(notifications.size() - 1, -1, -1):
		var n := notifications[i]
		notice_list.add_child(_notice_card(n.heading, n.body, n.color, n.app, FacilitySim.format_clock(n.t)))


# New journal lines: alarms and shift reports become notifications.
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
			toast("ALARM", text, OSTheme.ALARM, "plant", "alarm")
			shown += 1
		elif cat == "report":
			toast("Shift report", text.trim_prefix("Shift report: "), OSTheme.INFO, "log", "report")
			shown += 1


# --- Building ------------------------------------------------------------------------------

func _refresh_all() -> void:
	if not Facility.running:
		return
	for w in _windows.values():
		if w.visible:
			w.app.refresh()
	_refresh_taskbar()
	_check_journal()
	_check_learned()


# Something new learned: a quiet toast (commands, secrets, apps), and apps
# that have been found appear on the desktop.
func _check_learned() -> void:
	var k := Story.knowledge(Facility.sim)
	if k == null or k.learned_count == _learned_mark:
		return
	var fresh := k.learned_count - _learned_mark
	_learned_mark = k.learned_count
	for key in k.recent.slice(maxi(0, k.recent.size() - fresh)):
		if key.begins_with("secret:"):
			toast("Found", Knowledge.secret_title(key.trim_prefix("secret:")), OSTheme.WARN, "")
		elif key.begins_with("app:"):
			toast("New program", "%s is on your desktop." % app_title(key.trim_prefix("app:")), OSTheme.INFO, key.trim_prefix("app:"))
	_rebuild_icons()


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
	# Columns of icons down the left edge; wraps into a new column when the screen is short.
	icons = VFlowContainer.new()
	icons.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	icons.offset_left = 14
	icons.offset_top = 14
	icons.offset_bottom = -TASKBAR_HEIGHT - 10
	icons.add_theme_constant_override("v_separation", 8)
	icons.add_theme_constant_override("h_separation", 8)
	icons.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(icons)
	_rebuild_icons()


func _rebuild_icons() -> void:
	var ids := APPS.filter(func(a): return app_available(a[0])).map(func(a): return a[0])
	var key := ",".join(ids)
	if key == _icon_key:
		return
	_icon_key = key
	for c in icons.get_children():
		c.queue_free()
	for a in APPS:
		if not ids.has(a[0]):
			continue
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


func _build_notice_panel() -> void:
	notice_panel = PanelContainer.new()
	notice_panel.add_theme_stylebox_override("panel", OSTheme.box(OSTheme.PANEL, OSTheme.LINE, 6, 10, 10))
	notice_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	notice_panel.offset_left = -380
	notice_panel.offset_right = -8
	notice_panel.offset_top = 8
	notice_panel.offset_bottom = -TASKBAR_HEIGHT - 8
	notice_panel.visible = false
	add_child(notice_panel)
	var col := VBoxContainer.new()
	notice_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := OSTheme.label("Notifications", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var clear := Button.new()
	clear.text = "Clear"
	clear.focus_mode = Control.FOCUS_NONE
	clear.pressed.connect(func():
		notifications.clear()
		_fill_notice_panel())
	head.add_child(clear)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	notice_list = VBoxContainer.new()
	notice_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice_list.add_theme_constant_override("separation", 6)
	scroll.add_child(notice_list)


func _build_context_menu() -> void:
	context_menu = PopupMenu.new()
	context_menu.add_item("Show desktop (minimise all)", 0)
	context_menu.add_item("Cascade windows", 1)
	context_menu.add_item("Close all windows", 2)
	context_menu.add_separator()
	context_menu.add_item("Settings", 4)
	context_menu.id_pressed.connect(_on_context_menu)
	add_child(context_menu)


func _on_context_menu(id: int) -> void:
	match id:
		0: show_desktop()
		1: cascade_windows()
		2: close_all_windows()
		4: open_app("settings")


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
	var titles: Array[String] = []
	for i in APPS.size():
		var app: OSApp = APPS[i][1].new()
		titles.append(app.title)
		menu.add_item(app.title, i)
		app.free()
	menu.add_separator()
	menu.add_item("Log off", 100)
	menu.about_to_popup.connect(func():
		for i in APPS.size():
			var found := app_available(APPS[i][0])
			menu.set_item_disabled(i, not found)
			menu.set_item_text(i, titles[i] if found else "???"))
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

	requests_button = Button.new()
	requests_button.focus_mode = Control.FOCUS_NONE
	requests_button.add_theme_color_override("font_color", OSTheme.WARN)
	requests_button.add_theme_stylebox_override("normal", OSTheme.box(OSTheme.WARN.darkened(0.75), OSTheme.WARN, 4, 8, 4))
	requests_button.tooltip_text = "A unit wants a word: it asks when you watch its camera"
	requests_button.pressed.connect(_show_request)
	requests_button.visible = false
	row.add_child(requests_button)

	output_label = OSTheme.mono_label("", 13, OSTheme.TEXT_DIM)
	output_label.tooltip_text = "Facility throughput: the pods' average sync"
	output_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(output_label)

	clock_button = Button.new()
	clock_button.flat = true
	clock_button.focus_mode = Control.FOCUS_NONE
	clock_button.tooltip_text = "Facility time (click: notifications)"
	clock_button.add_theme_font_override("font", Mono.font())
	clock_button.add_theme_font_size_override("font_size", 15)
	clock_button.custom_minimum_size.x = 270
	clock_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock_button.text = "--:--"
	clock_button.pressed.connect(toggle_notice_panel)
	row.add_child(clock_button)


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
				_on_minimized(w)
			else:
				w.visible = true
				focus_window(w))
		taskbar_buttons.add_child(b)


func _refresh_taskbar() -> void:
	if not Facility.running:
		return
	var sim := Facility.sim
	var camp := Story.campaign(sim)
	var shift_text := ""
	if camp:
		shift_text = "   Shift %d/%d" % [camp.shift, Campaign.SHIFTS] + ("" if camp.on_duty() else " (off duty)")
	var dot := "● " if unseen_notifications > 0 and not notice_panel.visible else ""
	clock_button.text = dot + FacilitySim.format_time(sim.time()) + shift_text
	clock_button.add_theme_color_override("font_color", OSTheme.WARN if not dot.is_empty() else OSTheme.TEXT)
	var plant := sim.get_system("plant") as FacilityPlant
	if plant:
		output_label.text = "THROUGHPUT %d%%" % roundi(plant.throughput * 100.0)
		output_label.add_theme_color_override("font_color", OSTheme.ACCENT if plant.throughput >= 0.8 else (OSTheme.WARN if plant.throughput >= 0.6 else OSTheme.ALARM))
		var faults := PlantApp.active_faults(plant)
		alarm_button.visible = faults > 0
		alarm_button.text = "ALARM  %d" % faults
	var reqs := sim.get_system("requests") as UnitRequests
	if reqs:
		reqs.prune(Facility.sim)
		requests_button.visible = not reqs.requests.is_empty()
		requests_button.text = "REQUESTS  %d" % reqs.requests.size()
		if _asked_mark >= 0 and reqs.asked > _asked_mark and not reqs.requests.is_empty():
			var r: Dictionary = reqs.requests.back()
			var bot := sim.get_system("robot_" + str(r.robot)) as RobotAgent
			toast("%s wants a word" % (bot.display_name() if bot else str(r.robot)), "Watch it on camera to hear it out (REQUESTS on the taskbar).", OSTheme.WARN, "cameras")
		_asked_mark = reqs.asked


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
	var quit := Button.new()
	quit.text = "Shut down"
	quit.flat = true
	quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit.add_theme_color_override("font_color", OSTheme.TEXT_DIM)
	quit.pressed.connect(func(): get_tree().quit())
	col.add_child(quit)
	_update_login_text()


func _update_login_text() -> void:
	(login.find_child("Hello", true, false) as Label).text = "Welcome, %s." % user_name()
	var info := login.find_child("Info", true, false) as Label
	var t := _saved_time()
	info.text = ("Facility on hold since %s.\nIt resumes the moment you log on." % FacilitySim.format_time(t)) if t >= 0.0 \
		else "No facility on record. A new one will be brought online."
	var archive := SupervisorArchive.summary()
	if not archive.is_empty():
		info.text += "\n\n" + archive


# Reads the facility time out of the save without starting a session.
func _saved_time() -> float:
	if not FileAccess.file_exists(save_path):
		return -1.0
	var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if d is Dictionary and int(d.get("version", 0)) == FacilitySim.SAVE_VERSION:
		return int(d.get("tick", 0)) * FacilitySim.TICK
	return -1.0

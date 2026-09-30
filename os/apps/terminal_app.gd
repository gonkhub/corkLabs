# Terminal: the supervisor's command line. Everything the other apps can do,
# typed, plus quick read-outs. Orders go through Supervisor like everywhere
# else, so they cost the same facility time and get the same answers.
# Up/down arrows walk your command history. Type "help".
#
# Some commands aren't in "help": the player learns them. IT Services'
# welcome in corkHQ gives the package server's address (connect <address>);
# the server's banner explains corkpkg (list, info, request, install).
class_name TerminalApp
extends OSApp

const HELP := [
	["help", "this list"],
	["status", "clock, shift, throughput, coolant, alarms"],
	["units", "what each robot is doing, its needs and order"],
	["jobs", "open jobs on the work board"],
	["plant", "every device and its state"],
	["routes", "passages between rooms: clearance, open or blocked"],
	["block <route> [reason]", "close a passage (needs route-control)"],
	["unblock <route>", "reopen a passage (needs route-control)"],
	["order <robot> <job#|recharge|standby|cancel>", "give an order (2 min)"],
	["priority <job#> <low|normal|high|critical|+|->", "change a job's priority (2 min)"],
	["wait <minutes>", "let facility time pass (an alarm stops it)"],
	["log [lines] [category]", "the facility journal (category: alarm, work, plant, tinker...)"],
	["open <app>", "open an app (cameras, units, work, plant, log, settings...)"],
	["sound [play|loop <name> [metres|robot|room]]", "audition a sound through the camera you're listening to"],
	["sound stop | mute | unmute", "stop auditions; mute the camera feed"],
	["clear", "clear the screen"],
]

var output: RichTextLabel
var input: LineEdit
var history: PackedStringArray = []
## Connected to the Cork package server (this terminal session only).
var connected := false
var _history_pos := 0


func _init() -> void:
	app_id = "terminal"
	title = "Terminal"
	default_size = Vector2(760, 440)
	icon_text = ">_"
	icon_color = OSTheme.ACCENT


func build() -> void:
	output = RichTextLabel.new()
	output.bbcode_enabled = true
	output.scroll_following = true
	output.selection_enabled = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(output)
	var row := HBoxContainer.new()
	add_child(row)
	row.add_child(OSTheme.mono_label("supervisor@corklabs $", 13, OSTheme.ACCENT))
	input = LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_override("font", Mono.font())
	input.placeholder_text = "type help"
	input.text_submitted.connect(_submit)
	input.gui_input.connect(_on_input_key)
	row.add_child(input)
	_print("[color=#%s]corkLabs supervisor shell. Type [b]help[/b].[/color]" % _hex(OSTheme.TEXT_DIM))
	input.grab_focus.call_deferred()


## Runs one command line and returns what it printed (tests use this).
func run(line: String) -> String:
	var before := output.get_parsed_text().length()
	_submit(line)
	return output.get_parsed_text().substr(before)


func _submit(line: String) -> void:
	input.clear()
	line = line.strip_edges()
	if line.is_empty():
		return
	history.append(line)
	_history_pos = history.size()
	_print("[color=#%s]$ %s[/color]" % [_hex(OSTheme.ACCENT), _esc(line)])
	var words := line.split(" ", false)
	var cmd := words[0].to_lower()
	var args := words.slice(1)
	if sim() == null:
		_print("No facility session.")
		return
	match cmd:
		"help", "?": _help()
		"status": _status()
		"units", "robots": _units()
		"jobs": _jobs()
		"plant", "devices": _plant()
		"routes", "passages": _routes()
		"block": _block(args, true)
		"unblock": _block(args, false)
		"order": _order(args)
		"priority", "prio": _priority(args)
		"wait": _wait(args)
		"log": _log(args)
		"open": _open(args)
		"sound": _sound(args)
		"connect": _connect(args)
		"disconnect": _disconnect()
		"corkpkg": _corkpkg(args)
		"clear", "cls": output.clear()
		_: _error("Unknown command '%s'. Type help." % cmd)


func _on_input_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed) or history.is_empty():
		return
	if event.keycode == KEY_UP:
		_history_pos = maxi(_history_pos - 1, 0)
	elif event.keycode == KEY_DOWN:
		_history_pos = mini(_history_pos + 1, history.size())
	else:
		return
	input.text = history[_history_pos] if _history_pos < history.size() else ""
	input.caret_column = input.text.length()
	input.accept_event()


# --- Commands -------------------------------------------------------------------------

func _help() -> void:
	for h in HELP:
		_print("  [color=#%s]%-48s[/color] %s" % [_hex(OSTheme.ACCENT), _esc(h[0]), h[1]])
	_print("  [color=#%s](corporate servers have their own commands)[/color]" % _hex(OSTheme.TEXT_DIM))


func _status() -> void:
	var s := sim()
	var plant := s.get_system("plant") as FacilityPlant
	var shifts := s.get_system("shifts") as ShiftSchedule
	var board := s.get_system("work") as WorkBoard
	var shift := "%s shift" % shifts.current_name() if shifts and shifts.current >= 0 else "before the first shift"
	_print("  %s   %s" % [FacilitySim.format_time(s.time()), shift])
	if plant:
		_print("  throughput %d%%   coolant %d%%   heat %.1fx   dock power %d%%   faults %d" % [
			_pct(plant.throughput), _pct(plant.coolant), plant.heat(), _pct(plant.charge_factor()), PlantApp.active_faults(plant)])
	_print("  open jobs %d" % board.open_jobs().size())


func _units() -> void:
	for bot in FacilitySetup.robots(sim()):
		var order := "" if bot.order.is_empty() else "   order: " + Supervisor.describe_order(sim(), bot.order.kind, int(bot.order.get("job", -1)))
		_print("  [color=#%s]%-7s[/color] %-46s power %3d%%  stability %3d%% %s%s" % [_hex(OSTheme.category_color(bot.robot_id)),
			bot.display_name().to_upper(), _esc(bot.doing_text(sim())), _pct(bot.power), _pct(bot.stability), bot.stability_state, order])


func _jobs() -> void:
	var board := sim().get_system("work") as WorkBoard
	var layout := sim().get_system("layout") as FacilityLayout
	var open := board.open_jobs()
	if open.is_empty():
		_print("  No open jobs.")
	for j in open:
		var who := str(j.claimed_by).trim_prefix("robot_") if j.status == "claimed" else "waiting"
		_print("  #%-3d %-32s %-12s %-8s %-8s %3d%%  %s" % [j.id, _esc(j.title), layout.station(j.station).get("name", "?"),
			j.skill, WorkBoard.PRIORITY_NAMES[int(j.priority)], int(board.fraction_done(j) * 100.0), who])


func _plant() -> void:
	var plant := sim().get_system("plant") as FacilityPlant
	for id in plant.device_ids():
		_print("  " + _esc(plant.device_text(id)))


func _routes() -> void:
	var layout := sim().get_system("layout") as FacilityLayout
	for sid in layout.passages():
		var s := layout.segment(sid)
		var rooms := "%s - %s" % [layout.rooms[layout.nodes[s.a].room].name, layout.rooms[layout.nodes[s.b].room].name]
		var clearance := "any size" if is_inf(s.clearance) else "%.1f m wide" % s.clearance
		var state := ("[color=#%s]BLOCKED (%s)[/color]" % [_hex(OSTheme.ALARM), _esc(s.block_reason)]) if s.blocked else "open"
		_print("  %-14s %-26s %-12s %s" % [sid, rooms, clearance, state])


func _block(args: PackedStringArray, blocked: bool) -> void:
	var sw := sim().get_system("software") as SoftwareLibrary
	if sw and not sw.installed("route-control"):
		_error("%s: command needs the route-control package." % ("block" if blocked else "unblock"))
		return
	var layout := sim().get_system("layout") as FacilityLayout
	if args.is_empty() or layout.segment(args[0]).is_empty():
		_error("Usage: %s <route>   (see: routes)" % ("block" if blocked else "unblock"))
		return
	var reason := " ".join(args.slice(1)) if args.size() > 1 else "closed by supervisor"
	layout.set_blocked(sim(), args[0], blocked, reason)
	Facility.act("choice", "Supervisor %s %s" % ["closes" if blocked else "reopens", layout.segment(args[0]).name])
	_print("  %s is now %s." % [layout.segment(args[0]).name, "blocked" if blocked else "open"])


func _order(args: PackedStringArray) -> void:
	if args.size() < 2:
		_error("Usage: order <robot> <job#|recharge|standby|cancel>")
		return
	var bot := sim().get_system("robot_" + args[0].to_lower()) as RobotAgent
	if bot == null:
		_error("No robot called '%s'." % args[0])
		return
	var what := args[1].to_lower().trim_prefix("#")
	var r: Dictionary
	if what.is_valid_int():
		r = Supervisor.order(bot, "job", int(what))
	elif what in ["recharge", "standby", "cancel"]:
		r = Supervisor.order(bot, what)
	elif what == "stand":
		r = Supervisor.order(bot, "standby")
	else:
		_error("Order what? A job number, recharge, standby or cancel.")
		return
	_print("  Order sent to %s%s. (Its answer is on camera.)" % [bot.display_name(), "" if r.ok else ", but it's not doing it"])


func _priority(args: PackedStringArray) -> void:
	if args.size() < 2 or not args[0].trim_prefix("#").is_valid_int():
		_error("Usage: priority <job#> <low|normal|high|critical|+|->")
		return
	var id := int(args[0].trim_prefix("#"))
	var board := sim().get_system("work") as WorkBoard
	var j := board.get_job(id)
	if j.is_empty() or not (j.status == "open" or j.status == "claimed"):
		_error("No open job #%d." % id)
		return
	var p := WorkBoard.PRIORITY_NAMES.find(args[1].to_lower())
	if args[1] == "+":
		p = int(j.priority) + 1
	elif args[1] == "-":
		p = int(j.priority) - 1
	if p < 0 or p > 3:
		_error("Priority must be low, normal, high, critical, + or -.")
		return
	Supervisor.set_priority(id, p)
	_print("  Job #%d is now %s priority." % [id, WorkBoard.PRIORITY_NAMES[p]])


func _wait(args: PackedStringArray) -> void:
	if args.is_empty() or not args[0].is_valid_float() or float(args[0]) <= 0.0:
		_error("Usage: wait <minutes>")
		return
	var minutes := minf(float(args[0]), 24.0 * 60.0)
	if desktop and desktop.has_method("start_wait"):
		desktop.start_wait(minutes * 60.0)
	else:
		Supervisor.wait(minutes * 60.0)
	_print("  Waiting up to %d min. An alarm will stop it." % int(minutes))


func _log(args: PackedStringArray) -> void:
	var count := 15
	var cat := ""
	for a in args:
		if a.is_valid_int():
			count = clampi(int(a), 1, 200)
		else:
			cat = a.to_lower()
	var entries := sim().journal.entries.filter(func(e): return e.cat != "time" and (cat.is_empty() or e.cat == cat))
	for e in entries.slice(maxi(0, entries.size() - count)):
		_print("  [color=#%s]%s[/color] [color=#%s]%-10s[/color] %s" % [_hex(OSTheme.TEXT_DIM), FacilitySim.format_clock(e.t),
			_hex(OSTheme.category_color(e.cat)), e.cat, _esc(str(e.text))])


# --- Cork package server ------------------------------------------------------

func _connect(args: PackedStringArray) -> void:
	if args.is_empty():
		_error("Usage: connect <address>")
		return
	if args[0].to_lower() != CorkHQ.SERVER:
		_error("connect: %s: host not found" % args[0])
		return
	connected = true
	_print("[color=#%s]Connected to Cork Package Service (%s)[/color]" % [_hex(OSTheme.ACCENT), CorkHQ.SERVER])
	_print("  Authorised supervisors only. All activity is logged.")
	for line in [["corkpkg list", "packages on this server"], ["corkpkg info <package>", "details and clearance needed"],
			["corkpkg request <package>", "ask IT Services for approval (answer arrives in corkHQ)"],
			["corkpkg install <package> <code>", "install an approved package"], ["corkpkg installed", "what's installed"],
			["disconnect", "close the session"]]:
		_print("  [color=#%s]%-36s[/color] %s" % [_hex(OSTheme.ACCENT), line[0], line[1]])


func _disconnect() -> void:
	connected = false
	_print("  Disconnected.")


func _corkpkg(args: PackedStringArray) -> void:
	var sw := sim().get_system("software") as SoftwareLibrary
	var sub := args[0].to_lower() if not args.is_empty() else ""
	if sub == "installed":
		_print("  " + (", ".join(sw.installed_ids) if not sw.installed_ids.is_empty() else "No packages installed."))
		return
	if not connected:
		_error("corkpkg: not connected to a package server")
		return
	match sub:
		"list":
			_print("  clearance: level %d" % sw.clearance)
			for p in sw.packages:
				var state := "installed" if sw.installed(p.id) else str(sw.requests.get(p.id, {}).get("status", ""))
				var locked: bool = int(p.clearance) > sw.clearance
				_print("  %-24s %-8s %5d MB  L%d %s  %s" % [p.id, p.version, p.size, p.clearance,
					"[color=#%s]LOCKED[/color]" % _hex(OSTheme.ALARM) if locked else "      ", state])
		"info":
			var p := sw.package(args[1] if args.size() > 1 else "")
			if p.is_empty():
				_error("Usage: corkpkg info <package>")
				return
			_print("  %s %s  (%d MB, clearance %d, installs in %d min)" % [p.name, p.version, p.size, p.clearance, int(p.minutes)])
			_print("  " + _esc(p.description))
		"request":
			if args.size() < 2:
				_error("Usage: corkpkg request <package>")
				return
			_print("  " + _esc(sw.request(sim(), args[1])))
		"install":
			if args.size() < 3:
				_error("Usage: corkpkg install <package> <code>")
				return
			var r := sw.install(sim(), args[1], args[2])
			if not r.ok:
				_error(r.text)
				return
			_print("  Downloading %s ..." % args[1])
			_print("  [color=#%s][####################] 100%%[/color]" % _hex(OSTheme.ACCENT))
			Facility.spend(float(r.minutes) * 60.0, "Installing %s" % args[1])
			_print("  " + _esc(r.text) + " (%d facility minutes)" % int(r.minutes))
		_:
			_error("Usage: corkpkg list | info | request | install | installed")


func _open(args: PackedStringArray) -> void:
	if args.is_empty() or desktop == null:
		_error("Usage: open <app>")
		return
	var id := args[0].to_lower()
	if desktop.open_app(id) == null:
		_error("No app called '%s'." % id)


# Auditioning: play a sound in the facility and hear it through the camera
# you're listening to, with that camera's distance, panning and walls.
func _sound(args: PackedStringArray) -> void:
	var world: FacilityWorld = desktop.world if desktop else null
	if world == null:
		_error("No facility world (log on first).")
		return
	var sub := args[0].to_lower() if args.size() > 0 else "list"
	match sub:
		"list":
			var listening := "camera %d (%s)" % [world.listener_cam + 1, world.cameras[world.listener_cam].display_name] 				if world.listener_cam >= 0 else "no camera (open Cameras; in the grid, point at a feed)"
			_print("  Listening through: %s%s" % [_esc(listening), "  [MUTED]" if FeedAudio.is_muted() else ""])
			_print("  Sounds (%s, then built-in): %s" % [SoundBank.SOUNDS_DIR, ", ".join(SoundBank.library())])
			_print("  [color=#%s]sound play <name> [metres ahead | robot | room]   sound loop ...   sound stop[/color]" % _hex(OSTheme.TEXT_DIM))
		"stop":
			_print("  Stopped %d sound(s)." % world.stop_auditions())
		"mute", "unmute":
			FeedAudio.set_muted(sub == "mute")
			if desktop.has_method("_refresh_all"):
				desktop._refresh_all()
			_print("  Camera feed %s." % ("muted" if sub == "mute" else "unmuted"))
		"play", "loop":
			if args.size() < 2:
				_error("Usage: sound %s <name> [metres ahead | robot | room]" % sub)
				return
			var stream := SoundBank.find_stream(args[1])
			if stream == null:
				_error("No sound '%s'. Type 'sound' for the list." % args[1])
				return
			var loop := sub == "loop"
			var where := args[2].to_lower() if args.size() > 2 else "10"
			var s: FacilitySound
			var said := ""
			if world.views.has(where):
				s = world.attach_sound(stream, where, loop)
				said = "on " + where.capitalize()
			elif world.layout.rooms.has(where):
				var rect: Rect2 = world.layout.rooms[where].rect
				s = world.play_sound(stream, Vector3(rect.get_center().x, 1.5, rect.get_center().y), loop)
				said = "in the middle of " + str(world.layout.rooms[where].name)
			elif where.is_valid_float():
				if world.listener_cam < 0:
					_error("Not listening through a camera: open Cameras, or give a robot or room.")
					return
				var cam := world.cameras[world.listener_cam]
				var at := cam.global_position - cam.global_transform.basis.z * float(where)
				s = world.play_sound(stream, at, loop)
				said = "%s m in front of camera %d" % [where, world.listener_cam + 1]
			else:
				_error("'%s' isn't a distance, robot (%s) or room (%s)." % [where, ", ".join(world.views.keys()), ", ".join(world.layout.rooms.keys())])
				return
			_print("  %s '%s' %s (room: %s)%s" % ["Looping" if loop else "Playing", args[1], said,
				s.current_room() if not s.current_room().is_empty() else "none", ", 'sound stop' to end" if loop else ""])
		_:
			_error("Usage: sound [list|play|loop|stop|mute|unmute]")


# --- Output --------------------------------------------------------------------------------

func _print(bbcode: String) -> void:
	output.append_text(bbcode + "\n")


func _error(text: String) -> void:
	_print("  [color=#%s]%s[/color]" % [_hex(OSTheme.WARN), _esc(text)])


static func _esc(t: String) -> String:
	return t.replace("[", "[lb]")


static func _hex(c: Color) -> String:
	return c.to_html(false)


static func _pct(x: float) -> int:
	return roundi(x * 100.0)

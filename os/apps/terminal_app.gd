# Terminal: the supervisor's command line. Everything the other apps can do,
# typed, plus quick read-outs. Orders go through Supervisor like everywhere
# else, so they cost the same facility time and get the same answers.
# Up/down arrows walk your command history. Type "help".
class_name TerminalApp
extends OSApp

const HELP := [
	["help", "this list"],
	["status", "clock, shift, throughput, coolant, alarms"],
	["units", "what each robot is doing, its needs and order"],
	["jobs", "open jobs on the work board"],
	["plant", "every device and its state"],
	["routes", "passages between rooms: clearance, open or blocked"],
	["block <route> [reason]", "close a passage (dev: test re-routing)"],
	["unblock <route>", "reopen a passage"],
	["order <robot> <job#|recharge|standby|cancel>", "give an order (2 min)"],
	["priority <job#> <low|normal|high|critical|+|->", "change a job's priority (2 min)"],
	["wait <minutes>", "let facility time pass (an alarm stops it)"],
	["log [lines] [category]", "the facility journal (category: alarm, work, plant, tinker...)"],
	["open <app>", "open an app (cameras, units, work, plant, log, settings...)"],
	["clear", "clear the screen"],
]

var output: RichTextLabel
var input: LineEdit
var history: PackedStringArray = []
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
		_print("  [color=#%s]%-7s[/color] %-46s power %3d%%  purpose %3d%% %s%s" % [_hex(OSTheme.category_color(bot.robot_id)),
			bot.display_name().to_upper(), _esc(bot.doing_text(sim())), _pct(bot.power), _pct(bot.purpose), bot.mood, order])


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


func _open(args: PackedStringArray) -> void:
	if args.is_empty() or desktop == null:
		_error("Usage: open <app>")
		return
	var id := args[0].to_lower()
	if desktop.open_app(id) == null:
		_error("No app called '%s'." % id)


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

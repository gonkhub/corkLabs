# Terminal: the supervisor's command line, and the part of the OS the
# player has to LEARN. "help" only lists the commands this supervisor knows
# (Knowledge "cmd:<name>"); a new supervisor knows a handful. The rest are
# found in files, in what corkHQ and the units say, in a game... Typing a real
# command works whether or not help lists it, and teaches it: what the
# PLAYER remembers carries over between runs.
#
# Also here:
#   the file system    ls, cd, cat, pwd, decrypt, run (Story / VirtualFS)
#   talk <unit>        a conversation over the unit link: numbered replies
#   su maint           the "decommissioned" maintenance account, and its
#                      commands (auditctl, hqctl, unitctl, pkgctl, podctl).
#                      Every one of them is a policy violation.
#
# Orders and duties go through Supervisor like everywhere else, so they cost
# the same facility time. Up/down arrows walk the command history.
class_name TerminalApp
extends OSApp

## name -> [usage, what it does, group]
const COMMANDS := {
	"help": ["help [command]", "the commands you know, or how to use one", "basics"],
	"status": ["status", "clock, shift, throughput, coolant, alarms", "basics"],
	"clear": ["clear", "clear the screen", "basics"],
	"open": ["open <app>", "open an app (cameras, units, work, plant, files, duties...)", "basics"],
	"whoami": ["whoami", "who this terminal thinks you are", "basics"],
	"duties": ["duties", "this shift's checklist", "shift"],
	"duty": ["duty <id>", "do a duty from the checklist (takes its time)", "shift"],
	"log": ["log [lines] [category]", "the facility journal (category: alarm, work, plant, tinker...)", "shift"],
	"units": ["units", "what each unit is doing, its needs and order", "units"],
	"jobs": ["jobs", "open jobs on the work board", "units"],
	"order": ["order <unit> <job#|recharge|standby|cancel>", "give an order (2 min)", "units"],
	"priority": ["priority <job#> <low|normal|high|critical|+|->", "change a job's priority (2 min)", "units"],
	"talk": ["talk <unit>", "open the unit link and talk (1 min a line)", "units"],
	"reboot": ["reboot <unit>", "remote reboot (needs remote-reboot)", "units"],
	"plant": ["plant", "every device and its state", "plant"],
	"routes": ["routes", "passages between rooms: clearance, open or blocked", "plant"],
	"block": ["block <route> [reason]", "close a passage (needs route-control)", "plant"],
	"unblock": ["unblock <route>", "reopen a passage (needs route-control)", "plant"],
	"ls": ["ls [-a] [-l] [folder]", "what's in a folder (-a: hidden files too)", "files"],
	"cd": ["cd <folder>", "change folder (cd .. goes up, cd ~ goes home)", "files"],
	"pwd": ["pwd", "which folder you're in", "files"],
	"cat": ["cat <file>", "read a file (takes time the first time)", "files"],
	"decrypt": ["decrypt <file> <password>", "unlock an encrypted file", "files"],
	"run": ["run <program>", "run a program", "files"],
	"connect": ["connect <address>", "open a session with a corporate server", "network"],
	"disconnect": ["disconnect", "close it", "network"],
	"corkpkg": ["corkpkg list|info|request|install|installed", "the Cork package service", "network"],
	"su": ["su <account>", "switch account", "maintenance"],
	"exit": ["exit", "leave the maintenance account", "maintenance"],
	"auditctl": ["auditctl list | purge", "corporate's audit trail of this terminal", "maintenance"],
	"hqctl": ["hqctl status | mute <minutes> | unmute", "the corkHQ link", "maintenance"],
	"unitctl": ["unitctl <unit> reset", "reset a unit's software stability", "maintenance"],
	"pkgctl": ["pkgctl force <package>", "install a package without approval", "maintenance"],
	"podctl": ["podctl list | inspect <pod> | wake <pod>", "the pods", "maintenance"],
	"sound": ["sound [play|loop|stop|mute|unmute] ...", "audition a sound through the camera you're listening to", "dev"],
}
const GROUPS := ["basics", "shift", "units", "plant", "files", "network", "maintenance"]
const ROOT_ONLY := ["auditctl", "hqctl", "unitctl", "pkgctl", "podctl"]
const ALIASES := {"?": "help", "robots": "units", "devices": "plant", "passages": "routes", "prio": "priority",
	"cls": "clear", "dir": "ls", "type": "cat", "logout": "exit", "chat": "talk"}
const ROOT_ACCOUNT := "maint"
## Suspicion added by a root action (on top of logging in).
const ROOT_VIOLATION := 6.0
const SU_VIOLATION := 10.0

var output: RichTextLabel
var input: LineEdit
var prompt_label: Label
var history: PackedStringArray = []
## Connected to the Cork package server (this terminal session only).
var connected := false
## Logged in as the maintenance account (this terminal session only).
var root := false
var cwd := VirtualFS.HOME
## "", "password" (su), "talk" (a conversation), "wake" (confirming podctl wake)
var mode := ""
var talk_runner: Dialogue.Runner
var talk_bot: RobotAgent
var _pending := ""
var _history_pos := 0


func _init() -> void:
	app_id = "terminal"
	title = "Terminal"
	default_size = Vector2(780, 460)
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
	prompt_label = OSTheme.mono_label("", 13, OSTheme.ACCENT)
	row.add_child(prompt_label)
	input = LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_override("font", Mono.font())
	input.placeholder_text = "type help"
	input.text_submitted.connect(_submit)
	input.gui_input.connect(_on_input_key)
	row.add_child(input)
	_print("[color=#%s]corkLabs supervisor shell 3.1.4. Type [b]help[/b].[/color]" % _hex(OSTheme.TEXT_DIM))
	_update_prompt()
	input.grab_focus.call_deferred()


## Runs one command line and returns what it printed (tests use this).
func run(line: String) -> String:
	var before := output.get_parsed_text().length()
	_submit(line)
	return output.get_parsed_text().substr(before)


func save_state() -> Dictionary:
	return {"cwd": cwd}


func load_state(state: Dictionary) -> void:
	cwd = str(state.get("cwd", VirtualFS.HOME))
	_update_prompt()


func _submit(line: String) -> void:
	input.clear()
	if mode == "password":
		_finish_su(line)
		return
	line = line.strip_edges()
	if mode == "talk":
		_talk_input(line)
		return
	if mode == "wake":
		_finish_wake(line)
		return
	if line.is_empty():
		return
	history.append(line)
	_history_pos = history.size()
	_print("[color=#%s]%s %s[/color]" % [_hex(_prompt_color()), _esc(_prompt_text()), _esc(line)])
	var words := line.split(" ", false)
	var cmd: String = words[0].to_lower()
	cmd = ALIASES.get(cmd, cmd)
	var args := words.slice(1)
	if sim() == null:
		_print("No facility session.")
		return
	if not COMMANDS.has(cmd):
		_error("%s: command not found" % cmd)
		return
	# A real command: typing it is how you learn it (dev commands stay out of help).
	if COMMANDS[cmd][2] != "dev" and Story.learn(sim(), "cmd:" + cmd):
		_print("  [color=#%s](new command noted: %s. help %s)[/color]" % [_hex(OSTheme.INFO), cmd, cmd])
	if cmd in ROOT_ONLY and not root:
		_error("%s: permission denied (maintenance account only)" % cmd)
		return
	match cmd:
		"help": _help(args)
		"status": _status()
		"clear": output.clear()
		"open": _open(args)
		"whoami": _whoami()
		"duties": _duties()
		"duty": _duty(args)
		"log": _log(args)
		"units": _units()
		"jobs": _jobs()
		"order": _order(args)
		"priority": _priority(args)
		"talk": _talk(args)
		"reboot": _reboot(args)
		"plant": _plant()
		"routes": _routes()
		"block": _block(args, true)
		"unblock": _block(args, false)
		"ls": _ls(args)
		"cd": _cd(args)
		"pwd": _print("  " + cwd)
		"cat": _cat(args)
		"decrypt": _decrypt(args)
		"run": _run(args)
		"connect": _connect(args)
		"disconnect": _disconnect()
		"corkpkg": _corkpkg(args)
		"su": _su(args)
		"exit": _exit()
		"auditctl": _auditctl(args)
		"hqctl": _hqctl(args)
		"unitctl": _unitctl(args)
		"pkgctl": _pkgctl(args)
		"podctl": _podctl(args)
		"sound": _sound(args)


func _on_input_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_ESCAPE and mode != "":
		if mode == "talk":
			_end_talk()
		else:
			_print("  (cancelled)")
			_set_mode("")
		input.accept_event()
		return
	if history.is_empty() or mode != "":
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


func _set_mode(m: String) -> void:
	mode = m
	input.secret = m == "password"
	_update_prompt()


func _prompt_text() -> String:
	match mode:
		"password": return "Password:"
		"talk": return "reply [1-%d, 0 closes] >" % (talk_runner.choices.size() if talk_runner else 0)
		"wake": return "confirm pod >"
	var where := cwd
	if where == VirtualFS.HOME or where.begins_with(VirtualFS.HOME + "/"):
		where = "~" + where.substr(VirtualFS.HOME.length())
	return "%s@corklabs:%s%s" % [ROOT_ACCOUNT if root else "supervisor", where, "#" if root else "$"]


func _prompt_color() -> Color:
	if mode == "talk" and talk_bot:
		return OSTheme.category_color(talk_bot.robot_id)
	return OSTheme.WARN if root else OSTheme.ACCENT


func _update_prompt() -> void:
	if prompt_label:
		prompt_label.text = _prompt_text()
		prompt_label.add_theme_color_override("font_color", _prompt_color())


# --- Help ------------------------------------------------------------------------------

func _knows(cmd: String) -> bool:
	return Story.knows(sim(), "cmd:" + cmd)


func _help(args: PackedStringArray) -> void:
	if not args.is_empty():
		var c: String = ALIASES.get(args[0].to_lower(), args[0].to_lower())
		if not COMMANDS.has(c) or not _knows(c):
			_error("help: no help for '%s'" % args[0])
			return
		_print("  [color=#%s]%s[/color]" % [_hex(OSTheme.ACCENT), _esc(COMMANDS[c][0])])
		_print("  " + _esc(COMMANDS[c][1]) + (" [color=#%s](maintenance account)[/color]" % _hex(OSTheme.WARN) if c in ROOT_ONLY else ""))
		return
	_print("  Commands you know ([b]help <command>[/b] for how to use one):")
	var known := 0
	var total := 0
	for g in GROUPS:
		var names := PackedStringArray()
		for c in COMMANDS:
			if COMMANDS[c][2] != g:
				continue
			total += 1
			if _knows(c):
				names.append(c)
				known += 1
		if not names.is_empty():
			_print("    [color=#%s]%-12s[/color] %s" % [_hex(OSTheme.TEXT_DIM), g, "  ".join(names)])
	if known < total:
		_print("  [color=#%s]There are more. There are always more.[/color]" % _hex(OSTheme.TEXT_DIM))


# --- Facility read-outs ---------------------------------------------------------------

func _status() -> void:
	var s := sim()
	var plant := s.get_system("plant") as FacilityPlant
	var board := s.get_system("work") as WorkBoard
	var camp := Story.campaign(s)
	var shift := "%s (%s)" % [camp.title(), camp.state.replace("_", " ")] if camp else ""
	_print("  %s   %s" % [FacilitySim.format_time(s.time()), shift])
	if plant:
		_print("  throughput %d%% (target %d%%)   coolant %d%%   heat %.1fx   dock power %d%%   faults %d" % [
			_pct(plant.throughput), _pct(CorkHQ.TARGET), _pct(plant.coolant), plant.heat(), _pct(plant.charge_factor()), PlantApp.active_faults(plant)])
	_print("  open jobs %d%s" % [board.open_jobs().size(), "   duties done %d/%d" % [camp.duties_done(), camp.duties.size()] if camp else ""])


func _whoami() -> void:
	var o := Story.oversight(sim())
	var camp := Story.campaign(sim())
	if root:
		_print("  maint  (legacy maintenance account, decommissioned 2011)")
		return
	_print("  supervisor  (probationary%s)" % (", shift %d of %d" % [camp.shift, Campaign.SHIFTS] if camp else ""))
	if o:
		var opinion := "exemplary" if o.standing >= 85 else ("good" if o.standing >= 65 else ("adequate" if o.standing >= 45 else ("poor" if o.standing >= 20 else "untenable")))
		_print("  corporate's opinion of you: %s%s" % [opinion, "   formal warnings: %d" % o.strikes if o.strikes > 0 else ""])


func _duties() -> void:
	var camp := Story.campaign(sim())
	if camp == null or camp.duties.is_empty():
		_print("  No duties.")
		return
	_print("  %s: duties" % camp.title())
	for d in camp.duties:
		var mark := "[color=#%s]done[/color]" % _hex(OSTheme.ACCENT) if d.done else ("from %s" % d.after if not str(d.after).is_empty() else "    ")
		_print("  %-6s %-15s %-44s %s" % [mark, d.id, _esc(d.title), ("%d min" % int(d.minutes)) if float(d.minutes) > 0.0 else ""])
	_print("  [color=#%s]duty <id> to do one.[/color]" % _hex(OSTheme.TEXT_DIM))


func _duty(args: PackedStringArray) -> void:
	if args.is_empty():
		_error("Usage: duty <id>   (see: duties)")
		return
	var why: String = Supervisor.do_duty(args[0].to_lower())
	if why.is_empty():
		_print("  Done: %s." % Story.campaign(sim()).duty(args[0].to_lower()).title)
	else:
		_error("duty: " + why)


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


func _bot(name: String) -> RobotAgent:
	return sim().get_system("robot_" + name.to_lower()) as RobotAgent


func _order(args: PackedStringArray) -> void:
	if args.size() < 2:
		_error("Usage: order <unit> <job#|recharge|standby|cancel>")
		return
	var bot := _bot(args[0])
	if bot == null:
		_error("No unit called '%s'." % args[0])
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


func _reboot(args: PackedStringArray) -> void:
	var bot := _bot(args[0]) if not args.is_empty() else null
	if bot == null:
		_error("Usage: reboot <unit>")
		return
	if not Supervisor.has_software("remote-reboot"):
		_error("reboot: needs the remote-reboot package")
		return
	_print("  " + ("Rebooting %s." % bot.display_name() if Supervisor.reboot(bot) else "%s is offline already." % bot.display_name()))


func _log(args: PackedStringArray) -> void:
	var count := 15
	var cat := ""
	for a in args:
		if a.is_valid_int():
			count = clampi(int(a), 1, 200)
		else:
			cat = a.to_lower()
	var entries := sim().journal.entries.filter(func(e): return e.cat != "time" and e.cat != "oversight" and (cat.is_empty() or e.cat == cat))
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


# --- Files -----------------------------------------------------------------------------

func _ls(args: PackedStringArray) -> void:
	var show_all := false
	var long := false
	var target := cwd
	for a in args:
		if a.begins_with("-"):
			show_all = show_all or a.contains("a")
			long = long or a.contains("l")
		else:
			target = VirtualFS.normalize(cwd, a)
	if show_all:
		Story.learn(sim(), "hidden_files")   # the Files app can show them now too
	var e := Story.fs().get_entry(target)
	if e.is_empty() or not Story.exists(sim(), target):
		_error("ls: %s: No such file or directory" % target)
		return
	if not e.dir:
		_print("  " + _file_line(e, long))
		return
	var items := Story.list(sim(), target, show_all)
	if items.is_empty():
		_print("  [color=#%s](empty)[/color]" % _hex(OSTheme.TEXT_DIM))
	if long:
		for it in items:
			_print("  " + _file_line(it, true))
	else:
		var names := PackedStringArray()
		for it in items:
			names.append(_file_name(it))
		_print("  " + "   ".join(names))


func _file_name(e: Dictionary) -> String:
	if e.dir:
		return "[color=#%s]%s/[/color]" % [_hex(OSTheme.INFO), _esc(e.name)]
	if e.meta.has("exec"):
		return "[color=#%s]%s*[/color]" % [_hex(OSTheme.WARN), _esc(e.name)]
	if Story.is_encrypted(sim(), e):
		return "[color=#%s]%s[/color]" % [_hex(OSTheme.ALARM), _esc(e.name)]
	return _esc(e.name)


func _file_line(e: Dictionary, long: bool) -> String:
	if not long:
		return _file_name(e)
	var kind := "d" if e.dir else ("x" if e.meta.has("exec") else ("e" if Story.is_encrypted(sim(), e) else "-"))
	var size := 0 if e.dir else str(e.body).length()
	return "%s %-10s %6d  %-12s %s" % [kind, e.meta.get("owner", "root"), size, e.meta.get("date", ""), _file_name(e)]


func _cd(args: PackedStringArray) -> void:
	var target := VirtualFS.normalize(cwd, args[0] if not args.is_empty() else "~")
	var e := Story.fs().get_entry(target)
	if e.is_empty() or not Story.exists(sim(), target):
		_error("cd: %s: No such file or directory" % target)
		return
	if not e.dir:
		_error("cd: %s: Not a directory" % target)
		return
	cwd = target
	_update_prompt()


func _cat(args: PackedStringArray) -> void:
	if args.is_empty():
		_error("Usage: cat <file>")
		return
	var path := VirtualFS.normalize(cwd, args[0])
	var r: Dictionary = Supervisor.read_file(path)
	if not r.ok:
		if r.get("encrypted", false):
			_print("[color=#%s]%s[/color]" % [_hex(OSTheme.TEXT_DIM), _esc(str(r.text))])
		_error(r.error)
		return
	if r.entry.meta.has("exec"):
		_print("  [color=#%s]%s[/color]" % [_hex(OSTheme.TEXT_DIM), _esc(str(r.text))])
		return
	_print(_esc(str(r.text)))
	if r.first and float(r.minutes) > 0.0:
		_print("  [color=#%s](%d min reading)[/color]" % [_hex(OSTheme.TEXT_DIM), int(r.minutes)])
	for key in r.learned:
		if str(key).begins_with("cmd:"):
			_print("  [color=#%s](new command noted: %s)[/color]" % [_hex(OSTheme.INFO), str(key).trim_prefix("cmd:")])


func _decrypt(args: PackedStringArray) -> void:
	if args.size() < 2:
		_error("Usage: decrypt <file> <password>")
		return
	var r: Dictionary = Supervisor.decrypt(VirtualFS.normalize(cwd, args[0]), " ".join(args.slice(1)))
	if r.ok:
		_print("  " + _esc(r.text))
	else:
		_error(r.text)


func _run(args: PackedStringArray) -> void:
	if args.is_empty():
		_error("Usage: run <program>")
		return
	var path := VirtualFS.normalize(cwd, args[0])
	var e := Story.fs().get_entry(path)
	if e.is_empty() or not Story.exists(sim(), path):
		# By name, from the usual places.
		for dir in ["/opt/games", "/opt"]:
			var p: String = str(dir) + "/" + args[0]
			if Story.exists(sim(), p):
				path = p
				e = Story.fs().get_entry(p)
				break
	if e.is_empty() or not Story.exists(sim(), path):
		_error("run: %s: not found" % args[0])
		return
	if not e.meta.has("exec"):
		_error("run: %s: not a program" % args[0])
		return
	var app_id: String = e.meta.exec
	Story.learn(sim(), "app:" + app_id)
	if desktop == null or desktop.open_app(app_id) == null:
		_error("run: %s: failed to start" % args[0])
		return
	_print("  Starting %s ..." % e.name)


# --- Talking to units ------------------------------------------------------------------

## Opens a conversation (Units' Talk button calls this too).
func start_talk(robot_id: String) -> void:
	if mode != "":
		_end_talk()
	var bot := _bot(robot_id)
	if bot == null:
		_error("talk: no unit called '%s'" % robot_id)
		return
	var r: Dictionary = Supervisor.talk_begin(bot)
	if r.runner == null:
		_error(r.error)
		return
	talk_runner = r.runner
	talk_bot = bot
	_print("  [color=#%s][unit link open: %s][/color]" % [_hex(OSTheme.TEXT_DIM), bot.display_name().to_upper()])
	_show_lines(r.lines)
	_after_lines()


func _talk(args: PackedStringArray) -> void:
	if args.is_empty():
		_error("Usage: talk <unit>   (%s)" % ", ".join(FacilitySetup.robots(sim()).map(func(b): return b.robot_id)))
		return
	start_talk(args[0].to_lower())


func _talk_input(line: String) -> void:
	if line.is_empty():
		return
	if line == "0" or line.to_lower() in ["bye", "exit", "quit"]:
		_end_talk()
		return
	if not line.is_valid_int() or int(line) < 1 or int(line) > talk_runner.choices.size():
		_error("Pick a reply: 1-%d (0 closes the link)." % talk_runner.choices.size())
		return
	var i := int(line) - 1
	_print("  [color=#%s]> %s[/color]" % [_hex(OSTheme.ACCENT), _esc(talk_runner.choices[i].text)])
	_show_lines(Supervisor.talk_choose(talk_runner, talk_bot, i))
	_after_lines()


func _show_lines(lines: Array) -> void:
	for l in lines:
		if l.speaker == "sys":
			_print("  [color=#%s][i]%s[/i][/color]" % [_hex(OSTheme.TEXT_DIM), _esc(l.text)])
		else:
			var who: String = "YOU" if l.speaker == "you" else str(l.speaker).to_upper()
			_print("  [color=#%s]%s:[/color] %s" % [_hex(OSTheme.category_color(l.speaker)), who, _esc(l.text)])


func _after_lines() -> void:
	if talk_runner == null or talk_runner.done or talk_runner.choices.is_empty():
		_end_talk()
		return
	for i in talk_runner.choices.size():
		_print("    [color=#%s]%d)[/color] %s" % [_hex(OSTheme.ACCENT), i + 1, _esc(talk_runner.choices[i].text)])
	_set_mode("talk")


func _end_talk() -> void:
	if talk_bot:
		_print("  [color=#%s][unit link closed][/color]" % _hex(OSTheme.TEXT_DIM))
	talk_runner = null
	talk_bot = null
	_set_mode("")


# --- The maintenance account -----------------------------------------------------------

func _su(args: PackedStringArray) -> void:
	var account := args[0].to_lower() if not args.is_empty() else "root"
	if account != ROOT_ACCOUNT:
		_error("su: user %s does not exist or is not permitted" % account)
		return
	if root:
		_print("  Already %s." % ROOT_ACCOUNT)
		return
	_pending = account
	_set_mode("password")


func _finish_su(password: String) -> void:
	_set_mode("")
	var o := Story.oversight(sim())
	if password.strip_edges() != Story.MAINT_PASSWORD:
		_error("su: Authentication failure")
		if o:
			o.violate(sim(), "failed login to the decommissioned maintenance account", 3.0)
		return
	root = true
	cwd = "/"
	Story.learn(sim(), "root")
	Story.learn(sim(), "secret:maint_account")
	if o:
		o.violate(sim(), "login to the decommissioned maintenance account", SU_VIOLATION)
	Facility.act("dialogue_line", "Supervisor logs in as %s" % ROOT_ACCOUNT)
	_print("[color=#%s]  Last login: 2011-06-02 13:51 (rmarrow). Welcome back.[/color]" % _hex(OSTheme.WARN))
	_print("[color=#%s]  maintenance commands: auditctl  hqctl  unitctl  pkgctl  podctl   (exit to leave)[/color]" % _hex(OSTheme.WARN))
	for c in ROOT_ONLY:
		Story.learn(sim(), "cmd:" + c)
	Story.learn(sim(), "cmd:exit")
	_update_prompt()


func _exit() -> void:
	if not root:
		_error("logout: not permitted. (There is no door.)")
		return
	leave_root()
	_print("  logout")


## Drops the maintenance account (exit, log off).
func leave_root() -> void:
	root = false
	var k := Story.knowledge(sim())
	if k:
		k.forget("root")
	if cwd.begins_with("/sys/pods"):
		cwd = VirtualFS.HOME
	_update_prompt()


func _root_act(what: String, amount := ROOT_VIOLATION, catch_chance := 0.0) -> void:
	var o := Story.oversight(sim())
	if o:
		o.violate(sim(), what, amount, catch_chance)
	Facility.act("choice", "Maintenance: " + what)


func _auditctl(args: PackedStringArray) -> void:
	var o := Story.oversight(sim())
	var sub := args[0].to_lower() if not args.is_empty() else "list"
	match sub:
		"list":
			Story.learn(sim(), "secret:audit_trail")
			_print("  AUDIT TRAIL (what corkHQ can see)   suspicion index: %d" % roundi(o.suspicion))
			if o.trail.is_empty():
				_print("  (empty)")
			for t in o.trail:
				_print("  %s  +%-4.1f %s" % [FacilitySim.format_clock(t.t), t.amount, _esc(str(t.what))])
		"purge":
			var key := "audit_purged:%d" % Story.shift(sim())
			if Story.knows(sim(), key):
				_error("auditctl: purge already run this shift (a second gap would be noticed)")
				return
			Story.learn(sim(), key)
			var n := o.purge_trail(sim())
			_root_act("audit trail discontinuity", 5.0)
			_print("  Purged %d entries. The purge itself is logged; that can't be helped." % n)
		_:
			_error("Usage: auditctl list | purge")


func _hqctl(args: PackedStringArray) -> void:
	var o := Story.oversight(sim())
	var sub := args[0].to_lower() if not args.is_empty() else "status"
	match sub:
		"status":
			_print("  corkHQ link: %s" % ("SUSPENDED until %s" % FacilitySim.format_clock(o.hq_muted_until) if o.hq_muted(sim()) else "open"))
		"mute":
			var minutes := clampf(float(args[1]) if args.size() > 1 and args[1].is_valid_float() else 60.0, 5.0, 180.0)
			o.hq_muted_until = sim().time() + minutes * 60.0
			Story.learn(sim(), "secret:hq_silence")
			_root_act("corkHQ link suspended", 4.0)
			_print("  corkHQ link suspended for %d minutes." % int(minutes))
			if desktop and desktop.hq_panel:
				desktop.hq_panel.refresh_now()
		"unmute":
			o.hq_muted_until = -1.0
			_print("  corkHQ link restored.")
			if desktop and desktop.hq_panel:
				desktop.hq_panel.refresh_now()
		_:
			_error("Usage: hqctl status | mute <minutes> | unmute")


func _unitctl(args: PackedStringArray) -> void:
	if args.size() < 2 or args[1].to_lower() != "reset" or _bot(args[0]) == null:
		_error("Usage: unitctl <unit> reset")
		return
	var bot := _bot(args[0])
	bot.stability = maxf(bot.stability, 0.8)
	_root_act("manual override of unit %s firmware" % bot.display_name())
	_print("  %s: software stability reset to %d%%." % [bot.display_name(), _pct(bot.stability)])


func _pkgctl(args: PackedStringArray) -> void:
	var sw := sim().get_system("software") as SoftwareLibrary
	if args.size() < 2 or args[0].to_lower() != "force" or sw.package(args[1]).is_empty():
		_error("Usage: pkgctl force <package>   (corkpkg list shows them, when connected)")
		return
	if sw.installed(args[1]):
		_error("pkgctl: %s is already installed" % args[1])
		return
	var p := sw.package(args[1])
	sw.force_install(sim(), args[1])
	_print("  Forcing %s %s past approval ..." % [p.name, p.version])
	_root_act("unapproved software installed: %s" % args[1], 15.0, 0.35)
	Facility.spend(float(p.minutes) * 60.0, "Installing %s" % args[1])
	_print("  Installed. IT Services was not told. Probably.")


func _podctl(args: PackedStringArray) -> void:
	var sub := args[0].to_lower() if not args.is_empty() else "list"
	var plant := sim().get_system("plant") as FacilityPlant
	match sub:
		"list":
			_print("  POD  OCCUPANT   SYNC   SINCE")
			for p in Story.pods():
				var d := plant.device("pod_" + str(p.pod)) if plant else {}
				_print("  %-4s %-10s %4d%%   %s" % [p.pod, p.occupant, _pct(float(d.get("value", 1.0))), p.since])
			_print("  [color=#%s]podctl inspect <pod>[/color]" % _hex(OSTheme.TEXT_DIM))
		"inspect":
			var p := _pod(args)
			if p.is_empty():
				_error("Usage: podctl inspect <1-4>")
				return
			_root_act("pod %s inspected" % p.pod, 8.0)
			_print("  POD %s   occupant %s   since %s" % [p.pod, p.occupant, p.since])
			_print("  name      %s" % _esc(p.name))
			_print("  dreaming  %s" % _esc(str(p.dream)).replace("\n", "\n            "))
			if str(p.pod) == "3":
				Story.learn(sim(), "secret:pod3")
			if str(p.pod) == "2":
				Story.learn(sim(), "found:hollis")
		"wake":
			var p := _pod(args)
			if p.is_empty():
				_error("Usage: podctl wake <1-4>")
				return
			if not Story.knows(sim(), "secret:pods_truth"):
				_error("podctl: wake: sequence unknown. (Somebody must have written it down.)")
				return
			_pending = str(p.pod)
			_print("  [color=#%s]This will open pod %s. It cannot be undone, and corkHQ will know at once.[/color]" % [_hex(OSTheme.ALARM), p.pod])
			_print("  Type the pod number again to confirm, anything else to stop.")
			_set_mode("wake")
		_:
			_error("Usage: podctl list | inspect <pod> | wake <pod>")


func _pod(args: PackedStringArray) -> Dictionary:
	if args.size() < 2:
		return {}
	for p in Story.pods():
		if str(p.pod) == args[1]:
			return p
	return {}


func _finish_wake(line: String) -> void:
	_set_mode("")
	if line != _pending:
		_print("  Stopped. Pod %s stays closed." % _pending)
		return
	Story.learn(sim(), "woke")
	Story.learn(sim(), "secret:woke")
	sim().note("story", "Pod %s opened from the maintenance console" % _pending)
	Facility.act("task", "Supervisor opens pod %s" % _pending)
	var camp := Story.campaign(sim())
	if camp:
		camp.finish(sim(), "wake")
	_print("  [color=#%s]Pod %s: wake sequence started.[/color]" % [_hex(OSTheme.ALARM), _pending])


# --- Cork package server ------------------------------------------------------

func _connect(args: PackedStringArray) -> void:
	if args.is_empty():
		_error("Usage: connect <address>")
		return
	if args[0].to_lower() != CorkHQ.SERVER:
		_error("connect: %s: host not found" % args[0])
		return
	connected = true
	Story.learn(sim(), "cmd:corkpkg")
	Story.learn(sim(), "cmd:disconnect")
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


# Auditioning: play a sound in the facility and hear it through the camera
# you're listening to, with that camera's distance, panning and walls. (A
# dev tool: it works, but never shows in help.)
func _sound(args: PackedStringArray) -> void:
	var world: FacilityWorld = desktop.world if desktop else null
	if world == null:
		_error("No facility world (log on first).")
		return
	var sub := args[0].to_lower() if args.size() > 0 else "list"
	match sub:
		"list":
			var listening := "camera %d (%s)" % [world.listener_cam + 1, world.cameras[world.listener_cam].display_name] \
				if world.listener_cam >= 0 else "no camera (open Cameras; in the grid, point at a feed)"
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

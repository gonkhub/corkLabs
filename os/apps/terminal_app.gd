# Terminal: the supervisor's command line, and the part of the OS the
# player has to LEARN. "help" only lists the commands this supervisor knows
# (Knowledge "cmd:<name>"); a new supervisor knows a handful. The rest are
# found in files, in what corkHQ and the units say, in a game... Typing a real
# command works whether or not help lists it, and teaches it: what the
# PLAYER remembers carries over between runs.
#
# Also here:
#   the file system    ls, cd, cat, pwd, decrypt, run (Story / VirtualFS)
#   talk <unit>        opens the unit link (the conversation runs in Cameras)
#   su maint           the "decommissioned" maintenance account, and its
#                      commands (auditctl, hqctl, unitctl, pkgctl, podctl).
#                      Every one of them is a policy violation.
#
# Units and jobs are read-only here (units, jobs): orders, requests and
# conversations happen in Cameras (click the unit). Duties go through
# Supervisor like everywhere else, so they cost the same facility time. Up/down arrows walk the command history.
class_name TerminalApp
extends OSApp

## name -> [usage, what it does, group]
const COMMANDS := {
	"help": ["help [command]", "the commands you know, or how to use one", "basics"],
	"status": ["status", "clock, shift, throughput, coolant, alarms", "basics"],
	"clear": ["clear", "clear the screen", "basics"],
	"open": ["open <app>", "open an app (cameras, plant, files, duties...)", "basics"],
	"whoami": ["whoami", "who this terminal thinks you are", "basics"],
	"who": ["who", "who's logged in", "system"],
	"ps": ["ps", "what's running on this terminal", "system"],
	"uptime": ["uptime", "how long the facility has been running", "system"],
	"date": ["date", "the facility date and time", "system"],
	"history": ["history", "the commands you've typed", "system"],
	"kill": ["kill <pid>", "stop a process", "maintenance"],
	"duties": ["duties", "this shift's checklist", "shift"],
	"duty": ["duty <id>", "do a duty from the checklist (takes its time)", "shift"],
	"log": ["log [lines] [category]", "the facility journal (category: alarm, work, plant, tinker...)", "shift"],
	"units": ["units", "what each unit is doing, its needs and order", "units"],
	"jobs": ["jobs", "open jobs on the work board", "units"],
	"talk": ["talk <unit>", "open the unit link (it opens in Cameras: 3 min a line)", "units"],
	"plant": ["plant", "every device and its state", "plant"],
	"routes": ["routes", "passages between rooms: clearance, open or blocked", "plant"],
	"block": ["block <route> [reason]", "close a passage (needs route-control)", "plant"],
	"unblock": ["unblock <route>", "reopen a passage (needs route-control)", "plant"],
	"ls": ["ls [-a] [-l] [folder]", "what's in a folder (-a: hidden files too)", "files"],
	"cd": ["cd <folder>", "change folder (cd .. goes up, cd ~ goes home)", "files"],
	"pwd": ["pwd", "which folder you're in", "files"],
	"cat": ["cat <file>", "read a file (takes time the first time)", "files"],
	"decrypt": ["decrypt <file> <password>", "unlock an encrypted file", "files"],
	"cp": ["cp <file>", "copy a file into your home folder (copies survive a purge)", "files"],
	"grep": ["grep <word>", "search every file you can open for a word (15 min)", "files"],
	"find": ["find <name>", "list files whose names contain it", "files"],
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
	"podctl": ["podctl list | inspect <pod>", "the pods", "maintenance"],
	"sound": ["sound [play|loop|stop|mute|unmute] ...", "audition a sound through the camera you're listening to", "dev"],
}
const GROUPS := ["basics", "system", "shift", "units", "plant", "files", "network", "maintenance"]
const ROOT_ONLY := ["auditctl", "hqctl", "unitctl", "pkgctl", "podctl", "kill"]
## What ps shows: [pid, user, command, note].
const PROCESSES := [
	[1, "root", "corkos-init", ""],
	[44, "corp", "corkhq-linkd", "the corkHQ panel, via the uplink relay (workshop)"],
	[45, "corp", "auditd", "writes the audit trail"],
	[112, "root", "podsync --pods 4", ""],
	[113, "root", "knowledge_filter --unit tinker", ""],
	[114, "root", "knowledge_filter --unit hauler", ""],
	[212, "rmarrow", "nightrun --attract-mode", "defunct"],
	[300, "supervisor", "shell", ""],
]
## Facility C-7 came online (for uptime and who).
const FACILITY_EPOCH := "1979-06-30"
const ALIASES := {"?": "help", "robots": "units", "devices": "plant", "passages": "routes", 
	"cls": "clear", "dir": "ls", "type": "cat", "logout": "exit", "chat": "talk"}
const ROOT_ACCOUNT := "maint"
## Accounts su knows, and their passwords. (Okafor's: Tinker, backwards.)
const ACCOUNTS := {"maint": Story.MAINT_PASSWORD, "dokafor": "reknit"}
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
## "" or "password" (su)
var mode := ""
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
		"talk": _talk(args)
		"plant": _plant()
		"routes": _routes()
		"block": _block(args, true)
		"unblock": _block(args, false)
		"ls": _ls(args)
		"cd": _cd(args)
		"pwd": _print("  " + cwd)
		"cat": _cat(args)
		"decrypt": _decrypt(args)
		"cp": _cp(args)
		"grep": _grep(args)
		"find": _find(args)
		"who": _who()
		"ps": _ps()
		"uptime": _uptime()
		"date": _print("  " + FacilitySim.format_time(sim().time()))
		"history": _history()
		"kill": _kill(args)
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
	var where := cwd
	if where == VirtualFS.HOME or where.begins_with(VirtualFS.HOME + "/"):
		where = "~" + where.substr(VirtualFS.HOME.length())
	return "%s@corklabs:%s%s" % [Story.user(sim()) if sim() else "supervisor", where, "#" if root else "$"]


func _prompt_color() -> Color:
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
		_print("  [color=#%s]%-8s[/color] %-46s power %3d%%  stability %3d%% %-8s wear %3d%%%s" % [_hex(OSTheme.category_color(bot.robot_id)),
			bot.display_name().to_upper(), _esc(bot.doing_text(sim())), _pct(bot.power), _pct(bot.stability), bot.stability_state, _pct(bot.wear), order])


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
	var e := Story.entry(sim(), target)
	if e.is_empty() or not Story.exists(sim(), target):
		_error("ls: %s: No such file or directory" % target)
		return
	if not e.dir:
		_print("  " + _file_line(e, long))
		return
	if not Story.can_access(sim(), target):
		_error("ls: %s: Permission denied" % target)
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
	var e := Story.entry(sim(), target)
	if e.is_empty() or not Story.exists(sim(), target):
		_error("cd: %s: No such file or directory" % target)
		return
	if not e.dir:
		_error("cd: %s: Not a directory" % target)
		return
	if not Story.can_access(sim(), target):
		_error("cd: %s: Permission denied" % target)
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
	var cmds := PackedStringArray()
	for key in r.learned:
		if str(key).begins_with("cmd:"):
			cmds.append(str(key).trim_prefix("cmd:"))
	if not cmds.is_empty():
		_print("  [color=#%s](new command%s noted: %s)[/color]" % [_hex(OSTheme.INFO), "" if cmds.size() == 1 else "s", ", ".join(cmds)])


# Every file that can be searched right now: existing, not a program, readable.
func _searchable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in Story.fs().all_files(Story.knowledge(sim()), Story.shift(sim())):
		if not e.meta.has("exec") and not Story.is_encrypted(sim(), e) and Story.can_access(sim(), str(e.path)):
			out.append(e)
	out.append_array(Story.copies(sim()))
	return out


func _grep(args: PackedStringArray) -> void:
	if args.is_empty():
		_error("Usage: grep <word>")
		return
	var word := " ".join(args).to_lower()
	var hits := 0
	var restricted := false
	for e in _searchable():
		var lines := str(e.body).split("\n")
		for i in lines.size():
			if lines[i].to_lower().contains(word):
				hits += 1
				if hits <= 30:
					_print("  [color=#%s]%s:%d[/color]  %s" % [_hex(OSTheme.INFO), e.path, i + 1, _esc(lines[i].strip_edges())])
				if Story.restricted(e) > 0.0:
					restricted = true
	if hits > 30:
		_print("  [color=#%s](%d more)[/color]" % [_hex(OSTheme.TEXT_DIM), hits - 30])
	if hits == 0:
		_print("  No matches.")
	var o := Story.oversight(sim())
	if restricted and o:
		o.violate(sim(), "searched former staff files for '%s'" % word, 2.0)
	Facility.act("interaction", "Supervisor searches the files for '%s'" % word)


func _find(args: PackedStringArray) -> void:
	if args.is_empty():
		_error("Usage: find <name>")
		return
	var name := args[0].to_lower()
	var n := 0
	for e in _searchable():
		if str(e.name).to_lower().contains(name) and not str(e.name).begins_with("."):
			_print("  " + str(e.path))
			n += 1
	if n == 0:
		_print("  Nothing called that.")


func _who() -> void:
	_print("  supervisor  tty1      Day %d 05:55" % Story.shift(sim()))
	_print("  pell        corkhq    since %s   (idle 0s)" % FACILITY_EPOCH)
	if Story.knows(sim(), "root") or root:
		_print("  maint       tty1      (you)")


func _ps() -> void:
	Story.learn(sim(), "hint:uplink")
	_print("  %5s  %-11s %s" % ["PID", "USER", "COMMAND"])
	for p in PROCESSES:
		_print("  %5d  %-11s %s%s" % [p[0], p[1], p[2], ("   [color=#%s](%s)[/color]" % [_hex(OSTheme.TEXT_DIM), p[3]]) if not str(p[3]).is_empty() else ""])


func _uptime() -> void:
	var days := 17258 + int(sim().time() / 86400.0)
	var plant := sim().get_system("plant") as FacilityPlant
	var load := plant.throughput if plant else 0.0
	_print("  up %d days (since %s), 4 pods, load %.2f %.2f %.2f" % [days, FACILITY_EPOCH, load, load, load])


func _history() -> void:
	for i in history.size():
		_print("  %4d  %s" % [i + 1, _esc(history[i])])


func _kill(args: PackedStringArray) -> void:
	if args.is_empty() or not args[0].is_valid_int():
		_error("Usage: kill <pid>   (see: ps)")
		return
	match int(args[0]):
		45:
			_root_act("audit daemon stopped", 12.0, 0.3)
			_print("  auditd stopped.")
			_print("  [color=#%s]auditd restarted by corkhq-linkd (0.3 s). That was noticed.[/color]" % _hex(OSTheme.WARN))
		44:
			_error("kill: corkhq-linkd: operation not permitted. (There's hqctl for that.)")
		1, 112, 113, 114:
			_error("kill: %s: operation not permitted" % args[0])
		212:
			_print("  nightrun: already defunct. It keeps its high scores anyway.")
		300:
			_print("  You can't log yourself off from in here.")
		_:
			_error("kill: (%s): no such process" % args[0])


func _cp(args: PackedStringArray) -> void:
	if args.is_empty():
		_error("Usage: cp <file>   (copies it into your home folder)")
		return
	var r: Dictionary = Supervisor.copy_file(VirtualFS.normalize(cwd, args[0]))
	if r.ok:
		_print("  " + _esc(r.text))
	else:
		_error(r.text)


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
	var e := Story.entry(sim(), path)
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
	var bot := sim().get_system("robot_" + robot_id) as RobotAgent
	if bot == null:
		_error("talk: no unit called '%s'" % robot_id)
		return
	var cams = desktop.open_app("cameras") if desktop else null
	if cams == null:
		_error("talk: the unit link needs the Cameras")
		return
	_print("  Opening the unit link to %s in Cameras..." % bot.display_name().to_upper())
	cams.start_talk(robot_id)


func _talk(args: PackedStringArray) -> void:
	if args.is_empty():
		_error("Usage: talk <unit>   (%s)" % ", ".join(FacilitySetup.robots(sim()).map(func(b): return b.robot_id)))
		return
	start_talk(args[0].to_lower())


# --- The maintenance account -----------------------------------------------------------

func _su(args: PackedStringArray) -> void:
	var account := args[0].to_lower() if not args.is_empty() else "root"
	if account == "dokafor" and Story.knows(sim(), "purged:dokafor"):
		_error("su: user dokafor does not exist")
		return
	if not ACCOUNTS.has(account):
		_error("su: user %s does not exist or is not permitted" % account)
		return
	if Story.user(sim()) == account:
		_print("  Already %s." % account)
		return
	_pending = account
	_set_mode("password")


func _finish_su(password: String) -> void:
	_set_mode("")
	var o := Story.oversight(sim())
	var account := _pending
	if password.strip_edges().to_lower() != str(ACCOUNTS.get(account, "")).to_lower():
		_error("su: Authentication failure")
		if o:
			o.violate(sim(), "failed login to %s" % ("the decommissioned maintenance account" if account == ROOT_ACCOUNT else "former staff account " + account), 3.0)
		return
	leave_root()
	if account == "dokafor":
		Story.learn(sim(), "as:dokafor")
		Story.learn(sim(), "secret:okafor_account")
		cwd = "/home/dokafor"
		if o:
			o.violate(sim(), "login to former staff account dokafor", 6.0)
		Facility.act("dialogue_line", "Supervisor logs in as dokafor")
		_print("[color=#%s]  Last login: two days ago 13:41. 2,511 sessions.[/color]" % _hex(OSTheme.WARN))
		_print("[color=#%s]  Mail: 0 unread. (Everything was read.)   (exit to leave)[/color]" % _hex(OSTheme.WARN))
		Story.learn(sim(), "cmd:exit")
		_update_prompt()
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
	if Story.user(sim()) == "supervisor":
		_error("logout: not permitted. (There is no door.)")
		return
	leave_root()
	_print("  logout")


## Back to the supervisor's own account (exit, su, log off).
func leave_root() -> void:
	root = false
	var k := Story.knowledge(sim())
	if k:
		k.forget("root")
		k.forget("as:dokafor")
	if not Story.can_access(sim(), cwd):
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
			# (The wake ending is archived for now: docs/archive/endings.txt.)
			_error("podctl: wake: refused. The sequence needs a Directorate key this account doesn't hold.")
		_:
			_error("Usage: podctl list | inspect <pod> | wake <pod>")


func _pod(args: PackedStringArray) -> Dictionary:
	if args.size() < 2:
		return {}
	for p in Story.pods():
		if str(p.pod) == args[1]:
			return p
	return {}


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

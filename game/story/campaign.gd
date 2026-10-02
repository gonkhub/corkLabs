# The campaign (sim_id "campaign"): the supervisor's few shifts, as one
# continuous timeline. Shifts separate the big segments of the game: each
# has its own brief, duties and scripted events, and later shifts open up
# more (files that appear, audits that get stricter).
#
#   pre        before a shift: the brief is up; "Clock in" starts it (06:00)
#   on_duty    the shift is running; facility time moves as the supervisor acts
#   off_duty   the shift ended (14:00): the end-of-shift screen; "Clock out"
#              lets the night pass (the facility runs without you) until the
#              next shift's brief
#   fired      dismissed (Oversight says why). Retry the shift from its
#              checkpoint, or start over on a new save
#   complete   the last shift ended: the end of this build (the endings are
#              archived in docs/archive/endings.txt until they come back)
#
# Data (plain text, edit freely):
#   shifts.txt   shift | title | brief
#   duties.txt   corporate's checklist for each shift (the good-supervisor path)
#   events.txt   scripted moments: corkHQ lines, robot lines, faults, audits...
class_name Campaign
extends RefCounted

const SHIFTS := 3
## The fault code a diagnostic reads off Ogre's dead core (Form C-9 asks for it).
const OGRE_FAULT := "E-417"
const SHIFT_START_HOUR := 6.0
const SHIFT_END_HOUR := 14.0
## A new facility (and every brief) starts this long before the shift.
const BRIEF_LEAD := 300.0
const DIR := "res://game/story/"
## Standing lost for each duty left undone at the end of a shift: what it
## would have earned, and at least this.
const MISSED_DUTY := 2.0
const DUTY_CHECK := 10.0

var sim_id := "campaign"
var state := "pre"
## 1..SHIFTS: the shift that's running, or the next one while "pre".
var shift := 1
var ending := ""
## This shift's duties: [{"id", "title", "minutes", "standing", "after", "needs", "description", "done"}]
var duties: Array[Dictionary] = []
## Summary of the last night (for the brief).
var overnight: PackedStringArray = []

var _shifts: Array[Dictionary] = []
var _duty_defs: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _duty_acc := 0.0
var _night_mark := 0


func _init() -> void:
	_shifts = DataTable.read(DIR + "shifts.txt", PackedStringArray(["shift", "title", "brief"]))
	_duty_defs = DataTable.read(DIR + "duties.txt", PackedStringArray(["shift", "id", "title", "minutes", "standing", "after", "needs", "description"]))
	_events = DataTable.read(DIR + "events.txt", PackedStringArray(["shift", "at", "condition", "action", "args"]))


func on_duty() -> bool:
	return state == "on_duty"


## Share of the plant's random faults that actually happen right now: how
## hard the facility pushes. Orientation is gentler; nights are quiet.
const PRESSURE := {1: 0.65, 2: 1.0, 3: 1.15}
const NIGHT_PRESSURE := 0.15


func pressure() -> float:
	return float(PRESSURE.get(shift, 1.0)) if on_duty() else NIGHT_PRESSURE


func title() -> String:
	for s in _shifts:
		if int(s.shift) == shift:
			return s.title
	return "Shift %d" % shift


func brief() -> String:
	for s in _shifts:
		if int(s.shift) == shift:
			return str(s.brief).replace("\\n", "\n")
	return ""


func ending_info() -> Dictionary:
	return {"id": ending, "title": "End of this build",
		"text": "That's as far as the facility goes for now. Three shifts, and you're still here.\n\nWhat you found is below. What you didn't find is still in there."}


## Facility time the next shift starts (06:00 on day `shift`).
func shift_start_time() -> float:
	return (shift - 1) * 86400.0 + SHIFT_START_HOUR * 3600.0


## When this shift's clock runs out (the day schedule's end).
func shift_end_time() -> float:
	return (shift - 1) * 86400.0 + SHIFT_END_HOUR * 3600.0


# --- Duties ------------------------------------------------------------------------

func duty(id: String) -> Dictionary:
	for d in duties:
		if d.id == id:
			return d
	return {}


## Why a duty can't be done now ("" = it can).
func duty_blocker(sim: FacilitySim, d: Dictionary) -> String:
	if d.is_empty():
		return "No such duty."
	if d.done:
		return "Done."
	if not on_duty():
		return "You're not on shift."
	if not str(d.after).is_empty() and _clock_seconds(sim.time()) < _parse_clock(d.after):
		return "Not before %s." % d.after
	if not str(d.needs).is_empty() and not check(sim, d.needs):
		return "Not yet: %s" % d.description
	return ""


## Does a duty (the caller spends its minutes). Returns "" or why not.
func do_duty(sim: FacilitySim, id: String) -> String:
	var d := duty(id)
	var why := duty_blocker(sim, d)
	if not why.is_empty():
		return why
	d.done = true
	sim.note("duty", "Duty done: %s" % d.title)
	_duty_effect(sim, id)
	var o := _oversight(sim)
	if o and float(d.standing) > 0.0:
		o.commend(sim, "duty: " + str(d.title), float(d.standing))
	return ""


# What a duty does, besides pleasing corporate.
func _duty_effect(sim: FacilitySim, id: String) -> void:
	var k := _knowledge(sim)
	match id:
		"coolant_walk":
			# Walking the loop finds problems before they're alarms.
			var plant := sim.get_system("plant") as FacilityPlant
			var board := sim.get_system("work") as WorkBoard
			if plant and board:
				for dev_id in plant.device_ids():
					var dv := plant.device(dev_id)
					var kind: Dictionary = FacilityPlant.KINDS[dv.kind]
					if kind.has("drift") and float(dv.value) < 0.6 and int(dv.job) < 0:
						dv.job = board.post(sim, FacilityPlant._job_title(dv), kind.skill, dv.station, kind.work, 1, dev_id)
						sim.note("duty", "Inspection: %s needs attention" % dv.name)
		"unit_diag":
			for bot in FacilitySetup.robots(sim):
				if not bot.offline():
					bot.stability = minf(bot.stability + 0.05, 1.0)
		"purge_okafor":
			if k:
				k.learn(sim, "purged:dokafor")
		"audit_prep":
			var o := _oversight(sim)
			if o:
				o.suspicion = maxf(o.suspicion - 10.0, 0.0)
		"pod_census":
			if k:
				k.learn(sim, "census")


func duties_done() -> int:
	return duties.filter(func(d): return d.done).size()


# --- Conditions ---------------------------------------------------------------------

## A condition string: knowledge keys ("flag", "!flag") and comparisons
## ("standing>=70", "suspicion<30", "strikes>0", "shift>=2", "trust:tinker>=3"),
## joined by "&".
func check(sim: FacilitySim, condition: String) -> bool:
	var k := _knowledge(sim)
	var o := _oversight(sim)
	for part in condition.split("&", false):
		var c := part.strip_edges()
		if c.is_empty():
			continue
		var cmp := _compare(c, o, k)
		if cmp == 0:
			return false
		if cmp == 1:
			continue
		if k == null or not k.check(c):
			return false
	return true


# 1 true, 0 false, -1 not a comparison.
func _compare(c: String, o: Oversight, k: Knowledge = null) -> int:
	for op in [">=", "<=", ">", "<", "="]:
		var i := c.find(op)
		if i <= 0:
			continue
		var name := c.substr(0, i).strip_edges()
		var want := float(c.substr(i + op.length()).strip_edges())
		var have := 0.0
		match name:
			"standing": have = o.standing if o else 0.0
			"suspicion": have = o.suspicion if o else 0.0
			"strikes": have = float(o.strikes) if o else 0.0
			"shift": have = float(shift)
			_:
				if name.contains(":") and k:
					have = k.value(name)
				else:
					return -1
		match op:
			">=": return int(have >= want)
			"<=": return int(have <= want)
			">": return int(have > want)
			"<": return int(have < want)
			"=": return int(is_equal_approx(have, want))
	return -1


# --- The end (of this build) -------------------------------------------------------

## The run is over. `ending_id` is kept for when endings come back.
func finish(sim: FacilitySim, ending_id := "end_of_build") -> void:
	if state == "complete" or state == "fired":
		return
	ending = ending_id
	state = "complete"
	_set_watching(sim)
	sim.note("story", "The end of this build")
	SupervisorArchive.saw_ending(ending)


# --- System ---------------------------------------------------------------------------

func sim_start(sim: FacilitySim) -> void:
	state = "pre"
	shift = 1
	_load_duties()
	SupervisorArchive.new_run()
	_set_watching(sim)
	# A new facility: Ogre's core regulator failed in the night (Form C-9 gets a new one).
	var ogre := sim.get_system("robot_ogre") as RobotAgent
	if ogre:
		ogre.break_down(sim, "core regulator failure")
		ogre.activity.code = OGRE_FAULT
		var k := sim.get_system("knowledge") as Knowledge
		if k:
			k.learn(sim, "ogre_down")


func sim_tick(sim: FacilitySim, dt: float) -> void:
	if not on_duty():
		return
	_duty_acc += dt
	if _duty_acc < DUTY_CHECK - 0.001:
		return
	_duty_acc = 0.0
	# Duties that are just "have you read it / done it" tick themselves off.
	for d in duties:
		if not d.done and float(d.minutes) <= 0.0 and duty_blocker(sim, d).is_empty():
			do_duty(sim, d.id)


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	match event_name:
		"shift_start":
			if state == "fired" or state == "complete":
				return
			state = "on_duty"
			_set_watching(sim)
			sim.note("story", "%s begins" % title())
			SupervisorArchive.shift_worked()
			_book_events(sim)
		"shift_end":
			if state == "on_duty":
				sim.schedule_in(0.0, "shift_close", {})
		"shift_close":
			_close_shift(sim)
		"dismissed":
			if state != "complete":
				state = "fired"
				_set_watching(sim)
				SupervisorArchive.was_fired(str(data.get("kind", "")))
		"story":
			if state == "on_duty" and check(sim, str(data.get("condition", ""))):
				run_action(sim, str(data.action), str(data.args))


func _close_shift(sim: FacilitySim) -> void:
	if state != "on_duty":
		return
	var o := _oversight(sim)
	for d in duties:
		if not d.done and o:
			o.penalise(sim, "duty not done: " + str(d.title), maxf(MISSED_DUTY, float(d.standing)))
	if state == "fired" or (o and o.fired()):
		state = "fired"
		_set_watching(sim)
		return
	if shift >= SHIFTS:
		finish(sim)
		return
	state = "off_duty"
	_set_watching(sim)
	_night_mark = sim.journal.added
	sim.note("story", "%s is over. Clock out when you're ready." % title())


## Clocking out: the night passes (the caller advances time to
## night_until()), then night_over() sets up the next shift's brief.
func night_until() -> float:
	return shift * 86400.0 + SHIFT_START_HOUR * 3600.0 - BRIEF_LEAD


func night_over(sim: FacilitySim) -> void:
	if state != "off_duty":
		return
	overnight = PackedStringArray()
	for e in sim.journal.added_since(_night_mark):
		if e.cat in ["alarm", "hq", "stability"] and overnight.size() < 8:
			overnight.append("%s  %s" % [FacilitySim.format_clock(e.t), e.text])
	shift += 1
	state = "pre"
	_load_duties()
	sim.note("story", "The night is over. %s brief" % title())


func _load_duties() -> void:
	duties.clear()
	for d in _duty_defs:
		var shifts := str(d.shift)
		if shifts == "*" or Array(shifts.split(",")).map(func(s): return int(s)).has(shift):
			var row: Dictionary = d.duplicate()
			row.minutes = float(row.minutes)
			row.standing = float(row.standing)
			row.done = false
			duties.append(row)


func _book_events(sim: FacilitySim) -> void:
	var day := (shift - 1) * 86400.0
	for e in _events:
		if int(e.shift) != shift:
			continue
		var at := day + _parse_clock(e.at)
		if at < sim.time():
			at = sim.time()
		sim.schedule(at, "story", {"condition": e.condition, "action": e.action, "args": e.args})


## Runs one scripted action (events.txt, dialogue effects).
func run_action(sim: FacilitySim, action: String, args: String) -> void:
	var a := Array(args.split("|")).map(func(s): return str(s).strip_edges())
	var hq := sim.get_system("hq") as CorkHQ
	match action:
		"hq":
			if hq and a.size() >= 3:
				hq.post(sim, a[0], a[1], "|".join(a.slice(2)))
		"learn":
			var k := _knowledge(sim)
			if k:
				k.learn(sim, a[0])
		"fault":
			sim.schedule_in(0.0, "plant_fault", {"device": a[0]})
		"say":
			var chatter := sim.get_system("chatter") as RobotChatter
			var bot := sim.get_system("robot_" + str(a[0])) as RobotAgent
			if chatter and bot and a.size() >= 2 and not bot.offline():
				chatter.say_line(sim, bot, "|".join(a.slice(1)))
		"audit":
			var o := _oversight(sim)
			if o:
				o.audit(sim, float(a[0]) if a.size() > 0 else 0.0)
		"job":
			var board := sim.get_system("work") as WorkBoard
			if board and a.size() >= 4:
				board.post(sim, a[0], a[1], a[2], float(a[3]), 2, "story")
		"perform":
			var bot := sim.get_system("robot_" + str(a[0])) as RobotAgent
			if bot and a.size() >= 2:
				bot.request_clip(a[1])
		"stability":
			var bot := sim.get_system("robot_" + str(a[0])) as RobotAgent
			if bot and a.size() >= 2:
				bot.stability = clampf(bot.stability + float(a[1]), 0.0, 1.0)
		"seize":
			var bot := sim.get_system("robot_" + str(a[0])) as RobotAgent
			if bot and not bot.offline():
				bot.wear = maxf(bot.wear, RobotAgent.WEAR_SEIZE)
				bot.seize(sim)
		"wear":
			var bot := sim.get_system("robot_" + str(a[0])) as RobotAgent
			if bot and a.size() >= 2:
				bot.wear = clampf(bot.wear + float(a[1]), 0.0, 1.0)
		"directive":
			var dirs := sim.get_system("directives") as Directives
			if dirs and a.size() >= 4:
				dirs.issue(sim, a[0], a[1], float(a[2]), "|".join(a.slice(3)))
		"standing":
			var o := _oversight(sim)
			if o and a.size() >= 1:
				if float(a[0]) >= 0.0:
					o.commend(sim, a[1] if a.size() > 1 else "story", float(a[0]))
				else:
					o.penalise(sim, a[1] if a.size() > 1 else "story", -float(a[0]))
		"suspicion":
			var o := _oversight(sim)
			if o and a.size() >= 1:
				o.violate(sim, a[1] if a.size() > 1 else "story", float(a[0]))
		"end":
			finish(sim, a[0] if a.size() > 0 else "")
		_:
			push_warning("Campaign: unknown action '%s'" % action)


func _set_watching(sim: FacilitySim) -> void:
	var o := _oversight(sim)
	if o:
		o.watching = on_duty()


static func _parse_clock(hhmm: String) -> float:
	var p := hhmm.strip_edges().split(":")
	if p.size() < 2:
		return 0.0
	return float(p[0]) * 3600.0 + float(p[1]) * 60.0


static func _clock_seconds(t: float) -> float:
	return fmod(t, 86400.0)


func _oversight(sim: FacilitySim) -> Oversight:
	return sim.get_system("oversight") as Oversight


func _knowledge(sim: FacilitySim) -> Knowledge:
	return sim.get_system("knowledge") as Knowledge


func sim_save() -> Dictionary:
	return {"state": state, "shift": shift, "ending": ending, "duties": duties.duplicate(true), "overnight": Array(overnight),
		"duty_acc": _duty_acc, "night_mark": _night_mark}


func sim_load(d: Dictionary) -> void:
	state = str(d.get("state", "pre"))
	shift = int(d.get("shift", 1))
	ending = str(d.get("ending", ""))
	duties.clear()
	for row in d.get("duties", []):
		var r: Dictionary = row.duplicate()
		r.minutes = float(r.minutes)
		r.standing = float(r.standing)
		r.done = bool(r.done)
		duties.append(r)
	overnight = PackedStringArray(d.get("overnight", []))
	_duty_acc = float(d.get("duty_acc", 0.0))
	_night_mark = int(d.get("night_mark", 0))


func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	return PackedStringArray(["CAMPAIGN  shift %d/%d  %s   duties %d/%d%s" % [shift, SHIFTS, state, duties_done(), duties.size(),
		("   ending: " + ending) if not ending.is_empty() else ""]])

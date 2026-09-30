# Everything the player (the supervisor) can do to the facility, in one
# place. Each action is journaled as the supervisor speaking, and costs
# facility time through Facility.act(), so the robots and the plant play out
# while the supervisor "does" it.
#
# Used by the corkLabs desktop apps and the demo console.
class_name Supervisor
extends RefCounted

## Facility time each supervisor action costs (a key into Facility.COST).
const ORDER_COST := "choice"         # an order: 2 minutes
const PRIORITY_COST := "choice"      # re-prioritising a job: 2 minutes


## Orders a robot. kind: "job" (with job_id), "recharge", "standby", "cancel".
## Returns the robot's answer: {"ok": bool, "reply": String}.
static func order(bot: RobotAgent, kind: String, job_id := -1) -> Dictionary:
	var sim: FacilitySim = Facility.sim
	var what := describe_order(sim, kind, job_id)
	sim.note("supervisor", "To %s: %s" % [bot.display_name(), what])
	var r := bot.give_order(sim, kind, job_id)
	Facility.act(ORDER_COST, "Supervisor orders %s: %s" % [bot.display_name(), what])
	return r


static func set_priority(job_id: int, priority: int) -> void:
	var sim: FacilitySim = Facility.sim
	var board := sim.get_system("work") as WorkBoard
	var job := board.get_job(job_id)
	if job.is_empty():
		return
	sim.note("supervisor", "Job #%d %s: set to %s priority" % [job_id, job.title, WorkBoard.PRIORITY_NAMES[clampi(priority, 0, 3)]])
	board.set_priority(sim, job_id, priority)
	Facility.act(PRIORITY_COST, "Supervisor re-prioritises job #%d" % job_id)


## Places a requisition (Requisitions app, Terminal). A choice: costs facility
## time. Returns {"ok", "text"}; corkHQ reports what happens next.
static func requisition(item_id: String, qty := 1) -> Dictionary:
	var sim: FacilitySim = Facility.sim
	var req := sim.get_system("requisitions") as Requisitions
	if req == null:
		return {"ok": false, "text": "Requisitions unavailable."}
	var it := req.item(item_id)
	var r := req.place(sim, item_id, qty)
	if r.ok:
		sim.note("supervisor", "Requisition: %dx %s" % [qty, it.get("name", item_id)])
		Facility.act(ORDER_COST, "Supervisor files a requisition")
	return r


## Remote reboot (needs the "remote-reboot" software package). Returns false if locked.
static func reboot(bot: RobotAgent) -> bool:
	if not has_software("remote-reboot") or bot.offline():
		return false
	var sim: FacilitySim = Facility.sim
	sim.note("supervisor", "Remote reboot: %s" % bot.display_name())
	bot.reboot(sim)
	Facility.act(ORDER_COST, "Supervisor reboots %s" % bot.display_name())
	return true


## Is this software package installed on the facility?
static func has_software(package_id: String) -> bool:
	if not Facility.running:
		return false
	var sw := Facility.sim.get_system("software") as SoftwareLibrary
	return sw != null and sw.installed(package_id)


# --- Story actions ------------------------------------------------------------------
# Reading, talking, duties, programs: the actions that move the story, and
# (like orders) the only things that move facility time.

## Facility minutes a first conversation step costs: a line read, a reply chosen.
const TALK_LINE := "dialogue_line"
const TALK_CHOICE := "choice"
## Talking to a unit is "conversing beyond the needs of the work" (conduct 2):
## a small violation, once per conversation. It also steadies the unit.
const TALK_VIOLATION := 1.5
const TALK_STEADY := 0.06
const TALK_STEADY_EVERY := 3600.0
const INSPECT_MINUTES := 10.0


## Reads a file (Terminal cat, Files). Spends its reading time the first time.
static func read_file(vpath: String) -> Dictionary:
	var sim: FacilitySim = Facility.sim
	var r := Story.read_file(sim, vpath)
	if r.ok and float(r.minutes) > 0.0:
		Facility.spend(float(r.minutes) * 60.0, "Supervisor reads %s" % vpath)
	return r


## Tries a password on an encrypted file (a choice: 2 minutes).
static func decrypt(vpath: String, password: String) -> Dictionary:
	var r := Story.decrypt(Facility.sim, vpath, password)
	Facility.act("choice", "Supervisor tries to decrypt %s" % vpath)
	return r


## Opens the link to a unit. Returns the conversation (or null: offline /
## nothing to say) and the lines it opens with; each line costs facility time.
static func talk_begin(bot: RobotAgent) -> Dictionary:
	var sim: FacilitySim = Facility.sim
	if bot.offline():
		return {"runner": null, "lines": [], "error": "No response from %s (offline)." % bot.display_name()}
	var d := Dialogue.for_robot(bot.robot_id)
	if d == null:
		return {"runner": null, "lines": [], "error": "%s has nothing to say." % bot.display_name()}
	sim.note("supervisor", "Opens the unit link to %s" % bot.display_name())
	var k := Story.knowledge(sim)
	var key := "talked:" + bot.robot_id
	if k and sim.time() - float(k.flags.get(key, -INF)) >= TALK_STEADY_EVERY:
		bot.stability = minf(bot.stability + TALK_STEADY, 1.0)
		k.forget(key)
		k.learn(sim, key)
	var o := Story.oversight(sim)
	if o:
		o.violate(sim, "conversation with unit %s" % bot.display_name(), TALK_VIOLATION)
	var runner := Dialogue.Runner.new(d, bot.robot_id)
	var lines := runner.begin(sim)
	_spend_lines(bot, lines, "")
	return {"runner": runner, "lines": lines, "error": ""}


## Opens a reply to Liaison Pell (the corkHQ panel). Lines and answers cost
## time like a conversation with a unit; talking to corporate isn't a violation.
static func reply_begin() -> Dictionary:
	var sim: FacilitySim = Facility.sim
	var d := Dialogue.for_robot("pell")
	if d == null:
		return {"runner": null, "lines": []}
	sim.note("supervisor", "Replies to Liaison Pell")
	var runner := Dialogue.Runner.new(d, "pell")
	var lines := runner.begin(sim)
	if not lines.is_empty():
		Facility.spend(float(Facility.COST[TALK_LINE]) * lines.size(), "Reading the liaison's reply")
	return {"runner": runner, "lines": lines}


static func reply_choose(runner: Dialogue.Runner, i: int) -> Array[Dictionary]:
	if i < 0 or i >= runner.choices.size():
		return []
	var sim: FacilitySim = Facility.sim
	sim.note("supervisor", "To Liaison Pell: \"%s\"" % runner.choices[i].text)
	var lines := runner.choose(sim, i)
	Facility.act(TALK_CHOICE, "Supervisor writes to the liaison")
	for l in lines:
		sim.note("hq", "Liaison Pell (reply): %s" % l.text)
	if not lines.is_empty():
		Facility.spend(float(Facility.COST[TALK_LINE]) * lines.size(), "Reading the liaison's reply")
	return lines


## Picks a reply. Returns the lines that follow.
static func talk_choose(runner: Dialogue.Runner, bot: RobotAgent, i: int) -> Array[Dictionary]:
	if i < 0 or i >= runner.choices.size():
		return []
	var said: String = runner.choices[i].text
	Facility.sim.note("supervisor", "To %s: \"%s\"" % [bot.display_name(), said])
	var lines := runner.choose(Facility.sim, i)
	Facility.act(TALK_CHOICE, "Supervisor answers %s" % bot.display_name())
	_spend_lines(bot, lines, "")
	return lines


static func _spend_lines(bot: RobotAgent, lines: Array[Dictionary], _cause: String) -> void:
	for l in lines:
		if l.speaker != "sys" and l.speaker != "you":
			Facility.sim.note("speech", "%s (link): \"%s\"" % [bot.display_name(), l.text])
	if not lines.is_empty():
		Facility.spend(float(Facility.COST[TALK_LINE]) * lines.size(), "Talking with %s" % bot.display_name())


## Inspects a device properly (Plant app): 10 facility minutes. Returns the read-out.
static func inspect_device(id: String) -> String:
	var sim: FacilitySim = Facility.sim
	var plant := sim.get_system("plant") as FacilityPlant
	sim.note("supervisor", "Inspects %s" % plant.device(id).get("name", id))
	Facility.spend(INSPECT_MINUTES * 60.0, "Supervisor inspects %s" % plant.device(id).get("name", id))
	return plant.inspect_text(sim, id)


## Authorises a spare part from stock on a device (a choice: 2 minutes).
static func use_part(id: String) -> String:
	var sim: FacilitySim = Facility.sim
	var why := (sim.get_system("plant") as FacilityPlant).use_part(sim, id)
	if why.is_empty():
		Facility.act("choice", "Supervisor authorises a spare part")
	return why


## Posts a maintenance job for a worn device before it's an alarm (2 minutes).
static func request_maintenance(id: String) -> String:
	var sim: FacilitySim = Facility.sim
	var plant := sim.get_system("plant") as FacilityPlant
	var board := sim.get_system("work") as WorkBoard
	var d := plant.device(id)
	if d.is_empty() or not FacilityPlant.KINDS[d.kind].has("drift"):
		return "That isn't something you service; it breaks, and then it's fixed."
	var job: Dictionary = board.get_job(int(d.job)) if int(d.job) >= 0 else {}
	if not job.is_empty() and (job.status == "open" or job.status == "claimed"):
		return "There's already job #%d for it." % int(d.job)
	if float(d.value) >= 0.95:
		return "%s doesn't need it." % d.name
	var k: Dictionary = FacilityPlant.KINDS[d.kind]
	d.job = board.post(sim, FacilityPlant._job_title(d), k.skill, d.station, k.work * maxf(1.0 - float(d.value), 0.3), 1, id)
	sim.note("supervisor", "Requests maintenance: %s" % d.name)
	Facility.act("choice", "Supervisor requests maintenance")
	return ""


## Does a duty from the checklist. Returns "" or why not.
static func do_duty(id: String) -> String:
	var sim: FacilitySim = Facility.sim
	var camp := Story.campaign(sim)
	if camp == null:
		return "No duties."
	var d := camp.duty(id)
	var why := camp.duty_blocker(sim, d)
	if not why.is_empty():
		return why
	sim.note("supervisor", "Duty: %s" % d.title)
	camp.do_duty(sim, id)
	if float(d.minutes) > 0.0:
		Facility.spend(float(d.minutes) * 60.0, "Duty: %s" % d.title)
	return ""


## Time lost to a program (a round of Night Run). Recreational software is
## a policy violation (conduct 4), logged once per session of play.
static func play(minutes: float, what: String, violation := 0.0) -> void:
	var sim: FacilitySim = Facility.sim
	if violation > 0.0:
		var o := Story.oversight(sim)
		if o:
			o.violate(sim, "recreational software: %s" % what, violation)
	Facility.spend(minutes * 60.0, "Supervisor plays %s" % what)


static func describe_order(sim: FacilitySim, kind: String, job_id: int) -> String:
	match kind:
		"job":
			var board := sim.get_system("work") as WorkBoard
			var j: Dictionary = board.get_job(job_id) if board else {}
			return "take job #%d %s" % [job_id, j.get("title", "")]
		"recharge": return "recharge"
		"standby": return "stand by"
		"cancel": return "cancel your order"
	return kind


## Can this robot get to this job right now (a route that fits it, not blocked)?
static func can_reach(sim: FacilitySim, bot: RobotAgent, job: Dictionary) -> bool:
	return bot.why_cant_reach(sim, str(job.get("station", ""))).is_empty()


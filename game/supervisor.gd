# Everything the player (the supervisor) can do to the facility, in one
# place. Each action is journaled as the supervisor speaking, and costs
# facility time through Facility.act(), so the robots and the plant play out
# while the supervisor "does" it.
#
# Used by the corkLabs desktop apps and the demo console.
class_name Supervisor
extends RefCounted

## Facility time each supervisor action costs (a key into Facility.COST).
const ORDER_COST := "choice"         # an order: 5 minutes
const PRIORITY_COST := "choice"      # re-prioritising a job: 5 minutes


## Orders a robot. kind: "job" (with job_id), "recharge", "standby", "cancel".
## Putting a unit on a job also requests the job (its part comes out of
## stock: no part, no order). Returns the robot's answer: {"ok": bool, "reply": String}.
static func order(bot: RobotAgent, kind: String, job_id := -1) -> Dictionary:
	var sim: FacilitySim = Facility.sim
	var what := describe_order(sim, kind, job_id)
	if kind == "job":
		var board := sim.get_system("work") as WorkBoard
		var why := board.request(sim, job_id) if board else ""
		if not why.is_empty():
			return {"ok": false, "reply": why}
	sim.note("supervisor", "To %s: %s" % [bot.display_name(), what])
	var r := bot.give_order(sim, kind, job_id)
	did("order")
	if kind == "job" and r.ok:
		_go(job_id, bot, "Supervisor orders %s: %s" % [bot.display_name(), what])
	else:
		Facility.act(ORDER_COST, "Supervisor orders %s: %s" % [bot.display_name(), what])
	return r


## Marks that the supervisor has done something (shift 1's tutorial duties
## tick themselves off on these: "did:order", "did:inspect"...).
static func did(what: String) -> void:
	if Facility.running:
		Story.learn(Facility.sim, "did:" + what)


## Answers a unit's request (option index). A choice: 5 minutes.
static func answer_request(id: int, i: int) -> String:
	var sim: FacilitySim = Facility.sim
	var reqs := sim.get_system("requests") as UnitRequests
	if reqs == null:
		return ""
	var r := reqs.get_request(id)
	var out := reqs.answer(sim, id, i)
	if not out.is_empty():
		did("answer")
		if r.get("kind", "") == "part" and i == 0:
			did("requisition")
		Facility.act(ORDER_COST, "Supervisor answers a unit's request")
	return out


## Books a unit's service at its dock (uses a servo bundle). 5 minutes.
static func book_service(bot: RobotAgent) -> int:
	var sim: FacilitySim = Facility.sim
	var id := bot.book_service(sim)
	if id >= 0:
		sim.note("supervisor", "Books a service for %s" % bot.display_name())
		var board := sim.get_system("work") as WorkBoard
		var who := Dispatch.best_unit(sim, board.get_job(id))   # Tinker, if it's free
		if who != null:
			who.give_order(sim, "job", id)
		_go(id, who, "Supervisor books a service")
	return id


## Files an interim output report for a directive (Duties). 20 minutes.
static func file_report() -> void:
	var sim: FacilitySim = Facility.sim
	var dirs := sim.get_system("directives") as Directives
	sim.note("supervisor", "Files an output report")
	if dirs:
		dirs.notify(sim, "report")
	Facility.spend(Directives.REPORT_MINUTES * 60.0, "Supervisor files an output report")


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
static func requisition(item_id: String, qty := 1, express := false) -> Dictionary:
	var sim: FacilitySim = Facility.sim
	var req := sim.get_system("requisitions") as Requisitions
	if req == null:
		return {"ok": false, "text": "Requisitions unavailable."}
	var it := req.item(item_id)
	var r := req.place(sim, item_id, qty, express)
	if r.ok:
		sim.note("supervisor", "Requisition: %dx %s%s" % [qty, it.get("name", item_id), " (express)" if express else ""])
		did("requisition")
		Facility.act(ORDER_COST, "Supervisor files a requisition")
	return r


## Remote reboot (needs the "remote-reboot" software package). Returns false if locked.
## Remote reboot (the remote-reboot package): offline a few minutes,
## stability restored. It also frees a seized unit (no manual reboot needed).
static func reboot(bot: RobotAgent) -> bool:
	if not has_software("remote-reboot") or (bot.offline() and bot.activity.kind != "seized"):
		return false
	var sim: FacilitySim = Facility.sim
	sim.note("supervisor", "Remote reboot: %s" % bot.display_name())
	bot.reboot(sim)
	Facility.act(ORDER_COST, "Supervisor reboots %s" % bot.display_name())
	return true


## Activates a crated unit from stock (Units app): 30 facility minutes of
## unpacking, bolting on, first boot. Returns {"ok", "text"}.
static func activate_unit(item_id: String) -> Dictionary:
	var sim: FacilitySim = Facility.sim
	var req := sim.get_system("requisitions") as Requisitions
	var r := req.activate(sim, item_id)
	if r.ok:
		sim.note("supervisor", "Activates a crated unit: %s" % r.bot.display_name())
		Facility.spend(ACTIVATE_MINUTES * 60.0, "Supervisor activates %s" % r.bot.display_name())
	return r


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
## A conversation builds trust (Knowledge "trust:<unit>") if the last one that
## did was at least this long ago: trust takes days, not one long chat.
const TRUST_GAP := 7200.0
## Facility minutes a diagnostic takes, and how much it steadies the unit.
const DIAGNOSE_MINUTES := 30.0
const DIAGNOSE_STEADY := 0.02
const ACTIVATE_MINUTES := 90.0


## Reads a file (Terminal cat, Files). Spends its reading time the first time.
static func read_file(vpath: String) -> Dictionary:
	var sim: FacilitySim = Facility.sim
	var r := Story.read_file(sim, vpath)
	if r.ok and float(r.minutes) > 0.0:
		Facility.spend(float(r.minutes) * 60.0, "Supervisor reads %s" % vpath)
	return r


## Copies a file into the home folder (1 minute).
static func copy_file(vpath: String) -> Dictionary:
	var r := Story.copy_file(Facility.sim, vpath)
	if r.ok:
		Facility.act("dialogue_line", "Supervisor copies %s" % vpath)
	return r


## Empties the Recycle Bin: what's in it is gone for good (this run). Corporate
## likes a tidy terminal.
static func empty_bin() -> bool:
	var sim: FacilitySim = Facility.sim
	if not Story.learn(sim, "bin_emptied"):
		return false
	sim.note("supervisor", "Empties the Recycle Bin")
	var o := Story.oversight(sim)
	if o:
		o.commend(sim, "a tidy terminal", 1.0)
	Facility.act("dialogue_line", "Supervisor empties the Recycle Bin")
	return true


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
		o.violate(sim, "conversation with unit %s" % bot.display_name(), TALK_VIOLATION, 0.0, bot.room(sim))
	var runner := Dialogue.Runner.new(d, bot.robot_id)
	var lines := runner.begin(sim)
	if k and not runner.done:
		var tkey := "trusted:" + bot.robot_id
		if sim.time() - float(k.flags.get(tkey, -INF)) >= TRUST_GAP:
			k.forget(tkey)
			k.learn(sim, tkey)
			k.add_value("trust:" + bot.robot_id)
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


## Sends a unit to inspect a device (its menu in Cameras, or Plant): it goes,
## looks, and reports (on camera, in the Facility Log, and in Plant). An
## errand: the time passes while it does it. `unit_id` "" = the best free unit.
static func order_inspection(device_id: String, unit_id := "") -> Dictionary:
	var sim: FacilitySim = Facility.sim
	var plant := sim.get_system("plant") as FacilityPlant
	var d := plant.device(device_id) if plant else {}
	if d.is_empty():
		return {"ok": false, "text": "Nothing there."}
	var id := plant.post_inspection(sim, device_id)
	did("inspect_order")
	return request_job(id, false, "inspect " + str(d.name), unit_id)


## Patches a repair without its part (5 minutes): a unit is sent, but the
## device won't hold long. Returns false if the job doesn't need a part.
static func patch_job(job_id: int) -> bool:
	var sim: FacilitySim = Facility.sim
	var board := sim.get_system("work") as WorkBoard
	var j := board.get_job(job_id) if board else {}
	if not WorkBoard.active(j) or not j.has("part") or j.get("part_used", false):
		return false
	return request_job(job_id, true).ok


## Orders maintenance on a device (its object menu in Cameras): requests its
## job (posting one for something that wears; the part comes out of stock)
## and Dispatch sends the most suitable free unit. `makeshift`: patch it
## without the part. 5 minutes. Returns {"ok", "text"}.
static func order_maintenance(device_id: String, makeshift := false, unit_id := "") -> Dictionary:
	var sim: FacilitySim = Facility.sim
	var plant := sim.get_system("plant") as FacilityPlant
	var d := plant.device(device_id) if plant else {}
	if d.is_empty():
		return {"ok": false, "text": "Nothing there."}
	var job := Dispatch.job_for_device(sim, device_id)
	if job.is_empty():
		return {"ok": false, "text": "%s doesn't need anything." % d.name}
	return request_job(int(job.id), makeshift, d.name, unit_id)


## Requests a job and sends a unit (a seized unit's manual reboot, a device's
## repair). 5 minutes. Returns {"ok", "text"}.
static func request_job(job_id: int, makeshift := false, what := "", unit_id := "") -> Dictionary:
	var sim: FacilitySim = Facility.sim
	var board := sim.get_system("work") as WorkBoard
	var job := board.get_job(job_id)
	var unit := sim.get_system("robot_" + unit_id) as RobotAgent if not unit_id.is_empty() else null
	var r := Dispatch.request(sim, job_id, makeshift, unit)
	if not r.ok:
		return r
	sim.note("supervisor", "%s: %s%s" % ["Patch it" if makeshift else "Maintenance", what if not what.is_empty() else str(job.get("title", "")),
		" (no part)" if makeshift else ""])
	did("order")
	_go(job_id, r.unit, "Supervisor orders maintenance")
	return r


# A unit on its way: the time passes as it does the job (an errand), not now.
# Nobody free (queued): the order itself is all that happens now (5 minutes).
static func _go(job_id: int, bot: Variant, cause: String) -> void:
	var sim: FacilitySim = Facility.sim
	var unit := bot as RobotAgent
	if unit != null and unit.order.get("kind", "") == "job" and int(unit.order.get("job", -1)) == job_id:
		Facility.start_errand(job_id, unit.sim_id, cause)
	else:
		Facility.act(ORDER_COST, cause)


## Takes a job off the queue (its unit stands down; an unused part goes back). 5 minutes.
static func cancel_request(job_id: int) -> void:
	var sim: FacilitySim = Facility.sim
	var board := sim.get_system("work") as WorkBoard
	board.unrequest(sim, job_id)
	sim.note("supervisor", "Calls off job #%d" % job_id)
	Facility.act(ORDER_COST, "Supervisor calls off a job")


## Has Ogre feed a coolant canister from stock into the loop (the coolant
## feed in the hangar; +50% when it's done). An errand, like maintenance.
static func pump_coolant() -> Dictionary:
	var sim: FacilitySim = Facility.sim
	var req := sim.get_system("requisitions") as Requisitions
	var plant := sim.get_system("plant") as FacilityPlant
	if req == null or plant == null or int(req.inventory.get("coolant_canister", 0)) <= 0:
		return {"ok": false, "text": "No coolant canisters in stock."}
	if plant.coolant >= 0.95:
		return {"ok": false, "text": "The reservoir is full."}
	return order_maintenance("coolant_feed")


## Diagnostics on a unit (its object menu): reads it out properly and
## steadies it a little. 30 minutes. Returns the read-out.
static func diagnose(bot: RobotAgent) -> String:
	var sim: FacilitySim = Facility.sim
	sim.note("supervisor", "Runs diagnostics on %s" % bot.display_name())
	did("diagnose")
	var dirs := sim.get_system("directives") as Directives
	if dirs:
		dirs.notify(sim, "diagnose", bot.robot_id)
	if not bot.offline():
		bot.stability = minf(bot.stability + DIAGNOSE_STEADY, 1.0)
	Facility.spend(DIAGNOSE_MINUTES * 60.0, "Supervisor runs diagnostics on %s" % bot.display_name())
	return "DIAG %s: power %d%%, stability %d%% (%s), independence %d%%, wear %d%%, jobs done %d. %s" % [
		bot.display_name().to_upper(), roundi(bot.power * 100.0), roundi(bot.stability * 100.0), bot.stability_state,
		roundi(bot.independence() * 100.0), roundi(bot.wear * 100.0), bot.jobs_done,
		"Firmware: knowledge filter active." if bot.robot_id != "ogre" else "Firmware: no knowledge filter installed."]


## Posts a maintenance job for a worn device before it's an alarm (5 minutes).
static func request_maintenance(id: String) -> String:
	var sim: FacilitySim = Facility.sim
	var plant := sim.get_system("plant") as FacilityPlant
	var board := sim.get_system("work") as WorkBoard
	var d := plant.device(id)
	if d.is_empty() or not FacilityPlant.KINDS[d.kind].has("drift"):
		return "That isn't something you service; it breaks, and then it's fixed."
	var job: Dictionary = board.get_job(int(d.job)) if int(d.job) >= 0 else {}
	if not job.is_empty() and WorkBoard.active(job):
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


# Dispatch: who does a job. The supervisor asks for maintenance on a thing
# (a camera's object menu, Supervisor.order_maintenance); Dispatch requests
# the job (WorkBoard.request: its part comes out of stock) and sends the most
# suitable unit that's free:
#
#   can do it     skill at least its refuse_below_skill; not a rail-only job
#                 for a crane; not someone else's service; not the unit
#                 that broke it
#   can get there a route that fits it (narrow hatches, stuck doors)
#   is free       online, not on another job, not charging below reserve
#   is willing    stable units first; a unit with a will of its own may
#                 refuse (RobotAgent.give_order)
#   best          skill x nearness x power
#
# With nobody free the job waits in the queue (requested, unclaimed) and the
# first stable unit to come free takes it.
class_name Dispatch
extends RefCounted


## Requests a job and sends a unit. Returns {"ok", "text", "unit"}.
static func request(sim: FacilitySim, job_id: int, makeshift := false) -> Dictionary:
	var board := sim.get_system("work") as WorkBoard
	if board == null:
		return {"ok": false, "text": "No work board.", "unit": null}
	var why := board.request(sim, job_id, makeshift)
	if not why.is_empty():
		return {"ok": false, "text": why, "unit": null}
	var job := board.get_job(job_id)
	if job.status == "claimed":
		return {"ok": true, "text": "%s is already on it." % _name(str(job.claimed_by)), "unit": sim.get_system(str(job.claimed_by))}
	var bot := best_unit(sim, job)
	if bot == null:
		return {"ok": true, "text": "Queued: no unit is free for it. The first one that is will take it.", "unit": null}
	var r := bot.give_order(sim, "job", job_id)
	if not r.ok:
		return {"ok": true, "text": "%s: \"%s\" (queued for the next free unit)" % [bot.display_name(), r.reply], "unit": bot}
	return {"ok": true, "text": "%s is on its way." % bot.display_name(), "unit": bot}


## The best free unit for a job, or null.
static func best_unit(sim: FacilitySim, job: Dictionary) -> RobotAgent:
	var options := candidates(sim, job)
	return options[0].bot if not options.is_empty() else null


## Units that could take a job now, best first: [{"bot", "score", "why"}].
static func candidates(sim: FacilitySim, job: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if job.is_empty():
		return out
	for bot in FacilitySetup.robots(sim):
		var why := unfit(sim, bot, job)
		if not why.is_empty():
			continue
		var dist := bot.route_length(sim, str(job.station))
		var fit := bot.traits.skill(str(job.skill))
		var near := 1.0 - 0.5 * clampf(dist / RobotAgent.FAR, 0.0, 1.0)
		var score := fit * near * clampf(bot.power + 0.2, 0.0, 1.0)
		if bot.own_will():
			score *= 0.3   # last resort: it may not listen
		out.append({"bot": bot, "score": score, "why": "%s skill %d%%, %.0f m" % [job.skill, roundi(fit * 100.0), dist]})
	out.sort_custom(func(a, b): return a.score > b.score)
	return out


## "" if this unit could take this job right now, else why not.
static func unfit(sim: FacilitySim, bot: RobotAgent, job: Dictionary) -> String:
	if bot.offline():
		return "offline"
	if not str(job.get("only", "")).is_empty() and str(job.only) != bot.sim_id:
		return "someone else's"
	if str(job.get("not_by", "")) == bot.sim_id:
		return "it broke it"
	if bot.traits.stationary and job.get("rail_only", false):
		return "can't carry it"
	if bot.traits.skill(str(job.skill)) < bot.traits.refuse_below_skill:
		return "not built for it"
	if bot.activity.kind == "work" and int(bot.activity.job) != int(job.id):
		return "busy"
	if bot.order.get("kind", "") == "job" and int(bot.order.get("job", -1)) != int(job.id):
		return "busy"
	if bot.power < bot.traits.power_reserve:
		return "needs to charge"
	if bot.route_length(sim, str(job.station)) < 0.0:
		return "can't get there"
	return ""


## The job for a device: its active one, or (a device that wears) a new one
## posted now. {} if there's nothing to do.
static func job_for_device(sim: FacilitySim, device_id: String) -> Dictionary:
	var plant := sim.get_system("plant") as FacilityPlant
	var board := sim.get_system("work") as WorkBoard
	if plant == null or board == null:
		return {}
	var d := plant.device(device_id)
	if d.is_empty():
		return {}
	var job: Dictionary = board.get_job(int(d.job)) if int(d.job) >= 0 else {}
	if WorkBoard.active(job):
		return job
	var k: Dictionary = FacilityPlant.KINDS[d.kind]
	if k.has("drift") and float(d.value) < 0.95:
		d.job = board.post(sim, FacilityPlant._job_title(d), k.skill, d.station, k.work * maxf(1.0 - float(d.value), 0.3), 1, device_id)
		return board.get_job(int(d.job))
	return {}


static func _name(sim_id: String) -> String:
	return sim_id.trim_prefix("robot_").capitalize()

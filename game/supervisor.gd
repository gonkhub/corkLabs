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


## Lets facility time pass while the supervisor watches.
static func wait(seconds: float) -> void:
	Facility.spend(seconds, "Supervisor waits %s" % _dur(seconds))


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


## Can this robot reach this job at all (same rail)?
static func can_reach(sim: FacilitySim, bot: RobotAgent, job: Dictionary) -> bool:
	var layout := sim.get_system("layout") as FacilityLayout
	return layout != null and layout.station(job.get("station", "")).get("rail", "") == bot.rail


static func _dur(seconds: float) -> String:
	if seconds < 3600.0:
		return "%d min" % int(seconds / 60.0)
	return "%.1f h" % (seconds / 3600.0)

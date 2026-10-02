# The facility's job board: every piece of work waiting to be done ("clear
# debris at Bay 2", "recalibrate pod 3"). Things that break post jobs here,
# but a posted job is only a record that something needs doing. Nobody works
# on it until it's REQUESTED: the supervisor orders maintenance on the thing
# (a camera's object menu: Dispatch picks the best free unit), or, off duty,
# the night autopilot requests everything it can. Stable units only work on
# requested jobs (or the one they were ordered onto); unstable ones choose
# for themselves, requested or not (RobotAgent).
#
# Parts are taken from stock when a job is requested, not halfway through: a
# repair that needs a part can't be requested without one (order it, or
# patch it: a makeshift repair with no part, which won't hold long).
#
# A job is plain data, so it saves and loads:
#   id         int, never reused
#   title      "Clear debris"
#   skill      "heavy" / "precise" / "general" (robots are better at some)
#   station    where the work is (FacilityLayout station id)
#   work       work units needed (a robot with skill 1 and work_speed 1 does 1 per second)
#   progress   work units done so far (kept if a robot walks away)
#   priority   0 low, 1 normal, 2 high, 3 critical
#   status     "open", "claimed", "done", "cancelled"
#   requested  true once someone asked for it to be done (see above)
#   units      the units whose work it is (robot ids; absent = anyone's)
#   part       a Requisitions stock item the repair uses up, or absent;
#              taken when it's requested ("part_used"). "makeshift": patched
#              without it.
#   claimed_by robot sim_id working on it, or ""
#   source     who posted it (a device id, "dev", "supervisor"...)
#   posted     facility time it was posted
#
# When a job finishes, a "job_done" event fires with {"job": id, "source",
# "by": robot}, so whatever posted it can react (the pipe is fixed).
class_name WorkBoard
extends RefCounted

const PRIORITY_NAMES := ["low", "normal", "high", "critical"]
## Finished and cancelled jobs kept for the record.
const HISTORY := 60
## Off duty, the night autopilot requests what it can this often.
const AUTOPILOT_EVERY := 60.0
## Jobs from these sources are requested as soon as they're posted: the
## follow-on steps of something already under way (a crate's hand-off, a
## salvaged part), story and dev jobs. (A booked service is requested by
## RobotAgent.book_service once its servo bundle is on it.)
const AUTO_SOURCES := ["crate:", "core:", "part:", "story", "dev", "routine", "inspect:", "fetch:", "bring:"]

## Everyday work a dev key (or a quiet facility) can post: [title, skill, work units].
const ROUTINE := [
	["Clear debris", "heavy", 300.0],
	["Move coolant drums", "heavy", 420.0],
	["Recalibrate sensor", "precise", 240.0],
	["Replace fuse", "precise", 180.0],
	["Inspect conduit", "general", 150.0],
	["Sweep filters", "general", 200.0],
]

var sim_id := "work"
## Random routine jobs posted when a brand-new facility starts.
var starter_jobs := 0
var jobs: Array[Dictionary] = []   # in id order
var next_id := 1
var _autopilot_acc := 0.0


func post(sim: FacilitySim, title: String, skill: String, station: String, work: float,
		priority := 1, source := "") -> int:
	var job := {"id": next_id, "title": title, "skill": skill, "station": station,
		"work": work, "progress": 0.0, "priority": clampi(priority, 0, 3), "status": "open",
		"claimed_by": "", "source": source, "posted": sim.time()}
	next_id += 1
	# Repairs to plant devices use up a spare part (FacilityPlant.KINDS "part").
	var plant := sim.get_system("plant") as FacilityPlant
	if plant and plant.devices.has(source):
		var part: String = FacilityPlant.KINDS[plant.device(source).kind].get("part", "")
		if not part.is_empty():
			job.part = part
	# Whose work it is (FacilityPlant: roles).
	var units: Array = FacilityPlant.units_for(source, plant.device(source).kind if plant and plant.devices.has(source) else "")
	if not units.is_empty():
		job.units = units.duplicate()
	jobs.append(job)
	var st: Dictionary = _layout(sim).station(station)
	sim.note("work", "Job #%d posted: %s at %s (%s, %s priority)" % [job.id, title,
		st.get("name", station), skill, PRIORITY_NAMES[job.priority]])
	if AUTO_SOURCES.any(func(p): return source.begins_with(p)) or (autopilot(sim) and missing_part(sim, job).is_empty() and (not FacilityPlant.is_chore(sim, job) or night_watch(sim))):
		request(sim, job.id)
	return job.id


## Asks for a job to be done: from now on units will take it (Dispatch also
## sends one). Takes its part from stock; `makeshift` does without (a patch).
## Returns "" or why not (no part in stock, not open).
func request(sim: FacilitySim, id: int, makeshift := false) -> String:
	var j := get_job(id)
	if not active(j):
		return "There's no open job #%d." % id
	var plant := sim.get_system("plant") as FacilityPlant
	var blocked := plant.request_blocker(j) if plant else ""
	if not blocked.is_empty() and not j.get("requested", false):
		return blocked
	if j.has("part") and not j.get("part_used", false):
		if makeshift:
			j.part_used = true
			j.makeshift = true
			sim.note("work", "Job #%d: patching it without a %s (makeshift)" % [j.id, j.part])
		else:
			var req := sim.get_system("requisitions") as Requisitions
			if req:
				var part := str(j.part)
				if int(req.inventory.get(part, 0)) <= 0:
					return "It needs %s, and there are none in stock." % part_name(sim, part)
				req.inventory[part] = int(req.inventory[part]) - 1
			j.part_used = true
	if not j.get("requested", false):
		j.requested = true
		j.requested_at = sim.time()
		sim.note("work", "Job #%d requested: %s" % [j.id, j.title])
		sim.schedule(sim.time(), "job_requested", {"job": j.id})   # units reconsider
	return ""


## Takes a job off the queue (it stays posted; its part goes back in stock).
func unrequest(sim: FacilitySim, id: int) -> void:
	var j := get_job(id)
	if not active(j) or not j.get("requested", false):
		return
	j.requested = false
	if j.get("part_used", false) and not j.get("makeshift", false) and float(j.progress) <= 0.0:
		var req := sim.get_system("requisitions") as Requisitions
		if req:
			req.inventory[str(j.part)] = int(req.inventory.get(str(j.part), 0)) + 1
		j.part_used = false
	if j.status == "claimed":
		var by := str(j.claimed_by)
		j.status = "open"
		j.claimed_by = ""
		sim.schedule(sim.time(), "job_released", {"job": id, "by": by})
	sim.note("work", "Job #%d taken off the queue: %s" % [j.id, j.title])


## The part a job still needs and can't get from stock ("" = none needed, or in stock).
func missing_part(sim: FacilitySim, j: Dictionary) -> String:
	if j.is_empty() or not j.has("part") or j.get("part_used", false):
		return ""
	var req := sim.get_system("requisitions") as Requisitions
	if req == null or int(req.inventory.get(str(j.part), 0)) > 0:
		return ""
	return str(j.part)


static func part_name(sim: FacilitySim, part: String) -> String:
	var req := sim.get_system("requisitions") as Requisitions
	return str(req.item(part).get("name", part)) if req else part


## Requested jobs nobody's on yet (the queue), in id order.
func queued_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for j in jobs:
		if j.status == "open" and j.get("requested", false):
			out.append(j)
	return out


func get_job(id: int) -> Dictionary:
	for j in jobs:
		if j.id == id:
			return j
	return {}


## Still to be done: open or claimed.
static func active(j: Dictionary) -> bool:
	return not j.is_empty() and j.get("status", "") in ["open", "claimed"]


## Jobs that can't be requested for want of a part (none in stock), in id order.
func waiting_jobs(sim: FacilitySim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for j in jobs:
		if j.status == "open" and not missing_part(sim, j).is_empty():
			out.append(j)
	return out


## Jobs not finished or cancelled, in id order.
func open_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for j in jobs:
		if j.status == "open" or j.status == "claimed":
			out.append(j)
	return out


## Open jobs posted by `source` (e.g. to avoid posting the same fault twice).
func jobs_from(source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for j in open_jobs():
		if j.source == source:
			out.append(j)
	return out


func claim(id: int, robot: String) -> bool:
	var j := get_job(id)
	if j.is_empty() or j.status != "open":
		return j.get("claimed_by", "") == robot and j.get("status", "") == "claimed"
	j.status = "claimed"
	j.claimed_by = robot
	return true


## The robot walked away: the job goes back on the board, progress kept.
func release(id: int, robot: String) -> void:
	var j := get_job(id)
	if not j.is_empty() and j.status == "claimed" and j.claimed_by == robot:
		j.status = "open"
		j.claimed_by = ""


## Adds work. Returns true when this finished the job.
func add_progress(sim: FacilitySim, id: int, robot: String, amount: float) -> bool:
	var j := get_job(id)
	if j.is_empty() or j.status != "claimed" or j.claimed_by != robot:
		return false
	j.progress = minf(j.progress + amount, j.work)
	if j.progress < j.work:
		return false
	j.status = "done"
	j.done_at = sim.time()
	sim.note("work", "Job #%d done: %s (by %s, %s after posting)" % [j.id, j.title,
		robot.trim_prefix("robot_").capitalize(), _dur(sim.time() - float(j.posted))])
	sim.schedule(sim.time(), "job_done", {"job": j.id, "source": j.source, "by": robot})
	_trim_history()
	return true


## Does a job without its part: a makeshift fix (the device it repairs won't
## hold long, see FacilityPlant). Requests it. Returns false if there's no
## open job that still needs a part.
func patch(sim: FacilitySim, id: int) -> bool:
	var j := get_job(id)
	if not active(j) or not j.has("part") or j.get("part_used", false):
		return false
	return request(sim, id, true).is_empty()


## A delivery's been unpacked: say if jobs were waiting for it.
func parts_arrived(sim: FacilitySim, part: String) -> void:
	var n := jobs.filter(func(j): return active(j) and str(j.get("part", "")) == part and not j.get("part_used", false)).size()
	if n > 0:
		sim.note("work", "%s in stock: %d job%s can be requested now" % [part_name(sim, part), n, "" if n == 1 else "s"])


func cancel(sim: FacilitySim, id: int, reason: String) -> void:
	var j := get_job(id)
	if j.is_empty() or j.status == "done" or j.status == "cancelled":
		return
	j.status = "cancelled"
	j.claimed_by = ""
	sim.note("work", "Job #%d cancelled: %s (%s)" % [id, j.title, reason])
	sim.schedule(sim.time(), "job_cancelled", {"job": id, "source": j.source})
	_trim_history()


## Raises or lowers a job's priority (things got worse, or the supervisor says so).
func set_priority(sim: FacilitySim, id: int, priority: int) -> void:
	var j := get_job(id)
	priority = clampi(priority, 0, 3)
	if j.is_empty() or int(j.priority) == priority:
		return
	var up := priority > int(j.priority)
	j.priority = priority
	sim.note("work", "Job #%d %s to %s priority: %s" % [id, "escalated" if up else "lowered",
		PRIORITY_NAMES[priority], j.title])


func fraction_done(j: Dictionary) -> float:
	return float(j.progress) / maxf(float(j.work), 0.001)


func _trim_history() -> void:
	var finished := jobs.filter(func(j): return j.status == "done" or j.status == "cancelled")
	var extra := finished.size() - HISTORY
	if extra <= 0:
		return
	var drop := {}
	for i in extra:
		drop[finished[i].id] = true
	jobs = jobs.filter(func(j): return not drop.has(j.id))


func _layout(sim: FacilitySim) -> FacilityLayout:
	var l := sim.get_system("layout") as FacilityLayout
	return l if l else FacilityLayout.new()


static func _dur(seconds: float) -> String:
	if seconds < 60.0:
		return "%ds" % int(seconds)
	if seconds < 3600.0:
		return "%dm" % int(seconds / 60.0)
	return "%dh%02dm" % [int(seconds / 3600.0), int(fmod(seconds, 3600.0) / 60.0)]


## Posts a random routine job at a random work station (dev key F9).
func post_random(sim: FacilitySim, source := "dev") -> int:
	var layout := _layout(sim)
	var spots: Array[String] = []
	for id in layout.stations:
		if layout.stations[id].kind == "work":
			spots.append(id)
	if spots.is_empty():
		return -1
	spots.sort()
	var r: Array = ROUTINE[sim.rng.randi() % ROUTINE.size()]
	return post(sim, r[0], r[1], spots[sim.rng.randi() % spots.size()], r[2],
		sim.rng.randi_range(0, 2), source)


# --- System -----------------------------------------------------------------

func sim_start(sim: FacilitySim) -> void:
	for i in starter_jobs:
		post_random(sim, "routine")


# Off duty (or with no campaign at all), the night autopilot requests every
# open job it can (anything that needs a part it hasn't got waits for night
# procurement, see Requisitions).
func sim_tick(sim: FacilitySim, dt: float) -> void:
	_autopilot_acc += dt
	if _autopilot_acc < AUTOPILOT_EVERY - 0.001:
		return
	_autopilot_acc = 0.0
	if not autopilot(sim):
		return
	for j in jobs:
		if j.status == "open" and not j.get("requested", false) and missing_part(sim, j).is_empty() \
				and (not FacilityPlant.is_chore(sim, j) or night_watch(sim)):
			request(sim, int(j.id))   # (chores wait for the supervisor, unless the night-watch package is in)


## The night-watch package: the night crew does the chores too.
static func night_watch(sim: FacilitySim) -> bool:
	var sw := sim.get_system("software") as SoftwareLibrary
	return sw != null and sw.installed("night-watch")


## Is the night autopilot running (nobody on duty to give orders)?
static func autopilot(sim: FacilitySim) -> bool:
	var camp := sim.get_system("campaign") as Campaign
	return camp == null or not camp.on_duty()


func sim_save() -> Dictionary:
	return {"next_id": next_id, "jobs": jobs.duplicate(true), "autopilot_acc": _autopilot_acc}


func sim_load(d: Dictionary) -> void:
	next_id = int(d.get("next_id", 1))
	_autopilot_acc = float(d.get("autopilot_acc", 0.0))
	jobs.clear()
	for j in d.get("jobs", []):
		var job: Dictionary = j.duplicate(true)
		# JSON turns ints into floats; put them back.
		job.id = int(job.id)
		job.priority = int(job.priority)
		job.work = float(job.work)
		job.progress = float(job.progress)
		job.posted = float(job.posted)
		jobs.append(job)


## Dev panel lines.
func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	var lines := PackedStringArray()
	var open := open_jobs()
	lines.append("WORK BOARD  %d open" % open.size())
	for j in open:
		lines.append("  #%d %-26s %-8s %-7s %3d%%  %s" % [j.id, j.title, j.skill,
			PRIORITY_NAMES[j.priority], int(fraction_done(j) * 100.0),
			("-> " + str(j.claimed_by).trim_prefix("robot_")) if j.status == "claimed" else ("queued" if j.get("requested", false) else "not requested")])
	return lines

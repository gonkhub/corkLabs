# The facility's job board: every piece of work waiting to be done ("clear
# debris at Bay 2", "recalibrate pod 3"). Things that break post jobs here;
# robots pick them up by their own choice (utility scores), or because the
# supervisor ordered them to.
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


func post(sim: FacilitySim, title: String, skill: String, station: String, work: float,
		priority := 1, source := "") -> int:
	var job := {"id": next_id, "title": title, "skill": skill, "station": station,
		"work": work, "progress": 0.0, "priority": clampi(priority, 0, 3), "status": "open",
		"claimed_by": "", "source": source, "posted": sim.time()}
	next_id += 1
	jobs.append(job)
	var st: Dictionary = _layout(sim).station(station)
	sim.note("work", "Job #%d posted: %s at %s (%s, %s priority)" % [job.id, title,
		st.get("name", station), skill, PRIORITY_NAMES[job.priority]])
	return job.id


func get_job(id: int) -> Dictionary:
	for j in jobs:
		if j.id == id:
			return j
	return {}


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


func sim_tick(_sim: FacilitySim, _dt: float) -> void:
	pass


func sim_save() -> Dictionary:
	return {"next_id": next_id, "jobs": jobs.duplicate(true)}


func sim_load(d: Dictionary) -> void:
	next_id = int(d.get("next_id", 1))
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
			("-> " + str(j.claimed_by).trim_prefix("robot_")) if j.status == "claimed" else "waiting"])
	return lines

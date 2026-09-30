# The facility's machinery, as one system (sim_id "plant"): the things the
# robots keep running, which drift, break, and post jobs on the work board.
#
#   pods     The processing pods (the humans; the robots don't know that).
#            Their "sync" drifts down, faster when the facility runs hot.
#            Low sync = a "Recalibrate" job (precise work, Tinker's rail).
#            Facility throughput is the pods' average sync.
#   filters  One per bay. Clog slowly; a clogged filter makes things run
#            hot. "Sweep filters" (general work).
#   pipes    Coolant pipes, one per bay. Leak at random ("Clamp coolant
#            leak", heavy work, Hauler's rail). Every leak drains the
#            coolant reservoir; low coolant = hot facility = pods drift faster.
#   relay    The power relay. Its fuse blows at random ("Replace fuse",
#            precise). While it's out, robot docks charge at 40%.
#   bays     Debris falls in the bays at random ("Clear debris", heavy).
#   gate     The freight gate between the main hall and the workshop. It
#            jams at random, which BLOCKS that route on the rail network
#            (Hauler's only way into the workshop) until it's unjammed.
#
# So problems chain: a leak nobody clamps heats the facility, the pods drift,
# throughput drops, and a blown fuse slows the recharging robots who'd fix it.
#
# Devices update every UPDATE facility seconds; random faults are booked as
# scheduler events from the seeded RNG, so everything is repeatable.
class_name FacilityPlant
extends RefCounted

const UPDATE := 10.0

## Per kind: the job it posts, how fast it drifts (value lost per hour at
## normal temperature) and at which values the job appears and escalates
## ([normal, high, critical]; below the first = post), or the fault rate
## (faults per hour) for things that break suddenly.
const KINDS := {
	"pod": {"job": "Recalibrate %s", "skill": "precise", "work": 600.0, "drift": 0.08,
		"levels": [0.75, 0.5, 0.3]},
	"filter": {"job": "Sweep filters", "skill": "general", "work": 400.0, "drift": 0.05,
		"levels": [0.6, 0.35, 0.15], "start_priority": 0},
	"pipe": {"job": "Clamp coolant leak", "skill": "heavy", "work": 900.0, "rate": 0.08, "priority": 2},
	"relay": {"job": "Replace relay fuse", "skill": "precise", "work": 360.0, "rate": 0.05, "priority": 2},
	"bay": {"job": "Clear debris", "skill": "heavy", "work": 600.0, "rate": 0.1, "priority": 1},
	"gate": {"job": "Unjam freight gate", "skill": "general", "work": 300.0, "rate": 0.04, "priority": 2,
		"blocks": "freight_gate"},
}
## Chance that cleared debris turns up a damaged part. The part goes to the
## workbench for repair (precise work), then back to its bay to be refitted
## (heavy work): a hand-off between the robots.
const SALVAGE_CHANCE := 0.5
const SALVAGE_PARTS := ["servo", "valve actuator", "cable reel", "pressure sensor", "fan hub"]
const REPAIR_WORK := 480.0
const REFIT_WORK := 300.0
## Coolant lost per hour per leaking pipe, and regained per hour with no leaks.
const LEAK_RATE := 0.5
const REFILL_RATE := 0.1
## Charge speed on docks while the relay is out.
const RELAY_OUT_CHARGE := 0.4

var sim_id := "plant"
## id -> {"id", "kind", "name", "station", "value" (1 = perfect), "fault": bool, "job": int}
var devices := {}
var coolant := 1.0
var throughput := 1.0
## This shift so far: throughput samples, faults, jobs done.
var shift_stats := {"output_sum": 0.0, "samples": 0, "faults": 0, "jobs": 0}

var _ids: Array[String] = []
var _acc := 0.0


func _init() -> void:
	for i in 4:
		_add("pod_%d" % (i + 1), "pod", "Pod %d" % (i + 1), "pods_a" if i < 2 else "pods_b")
	for b in 3:
		var bay := "bay_%d" % (b + 1)
		_add("filter_%d" % (b + 1), "filter", "Bay %d filters" % (b + 1), bay)
		_add("pipe_%d" % (b + 1), "pipe", "Bay %d coolant pipe" % (b + 1), bay)
		_add("bay_%d" % (b + 1), "bay", "Bay %d" % (b + 1), bay)
	_add("relay", "relay", "Power relay", "relay")
	_add("gate", "gate", "Freight gate", "gate")


func _add(id: String, kind: String, display_name: String, station: String) -> void:
	devices[id] = {"id": id, "kind": kind, "name": display_name, "station": station,
		"value": 1.0, "fault": false, "job": -1}
	_ids.append(id)
	_ids.sort()


func device(id: String) -> Dictionary:
	return devices.get(id, {})


func device_ids() -> Array[String]:
	return _ids.duplicate()


## How fast robot docks charge right now (1 = normal).
func charge_factor() -> float:
	return RELAY_OUT_CHARGE if devices.relay.fault else 1.0


## How hot the facility runs: 1 = normal. Low coolant and clogged filters
## push it up, and pods drift faster.
func heat() -> float:
	var clog := 0.0
	var n := 0
	for id in _ids:
		if devices[id].kind == "filter":
			clog += 1.0 - float(devices[id].value)
			n += 1
	return 1.0 + 3.0 * (1.0 - coolant) + 0.6 * (clog / maxf(n, 1))


# --- System ------------------------------------------------------------------------

func sim_start(sim: FacilitySim) -> void:
	# A lived-in facility: things are part-way worn, and one pod already needs care.
	for id in _ids:
		var d: Dictionary = devices[id]
		if d.kind == "pod":
			d.value = sim.rng.randf_range(0.8, 1.0)
		elif d.kind == "filter":
			d.value = sim.rng.randf_range(0.55, 1.0)
	devices[_ids.filter(func(i): return devices[i].kind == "pod")[sim.rng.randi() % 4]].value = 0.7
	for id in _ids:
		if KINDS[devices[id].kind].has("rate"):
			_book_fault(sim, id)
	_update(sim)
	sim.note("plant", "Plant online: 4 pods, 3 bays, coolant %d%%, throughput %d%%" % [_pct(coolant), _pct(throughput)])


func sim_tick(sim: FacilitySim, dt: float) -> void:
	_acc += dt
	if _acc >= UPDATE - 0.001:
		_drift(sim, _acc)
		_acc = 0.0
		_update(sim)


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	match event_name:
		"plant_fault":
			_fault(sim, str(data.device))
		"job_done":
			var id := str(data.get("source", ""))
			if devices.has(id):
				_repaired(sim, id, str(data.get("by", "")))
			elif id.begins_with("part:"):
				_part_step(sim, id, str(data.get("by", "")))
			shift_stats.jobs += 1
		"job_cancelled":
			var id := str(data.get("source", ""))
			if devices.has(id) and int(devices[id].job) == int(data.job):
				devices[id].job = -1
		"shift_start":
			shift_stats = {"output_sum": 0.0, "samples": 0, "faults": 0, "jobs": 0}
		"shift_end":
			var avg := float(shift_stats.output_sum) / maxf(float(shift_stats.samples), 1.0)
			sim.note("report", "Shift report: throughput %d%% average, %d jobs done, %d faults. Now: coolant %d%%, heat %.1fx" % [
				_pct(avg), int(shift_stats.jobs), int(shift_stats.faults), _pct(coolant), heat()])


# Slow changes: pods lose sync (faster when hot), filters clog, leaks drain coolant.
func _drift(sim: FacilitySim, seconds: float) -> void:
	var hours := seconds / 3600.0
	var h := heat()
	var leaks := 0
	for id in _ids:
		var d: Dictionary = devices[id]
		var k: Dictionary = KINDS[d.kind]
		if d.kind == "pipe" and d.fault:
			leaks += 1
		if not k.has("drift"):
			continue
		var was: float = d.value
		var rate: float = k.drift * (h if d.kind == "pod" else 1.0) * sim.rng.randf_range(0.5, 1.5)
		d.value = maxf(was - rate * hours, 0.0)
		if d.kind == "pod" and was > 0.0 and d.value <= 0.0:
			sim.note("alarm", "%s has DESYNCED: no output until recalibrated" % d.name)
	if leaks > 0:
		var was_c := coolant
		coolant = maxf(coolant - LEAK_RATE * leaks * hours, 0.0)
		if was_c >= 0.5 and coolant < 0.5:
			sim.note("alarm", "Coolant below 50%%: the facility is running hot (heat %.1fx)" % heat())
	else:
		coolant = minf(coolant + REFILL_RATE * hours, 1.0)


# Posts or escalates jobs for worn devices, and updates throughput.
func _update(sim: FacilitySim) -> void:
	var board := sim.get_system("work") as WorkBoard
	var sync := 0.0
	var pods := 0
	for id in _ids:
		var d: Dictionary = devices[id]
		var k: Dictionary = KINDS[d.kind]
		if d.kind == "pod":
			sync += d.value if d.value > 0.05 else 0.0
			pods += 1
		if not k.has("levels") or board == null:
			continue
		var want := -1
		for i in k.levels.size():
			if d.value < k.levels[i]:
				want = i + int(k.get("start_priority", 1))
		want = mini(want, 3)
		if want < 0:
			continue
		var job: Dictionary = board.get_job(int(d.job)) if int(d.job) >= 0 else {}
		if job.is_empty() or not (job.status == "open" or job.status == "claimed"):
			d.job = board.post(sim, _job_title(d), k.skill, d.station, k.work, want, id)
		elif int(job.priority) < want:
			board.set_priority(sim, int(d.job), want)
	throughput = sync / maxf(pods, 1)
	shift_stats.output_sum += throughput
	shift_stats.samples += 1


func _fault(sim: FacilitySim, id: String) -> void:
	var d: Dictionary = devices[id]
	if d.fault:
		return
	var k: Dictionary = KINDS[d.kind]
	shift_stats.faults += 1
	var board := sim.get_system("work") as WorkBoard
	if d.kind != "bay":
		d.fault = true
		sim.note("alarm", {"pipe": "COOLANT LEAK: %s", "relay": "%s FUSE BLOWN: docks charge at 40%%",
			"gate": "%s JAMMED: the route is blocked"}.get(d.kind, "FAULT: %s") % d.name)
		if k.has("blocks"):
			var layout := sim.get_system("layout") as FacilityLayout
			if layout:
				layout.set_blocked(sim, k.blocks, true, "jammed")
	var open_job: Dictionary = board.get_job(int(d.job)) if board and int(d.job) >= 0 else {}
	if board and (open_job.is_empty() or not (open_job.status == "open" or open_job.status == "claimed")):
		d.job = board.post(sim, _job_title(d), k.skill, d.station, k.work, int(k.priority), id)
	if d.kind == "bay":
		_book_fault(sim, id)   # debris keeps falling whether or not it's cleared
	# Everyone reconsiders right away.
	sim.schedule(sim.time(), "alarm", {"device": id})


## A robot deliberately breaks a device (a critically unstable robot making
## work for itself). To the facility it looks like an ordinary fault or drift;
## only the journal's "sabotage" line says who did it.
func sabotage(sim: FacilitySim, id: String, robot: RobotAgent) -> void:
	var d: Dictionary = devices.get(id, {})
	if d.is_empty():
		return
	sim.note("sabotage", "%s SABOTAGED %s" % [robot.display_name(), d.name])
	var hq := sim.get_system("hq") as CorkHQ
	if hq:
		hq.noticed_damage(sim, robot)
	if KINDS[d.kind].has("drift"):
		d.value = maxf(float(d.value) - 0.45, 0.0)   # the job gets posted on the next update
	else:
		_fault(sim, id)


func _repaired(sim: FacilitySim, id: String, by: String) -> void:
	var d: Dictionary = devices[id]
	var was_fault: bool = d.fault
	d.value = 1.0
	d.fault = false
	d.job = -1
	var who := by.trim_prefix("robot_").capitalize()
	match d.kind:
		"pod": sim.note("plant", "%s recalibrated by %s: sync 100%%" % [d.name, who])
		"filter": sim.note("plant", "%s swept by %s" % [d.name, who])
		"pipe": sim.note("plant", "%s clamped by %s" % [d.name, who])
		"relay": sim.note("plant", "%s fuse replaced by %s: docks back to full charge" % [d.name, who])
		"gate": sim.note("plant", "%s unjammed by %s" % [d.name, who])
		"bay":
			if sim.rng.randf() < SALVAGE_CHANCE:
				var part: String = SALVAGE_PARTS[sim.rng.randi() % SALVAGE_PARTS.size()]
				sim.note("plant", "%s found a damaged %s in the %s debris and set it aside for the workbench" % [who, part, d.name])
				var board := sim.get_system("work") as WorkBoard
				if board:
					board.post(sim, "Repair salvaged %s" % part, "precise", "bench", REPAIR_WORK, 1,
						"part:repair:%s:%s:%s" % [id, part, by])
	if KINDS[d.kind].has("blocks"):
		var layout := sim.get_system("layout") as FacilityLayout
		if layout:
			layout.set_blocked(sim, KINDS[d.kind].blocks, false)
	if was_fault:
		_book_fault(sim, id)


# The salvage chain: "part:repair:<bay>:<part>:<finder>" -> refit job back at
# the bay -> "part:refit:<bay>:<part>:<repairer>" -> done.
func _part_step(sim: FacilitySim, source: String, by: String) -> void:
	var bits := source.split(":")
	if bits.size() < 5:
		return
	var bay := bits[2]
	var part := bits[3]
	var who := by.trim_prefix("robot_").capitalize()
	var board := sim.get_system("work") as WorkBoard
	if bits[1] == "repair" and board:
		sim.note("plant", "%s repaired the %s from %s; it needs refitting" % [who, part, devices[bay].name])
		board.post(sim, "Refit repaired %s" % part, "heavy", devices[bay].station, REFIT_WORK, 1,
			"part:refit:%s:%s:%s" % [bay, part, by])
	elif bits[1] == "refit":
		sim.note("plant", "%s refitted the %s in %s (repaired by %s)" % [who, part, devices[bay].name,
			bits[4].trim_prefix("robot_").capitalize()])


# Faults arrive at random (exponential gaps): the next one is booked when the
# last is fixed.
func _book_fault(sim: FacilitySim, id: String) -> void:
	var rate: float = KINDS[devices[id].kind].rate
	var hours := -log(1.0 - sim.rng.randf() * 0.999) / rate
	sim.schedule_in(hours * 3600.0, "plant_fault", {"device": id})


static func _job_title(d: Dictionary) -> String:
	var t: String = KINDS[d.kind].job
	return t % d.name if t.contains("%s") else t


static func _pct(x: float) -> int:
	return int(roundf(x * 100.0))


# --- Save / describe -------------------------------------------------------------------

func sim_save() -> Dictionary:
	var devs := {}
	for id in _ids:
		devs[id] = {"value": devices[id].value, "fault": devices[id].fault, "job": devices[id].job}
	return {"devices": devs, "coolant": coolant, "throughput": throughput,
		"shift_stats": shift_stats.duplicate(), "acc": _acc}


func sim_load(data: Dictionary) -> void:
	var devs: Dictionary = data.get("devices", {})
	for id in devs:
		if devices.has(id):
			devices[id].value = float(devs[id].value)
			devices[id].fault = bool(devs[id].fault)
			devices[id].job = int(devs[id].job)
	coolant = float(data.get("coolant", 1.0))
	throughput = float(data.get("throughput", 1.0))
	var st: Dictionary = data.get("shift_stats", {})
	shift_stats = {"output_sum": float(st.get("output_sum", 0.0)), "samples": int(st.get("samples", 0)),
		"faults": int(st.get("faults", 0)), "jobs": int(st.get("jobs", 0))}
	_acc = float(data.get("acc", 0.0))


## One line per device, for panels.
func device_text(id: String) -> String:
	var d: Dictionary = devices[id]
	var state := ""
	match d.kind:
		"pod": state = "sync %d%%" % _pct(d.value) if d.value > 0.0 else "DESYNCED"
		"filter": state = "clean %d%%" % _pct(d.value)
		"pipe": state = "LEAKING" if d.fault else "sealed"
		"relay": state = "FUSE BLOWN" if d.fault else "ok"
		"gate": state = "JAMMED" if d.fault else "open"
		"bay": state = "debris" if int(d.job) >= 0 else "clear"
	return "%-20s %-10s%s" % [d.name, state, ("  job #%d" % int(d.job)) if int(d.job) >= 0 else ""]


func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("PLANT  throughput %d%%   coolant %d%%   heat %.1fx   dock charge %d%%" % [
		_pct(throughput), _pct(coolant), heat(), _pct(charge_factor())])
	for id in _ids:
		if devices[id].kind != "bay" or int(devices[id].job) >= 0:
			lines.append("  " + device_text(id))
	return lines

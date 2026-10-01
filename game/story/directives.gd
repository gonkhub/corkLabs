# Directives (sim_id "directives"): corporate's demands, with deadlines.
# Every so often on duty corkHQ wants something specific, now: inspect this,
# run diagnostics on that, get that job done, get throughput back up, file a
# report. Each has a deadline; done in time it pleases the Directorate, missed
# it costs standing. They're what keeps pulling the supervisor back to the
# work, whatever else they were doing.
#
# A directive: {"id", "kind", "target", "text", "due", "reward", "penalty",
# "posted", "done"}. Kinds and how they're met:
#   inspect   a unit inspects that device            (FacilityPlant._inspected)
#   diagnose  Diagnose that unit                     (its menu in Cameras)
#   job       that job is done by the deadline        (checked)
#   output    throughput at or above `target`% at the deadline
#   report    Duties > File it (a button: 20 minutes)
#   explain   reply to Liaison Pell and explain yourself (her Reply)
#   uplink    the corkHQ uplink is restored           (checked)
# Others come from Pell (escalation) and the story (events.txt "directive").
class_name Directives
extends RefCounted

const CHECK_EVERY := 60.0
## Facility seconds between new directives (random in this range).
const GAP := Vector2(4200.0, 7200.0)
## How long the first one waits after clock-in.
const FIRST_AFTER := 3000.0
const MAX_ACTIVE := 2
const REPORT_MINUTES := 20.0
## No new directives this close to the end of the shift.
const LAST_CALL := 2700.0

var sim_id := "directives"
var active: Array[Dictionary] = []
var next_id := 1
var posted := 0
## This shift: directives met and missed.
var met := 0
var missed := 0
var rng := RandomNumberGenerator.new()
var _acc := 0.0
var _next_at := -1.0


## A directive is met (the supervisor did the thing). kind/target as above.
func notify(sim: FacilitySim, kind: String, target := "") -> void:
	for d in active.duplicate():
		if d.kind == kind and (target.is_empty() or str(d.target) == target or str(d.target).is_empty()):
			_complete(sim, d)


## Posts a directive now. Returns its id.
func issue(sim: FacilitySim, kind: String, target: String, minutes: float, text: String, reward := 3.0, penalty := 7.0) -> int:
	for d in active:
		if d.kind == kind and str(d.target) == target:
			return int(d.id)
	var due := sim.time() + minutes * 60.0
	var camp := sim.get_system("campaign") as Campaign
	if camp and camp.on_duty():
		due = minf(due, camp.shift_end_time())   # nothing is due after the shift
	var d := {"id": next_id, "kind": kind, "target": target, "text": text, "due": due,
		"reward": reward, "penalty": penalty, "posted": sim.time()}
	next_id += 1
	posted += 1
	active.append(d)
	var hq := sim.get_system("hq") as CorkHQ
	if hq:
		hq.post(sim, "Directorate of Output", "order", "DIRECTIVE: %s Due %s." % [text, FacilitySim.format_clock(d.due)])
	return int(d.id)


func get_directive(id: int) -> Dictionary:
	for d in active:
		if int(d.id) == id:
			return d
	return {}


func _complete(sim: FacilitySim, d: Dictionary) -> void:
	active.erase(d)
	met += 1
	var o := sim.get_system("oversight") as Oversight
	if o:
		o.commend(sim, "directive met: " + str(d.text), float(d.reward))
	var hq := sim.get_system("hq") as CorkHQ
	if hq:
		hq.post(sim, "Directorate of Output", "notice", "Directive met. Noted.")


func _miss(sim: FacilitySim, d: Dictionary) -> void:
	active.erase(d)
	missed += 1
	var hq := sim.get_system("hq") as CorkHQ
	if hq:
		hq.post(sim, "Directorate of Output", "warning", "DIRECTIVE MISSED: %s This is on your record." % d.text)
	var o := sim.get_system("oversight") as Oversight
	if o:
		o.penalise(sim, "missed directive: " + str(d.text), float(d.penalty))


# --- Making them up -----------------------------------------------------------------

func _generate(sim: FacilitySim) -> void:
	var plant := sim.get_system("plant") as FacilityPlant
	var board := sim.get_system("work") as WorkBoard
	var options: Array[Callable] = []
	if plant:
		options.append(func():
			# Inspect something that's wearing, or anything with a fault.
			var ids := plant.device_ids().filter(func(i): return plant.device(i).kind in ["pod", "filter", "pipe", "relay", "door", "camera"])
			var id: String = ids[rng.randi() % ids.size()]
			issue(sim, "inspect", id, rng.randf_range(45.0, 75.0), ("Have %s inspected (Cameras: open it and click its caption, send a unit)." if plant.device(id).kind == "camera" else "Have %s inspected (Cameras: click it, send a unit).") % plant.device(id).name))
		options.append(func():
			var target := clampi(roundi(plant.throughput * 100.0) + 2, 78, 88)
			issue(sim, "output", str(target), rng.randf_range(60.0, 90.0), "Throughput is %d%%. Have it at %d%% or better." % [roundi(plant.throughput * 100.0), target], 4.0, 8.0))
	options.append(func():
		var bots := FacilitySetup.robots(sim).filter(func(b): return not b.offline())
		if not bots.is_empty():
			var b: RobotAgent = bots[rng.randi() % bots.size()]
			issue(sim, "diagnose", b.robot_id, rng.randf_range(45.0, 75.0), "Run diagnostics on unit %s (Cameras: click it)." % b.display_name().to_upper()))
	options.append(func():
		issue(sim, "report", "", rng.randf_range(40.0, 70.0), "File an interim output report (Duties)."))
	if board:
		var urgent := board.open_jobs().filter(func(j): return int(j.priority) >= 1 and str(j.claimed_by).is_empty())
		if not urgent.is_empty():
			options.append(func():
				var j: Dictionary = urgent[rng.randi() % urgent.size()]
				issue(sim, "job", str(j.id), rng.randf_range(60.0, 90.0), "Get job #%d (%s) done." % [j.id, j.title], 4.0, 8.0))
	options[rng.randi() % options.size()].call()


func _met(sim: FacilitySim, d: Dictionary) -> int:
	# 1 met, 0 failed (at the deadline), -1 still open
	var late := sim.time() >= float(d.due)
	match str(d.kind):
		"job":
			var board := sim.get_system("work") as WorkBoard
			var j := board.get_job(int(d.target)) if board else {}
			if j.is_empty() or j.status == "done":
				return 1
			if j.status == "cancelled":
				return 1
		"output":
			if late:
				var plant := sim.get_system("plant") as FacilityPlant
				return 1 if plant and plant.throughput * 100.0 >= float(d.target) - 0.5 else 0
		"uplink":
			var plant := sim.get_system("plant") as FacilityPlant
			if plant and not plant.device("uplink").fault:
				return 1
	return 0 if late else -1


# --- System ---------------------------------------------------------------------------

func sim_start(sim: FacilitySim) -> void:
	rng.seed = sim.rng.randi()


func sim_tick(sim: FacilitySim, dt: float) -> void:
	_acc += dt
	if _acc < CHECK_EVERY - 0.001:
		return
	_acc = 0.0
	var camp := sim.get_system("campaign") as Campaign
	if camp and not camp.on_duty():
		_next_at = -1.0
		return
	for d in active.duplicate():
		var m := _met(sim, d)
		if m == 1:
			_complete(sim, d)
		elif m == 0:
			_miss(sim, d)
	if _next_at < 0.0:
		_next_at = sim.time() + FIRST_AFTER
	# No new demands while corkHQ can't reach the facility (the uplink is down).
	var o := sim.get_system("oversight") as Oversight
	var late_in_shift := camp != null and camp.shift_end_time() - sim.time() < LAST_CALL
	if sim.time() >= _next_at and active.size() < MAX_ACTIVE and not late_in_shift and not (o and o.uplink_down(sim)):
		_generate(sim)
		_next_at = sim.time() + rng.randf_range(GAP.x, GAP.y)


func sim_event(sim: FacilitySim, event_name: String, _data: Dictionary) -> void:
	if event_name == "shift_start":
		met = 0
		missed = 0
	if event_name == "shift_end":
		# Whatever's outstanding at the end of the shift is missed: now, on
		# shift, not in the night (shift_close is when the night begins).
		for d in active.duplicate():
			_miss(sim, d)


func sim_save() -> Dictionary:
	return {"active": active.duplicate(true), "next_id": next_id, "posted": posted, "acc": _acc, "next_at": _next_at, "met": met, "missed": missed,
		"rng_seed": str(rng.seed), "rng_state": str(rng.state)}


func sim_load(d: Dictionary) -> void:
	active.clear()
	for a in d.get("active", []):
		var x: Dictionary = a.duplicate()
		x.id = int(x.id)
		x.due = float(x.due)
		active.append(x)
	next_id = int(d.get("next_id", 1))
	posted = int(d.get("posted", 0))
	met = int(d.get("met", 0))
	missed = int(d.get("missed", 0))
	_acc = float(d.get("acc", 0.0))
	_next_at = float(d.get("next_at", -1.0))
	rng.seed = int(str(d.get("rng_seed", "0")))
	rng.state = int(str(d.get("rng_state", "0")))


func sim_describe(sim: FacilitySim) -> PackedStringArray:
	var lines := PackedStringArray(["DIRECTIVES  %d active, next at %s" % [active.size(), FacilitySim.format_clock(_next_at) if _next_at >= 0.0 else "-"]])
	for d in active:
		lines.append("  #%d %s %s due %s: %s" % [d.id, d.kind, d.target, FacilitySim.format_clock(d.due), d.text])
	return lines

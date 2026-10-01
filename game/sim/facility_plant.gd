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
#   freight  Crates delivered to the hangar at random ("Stack freight"): at
#            the loading bay and in the deep stacks. Ogre's work.
#   waste    The pods' waste bins (pod bay). They fill as the pods run.
#            "Take out the pod waste" (Hauler) carries it to the hangar
#            compactor. Bins near full and the units complain; overflowing,
#            it wears on their software (stability, every unit).
#   rails    Grime on the rail network. Dirty rails slow every unit down.
#            "Clean the rails" (Hauler).
#   compactor  The hangar's waste compactor. Pod waste and cleared debris go
#            in it; full, nobody can take out waste or clear debris until Ogre
#            empties it in bulk ("Empty the waste compactor"). It starts nearly
#            empty: hauling the waste once a day, it fills on day 2.
#
# CHORES (pod waste, the compactor, the rails: "chore" below) wait for the
# supervisor: the night autopilot only keeps the facility alive (breakdowns,
# pods, filters), it doesn't do the rounds.
#
# Most of the work is ROUTINE: pods, filters, waste, rails, the compactor,
# freight. No parts, just the units' time and a little wear. Parts are for
# real breakdowns (leaks, the relay, the gate, cameras).
#   feed     The hangar's coolant feed: a canister from stock goes into the
#            loop by Ogre's crane ("Feed a coolant canister", +50% coolant).
#            Hauler can do it from the rail when it must (Ogre's down), but
#            the canisters are too heavy for it: it wears, and it says so.
#
# OGRE'S CORE. A new facility starts with Ogre offline (core regulator).
# The replacement comes through corporate (Form C-9, see Forms); a courier
# drops it at the loading bay, Hauler carries it under Ogre ("core:haul"),
# Tinker fits it ("core:install"), and Ogre's back.
#
# ROLES. Every kind of work belongs to particular units ("units" below; the
# board copies it onto the job, and nobody else will take it):
#   Tinker  pods, the relay, cameras, the uplink (precision work)
#   Hauler  leaks, filters, debris, the freight gate, pod waste, the rails
#           (heavy work, and the routine rounds)
#   either  stuck doors (whoever's on the right side of them)
#   Ogre    everything in the hangar: freight, the compactor, the coolant feed
# (and on the board: Hauler hauls crates and refits parts; Tinker unpacks,
# repairs salvaged parts, and is the only one who services or reboots a unit).
#
# CRATES (the hand-off chain): what you order from Requisitions arrives as
# crates in the deep stacks, and three units bring it in:
#   Ogre     "Stack freight (Deep stacks)": lifts the crate to the loading bay
#   a rail unit  "Haul crate: <item>" from the loading bay (rail units only)
#   Tinker   "Unpack crate: <item>" at the workbench: then it's in stock
# (Coolant is pumped straight into the reservoir; no crate.)
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
## "part": the Requisitions stock item each repair uses up (WorkBoard stops
## the job halfway if there's none). "blocks": the passage a stuck door closes.
const KINDS := {
	"pod": {"job": "Recalibrate %s", "skill": "precise", "work": 600.0, "drift": 0.06,
		"levels": [0.75, 0.5, 0.3], "units": ["tinker"]},
	"filter": {"job": "Sweep filters", "skill": "general", "work": 400.0, "drift": 0.06,
		"levels": [0.6, 0.35, 0.15], "start_priority": 0, "units": ["hauler"]},
	"pipe": {"job": "Clamp coolant leak", "skill": "heavy", "work": 900.0, "rate": 0.05, "priority": 2, "part": "pipe_clamps", "units": ["hauler"]},
	"relay": {"job": "Replace relay fuse", "skill": "precise", "work": 360.0, "rate": 0.08, "priority": 2, "part": "fuse_pack", "units": ["tinker"]},
	"bay": {"job": "Clear debris", "skill": "heavy", "work": 600.0, "rate": 0.12, "priority": 1, "units": ["hauler"]},
	"gate": {"job": "Unjam freight gate", "skill": "general", "work": 300.0, "rate": 0.06, "priority": 2,
		"blocks": "freight_gate", "part": "actuator_kit", "units": ["hauler"]},
	"door": {"job": "Free stuck door: %s", "skill": "general", "work": 480.0, "rate": 0.045, "priority": 2, "units": ["hauler", "tinker"]},
	"camera": {"job": "Repair %s", "skill": "precise", "work": 420.0, "rate": 0.015, "priority": 1, "part": "camera_module", "units": ["tinker"]},
	"uplink": {"job": "Restore the corkHQ uplink", "skill": "precise", "work": 1800.0, "rate": 0.008, "priority": 3, "units": ["tinker"]},
	"freight": {"job": "Stack freight (%s)", "skill": "heavy", "work": 900.0, "rate": 0.12, "priority": 1, "units": ["ogre"]},
	"compactor": {"job": "Empty the waste compactor", "skill": "heavy", "work": 600.0, "drift": 0.004,
		"levels": [0.25, 0.12, 0.03], "units": ["ogre"], "chore": true},
	"waste": {"job": "Take out the pod waste", "skill": "heavy", "work": 420.0, "drift": 0.025,
		"levels": [0.5, 0.3, 0.12], "units": ["hauler"], "chore": true},
	"rails": {"job": "Clean the rails", "skill": "general", "work": 540.0, "drift": 0.04,
		"levels": [0.6, 0.4, 0.2], "start_priority": 0, "units": ["hauler"], "chore": true},
	"feed": {"job": "Feed a coolant canister", "skill": "heavy", "work": 300.0, "part": "coolant_canister", "units": ["ogre", "hauler"]},
}
## Who does the work that isn't a device's: job source prefix -> units.
const SOURCE_UNITS := {"core:haul": ["hauler"], "core:install": ["tinker"], "crate:haul": ["hauler"], "crate:unpack": ["tinker"], "part:repair": ["tinker"],
	"part:refit": ["hauler"], "unit:": ["tinker"], "service:": ["tinker"], "freight_stacks": ["ogre"]}
## Extra wear when Hauler feeds a coolant canister (they're Ogre's to lift).
const FEED_WEAR_HAULER := 0.12
const CORE_HAUL_WORK := 420.0
const CORE_INSTALL_WORK := 900.0
## How much one load of cleared debris, or of pod waste, fills the compactor.
const DEBRIS_LOAD := 0.1
const WASTE_LOAD := 0.3
## On top of the waste bins' slow drift, the pods dump a batch now and then:
## this many batches an hour on average, each this big. (About one full set
## of bins a day, unevenly.)
const WASTE_BATCHES := 0.2
const WASTE_BATCH := Vector2(0.04, 0.09)
## Pod waste bins this full and the units start to mind; full, they lose
## this much software stability an hour (every unit).
const WASTE_COMPLAINS := 0.75
const WASTE_STRESS := 0.025
## Slowest the rails get when they're filthy (x normal speed).
const GRIME_SLOW := 0.6
## Passage doors that can stick: device id -> [name, passage segment, hall-side
## controls, a station on the far side]. A stuck door can be freed from either
## side: the job goes wherever a working unit can actually get to (units
## charging behind a stuck dock door free it from inside).
const DOORS := {"door_pod": ["Pod bay door", "pod_door", "pod_door_ctl", "pods_a"], "door_dock": ["Dock door", "dock_door", "dock_door_ctl", "t_dock"],
	"door_hangar": ["Hangar door", "hangar_door", "hangar_door_ctl", "loading"]}
## Where a unit goes to fix a camera, by the camera's room.
const CAMERA_STATIONS := {"hall": "bay_2", "pod_bay": "pods_a", "workshop": "bench", "maintenance": "t_dock", "hangar": "loading"}
## How long a makeshift patch (no part) holds before the device fails again.
const PATCH_HOLDS := Vector2(7200.0, 18000.0)
## After a proper repair (with its part) a device holds at least this long.
const REPAIR_GRACE := 8.0 * 3600.0
## A hot facility (heat 1 = normal) strains its pipes: leak rate x heat, up to this.
const HEAT_STRAIN := 2.5
## How long the corkHQ uplink runs on its battery once the relay's fuse blows.
const UPLINK_BATTERY := 1200.0
## Suspicion when a camera sees a unit "accidentally" wreck something.
const ACCIDENT_SEEN := 15.0
## Seconds of work in an inspection (a unit goes and looks).
const INSPECT_WORK := 240.0
const HAUL_WORK := 360.0
const UNPACK_WORK := 300.0
## Kinds that don't break: a "fault" is new work arriving (debris, freight).
const ARRIVALS := ["bay", "freight"]
## Chance that cleared debris turns up a damaged part. The part goes to the
## workbench for repair (precise work), then back to its bay to be refitted
## (heavy work): a hand-off between the robots.
const SALVAGE_CHANCE := 0.5
const SALVAGE_PARTS := ["servo", "valve actuator", "cable reel", "pressure sensor", "fan hub"]
const REPAIR_WORK := 480.0
const REFIT_WORK := 300.0
## Coolant lost per hour per leaking pipe, and regained per hour with no leaks.
const LEAK_RATE := 0.25
## How much a coolant canister from stock fills the reservoir.
const COOLANT_CANISTER := 0.5
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
## Crates waiting in the deep stacks for Ogre: requisition order ids, oldest first.
var crates: Array[int] = []

var _ids: Array[String] = []
var _last_job := {}   # device id -> the job that last repaired it (not saved: read at once)
## The last inspection report per device: id -> {"t", "by", "text"}.
var reports := {}
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
	devices.gate.blocks = "freight_gate"
	for id in DOORS:
		_add(id, "door", DOORS[id][0], DOORS[id][2])
		devices[id].blocks = DOORS[id][1]
	var cams := FacilitySetup.cameras()
	for i in cams.size():
		_add("cam_%d" % (i + 1), "camera", "Camera %d" % (i + 1), CAMERA_STATIONS.get(cams[i].room, "bay_2"))
	_add("uplink", "uplink", "corkHQ uplink relay", "uplink")
	_add("freight_bay", "freight", "Loading bay", "loading")
	_add("freight_stacks", "freight", "Deep stacks", "stacks")
	_add("compactor", "compactor", "Waste compactor", "compactor")
	_add("pod_waste", "waste", "Pod waste bins", "waste_bins")
	_add("rails", "rails", "Rails", "bay_2")
	_add("coolant_feed", "feed", "Coolant feed", "coolant_feed")


func _add(id: String, kind: String, display_name: String, station: String) -> void:
	devices[id] = {"id": id, "kind": kind, "name": display_name, "station": station,
		"value": 1.0, "fault": false, "job": -1}
	_ids.append(id)
	_ids.sort()


func device(id: String) -> Dictionary:
	return devices.get(id, {})


func device_ids() -> Array[String]:
	return _ids.duplicate()


## How fast units ride the rails right now (grime slows them).
func rail_factor() -> float:
	return lerpf(GRIME_SLOW, 1.0, clampf(float(devices.rails.value) / 0.6, 0.0, 1.0))


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
	devices.pod_waste.value = sim.rng.randf_range(0.5, 0.65)   # the first run comes up on day 1
	devices.compactor.value = 0.95                              # room for day 1; full by day 2
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
			# How hard the facility pushes depends on the shift (orientation is
			# gentler, audit day harsher), and nights are quiet: some random
			# faults hold off and come back later.
			var camp := sim.get_system("campaign") as Campaign
			if data.get("random", false) and camp and sim.rng.randf() >= camp.pressure():
				_book_fault(sim, str(data.device))
				return
			_fault(sim, str(data.device))
		"job_done":
			var id := str(data.get("source", ""))
			if devices.has(id):
				_last_job[id] = int(data.get("job", -1))
				_repaired(sim, id, str(data.get("by", "")))
				var board := sim.get_system("work") as WorkBoard
				var job := board.get_job(int(data.get("job", -1))) if board else {}
				if job.get("makeshift", false) and KINDS[devices[id].kind].has("rate"):
					# A patch without the part: it won't hold for long.
					sim.schedule_in(sim.rng.randf_range(PATCH_HOLDS.x, PATCH_HOLDS.y), "plant_fault", {"device": id})
					sim.note("plant", "%s is patched, not fixed: it won't hold long" % devices[id].name)
			elif id.begins_with("inspect:"):
				_inspected(sim, id.trim_prefix("inspect:"), str(data.get("by", "")))
			elif id.begins_with("part:"):
				_part_step(sim, id, str(data.get("by", "")))
			elif id.begins_with("crate:"):
				_crate_step(sim, id, str(data.get("by", "")))
			elif id.begins_with("core:"):
				_core_step(sim, id, str(data.get("by", "")))
			shift_stats.jobs += 1
		"job_cancelled":
			var id := str(data.get("source", ""))
			if devices.has(id) and int(devices[id].job) == int(data.job):
				devices[id].job = -1
		"uplink_battery":
			# The relay's still out: the uplink's battery is flat.
			if devices.relay.fault and not devices.uplink.fault:
				devices.uplink.fault = true
				devices.uplink.unpowered = true
				sim.note("alarm", "corkHQ uplink DOWN: no power (the relay is out)")
				sim.schedule(sim.time(), "alarm", {"device": "uplink"})
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
		if d.kind == "waste" and sim.rng.randf() < WASTE_BATCHES * hours:
			d.value = maxf(float(d.value) - sim.rng.randf_range(WASTE_BATCH.x, WASTE_BATCH.y), 0.0)   # a batch from the pods
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
		if job.is_empty() or not WorkBoard.active(job):
			d.job = board.post(sim, _job_title(d), k.skill, d.station, k.work, want, id)
		elif int(job.priority) < want:
			board.set_priority(sim, int(d.job), want)
	throughput = sync / maxf(pods, 1)
	shift_stats.output_sum += throughput
	shift_stats.samples += 1
	_waste_stress(sim)


# Pod waste piling up: the units mind. Near full, they grumble about it;
# overflowing, it wears on their software.
func _waste_stress(sim: FacilitySim) -> void:
	var fill := 1.0 - float(devices.pod_waste.value)
	if fill < WASTE_COMPLAINS:
		return
	var k := clampf((fill - WASTE_COMPLAINS) / (1.0 - WASTE_COMPLAINS), 0.0, 1.0)
	var chatter := sim.get_system("chatter") as RobotChatter
	for bot in FacilitySetup.robots(sim):
		if bot.offline():
			continue
		bot.stability = maxf(bot.stability - WASTE_STRESS * k * UPDATE / 3600.0, 0.0)
		if chatter and sim.rng.randf() < 0.004:
			chatter.trigger(sim, bot, "waste", {})


func _fault(sim: FacilitySim, id: String) -> void:
	var d: Dictionary = devices[id]
	if d.fault:
		return
	var k: Dictionary = KINDS[d.kind]
	shift_stats.faults += 1
	var board := sim.get_system("work") as WorkBoard
	if d.kind == "freight":
		sim.note("plant", "Freight delivered: crates waiting at %s" % d.name)
	elif not d.kind in ARRIVALS:
		d.fault = true
		sim.note("alarm", {"pipe": "COOLANT LEAK: %s", "relay": "%s FUSE BLOWN: docks charge at 40%%",
			"gate": "%s JAMMED: the route is blocked", "door": "%s STUCK: the route is blocked",
			"camera": "%s: NO SIGNAL", "uplink": "%s DOWN: no link to corkHQ"}.get(d.kind, "FAULT: %s") % d.name)
		if d.has("blocks"):
			var layout := sim.get_system("layout") as FacilityLayout
			if layout:
				layout.set_blocked(sim, d.blocks, true, "stuck" if d.kind == "door" else "jammed")
		if d.kind == "relay":
			sim.schedule_in(UPLINK_BATTERY, "uplink_battery", {})
			sim.note("plant", "corkHQ uplink on battery (%d minutes)" % roundi(UPLINK_BATTERY / 60.0))
	var open_job: Dictionary = board.get_job(int(d.job)) if board and int(d.job) >= 0 else {}
	if board and (open_job.is_empty() or not WorkBoard.active(open_job)):
		var where: String = _door_side(sim, id) if d.kind == "door" else str(d.station)
		d.job = board.post(sim, _job_title(d), k.skill, where, k.work, int(k.priority), id)
	if d.kind in ARRIVALS:
		_book_fault(sim, id)   # debris keeps falling (and freight arriving) whether or not it's cleared
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
	if hq and Oversight.watched(sim, robot.room(sim)):   # corporate only sees it on camera
		hq.noticed_damage(sim, robot)
	if KINDS[d.kind].has("drift"):
		d.value = maxf(float(d.value) - 0.45, 0.0)   # the job gets posted on the next update
	else:
		_fault(sim, id)


# Which side of a stuck door its job goes on: the controls in the hall if a
# working unit can get there, else the far side.
func _door_side(sim: FacilitySim, id: String) -> String:
	var sides: Array = [DOORS[id][2], DOORS[id][3]]
	var who: Array = KINDS.door.get("units", [])
	for st in sides:
		for bot in FacilitySetup.robots(sim):
			if (who.is_empty() or bot.robot_id in who) and not bot.offline() and not bot.traits.stationary and bot.why_cant_reach(sim, st).is_empty():
				return st
	return sides[0]


## A unit "accidentally" damages a device (it was asked to). To the facility
## and to corporate it's an ordinary fault; only the unit and you know.
func accident(sim: FacilitySim, id: String, robot: RobotAgent) -> void:
	var d: Dictionary = devices.get(id, {})
	if d.is_empty() or d.fault:
		return
	sim.note(robot.robot_id, "%s knocked into %s" % [robot.display_name(), d.name])
	var o := sim.get_system("oversight") as Oversight
	if o:   # on camera, it's not an accident (recorded before the link goes)
		o.violate(sim, "unit %s damaged the %s, on camera" % [robot.display_name(), d.name], ACCIDENT_SEEN, 0.0, robot.room(sim))
	_fault(sim, id)
	# It won't be the one to fix what it just broke.
	var board := sim.get_system("work") as WorkBoard
	var job := board.get_job(int(d.job)) if board and int(d.job) >= 0 else {}
	if not job.is_empty():
		job.not_by = robot.sim_id


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
		"door": sim.note("plant", "%s freed by %s" % [d.name, who])
		"camera":
			sim.note("plant", "%s repaired by %s: signal back" % [d.name, who])
			var fixer := sim.get_system(by) as RobotAgent
			if fixer:   # the first thing the camera sees: its face, close up, then a wave
				fixer.request_clip("act_wave_camera", {"cam": int(id.trim_prefix("cam_")) - 1})
		"uplink": sim.note("plant", "%s restored by %s: corkHQ is listening again" % [d.name, who])
		"compactor": sim.note("plant", "%s emptied by %s" % [d.name, who])
		"waste":
			var comp: Dictionary = devices["compactor"]
			comp.value = maxf(float(comp.value) - WASTE_LOAD, 0.0)
			sim.note("plant", "%s took the pod waste down to the hangar compactor (%d%% full)" % [who, _pct(1.0 - float(comp.value))])
		"rails": sim.note("plant", "%s cleaned the rails" % who)
		"feed":
			coolant = minf(coolant + COOLANT_CANISTER, 1.0)
			sim.note("plant", "%s fed a coolant canister into the loop: coolant %d%%" % [who, _pct(coolant)])
			var bot := sim.get_system(by) as RobotAgent
			if bot and not bot.traits.stationary:
				# Not built for it: the canisters are Ogre's to lift.
				bot.wear = minf(bot.wear + FEED_WEAR_HAULER, 1.0)
				var chatter := sim.get_system("chatter") as RobotChatter
				if chatter:
					chatter.trigger(sim, bot, "feed_heavy", {})
		"freight":
			sim.note("plant", "Freight at %s stacked by %s" % [d.name, who])
			if id == "freight_stacks" and not crates.is_empty():
				_lift_crate(sim, who)
		"bay":
			var comp: Dictionary = devices["compactor"]
			comp.value = maxf(float(comp.value) - DEBRIS_LOAD, 0.0)
			if float(comp.value) <= 0.02:
				sim.note("alarm", "Waste compactor FULL: no more debris can be cleared until it's emptied")
			if sim.rng.randf() < SALVAGE_CHANCE:
				var part: String = SALVAGE_PARTS[sim.rng.randi() % SALVAGE_PARTS.size()]
				sim.note("plant", "%s found a damaged %s in the %s debris and set it aside for the workbench" % [who, part, d.name])
				var board := sim.get_system("work") as WorkBoard
				if board:
					board.post(sim, "Repair salvaged %s" % part, "precise", "bench", REPAIR_WORK, 1,
						"part:repair:%s:%s:%s" % [id, part, by])
	if d.has("blocks"):
		var layout := sim.get_system("layout") as FacilityLayout
		if layout:
			layout.set_blocked(sim, d.blocks, false)
	if was_fault:
		var board := sim.get_system("work") as WorkBoard
		var job := board.get_job(int(_last_job.get(id, -1))) if board else {}
		if not job.get("makeshift", false):
			_book_fault(sim, id, REPAIR_GRACE)   # fixed properly: it holds a good while
	var was_unpowered: bool = id == "relay" and bool(devices.uplink.get("unpowered", false))
	if was_unpowered:
		devices.uplink.unpowered = false
	# Power's back: the uplink comes back too (unless it's been cut by hand, or it's broken as well).
	if was_unpowered and devices.uplink.fault and not bool(devices.uplink.get("disabled", false)) and not _uplink_broken():
		devices.uplink.fault = false
		sim.note("plant", "corkHQ uplink back on mains power")
		sim.schedule(sim.time(), "uplink_restored", {})


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


# --- Crates ----------------------------------------------------------------------------

## Ogre's replacement core has arrived at the loading bay: Hauler brings it
## under Ogre, Tinker fits it.
func receive_core(sim: FacilitySim) -> void:
	sim.note("plant", "Priority courier: Ogre's replacement core is at the loading bay")
	var board := sim.get_system("work") as WorkBoard
	if board:
		var id := board.post(sim, "Haul crate: Ogre's core", "heavy", "loading", CORE_HAUL_WORK, 2, "core:haul")
		board.get_job(id).rail_only = true


func _core_step(sim: FacilitySim, source: String, by: String) -> void:
	var board := sim.get_system("work") as WorkBoard
	var who := by.trim_prefix("robot_").capitalize()
	if source == "core:haul" and board:
		sim.note("plant", "%s set Ogre's new core down under it" % who)
		board.post(sim, "Install Ogre's core", "precise", "ogre_service", CORE_INSTALL_WORK, 2, "core:install")
	elif source == "core:install":
		sim.note("plant", "%s fitted Ogre's new core regulator" % who)
		var ogre := sim.get_system("robot_ogre") as RobotAgent
		if ogre:
			ogre.repair(sim)
		var k := sim.get_system("knowledge") as Knowledge
		if k:
			k.forget("ogre_down")
			k.learn(sim, "ogre_fixed")


## A requisition has arrived as a crate. A very heavy one waits in the deep
## stacks for Ogre to lift; anything else is left at the loading bay for a
## rail unit to haul in.
func receive_crate(sim: FacilitySim, order_id: int, label: String, heavy := true) -> void:
	if not heavy:
		sim.note("plant", "Crate delivered to the loading bay: %s" % label)
		var board0 := sim.get_system("work") as WorkBoard
		if board0:
			var jid := board0.post(sim, "Haul crate: %s" % label, "heavy", "loading", HAUL_WORK, 1, "crate:haul:%d" % order_id)
			board0.get_job(jid).rail_only = true
		return
	crates.append(order_id)
	sim.note("plant", "Crate delivered to the deep stacks: %s" % label)
	var d: Dictionary = devices["freight_stacks"]
	var board := sim.get_system("work") as WorkBoard
	var job: Dictionary = board.get_job(int(d.job)) if board and int(d.job) >= 0 else {}
	if board and (job.is_empty() or not WorkBoard.active(job)):
		d.job = board.post(sim, _job_title(d), KINDS.freight.skill, d.station, KINDS.freight.work, 1, "freight_stacks")
	if board:
		board.request(sim, int(d.job))   # a delivery is brought in without being asked


# Ogre has cleared the stacks: the oldest crate goes to the loading bay for a rail unit.
func _lift_crate(sim: FacilitySim, who: String) -> void:
	var order_id: int = crates.pop_front()
	var label := _crate_label(sim, order_id)
	var board := sim.get_system("work") as WorkBoard
	sim.note("plant", "%s lowered the crate (%s) to the loading bay" % [who, label])
	if board:
		var jid := board.post(sim, "Haul crate: %s" % label, "heavy", "loading", HAUL_WORK, 1, "crate:haul:%d" % order_id)
		board.get_job(jid).rail_only = true   # Ogre can't carry it anywhere
	# More crates: the stacks aren't clear yet.
	if not crates.is_empty():
		var d: Dictionary = devices["freight_stacks"]
		d.job = board.post(sim, _job_title(d), KINDS.freight.skill, d.station, KINDS.freight.work, 1, "freight_stacks")
		board.request(sim, int(d.job))


# "crate:haul:<order>" -> unpack at the workbench -> "crate:unpack:<order>" -> in stock.
func _crate_step(sim: FacilitySim, source: String, by: String) -> void:
	var bits := source.split(":")
	if bits.size() < 3:
		return
	var order_id := int(bits[2])
	var label := _crate_label(sim, order_id)
	var who := by.trim_prefix("robot_").capitalize()
	var board := sim.get_system("work") as WorkBoard
	if bits[1] == "haul" and board:
		sim.note("plant", "%s hauled the crate (%s) to the workshop" % [who, label])
		board.post(sim, "Unpack crate: %s" % label, "precise", "bench", UNPACK_WORK, 1, "crate:unpack:%d" % order_id)
	elif bits[1] == "unpack":
		sim.note("plant", "%s unpacked the crate (%s)" % [who, label])
		var req := sim.get_system("requisitions") as Requisitions
		if req:
			req.unpacked(sim, order_id)


func _crate_label(sim: FacilitySim, order_id: int) -> String:
	var req := sim.get_system("requisitions") as Requisitions
	var o := req.get_order(order_id) if req else {}
	if o.is_empty():
		return "order #%d" % order_id
	return "%dx %s" % [int(o.qty), req.item(o.item).get("name", o.item)]


# Faults arrive at random (exponential gaps): the next one is booked when the
# last is fixed.
func _book_fault(sim: FacilitySim, id: String, after := 0.0) -> void:
	var rate: float = KINDS[devices[id].kind].rate
	if devices[id].kind == "pipe":
		rate *= clampf(heat(), 1.0, HEAT_STRAIN)   # neglect spirals: hot pipes leak
	var hours := -log(1.0 - sim.rng.randf() * 0.999) / rate
	sim.schedule_in(after + hours * 3600.0, "plant_fault", {"device": id, "random": true})


## Why a job can't be requested right now ("" = it can): debris with the
## compactor full.
func request_blocker(job: Dictionary) -> String:
	var src := str(job.get("source", ""))
	if devices.has(src) and devices[src].kind in ["bay", "waste"] and float(devices.compactor.value) <= 0.02:
		return "The waste compactor in the hangar is full: Ogre has to empty it first."
	return ""


## Is this job a chore the night autopilot leaves for the supervisor?
static func is_chore(sim: FacilitySim, job: Dictionary) -> bool:
	var plant := sim.get_system("plant") as FacilityPlant
	var src := str(job.get("source", ""))
	return plant != null and plant.devices.has(src) and KINDS[plant.devices[src].kind].get("chore", false)


## Which units may do a job (empty = anyone).
static func units_for(source: String, kind := "") -> Array:
	if not kind.is_empty():
		return KINDS.get(kind, {}).get("units", [])
	for p in SOURCE_UNITS:
		if source.begins_with(p):
			return SOURCE_UNITS[p]
	return []


# The uplink itself is broken (a fault with a repair job), not just unpowered.
func _uplink_broken() -> bool:
	return int(devices.uplink.job) >= 0


## Cuts or restores the corkHQ uplink by hand (the maintenance account's
## hqctl). To corporate a cut is just an outage. Returns "" or why not.
func set_uplink_disabled(sim: FacilitySim, off: bool) -> String:
	var u: Dictionary = devices.uplink
	if off:
		if u.fault:
			return "the uplink is already down"
		u.fault = true
		u.disabled = true
		sim.note("alarm", "corkHQ uplink DOWN: disabled from the supervisor terminal")
		sim.schedule(sim.time(), "alarm", {"device": "uplink"})
		return ""
	if not u.get("disabled", false):
		return "the link isn't disabled"
	u.disabled = false
	if u.get("unpowered", false):
		return "enabled, but there's no power to it (the relay is out)"
	u.fault = false
	sim.note("plant", "corkHQ uplink enabled from the supervisor terminal")
	sim.schedule(sim.time(), "uplink_restored", {})
	return ""


# A unit has looked at a device: its report.
func _inspected(sim: FacilitySim, id: String, by: String) -> void:
	if not devices.has(id):
		return
	var text := inspect_text(sim, id)
	var who := by.trim_prefix("robot_").capitalize()
	reports[id] = {"t": sim.time(), "by": who, "text": text}
	sim.note("report", "%s's report on %s: %s" % [who, devices[id].name, text.replace("\n", " ")])
	var bot := sim.get_system(by) as RobotAgent
	var chatter := sim.get_system("chatter") as RobotChatter
	if bot and chatter:
		chatter.trigger(sim, bot, "order_reply", {"text": text.get_slice("\n", 0) + (" " + text.get_slice("\n", 1) if text.get_slice_count("\n") > 1 else "")})
	var dirs := sim.get_system("directives") as Directives
	if dirs:
		dirs.notify(sim, "inspect", id)
	var k := sim.get_system("knowledge") as Knowledge
	if k:
		k.learn(sim, "did:inspect")


## Sends a unit to look at a device (a job anyone can do). Returns the job id.
func post_inspection(sim: FacilitySim, id: String) -> int:
	var board := sim.get_system("work") as WorkBoard
	if board == null or not devices.has(id):
		return -1
	for j in board.open_jobs():
		if str(j.source) == "inspect:" + id:
			return int(j.id)
	return board.post(sim, "Inspect %s" % devices[id].name, "general", str(devices[id].station), INSPECT_WORK, 1, "inspect:" + id)


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
		"shift_stats": shift_stats.duplicate(), "acc": _acc, "crates": crates.duplicate()}


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
	crates.clear()
	for c in data.get("crates", []):
		crates.append(int(c))


## A proper look at one device (the Plant app's Inspect): its state, how
## fast it's wearing, when it'll need work, and who's on it.
func inspect_text(sim: FacilitySim, id: String) -> String:
	var d := device(id)
	if d.is_empty():
		return ""
	var k: Dictionary = KINDS[d.kind]
	var lines := PackedStringArray([device_text(id).strip_edges()])
	if k.has("drift"):
		var rate: float = k.drift * (heat() if d.kind == "pod" else 1.0)
		lines.append("Wearing %.0f%% an hour at this heat." % (rate * 100.0))
		var levels: Array = k.get("levels", [])
		for lv in levels:
			if float(d.value) >= float(lv):
				lines.append("Needs work in about %.1f h (below %d%%)." % [(float(d.value) - float(lv)) / maxf(rate, 0.0001), _pct(lv)])
				break
	elif k.has("rate"):
		lines.append("Fails about %.1f times a day, on average." % (float(k.rate) * 24.0))
	var board := sim.get_system("work") as WorkBoard
	var job: Dictionary = board.get_job(int(d.job)) if board and int(d.job) >= 0 else {}
	if not job.is_empty() and WorkBoard.active(job):
		lines.append("Job #%d %s: %d%% done, %s." % [job.id, job.title, roundi(board.fraction_done(job) * 100.0),
			("%s is on it" % str(job.claimed_by).trim_prefix("robot_").capitalize()) if job.status == "claimed" else "nobody on it yet"])
	if k.has("part"):
		var req := sim.get_system("requisitions") as Requisitions
		lines.append("Repairs use: %s (%d in stock)." % [req.item(k.part).get("name", k.part) if req else k.part,
			int(req.inventory.get(k.part, 0)) if req else 0])
	if not job.is_empty() and not board.missing_part(sim, job).is_empty():
		lines.append("NO PART IN STOCK: order one (Requisitions), or patch it without.")
	elif not job.is_empty() and not job.get("requested", false):
		lines.append("Nobody's been asked to fix it: order maintenance (Cameras: click it).")
	return "\n".join(lines)


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
		"door": state = "STUCK" if d.fault else "working"
		"camera": state = "NO SIGNAL" if d.fault else "ok"
		"uplink": state = ("DISABLED" if d.get("disabled", false) else ("NO POWER" if d.get("unpowered", false) else "DOWN")) if d.fault else "linked"
		"bay": state = "debris" if int(d.job) >= 0 else "clear"
		"freight": state = "crates" if int(d.job) >= 0 else "clear"
		"compactor": state = "FULL" if float(d.value) <= 0.02 else "%d%% full" % _pct(1.0 - float(d.value))
		"waste": state = "OVERFLOWING" if float(d.value) <= 0.02 else "%d%% full" % _pct(1.0 - float(d.value))
		"rails": state = "grime %d%%" % _pct(1.0 - float(d.value))
		"feed": state = "feeding" if int(d.job) >= 0 else "ready"
	return "%-20s %-10s%s" % [d.name, state, ("  job #%d" % int(d.job)) if int(d.job) >= 0 else ""]


func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("PLANT  throughput %d%%   coolant %d%%   heat %.1fx   dock charge %d%%" % [
		_pct(throughput), _pct(coolant), heat(), _pct(charge_factor())])
	for id in _ids:
		if not devices[id].kind in ARRIVALS or int(devices[id].job) >= 0:
			lines.append("  " + device_text(id))
	return lines

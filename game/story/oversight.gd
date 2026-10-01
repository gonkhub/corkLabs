# Oversight (sim_id "oversight"): how corporate judges the supervisor, and
# how the supervisor gets fired. Three ways out:
#
#   performance   STANDING (0-100, corporate's opinion) reaches 0. Shift
#                 reviews move it (A +15 ... F -25), so do duties done or
#                 skipped, idle units, crashes, and commendations.
#   misconduct    SUSPICION (0-100) is what corporate suspects. Policy
#                 violations raise it (reading former staff files, root
#                 commands, games, forced installs...). Every hour on duty
#                 there's an AUDIT: the higher the suspicion, the likelier
#                 it finds something. First find = a formal warning (a
#                 strike), second = dismissal. Some violations can be caught
#                 on the spot (catch_chance).
#   catastrophe   the facility fails on your watch: coolant empty for 60
#                 facility minutes, or throughput under 25% for an hour and a half.
#
# Every violation is written to the AUDIT TRAIL, which corporate reads. With
# the maintenance account, "auditctl" can read and purge it (itself a risk).
# The maintenance account can also cut the uplink by hand ("hqctl disable"):
# to corporate that's just an outage (see THE UPLINK below).
#
# PELL ESCALATES. Violations come in kinds (files, games, talk, maint). As a
# kind piles up in a shift, Liaison Pell says something (level 1), then
# demands an explanation with a deadline (level 2: a directive, answered in
# her Reply), then sets Compliance on you (level 3: standing down, and a
# targeted audit half an hour later).
#
# THE CAMERAS ARE CORPORATE'S EYES. What happens in a room (talking to a
# unit, a unit's "accident" or sabotage) is only on the record if a working
# camera covers that room (`room` in violate()). A dead camera is a blind
# spot; a careful supervisor makes one before doing something it shouldn't.
# Terminal activity (files, accounts, tools) goes through the audit daemon
# whatever the cameras see.
#
# THE UPLINK. corkHQ sees the facility through one relay in the workshop.
# While it's down (it breaks now and then, or a unit can be talked into an
# "accident" with it), nothing is recorded: no suspicion, no trail, no audits,
# no Pell. Corporate notices the outage itself, wants it fixed within the hour,
# and every repeat outage adds suspicion of its own.
class_name Oversight
extends RefCounted

const START_STANDING := 60.0
const AUDIT_EVERY := 3600.0
## Suspicion lost per facility hour (they forget, slowly).
const SUSPICION_DECAY := 2.0
## Below this, audits find nothing.
const AUDIT_FLOOR := 25.0
const REVIEW_STANDING := {"A": 15.0, "B": 8.0, "C": 0.0, "D": -12.0, "F": -25.0}
const STRIKES_TO_FIRE := 2
const CRISIS_CHECK := 60.0
const COOLANT_CRISIS := 0.02
const COOLANT_LIMIT := 3600.0
const OUTPUT_CRISIS := 0.25
const OUTPUT_LIMIT := 5400.0
## No catastrophe in the first hour of a shift: that's the night's mess.
const CRISIS_GRACE := 5400.0
## Violations of each kind (in one shift) at which Pell escalates to levels 1, 2, 3.
const ESCALATE := {"files": [1, 3, 5], "games": [1, 2, 4], "talk": [3, 6, 10], "maint": [1, 2, 3]}
const COMPLIANCE_STANDING := 6.0
const TARGETED_AUDIT := 30.0
## Suspicion each repeat uplink outage adds (x outages so far, minus one).
const UPLINK_REPEAT := 5.0

var sim_id := "oversight"
var standing := START_STANDING
var suspicion := 0.0
var strikes := 0
## [{"t", "what", "amount"}]: what corporate can find at an audit.
var trail: Array[Dictionary] = []
## "" while employed; otherwise why they were let go.
var fired_reason := ""
var fired_kind := ""
## DevTools: never dismissed (not saved).
var immune := false
var rng := RandomNumberGenerator.new()
## Audits only run while this is true (the Campaign sets it: on duty).
var watching := true

var _audit_acc := 0.0
var _crisis_acc := 0.0
var _coolant_since := -1.0
var _output_since := -1.0
var _warned := {}
## Violations this shift, by kind (Pell's escalation).
var counts := {}
## Times the uplink has gone down, when the current outage began, and how much
## went unrecorded while it was down.
var uplink_breaks := 0
var _uplink_since := -1.0
var blind := 0
## Things done where no camera could see them (this run).
var unseen := 0


func fired() -> bool:
	return not fired_reason.is_empty()


## Does a working camera cover this room (does corporate see what happens there)?
static func watched(sim: FacilitySim, room: String) -> bool:
	var plant := sim.get_system("plant") as FacilityPlant if sim else null
	var cams := FacilitySetup.cameras()
	for i in cams.size():
		if str(cams[i].room) == room and (plant == null or not bool(plant.device("cam_%d" % (i + 1)).get("fault", false))):
			return true
	return false


## Is corkHQ's uplink down (nothing gets recorded)?
func uplink_down(sim: FacilitySim) -> bool:
	var plant := sim.get_system("plant") as FacilityPlant if sim else null
	return plant != null and bool(plant.device("uplink").get("fault", false))


## A policy violation: suspicion + a line in the audit trail. With
## `catch_chance`, corporate may notice right now. Nothing at all while the
## uplink is down, or (something done in a `room`) if no camera sees it.
func violate(sim: FacilitySim, what: String, amount: float, catch_chance := 0.0, room := "") -> void:
	if uplink_down(sim):
		blind += 1
		sim.note("oversight", "Unrecorded (uplink down): %s" % what)
		return
	if not room.is_empty() and not watched(sim, room):
		unseen += 1
		sim.note("oversight", "Unseen (no working camera in the %s): %s" % [room.replace("_", " "), what])
		return
	suspicion = clampf(suspicion + amount, 0.0, 100.0)
	trail.append({"t": sim.time(), "what": what, "amount": amount})
	sim.note("oversight", "Violation logged: %s (suspicion %d)" % [what, roundi(suspicion)])
	if catch_chance > 0.0 and not fired() and rng.randf() < catch_chance:
		_caught(sim, what)
	_escalate(sim, category(what), what)


## Which kind of violation this is (for Pell).
static func category(what: String) -> String:
	if what.begins_with("read /home") or what.begins_with("copied /home") or what.contains("former staff"):
		return "files"
	if what.contains("recreational"):
		return "games"
	if what.begins_with("conversation with unit") or what.ends_with("on camera"):
		return "talk"
	if what.contains("maintenance account") or what.contains("pod ") or what.contains("audit") or what.contains("corkHQ link") \
			or what.contains("override") or what.contains("unapproved") or what.contains("decommissioned"):
		return "maint"
	return ""


func _escalate(sim: FacilitySim, cat: String, what := "") -> void:
	if cat.is_empty() or not ESCALATE.has(cat) or not watching:
		return
	counts[cat] = int(counts.get(cat, 0)) + 1
	var level: int = (ESCALATE[cat] as Array).find(int(counts[cat])) + 1
	if level <= 0:
		return
	var hq := sim.get_system("hq") as CorkHQ
	if hq:
		hq.say(sim, "pell_%s_%d" % [cat, level], "reprimand", {"what": what})
	match level:
		2:
			var dirs := sim.get_system("directives") as Directives
			if dirs:
				dirs.issue(sim, "explain", cat, 45.0, "Explain your %s to Liaison Pell (corkHQ: Reply)." % {"files": "file access",
					"games": "use of recreational software", "talk": "conversations with units", "maint": "use of maintenance tools"}[cat], 2.0, 8.0)
		3:
			standing = clampf(standing - COMPLIANCE_STANDING, 0.0, 100.0)
			sim.note("oversight", "Compliance has your terminal (%s): standing %d" % [cat, roundi(standing)])
			sim.schedule_in(1800.0, "targeted_audit", {"why": cat})


## Corporate likes something (a duty done, a good review).
func commend(sim: FacilitySim, what: String, amount: float) -> void:
	standing = clampf(standing + amount, 0.0, 100.0)
	sim.note("oversight", "Standing +%d: %s (%d)" % [roundi(amount), what, roundi(standing)])


## Corporate dislikes something. Standing at 0 = dismissal.
func penalise(sim: FacilitySim, what: String, amount: float) -> void:
	standing = clampf(standing - amount, 0.0, 100.0)
	sim.note("oversight", "Standing -%d: %s (%d)" % [roundi(amount), what, roundi(standing)])
	if standing <= 0.0:
		fire(sim, "performance", "Your standing with the Directorate has reached zero. %s was the last straw." % what.capitalize())


func fire(sim: FacilitySim, kind: String, reason: String) -> void:
	if fired():
		return
	if immune:
		sim.note("oversight", "(dev) would have been dismissed: %s" % reason)
		return
	fired_kind = kind
	fired_reason = reason
	sim.note("oversight", "DISMISSED (%s): %s" % [kind, reason])
	var hq := sim.get_system("hq") as CorkHQ
	if hq:
		hq.post(sim, "Human Resources", "reprimand", "NOTICE OF DISMISSAL. %s Your access ends at the close of this session." % reason)
	sim.schedule_in(0.0, "dismissed", {"kind": kind})


## Erases the audit trail (auditctl purge). Suspicion falls by half; the
## gap in the logs is itself a (smaller) risk.
func purge_trail(sim: FacilitySim) -> int:
	var n := trail.size()
	trail.clear()
	suspicion *= 0.5
	sim.note("oversight", "Audit trail purged (%d entries)" % n)
	return n


# --- Audits ------------------------------------------------------------------------

## Runs an audit now. `strictness` adds to the odds (audit day).
## Returns what it found ("" = nothing).
func audit(sim: FacilitySim, strictness := 0.0) -> String:
	if uplink_down(sim):
		sim.note("oversight", "Audit skipped: no uplink to corkHQ")
		return ""
	var odds := (suspicion - AUDIT_FLOOR + strictness) / 100.0
	if trail.is_empty() or odds <= 0.0 or rng.randf() >= odds:
		sim.note("oversight", "Hourly audit: nothing found (suspicion %d)" % roundi(suspicion))
		return ""
	var found: Dictionary = trail[rng.randi() % trail.size()]
	_caught(sim, str(found.what))
	return str(found.what)


func _caught(sim: FacilitySim, what: String) -> void:
	strikes += 1
	var hq := sim.get_system("hq") as CorkHQ
	if strikes >= STRIKES_TO_FIRE:
		fire(sim, "misconduct", "An audit of your terminal found: %s. This was your final warning." % what)
		return
	standing = clampf(standing - 15.0, 0.0, 100.0)
	suspicion = maxf(suspicion - 20.0, 0.0)
	sim.note("oversight", "Caught: %s (strike %d)" % [what, strikes])
	if hq:
		hq.post(sim, "Compliance", "reprimand", "FORMAL WARNING. An audit of your terminal found: %s. This is recorded. There will not be a second warning." % what)


# --- Crises ---------------------------------------------------------------------------

func _check_crisis(sim: FacilitySim) -> void:
	var plant := sim.get_system("plant") as FacilityPlant
	if plant == null:
		return
	# What you inherit from the night isn't on your watch yet: an hour's grace.
	var camp := sim.get_system("campaign") as Campaign
	if camp and sim.time() < camp.shift_start_time() + CRISIS_GRACE:
		_coolant_since = -1.0
		_output_since = -1.0
		return
	_coolant_since = _crisis_timer(sim, plant.coolant <= COOLANT_CRISIS, _coolant_since, COOLANT_LIMIT, "coolant",
		"CRITICAL: the coolant loop is empty. The pod hall is overheating. Restore coolant immediately.",
		"The coolant loop ran dry on your watch and the pod hall overheated.")
	_output_since = _crisis_timer(sim, plant.throughput <= OUTPUT_CRISIS, _output_since, OUTPUT_LIMIT, "output",
		"CRITICAL: facility throughput has collapsed. Restore output, now.",
		"Facility output collapsed on your watch and stayed down for an hour and a half.")


func _crisis_timer(sim: FacilitySim, bad: bool, since: float, limit: float, id: String, warning: String, reason: String) -> float:
	if not bad:
		_warned.erase(id)
		return -1.0
	if since < 0.0:
		since = sim.time()
	var hq := sim.get_system("hq") as CorkHQ
	if not _warned.has(id):
		_warned[id] = true
		if hq:
			hq.post(sim, "Directorate of Output", "warning", warning)
	if sim.time() - since >= limit:
		fire(sim, "catastrophe", reason)
	return since


# --- System ---------------------------------------------------------------------------

func sim_start(sim: FacilitySim) -> void:
	rng.seed = sim.rng.randi()


func sim_tick(sim: FacilitySim, dt: float) -> void:
	if fired():
		return
	suspicion = maxf(suspicion - SUSPICION_DECAY * dt / 3600.0, 0.0)
	if not watching:
		_coolant_since = -1.0
		_output_since = -1.0
		return
	_crisis_acc += dt
	if _crisis_acc >= CRISIS_CHECK - 0.001:
		_crisis_acc = 0.0
		_check_crisis(sim)
	_audit_acc += dt
	if _audit_acc >= AUDIT_EVERY - 0.001:
		_audit_acc = 0.0
		audit(sim)


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	match event_name:
		"shift_start":
			counts = {}
		"targeted_audit":
			if watching and not fired():
				var hq := sim.get_system("hq") as CorkHQ
				if hq:
					hq.post(sim, "Compliance", "reprimand", "Targeted audit of your terminal: in progress.")
				audit(sim, TARGETED_AUDIT)
		"job_done", "uplink_restored":
			if (event_name == "uplink_restored" or str(data.get("source", "")) == "uplink") and _uplink_since >= 0.0:
				var down := sim.time() - _uplink_since
				_uplink_since = -1.0
				var hq := sim.get_system("hq") as CorkHQ
				if hq:
					hq.post(sim, "IT Services", "notice", "Uplink to C-7 restored after %d minutes. Logs from the outage are incomplete." % roundi(down / 60.0))
				sim.note("oversight", "Uplink back after %d min: %d things went unrecorded" % [roundi(down / 60.0), blind])
				blind = 0
		"shift_end":
			var hq := sim.get_system("hq") as CorkHQ
			if hq and not hq.grade.is_empty() and not fired():
				var delta: float = REVIEW_STANDING.get(hq.grade, 0.0)
				if delta >= 0.0:
					commend(sim, "shift review %s" % hq.grade, delta)
				else:
					penalise(sim, "shift review %s" % hq.grade, -delta)
		"alarm":
			if str(data.get("device", "")) == "uplink":
				_uplink_lost(sim)
			if data.has("robot"):
				var bot := sim.get_system("robot_" + str(data.robot)) as RobotAgent
				if bot and bot.activity.kind == "crashed" and watching:
					penalise(sim, "unit %s crashed" % bot.display_name(), 4.0)


# The uplink just went down: corporate notices the silence.
func _uplink_lost(sim: FacilitySim) -> void:
	uplink_breaks += 1
	_uplink_since = sim.time()
	var hq := sim.get_system("hq") as CorkHQ
	if uplink_breaks >= 2:
		var extra := UPLINK_REPEAT * (uplink_breaks - 1)
		suspicion = clampf(suspicion + extra, 0.0, 100.0)
		trail.append({"t": sim.time(), "what": "repeated loss of the corkHQ uplink (%d times)" % uplink_breaks, "amount": extra})
		if hq:
			hq.post(sim, "Compliance", "warning", "Uplink outage number %d. Outages are not supposed to happen. This one is noted." % uplink_breaks)
	if hq:
		hq.post(sim, "Directorate of Output", "warning", "The uplink to facility C-7 is down. Restore it immediately.")
	var dirs := sim.get_system("directives") as Directives
	if dirs and watching:
		dirs.issue(sim, "uplink", "", 60.0, "Restore the corkHQ uplink (workshop).", 1.0, 10.0)


func sim_save() -> Dictionary:
	return {"standing": standing, "counts": counts.duplicate(), "uplink_breaks": uplink_breaks, "uplink_since": _uplink_since, "blind": blind, "suspicion": suspicion, "strikes": strikes, "trail": trail.duplicate(true),
		"fired_reason": fired_reason, "fired_kind": fired_kind, "watching": watching,
		"audit_acc": _audit_acc, "crisis_acc": _crisis_acc, "coolant_since": _coolant_since, "output_since": _output_since, "warned": _warned.duplicate(),
		"rng_seed": str(rng.seed), "rng_state": str(rng.state)}


func sim_load(d: Dictionary) -> void:
	standing = float(d.get("standing", START_STANDING))
	suspicion = float(d.get("suspicion", 0.0))
	strikes = int(d.get("strikes", 0))
	trail.clear()
	for t in d.get("trail", []):
		trail.append({"t": float(t.t), "what": str(t.what), "amount": float(t.amount)})
	fired_reason = str(d.get("fired_reason", ""))
	fired_kind = str(d.get("fired_kind", ""))
	watching = bool(d.get("watching", true))
	_audit_acc = float(d.get("audit_acc", 0.0))
	_crisis_acc = float(d.get("crisis_acc", 0.0))
	_coolant_since = float(d.get("coolant_since", -1.0))
	_output_since = float(d.get("output_since", -1.0))
	_warned = d.get("warned", {}).duplicate()
	counts = {}
	var c: Dictionary = d.get("counts", {})
	for k in c:
		counts[k] = int(c[k])
	uplink_breaks = int(d.get("uplink_breaks", 0))
	_uplink_since = float(d.get("uplink_since", -1.0))
	blind = int(d.get("blind", 0))
	rng.seed = int(str(d.get("rng_seed", "0")))
	rng.state = int(str(d.get("rng_state", "0")))


func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	return PackedStringArray(["OVERSIGHT  standing %d   suspicion %d   strikes %d   trail %d%s" % [roundi(standing), roundi(suspicion),
		strikes, trail.size(), ("   FIRED: " + fired_reason) if fired() else ""]])

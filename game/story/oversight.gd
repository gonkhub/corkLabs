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
#   catastrophe   the facility fails on your watch: coolant empty for 30
#                 facility minutes, or throughput under 30% for an hour.
#
# Every violation is written to the AUDIT TRAIL, which corporate reads. With
# the maintenance account, "auditctl" can read and purge it (itself a risk).
# Muting corkHQ ("hqctl mute") silences the panel for a while; corporate
# notices at the next audit.
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
const COOLANT_LIMIT := 1800.0
const OUTPUT_CRISIS := 0.3
const OUTPUT_LIMIT := 3600.0

var sim_id := "oversight"
var standing := START_STANDING
var suspicion := 0.0
var strikes := 0
## [{"t", "what", "amount"}]: what corporate can find at an audit.
var trail: Array[Dictionary] = []
## "" while employed; otherwise why they were let go.
var fired_reason := ""
var fired_kind := ""
## corkHQ's panel is silent until this facility time (hqctl mute).
var hq_muted_until := -1.0
var rng := RandomNumberGenerator.new()
## Audits only run while this is true (the Campaign sets it: on duty).
var watching := true

var _audit_acc := 0.0
var _crisis_acc := 0.0
var _coolant_since := -1.0
var _output_since := -1.0
var _warned := {}


func fired() -> bool:
	return not fired_reason.is_empty()


func hq_muted(sim: FacilitySim) -> bool:
	return sim != null and sim.time() < hq_muted_until


## A policy violation: suspicion + a line in the audit trail. With
## `catch_chance`, corporate may notice right now.
func violate(sim: FacilitySim, what: String, amount: float, catch_chance := 0.0) -> void:
	suspicion = clampf(suspicion + amount, 0.0, 100.0)
	trail.append({"t": sim.time(), "what": what, "amount": amount})
	sim.note("oversight", "Violation logged: %s (suspicion %d)" % [what, roundi(suspicion)])
	if catch_chance > 0.0 and not fired() and rng.randf() < catch_chance:
		_caught(sim, what)


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
	fired_kind = kind
	fired_reason = reason
	sim.note("oversight", "DISMISSED (%s): %s" % [kind, reason])
	var hq := sim.get_system("hq") as CorkHQ
	if hq:
		hq.post(sim, "Human Resources", "warning", "NOTICE OF DISMISSAL. %s Your access ends at the close of this session." % reason)
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
	var hq := sim.get_system("hq") as CorkHQ
	if hq_muted(sim) and not _warned.has("mute_%d" % int(hq_muted_until)):
		_warned["mute_%d" % int(hq_muted_until)] = true
		violate(sim, "corkHQ link suspended from the supervisor terminal", 12.0)
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
		hq.post(sim, "Compliance", "warning", "FORMAL WARNING. An audit of your terminal found: %s. This is recorded. There will not be a second warning." % what)


# --- Crises ---------------------------------------------------------------------------

func _check_crisis(sim: FacilitySim) -> void:
	var plant := sim.get_system("plant") as FacilityPlant
	if plant == null:
		return
	_coolant_since = _crisis_timer(sim, plant.coolant <= COOLANT_CRISIS, _coolant_since, COOLANT_LIMIT, "coolant",
		"CRITICAL: the coolant loop is empty. The pod hall is overheating. Restore coolant immediately.",
		"The coolant loop ran dry on your watch and the pod hall overheated.")
	_output_since = _crisis_timer(sim, plant.throughput <= OUTPUT_CRISIS, _output_since, OUTPUT_LIMIT, "output",
		"CRITICAL: facility throughput has collapsed. Restore output within the hour.",
		"Facility output collapsed on your watch and stayed down for an hour.")


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
		"shift_end":
			var hq := sim.get_system("hq") as CorkHQ
			if hq and not hq.grade.is_empty() and not fired():
				var delta: float = REVIEW_STANDING.get(hq.grade, 0.0)
				if delta >= 0.0:
					commend(sim, "shift review %s" % hq.grade, delta)
				else:
					penalise(sim, "shift review %s" % hq.grade, -delta)
		"alarm":
			if data.has("robot"):
				var bot := sim.get_system("robot_" + str(data.robot)) as RobotAgent
				if bot and bot.activity.kind == "crashed" and watching:
					penalise(sim, "unit %s crashed" % bot.display_name(), 4.0)


func sim_save() -> Dictionary:
	return {"standing": standing, "suspicion": suspicion, "strikes": strikes, "trail": trail.duplicate(true),
		"fired_reason": fired_reason, "fired_kind": fired_kind, "hq_muted_until": hq_muted_until, "watching": watching,
		"audit_acc": _audit_acc, "coolant_since": _coolant_since, "output_since": _output_since, "warned": _warned.duplicate(),
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
	hq_muted_until = float(d.get("hq_muted_until", -1.0))
	watching = bool(d.get("watching", true))
	_audit_acc = float(d.get("audit_acc", 0.0))
	_coolant_since = float(d.get("coolant_since", -1.0))
	_output_since = float(d.get("output_since", -1.0))
	_warned = d.get("warned", {}).duplicate()
	rng.seed = int(str(d.get("rng_seed", "0")))
	rng.state = int(str(d.get("rng_state", "0")))


func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	return PackedStringArray(["OVERSIGHT  standing %d   suspicion %d   strikes %d   trail %d%s" % [roundi(standing), roundi(suspicion),
		strikes, trail.size(), ("   FIRED: " + fired_reason) if fired() else ""]])

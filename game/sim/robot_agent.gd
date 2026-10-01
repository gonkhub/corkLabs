# A robot's mind, as a facility system (sim_id "robot_<id>"). This is the
# robot the simulation knows about: where it is on the rail network, its
# needs, what it's doing and why. The 3D robot just shows it (RobotView).
#
# WHERE IT IS
#   A segment of the rail network + an offset along it (FacilityLayout).
#   To go somewhere it plans a route for its own WIDTH: narrow hatches and
#   ducts are closed to wide robots, blocked routes are closed to everyone.
#   If a route closes on the way it re-plans; if there's no way at all it
#   gives up on that job and says so.
#   A STATIONARY robot (Ogre) never moves: it works whatever is within its
#   `reach` (in its own room) and turns down the rest.
#
# POWER  0-1. Drains while it's on, faster moving and working. Recharges on a
#        dock. Below `power_reserve` it drops everything to recharge. At 0 it
#        stalls and limps on emergency cells.
#
# SOFTWARE STABILITY  0-1. The robots believe the work keeps *them* running:
#   idleness makes their software drift, and so do stalling and being
#   overruled. Work and finished jobs restore it. As it falls the robot turns
#   INDEPENDENT (see `independence`):
#     stable    >= 60%  does as it's told, sensible choices
#     drifting  >= 35%  orders count for less, choices get noisy, it wanders
#     unstable  >= 15%  mostly ignores orders; fixates on random places
#     critical  <  15%  critical errors (it CRASHES and is offline for a while,
#                       or GLITCHES and does something senseless), and it may
#                       SABOTAGE a device so there's work it can do
#   A reboot (after a crash, or remote-reboot from the supervisor) restores
#   some stability.
#
# DECIDING (utility scores)
#   Every `think_interval` facility seconds (and whenever something finishes)
#   it scores every option: each job it can reach, recharging, standing by,
#   wandering, and (when unstable) errant options. Highest score wins.
#   A STABLE unit doesn't pick its own work: it only considers jobs that were
#   REQUESTED (WorkBoard: the supervisor asked, or the night autopilot) and
#   the job it was ordered onto, and it always does as it's told. Below
#   "stable" it has a will of its own (`own_will`): every open job is fair
#   game, requested or not, and orders count for less and less.
#   Scores and reasons are kept in `scores` (F1 dev panel, Units app); every
#   change of mind is journaled.
#
# ORDERS (a strong nudge, not a command)
#   give_order() adds `obedience` to the ordered option's score, scaled down
#   by independence. A robot below its power reserve recharges first, won't
#   take work it's hopeless at or can't get to, and an unstable robot may just
#   ignore you. Its answer is spoken (RobotChatter).
#
# WEAR  0-1. Joints wear with work (and a little with travel). Past WEAR_SLOW
#   it moves and works slower; past WEAR_SEIZE it can SEIZE UP: frozen where
#   it stands until another unit gets to it and reboots it by hand ("Manual
#   reboot" job, precise: Tinker's work). A SERVICE at its dock (a job that
#   uses a servo bundle from stock) brings wear back down. Worn units ask for
#   one (UnitRequests).
#
# SPEAKING
#   It tells RobotChatter what just happened ("start_job", "low_power",
#   "critical_error"...); the chatter system decides whether and what it says.
class_name RobotAgent
extends RefCounted

## Stability bands, highest first: [threshold, name].
const STATES := [[0.6, "stable"], [0.35, "drifting"], [0.15, "unstable"], [0.0, "critical"]]
const ORDER_TIMEOUT := 3600.0   # a stand-by order lapses after an hour
## Robots act in steps of this many facility seconds (5 sim ticks).
const STEP := 0.5
const EMERGENCY_CHARGE := 0.0002   # per second, while stalled
const EMERGENCY_RESTART := 0.05    # restarts at this and limps to a dock
## Travel distance (m) at which a job counts as "far" when scoring.
const FAR := 80.0
## Stability lost when it runs out of power.
const STALL_SHOCK := 0.15
## Stability after a reboot (crash recovery or remote reboot) goes up by this.
const REBOOT_RESTORE := 0.3
## Chance per think, at 0% stability, of a critical error (scaled by error_resistance).
const CRITICAL_ERROR_CHANCE := 0.04
## Seconds offline after a crash / a remote reboot.
const CRASH_TIME := Vector2(600.0, 2400.0)
const REBOOT_TIME := 300.0
## Seconds an errant fixation or glitch lasts.
const FIXATE_TIME := Vector2(120.0, 420.0)
const GLITCH_TIME := Vector2(60.0, 240.0)
## Seconds spent at a device sabotaging it.
const SABOTAGE_WORK := 25.0
## Wear gained per second of work / travel (x the trait's wear_rate).
const WEAR_WORK := 0.000018
const WEAR_MOVE := 0.000006
## Wear at which it slows down, and at which it can seize up.
const WEAR_SLOW := 0.4
const WEAR_SEIZE := 0.5
## Seizures per facility hour at full wear (scaled from 0 at WEAR_SEIZE).
const SEIZE_RATE := 1.2
## A service brings wear back down to this.
const WEAR_SERVICED := 0.08
const MANUAL_REBOOT_WORK := 300.0
## Wear between shifts, as a share of on-shift wear.
const NIGHT_WEAR := 0.3
## A seized unit nobody reboots works itself free after this long.
const SELF_FREE := 7200.0
const SERVICE_WORK := 480.0
## An independent robot's whims (its random bias for or against each option)
## hold this long before they change: erratic, but it follows through.
const WHIM_TIME := 600.0
## How much slower idle software drifts between shifts (standby).
const NIGHT_DRIFT := 0.15
## How much slower a stable unit's software drifts while it stands by
## waiting for orders (on duty: that's its job now, but it still frets).
const WAITING_DRIFT := 0.4
## Trust (Knowledge.nudge_trust): how being treated moves it.
const TRUST_SERVICED := 0.5
const TRUST_PER_JOB := 0.02
const TRUST_OVERRULED := -0.1
const TRUST_LEFT_SEIZED := -0.5
## Longest a unit waits on an open link before it gets on with things.
const LINK_MAX := 1800.0
## The overclock package: faster, at a price (wear, and software drift).
const OVERCLOCK_SPEED := 1.3
const OVERCLOCK_WEAR := 1.5
const OVERCLOCK_DRIFT := 1.4
## The night-watch package: the night crew does the chores, and wears for it.
const NIGHT_WATCH_WEAR := 2.0
## A unit that went to charge because it was low stays on the dock until
## it's this far above its reserve (no dithering between dock and job).
const LOW_MARGIN := 0.25
## Independence at which errant fixations start.
const FIXATE_FROM := 0.35

var sim_id: String
var robot_id: String
var traits: RobotTraits

# --- State (saved) ---
## Where it is: a segment of the rail network and meters along it.
var seg := ""
var off := 0.0
var power := 1.0
## Software stability, 0-1.
var stability := 0.8
## Band name for `stability` ("stable", "drifting", "unstable", "critical").
var stability_state := "stable"
## What it's doing: {"kind": "idle"/"work"/"recharge"/"wander"/"fixate"/"sabotage"/
## "glitch"/"crashed"/"rebooting"/"stalled", plus "job", "station", "seg"/"off",
## "until", "device" as the kind needs}
var activity := {"kind": "idle"}
## The standing order: {} or {"kind": "job"/"recharge"/"standby", "job": int, "given": time}
var order := {}
var moving := false
## A story moment asks the 3D robot to perform a clip ("act_hum_pod3"). The
## view plays it if the robot has it (clips are performed in the VR recorder),
## and does nothing if not, so story scripts can name clips before they exist.
## Not saved: it's a one-off cue.
var perform := {"clip": "", "n": 0}
var jobs_done := 0
## Joint wear, 0-1 (see WEAR above).
var wear := 0.2
## The route being ridden: [{"seg", "from", "to"}...] (see FacilityLayout.plan).
var route: Array = []
var _route_goal := ""     # what `route` leads to ("station:bay_2", "wander:...")
var _think_left := 0.0
var _step_left := 0.0
var _whim_seed := 0
var _whim_until := -1.0

## The last evaluation, best first: [{"key", "label", "score", "why"}]
var scores: Array[Dictionary] = []


func _init(id: String, robot_traits: RobotTraits = null, start_seg := "", start_off := 0.0) -> void:
	robot_id = id
	sim_id = "robot_" + id
	traits = robot_traits if robot_traits else RobotTraits.load_for(id)
	seg = start_seg
	off = start_off


func request_clip(clip: String, extra := {}) -> void:
	perform = {"clip": clip, "n": int(perform.n) + 1}
	perform.merge(extra, true)


## The supervisor opened the unit link: it stops where it is and faces the
## camera (RobotView) until the link closes (or LINK_MAX passes).
func link_open(sim: FacilitySim) -> void:
	if offline():
		return
	var board := _board(sim)
	if activity.kind == "work" and board:
		board.release(int(activity.job), sim_id)   # it puts the job down (progress kept)
	route = []
	_route_goal = ""
	activity = {"kind": "link", "until": sim.time() + LINK_MAX}


func link_close(sim: FacilitySim) -> void:
	if activity.kind == "link":
		activity = {"kind": "idle"}
		_think_left = 0.0


func display_name() -> String:
	return traits.display_name


## The room it's in right now.
func room(sim: FacilitySim) -> String:
	return _layout(sim).room_at(seg, off)


func world_pos(sim: FacilitySim) -> Vector3:
	return _layout(sim).world_pos(seg, off)


## 0 = does as it's told ... 1 = entirely its own robot. Grows as stability
## falls below 70%, scaled by the robot's `independence` trait.
func independence() -> float:
	return clampf((0.7 - stability) / 0.6, 0.0, 1.0) * traits.independence


## Below "stable" it chooses its own work and starts to ignore you.
func own_will() -> bool:
	return stability < STATES[0][0]


## How far it would travel to a station (m), or -1 if it can't get there.
func route_length(sim: FacilitySim, station_id: String) -> float:
	var layout := _layout(sim)
	var r := _reach_station(layout, _field(layout), station_id)
	return -1.0 if r.is_empty() else float(r.length)


## Where it is with a job it was sent on (Facility errands): {"phase":
## "travel" / "work" / "other", "left": facility seconds that phase still needs}.
func errand_estimate(sim: FacilitySim, job_id: int) -> Dictionary:
	var board := _board(sim)
	var j: Dictionary = board.get_job(job_id) if board else {}
	if j.is_empty() or activity.get("kind", "") != "work" or int(activity.get("job", -1)) != job_id:
		return {"phase": "other", "left": 600.0}
	var st := _layout(sim).station(str(j.station))
	var there: bool = not st.is_empty() and seg == st.segment and absf(off - float(st.offset)) < 0.01
	if not there and not traits.stationary:
		return {"phase": "travel", "left": maxf(route_length(sim, str(j.station)), 0.0) / maxf(traits.rail_speed * wear_factor() * 0.8, 0.05)}
	var speed := traits.skill(str(j.get("skill", "general"))) * traits.work_speed * wear_factor()
	return {"phase": "work", "left": maxf(float(j.work) - float(j.progress), 0.0) / maxf(speed, 0.01)}


## Out of action (crashed, rebooting, stalled, seized): it can't think or take orders.
func offline() -> bool:
	return activity.kind in ["crashed", "rebooting", "stalled", "seized", "broken"]


## Something's broken inside it (Ogre's core): offline until the part is
## replaced (FacilityPlant: the core chain). No reboot fixes it.
func break_down(sim: FacilitySim, why: String) -> void:
	var board := _board(sim)
	if activity.kind == "work" and board:
		board.release(int(activity.job), sim_id)
	route = []
	order = {}
	activity = {"kind": "broken", "why": why}
	sim.note(robot_id, "%s is OFFLINE: %s" % [display_name(), why])


## The part's in: back online.
func repair(sim: FacilitySim) -> void:
	if activity.kind != "broken":
		return
	activity = {"kind": "idle"}
	_think_left = 0.0
	sim.note(robot_id, "%s is back online" % display_name())
	_say(sim, "restarted", {})


## How much wear slows it: 1 = not at all ... 0.5 = half speed at full wear.
func wear_factor() -> float:
	return 1.0 - 0.5 * clampf((wear - WEAR_SLOW) / (1.0 - WEAR_SLOW), 0.0, 1.0)


# --- System ---------------------------------------------------------------------

func sim_start(sim: FacilitySim) -> void:
	wear = sim.rng.randf_range(0.15, 0.35) * traits.wear_rate
	sim.note(robot_id, "%s online in %s (power %d%%, stability %d%%)" % [display_name(), _room_name(sim), _pct(power), _pct(stability)])
	think(sim)   # decide straight away, so a new facility isn't all "standing by"


func sim_tick(sim: FacilitySim, dt: float) -> void:
	_step_left += dt
	if _step_left < STEP - 0.001:
		return
	var step := _step_left
	_step_left = 0.0
	_think_left -= step
	if _think_left <= 0.0:
		_update_state(sim)
		_maybe_critical_error(sim)
		think(sim)
	_maybe_seize(sim, step)
	_perform(sim, step)


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	match event_name:
		"alarm", "job_requested":
			_think_left = 0.0   # something broke: reconsider now
		"route_changed":
			route = []           # re-plan on the next step
			_route_goal = ""
			_think_left = 0.0
		"job_released":
			# Taken off the queue: put it down.
			var id := int(data.get("job", -1))
			if order.get("kind", "") == "job" and int(order.get("job", -1)) == id:
				order = {}
			if activity.get("kind", "") == "work" and int(activity.get("job", -1)) == id:
				activity = {"kind": "idle"}
				route = []
				_think_left = 0.0
		"job_done", "job_cancelled":
			var src := str(data.get("source", ""))
			if event_name == "job_done" and src == "unit:" + robot_id and activity.kind == "seized":
				wear = maxf(wear - 0.05, 0.0)
				activity = {"kind": "idle"}
				_think_left = 0.0
				sim.note(robot_id, "%s is moving again (rebooted by hand by %s)" % [display_name(), str(data.get("by", "")).trim_prefix("robot_").capitalize()])
				_say(sim, "restarted", {})
			elif event_name == "job_done" and src == "service:" + robot_id:
				wear = WEAR_SERVICED
				Knowledge.nudge_trust(sim, robot_id, TRUST_SERVICED, "serviced")
				sim.note(robot_id, "%s serviced: joints like new (wear %d%%)" % [display_name(), _pct(wear)])
			var id := int(data.get("job", -1))
			if order.get("kind", "") == "job" and int(order.get("job", -1)) == id:
				order = {}
			if activity.get("kind", "") == "work" and int(activity.get("job", -1)) == id:
				activity = {"kind": "idle"}
				_think_left = 0.0


# --- Deciding ---------------------------------------------------------------------

## Scores every option, best first. Doesn't change anything (except that an
## erratic robot's random jitter uses the facility's random numbers).
func evaluate(sim: FacilitySim) -> Array[Dictionary]:
	var layout := _layout(sim)
	var board := _board(sim)
	var out: Array[Dictionary] = []
	var energy := clampf((power - traits.power_reserve) / 0.2, 0.0, 1.0)
	var hunger := 1.0 + (1.0 - stability) * 0.5
	var ind := independence()
	var own := own_will()
	var listen := traits.obedience * (1.0 - ind)   # what an order is worth right now
	if not own:
		listen = maxf(listen, 1.2)   # stable: it does as it's told
	var current := activity_key()
	var f := _field(layout)   # travel costs to everywhere, once

	# Work: every open job it can get to.
	if board:
		for j in board.open_jobs():
			if j.status == "claimed" and j.claimed_by != sim_id:
				continue
			if not str(j.get("only", "")).is_empty() and str(j.only) != sim_id:
				continue   # someone else's service
			if not (j.get("units", []) as Array).is_empty() and not robot_id in j.units:
				continue   # not its kind of work
			if str(j.get("not_by", "")) == sim_id:
				continue   # it broke this one
			var requested: bool = j.get("requested", false)
			var mine: bool = activity.get("kind", "") == "work" and int(activity.get("job", -1)) == int(j.id)
			if not own and not requested and _ordered_job() != int(j.id) and not mine:
				continue   # stable: nobody asked for it (but it finishes what it started)
			if not own and requested and not mine and _ordered_job() != int(j.id) and str(j.claimed_by).is_empty():
				var better := Dispatch.best_unit(sim, j)
				if better != null and better != self:
					continue   # a queued job: leave it to the unit that's best for it
			if traits.stationary and j.get("rail_only", false):
				continue   # something to carry somewhere: not a job for a crane bolted to the ceiling
			var r := _reach_station(layout, f, j.station)
			if r.is_empty():
				continue   # can't get there (too narrow, or blocked)
			var fit := traits.skill(j.skill)
			var prio: float = [0.35, 0.55, 0.75, 0.95][int(j.priority)]
			var dist: float = r.length
			var near := 1.0 - traits.distance_aversion * 0.5 * clampf(dist / FAR, 0.0, 1.0)
			var s := prio * (0.4 + 0.6 * fit) * near * hunger * energy
			var why := "%s priority, %s skill %d%%, %.0f m away" % [WorkBoard.PRIORITY_NAMES[int(j.priority)], j.skill, _pct(fit), dist]
			if requested and not own:
				s += 0.3 * fit * energy   # asked for: worth doing (if it's any good at it)
				why += ", requested"
			elif not requested:
				why += ", its own idea"
			if energy < 1.0:
				why += ", power %d%%" % _pct(power)
			if _ordered_job() == int(j.id):
				if fit < traits.refuse_below_skill:
					why += ", ordered but not built for it"
				elif energy > 0.0:
					s += listen
					why += ", ORDERED" + (" (half-listening)" if ind > 0.3 else "")
			out.append({"key": "work:%d" % j.id, "label": "work #%d %s" % [j.id, j.title], "score": s, "why": why})

	# Asked to have an "accident" with a device (a conversation, not the board).
	if order.get("kind", "") == "accident":
		var plant := _plant(sim)
		var dev: Dictionary = plant.device(str(order.device)) if plant else {}
		if not dev.is_empty() and not dev.fault and not _reach_station(layout, f, dev.station).is_empty():
			out.append({"key": "accident:" + str(order.device), "label": "head for " + str(dev.name), "score": 0.5 + listen,
				"why": "asked to, quietly"})
		else:
			order = {}

	# Recharge at the nearest dock it can get to.
	var dock := _nearest_dock(sim, f)
	if not dock.is_empty():
		var s := pow(1.0 - power, 2.0) * 1.1
		var why := "power %d%%" % _pct(power)
		if power < traits.power_reserve:
			s = 1.6
			why += ", below reserve"
		elif current == "recharge" and power < traits.power_reserve + LOW_MARGIN:
			s = 1.6   # it came in low: it charges to a safe margin before anything else
			why += ", charging to a safe %d%%" % _pct(traits.power_reserve + LOW_MARGIN)
		elif current == "recharge" and power < traits.charge_until:
			s = maxf(s, 0.9)
			why += ", charging to %d%%" % _pct(traits.charge_until)
		if order.get("kind", "") == "recharge":
			s += listen
			why += ", ORDERED"
		out.append({"key": "recharge", "label": "recharge at " + str(dock.name), "score": s, "why": why})

	# Stand by where it is. Stable robots are happy to; unstable ones aren't.
	var idle := 0.12 + 0.2 * stability
	var idle_why := "stability %d%% (%s)" % [_pct(stability), stability_state]
	if order.get("kind", "") == "standby":
		idle += listen * stability
		idle_why += ", ORDERED to stand by"
	out.append({"key": "idle", "label": "stand by", "score": idle, "why": idle_why})

	# Errant behaviour: grows as stability falls.
	var drift := clampf(traits.stability_decay / 0.0004, 0.3, 2.0)
	var wander := drift * 0.25 * pow(1.0 - stability, 1.5) * (0.3 + 0.7 * energy)
	out.append({"key": "wander", "label": "sweep the crane about" if traits.stationary else "wander the rails", "score": wander, "why": "drifting (stability %d%%)" % _pct(stability)})
	if ind > FIXATE_FROM:
		out.append({"key": "fixate", "label": "fixate on something", "score": ind * 0.45 * (0.5 + 0.5 * energy),
			"why": "unstable: an errant fixation (independence %d%%)" % _pct(ind)})
	if stability < 0.25 and traits.sabotage_tendency > 0.0 and energy > 0.0:
		var target := _sabotage_target(sim, f)
		if not target.is_empty():
			out.append({"key": "sabotage:" + str(target.id), "label": "tamper with " + str(target.name),
				"score": traits.sabotage_tendency * (0.25 - stability) * 4.0 * 0.95,
				"why": "critical: breaking %s would make work it can do" % target.name})

	# Stick with a task already started (not with doing nothing).
	for o in out:
		if o.key == current and current != "idle":
			o.score += traits.commitment
	# Independence makes its choices erratic: a whim for or against each option.
	if ind > 0.0:
		if sim.time() >= _whim_until:
			_whim_seed = sim.rng.randi()
			_whim_until = sim.time() + WHIM_TIME
		for o in out:
			var whim := float(hash(str(o.key) + ":" + str(_whim_seed)) % 2001) / 1000.0 - 1.0   # -1..1, steady per option
			o.score += whim * 0.35 * ind
	out.sort_custom(func(a, b): return a.score > b.score or (a.score == b.score and a.key < b.key))
	return out


## Re-scores and switches to the best option if it isn't already doing it.
func think(sim: FacilitySim) -> void:
	_think_left = traits.think_interval
	if offline() or activity.kind == "glitch" or activity.kind == "link":
		return
	scores = evaluate(sim)
	if scores.is_empty():
		return
	# Its job just became unreachable (a route closed): say so and let it go.
	if activity.kind == "work" and not scores.any(func(o): return o.key == activity_key()):
		var j := _board(sim).get_job(int(activity.job)) if _board(sim) else {}
		if not j.is_empty() and (j.status == "open" or j.status == "claimed"):
			_give_up(sim, "station:" + str(activity.station))
	var best: Dictionary = scores[0]
	if best.key == activity_key() or (best.key == "fixate" and activity.kind == "fixate"):
		return
	_switch_to(sim, best)
	var line := "%s: %s (%.2f: %s)" % [display_name(), best.label, best.score, best.why]
	if scores.size() > 1:
		line += "; next best %s (%.2f)" % [scores[1].label, scores[1].score]
	sim.note(robot_id, line)


func activity_key() -> String:
	match activity.get("kind", "idle"):
		"work": return "work:%d" % int(activity.job)
		"sabotage": return "sabotage:" + str(activity.device)
		"accident": return "accident:" + str(activity.device)
		"idle": return "idle"
	return str(activity.kind)


func _switch_to(sim: FacilitySim, option: Dictionary) -> void:
	var board := _board(sim)
	if activity.kind == "work" and board:
		board.release(int(activity.job), sim_id)
	route = []
	_route_goal = ""
	var key: String = option.key
	if key.begins_with("work:"):
		var id := int(key.trim_prefix("work:"))
		board.claim(id, sim_id)
		var j := board.get_job(id)
		activity = {"kind": "work", "job": id, "station": j.station}
		_say(sim, "start_job", {"job": j.title, "station": _layout(sim).station(j.station).get("name", "")})
	elif key == "recharge":
		activity = {"kind": "recharge", "station": _nearest_dock(sim).id}
		_say(sim, "recharge", {})
	elif key == "wander":
		activity = _wander_target(sim)
		_say(sim, "wander", {})
	elif key == "fixate":
		var ids := _layout(sim).stations_of()
		if traits.stationary:
			ids = ids.filter(func(i): return _crane_distance(_layout(sim), i) <= traits.reach)
		var st: String = ids[sim.rng.randi() % ids.size()]
		activity = {"kind": "fixate", "station": st, "until": -1.0}
		_say(sim, "fixate", {"station": _layout(sim).station(st).name})
	elif key.begins_with("accident:"):
		var plant := _plant(sim)
		var dev: String = key.trim_prefix("accident:")
		activity = {"kind": "accident", "device": dev, "station": plant.device(dev).station, "left": SABOTAGE_WORK}
	elif key.begins_with("sabotage:"):
		var plant := _plant(sim)
		var dev: String = key.trim_prefix("sabotage:")
		activity = {"kind": "sabotage", "device": dev, "station": plant.device(dev).station, "left": SABOTAGE_WORK}
		sim.note("sabotage", "%s is heading for %s, intending to break it" % [display_name(), plant.device(dev).name])
		_say(sim, "sabotage", {"device": plant.device(dev).name})
	else:
		activity = {"kind": "idle"}


# A device it could break to make a job it's good at (and can reach).
func _sabotage_target(sim: FacilitySim, f: Dictionary) -> Dictionary:
	var plant := _plant(sim)
	if plant == null:
		return {}
	var best := {}
	var best_fit := 0.0
	for id in plant.device_ids():
		var d := plant.device(id)
		if d.fault or int(d.job) >= 0 or not FacilityPlant.KINDS[d.kind].has("job"):
			continue
		var fit := traits.skill(FacilityPlant.KINDS[d.kind].skill)
		if fit > best_fit and not _reach_station(_layout(sim), f, d.station).is_empty():
			best_fit = fit
			best = d
	return best


# --- Critical errors -------------------------------------------------------------------

func _maybe_critical_error(sim: FacilitySim) -> void:
	if stability >= 0.15 or offline() or activity.kind == "glitch":
		return
	var chance := CRITICAL_ERROR_CHANCE * (0.15 - stability) / 0.15 * (1.0 - traits.error_resistance)
	if sim.rng.randf() >= chance:
		return
	var board := _board(sim)
	if activity.kind == "work" and board:
		board.release(int(activity.job), sim_id)
	route = []
	_route_goal = ""
	if sim.rng.randf() < 0.5:
		var until := sim.time() + sim.rng.randf_range(CRASH_TIME.x, CRASH_TIME.y)
		activity = {"kind": "crashed", "until": until}
		sim.note("alarm", "%s CRITICAL ERROR: software crash. Offline until %s" % [display_name(), FacilitySim.format_clock(until)])
		sim.schedule(sim.time(), "alarm", {"robot": robot_id})
		_say(sim, "critical_error", {})
	else:
		var target := _wander_target(sim)
		activity = {"kind": "glitch", "seg": target.seg, "off": target.off,
			"until": sim.time() + sim.rng.randf_range(GLITCH_TIME.x, GLITCH_TIME.y)}
		sim.note(robot_id, "%s is glitching: behaviour makes no sense" % display_name())
		_say(sim, "glitch", {})


# --- Wear -------------------------------------------------------------------------------

# Between shifts the units work gently (standby, no pushing): less wear.
func _wear_scale(sim: FacilitySim) -> float:
	var camp := sim.get_system("campaign") as Campaign
	var s := 1.0
	if camp and not camp.on_duty():
		s = NIGHT_WEAR * (NIGHT_WATCH_WEAR if _has(sim, "night-watch") else 1.0)   # the night crew does the rounds
	return s * (OVERCLOCK_WEAR if _has(sim, "overclock") else 1.0)


## Overclocked units move and work this much faster.
func speed_boost(sim: FacilitySim) -> float:
	return OVERCLOCK_SPEED if _has(sim, "overclock") else 1.0


func _has(sim: FacilitySim, package_id: String) -> bool:
	var sw := sim.get_system("software") as SoftwareLibrary
	return sw != null and sw.installed(package_id)


func _maybe_seize(sim: FacilitySim, dt: float) -> void:
	if wear < WEAR_SEIZE or offline():
		return
	var camp := sim.get_system("campaign") as Campaign
	if camp and not camp.on_duty():
		return   # overnight standby: nothing moves hard enough to seize
	var rate := SEIZE_RATE * (wear - WEAR_SEIZE) / (1.0 - WEAR_SEIZE)
	if sim.rng.randf() >= rate * dt / 3600.0:
		return
	seize(sim)


## Freezes up: offline until another unit reboots it by hand.
func seize(sim: FacilitySim) -> void:
	var board := _board(sim)
	if activity.kind == "work" and board:
		board.release(int(activity.job), sim_id)
	route = []
	_route_goal = ""
	activity = {"kind": "seized", "until": sim.time() + SELF_FREE}
	var where := _nearest_station(sim)
	sim.note("alarm", "%s SEIZED UP in %s (wear %d%%): needs a manual reboot" % [display_name(), _room_name(sim), _pct(wear)])
	if board:
		board.post(sim, "Manual reboot: %s" % display_name(), "precise", where, MANUAL_REBOOT_WORK, 3, "unit:" + robot_id)
	sim.schedule(sim.time(), "alarm", {"robot": robot_id})
	_say(sim, "seized", {})


## Books a service at its dock (a job only it takes; uses a servo bundle).
## Returns the job id, or -1 if one's already booked.
func book_service(sim: FacilitySim) -> int:
	var board := _board(sim)
	if board == null:
		return -1
	for j in board.jobs:
		if str(j.source) == "service:" + robot_id and WorkBoard.active(j):
			return -1
	var where := str(_nearest_dock(sim).get("id", "")) if not traits.stationary else _nearest_station(sim)
	if where.is_empty():
		where = _nearest_station(sim)
	var id := board.post(sim, "Service %s" % display_name(), "precise", where, SERVICE_WORK, 1, "service:" + robot_id)
	var j := board.get_job(id)
	j.part = "servo_bundle"
	if not board.request(sim, id).is_empty():
		board.cancel(sim, id, "no servo bundles in stock")
		return -2
	return id


# The nearest station a rail unit can get to, in its room if possible (where a
# seized unit gets rebooted from).
func _nearest_station(sim: FacilitySim) -> String:
	var layout := _layout(sim)
	var me := world_pos(sim)
	var room_id := room(sim)
	var best := ""
	var best_d := INF
	for id in layout.stations_of():
		var st := layout.station(id)
		if layout.is_pad(st.segment):
			continue
		var d := layout.station_world_pos(id).distance_to(me)
		if layout.room_at(st.segment, st.offset) != room_id:
			d += 1000.0
		if d < best_d:
			best_d = d
			best = id
	return best


## Remote reboot (supervisor): offline for REBOOT_TIME, then stability up.
func reboot(sim: FacilitySim) -> void:
	if activity.kind == "broken":
		return   # a dead part isn't a software problem
	var board := _board(sim)
	if activity.kind == "work" and board:
		board.release(int(activity.job), sim_id)
	if activity.kind == "seized" and board:
		# Rebooted remotely: nobody needs to come and do it by hand.
		for j in board.open_jobs():
			if str(j.source) == "unit:" + robot_id:
				board.cancel(sim, int(j.id), "rebooted remotely")
		wear = maxf(wear - 0.05, 0.0)
	route = []
	order = {}
	activity = {"kind": "rebooting", "until": sim.time() + REBOOT_TIME}
	sim.note(robot_id, "%s is rebooting (remote)" % display_name())
	_say(sim, "rebooting", {})


func _finish_reboot(sim: FacilitySim) -> void:
	stability = minf(stability + REBOOT_RESTORE, 1.0)
	sim.note(robot_id, "%s back online after reboot (stability %d%%)" % [display_name(), _pct(stability)])
	_say(sim, "rebooted", {})
	activity = {"kind": "idle"}
	_update_state(sim)
	_think_left = 0.0


# --- Orders ---------------------------------------------------------------------------

## The supervisor tells this robot to do something. kind: "job" (with job_id),
## "recharge" or "standby"; "cancel" clears the standing order.
## Returns {"ok": bool, "reply": String}; the robot also says the reply.
func give_order(sim: FacilitySim, kind: String, job_id := -1, device := "") -> Dictionary:
	if offline():
		return {"ok": false, "reply": "(no response: %s is %s)" % [display_name(), activity.kind]}
	if kind == "cancel":
		order = {}
		return _reply(sim, true, "Understood. Back to my own judgement.")
	if kind == "accident":
		# Not an order the board knows about: it just goes and has its accident.
		order = {"kind": "accident", "device": device, "given": sim.time()}
		_think_left = 0.0
		think(sim)
		return {"ok": activity.get("kind", "") == "accident", "reply": ""}
	if kind == "job":
		var board := _board(sim)
		var j: Dictionary = board.get_job(job_id) if board else {}
		if j.is_empty() or not (j.status == "open" or j.status == "claimed"):
			return _reply(sim, false, "There's no open job #%d." % job_id)
		var st := _layout(sim).station(j.station)
		var why := why_cant_reach(sim, j.station)
		if not why.is_empty():
			return _reply(sim, false, "I can't get to %s: %s." % [st.get("name", j.station), why])
		if j.status == "claimed" and j.claimed_by != sim_id:
			return _reply(sim, false, "%s is already on job #%d." % [str(j.claimed_by).trim_prefix("robot_").capitalize(), job_id])
		if not (j.get("units", []) as Array).is_empty() and not robot_id in j.units:
			return _reply(sim, false, "No. '%s' is %s's work." % [j.title, " or ".join(j.units.map(func(u): return str(u).capitalize()))])
		if traits.skill(j.skill) < traits.refuse_below_skill:
			return _reply(sim, false, "No. '%s' is %s work; I'm not built for it." % [j.title, j.skill])
	var before := evaluate(sim)   # what it wanted before the order (not the cached scores: those aren't saved)
	var wanted_before: String = before[0].key if not before.is_empty() else ""
	order = {"kind": kind, "job": job_id, "given": sim.time()}
	scores = evaluate(sim)
	var want: String = ("work:%d" % job_id) if kind == "job" else ("recharge" if kind == "recharge" else "idle")
	var ok: bool = scores[0].key == want
	var reply := "On it."
	if not ok:
		if independence() > 0.4:
			reply = "No. I have my own work."
			_say(sim, "order_ignored", {})
		elif power < traits.power_reserve or scores[0].key == "recharge":
			reply = "Acknowledged. Recharging first, power at %d%%." % _pct(power)
		elif kind == "standby":
			reply = "I... will try. Standing still feels wrong right now."
		else:
			reply = "Acknowledged. Doing %s first." % scores[0].label
	elif wanted_before != "" and wanted_before != want:
		# Overruled: it complies, but it wears on its software.
		stability = maxf(stability - traits.order_stress, 0.0)
		Knowledge.nudge_trust(sim, robot_id, TRUST_OVERRULED, "overruled")
	var result := _reply(sim, ok, reply)
	think(sim)
	return result


## "" if it can get to the station, else why not ("too narrow", "blocked: ...").
func why_cant_reach(sim: FacilitySim, station_id: String) -> String:
	var layout := _layout(sim)
	var st := layout.station(station_id)
	if st.is_empty():
		return "there's no such place"
	if traits.stationary:
		if _crane_distance(layout, station_id) <= traits.reach:
			return ""
		return "it's out of my reach, and I don't leave the %s" % str(layout.rooms.get(layout.room_at(seg, off), {}).get("name", "room")).to_lower()
	if not layout.plan_to_station(seg, off, station_id, traits.width).is_empty():
		return ""
	# Would it get there if nothing were blocked? Then something's blocked.
	var open := layout.plan(seg, off, st.segment, st.offset, traits.width, true)
	if not open.is_empty():
		for leg in open.legs:
			if layout.segment(leg.seg).blocked:
				return "%s is blocked (%s)" % [layout.segment(leg.seg).name, layout.segment(leg.seg).block_reason]
		return "the way is blocked"
	return "every way in is too narrow for me"


func _ordered_job() -> int:
	return int(order.get("job", -1)) if order.get("kind", "") == "job" else -1


func _reply(sim: FacilitySim, ok: bool, text: String) -> Dictionary:
	sim.note(robot_id, "%s answers: \"%s\"" % [display_name(), text])
	_say(sim, "order_reply", {"text": text, "ok": ok})
	return {"ok": ok, "reply": text}


func _say(sim: FacilitySim, trigger: String, data: Dictionary) -> void:
	var chatter := sim.get_system("chatter") as RobotChatter
	if chatter:
		chatter.trigger(sim, self, trigger, data)


# --- Doing ------------------------------------------------------------------------------

func _perform(sim: FacilitySim, dt: float) -> void:
	if activity.kind == "broken":
		return   # dead: no power drawn, nothing done, until it's repaired
	var layout := _layout(sim)
	_use_power(sim, traits.drain_idle * dt)
	moving = false
	match activity.kind:
		"stalled":
			power = minf(power + EMERGENCY_CHARGE * dt, 1.0)
			if power >= EMERGENCY_RESTART:
				sim.note(robot_id, "%s restarts on emergency power (%d%%)" % [display_name(), _pct(power)])
				_say(sim, "restarted", {})
				activity = {"kind": "idle"}
				_think_left = 0.0
			return
		"crashed", "rebooting":
			if sim.time() >= float(activity.until):
				_finish_reboot(sim)
			return
		"broken":
			return   # nothing until it's repaired
		"link":
			if sim.time() >= float(activity.get("until", 0.0)):
				link_close(sim)
			return
		"seized":
			# Frozen until someone reboots it by hand, or (slowly) it works itself free.
			if sim.time() >= float(activity.get("until", INF)):
				var board := _board(sim)
				if board:
					for j in board.jobs:
						if str(j.source) == "unit:" + robot_id and WorkBoard.active(j):
							board.cancel(sim, int(j.id), "it worked itself free")
				activity = {"kind": "idle"}
				_think_left = 0.0
				sim.note(robot_id, "%s worked itself free after %d minutes seized" % [display_name(), roundi(SELF_FREE / 60.0)])
				Knowledge.nudge_trust(sim, robot_id, TRUST_LEFT_SEIZED, "left seized")
				_say(sim, "restarted", {})
			return
		"glitch":
			stability = maxf(stability - _decay(sim) * 0.5 * dt, 0.0)
			var arrived := _travel(sim, "glitch:%s:%.2f" % [activity.seg, float(activity.off)], str(activity.seg), float(activity.off), dt)
			if activity.kind != "glitch":
				return   # it gave up on the way (no route) or ran out of power
			if sim.time() >= float(activity.until):
				sim.note(robot_id, "%s stops glitching" % display_name())
				activity = {"kind": "idle"}
				_think_left = 0.0
			elif arrived:
				var t := _wander_target(sim)
				activity.seg = t.seg
				activity.off = t.off
		"idle":
			stability = maxf(stability - _decay(sim) * dt, 0.0)
			if order.get("kind", "") == "standby" and sim.time() - float(order.given) > ORDER_TIMEOUT:
				order = {}
				sim.note(robot_id, "%s's stand-by order lapsed" % display_name())
				_think_left = 0.0
		"wander":
			stability = maxf(stability - _decay(sim) * 0.5 * dt, 0.0)
			if _travel(sim, "wander:%s:%.2f" % [activity.seg, float(activity.off)], str(activity.seg), float(activity.off), dt):
				activity = _wander_target(sim)
		"fixate":
			stability = maxf(stability - _decay(sim) * 0.7 * dt, 0.0)
			var st := layout.station(activity.station)
			if _travel(sim, "station:" + str(activity.station), st.segment, st.offset, dt):
				if float(activity.until) < 0.0:
					activity.until = sim.time() + sim.rng.randf_range(FIXATE_TIME.x, FIXATE_TIME.y)
				elif sim.time() >= float(activity.until):
					activity = {"kind": "idle"}
					_think_left = 0.0
		"accident":
			var st := layout.station(activity.station)
			if _travel(sim, "station:" + str(activity.station), st.segment, st.offset, dt):
				activity.left = float(activity.left) - dt
				if float(activity.left) <= 0.0:
					var plant := _plant(sim)
					if plant:
						plant.accident(sim, str(activity.device), self)
					order = {}
					activity = {"kind": "idle"}
					_think_left = 0.0
		"sabotage":
			var st := layout.station(activity.station)
			if _travel(sim, "station:" + str(activity.station), st.segment, st.offset, dt):
				activity.left = float(activity.left) - dt
				if float(activity.left) <= 0.0:
					var plant := _plant(sim)
					if plant:
						plant.sabotage(sim, str(activity.device), self)
					stability = minf(stability + 0.05, 1.0)   # it did *something*
					activity = {"kind": "idle"}
					_think_left = 0.0
		"work":
			var st := layout.station(activity.station)
			if _travel(sim, "station:" + str(activity.station), st.segment, st.offset, dt):
				var board := _board(sim)
				_use_power(sim, traits.drain_work * dt)
				if activity.kind != "work":
					return   # ran out of power on the job
				stability = minf(stability + traits.stability_from_work * dt, 1.0)
				var j := board.get_job(int(activity.job))
				wear = minf(wear + WEAR_WORK * traits.wear_rate * _wear_scale(sim) * dt, 1.0)
				var amount: float = traits.skill(j.get("skill", "general")) * traits.work_speed * wear_factor() * speed_boost(sim) * dt
				if j.get("status", "") != "claimed" or j.get("claimed_by", "") != sim_id:
					activity = {"kind": "idle"}   # stopped under it (waiting for a part, cancelled)
					_think_left = 0.0
				elif board.add_progress(sim, int(activity.job), sim_id, amount):
					jobs_done += 1
					Knowledge.nudge_trust(sim, robot_id, TRUST_PER_JOB, "kept working")
					if j.get("hot", false):
						wear = minf(wear + 0.15, 1.0)   # clamped live: it cost its joints
					stability = minf(stability + traits.stability_per_job, 1.0)
					if _ordered_job() == int(activity.job):
						order = {}
					_say(sim, "job_done", {"job": j.get("title", "")})
					activity = {"kind": "idle"}
					_think_left = 0.0
		"recharge":
			var st := layout.station(activity.station)
			if _travel(sim, "station:" + str(activity.station), st.segment, st.offset, dt):
				power = minf(power + traits.charge_rate * _charge_factor(sim) * dt, 1.0)
				if power >= traits.charge_until:
					if order.get("kind", "") == "recharge":
						order = {}
					sim.note(robot_id, "%s charged to %d%%" % [display_name(), _pct(power)])
					_say(sim, "charged", {})
					activity = {"kind": "idle"}
					_think_left = 0.0


# Rides the network toward (to_seg, to_off). Plans (or re-plans) the route as
# needed. Returns true once there. If there's no way through, it gives up:
# says so, drops the job, and rethinks.
func _travel(sim: FacilitySim, goal: String, to_seg: String, to_off: float, dt: float) -> bool:
	if seg == to_seg and absf(off - to_off) < 0.01:
		return true
	var layout := _layout(sim)
	if traits.stationary:
		# It never moves: the place is either within reach (it's "there") or not.
		var p := layout.world_pos(to_seg, to_off)
		var me := layout.world_pos(seg, off)
		if Vector2(p.x - me.x, p.z - me.z).length() <= traits.reach and layout.room_at(to_seg, to_off) == layout.room_at(seg, off):
			return true
		_give_up(sim, goal)
		return false
	if route.is_empty() or _route_goal != goal:
		var r := layout.plan(seg, off, to_seg, to_off, traits.width)
		if r.is_empty() and layout.world_pos(seg, off).distance_to(layout.world_pos(to_seg, to_off)) < 0.05:
			seg = to_seg   # already there, just on the neighbouring segment
			off = to_off
			return true
		if r.is_empty():
			_give_up(sim, goal)
			return false
		route = r.legs.duplicate(true)
		_route_goal = goal
	var budget := traits.rail_speed * wear_factor() * speed_boost(sim) * (_plant_ref.rail_factor() if _plant_ref else 1.0) * dt   # meters at speed 1 (grime slows the rails)
	wear = minf(wear + WEAR_MOVE * traits.wear_rate * _wear_scale(sim) * dt, 1.0)
	while budget > 0.0001 and not route.is_empty():
		var leg: Dictionary = route[0]
		if leg.seg != seg:
			seg = leg.seg
			off = float(leg.from)
		var speed: float = layout.segment(seg).speed
		var remaining := absf(float(leg.to) - off)
		var step := minf(budget * speed, remaining)
		off += signf(float(leg.to) - off) * step
		budget -= step / speed
		moving = true
		if absf(float(leg.to) - off) < 0.001:
			off = float(leg.to)
			route.pop_front()
	_use_power(sim, traits.drain_move * dt)
	return seg == to_seg and absf(off - to_off) < 0.01


func _give_up(sim: FacilitySim, goal: String) -> void:
	var where := goal.trim_prefix("station:")
	var why := why_cant_reach(sim, where) if goal.begins_with("station:") else "no way through"
	sim.note(robot_id, "%s can't get to %s: %s" % [display_name(), _layout(sim).station(where).get("name", where), why])
	_say(sim, "route_blocked", {"place": _layout(sim).station(where).get("name", where), "why": why})
	if activity.kind == "work":
		var board := _board(sim)
		if board:
			board.release(int(activity.job), sim_id)
	activity = {"kind": "idle"}
	route = []
	_route_goal = ""
	_think_left = 0.0


func _use_power(sim: FacilitySim, amount: float) -> void:
	var was := power
	power = maxf(power - amount, 0.0)
	if was >= traits.power_reserve and power < traits.power_reserve:
		sim.note(robot_id, "%s power low (%d%%)" % [display_name(), _pct(power)])
		_say(sim, "low_power", {})
	if power <= 0.0 and activity.kind != "stalled":
		var board := _board(sim)
		if activity.kind == "work" and board:
			board.release(int(activity.job), sim_id)
		activity = {"kind": "stalled"}
		route = []
		stability = maxf(stability - STALL_SHOCK, 0.0)
		sim.note(robot_id, "%s is OUT OF POWER, stalled in %s. Emergency cells engaged." % [display_name(), _room_name(sim)])
		_say(sim, "stalled", {})


func _update_state(sim: FacilitySim) -> void:
	var now := state_for(stability)
	# A little hysteresis so it doesn't flicker on a boundary.
	if now != stability_state and absf(stability - _band_edge(now, stability_state)) > 0.03:
		var worse := _band_index(now) > _band_index(stability_state)
		sim.note("stability" if worse else robot_id, "%s software %s: stability %d%%" % [display_name(),
			"now " + now.to_upper() if worse else "recovering, " + now, _pct(stability)])
		_say(sim, "stability_" + now, {})
		stability_state = now


static func state_for(s: float) -> String:
	for b in STATES:
		if s >= b[0]:
			return b[1]
	return STATES.back()[1]


static func _band_index(name: String) -> int:
	for i in STATES.size():
		if STATES[i][1] == name:
			return i
	return 0


static func _band_edge(a: String, b: String) -> float:
	for m in STATES:
		if m[1] == a or m[1] == b:
			return m[0]
	return 0.0


# Stability lost per idle second: its trait, halved by the firmware-stabilizer package.
func _decay(sim: FacilitySim) -> float:
	var sw := sim.get_system("software") as SoftwareLibrary
	var night := 1.0
	var camp := sim.get_system("campaign") as Campaign
	if camp and not camp.on_duty():
		night = NIGHT_DRIFT   # no supervisor: idle units sit in low-power standby
	elif camp and not own_will() and activity.get("kind", "") == "idle":
		night = WAITING_DRIFT   # stable, waiting to be told: it frets, slowly
	return traits.stability_decay * night * (0.5 if sw and sw.installed("firmware-stabilizer") else 1.0) \
		* (OVERCLOCK_DRIFT if sw and sw.installed("overclock") else 1.0)


# Travel costs from where it is to every node. Cached: a robot standing still
# (idle, charging, working) with no route changes reuses the last one.
var _field_cache := {}
var _field_key := ""


func _field(layout: FacilityLayout) -> Dictionary:
	var key := "%s:%.2f:%d" % [seg, off, layout.version]
	if key != _field_key:
		_field_cache = layout.field(seg, off, traits.width)
		_field_key = key
	return _field_cache


# A random spot it can get to, somewhere on the network (a stationary robot
# stays where it is).
func _wander_target(sim: FacilitySim) -> Dictionary:
	if traits.stationary:
		return {"kind": "wander", "seg": seg, "off": off}
	var layout := _layout(sim)
	var ids := layout.segments.keys()
	ids.sort()
	var f := _field(layout)
	for attempt in 6:
		var sid: String = ids[sim.rng.randi() % ids.size()]
		var s := layout.segment(sid)
		var o := sim.rng.randf_range(0.0, s.length)
		if not layout.reach(f, sid, o).is_empty():
			return {"kind": "wander", "seg": sid, "off": o}
	return {"kind": "wander", "seg": seg, "off": off}


# The dock with the quickest route, or {} if it can't reach any.
func _nearest_dock(sim: FacilitySim, f := {}) -> Dictionary:
	var layout := _layout(sim)
	if f.is_empty():
		f = _field(layout)
	var best := {}
	var best_cost := INF
	for id in layout.stations_of("dock"):
		var r := _reach_station(layout, f, id)
		if not r.is_empty() and float(r.cost) < best_cost:
			best_cost = r.cost
			best = layout.station(id)
	return best


# Can it get to a station, and how far is it: {"cost", "length"} or {}.
# Rail robots ride the network; a stationary one reaches with its crane.
func _reach_station(layout: FacilityLayout, f: Dictionary, station_id: String) -> Dictionary:
	if not traits.stationary:
		return layout.reach_station(f, station_id)
	var d := _crane_distance(layout, station_id)
	return {"cost": 0.0, "length": d} if d <= traits.reach else FacilityLayout.NO_ROUTE


# Floor distance from its mount to a station (INF if it's in another room).
func _crane_distance(layout: FacilityLayout, station_id: String) -> float:
	var st := layout.station(station_id)
	if st.is_empty() or st.room != layout.room_at(seg, off):
		return INF
	var a := layout.world_pos(seg, off)
	var b := layout.station_world_pos(station_id)
	return Vector2(a.x - b.x, a.z - b.z).length()


func _room_name(sim: FacilitySim) -> String:
	var layout := _layout(sim)
	return layout.rooms.get(layout.room_at(seg, off), {}).get("name", "?")


# Looked up once per sim (systems don't change while it runs).
var _sim_ref: WeakRef
var _layout_ref: FacilityLayout
var _board_ref: WorkBoard
var _plant_ref: FacilityPlant


func _layout(sim: FacilitySim) -> FacilityLayout:
	_cache(sim)
	return _layout_ref


func _board(sim: FacilitySim) -> WorkBoard:
	_cache(sim)
	return _board_ref


func _plant(sim: FacilitySim) -> FacilityPlant:
	_cache(sim)
	return _plant_ref


# Docks charge slower while the facility's power relay is out.
func _charge_factor(sim: FacilitySim) -> float:
	_cache(sim)
	return _plant_ref.charge_factor() if _plant_ref else 1.0


func _cache(sim: FacilitySim) -> void:
	if _sim_ref and _sim_ref.get_ref() == sim:
		return
	_sim_ref = weakref(sim)
	_plant_ref = sim.get_system("plant") as FacilityPlant
	_layout_ref = sim.get_system("layout") as FacilityLayout
	if _layout_ref == null:
		_layout_ref = FacilityLayout.new()
	_board_ref = sim.get_system("work") as WorkBoard


static func _pct(x: float) -> int:
	return int(roundf(x * 100.0))


# --- Save / describe -------------------------------------------------------------------

func sim_save() -> Dictionary:
	return {"seg": seg, "off": off, "power": power, "stability": stability, "stability_state": stability_state, "wear": wear,
		"activity": activity.duplicate(), "order": order.duplicate(), "moving": moving, "jobs_done": jobs_done,
		"route": route.duplicate(true), "route_goal": _route_goal,
		"think_left": _think_left, "step_left": _step_left, "whim_seed": str(_whim_seed), "whim_until": _whim_until}


func sim_load(d: Dictionary) -> void:
	seg = str(d.get("seg", seg))
	off = float(d.get("off", off))
	power = float(d.get("power", 1.0))
	stability = float(d.get("stability", 0.8))
	stability_state = str(d.get("stability_state", "stable"))
	wear = float(d.get("wear", 0.2))
	activity = d.get("activity", {"kind": "idle"}).duplicate()
	if activity.has("job"):
		activity.job = int(activity.job)
	order = d.get("order", {}).duplicate()
	if order.has("job"):
		order.job = int(order.job)
	moving = bool(d.get("moving", false))
	jobs_done = int(d.get("jobs_done", 0))
	route = []
	for leg in d.get("route", []):
		route.append({"seg": str(leg.seg), "from": float(leg.from), "to": float(leg.to)})
	_route_goal = str(d.get("route_goal", ""))
	_think_left = float(d.get("think_left", 0.0))
	_step_left = float(d.get("step_left", 0.0))
	_whim_seed = int(str(d.get("whim_seed", "0")))
	_whim_until = float(d.get("whim_until", -1.0))


## One line saying what it's doing, for panels and camera labels.
func doing_text(sim: FacilitySim) -> String:
	match activity.kind:
		"work":
			var j := _board(sim).get_job(int(activity.job)) if _board(sim) else {}
			var st := _layout(sim).station(activity.station)
			var where := "heading to" if moving else "at"
			return "job #%d %s, %s %s (%d%%)" % [int(activity.job), j.get("title", "?"), where,
				st.get("name", "?"), int(_board(sim).fraction_done(j) * 100.0) if not j.is_empty() else 0]
		"recharge":
			return ("heading to " if moving else "charging at ") + str(_layout(sim).station(activity.station).get("name", "dock"))
		"wander":
			return ("restless, sweeping its crane (%s)" if traits.stationary else "wandering (%s)") % _room_name(sim)
		"fixate":
			return "fixated on %s (no job there)" % _layout(sim).station(activity.station).get("name", "?")
		"sabotage":
			return "heading to %s (no job there)" % _layout(sim).station(activity.station).get("name", "?")
		"glitch":
			return "GLITCHING"
		"crashed":
			return "CRASHED (offline until %s)" % FacilitySim.format_clock(float(activity.until))
		"rebooting":
			return "rebooting (back at %s)" % FacilitySim.format_clock(float(activity.until))
		"stalled":
			return "STALLED (no power)"
		"seized":
			return "SEIZED UP (needs a manual reboot)"
		"broken":
			return "OFFLINE: %s" % str(activity.get("why", "broken"))
		"link":
			return "on the link with you"
		"accident":
			return "heading to %s" % _layout(sim).station(activity.station).get("name", "?")
	return "standing by (%s)" % _room_name(sim)


## Dev panel lines.
func sim_describe(sim: FacilitySim) -> PackedStringArray:
	var lines := PackedStringArray()
	var ord := "none"
	if not order.is_empty():
		ord = "job #%d" % int(order.job) if order.kind == "job" else str(order.kind)
	lines.append("%s  %s   %s %.1f m   power %d%%   stability %d%% %s (independence %d%%)   order: %s   jobs done %d" % [
		display_name().to_upper(), doing_text(sim), seg, off, _pct(power), _pct(stability), stability_state,
		_pct(independence()), ord, jobs_done])
	var parts := PackedStringArray()
	for o in scores.slice(0, 4):
		parts.append("%.2f %s" % [o.score, o.label])
	if not parts.is_empty():
		lines.append("    " + "  |  ".join(parts))
		lines.append("    why: " + str(scores[0].why))
	return lines

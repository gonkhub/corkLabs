# A robot's mind, as a facility system (sim_id "robot_<id>"). This is the
# robot the simulation knows about: where it is on its rail, its needs, what
# it's doing and why. The 3D robot (RobotActor + RailRider) just shows it;
# see game/robot_view.gd.
#
# NEEDS
#   power    0-1. Drains while it's on, faster moving and working. Recharges
#            on a dock. Below `power_reserve` it drops everything to recharge.
#            At 0 it stalls and limps on emergency cells.
#   purpose  0-1. Robots believe the work keeps *them* running, so standing
#            idle wears it down ("restless", then "uneasy"); working and
#            finishing jobs restore it. Low purpose makes it hungry for work,
#            and eventually it wanders the rail looking for some.
#
# DECIDING (utility scores)
#   Every `think_interval` facility seconds (and whenever something finishes)
#   it scores every option: each open job it can reach, recharging, standing
#   by, wandering. Highest score wins. The scores and the reason for each are
#   kept in `scores`, shown on the F1 dev panel, and every change of mind is
#   written to the journal with the runner-up, so you can always see why.
#
# ORDERS (a strong nudge, not a command)
#   give_order() adds `obedience` to the ordered option's score. Usually that
#   wins. But a robot below its power reserve recharges first, a robot won't
#   take work it's hopeless at (`refuse_below_skill`), and a very restless
#   robot finds it hard to "stand by". It answers every order in the journal.
class_name RobotAgent
extends RefCounted

## Purpose bands, for mood lines in the journal.
const MOODS := [[0.6, "content"], [0.3, "restless"], [0.0, "uneasy"]]
const ORDER_TIMEOUT := 3600.0   # a stand-by order lapses after an hour
## Robots act in steps of this many facility seconds (5 sim ticks): plenty
## for rail travel and work, and 5x cheaper than acting every tick.
const STEP := 0.5
const EMERGENCY_CHARGE := 0.0002   # per second, while stalled
const EMERGENCY_RESTART := 0.05   # restarts at this and limps to a dock

var sim_id: String
var robot_id: String
var rail: String
var traits: RobotTraits

# --- State (saved) ---
var pos := 0.0
var power := 1.0
var purpose := 0.7
## What it's doing: {"kind": "idle"/"work"/"recharge"/"wander"/"stalled",
## "job": int (work), "station": String (work/recharge), "target": float (wander)}
var activity := {"kind": "idle"}
## The standing order: {} or {"kind": "job"/"recharge"/"standby", "job": int, "given": time}
var order := {}
var moving := false
var jobs_done := 0
var mood := "content"
var _think_left := 0.0
var _step_left := 0.0

## The last evaluation, best first: [{"key", "label", "score", "why"}]
var scores: Array[Dictionary] = []


func _init(id: String, rail_id: String, robot_traits: RobotTraits = null, start_pos := 0.0) -> void:
	robot_id = id
	sim_id = "robot_" + id
	rail = rail_id
	traits = robot_traits if robot_traits else RobotTraits.load_for(id)
	pos = start_pos


func display_name() -> String:
	return traits.display_name


# --- System ---------------------------------------------------------------------

func sim_start(sim: FacilitySim) -> void:
	sim.note(robot_id, "%s online at %.1f m on %s (power %d%%)" % [display_name(), pos, rail, _pct(power)])
	think(sim)   # decide straight away, so a new facility isn't all "standing by"


func sim_tick(sim: FacilitySim, dt: float) -> void:
	_step_left += dt
	if _step_left < STEP - 0.001:
		return
	var step := _step_left
	_step_left = 0.0
	_think_left -= step
	if _think_left <= 0.0:
		_update_mood(sim)
		think(sim)
	_perform(sim, step)


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	match event_name:
		"alarm":
			_think_left = 0.0   # something broke: reconsider now
		"job_done", "job_cancelled":
			var id := int(data.get("job", -1))
			if order.get("kind", "") == "job" and int(order.get("job", -1)) == id:
				order = {}
			if activity.get("kind", "") == "work" and int(activity.get("job", -1)) == id:
				activity = {"kind": "idle"}
				_think_left = 0.0


# --- Deciding ---------------------------------------------------------------------

## Scores every option, best first. Doesn't change anything.
func evaluate(sim: FacilitySim) -> Array[Dictionary]:
	var layout := _layout(sim)
	var board := _board(sim)
	var out: Array[Dictionary] = []
	var energy := clampf((power - traits.power_reserve) / 0.2, 0.0, 1.0)
	var hunger := 1.0 + (1.0 - purpose) * 0.5
	var current := activity_key()

	# Work: every open job on our rail.
	if board:
		for j in board.open_jobs():
			if j.status == "claimed" and j.claimed_by != sim_id:
				continue
			var st := layout.station(j.station)
			if st.is_empty() or st.rail != rail:
				continue
			var fit := traits.skill(j.skill)
			var prio: float = [0.35, 0.55, 0.75, 0.95][int(j.priority)]
			var dist := layout.distance(rail, pos, st.pos)
			var near := 1.0 - traits.distance_aversion * 0.5 * clampf(dist / maxf(layout.rail_length(rail) * 0.5, 0.1), 0.0, 1.0)
			var s := prio * (0.4 + 0.6 * fit) * near * hunger * energy
			var why := "%s priority, %s skill %d%%, %.1f m away" % [WorkBoard.PRIORITY_NAMES[int(j.priority)], j.skill, _pct(fit), dist]
			if energy < 1.0:
				why += ", power %d%%" % _pct(power)
			if _ordered_job() == int(j.id):
				if fit < traits.refuse_below_skill:
					why += ", ordered but not built for it"
				elif energy > 0.0:
					s += traits.obedience
					why += ", ORDERED"
			out.append({"key": "work:%d" % j.id, "label": "work #%d %s" % [j.id, j.title], "score": s, "why": why})

	# Recharge at the nearest dock.
	var dock := _nearest_dock(layout)
	if not dock.is_empty():
		var s := pow(1.0 - power, 2.0) * 1.1
		var why := "power %d%%" % _pct(power)
		if power < traits.power_reserve:
			s = 1.6
			why += ", below reserve"
		elif current == "recharge" and power < traits.charge_until:
			s = maxf(s, 0.9)
			why += ", charging to %d%%" % _pct(traits.charge_until)
		if order.get("kind", "") == "recharge":
			s += traits.obedience
			why += ", ORDERED"
		out.append({"key": "recharge", "label": "recharge at " + str(dock.name), "score": s, "why": why})

	# Stand by where it is. Content robots are happy to; restless ones aren't.
	var idle := 0.12 + 0.2 * purpose
	var idle_why := "purpose %d%% (%s)" % [_pct(purpose), mood]
	if order.get("kind", "") == "standby":
		idle += traits.obedience * purpose
		idle_why += ", ORDERED to stand by"
	out.append({"key": "idle", "label": "stand by", "score": idle, "why": idle_why})

	# Wander the rail looking for something to do.
	var restless := clampf(traits.restlessness / 0.0004, 0.0, 2.0)
	var wander := restless * 0.25 * pow(1.0 - purpose, 1.5) * (0.3 + 0.7 * energy)
	out.append({"key": "wander", "label": "wander the rail", "score": wander, "why": "looking for purpose (%d%%)" % _pct(purpose)})

	# Stick with a task already started (not with doing nothing).
	for o in out:
		if o.key == current and current != "idle":
			o.score += traits.commitment
	out.sort_custom(func(a, b): return a.score > b.score or (a.score == b.score and a.key < b.key))
	return out


## Re-scores and switches to the best option if it isn't already doing it.
func think(sim: FacilitySim) -> void:
	_think_left = traits.think_interval
	if activity.kind == "stalled":
		return
	scores = evaluate(sim)
	if scores.is_empty():
		return
	var best: Dictionary = scores[0]
	if best.key == activity_key():
		return
	_switch_to(sim, best)
	var line := "%s: %s (%.2f: %s)" % [display_name(), best.label, best.score, best.why]
	if scores.size() > 1:
		line += "; next best %s (%.2f)" % [scores[1].label, scores[1].score]
	sim.note(robot_id, line)


func activity_key() -> String:
	match activity.get("kind", "idle"):
		"work": return "work:%d" % int(activity.job)
		"recharge": return "recharge"
		"wander": return "wander"
		"stalled": return "stalled"
	return "idle"


func _switch_to(sim: FacilitySim, option: Dictionary) -> void:
	var board := _board(sim)
	if activity.kind == "work" and board:
		board.release(int(activity.job), sim_id)
	var key: String = option.key
	if key.begins_with("work:"):
		var id := int(key.trim_prefix("work:"))
		board.claim(id, sim_id)
		activity = {"kind": "work", "job": id, "station": board.get_job(id).station}
	elif key == "recharge":
		activity = {"kind": "recharge", "station": _nearest_dock(_layout(sim)).id}
	elif key == "wander":
		activity = {"kind": "wander", "target": _wander_target(sim)}
	else:
		activity = {"kind": "idle"}


# --- Orders ---------------------------------------------------------------------------

## The supervisor tells this robot to do something. kind: "job" (with job_id),
## "recharge" or "standby"; "cancel" clears the standing order.
## Returns {"ok": bool, "reply": String}; the reply also goes in the journal.
func give_order(sim: FacilitySim, kind: String, job_id := -1) -> Dictionary:
	if kind == "cancel":
		order = {}
		return _reply(sim, true, "Understood. Back to my own judgement.")
	if kind == "job":
		var board := _board(sim)
		var j: Dictionary = board.get_job(job_id) if board else {}
		if j.is_empty() or not (j.status == "open" or j.status == "claimed"):
			return _reply(sim, false, "There's no open job #%d." % job_id)
		var st := _layout(sim).station(j.station)
		if st.get("rail", "") != rail:
			return _reply(sim, false, "I can't reach %s from my rail." % st.get("name", j.station))
		if j.status == "claimed" and j.claimed_by != sim_id:
			return _reply(sim, false, "%s is already on job #%d." % [str(j.claimed_by).trim_prefix("robot_").capitalize(), job_id])
		if traits.skill(j.skill) < traits.refuse_below_skill:
			return _reply(sim, false, "No. '%s' is %s work; I'm not built for it." % [j.title, j.skill])
	order = {"kind": kind, "job": job_id, "given": sim.time()}
	scores = evaluate(sim)
	var want: String = ("work:%d" % job_id) if kind == "job" else ("recharge" if kind == "recharge" else "idle")
	var ok: bool = scores[0].key == want
	var reply := "On it."
	if not ok:
		if power < traits.power_reserve or scores[0].key == "recharge":
			reply = "Acknowledged. Recharging first, power at %d%%." % _pct(power)
		elif kind == "standby":
			reply = "I... will try. Standing still feels wrong right now." 
		else:
			reply = "Acknowledged. Doing %s first." % scores[0].label
	var result := _reply(sim, ok, reply)
	think(sim)
	return result


func _ordered_job() -> int:
	return int(order.get("job", -1)) if order.get("kind", "") == "job" else -1


func _reply(sim: FacilitySim, ok: bool, text: String) -> Dictionary:
	sim.note(robot_id, "%s, to the supervisor: \"%s\"" % [display_name(), text])
	return {"ok": ok, "reply": text}


# --- Doing ------------------------------------------------------------------------------

func _perform(sim: FacilitySim, dt: float) -> void:
	var layout := _layout(sim)
	_use_power(sim, traits.drain_idle * dt)
	moving = false
	match activity.kind:
		"stalled":
			power = minf(power + EMERGENCY_CHARGE * dt, 1.0)
			if power >= EMERGENCY_RESTART:
				sim.note(robot_id, "%s restarts on emergency power (%d%%)" % [display_name(), _pct(power)])
				activity = {"kind": "idle"}
				_think_left = 0.0
			return
		"idle":
			purpose = maxf(purpose - traits.restlessness * dt, 0.0)
			if order.get("kind", "") == "standby" and sim.time() - float(order.given) > ORDER_TIMEOUT:
				order = {}
				sim.note(robot_id, "%s's stand-by order lapsed" % display_name())
				_think_left = 0.0
		"wander":
			purpose = maxf(purpose - traits.restlessness * 0.5 * dt, 0.0)
			if _move_toward(sim, layout, float(activity.target), dt):
				activity.target = _wander_target(sim)
		"work":
			var st := layout.station(activity.station)
			if _move_toward(sim, layout, float(st.pos), dt):
				var board := _board(sim)
				_use_power(sim, traits.drain_work * dt)
				purpose = minf(purpose + traits.purpose_from_work * dt, 1.0)
				var j := board.get_job(int(activity.job))
				var amount: float = traits.skill(j.get("skill", "general")) * traits.work_speed * dt
				if board.add_progress(sim, int(activity.job), sim_id, amount):
					jobs_done += 1
					purpose = minf(purpose + traits.purpose_per_job, 1.0)
					if _ordered_job() == int(activity.job):
						order = {}
					activity = {"kind": "idle"}
					_think_left = 0.0
		"recharge":
			var st := layout.station(activity.station)
			if _move_toward(sim, layout, float(st.pos), dt):
				power = minf(power + traits.charge_rate * _charge_factor(sim) * dt, 1.0)
				if power >= traits.charge_until:
					if order.get("kind", "") == "recharge":
						order = {}
					sim.note(robot_id, "%s charged to %d%%" % [display_name(), _pct(power)])
					activity = {"kind": "idle"}
					_think_left = 0.0


# Moves toward `target` along the rail. Returns true once there.
func _move_toward(sim: FacilitySim, layout: FacilityLayout, target: float, dt: float) -> bool:
	var off := layout.signed_offset(rail, pos, target)
	if absf(off) < 0.01:
		return true
	var step := minf(traits.rail_speed * dt, absf(off))
	pos = layout.wrap(rail, pos + signf(off) * step)
	moving = true
	_use_power(sim, traits.drain_move * dt)
	return absf(layout.signed_offset(rail, pos, target)) < 0.01


func _use_power(sim: FacilitySim, amount: float) -> void:
	var was := power
	power = maxf(power - amount, 0.0)
	if was >= traits.power_reserve and power < traits.power_reserve:
		sim.note(robot_id, "%s power low (%d%%)" % [display_name(), _pct(power)])
	if power <= 0.0 and activity.kind != "stalled":
		var board := _board(sim)
		if activity.kind == "work" and board:
			board.release(int(activity.job), sim_id)
		activity = {"kind": "stalled"}
		sim.note(robot_id, "%s is OUT OF POWER, stalled at %.1f m. Emergency cells engaged." % [display_name(), pos])


func _update_mood(sim: FacilitySim) -> void:
	var now := mood_for(purpose)
	# A little hysteresis so it doesn't flicker on a boundary.
	if now != mood and absf(purpose - _band_edge(now, mood)) > 0.05:
		sim.note(robot_id, "%s feels %s (purpose %d%%)" % [display_name(), now, _pct(purpose)])
		mood = now


static func mood_for(p: float) -> String:
	for m in MOODS:
		if p >= m[0]:
			return m[1]
	return MOODS.back()[1]


static func _band_edge(a: String, b: String) -> float:
	for m in MOODS:
		if m[1] == a or m[1] == b:
			return m[0]
	return 0.0


func _wander_target(sim: FacilitySim) -> float:
	return sim.rng.randf_range(0.0, _layout(sim).rail_length(rail))


func _nearest_dock(layout: FacilityLayout) -> Dictionary:
	var best := {}
	var best_d := INF
	for id in layout.stations_on(rail, "dock"):
		var st := layout.station(id)
		var d := layout.distance(rail, pos, st.pos)
		if d < best_d:
			best_d = d
			best = st
	return best


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
	return {"pos": pos, "power": power, "purpose": purpose, "activity": activity.duplicate(),
		"order": order.duplicate(), "moving": moving, "jobs_done": jobs_done, "mood": mood,
		"think_left": _think_left, "step_left": _step_left}


func sim_load(d: Dictionary) -> void:
	pos = float(d.get("pos", pos))
	power = float(d.get("power", 1.0))
	purpose = float(d.get("purpose", 0.7))
	activity = d.get("activity", {"kind": "idle"}).duplicate()
	if activity.has("job"):
		activity.job = int(activity.job)
	order = d.get("order", {}).duplicate()
	if order.has("job"):
		order.job = int(order.job)
	moving = bool(d.get("moving", false))
	jobs_done = int(d.get("jobs_done", 0))
	mood = str(d.get("mood", "content"))
	_think_left = float(d.get("think_left", 0.0))
	_step_left = float(d.get("step_left", 0.0))


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
			return "wandering"
		"stalled":
			return "STALLED (no power)"
	return "standing by"


## Dev panel lines.
func sim_describe(sim: FacilitySim) -> PackedStringArray:
	var lines := PackedStringArray()
	var ord := "none"
	if not order.is_empty():
		ord = "job #%d" % int(order.job) if order.kind == "job" else str(order.kind)
	lines.append("%s  %s   %.1f m   power %d%%   purpose %d%% %s   order: %s   jobs done %d" % [
		display_name().to_upper(), doing_text(sim), pos, _pct(power), _pct(purpose), mood, ord, jobs_done])
	var parts := PackedStringArray()
	for o in scores.slice(0, 4):
		parts.append("%.2f %s" % [o.score, o.label])
	if not parts.is_empty():
		lines.append("    " + "  |  ".join(parts))
		lines.append("    why: " + str(scores[0].why))
	return lines

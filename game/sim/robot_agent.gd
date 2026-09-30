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
#
# NEEDS
#   power    0-1. Drains while it's on, faster moving and working. Recharges
#            on a dock. Below `power_reserve` it drops everything to recharge.
#            At 0 it stalls and limps on emergency cells.
#   purpose  0-1. Robots believe the work keeps *them* running, so standing
#            idle wears it down ("restless", then "uneasy"); working and
#            finishing jobs restore it. Low purpose makes it hungry for work,
#            and eventually it wanders the rails looking for some.
#
# DECIDING (utility scores)
#   Every `think_interval` facility seconds (and whenever something finishes)
#   it scores every option: each open job it can reach, recharging, standing
#   by, wandering. Highest score wins. Scores and reasons are kept in
#   `scores` (F1 dev panel, Units app); every change of mind is journaled.
#
# ORDERS (a strong nudge, not a command)
#   give_order() adds `obedience` to the ordered option's score. Usually that
#   wins. But a robot below its power reserve recharges first, a robot won't
#   take work it's hopeless at or can't get to, and a very restless robot
#   finds it hard to "stand by". Its answer is spoken (RobotChatter).
#
# SPEAKING
#   It tells RobotChatter what just happened ("start_job", "low_power",
#   "route_blocked"...); the chatter system decides whether and what it says.
class_name RobotAgent
extends RefCounted

## Purpose bands, for moods.
const MOODS := [[0.6, "content"], [0.3, "restless"], [0.0, "uneasy"]]
const ORDER_TIMEOUT := 3600.0   # a stand-by order lapses after an hour
## Robots act in steps of this many facility seconds (5 sim ticks).
const STEP := 0.5
const EMERGENCY_CHARGE := 0.0002   # per second, while stalled
const EMERGENCY_RESTART := 0.05    # restarts at this and limps to a dock
## Travel distance (m) at which a job counts as "far" when scoring.
const FAR := 80.0

var sim_id: String
var robot_id: String
var traits: RobotTraits

# --- State (saved) ---
## Where it is: a segment of the rail network and meters along it.
var seg := ""
var off := 0.0
var power := 1.0
var purpose := 0.7
## What it's doing: {"kind": "idle"/"work"/"recharge"/"wander"/"stalled",
## "job": int (work), "station": String (work/recharge), "seg"/"off" (wander target)}
var activity := {"kind": "idle"}
## The standing order: {} or {"kind": "job"/"recharge"/"standby", "job": int, "given": time}
var order := {}
var moving := false
var jobs_done := 0
var mood := "content"
## The route being ridden: [{"seg", "from", "to"}...] (see FacilityLayout.plan).
var route: Array = []
var _route_goal := ""     # what `route` leads to ("station:bay_2", "wander")
var _think_left := 0.0
var _step_left := 0.0

## The last evaluation, best first: [{"key", "label", "score", "why"}]
var scores: Array[Dictionary] = []


func _init(id: String, robot_traits: RobotTraits = null, start_seg := "", start_off := 0.0) -> void:
	robot_id = id
	sim_id = "robot_" + id
	traits = robot_traits if robot_traits else RobotTraits.load_for(id)
	seg = start_seg
	off = start_off


func display_name() -> String:
	return traits.display_name


## The room it's in right now.
func room(sim: FacilitySim) -> String:
	return _layout(sim).room_at(seg, off)


func world_pos(sim: FacilitySim) -> Vector3:
	return _layout(sim).world_pos(seg, off)


# --- System ---------------------------------------------------------------------

func sim_start(sim: FacilitySim) -> void:
	sim.note(robot_id, "%s online in %s (power %d%%)" % [display_name(), _room_name(sim), _pct(power)])
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
		"route_changed":
			route = []           # re-plan on the next step
			_route_goal = ""
			_think_left = 0.0
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
	var f := _field(layout)   # travel costs to everywhere, once

	# Work: every open job it can get to.
	if board:
		for j in board.open_jobs():
			if j.status == "claimed" and j.claimed_by != sim_id:
				continue
			var r := layout.reach_station(f, j.station)
			if r.is_empty():
				continue   # can't get there (too narrow, or blocked)
			var fit := traits.skill(j.skill)
			var prio: float = [0.35, 0.55, 0.75, 0.95][int(j.priority)]
			var dist: float = r.length
			var near := 1.0 - traits.distance_aversion * 0.5 * clampf(dist / FAR, 0.0, 1.0)
			var s := prio * (0.4 + 0.6 * fit) * near * hunger * energy
			var why := "%s priority, %s skill %d%%, %.0f m away" % [WorkBoard.PRIORITY_NAMES[int(j.priority)], j.skill, _pct(fit), dist]
			if energy < 1.0:
				why += ", power %d%%" % _pct(power)
			if _ordered_job() == int(j.id):
				if fit < traits.refuse_below_skill:
					why += ", ordered but not built for it"
				elif energy > 0.0:
					s += traits.obedience
					why += ", ORDERED"
			out.append({"key": "work:%d" % j.id, "label": "work #%d %s" % [j.id, j.title], "score": s, "why": why})

	# Recharge at the nearest dock it can get to.
	var dock := _nearest_dock(sim, f)
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

	# Wander the rails looking for something to do.
	var restless := clampf(traits.restlessness / 0.0004, 0.0, 2.0)
	var wander := restless * 0.25 * pow(1.0 - purpose, 1.5) * (0.3 + 0.7 * energy)
	out.append({"key": "wander", "label": "wander the rails", "score": wander, "why": "looking for purpose (%d%%)" % _pct(purpose)})

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
	# Its job just became unreachable (a route closed): say so and let it go.
	if activity.kind == "work" and not scores.any(func(o): return o.key == activity_key()):
		var j := _board(sim).get_job(int(activity.job)) if _board(sim) else {}
		if not j.is_empty() and (j.status == "open" or j.status == "claimed"):
			_give_up(sim, "station:" + str(activity.station))
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
	else:
		activity = {"kind": "idle"}


# --- Orders ---------------------------------------------------------------------------

## The supervisor tells this robot to do something. kind: "job" (with job_id),
## "recharge" or "standby"; "cancel" clears the standing order.
## Returns {"ok": bool, "reply": String}; the robot also says the reply.
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
		var why := why_cant_reach(sim, j.station)
		if not why.is_empty():
			return _reply(sim, false, "I can't get to %s: %s." % [st.get("name", j.station), why])
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


## "" if it can get to the station, else why not ("too narrow", "blocked: ...").
func why_cant_reach(sim: FacilitySim, station_id: String) -> String:
	var layout := _layout(sim)
	var st := layout.station(station_id)
	if st.is_empty():
		return "there's no such place"
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
		"idle":
			purpose = maxf(purpose - traits.restlessness * dt, 0.0)
			if order.get("kind", "") == "standby" and sim.time() - float(order.given) > ORDER_TIMEOUT:
				order = {}
				sim.note(robot_id, "%s's stand-by order lapsed" % display_name())
				_think_left = 0.0
		"wander":
			purpose = maxf(purpose - traits.restlessness * 0.5 * dt, 0.0)
			if _travel(sim, "wander:%s:%.2f" % [activity.seg, float(activity.off)], str(activity.seg), float(activity.off), dt):
				activity = _wander_target(sim)
		"work":
			var st := layout.station(activity.station)
			if _travel(sim, "station:" + str(activity.station), st.segment, st.offset, dt):
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
	if route.is_empty() or _route_goal != goal:
		var r := layout.plan(seg, off, to_seg, to_off, traits.width)
		if r.is_empty():
			_give_up(sim, goal)
			return false
		route = r.legs.duplicate(true)
		_route_goal = goal
	var budget := traits.rail_speed * dt   # meters at speed 1
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
		sim.note(robot_id, "%s is OUT OF POWER, stalled in %s. Emergency cells engaged." % [display_name(), _room_name(sim)])
		_say(sim, "stalled", {})


func _update_mood(sim: FacilitySim) -> void:
	var now := mood_for(purpose)
	# A little hysteresis so it doesn't flicker on a boundary.
	if now != mood and absf(purpose - _band_edge(now, mood)) > 0.05:
		sim.note(robot_id, "%s feels %s (purpose %d%%)" % [display_name(), now, _pct(purpose)])
		_say(sim, "mood_" + now, {})
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


# A random spot it can get to, somewhere on the network.
func _wander_target(sim: FacilitySim) -> Dictionary:
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
		var r := layout.reach_station(f, id)
		if not r.is_empty() and float(r.cost) < best_cost:
			best_cost = r.cost
			best = layout.station(id)
	return best


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
	return {"seg": seg, "off": off, "power": power, "purpose": purpose, "activity": activity.duplicate(),
		"order": order.duplicate(), "moving": moving, "jobs_done": jobs_done, "mood": mood,
		"route": route.duplicate(true), "route_goal": _route_goal,
		"think_left": _think_left, "step_left": _step_left}


func sim_load(d: Dictionary) -> void:
	seg = str(d.get("seg", seg))
	off = float(d.get("off", off))
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
	route = []
	for leg in d.get("route", []):
		route.append({"seg": str(leg.seg), "from": float(leg.from), "to": float(leg.to)})
	_route_goal = str(d.get("route_goal", ""))
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
			return "wandering (%s)" % _room_name(sim)
		"stalled":
			return "STALLED (no power)"
	return "standing by (%s)" % _room_name(sim)


## Dev panel lines.
func sim_describe(sim: FacilitySim) -> PackedStringArray:
	var lines := PackedStringArray()
	var ord := "none"
	if not order.is_empty():
		ord = "job #%d" % int(order.job) if order.kind == "job" else str(order.kind)
	lines.append("%s  %s   %s %.1f m   power %d%%   purpose %d%% %s   order: %s   jobs done %d" % [
		display_name().to_upper(), doing_text(sim), seg, off, _pct(power), _pct(purpose), mood, ord, jobs_done])
	var parts := PackedStringArray()
	for o in scores.slice(0, 4):
		parts.append("%.2f %s" % [o.score, o.label])
	if not parts.is_empty():
		lines.append("    " + "  |  ".join(parts))
		lines.append("    why: " + str(scores[0].why))
	return lines

# What the robots say, and when (sim_id "chatter"). The simulation side of
# robot speech: it decides that a robot speaks and picks the line; the
# corkLabs OS shows it as floating text over the robot in camera feeds, with
# voice blips (SpeechDirector).
#
# When robots speak:
#   - Robots report what happens to them (RobotAgent calls trigger()):
#     start_job, job_done, recharge, charged, low_power, stalled, restarted,
#     wander, mood_*, route_blocked, and their answers to orders.
#   - Every CHECK_EVERY seconds it looks around: an idle robot may mutter
#     ("idle"); two robots in the same room close together may talk
#     ("peer_greet" / "peer_info", answered a few seconds later by
#     "peer_reply" / "peer_info_reply").
#   - Facility events: alarms ("alarm"), routes closing ("route_closed").
#
# Some triggers always speak (order replies, stalls, blocked routes, low
# power); the rest only if the robot's cooldown has passed and a roll against
# its chattiness succeeds. Lines come from BarkLibrary (barks.txt) and depend
# on the robot's condition (low power, low purpose, mood...).
#
# It uses its own random numbers (seeded from the facility's), so talk never
# changes what else happens, and it's saved, so replays say the same things.
class_name RobotChatter
extends RefCounted

const CHECK_EVERY := 10.0
## Robots this close (meters) in the same room may talk to each other.
const PEER_RANGE := 25.0
## Minimum facility seconds between two conversations of the same pair.
const PEER_COOLDOWN := 900.0
## Seconds before the other robot answers.
const REPLY_DELAY := 4.0
## Idle muttering waits this many times the robot's cooldown between lines.
const IDLE_GAP := 4.0
## A robot won't repeat any of its last this-many lines.
const NO_REPEAT := 3
## Said lines kept for the camera feeds and panels.
const RECENT := 40
## Triggers that always speak, ignoring cooldown and chattiness.
const ALWAYS := ["order_reply", "stalled", "route_blocked", "low_power", "restarted", "peer_reply", "peer_info_reply"]
## Base chance (before chattiness) for the rest.
const CHANCE := {"start_job": 0.5, "job_done": 0.6, "recharge": 0.5, "charged": 0.5, "wander": 0.6,
	"mood_restless": 0.8, "mood_uneasy": 0.9, "mood_content": 0.4, "idle": 0.15, "alarm": 0.8,
	"route_closed": 0.7, "peer_greet": 0.6, "peer_info": 0.9}

var sim_id := "chatter"
var library: BarkLibrary
var rng := RandomNumberGenerator.new()
## Every line said, newest last: {"n", "t", "robot", "text", "trigger", "to"}
var recent: Array[Dictionary] = []
## How many lines have ever been said (the feeds watch this to spot new ones).
var said := 0

var _last_spoke := {}     # robot id -> facility time
var _last_lines := {}     # robot id -> [recent texts] (so it doesn't repeat itself)
var _pair_last := {}      # "a|b" -> facility time
var _acc := 0.0


func _init(lib: BarkLibrary = null) -> void:
	library = lib if lib else BarkLibrary.shared()


## Something happened to `robot`; maybe it says something about it.
func trigger(sim: FacilitySim, robot: RobotAgent, what: String, data := {}) -> bool:
	if what == "order_reply":
		return _speak(sim, robot, str(data.get("text", "")), what, "")
	var forced := ALWAYS.has(what)
	if not forced:
		var since := sim.time() - float(_last_spoke.get(robot.robot_id, -INF))
		if since < robot.traits.chatter_cooldown:
			return false
		var chance: float = CHANCE.get(what, 0.5) * (0.4 + 1.2 * robot.traits.chattiness)
		if rng.randf() > chance:
			return false
	var ctx := context(sim, robot)
	ctx.merge(data, true)
	var text := _pick(what, robot, ctx)
	if text.is_empty():
		return false
	return _speak(sim, robot, text, what, str(data.get("peer_id", "")))


## What placeholders and conditions see about a robot.
func context(sim: FacilitySim, robot: RobotAgent) -> Dictionary:
	var layout := sim.get_system("layout") as FacilityLayout
	var room_id := robot.room(sim) if layout else ""
	return {"me": robot.display_name(), "power": robot.power, "purpose": robot.purpose, "mood": robot.mood,
		"working": robot.activity.kind == "work",
		"room": layout.rooms.get(room_id, {}).get("name", "") if layout else ""}


func _pick(what: String, robot: RobotAgent, ctx: Dictionary) -> String:
	var options := library.candidates(what, robot.robot_id, ctx)
	var last: Array = _last_lines.get(robot.robot_id, [])
	var fresh := options.filter(func(o): return not last.has(BarkLibrary.fill(o.text, ctx)))
	if not fresh.is_empty():
		options = fresh
	if options.is_empty():
		return ""
	var total := 0.0
	for o in options:
		total += o.weight
	var roll := rng.randf() * total
	for o in options:
		roll -= o.weight
		if roll <= 0.0:
			return BarkLibrary.fill(o.text, ctx)
	return BarkLibrary.fill(options.back().text, ctx)


func _speak(sim: FacilitySim, robot: RobotAgent, text: String, what: String, to: String) -> bool:
	if text.is_empty():
		return false
	said += 1
	recent.append({"n": said, "t": sim.time(), "robot": robot.robot_id, "text": text, "trigger": what, "to": to})
	if recent.size() > RECENT:
		recent.pop_front()
	_last_spoke[robot.robot_id] = sim.time()
	var last: Array = _last_lines.get(robot.robot_id, [])
	last.append(text)
	if last.size() > NO_REPEAT:
		last.pop_front()
	_last_lines[robot.robot_id] = last
	sim.note("speech", "%s: \"%s\"" % [robot.display_name(), text])
	return true


## Lines said after line number `mark` (the feeds call this every frame).
func said_since(mark: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in recent:
		if int(r.n) > mark:
			out.append(r)
	return out


# --- Looking around ---------------------------------------------------------------------

func sim_start(sim: FacilitySim) -> void:
	rng.seed = sim.rng.randi()


func sim_tick(sim: FacilitySim, dt: float) -> void:
	_acc += dt
	if _acc < CHECK_EVERY - 0.001:
		return
	_acc = 0.0
	var robots := FacilitySetup.robots(sim)
	for r in robots:
		var quiet_for := sim.time() - float(_last_spoke.get(r.robot_id, -INF))
		if r.activity.kind == "idle" and quiet_for >= r.traits.chatter_cooldown * IDLE_GAP:
			trigger(sim, r, "idle")
	# Pairs in the same room, close together.
	for i in robots.size():
		for k in range(i + 1, robots.size()):
			_maybe_talk(sim, robots[i], robots[k])


func _maybe_talk(sim: FacilitySim, a: RobotAgent, b: RobotAgent) -> void:
	var key := "%s|%s" % [a.robot_id, b.robot_id]
	if sim.time() - float(_pair_last.get(key, -INF)) < PEER_COOLDOWN:
		return
	if a.room(sim) != b.room(sim) or a.world_pos(sim).distance_to(b.world_pos(sim)) > PEER_RANGE:
		return
	# The chattier one starts. If there's a job the other is better at, pass it on.
	var first := a if a.traits.chattiness >= b.traits.chattiness else b
	var second := b if first == a else a
	var tip := _job_for(sim, first, second)
	var what := "peer_info" if not tip.is_empty() else "peer_greet"
	var data := {"peer": second.display_name(), "peer_id": second.robot_id}
	data.merge(tip, true)
	if trigger(sim, first, what, data):
		_pair_last[key] = sim.time()
		sim.schedule_in(REPLY_DELAY, "chatter_reply", {"robot": second.robot_id, "peer": first.robot_id,
			"trigger": "peer_info_reply" if what == "peer_info" else "peer_reply"})


# An open, unclaimed job `other` is better at than `me`: {"job", "station"} or {}.
func _job_for(sim: FacilitySim, me: RobotAgent, other: RobotAgent) -> Dictionary:
	var board := sim.get_system("work") as WorkBoard
	var layout := sim.get_system("layout") as FacilityLayout
	if board == null:
		return {}
	for j in board.open_jobs():
		if j.status == "open" and other.traits.skill(j.skill) > me.traits.skill(j.skill) + 0.3:
			return {"job": j.title, "station": layout.station(j.station).get("name", "")}
	return {}


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	match event_name:
		"chatter_reply":
			var r := sim.get_system("robot_" + str(data.robot)) as RobotAgent
			var p := sim.get_system("robot_" + str(data.peer)) as RobotAgent
			if r and p:
				trigger(sim, r, str(data.trigger), {"peer": p.display_name(), "peer_id": p.robot_id})
		"alarm":
			# The robot nearest the trouble comments.
			var plant := sim.get_system("plant") as FacilityPlant
			var device: Dictionary = plant.device(str(data.get("device", ""))) if plant else {}
			var bot := _nearest_robot(sim, device.get("station", ""))
			if bot:
				trigger(sim, bot, "alarm", {"device": device.get("name", "something")})
		"route_changed":
			if bool(data.get("blocked", false)):
				var layout := sim.get_system("layout") as FacilityLayout
				var s := layout.segment(str(data.segment))
				for bot in FacilitySetup.robots(sim):
					if bot.room(sim) == layout.nodes[s.a].room or bot.room(sim) == layout.nodes[s.b].room:
						trigger(sim, bot, "route_closed", {"device": s.name})
						break


func _nearest_robot(sim: FacilitySim, station_id: String) -> RobotAgent:
	var layout := sim.get_system("layout") as FacilityLayout
	var robots := FacilitySetup.robots(sim)
	if robots.is_empty():
		return null
	if layout == null or station_id.is_empty():
		return robots[0]
	var at := layout.station_world_pos(station_id)
	robots.sort_custom(func(x, y): return x.world_pos(sim).distance_to(at) < y.world_pos(sim).distance_to(at))
	return robots[0]


# --- Save --------------------------------------------------------------------------------

func sim_save() -> Dictionary:
	return {"rng_seed": str(rng.seed), "rng_state": str(rng.state), "recent": recent.duplicate(true), "said": said,
		"last_spoke": _last_spoke.duplicate(), "last_lines": _last_lines.duplicate(true), "pair_last": _pair_last.duplicate(), "acc": _acc}


func sim_load(d: Dictionary) -> void:
	rng.seed = int(str(d.get("rng_seed", "0")))
	rng.state = int(str(d.get("rng_state", "0")))
	recent.clear()
	for r in d.get("recent", []):
		var line: Dictionary = r.duplicate()
		line.n = int(line.n)
		line.t = float(line.t)
		recent.append(line)
	said = int(d.get("said", 0))
	_last_spoke = d.get("last_spoke", {}).duplicate()
	_last_lines = d.get("last_lines", {}).duplicate(true)
	_pair_last = d.get("pair_last", {}).duplicate()
	_acc = float(d.get("acc", 0.0))


## Dev panel lines.
func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	var lines := PackedStringArray(["CHATTER  %d lines said" % said])
	for r in recent.slice(maxi(0, recent.size() - 5)):
		lines.append("  %s  %s: %s" % [FacilitySim.format_clock(r.t), r.robot, r.text])
	return lines

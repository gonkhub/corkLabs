# What the robots say, and when (sim_id "chatter"). The simulation side of
# robot speech: it decides that a robot speaks and picks the line; the
# corkLabs OS shows it as floating text over the robot in camera feeds, with
# voice blips (SpeechDirector).
#
# When robots speak:
#   - Robots report what happens to them (RobotAgent calls trigger()):
#     start_job, job_done, recharge, charged, low_power, stalled, restarted,
#     wander, mood_*, route_blocked, and their answers to orders.
#   - Every CHECK_EVERY seconds it looks around: an idle robot now and then
#     mutters ("idle"); and an EXCHANGE plays if its
#     situation holds (Exchanges, exchanges.txt): written conversations
#     that happen once (or rarely), mostly because of what the supervisor
#     did. That's most of what they say to each other.
#   - A robot remembers its last NO_REPEAT lines and doesn't say them again,
#     and doesn't bring up the same topic (trigger) twice within TOPIC_GAP.
#   - Units never tell each other what to do: orders come from the supervisor.
#   - Facility events: alarms ("alarm"), routes closing ("route_closed").
#
# Some triggers always speak (order replies, stalls, blocked routes, low
# power); the rest only if the robot's cooldown has passed and a roll against
# its chattiness succeeds. Lines come from BarkLibrary (barks.txt) and depend
# on the robot's condition (low power, software stability...). A critically
# unstable robot's lines sometimes come out garbled; "glitch" lines always do.
#
# It uses its own random numbers (seeded from the facility's), so talk never
# changes what else happens, and it's saved, so replays say the same things.
class_name RobotChatter
extends RefCounted

const CHECK_EVERY := 10.0
## Facility seconds before a robot brings up the same topic again (passive triggers).
const TOPIC_GAP := 1800.0
## Topics with a longer gap.
const TOPIC_GAPS := {"waste": 7200.0, "alarm": 3600.0, "route_closed": 3600.0}
## Idle muttering waits this many times the robot's cooldown between lines.
const IDLE_GAP := 4.0
## A robot won't repeat any of its last this-many lines.
const NO_REPEAT := 12
## Exchanges: checked this often; the gap between one and the next; seconds between lines.
const EXCHANGE_EVERY := 60.0
const EXCHANGE_GAP := 1200.0
const EXCHANGE_LINE := 4.0
## Said lines kept for the camera feeds and panels.
const RECENT := 40
## Triggers that always speak, ignoring cooldown and chattiness.
const ALWAYS := ["order_reply", "stalled", "route_blocked", "low_power", "restarted",
	"critical_error", "glitch", "rebooting", "rebooted", "stability_critical", "seized", "need_part", "unanswered", "feed_heavy"]
## Base chance (before chattiness) for the rest.
const CHANCE := {"start_job": 0.5, "job_done": 0.6, "recharge": 0.5, "charged": 0.5, "wander": 0.6,
	"stability_drifting": 0.8, "stability_unstable": 0.9, "stability_stable": 0.4, "idle": 0.06, "alarm": 0.8,
	"fixate": 0.6, "sabotage": 0.5, "order_ignored": 0.9, "waste": 0.7,
	"route_closed": 0.7}

var sim_id := "chatter"
var library: BarkLibrary
var rng := RandomNumberGenerator.new()
## Every line said, newest last: {"n", "t", "robot", "text", "trigger", "to"}
var recent: Array[Dictionary] = []
## How many lines have ever been said (the feeds watch this to spot new ones).
var said := 0

var _last_spoke := {}     # robot id -> facility time
var _last_lines := {}     # robot id -> [recent texts] (so it doesn't repeat itself)
var _topic_last := {}     # "robot|trigger" -> facility time
var _acc := 0.0
var _exchange_acc := 0.0
var _exchange_last := -1e18
## Exchanges played: id -> facility time.
var exchanged := {}


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
		var topic := robot.robot_id + "|" + what
		if sim.time() - float(_topic_last.get(topic, -INF)) < float(TOPIC_GAPS.get(what, TOPIC_GAP)):
			return false
		var chance: float = CHANCE.get(what, 0.5) * (0.4 + 1.2 * robot.traits.chattiness)
		if rng.randf() > chance:
			return false
	var ctx := context(sim, robot)
	ctx.merge(data, true)
	var text := _pick(what, robot, ctx)
	if text.is_empty():
		return false
	if not forced:
		_topic_last[robot.robot_id + "|" + what] = sim.time()
	if what == "glitch" or robot.stability_state == "critical" and rng.randf() < 0.3:
		text = corrupt(text, 0.35 if what == "glitch" else 0.12)
	return _speak(sim, robot, text, what, str(data.get("peer_id", "")))


## Says exactly this line (scripted story moments), on camera like any other.
func say_line(sim: FacilitySim, robot: RobotAgent, text: String) -> bool:
	return _speak(sim, robot, text, "story", "")


## Garbles a line: characters swapped for noise, stutters. `amount` 0-1.
func corrupt(text: String, amount: float) -> String:
	var noise := "#%&@$*!?/|01"
	var out := ""
	for ch in text:
		var r := rng.randf()
		if ch != " " and r < amount:
			out += noise[rng.randi() % noise.length()]
		elif ch != " " and r < amount * 1.4:
			out += ch + "-" + ch
		else:
			out += ch
	return out


## What placeholders and conditions see about a robot.
func context(sim: FacilitySim, robot: RobotAgent) -> Dictionary:
	var layout := sim.get_system("layout") as FacilityLayout
	var room_id := robot.room(sim) if layout else ""
	return {"me": robot.display_name(), "power": robot.power, "stability": robot.stability, "state": robot.stability_state,
		"working": robot.activity.kind == "work",
		"room": layout.rooms.get(room_id, {}).get("name", "") if layout else ""}


func _pick(what: String, robot: RobotAgent, ctx: Dictionary) -> String:
	var options := library.candidates(what, RobotTraits.model_of(robot.robot_id), ctx)
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
	_exchange_acc += CHECK_EVERY
	if _exchange_acc >= EXCHANGE_EVERY and sim.time() - _exchange_last >= EXCHANGE_GAP:
		_exchange_acc = 0.0
		_maybe_exchange(sim)


# An exchange whose situation holds, that hasn't been played (or not for its hours).
func _maybe_exchange(sim: FacilitySim) -> void:
	for d in Exchanges.defs():
		var id := str(d.id)
		var last := float(exchanged.get(id, -INF))
		if str(d.repeat) == "once" and exchanged.has(id):
			continue
		if str(d.repeat).is_valid_float() and sim.time() - last < float(d.repeat) * 3600.0:
			continue
		if not Exchanges.speakers(d).all(func(r): return Exchanges.can_speak(sim.get_system("robot_" + r) as RobotAgent)):
			continue
		if not Exchanges.check(sim, str(d.condition)):
			continue
		play_exchange(sim, d)
		return


## Plays an exchange: its lines, a few seconds apart.
func play_exchange(sim: FacilitySim, d: Dictionary) -> void:
	exchanged[str(d.id)] = sim.time()
	_exchange_last = sim.time()
	var k := sim.get_system("knowledge") as Knowledge
	if k:
		k.learn(sim, "exchange:" + str(d.id))
	for i in (d.lines as Array).size():
		sim.schedule_in(EXCHANGE_LINE * i, "exchange_line", {"robot": str(d.lines[i].robot), "text": str(d.lines[i].text)})


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	match event_name:
		"exchange_line":
			var who := sim.get_system("robot_" + str(data.robot)) as RobotAgent
			if who and Exchanges.can_speak(who):
				_speak(sim, who, str(data.text), "exchange", "")
		"alarm":
			if not data.has("device"):
				return
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
		"last_spoke": _last_spoke.duplicate(), "last_lines": _last_lines.duplicate(true), "topic_last": _topic_last.duplicate(), "acc": _acc,
		"exchanged": exchanged.duplicate(), "exchange_acc": _exchange_acc, "exchange_last": _exchange_last if _exchange_last > -1e17 else -1e18}


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
	_topic_last = d.get("topic_last", {}).duplicate()
	_acc = float(d.get("acc", 0.0))
	exchanged = {}
	var ex: Dictionary = d.get("exchanged", {})
	for k in ex:
		exchanged[k] = float(ex[k])
	_exchange_acc = float(d.get("exchange_acc", 0.0))
	_exchange_last = float(d.get("exchange_last", -1e18))


## Dev panel lines.
func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	var lines := PackedStringArray(["CHATTER  %d lines said" % said])
	for r in recent.slice(maxi(0, recent.size() - 5)):
		lines.append("  %s  %s: %s" % [FacilitySim.format_clock(r.t), r.robot, r.text])
	return lines

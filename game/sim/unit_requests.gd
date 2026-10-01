# Unit requests (sim_id "requests"): the units ask the supervisor for
# things, and wait for an answer. Answering is a choice (it costs facility
# time, through Supervisor.answer_request). Leave one too long and the unit
# decides for itself (the default answer), says so, and its software takes the
# knock: being ignored hurts.
#
#   service   joints grinding (wear): book a service (uses a servo bundle)?
#   help      another unit has seized up: can I go and reboot it?
#   recharge  power's low in the middle of something urgent: finish or charge?
#   bored     standing about with nothing asked of it: can I do something?
#   hot       a leak in a hot facility: clamp it live (fast, but it wears me)?
#
# Each request: {"id", "robot", "kind", "text", "options": [labels],
# "default": option index used when it expires, "expires", "data"}.
class_name UnitRequests
extends RefCounted

const CHECK_EVERY := 60.0
## How long a request waits for an answer (facility seconds).
const WAIT := 2700.0
## What being ignored costs a unit's software stability.
const IGNORED := 0.08
## The same unit doesn't ask the same kind of thing again for this long.
const REPEAT_GAP := 7200.0
const SERVICE_AT := 0.55
## Trust: answering a request (and saying yes), or leaving it to expire.
const TRUST_ANSWERED := 0.15
const TRUST_YES := 0.05
const TRUST_IGNORED := -0.4

var sim_id := "requests"
var requests: Array[Dictionary] = []
var next_id := 1
## How many requests have ever been asked (the desktop watches this).
var asked := 0
## This shift: requests answered by the supervisor, and left to expire.
var answered := 0
var ignored := 0
var _acc := 0.0
var _last := {}   # "robot:kind" -> facility time asked


func open_requests() -> Array[Dictionary]:
	return requests.duplicate()


func get_request(id: int) -> Dictionary:
	for r in requests:
		if int(r.id) == id:
			return r
	return {}


## Asks (unless the same unit asked the same thing recently). Returns the id or -1.
func ask(sim: FacilitySim, robot: String, kind: String, text: String, options: Array, default := 1, data := {}) -> int:
	var key := robot + ":" + kind
	if sim.time() - float(_last.get(key, -INF)) < REPEAT_GAP:
		return -1
	for r in requests:
		if r.robot == robot and r.kind == kind:
			return -1
	_last[key] = sim.time()
	var r := {"id": next_id, "robot": robot, "kind": kind, "text": text, "options": options, "default": default,
		"expires": sim.time() + WAIT, "data": data, "t": sim.time()}
	next_id += 1
	asked += 1
	requests.append(r)
	var bot := sim.get_system("robot_" + robot) as RobotAgent
	sim.note("request", "%s asks: %s" % [bot.display_name() if bot else robot, text])
	return int(r.id)


## Is this request still worth asking? (The supervisor may already have dealt
## with what it's about: ordered the repair, booked the service...)
func relevant(sim: FacilitySim, r: Dictionary) -> bool:
	var bot := sim.get_system("robot_" + str(r.robot)) as RobotAgent
	var board := sim.get_system("work") as WorkBoard
	if bot == null or board == null:
		return false
	var d: Dictionary = r.data
	match str(r.kind):
		"service":
			return bot.wear >= SERVICE_AT - 0.05 and not board.jobs.any(func(j): return str(j.source) == "service:" + bot.robot_id and WorkBoard.active(j))
		"help":
			var seized := sim.get_system("robot_" + str(d.get("robot", ""))) as RobotAgent
			return seized != null and seized.activity.kind == "seized" and not bot.offline() \
				and not board.jobs.any(func(j): return str(j.source) == "unit:" + seized.robot_id and WorkBoard.active(j) and (j.get("requested", false) or j.status == "claimed"))
		"recharge":
			var j := board.get_job(int(d.get("job", -1)))
			return WorkBoard.active(j) and bot.activity.kind == "work" and int(bot.activity.get("job", -1)) == int(j.id) and bot.power < bot.traits.power_reserve + 0.12
		"bored":
			var plant := sim.get_system("plant") as FacilityPlant
			var dev := plant.device(str(d.get("device", ""))) if plant else {}
			return bot.activity.kind in ["idle", "wander"] and bot.order.is_empty() and not dev.is_empty() and int(dev.job) < 0
		"hot":
			var j := board.get_job(int(d.get("job", -1)))
			return WorkBoard.active(j) and not j.get("requested", false) and j.status != "claimed" and not bot.offline()
	return true


## Withdraws requests that no longer make sense (quietly: nobody ignored anything).
func prune(sim: FacilitySim) -> void:
	for q in requests.duplicate():
		if not relevant(sim, q):
			requests.erase(q)
			sim.note("request", "%s no longer asks: %s" % [str(q.robot).capitalize(), str(q.text).left(60)])


## Answers request `id` with option `i`. Returns what happened ("" = no such request).
func answer(sim: FacilitySim, id: int, i: int, by_default := false) -> String:
	var r := get_request(id)
	if r.is_empty() or i < 0 or i >= (r.options as Array).size():
		return ""
	requests.erase(r)
	var bot := sim.get_system("robot_" + str(r.robot)) as RobotAgent
	var name := bot.display_name() if bot else str(r.robot)
	var out := _apply(sim, r, i, bot)
	if not by_default:
		answered += 1
		sim.note("request", "Supervisor to %s: %s" % [name, r.options[i]])
		Knowledge.nudge_trust(sim, str(r.robot), TRUST_ANSWERED + (TRUST_YES if i == 0 else 0.0), "you answered it")
	return out


func _apply(sim: FacilitySim, r: Dictionary, i: int, bot: RobotAgent) -> String:
	var yes := i == 0
	var d: Dictionary = r.data
	match str(r.kind):
		"service":
			if yes and bot:
				var id := bot.book_service(sim)
				return "Service booked (job #%d)." % id if id >= 0 else ("No servo bundles in stock." if id == -2 else "A service is already booked.")
			if bot:
				bot.stability = maxf(bot.stability - 0.03, 0.0)
			return "Not now."
		"help":
			if yes and bot:
				var board := sim.get_system("work") as WorkBoard
				for j in board.open_jobs():
					if str(j.source) == "unit:" + str(d.robot):
						var why := board.request(sim, int(j.id))
						if not why.is_empty():
							return why
						bot.give_order(sim, "job", int(j.id))
						return "%s is on its way." % bot.display_name()
			return "It stays seized for now."
		"recharge":
			if bot:
				if yes:
					bot.give_order(sim, "job", int(d.get("job", -1)))
					return "%s keeps going." % bot.display_name()
				bot.give_order(sim, "recharge")
				return "%s breaks off to recharge." % bot.display_name()
		"bored":
			if bot:
				if yes:
					var plant := sim.get_system("plant") as FacilityPlant
					var board := sim.get_system("work") as WorkBoard
					var dev := plant.device(str(d.device)) if plant else {}
					if not dev.is_empty() and int(dev.job) < 0 and board:
						dev.job = board.post(sim, FacilityPlant._job_title(dev), FacilityPlant.KINDS[dev.kind].skill, dev.station,
							FacilityPlant.KINDS[dev.kind].work * 0.6, 1, str(d.device))
					if not dev.is_empty() and int(dev.job) >= 0 and board and board.request(sim, int(dev.job)).is_empty():
						bot.give_order(sim, "job", int(dev.job))
					bot.stability = minf(bot.stability + 0.06, 1.0)
					return "%s goes early." % bot.display_name()
				bot.stability = maxf(bot.stability - 0.04, 0.0)
				return "%s stands by. Unhappily." % bot.display_name()
		"hot":
			var board := sim.get_system("work") as WorkBoard
			var j := board.get_job(int(d.get("job", -1))) if board else {}
			if yes and not j.is_empty() and WorkBoard.active(j):
				var why := board.request(sim, int(j.id))
				if not why.is_empty():
					return why
				j.work = float(j.progress) + (float(j.work) - float(j.progress)) * 0.5
				j.hot = true
				if bot:
					bot.give_order(sim, "job", int(j.id))
				return "Clamping it live."
			return "Waiting for it to cool."
	return ""


# --- Noticing what to ask ------------------------------------------------------------

func sim_tick(sim: FacilitySim, dt: float) -> void:
	_acc += dt
	if _acc < CHECK_EVERY - 0.001:
		return
	_acc = 0.0
	var camp := sim.get_system("campaign") as Campaign
	var on := camp == null or camp.on_duty()
	prune(sim)
	# Expired: the unit decides for itself.
	for r in requests.duplicate():
		if sim.time() >= float(r.expires) or not on:
			var bot := sim.get_system("robot_" + str(r.robot)) as RobotAgent
			answer(sim, int(r.id), int(r.default), true)
			if bot and on:
				ignored += 1
				bot.stability = maxf(bot.stability - IGNORED, 0.0)
				Knowledge.nudge_trust(sim, bot.robot_id, TRUST_IGNORED, "you ignored it")
				sim.note("request", "%s got no answer and decided for itself" % bot.display_name())
				var chatter := sim.get_system("chatter") as RobotChatter
				if chatter:
					chatter.trigger(sim, bot, "unanswered", {})
	if not on:
		return
	var board := sim.get_system("work") as WorkBoard
	var plant := sim.get_system("plant") as FacilityPlant
	for bot in FacilitySetup.robots(sim):
		if bot.offline():
			continue
		# Worn joints.
		if bot.wear >= SERVICE_AT and not board.jobs.any(func(j): return str(j.source) == "service:" + bot.robot_id and WorkBoard.active(j)):
			ask(sim, bot.robot_id, "service", "My joints are grinding (wear %d%%). Book me a service? It uses a servo bundle." % roundi(bot.wear * 100.0),
				["Book a service", "Not now"], 1)
		# Low power in the middle of urgent work.
		if bot.activity.kind == "work" and bot.power < bot.traits.power_reserve + 0.08 and not bot.own_will():
			var j := board.get_job(int(bot.activity.job))
			if not j.is_empty() and int(j.priority) >= 2:
				ask(sim, bot.robot_id, "recharge", "Power's at %d%%. Finish job #%d (%s) first, or go and charge?" % [roundi(bot.power * 100.0), j.id, j.title],
					["Finish it", "Go and charge"], 1, {"job": j.id})
		# Standing about with nothing asked of it (stable units wait to be told).
		if bot.activity.kind in ["idle", "wander"] and bot.stability < 0.75 and not bot.own_will() and board.queued_jobs().is_empty() and plant:
			# Only routine work that's its job, and that it can get to.
			var worst := ""
			var worst_v := 0.95
			for id in plant.device_ids():
				var dv := plant.device(id)
				var k: Dictionary = FacilityPlant.KINDS[dv.kind]
				var units: Array = k.get("units", [])
				if not k.has("drift") or int(dv.job) >= 0 or float(dv.value) >= worst_v:
					continue
				var levels: Array = k.get("levels", [0.7])
				if float(dv.value) >= minf(float(levels[0]) + 0.25, 0.95):
					continue   # not close to needing it yet
				if (not units.is_empty() and not bot.robot_id in units) or bot.route_length(sim, str(dv.station)) < 0.0:
					continue
				worst_v = float(dv.value)
				worst = id
			if not worst.is_empty():
				var title := FacilityPlant._job_title(plant.device(worst))
				ask(sim, bot.robot_id, "bored", "Nobody's asked me for anything. Standing still is bad for me. Can I go and %s?" % _lower_first(title),
					["Yes, go", "No, stand by"], 1, {"device": worst})


static func _lower_first(t: String) -> String:
	return t.left(1).to_lower() + t.substr(1)


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	if event_name == "shift_start":
		answered = 0
		ignored = 0
	var camp := sim.get_system("campaign") as Campaign
	if camp and not camp.on_duty():
		return
	match event_name:
		"alarm":
			if data.has("robot"):
				var seized := sim.get_system("robot_" + str(data.robot)) as RobotAgent
				var board := sim.get_system("work") as WorkBoard
				var taken := board != null and board.jobs.any(func(j): return str(j.source) == "unit:" + str(data.robot) and j.status == "claimed")
				if seized and seized.activity.kind == "seized" and not taken:
					# Someone who could reboot it asks to go (unless someone already is).
					for bot in FacilitySetup.robots(sim):
						if bot != seized and not bot.offline() and not bot.traits.stationary and bot.traits.skill("precise") >= 0.5:
							ask(sim, bot.robot_id, "help", "%s has seized up in %s. Can I go and reboot it?" % [seized.display_name(), seized._room_name(sim)],
								["Go now", "Not now"], 1, {"robot": seized.robot_id})
							break
			elif data.has("device"):
				var plant := sim.get_system("plant") as FacilityPlant
				var dv := plant.device(str(data.device)) if plant else {}
				if not dv.is_empty() and dv.kind == "pipe" and plant.heat() > 1.25 and int(dv.job) >= 0:
					for bot in FacilitySetup.robots(sim):
						if not bot.offline() and bot.traits.skill("heavy") >= 0.7 and not bot.traits.stationary:
							ask(sim, bot.robot_id, "hot", "%s is leaking and the facility's running hot. Clamp it live? Twice as fast, but it'll grind my joints." % dv.name,
								["Clamp it live", "Wait for it to cool"], 1, {"job": dv.job})
							break


func sim_save() -> Dictionary:
	return {"requests": requests.duplicate(true), "next_id": next_id, "asked": asked, "acc": _acc, "last": _last.duplicate(),
		"answered": answered, "ignored": ignored}


func sim_load(d: Dictionary) -> void:
	requests.clear()
	for r in d.get("requests", []):
		var req: Dictionary = r.duplicate(true)
		req.id = int(req.id)
		req.default = int(req.default)
		req.expires = float(req.expires)
		requests.append(req)
	next_id = int(d.get("next_id", 1))
	asked = int(d.get("asked", 0))
	answered = int(d.get("answered", 0))
	ignored = int(d.get("ignored", 0))
	_acc = float(d.get("acc", 0.0))
	_last = {}
	var l: Dictionary = d.get("last", {})
	for k in l:
		_last[k] = float(l[k])


func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	var lines := PackedStringArray(["REQUESTS  %d open" % requests.size()])
	for r in requests:
		lines.append("  #%d %s: %s %s" % [r.id, r.robot, r.text, str(r.options)])
	return lines

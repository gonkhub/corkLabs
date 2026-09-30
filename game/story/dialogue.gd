# Conversations with the units, written as plain text scripts
# (game/story/dialogue/<robot>.txt), and a runner that plays one.
# The supervisor starts one with "talk <robot>" in the Terminal (or Talk in
# Units). Every line read and every choice made costs facility time
# (Supervisor.talk_*), like everything else.
#
# Script format:
#   == node_id                  a node (every script starts at "start")
#   tinker: Hello!              a line (speaker: robot id, "you" or "sys")
#   ~ learn secret:x            an effect: learn, stability <+/-n> (this unit),
#                               or any Campaign action ("~ suspicion 3 | why")
#   -> node_id                  go to a node ("END" ends the conversation)
#   -> {condition} node_id      go there only if the condition holds
#   * choice text -> node_id    a reply the supervisor can pick
#   * {condition} text -> node  a reply that only shows if the condition holds
# Conditions: knowledge keys, !key, comparisons (standing>=50), joined with &,
# plus live facts about the unit: quiet (nobody else in its room), unstable,
# low_power, working.
# Entering a node learns "seen:<robot>.<node>", so scripts can check what's
# been said before ({!seen:tinker.who}).
class_name Dialogue
extends RefCounted

const DIR := "res://game/story/dialogue/"

static var _cache := {}

## node id -> Array of steps: {"kind": "line"/"effect"/"goto"/"choice", ...}
var nodes := {}


static func for_robot(robot_id: String) -> Dialogue:
	if not _cache.has(robot_id):
		var path := DIR + robot_id + ".txt"
		_cache[robot_id] = parse(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return _cache[robot_id]


static func parse(text: String) -> Dialogue:
	var d := Dialogue.new()
	var node := ""
	for raw in text.replace("\r", "").split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("=="):
			node = line.substr(2).strip_edges()
			d.nodes[node] = []
			continue
		if node.is_empty():
			continue
		var steps: Array = d.nodes[node]
		if line.begins_with("~"):
			var body := line.substr(1).strip_edges()
			var sp := body.find(" ")
			steps.append({"kind": "effect", "action": body if sp < 0 else body.substr(0, sp),
				"args": "" if sp < 0 else body.substr(sp + 1).strip_edges()})
		elif line.begins_with("->"):
			var rest := _cond(line.substr(2).strip_edges())
			steps.append({"kind": "goto", "cond": rest[0], "target": rest[1].strip_edges()})
		elif line.begins_with("*"):
			var rest := _cond(line.substr(1).strip_edges())
			var arrow: int = rest[1].rfind("->")
			var label: String = rest[1] if arrow < 0 else rest[1].substr(0, arrow).strip_edges()
			var target: String = "END" if arrow < 0 else rest[1].substr(arrow + 2).strip_edges()
			steps.append({"kind": "choice", "cond": rest[0], "text": label, "target": target})
		else:
			var colon := line.find(":")
			if colon > 0 and colon < 12 and not line.substr(0, colon).contains(" "):
				steps.append({"kind": "line", "speaker": line.substr(0, colon).strip_edges(), "text": line.substr(colon + 1).strip_edges()})
			else:
				steps.append({"kind": "line", "speaker": "sys", "text": line})
	return d


# "{cond} rest" -> [cond, rest]
static func _cond(s: String) -> Array:
	if s.begins_with("{"):
		var close := s.find("}")
		if close > 0:
			return [s.substr(1, close - 1).strip_edges(), s.substr(close + 1).strip_edges()]
	return ["", s]


# --- Running a conversation ---------------------------------------------------------

## One conversation in progress. step() plays lines until the supervisor has
## to choose (or it ends).
class Runner:
	extends RefCounted
	var dialogue: Dialogue
	var robot_id := ""
	var node := ""
	var index := 0
	var done := false
	## The replies on offer right now: [{"text", "target"}]
	var choices: Array[Dictionary] = []

	func _init(d: Dialogue, id: String) -> void:
		dialogue = d
		robot_id = id

	## Starts at "start". Returns the lines played (see step()).
	func begin(sim: FacilitySim) -> Array[Dictionary]:
		_enter(sim, "start")
		return step(sim)

	## Plays on until choices or the end. Returns the lines: [{"speaker", "text"}].
	func step(sim: FacilitySim) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		choices.clear()
		var guard := 0
		while not done and guard < 500:
			guard += 1
			var steps: Array = dialogue.nodes.get(node, [])
			if index >= steps.size():
				# Ran off the end of a node: offer its choices, or stop.
				if choices.is_empty():
					done = true
				return out
			var s: Dictionary = steps[index]
			index += 1
			match s.kind:
				"line":
					if not choices.is_empty():
						continue
					out.append({"speaker": s.speaker, "text": s.text})
				"effect":
					if choices.is_empty():
						Dialogue.apply(sim, robot_id, s.action, s.args)
				"goto":
					if choices.is_empty() and Dialogue.check(sim, robot_id, s.cond):
						if s.target == "END":
							done = true
							return out
						_enter(sim, s.target)
				"choice":
					if Dialogue.check(sim, robot_id, s.cond):
						choices.append({"text": s.text, "target": s.target})
		return out

	## Picks reply `i` (0-based). Returns the lines that follow.
	func choose(sim: FacilitySim, i: int) -> Array[Dictionary]:
		if i < 0 or i >= choices.size():
			return []
		var target: String = choices[i].target
		choices.clear()
		if target == "END":
			done = true
			return []
		_enter(sim, target)
		return step(sim)

	func _enter(sim: FacilitySim, n: String) -> void:
		node = n
		index = 0
		if not dialogue.nodes.has(n):
			push_warning("Dialogue %s: no node '%s'" % [robot_id, n])
			done = true
			return
		var k := Story.knowledge(sim)
		if k:
			k.learn(sim, "seen:%s.%s" % [robot_id, n])


## Condition check with live facts about the unit.
static func check(sim: FacilitySim, robot_id: String, condition: String) -> bool:
	if condition.strip_edges().is_empty():
		return true
	var bot := sim.get_system("robot_" + robot_id) as RobotAgent
	var facts := {}
	if bot:
		facts.unstable = bot.stability_state in ["unstable", "critical"]
		facts.low_power = bot.power < 0.3
		facts.working = bot.activity.kind == "work"
		var room := bot.room(sim)
		facts.quiet = FacilitySetup.robots(sim).all(func(r): return r == bot or r.room(sim) != room)
	var rest := PackedStringArray()
	for part in condition.split("&", false):
		var c := part.strip_edges()
		var neg := c.begins_with("!")
		var key := c.substr(1) if neg else c
		if facts.has(key):
			if bool(facts[key]) == neg:
				return false
		else:
			rest.append(c)
	var camp := Story.campaign(sim)
	if camp:
		return camp.check(sim, "&".join(rest))
	var k := Story.knowledge(sim)
	return k == null or k.check("&".join(rest))


## Runs an effect line (~ action args).
static func apply(sim: FacilitySim, robot_id: String, action: String, args: String) -> void:
	match action:
		"learn":
			for key in args.split(" ", false):
				Story.learn(sim, key)
		"forget":
			var k := Story.knowledge(sim)
			if k:
				k.forget(args.strip_edges())
		"stability":
			var bot := sim.get_system("robot_" + robot_id) as RobotAgent
			if bot:
				bot.stability = clampf(bot.stability + float(args), 0.0, 1.0)
		_:
			var camp := Story.campaign(sim)
			if camp:
				camp.run_action(sim, action, args)

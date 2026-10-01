# Turns what the robots say (RobotChatter, in the simulation) into speech on
# the supervisor's screens: coloured words that type themselves out above the
# robot in every camera feed that can see it, with the robot's voice blips.
#
#   - Each robot has at most one line up at a time: a newer line replaces it
#     (so a long Wait that skips an hour doesn't queue up an hour of talk).
#     Conversations over the unit link (Cameras) and requests QUEUE their
#     lines instead: each starts when the one before has been read, and
#     nothing else (idle chatter) replaces a queued line while it's up.
#   - Words type out at the robot's voice_speed, hold, then fade.
#   - You only HEAR a robot while it's on an open camera (feeds report which
#     robots they can see with mark_seen()). Voices can be turned off in Settings.
#
# CCTVFeed asks bubbles() every frame to draw them.
class_name SpeechDirector
extends Node

const HOLD := 2.5            # seconds after typing finishes
const HOLD_PER_CHAR := 0.04
const FADE := 0.6
const SEEN_GRACE := 0.3
## Lines that matter (story moments, exchanges, answers to orders): passive
## chatter doesn't replace them while they're up.
const KEEP := ["story", "exchange", "order_reply"]      # a robot counts as on camera for this long after a feed saw it

## robot id -> {"text", "color", "shown": float letters, "age", "life"}
var active := {}
var voices := {}             # robot id -> RobotVoice
var _mark := -1
var _seen := {}              # robot id -> seconds since a feed last saw it
var _traits := {}
## robot id -> [text, ...] waiting to be said (queue_line)
var _queued := {}


func _process(delta: float) -> void:
	if not Facility.running:
		active.clear()
		return
	var chatter := Facility.sim.get_system("chatter") as RobotChatter
	if chatter == null:
		return
	if _mark < 0:
		_mark = chatter.said   # don't replay what was said before we started watching
	for line in chatter.said_since(_mark):
		var who := str(line.robot)
		var keep: bool = KEEP.has(str(line.get("trigger", "")))
		var busy: bool = _queued.has(who) or (active.has(who) and active[who].get("keep", false))
		if keep and busy:
			queue_line(who, str(line.text))   # one that matters waits its turn
		elif not busy:   # passive chatter never talks over a line that matters
			_start(who, str(line.text), keep)
	for id in _queued.keys():
		var q: Array = _queued[id]
		if q.is_empty():
			_queued.erase(id)
		elif not active.has(id) or float(active[id].age) >= float(active[id].life) - FADE:
			_start(id, str(q.pop_front()), true)
	_mark = chatter.said
	var voices_on: bool = OSSettings.get_value("voices")
	for id in active.keys():
		var b: Dictionary = active[id]
		var t := _traits_for(id)
		var before := int(b.shown)
		b.shown = minf(float(b.shown) + t.voice_speed * delta, float(b.text.length()))
		b.age = float(b.age) + delta
		if voices_on and heard(id):
			for i in range(before, int(b.shown)):
				var ch: String = b.text[i]
				if i % 2 == 0 and (ch.to_lower() != ch.to_upper() or ch.is_valid_int()):   # letters and digits, every other one
					_voice(id).blip(ch)
		if b.age > float(b.life):
			active.erase(id)
	for id in _seen:
		_seen[id] = float(_seen[id]) + delta


## What to draw: [{"robot", "text" (typed so far), "color" (with fade)}]
func bubbles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in active:
		var b: Dictionary = active[id]
		var alpha := clampf((float(b.life) - float(b.age)) / FADE, 0.0, 1.0)
		var c: Color = b.color
		c.a = alpha
		out.append({"robot": id, "text": str(b.text).substr(0, int(b.shown)), "color": c})
	return out


## A feed can see this robot right now.
func mark_seen(robot_id: String) -> void:
	_seen[robot_id] = 0.0


func heard(robot_id: String) -> bool:
	return float(_seen.get(robot_id, INF)) <= SEEN_GRACE


## Queues a line: it's said after the robot's current one (a conversation).
func queue_line(robot_id: String, text: String) -> void:
	if not _queued.has(robot_id):
		_queued[robot_id] = []
	_queued[robot_id].append(text)


## Starts a line (the Terminal / tests can call this directly too).
func say(robot_id: String, text: String) -> void:
	_start(robot_id, text)


func _start(robot_id: String, text: String, keep := false) -> void:
	var t := _traits_for(robot_id)
	var type_time := text.length() / maxf(t.voice_speed, 1.0)
	active[robot_id] = {"text": text, "color": t.speech_color, "shown": 0.0, "age": 0.0, "keep": keep,
		"life": type_time + HOLD + HOLD_PER_CHAR * text.length() + FADE}


func _traits_for(robot_id: String) -> RobotTraits:
	if not _traits.has(robot_id):
		_traits[robot_id] = RobotTraits.load_for(robot_id)
	return _traits[robot_id]


func _voice(robot_id: String) -> RobotVoice:
	if not voices.has(robot_id):
		var v := RobotVoice.new()
		v.name = "Voice_" + robot_id
		add_child(v)
		v.setup(_traits_for(robot_id))
		voices[robot_id] = v
	var voice: RobotVoice = voices[robot_id]
	voice.volume_db = linear_to_db(maxf(float(OSSettings.get_value("voice_volume")), 0.001))
	return voice

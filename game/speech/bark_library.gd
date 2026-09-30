# The robots' lines ("barks"), loaded from game/speech/barks.txt.
#
# barks.txt is a plain text file you can edit without touching code. One
# line per bark:
#
#     trigger | robot | condition | text
#
#   trigger    what just happened: start_job, job_done, recharge, charged,
#              low_power, stalled, restarted, wander, mood_restless,
#              mood_uneasy, mood_content, route_blocked, idle, alarm,
#              route_closed, peer_greet, peer_reply, peer_info, peer_info_reply...
#              (RobotChatter decides when each one fires.)
#   robot      tinker, hauler, or any
#   condition  empty (always), or one of: low_power, full_power, low_purpose,
#              restless, uneasy, content, working, idle. Several, space-separated,
#              must all hold. Lines whose condition holds are picked more often
#              than plain ones, so a tired robot mostly sounds tired.
#   text       what it says. {placeholders} get filled in: {me} {peer} {job}
#              {station} {place} {why} {power} {purpose} {room} {device}
#
# Lines starting with # are comments.
class_name BarkLibrary
extends RefCounted

const PATH := "res://game/speech/barks.txt"
## How much more likely a line is when its condition holds (vs a plain line).
const CONDITION_WEIGHT := 4.0

## [{"trigger", "robot", "conditions": PackedStringArray, "text"}]
var lines: Array[Dictionary] = []

static var _shared: BarkLibrary


static func shared() -> BarkLibrary:
	if _shared == null:
		_shared = BarkLibrary.new()
		_shared.load_text(FileAccess.get_file_as_string(PATH))
	return _shared


func load_text(text: String) -> void:
	lines.clear()
	for raw in text.split("\n"):
		var l := raw.strip_edges()
		if l.is_empty() or l.begins_with("#"):
			continue
		var parts := l.split("|")
		if parts.size() < 4:
			push_warning("barks.txt: can't read line: " + l)
			continue
		var text_part := "|".join(parts.slice(3)).strip_edges()
		lines.append({"trigger": parts[0].strip_edges(), "robot": parts[1].strip_edges().to_lower(),
			"conditions": parts[2].strip_edges().split(" ", false), "text": text_part})


## Lines that fit this trigger, robot and situation, with their weights.
## ctx: {"power", "purpose", "mood", "working", ...}
func candidates(trigger: String, robot_id: String, ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in lines:
		if b.trigger != trigger or not (b.robot == "any" or b.robot == robot_id):
			continue
		var ok := true
		for c in b.conditions:
			if not condition(c, ctx):
				ok = false
				break
		if ok:
			var w := CONDITION_WEIGHT if not b.conditions.is_empty() else 1.0
			if b.robot == robot_id:
				w *= 1.5   # its own lines over generic ones
			out.append({"text": b.text, "weight": w})
	return out


static func condition(name: String, ctx: Dictionary) -> bool:
	match name:
		"low_power": return float(ctx.get("power", 1.0)) < 0.3
		"full_power": return float(ctx.get("power", 0.0)) > 0.85
		"low_purpose": return float(ctx.get("purpose", 1.0)) < 0.3
		"restless": return ctx.get("mood", "") == "restless"
		"uneasy": return ctx.get("mood", "") == "uneasy"
		"content": return ctx.get("mood", "") == "content"
		"working": return bool(ctx.get("working", false))
		"idle": return not bool(ctx.get("working", false))
	push_warning("barks.txt: unknown condition '%s'" % name)
	return false


## Fills {placeholders} from ctx.
static func fill(text: String, ctx: Dictionary) -> String:
	var out := text
	for k in ctx:
		var v = ctx[k]
		if v is float:
			v = "%d%%" % roundi(v * 100.0) if k in ["power", "purpose"] else str(snappedf(v, 0.1))
		out = out.replace("{%s}" % k, str(v))
	return out

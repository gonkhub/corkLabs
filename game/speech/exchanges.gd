# Exchanges: short conversations between units, written in
# game/speech/exchanges.txt, that only happen when a situation holds: the
# wrench cut off by a jammed gate, Ogre's core coming back, a camera just
# fixed, the waste overflowing... Most of those situations only arise
# because of what the supervisor did or didn't do. Each plays once (or again
# only after its hours), so the robots aren't heard saying the same thing.
#
# Format:  id | once or hours | condition | robot: line // robot: line // ...
# Condition: terms joined by &, ! to negate. Knowledge keys (secret:x,
# ogre_fixed...), and facts:
#   <unit>.idle  .working  .habit:<id>  .seized  .broken  .low_power  .worn
#   .unstable  .holding:<prop>  .in:<room>  .near:<unit> (same room, close)
#   fault:<device>  waste_full  compactor_full  coolant_low  uplink_down
#   pkg:<package>  on_duty
# Every speaker has to be able to talk (not crashed, rebooting, stalled or
# broken). Lines are said a few seconds apart, on camera, like any other.
class_name Exchanges
extends RefCounted

const PATH := "res://game/speech/exchanges.txt"
const NEAR := 25.0

static var _defs: Array[Dictionary] = []


static func defs() -> Array[Dictionary]:
	if _defs.is_empty():
		for row in DataTable.read(PATH, PackedStringArray(["id", "repeat", "condition", "lines"])):
			var lines: Array[Dictionary] = []
			for part in str(row.lines).split("//", false):
				var colon := part.find(":")
				if colon > 0:
					lines.append({"robot": part.substr(0, colon).strip_edges().to_lower(), "text": part.substr(colon + 1).strip_edges()})
			row.lines = lines
			_defs.append(row)
	return _defs


## The robots an exchange needs.
static func speakers(def: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for l in def.lines:
		if not out.has(str(l.robot)):
			out.append(str(l.robot))
	return out


static func can_speak(bot: RobotAgent) -> bool:
	return bot != null and not bot.activity.kind in ["crashed", "rebooting", "stalled", "broken", "link"]


static func check(sim: FacilitySim, condition: String) -> bool:
	for raw in condition.split("&", false):
		var term := raw.strip_edges()
		if term.is_empty():
			continue
		var neg := term.begins_with("!")
		if neg:
			term = term.substr(1)
		if _fact(sim, term) == neg:
			return false
	return true


static func _fact(sim: FacilitySim, term: String) -> bool:
	var plant := sim.get_system("plant") as FacilityPlant
	if term.begins_with("fault:"):
		return plant != null and bool(plant.device(term.trim_prefix("fault:")).get("fault", false))
	match term:
		"waste_full": return plant != null and float(plant.device("pod_waste").value) <= 0.15
		"compactor_full": return plant != null and float(plant.device("compactor").value) <= 0.05
		"coolant_low": return plant != null and plant.coolant < 0.4
		"uplink_down":
			var o := sim.get_system("oversight") as Oversight
			return o != null and o.uplink_down(sim)
		"on_duty":
			var camp := sim.get_system("campaign") as Campaign
			return camp == null or camp.on_duty()
	if term.begins_with("pkg:"):
		var sw := sim.get_system("software") as SoftwareLibrary
		return sw != null and sw.installed(term.trim_prefix("pkg:"))
	var dot := term.find(".")
	if dot > 0:
		var bot := sim.get_system("robot_" + term.substr(0, dot)) as RobotAgent
		if bot == null:
			return false
		var what := term.substr(dot + 1)
		match what:
			"idle": return bot.activity.kind in ["idle", "habit"]
			"working": return bot.activity.kind == "work"
			"seized": return bot.activity.kind == "seized"
			"broken": return bot.activity.kind == "broken"
			"low_power": return bot.power < 0.3
			"worn": return bot.wear > 0.5
			"unstable": return bot.own_will()
		if what.begins_with("habit:"):
			return bot.activity.kind == "habit" and str(bot.activity.get("habit", "")) == what.trim_prefix("habit:")
		if what.begins_with("holding:"):
			var props := sim.get_system("props") as UnitProps
			return props != null and props.held_by(what.trim_prefix("holding:"), bot.robot_id)
		if what.begins_with("in:"):
			return bot.room(sim) == what.trim_prefix("in:")
		if what.begins_with("near:"):
			var other := sim.get_system("robot_" + what.trim_prefix("near:")) as RobotAgent
			return other != null and other.room(sim) == bot.room(sim) and other.world_pos(sim).distance_to(bot.world_pos(sim)) <= NEAR
		return false
	return Story.knows(sim, term)

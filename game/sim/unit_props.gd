# The units' things (sim_id "props"): objects that live somewhere in the
# facility and that a unit can pick up, carry and put down.
#
#   wrench   Hauler's. On the tool rack in the workshop. Hauler needs it for
#            leaks, the freight gate and stuck doors (FacilityPlant KINDS
#            "tool"); it fetches it first, keeps it while it's busy, and
#            puts it back when it's idle. Cut off from it (the freight gate
#            jammed), it asks for Tinker to fetch it through the hatch
#            (UnitRequests "tool"): Tinker fetches it ("fetch:"), then brings
#            it ("bring:").
#   radio    Tinker's: an old radio on the workbench it fiddles with.
#   crate    Ogre's favourite empty crate, in the hangar: it swings it about
#            and sets it down on the other spot.
#
# Each: {"id", "name", "owner" (robot id), "home" (station), "at" (station,
# "" while held), "held_by" (robot id or "")}. Mostly for liveliness; the
# wrench is the one that matters.
class_name UnitProps
extends RefCounted

const DEFS := {
	"wrench": {"name": "Hauler's wrench", "owner": "hauler", "home": "tool_rack"},
	"radio": {"name": "the old radio", "owner": "tinker", "home": "bench"},
	"crate": {"name": "Ogre's crate", "owner": "ogre", "home": "crate_a"},
}
## Ogre's crate has two favourite spots.
const CRATE_SPOTS := ["crate_a", "crate_b"]
const FETCH_WORK := 60.0
const BRING_WORK := 30.0

var sim_id := "props"
var items := {}


func _init() -> void:
	for id in DEFS:
		items[id] = {"id": id, "name": DEFS[id].name, "owner": DEFS[id].owner, "home": DEFS[id].home, "at": DEFS[id].home, "held_by": ""}


func item(id: String) -> Dictionary:
	return items.get(id, {})


func held_by(id: String, robot_id: String) -> bool:
	return str(item(id).get("held_by", "")) == robot_id


## What a unit is holding ("" = nothing).
func holding(robot_id: String) -> String:
	for id in items:
		if str(items[id].held_by) == robot_id:
			return id
	return ""


## Picks it up (from wherever it is).
func take(sim: FacilitySim, id: String, robot_id: String) -> void:
	var it := item(id)
	if it.is_empty():
		return
	it.held_by = robot_id
	it.at = ""
	sim.note("props", "%s picked up %s" % [robot_id.capitalize(), it.name])


## Puts it down at a station.
func put(sim: FacilitySim, id: String, station: String) -> void:
	var it := item(id)
	if it.is_empty():
		return
	var who := str(it.held_by)
	it.held_by = ""
	it.at = station
	sim.note("props", "%s put %s down (%s)" % [who.capitalize() if not who.is_empty() else "Someone", it.name, station])


## Is anyone on their way to fetch it for its owner?
func being_fetched(sim: FacilitySim, id: String) -> bool:
	var board := sim.get_system("work") as WorkBoard
	return board != null and board.open_jobs().any(func(j): return str(j.source).begins_with("fetch:%s" % id) or str(j.source).begins_with("bring:%s" % id))


## Sends Tinker for it, to bring it to `for_robot` (Hauler cut off from its wrench).
func send_for(sim: FacilitySim, id: String, for_robot: String) -> String:
	var it := item(id)
	var board := sim.get_system("work") as WorkBoard
	if it.is_empty() or board == null:
		return "Nothing to fetch."
	if being_fetched(sim, id):
		return "Someone's already on it."
	if str(it.held_by) == for_robot:
		return "It's already got it."
	var where := str(it.at) if not str(it.at).is_empty() else "bench"
	var jid := board.post(sim, "Fetch %s" % it.name, "general", where, FETCH_WORK, 2, "fetch:%s:%s" % [id, for_robot])
	board.request(sim, jid)
	return ""


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	if event_name != "job_done":
		return
	var src := str(data.get("source", ""))
	var by := str(data.get("by", "")).trim_prefix("robot_")
	var bits := src.split(":")
	if bits.size() < 3:
		return
	var board := sim.get_system("work") as WorkBoard
	match bits[0]:
		"fetch":
			take(sim, bits[1], by)
			# Now take it to whoever needs it, where they are.
			var to := sim.get_system("robot_" + bits[2]) as RobotAgent
			var where := str(to.activity.get("station", "")) if to else ""
			if where.is_empty() and to:
				where = to.nearest_station(sim)
			if board and not where.is_empty():
				var jid := board.post(sim, "Bring %s to %s" % [item(bits[1]).name, bits[2].capitalize()], "general", where, BRING_WORK, 2,
					"bring:%s:%s" % [bits[1], bits[2]])
				board.get_job(jid).only = "robot_" + by   # whoever fetched it brings it
				board.request(sim, jid)
		"bring":
			take(sim, bits[1], bits[2])
			var k := sim.get_system("knowledge") as Knowledge
			if k:
				k.learn(sim, "seen_fetch")
			sim.schedule(sim.time(), "alarm", {"prop": bits[1]})   # its owner gets on with it


func sim_tick(_sim: FacilitySim, _dt: float) -> void:
	pass


func sim_save() -> Dictionary:
	return {"items": items.duplicate(true)}


func sim_load(d: Dictionary) -> void:
	var saved: Dictionary = d.get("items", {})
	for id in saved:
		if items.has(id):
			items[id] = saved[id].duplicate()


func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	var lines := PackedStringArray(["PROPS"])
	for id in items:
		lines.append("  %s: %s" % [items[id].name, ("held by " + str(items[id].held_by)) if not str(items[id].held_by).is_empty() else "at " + str(items[id].at)])
	return lines

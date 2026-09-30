# The facility's floor plan as the simulation sees it: rails, and stations
# at points along them (in meters from the rail's start, the same numbers a
# RailRider's `progress` uses). A robot can only reach stations on its own
# rail.
#
# The 3D world must match: a rail here called "tinker_loop" with length 30.27
# is the Path3D the Tinker rides in the scene (tests/test_robot_behaviour.gd
# checks the lengths agree).
#
# It's a system (sim_id "layout") only so other systems can find it with
# sim.get_system("layout"). It never changes, so it isn't saved.
class_name FacilityLayout
extends RefCounted

const NO_RAIL := {"length": 0.0, "loop": false}

var sim_id := "layout"

# rail id -> {"length": float, "loop": bool}
var rails := {}
# station id -> {"id", "rail", "pos", "kind": "dock"/"work", "name"}
var stations := {}


func add_rail(id: String, length: float, loop := false) -> void:
	rails[id] = {"length": length, "loop": loop}


func add_station(id: String, rail: String, pos: float, kind: String, display_name: String) -> void:
	assert(rails.has(rail), "unknown rail " + rail)
	stations[id] = {"id": id, "rail": rail, "pos": pos, "kind": kind, "name": display_name}


func station(id: String) -> Dictionary:
	return stations.get(id, {})


## Station ids on `rail`, in id order (so every run lists them the same way).
func stations_on(rail: String, kind := "") -> Array[String]:
	var out: Array[String] = []
	for id in stations:
		var s: Dictionary = stations[id]
		if s.rail == rail and (kind.is_empty() or s.kind == kind):
			out.append(id)
	out.sort()
	return out


## Distance along `rail` from a to b, the short way round on a loop.
func distance(rail: String, a: float, b: float) -> float:
	return absf(signed_offset(rail, a, b))


## How far to move from a to reach b (negative = backwards), the short way
## round on a loop.
func signed_offset(rail: String, a: float, b: float) -> float:
	var d := b - a
	var r: Dictionary = rails.get(rail, NO_RAIL)
	if r.loop and r.length > 0.0:
		d = wrapf(d, -r.length * 0.5, r.length * 0.5)
	return d


func wrap(rail: String, pos: float) -> float:
	var r: Dictionary = rails.get(rail, NO_RAIL)
	if r.loop and r.length > 0.0:
		return wrapf(pos, 0.0, r.length)
	return clampf(pos, 0.0, r.length)


func rail_length(rail: String) -> float:
	return float(rails.get(rail, NO_RAIL).length)


func sim_tick(_sim: FacilitySim, _dt: float) -> void:
	pass

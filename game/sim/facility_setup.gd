# The standard facility: which systems exist and how the floor is laid out.
# Every gameplay scene (the demo, the corkLabs desktop) starts its session
# with FacilitySetup.systems(), so they all run the same facility.
#
# The rail ids and lengths here must match the Path3D rails in the 3D world
# (game/demo_facility.tscn): tests/test_robot_behaviour.gd checks it.
class_name FacilitySetup
extends RefCounted

const TINKER_RAIL := "tinker_loop"
const HAULER_RAIL := "hauler_line"


static func layout() -> FacilityLayout:
	var l := FacilityLayout.new()
	# Tinker's loop runs round the room; its back straight passes the pods.
	l.add_rail(TINKER_RAIL, 30.27, true)
	l.add_station("t_dock", TINKER_RAIL, 18.0, "dock", "Tinker dock")
	l.add_station("pods_a", TINKER_RAIL, 2.0, "work", "Pods 1-2")
	l.add_station("pods_b", TINKER_RAIL, 6.0, "work", "Pods 3-4")
	l.add_station("relay", TINKER_RAIL, 12.0, "work", "Relay panel")
	l.add_station("bench", TINKER_RAIL, 25.0, "work", "Workbench")
	# Hauler's straight rail runs down the middle of the room.
	l.add_rail(HAULER_RAIL, 8.0, false)
	l.add_station("h_dock", HAULER_RAIL, 0.4, "dock", "Hauler dock")
	l.add_station("bay_1", HAULER_RAIL, 2.5, "work", "Bay 1")
	l.add_station("bay_2", HAULER_RAIL, 5.0, "work", "Bay 2")
	l.add_station("bay_3", HAULER_RAIL, 7.5, "work", "Bay 3")
	return l


## A fresh set of every facility system. Pass to Facility.start_session().
static func systems() -> Array:
	var l := layout()
	var board := WorkBoard.new()
	board.starter_jobs = 3
	return [
		l,
		ShiftSchedule.new(),
		board,
		RobotAgent.new("tinker", TINKER_RAIL, null, l.station("t_dock").pos),
		RobotAgent.new("hauler", HAULER_RAIL, null, l.station("h_dock").pos),
	]


## The robots in a running facility, in id order.
static func robots(sim: FacilitySim) -> Array[RobotAgent]:
	var out: Array[RobotAgent] = []
	for id in sim.system_ids():
		var a := sim.get_system(id) as RobotAgent
		if a:
			out.append(a)
	return out

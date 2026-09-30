# The standard facility: which systems exist, and the floor plan (rooms,
# rail network, stations, cameras). Every gameplay scene (the corkLabs
# desktop) starts its session with FacilitySetup.systems(), and the 3D world
# (FacilityWorld) builds itself from the same layout(), so the simulation and
# what you see on camera always agree.
#
# Coordinates: meters, x to the east, z to the south, y up; the main hall is
# centred on the origin.
#
#   ROOM          SIZE        WHAT'S IN IT
#   Main hall     80 x 50 m   big rail loop + a spine; the three bays
#   Pod bay       24 x 20 m   north of the hall; the pods
#   Workshop      14 x 16 m   east; relay panel, workbench
#   Maintenance   12 x 12 m   west; both docks
#
#   PASSAGES (the caveats)
#   Pod bay door       hall - pod bay     wide: everyone fits
#   Pod bay duct       hall - pod bay     narrow (1.0 m): Tinker's shortcut, Hauler can't fit
#   Workshop hatch     hall - workshop    narrow (1.2 m): Tinker only
#   Freight gate       hall - workshop    wide, but it JAMS (a plant fault) and blocks the route;
#                                         Hauler's only way into the workshop
#   Dock door          hall - maintenance wide; the only way to the docks
class_name FacilitySetup
extends RefCounted


static func layout() -> FacilityLayout:
	var l := FacilityLayout.new()
	l.add_room("hall", "Main hall", Rect2(-40, -25, 80, 50), 16.0, 11.0)
	l.add_room("pod_bay", "Pod bay", Rect2(-12, -45, 24, 20), 8.0, 6.0)
	l.add_room("workshop", "Workshop", Rect2(40, -8, 14, 16), 6.0, 4.5)
	l.add_room("maintenance", "Maintenance", Rect2(-52, -6, 12, 12), 7.0, 5.5)

	# Main hall: a big loop round the room, and a spine across the middle.
	l.add_node("h_nw", "hall", -30, -15)
	l.add_node("h_n", "hall", 0, -15)
	l.add_node("h_ne", "hall", 30, -15)
	l.add_node("h_e", "hall", 30, 0)
	l.add_node("h_se", "hall", 30, 15)
	l.add_node("h_sw", "hall", -30, 15)
	l.add_node("h_w", "hall", -30, 0)
	l.add_node("h_c", "hall", 0, 0)
	l.add_segment("hall_n1", "h_nw", "h_n", "Hall north rail (west)")
	l.add_segment("hall_n2", "h_n", "h_ne", "Hall north rail (east)")
	l.add_segment("hall_e1", "h_ne", "h_e", "Hall east rail (north)")
	l.add_segment("hall_e2", "h_e", "h_se", "Hall east rail (south)")
	l.add_segment("hall_s", "h_se", "h_sw", "Hall south rail")
	l.add_segment("hall_w1", "h_sw", "h_w", "Hall west rail (south)")
	l.add_segment("hall_w2", "h_w", "h_nw", "Hall west rail (north)")
	l.add_segment("spine_w", "h_w", "h_c", "Spine (west)")
	l.add_segment("spine_e", "h_c", "h_e", "Spine (east)")
	l.add_segment("spine_n", "h_c", "h_n", "Spine (north)")

	# Pod bay: a small loop past the pods.
	l.add_node("p_s", "pod_bay", 0, -30)
	l.add_node("p_w", "pod_bay", -8, -38)
	l.add_node("p_e", "pod_bay", 8, -38)
	l.add_segment("pod_w", "p_s", "p_w", "Pod bay rail (west)")
	l.add_segment("pod_n", "p_w", "p_e", "Pod row rail")
	l.add_segment("pod_e", "p_e", "p_s", "Pod bay rail (east)")

	# Workshop: a small triangle.
	l.add_node("w_w", "workshop", 44, 0)
	l.add_node("w_n", "workshop", 50, -5)
	l.add_node("w_s", "workshop", 50, 5)
	l.add_segment("ws_bench", "w_w", "w_n", "Workshop rail (bench)")
	l.add_segment("ws_back", "w_n", "w_s", "Workshop rail (relay)")
	l.add_segment("ws_front", "w_s", "w_w", "Workshop rail (front)")

	# Maintenance: one straight rail with the docks.
	l.add_node("m_e", "maintenance", -44, 0)
	l.add_node("m_w", "maintenance", -50, 0)
	l.add_segment("maint", "m_e", "m_w", "Maintenance rail")

	# Passages between rooms, with their caveats.
	l.add_segment("pod_door", "h_n", "p_s", "Pod bay door", 3.0)
	l.add_segment("pod_duct", "h_nw", "p_w", "Pod bay duct", 1.0, 0.7)
	l.add_segment("ws_hatch", "h_e", "w_w", "Workshop hatch", 1.2)
	l.add_segment("freight_gate", "h_se", "w_s", "Freight gate", 3.5, 0.6)
	l.add_segment("dock_door", "h_w", "m_e", "Dock door", 3.0)

	# Stations.
	l.add_station("t_dock", "maint", 2.0, "dock", "Tinker dock")
	l.add_station("h_dock", "maint", 4.5, "dock", "Hauler dock")
	l.add_station("pods_a", "pod_n", 4.0, "work", "Pods 1-2")
	l.add_station("pods_b", "pod_n", 12.0, "work", "Pods 3-4")
	l.add_station("bay_1", "hall_s", 45.0, "work", "Bay 1")
	l.add_station("bay_2", "hall_s", 30.0, "work", "Bay 2")
	l.add_station("bay_3", "hall_s", 15.0, "work", "Bay 3")
	l.add_station("relay", "ws_back", 3.0, "work", "Relay panel")
	l.add_station("bench", "ws_bench", 3.5, "work", "Workbench")
	l.add_station("gate", "hall_e2", 13.0, "work", "Freight gate controls")
	return l


## Security cameras: {"name", "room", "pos", "look", "track": robot id or ""}.
## ("track" makes a camera follow a robot while it's in the camera's room.)
static func cameras() -> Array[Dictionary]:
	return [
		{"name": "Main hall (south-east)", "room": "hall", "pos": Vector3(38, 13, 23), "look": Vector3(0, 2, 0), "track": ""},
		{"name": "Main hall (north-west)", "room": "hall", "pos": Vector3(-38, 13, -23), "look": Vector3(0, 2, 5), "track": ""},
		{"name": "Pod bay", "room": "pod_bay", "pos": Vector3(10, 7, -27), "look": Vector3(-2, 1.5, -40), "track": ""},
		{"name": "Workshop", "room": "workshop", "pos": Vector3(41, 5.5, 7), "look": Vector3(50, 1, -3), "track": ""},
		{"name": "Maintenance", "room": "maintenance", "pos": Vector3(-41, 6.5, 5), "look": Vector3(-48, 2, -1), "track": ""},
	]


## Where each robot starts in a brand-new facility (a station id).
const START_STATIONS := {"tinker": "t_dock", "hauler": "h_dock"}


## A fresh set of every facility system. Pass to Facility.start_session().
static func systems() -> Array:
	var l := layout()
	var out: Array = [l, ShiftSchedule.new(), WorkBoard.new(), FacilityPlant.new(), RobotChatter.new(),
		Requisitions.new(), SoftwareLibrary.new(), CorkHQ.new()]
	for id in ["tinker", "hauler"]:
		var st := l.station(START_STATIONS[id])
		out.append(RobotAgent.new(id, null, st.segment, st.offset))
	return out


## The robots in a running facility, in id order.
static func robots(sim: FacilitySim) -> Array[RobotAgent]:
	var out: Array[RobotAgent] = []
	for id in sim.system_ids():
		var a := sim.get_system(id) as RobotAgent
		if a:
			out.append(a)
	return out

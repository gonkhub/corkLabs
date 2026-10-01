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
#   Hangar        50 x 40 m   south; Ogre hangs from the middle of its ceiling
#                             and works everything its crane reaches (the
#                             loading bay, the deep stacks, the coolant feed,
#                             the waste compactor). It never leaves.
#
#   PASSAGES (the caveats)
#   Pod bay door       hall - pod bay     wide: everyone fits
#   Pod bay duct       hall - pod bay     narrow (1.0 m): Tinker's shortcut, Hauler can't fit
#   Workshop hatch     hall - workshop    narrow (1.2 m): Tinker only
#   Freight gate       hall - workshop    wide, but it JAMS (a plant fault) and blocks the route;
#                                         Hauler's only way into the workshop
#   Dock door          hall - maintenance wide; the only way to the docks
#   Hangar door        hall - hangar      wide: rail robots can reach the loading bay
class_name FacilitySetup
extends RefCounted


static func layout() -> FacilityLayout:
	var l := FacilityLayout.new()
	l.add_room("hall", "Main hall", Rect2(-40, -25, 80, 50), 16.0, 11.0)
	l.add_room("pod_bay", "Pod bay", Rect2(-12, -45, 24, 20), 8.0, 6.0)
	l.add_room("workshop", "Workshop", Rect2(40, -8, 14, 16), 6.0, 4.5)
	l.add_room("maintenance", "Maintenance", Rect2(-52, -6, 12, 12), 7.0, 5.5)
	l.add_room("hangar", "Hangar", Rect2(-40, 25, 50, 40), 26.0, 11.0)

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

	# Hangar: a short loading rail inside the door. Ogre is mounted on a pad
	# at the centre of the ceiling; the deep stacks are a pad on the floor
	# that only its crane reaches.
	l.add_node("g_door", "hangar", -30, 31)
	l.add_node("g_e", "hangar", -2, 31)
	l.add_segment("hangar_rail", "g_door", "g_e", "Hangar loading rail")
	l.add_pad("ogre_mount", "hangar", -15, 45, "Ogre's mount", 23.0)
	l.add_pad("deep_stacks", "hangar", -2, 56, "Deep stacks")
	l.add_pad("crate_pad_a", "hangar", -8, 52, "Ogre's crate spot")
	l.add_pad("crate_pad_b", "hangar", -24, 54, "Ogre's other crate spot")
	l.add_pad("compactor_pad", "hangar", 2, 41, "Waste compactor")

	# Passages between rooms, with their caveats.
	l.add_segment("pod_door", "h_n", "p_s", "Pod bay door", 3.0)
	l.add_segment("pod_duct", "h_nw", "p_w", "Pod bay duct", 1.0, 0.7)
	l.add_segment("ws_hatch", "h_e", "w_w", "Workshop hatch", 1.2)
	l.add_segment("freight_gate", "h_se", "w_s", "Freight gate", 3.5, 0.6)
	l.add_segment("dock_door", "h_w", "m_e", "Dock door", 3.0)
	l.add_segment("hangar_door", "h_sw", "g_door", "Hangar door", 4.0)

	# Stations.
	l.add_station("t_dock", "maint", 2.0, "dock", "Tinker dock")
	l.add_station("h_dock", "maint", 4.5, "dock", "Hauler dock")
	l.add_station("pods_a", "pod_n", 4.0, "work", "Pods 1-2")
	l.add_station("pods_b", "pod_n", 12.0, "work", "Pods 3-4")
	l.add_station("waste_bins", "pod_e", 5.0, "work", "Pod waste bins")
	l.add_station("bay_1", "hall_s", 45.0, "work", "Bay 1")
	l.add_station("bay_2", "hall_s", 30.0, "work", "Bay 2")
	l.add_station("bay_3", "hall_s", 15.0, "work", "Bay 3")
	l.add_station("relay", "ws_back", 3.0, "work", "Relay panel")
	l.add_station("bench", "ws_bench", 3.5, "work", "Workbench")
	l.add_station("gate", "hall_e2", 13.0, "work", "Freight gate controls")
	l.add_station("o_mains", "ogre_mount", 0.5, "dock", "Ogre's mains coupling")
	l.add_station("loading", "hangar_rail", 12.0, "work", "Hangar loading bay")
	l.add_station("pod_door_ctl", "hall_n1", 27.0, "work", "Pod bay door controls")
	l.add_station("dock_door_ctl", "hall_w1", 13.0, "work", "Dock door controls")
	l.add_station("hangar_door_ctl", "hall_s", 57.0, "work", "Hangar door controls")
	l.add_station("uplink", "ws_front", 3.0, "work", "corkHQ uplink relay")
	l.add_station("stacks", "deep_stacks", 0.5, "work", "Deep stacks")
	l.add_station("coolant_feed", "hangar_rail", 4.0, "work", "Coolant feed")
	l.add_station("ogre_service", "hangar_rail", 16.0, "work", "Under Ogre (service point)")
	l.add_station("tool_rack", "ws_back", 7.0, "work", "Tool rack")
	l.add_station("crate_a", "crate_pad_a", 0.5, "work", "Ogre's crate spot")
	l.add_station("crate_b", "crate_pad_b", 0.5, "work", "Ogre's other crate spot")
	l.add_station("compactor", "compactor_pad", 0.5, "work", "Waste compactor")
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
		{"name": "Hangar", "room": "hangar", "pos": Vector3(8, 21, 27), "look": Vector3(-15, 7, 47), "track": ""},
		{"name": "Hangar (floor)", "room": "hangar", "pos": Vector3(-37, 3, 62), "look": Vector3(-15, 12, 44), "track": ""},
	]


## Where each robot starts in a brand-new facility (a station id).
const START_STATIONS := {"tinker": "t_dock", "hauler": "h_dock", "ogre": "o_mains"}


## A fresh set of every facility system. Pass to Facility.start_session().
static func systems() -> Array:
	var l := layout()
	# The supervisor works the Day shift (06:00-14:00); the Campaign runs
	# the nights in between without them.
	var shifts := ShiftSchedule.new()
	shifts.starts.assign([Campaign.SHIFT_START_HOUR])
	shifts.names.assign(["Day"])
	var out: Array = [l, shifts, WorkBoard.new(), FacilityPlant.new(), RobotChatter.new(),
		Requisitions.new(), SoftwareLibrary.new(), CorkHQ.new(), Knowledge.new(), Oversight.new(), Campaign.new(),
		Directives.new(), UnitRequests.new(), Forms.new(), UnitProps.new()]
	for id in START_STATIONS:
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

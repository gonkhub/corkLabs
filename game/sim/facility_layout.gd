# The facility's floor plan as the simulation sees it: rooms, and a rail
# NETWORK running through them. Robots ride the rails and plan routes across
# the network to wherever they're going.
#
#   rooms      name + floor rectangle (x/z, meters) + height. Just space for now.
#   nodes      junctions / corners of the rail network, at 3D points.
#   segments   straight pieces of rail between two nodes. Each has CAVEATS:
#                clearance   widest robot that fits (a narrow hatch or duct).
#                            Hauler is too big for some routes.
#                blocked     closed for now (a jammed gate, debris...), with
#                            a reason. Robots route around it, or can't go.
#                speed       travel speed factor (a slow lift, a steep duct).
#              A segment that joins two rooms is a "passage" (a door, gate,
#              duct...). Rooms can be joined by several passages.
#   stations   named places along a segment (docks, pods, bays, the bench).
#   pads       spots on the floor with no rail to them (add_pad): a segment
#              nobody can ride (clearance 0). Only a stationary robot's reach
#              gets there; Ogre is mounted on one.
#
# A position on the network is a segment id + an offset in meters from the
# segment's first node (`a`). plan() finds the quickest route between two
# positions for a robot of a given width, as a list of "legs" to ride.
#
# It's a system (sim_id "layout") so other systems can find it; only the
# blocked state changes, and that's saved.
class_name FacilityLayout
extends RefCounted

const NO_ROUTE := {}

var sim_id := "layout"

# room id -> {"id", "name", "rect": Rect2 (x, z, width, depth), "height", "rail_height"}
var rooms := {}
# node id -> {"id", "pos": Vector3, "room"}
var nodes := {}
# segment id -> {"id", "a", "b", "length", "room" ("" for a passage), "name",
#                "clearance", "speed", "blocked", "block_reason"}
var segments := {}
# station id -> {"id", "segment", "offset", "kind": "dock"/"work", "name", "room"}
var stations := {}

var _links := {}   # node id -> [segment ids]
## Goes up whenever a route opens or closes (so cached route costs know they're stale).
var version := 0


# --- Building ------------------------------------------------------------------------

func add_room(id: String, display_name: String, rect: Rect2, height: float, rail_height: float) -> void:
	rooms[id] = {"id": id, "name": display_name, "rect": rect, "height": height, "rail_height": rail_height}


## A junction at (x, z) in `room`, at that room's rail height (or `y` if given).
func add_node(id: String, room: String, x: float, z: float, y := -1.0) -> void:
	assert(rooms.has(room), "unknown room " + room)
	var h: float = y if y >= 0.0 else rooms[room].rail_height
	nodes[id] = {"id": id, "pos": Vector3(x, h, z), "room": room}
	_links[id] = []


## A straight piece of rail from node a to node b. Rails inside one room get
## that room; rails joining two rooms are passages (room "").
func add_segment(id: String, a: String, b: String, display_name := "", clearance := INF, speed := 1.0) -> void:
	assert(nodes.has(a) and nodes.has(b), "unknown node on " + id)
	var ra: String = nodes[a].room
	var rb: String = nodes[b].room
	segments[id] = {"id": id, "a": a, "b": b, "length": nodes[a].pos.distance_to(nodes[b].pos),
		"room": ra if ra == rb else "", "name": display_name if not display_name.is_empty() else id,
		"clearance": clearance, "speed": speed, "blocked": false, "block_reason": ""}
	_links[a].append(id)
	_links[b].append(id)


## A spot with no rail to it, at (x, z) in `room` (at height `y` if given):
## a tiny segment `id` that no rail robot can use and that isn't drawn as
## rail. Put stations on it (offset 0.5 = its middle).
func add_pad(id: String, room: String, x: float, z: float, display_name: String, y := -1.0) -> void:
	add_node(id + "_a", room, x - 0.5, z, y)
	add_node(id + "_b", room, x + 0.5, z, y)
	add_segment(id, id + "_a", id + "_b", display_name, 0.0)
	segments[id].pad = true


func is_pad(seg: String) -> bool:
	return segments.get(seg, {}).get("pad", false)


func add_station(id: String, segment: String, offset: float, kind: String, display_name: String) -> void:
	assert(segments.has(segment), "unknown segment " + segment)
	var s: Dictionary = segments[segment]
	stations[id] = {"id": id, "segment": segment, "offset": clampf(offset, 0.0, s.length), "kind": kind,
		"name": display_name, "room": s.room if not s.room.is_empty() else nodes[s.a].room}


# --- Queries -----------------------------------------------------------------------------

func station(id: String) -> Dictionary:
	return stations.get(id, {})


func segment(id: String) -> Dictionary:
	return segments.get(id, {})


## Station ids of a kind ("" = all), in id order.
func stations_of(kind := "") -> Array[String]:
	var out: Array[String] = []
	for id in stations:
		if kind.is_empty() or stations[id].kind == kind:
			out.append(id)
	out.sort()
	return out


## Passages (segments joining two rooms), in id order.
func passages() -> Array[String]:
	var out: Array[String] = []
	for id in segments:
		if segments[id].room.is_empty():
			out.append(id)
	out.sort()
	return out


## Point in the world for a position on the network.
func world_pos(seg: String, offset: float) -> Vector3:
	var s: Dictionary = segments.get(seg, {})
	if s.is_empty():
		return Vector3.ZERO
	var t := clampf(offset / maxf(s.length, 0.001), 0.0, 1.0)
	return nodes[s.a].pos.lerp(nodes[s.b].pos, t)


func station_world_pos(id: String) -> Vector3:
	var st := station(id)
	return world_pos(st.segment, st.offset) if not st.is_empty() else Vector3.ZERO


## Which room a position is in (the room at the nearer end of a passage).
func room_at(seg: String, offset: float) -> String:
	var s: Dictionary = segments.get(seg, {})
	if s.is_empty():
		return ""
	if not s.room.is_empty():
		return s.room
	return nodes[s.a].room if offset < s.length * 0.5 else nodes[s.b].room


## Can a robot this wide use this segment right now?
func passable(seg: String, width: float, ignore_blocks := false) -> bool:
	var s: Dictionary = segments.get(seg, {})
	return not s.is_empty() and width <= s.clearance and (ignore_blocks or not s.blocked)


## Why a robot this wide can't use a segment ("" if it can).
func why_not(seg: String, width: float) -> String:
	var s: Dictionary = segments.get(seg, {})
	if s.is_empty():
		return "no such rail"
	if width > s.clearance:
		return "too narrow (%.1f m clearance)" % s.clearance
	if s.blocked:
		return "blocked: " + s.block_reason
	return ""


# --- Routes ---------------------------------------------------------------------------------

## Every node's travel cost from a position, for a robot `width` meters
## wide (Dijkstra). Use it with reach() to price many destinations at once
## (a robot scoring jobs), or let plan() do it for one.
## The robot's own segment is always usable (it's already on it).
func field(from_seg: String, from_off: float, width: float, ignore_blocks := false) -> Dictionary:
	var f := {"seg": from_seg, "off": from_off, "width": width, "ignore": ignore_blocks,
		"dist": {}, "len": {}, "prev": {}}
	var fs: Dictionary = segments.get(from_seg, {})
	if fs.is_empty():
		return f
	var dist: Dictionary = f.dist
	var lens: Dictionary = f.len
	var prev: Dictionary = f.prev
	dist[fs.a] = from_off / fs.speed
	dist[fs.b] = (fs.length - from_off) / fs.speed
	lens[fs.a] = from_off
	lens[fs.b] = fs.length - from_off
	prev[fs.a] = ["", from_seg]
	prev[fs.b] = ["", from_seg]
	var done := {}
	while true:
		var best := ""
		var best_d := INF
		for n in dist:
			if not done.has(n) and dist[n] < best_d:
				best_d = dist[n]
				best = n
		if best.is_empty():
			break
		done[best] = true
		for sid in _links[best]:
			if sid == from_seg or not passable(sid, width, ignore_blocks):
				continue
			var s: Dictionary = segments[sid]
			var other: String = s.b if s.a == best else s.a
			var nd: float = best_d + s.length / s.speed
			if nd < float(dist.get(other, INF)):
				dist[other] = nd
				lens[other] = float(lens[best]) + s.length
				prev[other] = [best, sid]
	return f


## Cost of getting from the field's start to (to_seg, to_off):
## {"cost", "length", "end_node"} or {} if there's no way.
func reach(f: Dictionary, to_seg: String, to_off: float) -> Dictionary:
	var ts: Dictionary = segments.get(to_seg, {})
	if ts.is_empty() or not segments.has(f.seg):
		return NO_ROUTE
	if to_seg == f.seg:
		var d := absf(to_off - float(f.off))
		return {"cost": d / ts.speed, "length": d, "end_node": ""}
	if not passable(to_seg, f.width, f.ignore):
		return NO_ROUTE
	var via_a: float = float(f.dist.get(ts.a, INF)) + to_off / ts.speed
	var via_b: float = float(f.dist.get(ts.b, INF)) + (ts.length - to_off) / ts.speed
	if is_inf(via_a) and is_inf(via_b):
		return NO_ROUTE
	if via_a <= via_b:
		return {"cost": via_a, "length": float(f.len[ts.a]) + to_off, "end_node": ts.a}
	return {"cost": via_b, "length": float(f.len[ts.b]) + ts.length - to_off, "end_node": ts.b}


func reach_station(f: Dictionary, station_id: String) -> Dictionary:
	var st := station(station_id)
	return reach(f, st.segment, st.offset) if not st.is_empty() else NO_ROUTE


## The quickest route from one position to another for a robot `width`
## meters wide. Returns {} if there's no way through, else
## {"cost": seconds at speed 1, "length": meters, "legs": [{"seg", "from", "to"}...]}.
func plan(from_seg: String, from_off: float, to_seg: String, to_off: float, width: float, ignore_blocks := false) -> Dictionary:
	if not segments.has(from_seg) or not segments.has(to_seg):
		return NO_ROUTE
	var f := field(from_seg, from_off, width, ignore_blocks)
	var r := reach(f, to_seg, to_off)
	if r.is_empty():
		return NO_ROUTE
	if r.end_node == "":
		return {"cost": r.cost, "length": r.length, "legs": [{"seg": from_seg, "from": from_off, "to": to_off}]}
	var ts: Dictionary = segments[to_seg]
	var legs: Array = [{"seg": to_seg, "from": 0.0 if r.end_node == ts.a else ts.length, "to": to_off}]
	var n: String = r.end_node
	while true:
		var p: Array = f.prev[n]
		var sid: String = p[1]
		var s: Dictionary = segments[sid]
		var at_n: float = 0.0 if s.a == n else s.length
		if p[0] == "":
			legs.push_front({"seg": sid, "from": from_off, "to": at_n})
			break
		var at_p: float = 0.0 if s.a == p[0] else s.length
		legs.push_front({"seg": sid, "from": at_p, "to": at_n})
		n = p[0]
	return {"cost": r.cost, "length": r.length, "legs": legs}


## Route to a station, or {}.
func plan_to_station(from_seg: String, from_off: float, station_id: String, width: float) -> Dictionary:
	var st := station(station_id)
	if st.is_empty():
		return NO_ROUTE
	return plan(from_seg, from_off, st.segment, st.offset, width)


# --- Blocking (saved) ---------------------------------------------------------------------

## Closes or reopens a segment. Journals it; robots re-plan on their next step.
func set_blocked(sim: FacilitySim, seg: String, blocked: bool, reason := "") -> void:
	var s: Dictionary = segments.get(seg, {})
	if s.is_empty() or s.blocked == blocked:
		return
	s.blocked = blocked
	s.block_reason = reason if blocked else ""
	version += 1
	if sim:
		sim.note("route", ("%s is BLOCKED: %s" % [s.name, reason]) if blocked else ("%s is open again" % s.name))
		sim.schedule(sim.time(), "route_changed", {"segment": seg, "blocked": blocked})


func sim_tick(_sim: FacilitySim, _dt: float) -> void:
	pass


func sim_save() -> Dictionary:
	var blocked := {}
	for id in segments:
		if segments[id].blocked:
			blocked[id] = segments[id].block_reason
	return {"blocked": blocked}


func sim_load(d: Dictionary) -> void:
	var blocked: Dictionary = d.get("blocked", {})
	for id in segments:
		segments[id].blocked = blocked.has(id)
		segments[id].block_reason = str(blocked.get(id, ""))
	version += 1

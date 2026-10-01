# The 3D facility, built from the same floor plan the simulation uses
# (FacilitySetup.layout()): rooms (floor, walls with openings where passages
# go through), the rail network, the robots, the plant's props and security
# cameras. Change the layout and the world follows; nothing here is placed by
# hand.
#
# There are no lights. The facility was built for robots, and robots don't
# need to see: no lamps, no windows, no washrooms or water fountains. What
# light there is comes from the machines themselves (status lamps, charging
# docks, the robots' own LEDs); the cameras see the rest in night vision
# (CCTVFeed). The Environment keeps a trace of ambient light, so shapes are
# only just there on a normal feed.
#
# It shows whatever Facility session is running (robots follow their sim
# selves via RobotView, props show the plant, blocked passages show a closed
# shutter), but never starts one: the corkLabs desktop does.
#
# Placeholder shapes everywhere: the point is the framework. Real models can
# replace any piece later.
#
# PICKING. Camera feeds let the supervisor point at things: a robot, a device
# (FacilityProps.pick_nodes), a passage door, a camera's housing, the
# workbench. pick() casts a ray from a feed's camera against the bounding
# boxes of each thing's meshes (things in other rooms don't count: walls)
# and returns its id ("robot:tinker", "pipe_2", "door_dock", "cam_3",
# "bench"); highlight() outlines it (an inverted-hull silhouette plus a faint
# tint, drawn as each mesh's material_overlay).
class_name FacilityWorld
extends Node3D

const RAIL_COLOR := Color(0.42, 0.43, 0.45)
const WALL_COLOR := Color(0.23, 0.24, 0.25)
const FLOOR_COLOR := Color(0.15, 0.16, 0.17)
const WALL_THICKNESS := 0.4
const HAZARD := Color(0.95, 0.75, 0.1)

var layout: FacilityLayout
var cameras: Array[SecurityCamera] = []
## Room id of each camera (same order as `cameras`): speech shows only for
## robots in the camera's room.
var camera_rooms: Array[String] = []
var views := {}            # robot id -> RobotView
var props: FacilityProps
var _shutters := {}        # passage segment id -> MeshInstance3D (shown while blocked)
var _trackers := {}        # camera index -> robot id it follows
## Pickable things built here (doors, camera housings): id -> [Node3D].
var _pick_nodes := {}
var _pick_rooms := {}      # id -> room ("" = seen from either side)
var _highlighted := ""
static var _outline: StandardMaterial3D
## Each camera's housing is on its own render layer, so its own feed doesn't see it.
const HOUSING_LAYER := 10
## The camera you're listening through (its feed is the 3D audio listener),
## or -1 for none. Set by the Cameras app; FacilitySound uses its room.
var listener_cam := -1
## Sounds started with play_sound() / attach_sound() (the Terminal's `sound`).
var auditions: Array[FacilitySound] = []


func _ready() -> void:
	layout = FacilitySetup.layout()
	for id in layout.rooms:
		_build_room(id)
	_build_rails()
	for id in FacilitySetup.START_STATIONS:
		_add_view(id)
	if Facility.running:
		sync_views()
	props = FacilityProps.new()
	props.name = "Props"
	add_child(props)
	props.build(layout)
	_build_cameras()
	_link_doors()


func _add_view(id: String) -> void:
	var view := RobotView.new()
	view.setup(id, layout)
	add_child(view)
	views[id] = view


## Units activated during play get a 3D robot too.
func sync_views() -> void:
	for bot in FacilitySetup.robots(Facility.sim):
		if not views.has(bot.robot_id):
			_add_view(bot.robot_id)


func _process(_delta: float) -> void:
	if not Facility.running:
		return
	var live := Facility.sim.get_system("layout") as FacilityLayout
	if live == null:
		return
	if views.size() != FacilitySetup.robots(Facility.sim).size():
		sync_views()
	for sid in _shutters:
		(_shutters[sid] as Node3D).visible = live.segment(sid).get("blocked", false)
	for i in _trackers:
		cameras[i].target_in_view = robot_room(_trackers[i]) == camera_rooms[i]


## Display names for the security cameras, same order as `cameras`.
func camera_names() -> PackedStringArray:
	var out := PackedStringArray()
	for c in cameras:
		out.append(c.display_name)
	return out


## Where a robot's words float (just above it), in world space.
func speech_anchor(robot_id: String) -> Vector3:
	var v: RobotView = views.get(robot_id)
	return v.speech_anchor() if v else Vector3.ZERO


## The room a robot is shown in right now.
func robot_room(robot_id: String) -> String:
	var v: RobotView = views.get(robot_id)
	return layout.room_at(v.seg, v.off) if v else ""


## The room of the camera you're listening through ("" if none).
func listen_room() -> String:
	return camera_rooms[listener_cam] if listener_cam >= 0 and listener_cam < camera_rooms.size() else ""


## Which room a point is in (by floor plan; "" if it's in none).
func room_at_point(p: Vector3) -> String:
	for id in layout.rooms:
		if (layout.rooms[id].rect as Rect2).has_point(Vector2(p.x, p.z)):
			return id
	return ""


# --- Sound auditions ------------------------------------------------------------------------

## Plays a sound at a point in the facility. `loop` repeats it until
## stop_auditions(); otherwise it plays once (a looping stream once through).
func play_sound(stream: AudioStream, at: Vector3, loop := false) -> FacilitySound:
	var s := _audition(stream, loop)
	s.position = at
	add_child(s)
	s.play()
	return s


## Plays a sound on a robot: it rides along and changes rooms with it.
func attach_sound(stream: AudioStream, robot_id: String, loop := false) -> FacilitySound:
	var v: RobotView = views.get(robot_id)
	if v == null:
		return null
	var s := _audition(stream, loop)
	s.robot_id = robot_id
	s.position = Vector3(0, 1.0 * v.traits.visual_scale, 0)
	v.add_child(s)
	s.play()
	return s


func stop_auditions() -> int:
	var n := 0
	for s in auditions:
		if is_instance_valid(s):
			s.queue_free()
			n += 1
	auditions.clear()
	return n


func _audition(stream: AudioStream, loop: bool) -> FacilitySound:
	var s := FacilitySound.new()
	s.name = "Audition"
	s.stream = stream
	if loop:
		s.finished.connect(s.play)   # streams that don't loop by themselves
	else:
		# Once through, even for streams that loop by themselves.
		s.one_shot = true
		var ref: WeakRef = weakref(s)   # it may free itself first (finished)
		get_tree().create_timer(maxf(stream.get_length(), 0.1) + 0.05).timeout.connect(func():
			var still: Node = ref.get_ref()
			if still:
				still.queue_free())
	s.tree_exiting.connect(func(): auditions.erase(s))
	auditions.append(s)
	return s


# --- Rooms --------------------------------------------------------------------------------

func _build_room(id: String) -> void:
	var r: Dictionary = layout.rooms[id]
	var rect: Rect2 = r.rect
	var h: float = r.height
	var root := Node3D.new()
	root.name = "Room_" + id
	add_child(root)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = rect.size
	var fl := _mesh(floor_mesh, _mat(FLOOR_COLOR, 0.0, 0.85), root)
	fl.position = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	# Name painted on the floor, for orientation on camera.
	var label := Label3D.new()
	label.text = str(r.name).to_upper()
	label.font_size = 256
	label.pixel_size = 0.004 * clampf(rect.size.x / 20.0, 0.6, 2.5)
	label.modulate = Color(1, 1, 1, 0.12)
	label.shaded = true   # painted on the floor, not lit: only night vision picks it up
	label.rotation.x = -PI / 2
	label.position = fl.position + Vector3(0, 0.02, 0)
	root.add_child(label)
	# Four walls, with openings where passages go through.
	var c := [Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x, rect.end.y), Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		_build_wall(root, id, c[i], c[(i + 1) % 4], h, rect.get_center())


# A wall from a to b (on the floor, x/z), `h` tall, pushed a little into the
# room, with an opening for each passage that crosses it.
func _build_wall(parent: Node3D, room: String, a: Vector2, b: Vector2, h: float, centre: Vector2) -> void:
	var along := b - a
	var length := along.length()
	var dir := along / length
	var inward := (centre - (a + b) * 0.5).normalized() * WALL_THICKNESS * 0.5
	var openings: Array = []   # [t (meters along), width, bottom, top, segment id]
	for sid in layout.passages():
		var s := layout.segment(sid)
		var pa: Vector3 = layout.nodes[s.a].pos
		var pb: Vector3 = layout.nodes[s.b].pos
		if layout.nodes[s.a].room != room and layout.nodes[s.b].room != room:
			continue
		var hit = Geometry2D.segment_intersects_segment(Vector2(pa.x, pa.z), Vector2(pb.x, pb.z), a, b)
		if hit == null:
			continue
		var t := (hit as Vector2).distance_to(a)
		var k := (hit as Vector2).distance_to(Vector2(pa.x, pa.z)) / maxf(Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z)), 0.01)
		var y := lerpf(pa.y, pb.y, k)
		var clearance: float = s.clearance if not is_inf(s.clearance) else 5.0
		var w := clampf(clearance * 1.25, 1.4, 6.0)
		var drop := 6.0 if clearance >= 2.0 else 2.0   # big robots hang low
		openings.append([t, w, maxf(y - drop, 0.0), minf(y + 1.0, h), sid, Vector3(hit.x, y, hit.y)])
	openings.sort_custom(func(p, q): return p[0] < q[0])
	var cursor := 0.0
	for o in openings:
		_wall_piece(parent, a, dir, inward, cursor, o[0] - o[1] * 0.5, 0.0, h)
		_wall_piece(parent, a, dir, inward, o[0] - o[1] * 0.5, o[0] + o[1] * 0.5, 0.0, o[2])
		_wall_piece(parent, a, dir, inward, o[0] - o[1] * 0.5, o[0] + o[1] * 0.5, o[3], h)
		cursor = o[0] + o[1] * 0.5
		if not _shutters.has(o[4]):   # each passage gets one frame, sign and shutter
			_build_passage(o[4], o[5] + Vector3(inward.x, 0, inward.y), dir, o[1], o[2], o[3])
	_wall_piece(parent, a, dir, inward, cursor, length, 0.0, h)


func _wall_piece(parent: Node3D, a: Vector2, dir: Vector2, inward: Vector2, t0: float, t1: float, y0: float, y1: float) -> void:
	if t1 - t0 < 0.01 or y1 - y0 < 0.01:
		return
	var box := BoxMesh.new()
	box.size = Vector3(t1 - t0, y1 - y0, WALL_THICKNESS)
	var m := _mesh(box, _mat(WALL_COLOR, 0.0, 0.9), parent)
	var mid := a + dir * (t0 + t1) * 0.5 + inward
	m.position = Vector3(mid.x, (y0 + y1) * 0.5, mid.y)
	m.rotation.y = -atan2(dir.y, dir.x)


# A doorway frame (hazard-striped if it's narrow), a sign with its name and
# clearance, and a red shutter that shows while the passage is blocked.
func _build_passage(sid: String, at: Vector3, dir: Vector2, w: float, bottom: float, top: float) -> void:
	var s := layout.segment(sid)
	var narrow: bool = s.clearance < 2.0
	var frame := Node3D.new()
	frame.name = "Passage_" + sid
	frame.position = Vector3(at.x, 0, at.z)
	frame.rotation.y = -atan2(dir.y, dir.x)
	add_child(frame)
	var col := HAZARD if narrow else Color(0.5, 0.55, 0.6)
	for side in [-1.0, 1.0]:
		var post := BoxMesh.new()
		post.size = Vector3(0.2, top - bottom, 0.6)
		var p := _mesh(post, _mat(col, 0.3, 0.6), frame)
		p.position = Vector3(side * w * 0.5, (top + bottom) * 0.5, 0)
	var lintel := BoxMesh.new()
	lintel.size = Vector3(w + 0.4, 0.2, 0.6)
	var l := _mesh(lintel, _mat(col, 0.3, 0.6), frame)
	l.position = Vector3(0, top, 0)
	var sign := Label3D.new()
	sign.text = "%s\n%s" % [str(s.name).to_upper(), ("%.1f m CLEARANCE" % s.clearance) if not is_inf(s.clearance) else ""]
	sign.font_size = 48
	sign.pixel_size = 0.01
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = col.lightened(0.3)
	sign.outline_size = 8
	sign.shaded = true   # stencilled paint, not a lit sign
	sign.position = Vector3(0, top + 0.8, 0)
	frame.add_child(sign)
	var shutter_box := BoxMesh.new()
	shutter_box.size = Vector3(w, top - bottom, 0.15)
	var shutter := _mesh(shutter_box, _mat(Color(0.75, 0.12, 0.08), 0.4, 0.5, true), frame)
	shutter.position = Vector3(0, (top + bottom) * 0.5, 0)
	shutter.visible = false
	_shutters[sid] = shutter


# --- Rails, cameras --------------------------------------------------------------------

func _build_rails() -> void:
	var root := Node3D.new()
	root.name = "Rails"
	add_child(root)
	var mat := _mat(RAIL_COLOR, 0.85, 0.35)
	var pad_nodes := {}
	for sid in layout.segments:
		var s := layout.segment(sid)
		if s.get("pad", false):   # no rail to a pad
			pad_nodes[s.a] = true
			pad_nodes[s.b] = true
			continue
		var pa: Vector3 = layout.nodes[s.a].pos
		var pb: Vector3 = layout.nodes[s.b].pos
		var beam := BoxMesh.new()
		beam.size = Vector3(0.18, 0.14, pa.distance_to(pb))
		var m := _mesh(beam, mat, root)
		m.position = (pa + pb) * 0.5 + Vector3(0, 0.12, 0)
		m.look_at_from_position(m.position, pb + Vector3(0, 0.12, 0), Vector3.UP if absf((pb - pa).normalized().y) < 0.99 else Vector3.RIGHT)
	for nid in layout.nodes:
		if pad_nodes.has(nid):
			continue
		var joint := BoxMesh.new()
		joint.size = Vector3(0.4, 0.25, 0.4)
		var j := _mesh(joint, mat, root)
		j.position = layout.nodes[nid].pos + Vector3(0, 0.12, 0)


func _build_cameras() -> void:
	var root := Node3D.new()
	root.name = "Cameras"
	add_child(root)
	for c in FacilitySetup.cameras():
		var cam := SecurityCamera.new()
		cam.display_name = c.name
		cam.look_point = c.look
		cam.fov = 70.0
		cam.position = c.pos
		if not str(c.track).is_empty() and views.has(c.track):
			cam.target = views[c.track].actor
			_trackers[cameras.size()] = c.track
		root.add_child(cam)
		# A housing for it, seen from the other cameras (click it: repair).
		var i := cameras.size()
		var housing := _mesh(_box_mesh(Vector3(0.35, 0.25, 0.5)), _mat(Color(0.82, 0.82, 0.78), 0.3, 0.5), root)
		housing.position = c.pos + Vector3(0, 0.22, 0)
		housing.layers = 1 << (HOUSING_LAYER + i)
		housing.look_at_from_position(housing.position, c.look, Vector3.UP)
		_pick_nodes["cam_%d" % (i + 1)] = [housing]
		_pick_rooms["cam_%d" % (i + 1)] = c.room
		cameras.append(cam)
		camera_rooms.append(c.room)


## The layers a camera's feed renders: everything but its own housing.
func feed_cull_mask(cam_index: int) -> int:
	return 0xFFFFF & ~(1 << (HOUSING_LAYER + cam_index))


# A stuck door is the passage itself: point at the doorway.
func _link_doors() -> void:
	for id in FacilityPlant.DOORS:
		var frame := get_node_or_null("Passage_" + str(FacilityPlant.DOORS[id][1]))
		if frame:
			_pick_nodes[id] = [frame]
			_pick_rooms[id] = ""


# --- Picking ------------------------------------------------------------------------------

## What's under a point of a feed (`eye` is the feed's camera; `room` the
## camera's room). Returns an id ("robot:hauler", "pipe_2", "bench") or "".
func pick(eye: Camera3D, screen_pos: Vector2, room: String) -> String:
	var from := eye.project_ray_origin(screen_pos)
	var dir := eye.project_ray_normal(screen_pos)
	var best := ""
	var best_d := INF
	for id in pickable_ids():
		var r := pick_room(id)
		if not r.is_empty() and not room.is_empty() and r != room:
			continue
		for mi in pick_meshes(id):
			if not mi.is_visible_in_tree() or (mi.layers & eye.cull_mask) == 0:
				continue
			var box: AABB = (mi.global_transform * mi.get_aabb()).grow(0.06)
			var hit: Variant = box.intersects_ray(from, dir)
			if hit == null:
				continue
			var d := from.distance_to(hit as Vector3)
			if d < best_d:
				best_d = d
				best = id
	return best


func pickable_ids() -> Array[String]:
	var out: Array[String] = []
	for id in views:
		out.append("robot:" + str(id))
	if props:
		for id in props.pick_nodes:
			out.append(str(id))
	for id in _pick_nodes:
		out.append(str(id))
	return out


## Which room a pickable thing is in ("" = more than one: a doorway).
func pick_room(id: String) -> String:
	if id.begins_with("robot:"):
		return robot_room(id.trim_prefix("robot:"))
	if _pick_rooms.has(id):
		return _pick_rooms[id]
	var plant := Facility.sim.get_system("plant") as FacilityPlant if Facility.running else null
	var st := "bench" if id == "bench" else (str(plant.device(id).get("station", "")) if plant else "")
	return str(layout.station(st).get("room", "")) if not st.is_empty() else ""


## Every mesh that makes up a pickable thing.
func pick_meshes(id: String) -> Array[MeshInstance3D]:
	var roots: Array = []
	if id.begins_with("robot:"):
		var v: RobotView = views.get(id.trim_prefix("robot:"))
		if v:
			roots = [v]
	elif _pick_nodes.has(id):
		roots = _pick_nodes[id]
	elif props and props.pick_nodes.has(id):
		roots = props.pick_nodes[id]
	var out: Array[MeshInstance3D] = []
	for n in roots:
		if n is MeshInstance3D:
			out.append(n)
		for m in (n as Node).find_children("*", "MeshInstance3D", true, false):
			out.append(m)
	return out


## Outlines one pickable thing ("" = none).
func highlight(id: String) -> void:
	if id == _highlighted:
		return
	for mi in pick_meshes(_highlighted):
		mi.material_overlay = null
	_highlighted = id
	for mi in pick_meshes(id):
		mi.material_overlay = outline_material()


static func outline_material() -> StandardMaterial3D:
	if _outline == null:
		var tint := StandardMaterial3D.new()
		tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tint.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tint.albedo_color = Color(1.0, 0.75, 0.25, 0.22)
		var hull := StandardMaterial3D.new()
		hull.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hull.cull_mode = BaseMaterial3D.CULL_FRONT
		hull.grow = true
		hull.grow_amount = 0.045
		hull.albedo_color = Color(1.0, 0.8, 0.3)
		tint.next_pass = hull
		_outline = tint
	return _outline


# --- Helpers ---------------------------------------------------------------------------

static func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _mesh(m: Mesh, mat: Material, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _mat(c: Color, metal := 0.0, rough := 0.8, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if glow:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.6
	return m

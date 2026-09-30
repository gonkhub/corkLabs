# The 3D facility, built from the same floor plan the simulation uses
# (FacilitySetup.layout()): rooms (floor, walls with openings where passages
# go through), the rail network, the robots, the plant's props, lights and
# security cameras. Change the layout and the world follows; nothing here is
# placed by hand.
#
# It shows whatever Facility session is running (robots follow their sim
# selves via RobotView, props show the plant, blocked passages show a closed
# shutter), but never starts one: the corkLabs desktop does.
#
# Placeholder shapes everywhere: the point is the framework. Real models can
# replace any piece later.
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
## The camera you're listening through (its feed is the 3D audio listener),
## or -1 for none. Set by the Cameras app; FacilitySound uses its room.
var listener_cam := -1
## Sounds started with play_sound() / attach_sound() (the Terminal's `sound`).
var auditions: Array[FacilitySound] = []


func _ready() -> void:
	layout = FacilitySetup.layout()
	_build_lights()
	for id in layout.rooms:
		_build_room(id)
	_build_rails()
	for id in FacilitySetup.START_STATIONS:
		var view := RobotView.new()
		view.setup(id, layout)
		add_child(view)
		views[id] = view
	props = FacilityProps.new()
	props.name = "Props"
	add_child(props)
	props.build(layout)
	_build_cameras()


func _process(_delta: float) -> void:
	if not Facility.running:
		return
	var live := Facility.sim.get_system("layout") as FacilityLayout
	if live == null:
		return
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
	sign.position = Vector3(0, top + 0.8, 0)
	frame.add_child(sign)
	var shutter_box := BoxMesh.new()
	shutter_box.size = Vector3(w, top - bottom, 0.15)
	var shutter := _mesh(shutter_box, _mat(Color(0.75, 0.12, 0.08), 0.4, 0.5, true), frame)
	shutter.position = Vector3(0, (top + bottom) * 0.5, 0)
	shutter.visible = false
	_shutters[sid] = shutter


# --- Rails, lights, cameras --------------------------------------------------------------------

func _build_rails() -> void:
	var root := Node3D.new()
	root.name = "Rails"
	add_child(root)
	var mat := _mat(RAIL_COLOR, 0.85, 0.35)
	for sid in layout.segments:
		var s := layout.segment(sid)
		var pa: Vector3 = layout.nodes[s.a].pos
		var pb: Vector3 = layout.nodes[s.b].pos
		var beam := BoxMesh.new()
		beam.size = Vector3(0.18, 0.14, pa.distance_to(pb))
		var m := _mesh(beam, mat, root)
		m.position = (pa + pb) * 0.5 + Vector3(0, 0.12, 0)
		m.look_at_from_position(m.position, pb + Vector3(0, 0.12, 0), Vector3.UP if absf((pb - pa).normalized().y) < 0.99 else Vector3.RIGHT)
	for nid in layout.nodes:
		var joint := BoxMesh.new()
		joint.size = Vector3(0.4, 0.25, 0.4)
		var j := _mesh(joint, mat, root)
		j.position = layout.nodes[nid].pos + Vector3(0, 0.12, 0)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_energy = 0.15
	add_child(sun)
	for id in layout.rooms:
		var r: Dictionary = layout.rooms[id]
		var rect: Rect2 = r.rect
		var nx := maxi(1, roundi(rect.size.x / 25.0))
		var nz := maxi(1, roundi(rect.size.y / 25.0))
		for i in nx:
			for k in nz:
				var lamp := OmniLight3D.new()
				lamp.position = Vector3(rect.position.x + rect.size.x * (i + 0.5) / nx, float(r.height) - 1.0,
					rect.position.y + rect.size.y * (k + 0.5) / nz)
				lamp.omni_range = maxf(rect.size.x / nx, rect.size.y / nz) * 1.1 + float(r.height)
				lamp.light_energy = 3.0 if rect.size.x > 40.0 else 2.0
				lamp.light_color = Color(1, 0.94, 0.84)
				add_child(lamp)


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
		cameras.append(cam)
		camera_rooms.append(c.room)


# --- Helpers ---------------------------------------------------------------------------

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

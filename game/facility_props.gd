# Shows the facility plant in the 3D world: builds simple props for each
# device at its station (placed from the same FacilityLayout the simulation
# uses, so the two can't drift apart) and colours them by their state every
# frame: pods glow green -> amber -> red as they lose sync, leaking bays flash
# red, debris piles up, the relay panel goes dark when its fuse blows, docks
# light up while a robot charges, repaired parts wait on the workbench,
# freight crates pile up in the hangar until they're stacked.
#
#     var props := FacilityProps.new()
#     add_child(props)
#     props.build(layout)          # FacilityWorld does this
#
# Placeholder shapes, like the robots: swap in real models later, keeping the
# state colours.
class_name FacilityProps
extends Node3D

const OK := Color(0.25, 0.95, 0.5)
const WARN := Color(1.0, 0.7, 0.15)
const BAD := Color(1.0, 0.18, 0.12)
const DEAD := Color(0.08, 0.1, 0.1)

## Show a floating name + state label over each device.
@export var labels := true

var _layout: FacilityLayout
var _pods := {}           # device id -> MeshInstance3D
var _pod_mats := {}       # device id -> StandardMaterial3D
var _lamps := {}          # device id -> [OmniLight3D, StandardMaterial3D]
var _debris := {}         # bay id -> Node3D
var _labels := {}         # device id -> Label3D
var _docks := {}          # station id -> [OmniLight3D, StandardMaterial3D]
var _freight := {}        # device id -> Node3D (the crates, shown while there's a job)
var _bench_part: MeshInstance3D
var _time := 0.0


## Builds a prop for every plant device at its station, and a charging clamp at each dock.
func build(layout: FacilityLayout) -> void:
	_layout = layout
	if DisplayServer.get_name() == "headless":
		return   # no renderer (tests): meshes would only spam errors
	var plant := FacilityPlant.new()   # just for the device list
	var pods_at := {}   # station -> [pod ids]
	for id in plant.device_ids():
		var d := plant.device(id)
		if d.kind == "pod":
			if not pods_at.has(d.station):
				pods_at[d.station] = []
			pods_at[d.station].append(id)
	for st in pods_at:
		var ids: Array = pods_at[st]
		for k in ids.size():
			_build_pod(ids[k], _beside_rail(st, (k - (ids.size() - 1) * 0.5) * 4.0, 3.0))
	for b in 3:
		var bay := "bay_%d" % (b + 1)
		_build_bay(bay, _beside_rail(bay, 0.0, 3.5))
	_build_relay(_by_wall("relay"))
	_build_bench(_beside_rail("bench", 0.0, 0.0))
	_build_gate_panel(_beside_rail("gate", 0.0, -3.0))
	for id in plant.device_ids():
		var d := plant.device(id)
		if d.kind == "freight":
			var st := layout.station(d.station)
			var at := layout.station_world_pos(d.station)
			_build_freight(id, _beside_rail(d.station, 0.0, 5.0) if not layout.is_pad(st.segment) else Vector3(at.x, 0.0, at.z))
	for dock in layout.stations_of("dock"):
		if not layout.is_pad(layout.station(dock).segment):   # Ogre's mains coupling is part of its mount
			_build_dock(dock, layout.station_world_pos(dock))


func _process(delta: float) -> void:
	_time += delta
	if not Facility.running:
		return
	var plant := Facility.sim.get_system("plant") as FacilityPlant
	if plant == null or _lamps.is_empty():
		return
	var flash := 0.5 + 0.5 * sin(_time * 7.0)
	for id in _pods:
		var v: float = plant.device(id).value
		var c := _health_color(v)
		var mat: StandardMaterial3D = _pod_mats[id]
		mat.albedo_color = Color(c.r, c.g, c.b, 0.35)
		mat.emission = c
		mat.emission_energy_multiplier = 0.15 if v <= 0.0 else 0.6
	for b in 3:
		var n := b + 1
		var leaking: bool = plant.device("pipe_%d" % n).fault
		var filters: float = plant.device("filter_%d" % n).value
		var lamp: Array = _lamps["bay_%d" % n]
		var col := BAD if leaking else _health_color(filters * 1.25 - 0.1)
		(lamp[0] as OmniLight3D).light_color = col
		(lamp[0] as OmniLight3D).light_energy = (0.3 + 2.5 * flash) if leaking else 0.35
		(lamp[1] as StandardMaterial3D).emission = col
		_debris["bay_%d" % n].visible = int(plant.device("bay_%d" % n).job) >= 0
	var gate: Array = _lamps["gate"]
	var jammed: bool = plant.device("gate").fault
	(gate[0] as OmniLight3D).light_color = BAD if jammed else OK
	(gate[0] as OmniLight3D).light_energy = (2.0 * flash) if jammed else 0.4
	(gate[1] as StandardMaterial3D).emission = BAD if jammed else OK
	var relay: Array = _lamps["relay"]
	var out: bool = plant.device("relay").fault
	(relay[0] as OmniLight3D).light_color = BAD if out else OK
	(relay[0] as OmniLight3D).light_energy = (2.0 * flash) if out else 0.4
	(relay[1] as StandardMaterial3D).emission = BAD if out else OK
	for dock in _docks:
		var charging := false
		for bot in FacilitySetup.robots(Facility.sim):
			if bot.activity.kind == "recharge" and bot.activity.get("station", "") == dock and not bot.moving:
				charging = true
		var light: OmniLight3D = _docks[dock][0]
		light.light_energy = (0.6 + 0.6 * flash) * plant.charge_factor() if charging else 0.05
		(_docks[dock][1] as StandardMaterial3D).emission_energy_multiplier = 2.0 if charging else 0.2
	for id in _freight:
		(_freight[id] as Node3D).visible = int(plant.device(id).job) >= 0
	var board := Facility.sim.get_system("work") as WorkBoard
	if _bench_part and board:
		_bench_part.visible = board.open_jobs().any(func(j): return str(j.source).begins_with("part:repair"))
	if labels:
		for id in _labels:
			(_labels[id] as Label3D).text = _label_text(plant, id)


static func _label_text(plant: FacilityPlant, id: String) -> String:
	if not plant.devices.has(id):
		return ""
	var d := plant.device(id)
	if d.kind == "bay":   # one label for the whole bay
		var n := id.trim_prefix("bay_")
		var pipe := plant.device("pipe_" + n)
		return "%s\n%s   filters %d%%%s" % [d.name, "LEAKING" if pipe.fault else "pipe sealed",
			roundi(float(plant.device("filter_" + n).value) * 100.0), "\nDEBRIS" if int(d.job) >= 0 else ""]
	var state := plant.device_text(id).substr(20).strip_edges()   # after the padded name
	return "%s\n%s" % [d.name, state]


# Green when healthy, amber around the point a job gets posted, red when
# it's getting serious, dark when dead.
static func _health_color(v: float) -> Color:
	if v <= 0.0:
		return DEAD
	if v >= 0.85:
		return OK
	if v >= 0.55:
		return WARN.lerp(OK, (v - 0.55) / 0.3)
	return BAD.lerp(WARN, clampf((v - 0.25) / 0.3, 0.0, 1.0))


# --- Placement ------------------------------------------------------------------------

# A floor point near a station: `along` meters along its rail, `side` meters
# to the side of it (+ = right when facing along the rail).
func _beside_rail(station_id: String, along: float, side: float) -> Vector3:
	var st := _layout.station(station_id)
	var s := _layout.segment(st.segment)
	var a: Vector3 = _layout.nodes[s.a].pos
	var b: Vector3 = _layout.nodes[s.b].pos
	var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var right := dir.cross(Vector3.UP)
	var p := _layout.station_world_pos(station_id) + dir * along + right * side
	return Vector3(p.x, 0.0, p.z)


# On the wall of the station's room nearest to it, at chest height.
func _by_wall(station_id: String) -> Vector3:
	var st := _layout.station(station_id)
	var p := _layout.station_world_pos(station_id)
	var rect: Rect2 = _layout.rooms[st.room].rect
	var pts := [Vector3(rect.position.x + 0.5, 1.2, p.z), Vector3(rect.end.x - 0.5, 1.2, p.z),
		Vector3(p.x, 1.2, rect.position.y + 0.5), Vector3(p.x, 1.2, rect.end.y - 0.5)]
	pts.sort_custom(func(u, v): return Vector2(u.x - p.x, u.z - p.z).length() < Vector2(v.x - p.x, v.z - p.z).length())
	return pts[0]


# --- Props ------------------------------------------------------------------------------

func _build_bay(bay: String, at: Vector3) -> void:
	var root := Node3D.new()
	root.name = bay.capitalize().replace(" ", "")
	root.position = at
	root.scale = Vector3.ONE * 2.0   # Hauler-sized
	add_child(root)
	# A coolant pipe running across the bay, and a filter housing.
	var pipe := _mesh(_cyl(0.12, 2.2), _mat(Color(0.35, 0.45, 0.55), 0.8), root)
	pipe.rotation.x = PI / 2
	pipe.position = Vector3(0, 0.25, 0)
	var filt := _mesh(_box(Vector3(0.6, 0.7, 0.5)), _mat(Color(0.3, 0.32, 0.3)), root)
	filt.position = Vector3(0.55, 0.35, -0.6)
	var lamp_mat := _mat(OK, 0.2, true)
	var bulb := _mesh(_sphere(0.08), lamp_mat, root)
	bulb.position = Vector3(0.55, 0.8, -0.6)
	var light := OmniLight3D.new()
	light.position = Vector3(0.55, 1.0, -0.6)
	light.omni_range = 2.5
	root.add_child(light)
	_lamps[bay] = [light, lamp_mat]
	# Debris: a few tumbled blocks, shown while there's a clear-debris job.
	var debris := Node3D.new()
	root.add_child(debris)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(bay)
	for i in 5:
		var d := _mesh(_box(Vector3(rng.randf_range(0.15, 0.35), rng.randf_range(0.1, 0.25), rng.randf_range(0.15, 0.35))),
			_mat(Color(0.45, 0.4, 0.33)), debris)
		d.position = Vector3(rng.randf_range(-0.5, 0.3), 0.08, rng.randf_range(0.2, 0.7))
		d.rotation.y = rng.randf() * TAU
	_debris[bay] = debris
	_add_label(bay, at + Vector3(1.1, 2.8, -1.2))


# A painted loading square on the floor, and a stack of crates on it while
# there's freight to shift.
func _build_freight(id: String, at: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Freight_" + id
	root.position = at
	add_child(root)
	var square := _mesh(_box(Vector3(9.0, 0.03, 9.0)), _mat(WARN.darkened(0.55), 0.0), root)
	square.position.y = 0.015
	var crates := Node3D.new()
	root.add_child(crates)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	for i in 6:
		var size := rng.randf_range(1.8, 2.6)
		var c := _mesh(_box(Vector3(size, size * 0.8, size)), _mat(Color(0.42, 0.36, 0.26).darkened(rng.randf() * 0.3), 0.1), crates)
		c.position = Vector3(rng.randf_range(-2.8, 2.8), size * 0.4 + (2.0 if i >= 4 else 0.0), rng.randf_range(-2.8, 2.8))
		c.rotation.y = rng.randf_range(-0.4, 0.4)
	_freight[id] = crates
	_add_label(id, at + Vector3(0, 6.0, 0))


func _build_pod(id: String, at: Vector3) -> void:
	var mat := _mat(OK, 0.0, true)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(OK.r, OK.g, OK.b, 0.35)
	var pod := _mesh(_cyl(0.6, 2.6), mat, self)
	pod.position = at + Vector3(0, 1.3, 0)
	_pods[id] = pod
	_pod_mats[id] = mat
	_add_label(id, at + Vector3(0, 3.0, 0))


func _build_gate_panel(at: Vector3) -> void:
	var post := _mesh(_box(Vector3(0.4, 1.4, 0.4)), _mat(Color(0.3, 0.3, 0.32), 0.5), self)
	post.position = at + Vector3(0, 0.7, 0)
	var lamp_mat := _mat(OK, 0.2, true)
	var bulb := _mesh(_sphere(0.1), lamp_mat, self)
	bulb.position = at + Vector3(0, 1.5, 0)
	var light := OmniLight3D.new()
	light.position = at + Vector3(0, 2.0, 0)
	light.omni_range = 4.0
	add_child(light)
	_lamps["gate"] = [light, lamp_mat]
	_add_label("gate", at + Vector3(0, 2.3, 0))


func _build_relay(at: Vector3) -> void:
	var panel := _mesh(_box(Vector3(0.2, 1.1, 0.8)), _mat(Color(0.25, 0.27, 0.3), 0.6), self)
	panel.position = at
	var lamp_mat := _mat(OK, 0.2, true)
	var bulb := _mesh(_sphere(0.07), lamp_mat, self)
	var inward := -Vector3(at.x, 0, at.z).normalized()
	bulb.position = at + Vector3(0, 0.35, 0) + inward * 0.12
	var light := OmniLight3D.new()
	light.position = bulb.position + inward * 0.3
	light.omni_range = 2.0
	add_child(light)
	_lamps["relay"] = [light, lamp_mat]
	_add_label("relay", at + Vector3(0, 0.8, 0))


func _build_bench(at: Vector3) -> void:
	var top := _mesh(_box(Vector3(1.0, 0.08, 1.4)), _mat(Color(0.4, 0.33, 0.25)), self)
	top.position = Vector3(at.x, 0.9, at.z)
	for dx in [-0.4, 0.4]:
		for dz in [-0.6, 0.6]:
			var leg := _mesh(_box(Vector3(0.06, 0.9, 0.06)), _mat(Color(0.2, 0.2, 0.2)), self)
			leg.position = Vector3(at.x + dx, 0.45, at.z + dz)
	_bench_part = _mesh(_cyl(0.12, 0.25), _mat(WARN, 0.4, true), self)
	_bench_part.position = Vector3(at.x, 1.07, at.z)


func _build_dock(dock: String, at: Vector3) -> void:
	# A clamp on the rail with a charge light under it.
	var mat := _mat(Color(0.3, 0.7, 1.0), 0.3, true)
	var clamp := _mesh(_box(Vector3(0.3, 0.16, 0.3)), mat, self)
	clamp.position = at + Vector3(0, -0.12, 0)
	var light := OmniLight3D.new()
	light.position = at + Vector3(0, -0.5, 0)
	light.light_color = Color(0.3, 0.7, 1.0)
	light.omni_range = 2.0
	add_child(light)
	_docks[dock] = [light, mat]


func _add_label(device: String, at: Vector3) -> void:
	if not labels:
		return
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 24
	l.pixel_size = 0.0035
	l.modulate = Color(0.85, 1.0, 0.9, 0.9)
	l.outline_size = 6
	l.position = at
	l.no_depth_test = false
	add_child(l)
	_labels[device] = l


# --- Mesh helpers ------------------------------------------------------------------------

func _mesh(m: Mesh, mat: Material, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _mat(c: Color, metal := 0.2, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.6
	if glow:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.0
	return m


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s

# Shows the facility plant in the 3D world: builds simple props for each
# device at its station (placed from the same FacilityLayout the simulation
# uses, so the two can't drift apart) and colours them by their state every
# frame: pods glow green -> amber -> red as they lose sync, leaking bays flash
# red, debris piles up, the relay panel goes dark when its fuse blows, docks
# light up while a robot charges, repaired parts wait on the workbench.
#
#     var props := FacilityProps.new()
#     add_child(props)
#     props.build({"tinker_loop": $TinkerRail, "hauler_line": $HaulerRail}, $Pods)
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

var _rails := {}
var _pods := {}           # device id -> MeshInstance3D (existing scene pods)
var _pod_mats := {}       # device id -> StandardMaterial3D
var _lamps := {}          # device id -> [OmniLight3D, StandardMaterial3D]
var _debris := {}         # bay id -> Node3D
var _labels := {}         # device id -> Label3D
var _docks := {}          # station id -> [OmniLight3D, StandardMaterial3D]
var _bench_part: MeshInstance3D
var _time := 0.0


## rails: rail id -> Path3D. pods_node: the scene's Pods (children Pod1..Pod4).
func build(rails: Dictionary, pods_node: Node3D = null) -> void:
	_rails = rails
	if DisplayServer.get_name() == "headless":
		return   # no renderer (tests): meshes would only spam errors
	var layout := FacilitySetup.layout()
	if pods_node:
		for i in 4:
			var mesh := pods_node.get_node_or_null("Pod%d" % (i + 1)) as MeshInstance3D
			if mesh:
				var mat := (mesh.get_surface_override_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(0, mat)
				var id := "pod_%d" % (i + 1)
				_pods[id] = mesh
				_pod_mats[id] = mat
				_add_label(id, mesh.global_position + Vector3(0, 1.4, 0))
	for b in 3:
		var bay := "bay_%d" % (b + 1)
		_build_bay(bay, _station_floor(layout, bay))
	_build_relay(_station_wall(layout, "relay"))
	_build_bench(_station_wall(layout, "bench"))
	for dock in ["t_dock", "h_dock"]:
		_build_dock(dock, _station_point(layout, dock))


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

func _station_point(layout: FacilityLayout, station: String) -> Vector3:
	var st := layout.station(station)
	var path := _rails.get(st.rail) as Path3D
	if path == null:
		return Vector3.ZERO
	return path.global_transform * path.curve.sample_baked(float(st.pos))


# On the floor below the station (bays: beside Hauler's straight rail).
func _station_floor(layout: FacilityLayout, station: String) -> Vector3:
	var p := _station_point(layout, station)
	return Vector3(p.x, 0.0, p.z)


# Pushed out from the room's centre towards the wall, at chest height.
func _station_wall(layout: FacilityLayout, station: String) -> Vector3:
	var p := _station_point(layout, station)
	var out := Vector3(p.x, 0.0, p.z).normalized()
	return Vector3(p.x, 1.2, p.z) + out * 0.9


# --- Props ------------------------------------------------------------------------------

func _build_bay(bay: String, at: Vector3) -> void:
	var root := Node3D.new()
	root.name = bay.capitalize().replace(" ", "")
	root.position = at
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
	_add_label(bay, at + Vector3(0.55, 1.3, -0.6))


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

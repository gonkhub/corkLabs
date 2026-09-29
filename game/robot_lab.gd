# Robot Lab: plays any take on every robot side by side, on a normal
# monitor. Use it to compare personalities and tune profiles without a
# headset. The robots are driven live through their rigs, exactly as a
# bake would drive them.
#
# Keys:
#   Left / Right   previous / next take
#   Space          pause / play
#   R              restart
#   , / .          step one frame back / forward (while paused)
#   M              mirror on/off (robots face you and move like a reflection)
#   G              show/hide the raw take as ghost cubes
#   Mouse drag     orbit    Wheel  zoom
extends Node3D

const SPACING := 2.2

@onready var stages: Node3D = $Stages
@onready var info: Label = $Overlay/Info
@onready var cam_pivot: Node3D = $CamPivot
@onready var cam: Camera3D = $CamPivot/Camera3D
@onready var ghost: Node3D = $Ghost

var take_paths := PackedStringArray()
var take_index := 0
var take: PerformanceTake
var clean: PerformanceTake
var rigs: Array[RobotRig] = []
var time := 0.0
var paused := false
var mirrored := true
var _dragging := false


func _ready() -> void:
	take_paths = TakeStore.list()
	# Start on the newest real take if there is one.
	take_index = take_paths.size() - 1
	for i in range(take_paths.size() - 1, -1, -1):
		if not take_paths[i].contains("/demo/"):
			take_index = i
			break
	var ids := RobotLibrary.ids()
	for i in ids.size():
		var holder := Node3D.new()
		holder.name = ids[i]
		stages.add_child(holder)
		holder.position = Vector3((i - (ids.size() - 1) / 2.0) * SPACING, 2.5, 0)
		var rig := RobotLibrary.instantiate(ids[i])
		holder.add_child(rig)
		rigs.append(rig)
		var label := Label3D.new()
		label.text = rig.profile.display_name if rig.profile else ids[i]
		label.position = Vector3(0, 0.35, 0)
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		holder.add_child(label)
	_apply_facing()
	_load_take()


func _process(delta: float) -> void:
	if clean == null:
		return
	if not paused:
		_advance(delta)
	var raw := take.sample(clamp(time, 0.0, take.duration()))
	$Ghost/Head.transform = raw.head
	$Ghost/Left.transform = raw.left
	$Ghost/Right.transform = raw.right
	info.text = "%s  (%d/%d)\nrobot: %s   clip: %s   %.2f / %.2f s%s\nmirror %s   [Left/Right take, Space pause, R restart, ,/. step, M mirror, G ghost]" % [
		take_paths[take_index].trim_prefix("res://takes/"), take_index + 1, take_paths.size(),
		take.robot_id if take.robot_id else "-", take.clip_name if take.clip_name else "-",
		time, clean.duration(), "   PAUSED" if paused else "", "on" if mirrored else "off"]


func _advance(delta: float) -> void:
	time += delta
	if time > clean.duration():
		time = 0.0
		for rig in rigs:
			rig.begin(take.eye_height)
	var f := clean.sample(time)
	if mirrored:
		f = f.mirrored()
	for rig in rigs:
		rig.drive(f, delta)


func _load_take() -> void:
	if take_paths.is_empty():
		info.text = "No takes in res://takes/ yet."
		return
	take = TakeStore.load_take(take_paths[take_index])
	clean = TakeCleanup.run(take).take
	time = 0.0
	for rig in rigs:
		rig.begin(take.eye_height)
		rig.drive(clean.sample(0.0), 1.0 / 60.0)


func _apply_facing() -> void:
	for holder in stages.get_children():
		holder.rotation.y = PI if mirrored else 0.0
	# The ghost shows the performer's side of the mirror: in front of the robots.
	ghost.position = Vector3(0, 0, 2.6) if mirrored else Vector3(0, 0, 0)
	ghost.rotation.y = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT:
				take_index = (take_index - 1 + take_paths.size()) % maxi(take_paths.size(), 1)
				_load_take()
			KEY_RIGHT:
				take_index = (take_index + 1) % maxi(take_paths.size(), 1)
				_load_take()
			KEY_SPACE:
				paused = not paused
			KEY_R:
				_load_take()
			KEY_PERIOD:
				if paused:
					_advance(1.0 / 30.0)
			KEY_COMMA:
				if paused:
					# Springs can't run backwards: re-simulate up to the earlier frame.
					var target := maxf(0.0, time - 1.0 / 30.0)
					_load_take()
					while time + 1.0 / 30.0 <= target:
						_advance(1.0 / 30.0)
			KEY_M:
				mirrored = not mirrored
				_apply_facing()
				_load_take()
			KEY_G:
				ghost.visible = not ghost.visible
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.position.z = maxf(1.5, cam.position.z * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.position.z = minf(20.0, cam.position.z * 1.1)
	elif event is InputEventMouseMotion and _dragging:
		cam_pivot.rotation.y -= event.relative.x * 0.006
		cam_pivot.rotation.x = clampf(cam_pivot.rotation.x - event.relative.y * 0.006, -1.2, 0.4)

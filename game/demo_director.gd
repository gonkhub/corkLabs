# Runs the demo facility: robots go about their shifts on the rails, and you
# watch through security cameras, like the supervisor will.
#
# Keys:
#   Tab / 1 2 3     switch camera
#   T               Tinker: play a random action
#   H               Hauler: play a random action
#   C               toggle the CCTV filter
#
# Nothing here is final game code; it's a place to see baked clips in
# context, and a starting point for real robot behaviour.
extends Node3D

## Hauler's work stations, in meters along its rail.
@export var hauler_stations: Array[float] = [0.6, 4.0, 7.4]

@onready var cameras: Array[Camera3D] = [$Cameras/Cam1, $Cameras/Cam2, $Cameras/Cam3]
@onready var cctv: CanvasItem = $Overlay/CCTV
@onready var cam_label: Label = $Overlay/CamLabel
@onready var help_label: Label = $Overlay/Help
@onready var tinker: RobotActor = $TinkerRail/Rider/Swing/Tinker
@onready var tinker_rider: RailRider = $TinkerRail/Rider
@onready var hauler: RobotActor = $HaulerRail/Rider/Swing/Hauler
@onready var hauler_rider: RailRider = $HaulerRail/Rider

var cam_index := 0
var _station := 0
var _hauler_wait := 2.0
var _tinker_wait := 6.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_use_camera(0)
	hauler_rider.arrived.connect(_on_hauler_arrived)
	hauler_rider.travel_to(hauler_stations[0])
	help_label.text = "Tab/1-3 camera   T tinker action   H hauler action   C CCTV filter\n" + _clip_summary()


func _process(delta: float) -> void:
	# Tinker patrols, and now and then stops what it's doing to gesture.
	_tinker_wait -= delta
	if _tinker_wait <= 0.0 and not tinker.is_busy():
		tinker.play_random_action()
		_tinker_wait = _rng.randf_range(6.0, 12.0)

	# Hauler: drive to a station, work, move on.
	if not hauler_rider.is_moving() and not hauler.is_busy():
		_hauler_wait -= delta
		if _hauler_wait <= 0.0:
			_station = (_station + 1) % hauler_stations.size()
			hauler_rider.travel_to(hauler_stations[_station])
			_hauler_wait = 1.5

	var now := Time.get_datetime_dict_from_system()
	cam_label.text = "CAM %02d  %s   %04d-%02d-%02d %02d:%02d:%02d   REC" % [
		cam_index + 1, cameras[cam_index].name.to_upper(), now.year, now.month, now.day,
		now.hour, now.minute, now.second]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_TAB:
			_use_camera((cam_index + 1) % cameras.size())
		KEY_1, KEY_2, KEY_3:
			_use_camera(event.keycode - KEY_1)
		KEY_T:
			tinker.play_random_action()
		KEY_H:
			hauler.play_random_action()
		KEY_C:
			cctv.visible = not cctv.visible


func _on_hauler_arrived() -> void:
	hauler.play_random_action()


func _use_camera(i: int) -> void:
	cam_index = clampi(i, 0, cameras.size() - 1)
	cameras[cam_index].make_current()


func _clip_summary() -> String:
	var lines := PackedStringArray()
	for actor in [tinker, hauler]:
		lines.append("%s: idles %s, actions %s" % [actor.robot_id, ", ".join(actor.idle_names),
			", ".join(actor.action_names)])
	return "\n".join(lines)

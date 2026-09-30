# A sound somewhere in the 3D facility, heard through whichever security
# camera you're listening to (the camera is the "microphone"; see CCTVFeed).
# Use it for anything that makes noise in the world: robot motors, machines,
# alarms, footsteps, auditioned sounds.
#
# It's an AudioStreamPlayer3D on the World bus, tuned for the facility's
# scale: distance attenuation (inverse distance, like real air), a gentle
# high-frequency roll-off with distance, and room awareness:
#
#   same room as the listening camera   plain distance attenuation
#   another room                        through_wall_db quieter and muffled
#                                       (eased over WALL_FADE, no jumps)
#
# The room is the robot's room if robot_id is set, else `room` if set, else
# the room its position is in. Add one as a child of whatever makes the
# noise and it follows it around.
#
# Tuning (all per emitter, all in the Inspector if you place one in a scene):
#   unit_size       metres at which it's at full volume (bigger = carries further)
#   max_distance    beyond this it's silent
#   volume_db       its own level (the room/wall offset is added on top)
class_name FacilitySound
extends AudioStreamPlayer3D

## Seconds to ease in/out of the through-wall sound.
const WALL_FADE := 0.25

## Fixed room id (props, machines). Leave empty to use robot_id or position.
@export var room := ""
## The robot this sound belongs to (its room follows the robot).
@export var robot_id := ""
## How much quieter it is when the listening camera is in another room.
@export var through_wall_db := -30.0
## Low-pass cutoff when heard through a wall (the open-air cutoff is `open_cutoff_hz`).
@export var through_wall_cutoff_hz := 500.0
@export var open_cutoff_hz := 6000.0
## Free itself when it finishes (one-shots).
var one_shot := false

var _wall := -1.0   # 0 = same room, 1 = fully through a wall (-1: not placed yet)
var _base_db := 0.0
var _world: FacilityWorld


func _init() -> void:
	bus = FeedAudio.WORLD
	attenuation_model = ATTENUATION_INVERSE_DISTANCE
	unit_size = 6.0
	max_distance = 90.0
	attenuation_filter_cutoff_hz = open_cutoff_hz
	attenuation_filter_db = -18.0
	panning_strength = 0.8
	finished.connect(func():
		if one_shot:
			queue_free())


func _ready() -> void:
	_base_db = volume_db
	var n := get_parent()
	while n and not n is FacilityWorld:
		n = n.get_parent()
	_world = n as FacilityWorld


## Its own level (use this rather than volume_db, which also carries the wall offset).
func set_level_db(db: float) -> void:
	_base_db = db


func level_db() -> float:
	return _base_db


## The room this sound is in right now.
func current_room() -> String:
	if _world == null:
		return room
	if not robot_id.is_empty():
		return _world.robot_room(robot_id)
	if not room.is_empty():
		return room
	return _world.room_at_point(global_position)


## True when the listening camera is in another room.
func behind_wall() -> bool:
	if _world == null:
		return false
	var listening := _world.listen_room()
	return not listening.is_empty() and current_room() != listening


func _process(delta: float) -> void:
	var target := 1.0 if behind_wall() else 0.0
	_wall = target if _wall < 0.0 else move_toward(_wall, target, delta / WALL_FADE)
	volume_db = _base_db + through_wall_db * _wall
	attenuation_filter_cutoff_hz = lerpf(open_cutoff_hz, through_wall_cutoff_hz, _wall)

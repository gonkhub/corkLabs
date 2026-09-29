# A robot in the game world, playing its baked clips.
#
# Put a RobotActor anywhere (usually inside a RailRider so it can travel),
# set robot_id, and it builds itself: the robot's model, plus an
# AnimationTree that
#   - loops idle clips (names starting "idle"), crossfading to a random
#     different idle each time one finishes, and
#   - plays actions (names starting "act") over the idle with play_action(),
#     fading in and out.
# Any other clip can be played with play_action() too.
class_name RobotActor
extends Node3D

signal action_finished(clip: String)

## Folder name under res://robots/ (e.g. "tinker", "hauler").
@export var robot_id := "tinker"
## Crossfade between idles, in seconds.
@export var idle_crossfade := 0.6
## Fade into an action, in seconds.
@export var action_fade_in := 0.25
## Fade out of an action back to idle, in seconds.
@export var action_fade_out := 0.4

var rig: RobotRig
var tree: AnimationTree
var idle_names := PackedStringArray()
var action_names := PackedStringArray()

var _idle_nodes: Array[AnimationNodeAnimation] = []
var _action_node: AnimationNodeAnimation
var _idle_slot := 0
var _idle_left := 0.0
var _current_action := ""
var _action_left := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	rig = RobotLibrary.instantiate(robot_id)
	if rig == null:
		return
	add_child(rig)
	var lib_path := RobotLibrary.library_path(robot_id)
	if not ResourceLoader.exists(lib_path):
		push_warning("%s has no baked clips yet (%s)" % [robot_id, lib_path])
		return
	var lib := load(lib_path) as AnimationLibrary
	for clip in lib.get_animation_list():
		if clip.begins_with("idle"):
			idle_names.append(clip)
		else:
			action_names.append(clip)
	_build_tree(lib)


func _process(delta: float) -> void:
	if tree == null:
		return
	if idle_names.size() > 0:
		_idle_left -= delta
		if _idle_left <= idle_crossfade:
			_next_idle()
	if not _current_action.is_empty():
		_action_left -= delta
		if _action_left <= 0.0:
			var done := _current_action
			_current_action = ""
			action_finished.emit(done)


## Plays a clip once over the idle. Returns false if the clip doesn't exist.
func play_action(clip: String) -> bool:
	if tree == null or not tree.has_animation(clip):
		return false
	_action_node.animation = clip
	tree.set("parameters/Shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_current_action = clip
	_action_left = tree.get_animation(clip).length
	return true


func play_random_action() -> String:
	if action_names.is_empty():
		return ""
	var clip := action_names[_rng.randi() % action_names.size()]
	play_action(clip)
	return clip


func is_busy() -> bool:
	return not _current_action.is_empty()


func _build_tree(lib: AnimationLibrary) -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	rig.add_child(tree)   # root_node ".." = the robot, which is what the tracks expect
	tree.add_animation_library("", lib)

	var bt := AnimationNodeBlendTree.new()
	# Idle: two slots, so the next idle can fade in while the last fades out.
	var idle := AnimationNodeTransition.new()
	idle.xfade_time = idle_crossfade
	idle.input_count = 2
	idle.set_input_name(0, "a")
	idle.set_input_name(1, "b")
	for i in 2:
		var n := AnimationNodeAnimation.new()
		n.animation = idle_names[0] if idle_names.size() > 0 else &""
		_idle_nodes.append(n)
	bt.add_node("IdleA", _idle_nodes[0])
	bt.add_node("IdleB", _idle_nodes[1])
	bt.add_node("Idle", idle)
	bt.connect_node("Idle", 0, "IdleA")
	bt.connect_node("Idle", 1, "IdleB")

	_action_node = AnimationNodeAnimation.new()
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = action_fade_in
	shot.fadeout_time = action_fade_out
	bt.add_node("Action", _action_node)
	bt.add_node("Shot", shot)
	bt.connect_node("Shot", 0, "Idle")
	bt.connect_node("Shot", 1, "Action")
	bt.connect_node("output", 0, "Shot")

	tree.tree_root = bt
	tree.active = true
	if idle_names.size() > 0:
		_idle_left = tree.get_animation(idle_names[0]).length


# Fades to a random idle (a different one when there's a choice) in the
# other slot.
func _next_idle() -> void:
	var choice := idle_names[0]
	if idle_names.size() > 1:
		var current := _idle_nodes[_idle_slot].animation
		while choice == current:
			choice = idle_names[_rng.randi() % idle_names.size()]
	_idle_slot = 1 - _idle_slot
	_idle_nodes[_idle_slot].animation = choice
	tree.set("parameters/Idle/transition_request", "a" if _idle_slot == 0 else "b")
	_idle_left = tree.get_animation(choice).length

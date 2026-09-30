# Finds robots. A robot is any folder res://robots/<id>/ that contains
# <id>.tscn whose root has a RobotRig script. Add a robot by adding a folder;
# nothing else needs registering.
class_name RobotLibrary
extends RefCounted

const ROBOTS_DIR := "res://robots"
const ANIMATIONS_DIR := "res://animations"

## Where baked clips go. Tests point this somewhere else so they never
## touch your real animation libraries.
static var animations_dir := ANIMATIONS_DIR


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for dir in DirAccess.get_directories_at(ROBOTS_DIR):
		if ResourceLoader.exists(scene_path(dir)):
			out.append(dir)
	return out


## (A numbered unit, "tinker2", uses its model's scene and clips.)
static func scene_path(id: String) -> String:
	id = RobotTraits.model_of(id)
	return "%s/%s/%s.tscn" % [ROBOTS_DIR, id, id]


static func instantiate(id: String) -> RobotRig:
	var scene := load(scene_path(id)) as PackedScene
	if scene == null:
		push_error("No robot scene at %s" % scene_path(id))
		return null
	var node := scene.instantiate()
	if not node is RobotRig:
		push_error("%s's root has no RobotRig script" % scene_path(id))
		node.free()
		return null
	return node


# Where a robot's baked clips live.
static func animation_dir(id: String) -> String:
	return "%s/%s" % [animations_dir, RobotTraits.model_of(id)]


# The AnimationLibrary that collects all of a robot's clips.
static func library_path(id: String) -> String:
	return "%s/%s_library.tres" % [animation_dir(id), RobotTraits.model_of(id)]


static func display_name(id: String) -> String:
	var rig := instantiate(id)
	if rig == null:
		return id
	var n := rig.profile.display_name if rig.profile else id
	rig.free()
	return n

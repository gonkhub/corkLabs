# Bakes a take into a robot animation:
#   raw take -> TakeCleanup -> robot rig (step by step) -> Animation tracks
#
# The result is an ordinary Godot Animation of the robot's joint nodes, so
# AnimationPlayer / AnimationTree use it like any other clip. Takes are the
# source of truth: bake again whenever a robot or its profile changes.
class_name Baker
extends RefCounted

## Cleanup works at this rate before the rig samples it at the clip's fps.
const CLEAN_RATE := 90.0


# Returns {"animation": Animation, "report": Dictionary}.
static func bake(take: PerformanceTake, rig: RobotRig, recipe: CleanupRecipe = null) -> Dictionary:
	if recipe == null:
		recipe = take.recipe if take.recipe else CleanupRecipe.new()
	var cleaned := TakeCleanup.run(take, recipe, CLEAN_RATE)
	var clean: PerformanceTake = cleaned.take
	var report: Dictionary = cleaned.report

	var fps := float(recipe.fps)
	var dt := 1.0 / fps
	var retime := rig.profile.retime if rig.profile else 1.0
	# A looping clip's last frame flows into its first, so its length is one
	# frame longer than its last sample.
	var period := clean.duration() + (1.0 / CLEAN_RATE if recipe.loop else 0.0)
	var count := maxi(2, int(round(period * fps)) + (0 if recipe.loop else 1))

	rig.begin(take.eye_height)
	if recipe.loop:
		# Warm-up lap: springs end the lap in the state they start the next
		# one, so the baked loop has no pop at the seam.
		for i in count:
			rig.drive(clean.sample(i * dt), dt)

	var nodes := rig.baked_nodes()
	var props := rig.baked_properties()
	var pos := []
	var rot := []
	var scl := []
	var vals := []
	for n in nodes:
		pos.append([])
		rot.append([])
		scl.append([])
	for p in props:
		vals.append([])

	for i in count:
		rig.drive(clean.sample(minf(i * dt, clean.duration())), dt)
		for k in nodes.size():
			var node := nodes[k]
			pos[k].append(node.position)
			# q and -q are the same rotation; keep neighbouring keys on the
			# same side so playback never spins the long way round.
			var q := node.quaternion
			if not rot[k].is_empty() and (rot[k].back() as Quaternion).dot(q) < 0.0:
				q = -q
			rot[k].append(q)
			scl[k].append(node.scale)
		for k in props.size():
			vals[k].append(props[k][0].get(props[k][1]))

	var anim := Animation.new()
	anim.length = (count - (0 if recipe.loop else 1)) * dt * retime
	anim.loop_mode = Animation.LOOP_LINEAR if recipe.loop else Animation.LOOP_NONE
	anim.step = dt * retime

	var tracks := 0
	for k in nodes.size():
		var path := node_path(rig, nodes[k])
		tracks += _add_track(anim, Animation.TYPE_POSITION_3D, path, pos[k], dt * retime)
		tracks += _add_track(anim, Animation.TYPE_ROTATION_3D, path, rot[k], dt * retime)
		tracks += _add_track(anim, Animation.TYPE_SCALE_3D, path, scl[k], dt * retime)
	for k in props.size():
		var path := "%s:%s" % [node_path(rig, props[k][0]), props[k][1]]
		tracks += _add_track(anim, Animation.TYPE_VALUE, path, vals[k], dt * retime)

	report["frames"] = count
	report["fps"] = fps
	report["length"] = anim.length
	report["tracks"] = tracks
	report["loop"] = recipe.loop
	return {"animation": anim, "report": report}


# Bakes a take for a robot and saves the clip into that robot's library.
# Returns {"ok": bool, "clip": String, "path": String, "report": Dictionary}.
static func bake_to_library(take: PerformanceTake, take_path: String, robot_id: String) -> Dictionary:
	var rig := RobotLibrary.instantiate(robot_id)
	if rig == null:
		return {"ok": false, "clip": "", "path": "", "report": {"notes": ["unknown robot '%s'" % robot_id]}}
	var result := bake(take, rig, null)
	rig.free()

	var clip := clip_name_for(take, take_path)
	var dir := RobotLibrary.animation_dir(robot_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var anim_path := "%s/%s.res" % [dir, clip]
	var anim: Animation = result.animation
	anim.resource_name = clip
	var err := ResourceSaver.save(anim, anim_path)
	if err != OK:
		return {"ok": false, "clip": clip, "path": anim_path, "report": result.report}

	# Point the robot's AnimationLibrary at the saved clip (a reference, so
	# the library file stays small and readable).
	var lib_path := RobotLibrary.library_path(robot_id)
	var lib: AnimationLibrary = null
	if ResourceLoader.exists(lib_path):
		lib = ResourceLoader.load(lib_path, "", ResourceLoader.CACHE_MODE_REPLACE) as AnimationLibrary
	if lib == null:
		lib = AnimationLibrary.new()
	if lib.has_animation(clip):
		lib.remove_animation(clip)
	lib.add_animation(clip, ResourceLoader.load(anim_path, "", ResourceLoader.CACHE_MODE_REPLACE))
	ResourceSaver.save(lib, lib_path)
	return {"ok": true, "clip": clip, "path": anim_path, "report": result.report}


static func clip_name_for(take: PerformanceTake, take_path: String) -> String:
	var n := take.clip_name.strip_edges() if take.clip_name else ""
	if n.is_empty():
		n = take_path.get_file().get_basename()
	return n.validate_filename().replace(" ", "_")


# Path from the rig root to a node, e.g. "Core/ArmL/Wrist".
static func node_path(rig: Node, node: Node) -> String:
	var parts := PackedStringArray()
	var n := node
	while n != null and n != rig:
		parts.insert(0, n.name)
		n = n.get_parent()
	return "/".join(parts)


# Adds one track; a channel that never changes gets a single key.
static func _add_track(anim: Animation, type: int, path: String, values: Array, dt: float) -> int:
	if values.is_empty():
		return 0
	var constant := true
	for v in values:
		if not _approx(v, values[0]):
			constant = false
			break
	var idx := anim.add_track(type)
	anim.track_set_path(idx, NodePath(path))
	if type == Animation.TYPE_ROTATION_3D:
		anim.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
	var keys := 1 if constant else values.size()
	for i in keys:
		var t := i * dt
		match type:
			Animation.TYPE_POSITION_3D:
				anim.position_track_insert_key(idx, t, values[i])
			Animation.TYPE_ROTATION_3D:
				anim.rotation_track_insert_key(idx, t, values[i])
			Animation.TYPE_SCALE_3D:
				anim.scale_track_insert_key(idx, t, values[i])
			_:
				anim.track_insert_key(idx, t, values[i])
	return 1


static func _approx(a: Variant, b: Variant) -> bool:
	if a is Vector3:
		return (a as Vector3).distance_squared_to(b) < 1e-10
	if a is Quaternion:
		return absf((a as Quaternion).dot(b)) > 0.9999999
	if a is float:
		return absf(a - b) < 1e-6
	return a == b

# Finds, loads and saves takes under res://takes/ (sub-folders allowed, e.g.
# res://takes/demo/ or res://takes/scene_03/).
class_name TakeStore
extends RefCounted

const TAKES_DIR := "res://takes"

## Where takes are read and written. Tests point this somewhere else so
## they never touch your real takes.
static var takes_dir := TAKES_DIR


# Every take file, sorted by path (timestamps sort oldest -> newest).
static func list(dir := "") -> PackedStringArray:
	if dir.is_empty():
		dir = takes_dir
	var out := PackedStringArray()
	_collect(dir, out)
	out.sort()
	return out


static func _collect(dir: String, out: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".res") or f.ends_with(".tres"):
			var path := dir.path_join(f)
			# Only count files that really are takes.
			if ResourceLoader.exists(path) and _is_take(path):
				out.append(path)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)


static func _is_take(path: String) -> bool:
	var r := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return r is PerformanceTake


static func load_take(path: String) -> PerformanceTake:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as PerformanceTake


static func save(take: PerformanceTake, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	return ResourceSaver.save(take, path)


# A new timestamped path, e.g. res://takes/take_2026-09-29T14-05-33.res
static func new_path(sub_dir := "") -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var dir := takes_dir if sub_dir.is_empty() else takes_dir.path_join(sub_dir)
	var path := dir.path_join("take_%s.res" % stamp)
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("take_%s_%d.res" % [stamp, n])
		n += 1
	return path


# One line describing a bake report, for printing.
static func describe_report(r: Dictionary) -> String:
	var bits := PackedStringArray()
	bits.append("%.2f s" % r.get("length", 0.0))
	bits.append("%d fps" % int(r.get("fps", 0)))
	if r.get("loop", false):
		bits.append("loop at %.2f s" % r.get("loop_point", -1.0))
	if int(r.get("gaps_repaired", 0)) > 0:
		bits.append("%d gaps repaired" % r.gaps_repaired)
	for g in r.get("gaps_left", []):
		bits.append("UNREPAIRED GAP " + str(g))
	for n in r.get("notes", []):
		bits.append(str(n))
	return ", ".join(bits)

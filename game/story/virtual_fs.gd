# The corkLabs OS file system: a folder tree of plain text files under
# res://game/story/fs/, shown to the player as /home, /corp, /opt... in the
# Terminal (ls, cd, cat) and the Files app. The facility is old; so is its
# OS. Former supervisors left their home folders behind.
#
# Add a file = drop a .txt in a folder. A file may start with header lines
# ("#! key: value"), which the player never sees:
#
#   #! name: .backdoor       the name the player sees (default: the file name).
#                            A name starting with "." is hidden (ls -a shows it)
#   #! date: 1987-03-02      shown by ls -l
#   #! owner: rmarrow        shown by ls -l (default: the folder's owner, or root)
#   #! learn: cmd:talk secret:x flag   knowledge keys learned on first read
#   #! restricted: 4         reading it is a policy violation (suspicion +4, first read only)
#   #! password: lantern     encrypted until "decrypt <file> lantern"
#   #! requires: flag        only exists once this condition holds (Knowledge.check)
#   #! gone_if: flag         disappears once this holds ("purged:dokafor")
#   #! shift: 2              only exists from this shift on
#   #! minutes: 5            reading time, x READ_SCALE (default: 1 facility minute per 5 lines, at least 5)
#   #! exec: nightrun        an executable: "run <name>" / double-click starts this app
#   #! access: dokafor       (folders) only these accounts may open it (the
#                            maintenance account opens everything); others see
#                            it's there and get "Permission denied"
#
# A folder can hold a _dir.txt with the same headers (requires, gone_if, shift,
# restricted, owner): it applies to the folder itself (restricted: entering
# it is the violation).
class_name VirtualFS
extends RefCounted

const ROOT := "res://game/story/fs"
const HOME := "/home/supervisor"
const DIR_META := "_dir.txt"

## vpath -> {"path", "name", "dir": bool, "parent", "meta": {}, "body": String}
var entries := {}

static var _shared: VirtualFS


static func shared() -> VirtualFS:
	if _shared == null:
		_shared = VirtualFS.new()
		_shared.load_tree()
	return _shared


func load_tree(root := ROOT) -> void:
	entries = {"/": {"path": "/", "name": "/", "dir": true, "parent": "", "meta": {"owner": "root"}, "body": ""}}
	_scan(root, "/")


func _scan(real_dir: String, vdir: String) -> void:
	var d := DirAccess.open(real_dir)
	if d == null:
		push_warning("VirtualFS: can't open %s" % real_dir)
		return
	d.include_hidden = true
	var parent: Dictionary = entries[vdir]
	var names := d.get_files()
	if names.has(DIR_META):
		var parsed := parse(FileAccess.get_file_as_string(real_dir.path_join(DIR_META)))
		parent.meta.merge(parsed.meta, true)
	for f in names:
		if f == DIR_META or not f.ends_with(".txt"):
			continue
		var parsed := parse(FileAccess.get_file_as_string(real_dir.path_join(f)))
		var name: String = parsed.meta.get("name", f)
		var vp := _join(vdir, name)
		if not parsed.meta.has("owner"):
			parsed.meta.owner = parent.meta.get("owner", "root")
		entries[vp] = {"path": vp, "name": name, "dir": false, "parent": vdir, "meta": parsed.meta, "body": parsed.body}
	for sub in d.get_directories():
		var vp := _join(vdir, sub)
		entries[vp] = {"path": vp, "name": sub, "dir": true, "parent": vdir, "meta": {"owner": parent.meta.get("owner", "root")}, "body": ""}
		_scan(real_dir.path_join(sub), vp)


## Splits "#! key: value" headers from the text.
static func parse(text: String) -> Dictionary:
	var meta := {}
	var lines := text.replace("\r", "").split("\n")
	var i := 0
	while i < lines.size() and lines[i].begins_with("#!"):
		var kv := lines[i].substr(2).split(":", true, 1)
		if kv.size() == 2:
			meta[kv[0].strip_edges()] = kv[1].strip_edges()
		elif not kv[0].strip_edges().is_empty():
			meta[kv[0].strip_edges()] = "yes"
		i += 1
	return {"meta": meta, "body": "\n".join(lines.slice(i)).strip_edges(false, true)}


## Resolves `path` against `cwd`: absolute, relative, ~, . and ..
static func normalize(cwd: String, path: String) -> String:
	var p := path.strip_edges()
	if p.is_empty():
		return cwd
	if p == "~" or p.begins_with("~/"):
		p = HOME + p.substr(1)
	elif not p.begins_with("/"):
		p = cwd.trim_suffix("/") + "/" + p
	var out: Array[String] = []
	for part in p.split("/", false):
		if part == "." or part.is_empty():
			continue
		if part == "..":
			if not out.is_empty():
				out.pop_back()
			continue
		out.append(part)
	return "/" + "/".join(out)


func get_entry(vpath: String) -> Dictionary:
	return entries.get(vpath, {})


## Does this entry exist for this supervisor right now? (requires, gone_if,
## shift; every folder above it must exist too.)
func exists(vpath: String, knowledge: Knowledge, shift: int) -> bool:
	var e := get_entry(vpath)
	while not e.is_empty():
		if not _here(e, knowledge, shift):
			return false
		if e.parent.is_empty():
			return true
		e = get_entry(e.parent)
	return false


func _here(e: Dictionary, knowledge: Knowledge, shift: int) -> bool:
	var m: Dictionary = e.meta
	if m.has("shift") and shift < int(m.shift):
		return false
	if knowledge:
		if m.has("requires") and not knowledge.check(m.requires):
			return false
		if m.has("gone_if") and knowledge.check(m.gone_if):
			return false
	elif m.has("requires"):
		return false
	return true


## What's in a folder: folders first, then files, by name. Hidden entries
## ("." names) only with `show_hidden`.
func children(vdir: String, knowledge: Knowledge, shift: int, show_hidden := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for vp in entries:
		var e: Dictionary = entries[vp]
		if e.parent != vdir or vp == "/":
			continue
		if not show_hidden and str(e.name).begins_with("."):
			continue
		if _here(e, knowledge, shift):
			out.append(e)
	out.sort_custom(func(a, b): return [not a.dir, a.name] < [not b.dir, b.name])
	return out


## Every file (not folder) that exists now, for searches.
func all_files(knowledge: Knowledge, shift: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for vp in entries:
		if not entries[vp].dir and exists(vp, knowledge, shift):
			out.append(entries[vp])
	out.sort_custom(func(a, b): return a.path < b.path)
	return out


## Facility minutes to read a file. Reading properly takes a while: you're
## reading a dead colleague's notes on a terminal, not skimming.
const READ_SCALE := 3.0
const READ_MIN := 5.0


static func read_minutes(e: Dictionary) -> float:
	if e.meta.has("minutes"):
		return float(e.meta.minutes) * READ_SCALE
	return maxf(READ_MIN, ceilf(str(e.body).count("\n") / 5.0))


static func _join(vdir: String, name: String) -> String:
	return ("/" if vdir == "/" else vdir + "/") + name
